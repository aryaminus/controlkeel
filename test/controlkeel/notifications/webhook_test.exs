defmodule ControlKeel.Notifications.WebhookTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Notifications.Webhook

  describe "notify/2 — no webhook URL configured" do
    test "returns :ok immediately when CONTROLKEEL_WEBHOOK_URL is not set" do
      Application.put_env(:controlkeel, :webhook_url, nil)
      finding = finding_fixture(%{severity: "critical"})
      assert :ok = Webhook.notify(finding)
    end
  end

  describe "notify/2 — severity filtering" do
    setup do
      bypass = Bypass.open()
      url = "http://localhost:#{bypass.port}/webhook"
      Application.put_env(:controlkeel, :webhook_url, url)
      on_exit(fn -> Application.put_env(:controlkeel, :webhook_url, nil) end)
      {:ok, bypass: bypass}
    end

    test "fires webhook for critical severity finding", %{bypass: bypass} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(test_pid, {:webhook_called, payload})
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      finding = finding_fixture(%{severity: "critical", status: "blocked"})
      assert :ok = Webhook.notify(finding)

      assert_receive {:webhook_called, payload}, 1_000
      assert payload["event"] == "finding.blocked"
      assert payload["finding"]["severity"] == "critical"
      assert payload["finding"]["rule_id"] == finding.rule_id
      assert is_binary(payload["timestamp"])
    end

    test "fires webhook for high severity finding", %{bypass: bypass} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        send(test_pid, :webhook_called)
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      finding = finding_fixture(%{severity: "high"})
      assert :ok = Webhook.notify(finding)
      assert_receive :webhook_called, 1_000
    end

    test "does not fire webhook for medium severity", %{bypass: _bypass} do
      finding = finding_fixture(%{severity: "medium"})
      assert :ok = Webhook.notify(finding)
      # No bypass expectation — if it fires, bypass raises
      Process.sleep(50)
    end

    test "does not fire webhook for low severity", %{bypass: _bypass} do
      finding = finding_fixture(%{severity: "low"})
      assert :ok = Webhook.notify(finding)
      Process.sleep(50)
    end
  end

  describe "notify/2 — with session context" do
    setup do
      bypass = Bypass.open()
      url = "http://localhost:#{bypass.port}/hook"
      Application.put_env(:controlkeel, :webhook_url, url)
      on_exit(fn -> Application.put_env(:controlkeel, :webhook_url, nil) end)
      {:ok, bypass: bypass}
    end

    test "includes session data in payload when session provided", %{bypass: bypass} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      session = session_fixture()
      finding = finding_fixture(%{session: session, severity: "critical"})
      assert :ok = Webhook.notify(finding, session)

      assert_receive {:payload, payload}, 1_000
      assert payload["session"]["id"] == session.id
      assert payload["session"]["title"] == session.title
      assert is_binary(payload["dashboard_url"])
    end
  end
end
