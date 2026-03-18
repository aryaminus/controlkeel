defmodule ControlKeel.Notifications.Webhook do
  @moduledoc false

  @doc """
  Fires a webhook POST for a finding when `CONTROLKEEL_WEBHOOK_URL` is set.
  Only fires for critical and high severity findings.
  Non-blocking — spawns a task and returns immediately.
  """
  def notify(finding, session \\ nil) do
    case webhook_url() do
      nil ->
        :ok

      url ->
        if finding.severity in ["critical", "high"] do
          Task.start(fn -> post(url, payload(finding, session)) end)
        end

        :ok
    end
  end

  defp post(url, body) do
    Req.post(
      url: url,
      json: body,
      headers: [{"content-type", "application/json"}, {"user-agent", "ControlKeel/#{version()}"}],
      receive_timeout: 5_000
    )
  rescue
    _ -> :error
  end

  defp payload(finding, session) do
    %{
      "event" => "finding.blocked",
      "finding" => %{
        "id" => finding.id,
        "rule_id" => finding.rule_id,
        "severity" => finding.severity,
        "category" => finding.category,
        "plain_message" => finding.plain_message,
        "status" => Map.get(finding, :status, "open"),
        "decision" => Map.get(finding, :decision, "block")
      },
      "session" =>
        if session do
          %{
            "id" => session.id,
            "title" => session.title,
            "risk_tier" => session.risk_tier
          }
        end,
      "dashboard_url" =>
        (if session, do: "#{base_url()}/missions/#{session.id}", else: "#{base_url()}/findings"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp webhook_url, do: Application.get_env(:controlkeel, :webhook_url)

  defp base_url do
    url_cfg =
      Application.get_env(:controlkeel, ControlKeelWeb.Endpoint, [])
      |> Keyword.get(:url, [])

    case url_cfg do
      [host: host, port: 443, scheme: "https"] -> "https://#{host}"
      [host: host, port: port, scheme: scheme] -> "#{scheme}://#{host}:#{port}"
      _ -> "http://localhost:4000"
    end
  rescue
    _ -> "http://localhost:4000"
  end

  defp version do
    Application.spec(:controlkeel, :vsn) |> to_string() |> then(&(&1 || "0.1.0"))
  end
end
