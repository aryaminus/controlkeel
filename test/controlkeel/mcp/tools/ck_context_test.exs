defmodule ControlKeel.MCP.Tools.CkContextTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkContext
  alias ControlKeel.MCP.Tools.CkContextPack
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Intent

  import ControlKeel.IntentFixtures
  import ControlKeel.MissionFixtures

  test "returns workspace-wide precedent separate from session-scoped memory hits" do
    prior_session = session_fixture()
    workspace = Mission.get_session_with_workspace(prior_session.id).workspace
    session = session_fixture(%{workspace: workspace})

    {:ok, _finding} =
      Mission.create_finding(%{
        session_id: session.id,
        title: "SQL injection",
        severity: "critical",
        category: "security",
        rule_id: "security.sql_injection",
        plain_message: "Current active issue",
        status: "blocked",
        metadata: %{}
      })

    {:ok, _memory} =
      Memory.record(%{
        workspace_id: workspace.id,
        session_id: prior_session.id,
        record_type: "finding",
        title: "Finding approved: prior SQL exception",
        summary: "Prior same-rule exception was approved for generated test data.",
        body: "security.sql_injection (critical/approved)",
        tags: ["security.sql_injection", "approved", "finding"],
        source_type: "finding",
        source_id: "context-precedent-fixture",
        metadata: %{"rule_id" => "security.sql_injection", "status" => "approved"}
      })

    assert {:ok, result} = CkContext.call(%{"session_id" => session.id})
    assert Enum.any?(result["precedent"], &(&1["rule_id"] == "security.sql_injection"))
  end

  test "returns task assurance with verification and context integrity" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, _run} = Platform.claim_task(task.id)

    assert {:ok, _checks} =
             Platform.record_task_checks(task.id, nil, [
               %{
                 check_type: "validation",
                 status: "passed",
                 summary: "Validation passed",
                 payload: %{"source" => "fixture"}
               }
             ])

    assert {:ok, _updated} =
             Mission.attach_task_runtime_context(task.id, %{
               "partial_reads" => [%{"path" => "lib/huge.ex", "truncated_at_line" => 2000}]
             })

    assert {:ok, done_task} = Mission.update_task(Mission.get_task!(task.id), %{status: "done"})
    assert {:ok, _proof} = Mission.generate_proof_bundle(done_task.id)

    assert {:ok, result} =
             CkContext.call(%{"session_id" => session.id, "task_id" => done_task.id})

    assert result["current_task"]["assurance"]["check_summary"]["passed"] == 1
    assert result["current_task"]["assurance"]["context_integrity"]["status"] == "degraded"

    assert "task_checks" in result["current_task"]["assurance"]["verification"][
             "evidence_sources"
           ]
  end

  test "accepts session_id alias current in bound project" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-context-current-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    session = session_fixture()

    assert {:ok, _updated} =
             Mission.attach_session_runtime_context(session.id, %{"project_root" => tmp_dir})

    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "opencode",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    assert {:ok, result} = CkContext.call(%{"session_id" => "current", "project_root" => tmp_dir})
    assert result["session_id"] == session.id
  end

  test "accepts session_id alias active in bound project" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-context-active-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    session = session_fixture()

    assert {:ok, _binding} =
             ControlKeel.ProjectBinding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "opencode"
               },
               tmp_dir
             )

    assert {:ok, result} =
             CkContext.call(%{
               "session_id" => "active",
               "task_id" => "",
               "project_root" => tmp_dir
             })

    assert result["session_id"] == session.id
  end

  test "falls back to the active bound session when session_id is omitted" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-context-implicit-current-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    session = session_fixture()

    assert {:ok, _updated} =
             Mission.attach_session_runtime_context(session.id, %{"project_root" => tmp_dir})

    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "codex-cli",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    assert {:ok, result} = CkContext.call(%{"project_root" => tmp_dir})
    assert result["session_id"] == session.id
  end

  test "falls back to the active bound session when a host passes an unmapped session id" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-context-stale-current-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    session = session_fixture()

    assert {:ok, _updated} =
             Mission.attach_session_runtime_context(session.id, %{"project_root" => tmp_dir})

    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "codex-cli",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    assert {:ok, result} =
             CkContext.call(%{"session_id" => 999_999_999, "project_root" => tmp_dir})

    assert result["session_id"] == session.id
  end

  test "surfaces harness principles through boundary_summary" do
    session =
      session_fixture(%{execution_brief: execution_brief_fixture() |> Intent.to_brief_map()})

    task = task_fixture(%{session: session})

    assert {:ok, result} = CkContext.call(%{"session_id" => session.id, "task_id" => task.id})

    assert result["boundary_summary"]["harness_policy"]["context_contract"]["tool_schema_posture"] ==
             "versioned_and_additive"

    assert result["boundary_summary"]["harness_policy"]["observability"]["mutation_audit"] ==
             "proofs_findings_and_reviews"

    assert result["boundary_summary"]["harness_policy"]["provider_choice"]["model_portability"] ==
             "cross_provider_handoff_supported"
  end

  test "returns clear error when session_id current cannot resolve binding" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-context-current-missing-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    assert {:error, {:invalid_arguments, message}} =
             CkContext.call(%{"session_id" => "current", "project_root" => tmp_dir})

    assert message =~ "must be an integer"
    assert message =~ "bound project"
  end

  test "context pack accepts current and omitted session id from bound project" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-context-pack-current-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    session = session_fixture()
    task = task_fixture(%{session: session, status: "in_progress"})

    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "codex-cli",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    assert {:ok, current_result} =
             CkContextPack.call(%{
               "session_id" => "current",
               "project_root" => tmp_dir,
               "query" => "continuation"
             })

    assert current_result["session_id"] == session.id
    assert current_result["task_id"] == task.id

    assert Enum.any?(
             current_result["context_pack"]["citations"],
             &(&1["kind"] == "resume_packet")
           )

    assert {:ok, omitted_result} =
             CkContextPack.call(%{"project_root" => tmp_dir, "query" => "continuation"})

    assert omitted_result["session_id"] == session.id
  end

  describe "attach_advisory" do
    test "reports :attached when host hooks/skills are installed" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "ck-context-advisory-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()

      assert {:ok, _binding} =
               ProjectBinding.write(
                 %{
                   "workspace_id" => session.workspace_id,
                   "session_id" => session.id,
                   "agent" => "claude-code",
                   "attached_agents" => %{
                     "claude_code" => %{"server_name" => "controlkeel", "scope" => "local"}
                   }
                 },
                 tmp_dir
               )

      assert {:ok, result} =
               CkContext.call(%{"session_id" => session.id, "project_root" => tmp_dir})

      advisory = result["attach_advisory"]
      assert advisory["status"] == "attached"
      assert "claude_code" in advisory["hosts"]
      assert advisory["guidance"] =~ "installed"
    end

    test "reports :mcp_only with ck_attach guidance when only MCP is wired" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "ck-context-advisory-mcp-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()

      # An auto-bootstrapped binding with no attached_agents simulates the
      # one-line MCP-add path: tools work but hooks/skills are missing.
      assert {:ok, _binding} =
               ProjectBinding.write(
                 %{
                   "workspace_id" => session.workspace_id,
                   "session_id" => session.id,
                   "agent" => "claude-code",
                   "attached_agents" => %{},
                   "bootstrap" => %{"auto_bootstrapped" => true, "mode" => "ephemeral"}
                 },
                 tmp_dir
               )

      assert {:ok, result} =
               CkContext.call(%{"session_id" => session.id, "project_root" => tmp_dir})

      advisory = result["attach_advisory"]
      assert advisory["status"] in ["mcp_only", "unbound"]
      assert advisory["guidance"] =~ "ck_attach" or advisory["guidance"] =~ "controlkeel attach"
    end
  end

  test "context pack rejects non-finite and non-integer ids clearly" do
    assert {:error, {:invalid_arguments, message}} =
             CkContextPack.call(%{"session_id" => :nan, "query" => "continuation"})

    assert message =~ "session_id"
    assert message =~ "integer"

    session = session_fixture()

    assert {:error, {:invalid_arguments, message}} =
             CkContextPack.call(%{"session_id" => session.id, "task_id" => "999999999"})

    assert message =~ "task_id"
    assert message =~ "current session"
  end
end
