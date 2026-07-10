defmodule ControlKeel.MCP.Discovery do
  @moduledoc """
  MCP server discovery module for auto-discovering tools from external MCP servers.

  This module implements progressive discovery for MCP tools, allowing CK to query
  an MCP server's tools/list endpoint and return discovered tool schemas without
  requiring manual configuration.

  Currently supports HTTP-based MCP servers. Stdio discovery is intentionally
  unsupported by this module; use configured MCP clients for stdio servers.

  ## Security

  Outbound requests are subject to a default SSRF allowlist policy that blocks
  loopback, link-local, and RFC1918 private addresses. Operators can opt-in to
  internal targets by setting `:controlkeel, :mcp_discovery_allow_private` to
  `true` (e.g. for trusted in-cluster discovery).
  """

  require Logger

  alias ControlKeel.MCP.ToolSecurity

  @default_timeout 10_000
  @max_response_bytes 1_048_576

  @doc """
  Discover tools from an MCP server.

  ## Parameters
    - server_url: URL of the MCP server (e.g., "http://localhost:3001/mcp")
    - opts: Optional parameters
      - :timeout - Request timeout in milliseconds (default: 10_000)
      - :transport - Transport type (:stdio or :http, default: auto-detect from URL)
  """
  def discover(server_url, opts \\ []) do
    transport = Keyword.get(opts, :transport, detect_transport(server_url))
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case transport do
      :http ->
        with :ok <- check_url_safety(server_url) do
          discover_http(server_url, timeout)
        end

      :stdio ->
        discover_stdio(server_url, timeout)

      other ->
        {:error, {:unsupported_transport, other}}
    end
  end

  defp detect_transport(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        :http

      String.starts_with?(url, "stdio://") or String.starts_with?(url, "/") ->
        :stdio

      true ->
        :http
    end
  end

  # Default-deny SSRF guard for outbound discovery.
  defp check_url_safety(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if private_or_loopback?(host) and not allow_private_targets?() do
          {:error, {:blocked_target, host}}
        else
          :ok
        end

      _ ->
        {:error, {:invalid_url, url}}
    end
  end

  defp allow_private_targets? do
    Application.get_env(:controlkeel, :mcp_discovery_allow_private, false) == true
  end

  defp private_or_loopback?(host) do
    host_l = String.downcase(host)

    cond do
      host_l in ["localhost", "ip6-localhost", "ip6-loopback"] -> true
      String.ends_with?(host_l, ".localhost") -> true
      match_ipv4_private?(host_l) -> true
      # IPv6 loopback / link-local / unique-local
      host_l in ["::1", "[::1]"] -> true
      String.starts_with?(host_l, "fe80:") or String.starts_with?(host_l, "[fe80:") -> true
      String.starts_with?(host_l, "fc") or String.starts_with?(host_l, "[fc") -> true
      String.starts_with?(host_l, "fd") or String.starts_with?(host_l, "[fd") -> true
      true -> false
    end
  end

  defp match_ipv4_private?(host) do
    case :inet.parse_ipv4_address(String.to_charlist(host)) do
      {:ok, {127, _, _, _}} -> true
      {:ok, {10, _, _, _}} -> true
      {:ok, {192, 168, _, _}} -> true
      {:ok, {172, b, _, _}} when b >= 16 and b <= 31 -> true
      # AWS/GCP/Azure instance metadata
      {:ok, {169, 254, _, _}} -> true
      {:ok, {0, 0, 0, 0}} -> true
      _ -> false
    end
  end

  defp discover_http(server_url, timeout) do
    request_body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/list",
      "params" => %{}
    }

    url = normalize_http_url(server_url)

    case Req.post(url,
           json: request_body,
           headers: [{"accept", "application/json"}],
           receive_timeout: timeout,
           connect_options: [timeout: min(timeout, 5_000)],
           redirect: false,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case enforce_response_size(body) do
          :ok -> parse_tools_response(body, server_url, :http)
          {:error, _} = err -> err
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_request_failed, reason}}
    end
  end

  defp enforce_response_size(body) when is_binary(body) do
    if byte_size(body) > @max_response_bytes do
      {:error, {:response_too_large, byte_size(body)}}
    else
      :ok
    end
  end

  defp enforce_response_size(body) when is_list(body) do
    enforce_response_size(IO.iodata_to_binary(body))
  rescue
    _ -> {:error, {:response_too_large, :unknown}}
  end

  defp enforce_response_size(_decoded_json), do: :ok

  defp normalize_http_url(url) do
    case URI.parse(url) do
      %{path: nil} -> url <> "/"
      %{path: ""} -> url <> "/"
      _ -> url
    end
  end

  defp discover_stdio(_server_path, _timeout) do
    {:error,
     {:stdio_discovery_unsupported,
      "Stdio MCP discovery is not supported. Use configured MCP clients (e.g. controlkeel attach <host>) for stdio servers."}}
  end

  defp parse_tools_response(%{"result" => %{"tools" => tools}}, server_url, transport)
       when is_list(tools) do
    normalized_tools = normalize_tools(tools)
    security = ToolSecurity.scan_tools(normalized_tools)

    {:ok,
     %{
       server_url: server_url,
       transport: transport,
       tools: normalized_tools,
       total: length(tools),
       trust_level: security["trust_level"],
       security: security
     }}
  end

  defp parse_tools_response(%{"error" => error}, _server_url, _transport),
    do: {:error, {:mcp_error, error}}

  defp parse_tools_response(decoded, _server_url, _transport) when is_map(decoded),
    do: {:error, {:unexpected_response, decoded}}

  defp parse_tools_response(body, server_url, transport) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"result" => %{"tools" => tools}}} when is_list(tools) ->
        normalized_tools = normalize_tools(tools)
        security = ToolSecurity.scan_tools(normalized_tools)

        {:ok,
         %{
           server_url: server_url,
           transport: transport,
           tools: normalized_tools,
           total: length(tools),
           trust_level: security["trust_level"],
           security: security
         }}

      {:ok, %{"error" => error}} ->
        {:error, {:mcp_error, error}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, {:json_decode_failed, reason}}
    end
  end

  defp normalize_tools(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      normalized = %{
        "name" => Map.get(tool, "name"),
        "description" => Map.get(tool, "description"),
        "input_schema" => Map.get(tool, "inputSchema", %{}),
        "original" => tool
      }

      Map.put(normalized, "security", ToolSecurity.scan_tool(normalized))
    end)
  end
end
