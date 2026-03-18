defmodule ControlKeelWeb.MissionControlController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Mission
  alias ControlKeel.Proxy

  def show(conn, %{"id" => id}) do
    session = Mission.get_session_with_details!(id)
    brief = stringify_keys(session.execution_brief)

    render(conn, :show,
      session: session,
      workspace: session.workspace,
      brief: brief,
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      active_tasks: Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      proxy_urls: %{
        openai_responses: Proxy.url(session, :openai, "/v1/responses"),
        openai_chat: Proxy.url(session, :openai, "/v1/chat/completions"),
        openai_realtime: Proxy.realtime_url(session, :openai, "/v1/realtime"),
        anthropic_messages: Proxy.url(session, :anthropic, "/v1/messages")
      }
    )
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
