defmodule ControlKeelWeb.ObservabilityControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Mission.SessionEvent
  alias ControlKeel.Platform
  alias ControlKeel.Repo

  describe "GET /observability/sessions/:id/export.json (local mode)" do
    test "exports the session envelope without authentication", %{conn: conn} do
      session = session_fixture()

      conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

      body = json_response(conn, :ok)
      assert body["integrity"]["session_id"] == session.id
      assert is_binary(body["integrity"]["payload_sha256"])
    end

    test "returns 404 for an unknown session", %{conn: conn} do
      conn = get(conn, "/observability/sessions/999999/export.json")
      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end
  end

  describe "GET /observability/sessions/:id/export.json (cloud mode)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    setup %{conn: conn} do
      {:ok, org} =
        Accounts.create_org(%{name: "Acme", slug: "acme-#{System.unique_integer([:positive])}"})

      {:ok, user} =
        Accounts.create_user(%{email: "acme-#{System.unique_integer([:positive])}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})
      session = session_fixture(%{workspace: workspace})

      conn = init_test_session(conn, %{current_user_id: user.id, current_org_id: org.id})

      {:ok, conn: conn, org: org, user: user, workspace: workspace, session: session}
    end

    test "unauthenticated requests are rejected with 401", %{session: session} do
      conn = build_conn()
      conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

      assert json_response(conn, :unauthorized) == %{"error" => "sign in required"}
    end

    test "authenticated requests for own-org sessions export the envelope", %{
      conn: conn,
      session: session
    } do
      conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

      body = json_response(conn, :ok)
      assert body["integrity"]["session_id"] == session.id
    end

    test "sessions from another org are not exportable", %{conn: conn} do
      {:ok, outsider_org} =
        Accounts.create_org(%{
          name: "Outsider",
          slug: "outsider-#{System.unique_integer([:positive])}"
        })

      outsider_workspace = workspace_fixture(%{org_id: outsider_org.id})
      outsider_session = session_fixture(%{workspace: outsider_workspace})

      conn = get(conn, ~p"/observability/sessions/#{outsider_session.id}/export.json")

      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end

    test "unknown sessions return 404 for authenticated users", %{conn: conn} do
      conn = get(conn, "/observability/sessions/999999/export.json")
      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end
  end

  describe "GET /observability/sessions/:id/audit-log/:format (local mode)" do
    test "downloads a JSON audit log byte-identical to the persisted export", %{conn: conn} do
      session = session_fixture()
      _finding = finding_fixture(%{session: session})

      conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/json")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      assert get_resp_header(conn, "content-disposition") |> hd() ==
               "attachment; filename=\"audit-log-#{session.id}.json\""

      body = response(conn, 200)
      assert body =~ "\"audit_log\""

      export = Platform.list_audit_exports(session.id, 1) |> List.first()
      assert export.format == "json"
      assert export.checksum == checksum(body)
    end

    test "downloads a CSV audit log with attachment disposition", %{conn: conn} do
      session = session_fixture()

      conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/csv")

      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") |> hd() ==
               "attachment; filename=\"audit-log-#{session.id}.csv\""

      csv = response(conn, 200)
      assert String.starts_with?(csv, "session_id,")
    end

    test "downloads a PDF audit log when a renderer is available", %{conn: conn} do
      setup_fake_pdf_renderer()
      session = session_fixture()

      conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/pdf")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert response(conn, 200) =~ "%PDF-FAKE"
    end

    test "records an audit.exported timeline event with the checksum", %{conn: conn} do
      session = session_fixture()

      conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/json")
      assert response(conn, 200)

      event =
        Repo.get_by(SessionEvent, session_id: session.id, event_type: "audit.exported")

      assert event.actor == "web"
      assert event.payload["format"] == "json"
      assert is_binary(event.payload["checksum"])
    end

    test "rejects unsupported formats with 400", %{conn: conn} do
      session = session_fixture()

      conn = get(conn, "/observability/sessions/#{session.id}/audit-log/xml")

      assert json_response(conn, :bad_request) == %{"error" => "format must be json, csv, or pdf"}
    end

    test "returns 404 for an unknown session", %{conn: conn} do
      conn = get(conn, "/observability/sessions/999999/audit-log/json")
      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end
  end

  describe "GET /observability/sessions/:id/audit-log/:format (cloud mode)" do
    setup :cloud_mode

    setup %{conn: conn} do
      {:ok, org} =
        Accounts.create_org(%{
          name: "Audit Co",
          slug: "audit-#{System.unique_integer([:positive])}"
        })

      {:ok, user} =
        Accounts.create_user(%{email: "audit-#{System.unique_integer([:positive])}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})
      session = session_fixture(%{workspace: workspace})

      conn = init_test_session(conn, %{current_user_id: user.id, current_org_id: org.id})

      {:ok, conn: conn, session: session}
    end

    test "own-org operators can download the audit log", %{conn: conn, session: session} do
      conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/json")
      assert response(conn, 200) =~ "\"audit_log\""
    end

    test "unauthenticated requests are rejected with 401", %{session: session} do
      conn = build_conn()
      conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/json")

      assert json_response(conn, :unauthorized) == %{"error" => "sign in required"}
    end

    test "sessions from another org are not exportable", %{conn: conn} do
      {:ok, outsider_org} =
        Accounts.create_org(%{
          name: "Outsider Audit",
          slug: "outsider-audit-#{System.unique_integer([:positive])}"
        })

      outsider_workspace = workspace_fixture(%{org_id: outsider_org.id})
      outsider_session = session_fixture(%{workspace: outsider_workspace})

      conn = get(conn, ~p"/observability/sessions/#{outsider_session.id}/audit-log/json")

      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end
  end

  defp cloud_mode(_context) do
    original = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original)
      end
    end)

    :ok
  end

  defp setup_fake_pdf_renderer do
    previous_renderer = Application.get_env(:controlkeel, :pdf_renderer)
    Application.put_env(:controlkeel, :pdf_renderer, ControlKeel.TestSupport.FakePdfRenderer)

    on_exit(fn ->
      if previous_renderer do
        Application.put_env(:controlkeel, :pdf_renderer, previous_renderer)
      else
        Application.delete_env(:controlkeel, :pdf_renderer)
      end
    end)
  end

  defp checksum(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end
