defmodule ControlKeelWeb.ProxyWebSock do
  @moduledoc false

  @behaviour WebSock

  alias ControlKeel.Proxy
  alias ControlKeel.Proxy.{Errors, Governor, Payload, WSClient}

  @impl true
  def init(state) do
    case WSClient.start_link(state.upstream_url, state.headers, self()) do
      {:ok, upstream_pid} ->
        {:ok, Map.put(state, :upstream_pid, upstream_pid)}

      {:error, reason} ->
        {:stop, reason, {1011, "Upstream realtime connection failed"}, state}
    end
  end

  @impl true
  def handle_in({payload, opcode: :text}, state) do
    case Jason.decode(payload) do
      {:ok, decoded} ->
        extracted = Payload.extract_ws_frame(decoded)

        case maybe_preflight(extracted, state) do
          {:ok, state} ->
            case WSClient.send_text(state.upstream_pid, payload) do
              :ok ->
                {:ok, maybe_track_usage(state, extracted)}

              {:error, reason} ->
                {:stop, reason, {1011, "Failed to relay upstream frame"}, state}
            end

          {:block, summary, state} ->
            stop_with_policy(summary, state)
        end

      {:error, _error} ->
        stop_with_policy("Realtime proxy expects JSON text frames.", state)
    end
  end

  def handle_in({_payload, opcode: _opcode}, state) do
    stop_with_policy("Realtime proxy only supports JSON text frames.", state)
  end

  @impl true
  def handle_info({:proxy_ws_upstream_connected, _pid}, state), do: {:ok, state}

  def handle_info({:proxy_ws_upstream_frame, payload}, state) do
    case Jason.decode(payload) do
      {:ok, decoded} ->
        extracted = Payload.extract_ws_frame(decoded)
        state = maybe_track_usage(state, extracted)

        if extracted.text != "" do
          case Governor.postflight(state.session, state.provider, extracted,
                 path: state.route,
                 kind: "text",
                 phase: "ws_delta",
                 timeout_ms: Proxy.timeout_ms()
               ) do
            {:ok, %{allowed: true}} ->
              {:push, {:text, payload}, state}

            {:ok, %{summary: summary}} ->
              state = commit_usage_once(state, "ws_blocked")
              stop_with_policy(summary, state)
          end
        else
          {:push, {:text, payload}, state}
        end

      {:error, _error} ->
        {:push, {:text, payload}, state}
    end
  end

  def handle_info({:proxy_ws_upstream_disconnect, _reason}, state) do
    state = commit_usage_once(state, "ws_disconnect")
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    _ = commit_usage_once(state, "ws_terminate")
    :ok
  end

  defp maybe_preflight(%{text: "", model: nil, max_output_tokens: nil}, state), do: {:ok, state}

  defp maybe_preflight(extracted, state) do
    case Governor.preflight(state.session, state.provider, state.upstream_path, extracted,
           path: state.route,
           kind: "text",
           timeout_ms: Proxy.timeout_ms()
         ) do
      {:ok, %{allowed: true} = preflight} ->
        {:ok,
         state
         |> Map.put(:preflight, budget_estimate(preflight))
         |> Map.put(:model, extracted.model || state.model)}

      {:ok, %{summary: summary}} ->
        {:block, summary, state}
    end
  end

  defp maybe_track_usage(state, %{usage: nil}), do: state

  defp maybe_track_usage(state, extracted) do
    state
    |> Map.put(:usage, extracted.usage)
    |> Map.put(:model, extracted.model || state.model)
  end

  defp stop_with_policy(summary, state) do
    {:stop, :normal, {1008, summary}, [{:text, Errors.websocket(summary)}], state}
  end

  defp commit_usage_once(%{committed?: true} = state, _phase), do: state

  defp commit_usage_once(state, phase) do
    _ =
      Governor.commit_usage(
        state.session,
        state.provider,
        Atom.to_string(state.provider) <> ":" <> state.upstream_path,
        state.preflight,
        state.usage,
        model: state.model,
        route: state.route,
        phase: phase
      )

    Map.put(state, :committed?, true)
  end

  defp budget_estimate(%{budget: {:ok, estimate}}), do: {:ok, estimate}
  defp budget_estimate(%{budget: other}), do: other
end
