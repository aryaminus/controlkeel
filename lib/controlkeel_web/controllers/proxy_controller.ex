defmodule ControlKeelWeb.ProxyController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Mission
  alias ControlKeel.Proxy
  alias ControlKeel.Proxy.{Errors, Governor, Payload, SSE}

  @hop_by_hop_headers ~w(connection content-length host transfer-encoding)

  def openai_responses(conn, params),
    do: handle_proxy(conn, params, :openai, :responses, "/v1/responses")

  def openai_chat_completions(conn, params),
    do: handle_proxy(conn, params, :openai, :chat_completions, "/v1/chat/completions")

  def openai_completions(conn, params),
    do: handle_proxy(conn, params, :openai, :completions, "/v1/completions")

  def openai_embeddings(conn, params),
    do: handle_proxy(conn, params, :openai, :embeddings, "/v1/embeddings")

  def openai_models(conn, params),
    do: handle_proxy_without_body(conn, params, :openai, :models, "/v1/models", :get)

  def anthropic_messages(conn, params),
    do: handle_proxy(conn, params, :anthropic, :messages, "/v1/messages")

  defp handle_proxy(conn, %{"proxy_token" => proxy_token}, provider, tool, upstream_path) do
    with {:ok, session} <- fetch_proxy_session(proxy_token),
         {:ok, raw_body, decoded_body} <- decode_body(conn),
         extracted <- Payload.extract_request(provider, tool, decoded_body),
         {:ok, preflight} <-
           Governor.preflight(session, provider, upstream_path, extracted,
             path: conn.request_path,
             kind: "text",
             timeout_ms: Proxy.timeout_ms()
           ) do
      if preflight.allowed do
        if extracted.stream? do
          proxy_stream(
            conn,
            session,
            provider,
            tool,
            upstream_path,
            raw_body,
            preflight,
            extracted
          )
        else
          proxy_json(
            conn,
            session,
            provider,
            tool,
            upstream_path,
            :post,
            raw_body,
            preflight,
            extracted
          )
        end
      else
        policy_error(conn, provider, preflight.summary)
      end
    else
      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"message" => "Proxy session not found"}})

      {:error, {:invalid_json, message}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => %{"message" => message}})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{"error" => %{"message" => inspect(reason)}})
    end
  end

  defp handle_proxy_without_body(
         conn,
         %{"proxy_token" => proxy_token},
         provider,
         tool,
         upstream_path,
         method
       ) do
    with {:ok, session} <- fetch_proxy_session(proxy_token),
         extracted <- Payload.extract_request(provider, tool, %{}),
         {:ok, preflight} <-
           Governor.preflight(session, provider, upstream_path, extracted,
             path: conn.request_path,
             kind: "text",
             timeout_ms: Proxy.timeout_ms()
           ) do
      if preflight.allowed do
        proxy_json(
          conn,
          session,
          provider,
          tool,
          upstream_path,
          method,
          nil,
          preflight,
          extracted
        )
      else
        policy_error(conn, provider, preflight.summary)
      end
    else
      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"message" => "Proxy session not found"}})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{"error" => %{"message" => inspect(reason)}})
    end
  end

  defp proxy_json(
         conn,
         session,
         provider,
         tool,
         upstream_path,
         method,
         raw_body,
         preflight,
         extracted
       ) do
    started_at = System.monotonic_time(:millisecond)

    case Req.request(
           request_options(
             conn,
             method,
             upstream_url(provider, upstream_path),
             raw_body
           )
         ) do
      {:ok, %Req.Response{} = response} ->
        emit_upstream(provider, upstream_path, started_at, response.status)

        with {:ok, decoded_response} <- Jason.decode(response.body),
             response_payload <- Payload.extract_response(provider, tool, decoded_response),
             {:ok, postflight} <-
               Governor.postflight(session, provider, response_payload,
                 path: conn.request_path,
                 kind: "text",
                 phase: "response",
                 timeout_ms: Proxy.timeout_ms()
               ) do
          _ =
            Governor.commit_usage(
              session,
              provider,
              proxy_tool(provider, upstream_path),
              budget_estimate(preflight),
              response_payload.usage,
              model: extracted.model,
              route: conn.request_path
            )

          if postflight.allowed do
            conn
            |> maybe_put_json_content_type(response.headers)
            |> copy_response_headers(response.headers)
            |> resp(response.status, response.body)
          else
            policy_error(conn, provider, postflight.summary)
          end
        else
          {:error, _reason} ->
            _ =
              Governor.commit_usage(
                session,
                provider,
                proxy_tool(provider, upstream_path),
                budget_estimate(preflight),
                nil,
                route: conn.request_path
              )

            conn
            |> copy_response_headers(response.headers)
            |> resp(response.status, response.body)
        end

      {:error, reason} ->
        emit_upstream(provider, upstream_path, started_at, :error)

        conn
        |> put_status(:bad_gateway)
        |> json(%{"error" => %{"message" => Exception.message(reason)}})
    end
  end

  defp proxy_stream(conn, session, provider, tool, upstream_path, raw_body, preflight, extracted) do
    started_at = System.monotonic_time(:millisecond)

    case Req.request(
           request_options(
             conn,
             :post,
             upstream_url(provider, upstream_path),
             raw_body,
             into: :self
           )
         ) do
      {:ok, %Req.Response{} = response} ->
        emit_upstream(provider, upstream_path, started_at, response.status)

        conn =
          conn
          |> copy_response_headers(response.headers)
          |> send_chunked(response.status)

        stream_loop(
          conn,
          response,
          %{
            session: session,
            provider: provider,
            tool: tool,
            upstream_path: upstream_path,
            preflight: budget_estimate(preflight),
            model: extracted.model,
            parser: SSE.new(),
            usage: nil,
            route: conn.request_path
          }
        )

      {:error, reason} ->
        emit_upstream(provider, upstream_path, started_at, :error)

        conn
        |> put_status(:bad_gateway)
        |> json(%{"error" => %{"message" => Exception.message(reason)}})
    end
  end

  defp stream_loop(conn, response, state) do
    receive do
      message ->
        case Req.parse_message(response, message) do
          {:ok, chunks} ->
            case handle_chunks(conn, response, chunks, state) do
              {:continue, conn, state} -> stream_loop(conn, response, state)
              {:stop, conn, _state} -> conn
            end

          {:error, reason} ->
            Req.cancel_async_response(response)

            _ =
              Governor.commit_usage(
                state.session,
                state.provider,
                proxy_tool(state.provider, state.upstream_path),
                state.preflight,
                state.usage,
                model: state.model,
                route: state.route,
                phase: "stream_error"
              )

            case chunk(conn, Errors.sse(state.provider, Exception.message(reason))) do
              {:ok, conn} -> conn
              {:error, _reason} -> conn
            end

          :unknown ->
            stream_loop(conn, response, state)
        end
    after
      Proxy.timeout_ms() ->
        Req.cancel_async_response(response)

        _ =
          Governor.commit_usage(
            state.session,
            state.provider,
            proxy_tool(state.provider, state.upstream_path),
            state.preflight,
            state.usage,
            model: state.model,
            route: state.route,
            phase: "timeout"
          )

        conn
    end
  end

  defp handle_chunks(conn, response, chunks, state) do
    Enum.reduce_while(chunks, {conn, state}, fn
      {:data, data}, {conn, state} ->
        case handle_stream_chunk(conn, data, state) do
          {:ok, conn, state} ->
            {:cont, {conn, state}}

          {:halt, conn, state} ->
            Req.cancel_async_response(response)
            {:halt, {:stop, conn, state}}
        end

      {:trailers, _trailers}, {conn, state} ->
        {:cont, {conn, state}}

      :done, {conn, state} ->
        {events, parser} = SSE.flush(state.parser)

        case dispatch_events(conn, events, %{state | parser: parser}) do
          {:ok, conn, state} ->
            _ =
              Governor.commit_usage(
                state.session,
                state.provider,
                proxy_tool(state.provider, state.upstream_path),
                state.preflight,
                state.usage,
                model: state.model,
                route: state.route,
                phase: "stream_complete"
              )

            {:halt, {:stop, conn, state}}

          {:halt, conn, state} ->
            _ =
              Governor.commit_usage(
                state.session,
                state.provider,
                proxy_tool(state.provider, state.upstream_path),
                state.preflight,
                state.usage,
                model: state.model,
                route: state.route,
                phase: "stream_blocked"
              )

            {:halt, {:stop, conn, state}}
        end
    end)
    |> case do
      {:stop, conn, state} -> {:stop, conn, state}
      {conn, state} -> {:continue, conn, state}
    end
  end

  defp handle_stream_chunk(conn, data, state) do
    {events, parser} = SSE.push(state.parser, data)
    dispatch_events(conn, events, %{state | parser: parser})
  end

  defp dispatch_events(conn, events, state) do
    Enum.reduce_while(events, {:ok, conn, state}, fn event, {:ok, conn, state} ->
      payload = Payload.extract_sse_event(state.provider, state.tool, event)
      usage = payload.usage || state.usage

      if payload.text != "" do
        case Governor.postflight(state.session, state.provider, payload,
               path: state.route,
               kind: "text",
               phase: "stream_delta",
               timeout_ms: Proxy.timeout_ms()
             ) do
          {:ok, %{allowed: true}} ->
            case chunk(conn, event.raw) do
              {:ok, conn} -> {:cont, {:ok, conn, %{state | usage: usage}}}
              {:error, _reason} -> {:halt, {:halt, conn, %{state | usage: usage}}}
            end

          {:ok, %{summary: summary}} ->
            {:ok, conn} = chunk(conn, Errors.sse(state.provider, summary))

            _ =
              Governor.commit_usage(
                state.session,
                state.provider,
                proxy_tool(state.provider, state.upstream_path),
                state.preflight,
                usage,
                model: state.model,
                route: state.route,
                phase: "stream_blocked"
              )

            {:halt, {:halt, conn, %{state | usage: usage}}}
        end
      else
        case chunk(conn, event.raw) do
          {:ok, conn} -> {:cont, {:ok, conn, %{state | usage: usage}}}
          {:error, _reason} -> {:halt, {:halt, conn, %{state | usage: usage}}}
        end
      end
    end)
  end

  defp fetch_proxy_session(proxy_token) do
    case Mission.get_session_by_proxy_token(proxy_token) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  defp decode_body(conn) do
    raw_body = conn.private[:raw_body] || "{}"

    case Jason.decode(raw_body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, raw_body, decoded}
      {:ok, _decoded} -> {:error, {:invalid_json, "Proxy body must be a JSON object."}}
      {:error, error} -> {:error, {:invalid_json, "Invalid JSON: #{Exception.message(error)}"}}
    end
  end

  defp policy_error(conn, provider, summary) do
    conn
    |> put_status(:bad_request)
    |> json(Errors.http(provider, summary))
  end

  defp forwarded_headers(conn) do
    conn.req_headers
    |> Enum.reject(fn {key, _value} -> String.downcase(key) in @hop_by_hop_headers end)
  end

  defp copy_response_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, acc ->
      values = List.wrap(value)

      Enum.reduce(values, acc, fn header_value, acc ->
        if String.downcase(key) in @hop_by_hop_headers do
          acc
        else
          put_resp_header(acc, key, header_value)
        end
      end)
    end)
  end

  defp request_options(conn, method, url, raw_body, extra_opts \\ []) do
    opts =
      [
        method: method,
        url: url,
        headers: forwarded_headers(conn),
        decode_body: false,
        compressed: false,
        receive_timeout: Proxy.timeout_ms()
      ] ++ extra_opts

    if is_binary(raw_body), do: Keyword.put(opts, :body, raw_body), else: opts
  end

  defp upstream_url(:openai, path), do: Proxy.openai_upstream() <> path
  defp upstream_url(:anthropic, path), do: Proxy.anthropic_upstream() <> path

  defp maybe_put_json_content_type(conn, headers) do
    has_content_type? =
      Enum.any?(headers, fn {key, _value} -> String.downcase(key) == "content-type" end)

    if has_content_type?, do: conn, else: put_resp_content_type(conn, "application/json")
  end

  defp emit_upstream(provider, route, started_at, status) do
    duration_ms = System.monotonic_time(:millisecond) - started_at

    :telemetry.execute(
      [:controlkeel, :proxy, :upstream, :stop],
      %{duration_ms: duration_ms},
      %{provider: provider, route: route, status: status}
    )
  end

  defp budget_estimate(%{budget: {:ok, estimate}}), do: {:ok, estimate}
  defp budget_estimate(%{budget: other}), do: other

  defp proxy_tool(provider, upstream_path), do: Atom.to_string(provider) <> ":" <> upstream_path
end
