defmodule ControlKeel.Proxy do
  @moduledoc false

  @default_timeout_ms 15_000

  alias ControlKeel.Mission.Session
  alias ControlKeelWeb.Endpoint

  def openai_upstream do
    Application.get_env(:controlkeel, __MODULE__, [])
    |> Keyword.get(:openai_upstream, "https://api.openai.com")
  end

  def anthropic_upstream do
    Application.get_env(:controlkeel, __MODULE__, [])
    |> Keyword.get(:anthropic_upstream, "https://api.anthropic.com")
  end

  def timeout_ms do
    Application.get_env(:controlkeel, __MODULE__, [])
    |> Keyword.get(:timeout_ms, @default_timeout_ms)
  end

  def semgrep_bin do
    Application.get_env(:controlkeel, __MODULE__, [])
    |> Keyword.get(:semgrep_bin, System.get_env("CONTROLKEEL_SEMGREP_BIN") || "semgrep")
  end

  def url(%Session{proxy_token: proxy_token}, :openai, suffix) when is_binary(suffix) do
    base_url() <> "/proxy/openai/#{proxy_token}" <> suffix
  end

  def url(%Session{proxy_token: proxy_token}, :anthropic, suffix) when is_binary(suffix) do
    base_url() <> "/proxy/anthropic/#{proxy_token}" <> suffix
  end

  def realtime_url(%Session{} = session, provider, suffix) do
    session
    |> url(provider, suffix)
    |> String.replace_prefix("http://", "ws://")
    |> String.replace_prefix("https://", "wss://")
  end

  def websocket_upstream_url(provider, suffix, query_string \\ nil)

  def websocket_upstream_url(:openai, suffix, query_string) do
    openai_upstream()
    |> String.replace_prefix("http://", "ws://")
    |> String.replace_prefix("https://", "wss://")
    |> Kernel.<>(suffix)
    |> append_query(query_string)
  end

  def websocket_upstream_url(:anthropic, suffix, query_string) do
    anthropic_upstream()
    |> String.replace_prefix("http://", "ws://")
    |> String.replace_prefix("https://", "wss://")
    |> Kernel.<>(suffix)
    |> append_query(query_string)
  end

  def base_url do
    Endpoint.url()
  end

  defp append_query(url, nil), do: url
  defp append_query(url, ""), do: url
  defp append_query(url, query_string), do: url <> "?" <> query_string
end
