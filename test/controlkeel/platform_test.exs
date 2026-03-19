defmodule ControlKeel.PlatformTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Scanner.FastPath

  setup do
    previous_renderer = Application.get_env(:controlkeel, :pdf_renderer)
    Application.put_env(:controlkeel, :pdf_renderer, ControlKeel.TestSupport.FakePdfRenderer)

    on_exit(fn ->
      if previous_renderer do
        Application.put_env(:controlkeel, :pdf_renderer, previous_renderer)
      else
        Application.delete_env(:controlkeel, :pdf_renderer)
      end
    end)

    :ok
  end

  test "creates, authenticates, and rotates service accounts" do
    workspace = workspace_fixture()

    %{service_account: account, token: token} =
      service_account_fixture(%{workspace_id: workspace.id})

    assert {:ok, authed} = Platform.authenticate_service_account(token)
    assert authed.id == account.id
    assert Platform.service_account_has_scope?(authed, "admin")

    assert {:ok, %{service_account: rotated, token: rotated_token}} =
             Platform.rotate_service_account(account.id)

    assert rotated.id == account.id
    assert {:error, :unauthorized} = Platform.authenticate_service_account(token)
    assert {:ok, _authed} = Platform.authenticate_service_account(rotated_token)
  end

  test "applied workspace policy sets participate in fast path scanning" do
    session = session_fixture()
    policy_set = policy_set_fixture()

    assert {:ok, _assignment} =
             Platform.apply_policy_set(session.workspace_id, policy_set.id, %{"precedence" => 10})

    result =
      FastPath.scan(%{
        "session_id" => session.id,
        "content" => "PAYROLL_EXPORT = true",
        "path" => "lib/payroll/export.ex",
        "kind" => "code"
      })

    assert result.decision == "block"
    assert Enum.any?(result.findings, &(&1.rule_id == "workspace.no_payroll_exports"))
  end

  test "materializes task graph and supports claim/check/report flows" do
    session = session_fixture()

    _arch =
      task_fixture(%{
        session: session,
        status: "done",
        position: 1,
        metadata: %{"track" => "architecture"}
      })

    feature =
      task_fixture(%{
        session: session,
        status: "queued",
        position: 2,
        metadata: %{"track" => "feature"}
      })

    release =
      task_fixture(%{
        session: session,
        status: "queued",
        position: 3,
        metadata: %{"track" => "release"}
      })

    assert %{edges: edges} = Platform.ensure_session_graph(session.id)
    assert length(edges) == 3

    assert {:ok, graph} = Platform.execute_session(session.id)
    assert feature.id in graph.ready_task_ids
    refute release.id in graph.ready_task_ids

    %{service_account: account} =
      service_account_fixture(%{
        workspace_id: session.workspace_id,
        scopes: "tasks:claim,tasks:report"
      })

    assert {:ok, task_run} =
             Platform.claim_task(feature.id, account, %{"external_ref" => "ci-123"})

    assert task_run.status == "in_progress"

    assert {:ok, checks} =
             Platform.record_task_checks(feature.id, account, [
               %{"check_type" => "tests", "status" => "passed", "summary" => "All green"}
             ])

    assert length(checks) == 1

    assert {:ok, _task_run} =
             Platform.report_task(feature.id, account, %{
               "status" => "done",
               "output" => %{"artifact" => "build.tar.gz"}
             })

    assert Mission.get_task!(feature.id).status == "done"

    assert {:ok, graph} = Platform.execute_session(session.id)
    assert release.id in graph.ready_task_ids
  end

  test "delivers signed webhook events and records deliveries" do
    workspace = workspace_fixture()
    bypass = Bypass.open()
    test_pid = self()

    _webhook =
      webhook_fixture(%{
        workspace_id: workspace.id,
        url: "http://localhost:#{bypass.port}/hooks",
        subscribed_events: "task.completed"
      })

    Bypass.expect_once(bypass, "POST", "/hooks", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:webhook_payload, Jason.decode!(body),
         Plug.Conn.get_req_header(conn, "x-controlkeel-signature")}
      )

      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert :ok =
             Platform.emit_event(
               "task.completed",
               %{"workspace_id" => workspace.id, "session_id" => 1, "task_id" => 2},
               async: false
             )

    assert_receive {:webhook_payload, %{"task_id" => 2}, [signature]}, 1_000
    assert is_binary(signature)

    deliveries = Platform.list_deliveries(workspace.id)
    assert Enum.any?(deliveries, &(&1.event == "task.completed"))
  end

  test "exports audit logs and persists pdf export metadata" do
    session = session_fixture()
    _finding = finding_fixture(%{session: session})

    assert {:ok, %{export: json_export, payload: json_payload}} =
             Platform.export_audit_log(session.id, "json")

    assert json_export.format == "json"
    assert json_payload =~ "\"audit_log\""

    assert {:ok, %{export: csv_export, payload: csv_payload}} =
             Platform.export_audit_log(session.id, "csv")

    assert csv_export.format == "csv"
    assert csv_payload =~ "session_id,session_title"

    assert {:ok, %{export: pdf_export, payload: pdf_payload}} =
             Platform.export_audit_log(session.id, "pdf")

    assert pdf_export.format == "pdf"
    assert pdf_export.artifact_path_or_ref
    assert pdf_payload =~ "%PDF-FAKE"
  end
end
