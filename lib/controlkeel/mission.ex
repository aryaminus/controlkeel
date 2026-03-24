defmodule ControlKeel.Mission do
  @moduledoc "Mission planning, persistence, and control-tower orchestration."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.AutoFix
  alias ControlKeel.Intent.ExecutionBrief
  alias ControlKeel.Memory
  alias ControlKeel.Notifications.Webhook
  alias ControlKeel.Platform
  alias ControlKeel.Repo

  alias ControlKeel.Mission.{
    Finding,
    Invocation,
    Planner,
    ProofBundle,
    Session,
    Task,
    TaskCheckpoint,
    Workspace
  }

  alias ControlKeel.Scanner

  @findings_page_size 20
  @proofs_page_size 20

  def list_sessions, do: Repo.all(Session)
  def get_session(id), do: Repo.get(Session, id)
  def get_session!(id), do: Repo.get!(Session, id)
  def get_session_by_proxy_token(token), do: Repo.get_by(Session, proxy_token: token)
  def get_session_with_workspace(id), do: Session |> Repo.get(id) |> Repo.preload(:workspace)

  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, session} -> record_brief_memory(session)
      _other -> :ok
    end)
  end

  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  def delete_session(%Session{} = session), do: Repo.delete(session)
  def change_session(%Session{} = session, attrs \\ %{}), do: Session.changeset(session, attrs)

  def list_workspaces, do: Repo.all(Workspace)
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  def list_sessions_for_workspace(workspace_id),
    do: Repo.all(from s in Session, where: s.workspace_id == ^workspace_id)

  def create_workspace(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> Repo.update()
  end

  def delete_workspace(%Workspace{} = workspace), do: Repo.delete(workspace)

  def change_workspace(%Workspace{} = workspace, attrs \\ %{}),
    do: Workspace.changeset(workspace, attrs)

  def list_tasks, do: Repo.all(Task)
  def get_task(id), do: Repo.get(Task, id)
  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, task} -> record_task_memory(:created, task)
      _other -> :ok
    end)
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> record_task_memory(:updated, updated, previous_status: task.status)
      _other -> :ok
    end)
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)
  def change_task(%Task{} = task, attrs \\ %{}), do: Task.changeset(task, attrs)

  def list_findings, do: Repo.all(Finding)
  def get_finding(id), do: Repo.get(Finding, id)
  def get_finding!(id), do: Repo.get!(Finding, id)

  def get_finding_with_context(id) do
    Finding
    |> Repo.get(id)
    |> case do
      nil -> nil
      finding -> Repo.preload(finding, session: :workspace)
    end
  end

  def create_finding(attrs) do
    %Finding{}
    |> Finding.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, finding} ->
        record_finding_memory(:created, finding)

        Platform.emit_event(
          "finding.created",
          %{
            "workspace_id" => workspace_id_for_session(finding.session_id),
            "session_id" => finding.session_id,
            "finding_id" => finding.id,
            "rule_id" => finding.rule_id,
            "severity" => finding.severity,
            "status" => finding.status
          },
          workspace_id: workspace_id_for_session(finding.session_id)
        )

      _other ->
        :ok
    end)
  end

  def update_finding(%Finding{} = finding, attrs) do
    finding
    |> Finding.changeset(attrs)
    |> Repo.update()
  end

  def delete_finding(%Finding{} = finding), do: Repo.delete(finding)
  def change_finding(%Finding{} = finding, attrs \\ %{}), do: Finding.changeset(finding, attrs)

  def list_invocations, do: Repo.all(Invocation)

  def create_invocation(attrs) do
    %Invocation{}
    |> Invocation.changeset(attrs)
    |> Repo.insert()
  end

  def list_proof_bundles do
    Repo.all(ProofBundle)
  end

  def get_proof_bundle(id), do: Repo.get(ProofBundle, id)
  def get_proof_bundle!(id), do: Repo.get!(ProofBundle, id)

  def get_proof_bundle_with_context(id) do
    ProofBundle
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      proof ->
        Repo.preload(proof, task: [], session: :workspace)
    end
  end

  def latest_proof_bundle_for_task(task_id) when is_integer(task_id) do
    ProofBundle
    |> where([proof], proof.task_id == ^task_id)
    |> order_by([proof], desc: proof.version, desc: proof.id)
    |> limit(1)
    |> Repo.one()
  end

  def latest_proof_bundles_for_session(session_id) when is_integer(session_id) do
    ProofBundle
    |> where([proof], proof.session_id == ^session_id)
    |> order_by([proof], asc: proof.task_id, desc: proof.version, desc: proof.id)
    |> Repo.all()
    |> Enum.group_by(& &1.task_id)
    |> Enum.into(%{}, fn {task_id, [latest | _rest]} -> {task_id, latest} end)
  end

  def create_task_checkpoint(attrs) do
    %TaskCheckpoint{}
    |> TaskCheckpoint.changeset(attrs)
    |> Repo.insert()
  end

  def latest_task_checkpoint(task_id) when is_integer(task_id) do
    TaskCheckpoint
    |> where([checkpoint], checkpoint.task_id == ^task_id)
    |> order_by([checkpoint], desc: checkpoint.inserted_at, desc: checkpoint.id)
    |> limit(1)
    |> Repo.one()
  end

  def list_recent_sessions(limit \\ 6) do
    Session
    |> order_by(desc: :inserted_at)
    |> preload([:workspace, :tasks, :findings])
    |> limit(^limit)
    |> Repo.all()
  end

  def get_session_with_details!(id) do
    Session
    |> Repo.get!(id)
    |> Repo.preload([
      :workspace,
      tasks: from(t in Task, order_by: t.position),
      findings: from(f in Finding, order_by: [desc: f.severity, asc: f.inserted_at])
    ])
  end

  def get_session_context(id) do
    Session
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      session ->
        Repo.preload(session, [
          :workspace,
          tasks: from(t in Task, order_by: t.position),
          findings: from(f in Finding, order_by: [desc: f.inserted_at]),
          invocations: from(i in Invocation, order_by: [desc: i.inserted_at])
        ])
    end
  end

  @doc """
  Returns task graph data (nodes, edges, `ready_task_ids`) for Mission Control and APIs.

  Ensures default edges exist when tasks have no edges yet (see `Platform.ensure_session_graph/1`).
  """
  def session_task_graph(session_id) when is_integer(session_id) do
    Platform.ensure_session_graph(session_id)
  end

  @doc """
  Short UI copy for the expected human gate given persisted finding severity/category.
  """
  def finding_human_gate_hint(%Finding{} = finding) do
    case {finding.severity, finding.category} do
      {"critical", _} ->
        "Human review required before any production or high-impact action."

      {"high", "security"} ->
        "Review and approve before merge or release."

      {"high", _} ->
        "Review recommended before marking this work complete."

      {"medium", _} ->
        "Medium risk: review when convenient; fixes may be suggested automatically."

      {_, _} ->
        "Low severity: governance still records the outcome."
    end
  end

  def change_launch(attrs \\ %{}) do
    {%{},
     %{
       project_name: :string,
       industry: :string,
       agent: :string,
       idea: :string,
       users: :string,
       data: :string,
       features: :string,
       budget: :string
     }}
    |> Ecto.Changeset.cast(attrs, [
      :project_name,
      :industry,
      :agent,
      :idea,
      :users,
      :data,
      :features,
      :budget
    ])
    |> Ecto.Changeset.validate_required([:industry, :agent, :idea, :features])
  end

  def create_launch(%{"execution_brief" => %ExecutionBrief{} = brief} = attrs) do
    attrs
    |> Map.delete("execution_brief")
    |> create_launch_from_brief(brief)
  end

  def create_launch(%{execution_brief: %ExecutionBrief{} = brief} = attrs) do
    attrs
    |> Map.delete(:execution_brief)
    |> create_launch_from_brief(brief)
  end

  def create_launch(attrs) do
    plan = Planner.build(attrs)
    persist_launch_plan(plan)
  end

  def create_launch_from_brief(attrs, %ExecutionBrief{} = brief) do
    attrs =
      Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

    brief
    |> Planner.build_from_brief(attrs)
    |> persist_launch_plan()
  end

  defp persist_launch_plan(plan) do
    Multi.new()
    |> Multi.insert(:workspace, Workspace.changeset(%Workspace{}, plan.workspace))
    |> Multi.insert(:session, fn %{workspace: workspace} ->
      Session.changeset(%Session{}, Map.put(plan.session, :workspace_id, workspace.id))
    end)
    |> Multi.run(:tasks, fn repo, %{session: session} ->
      insert_many(repo, Task, plan.tasks, :session_id, session.id)
    end)
    |> Multi.run(:task_edges, fn repo, %{session: session, tasks: tasks} ->
      insert_task_edges(repo, session.id, tasks)
    end)
    |> Multi.run(:findings, fn repo, %{session: session} ->
      insert_many(repo, Finding, plan.findings, :session_id, session.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} ->
        emit_mission_created(plan, session)
        record_brief_memory(session)
        loaded = get_session_with_details!(session.id)
        Enum.each(loaded.tasks, &record_task_memory(:created, &1))
        Enum.each(loaded.findings, &record_finding_memory(:created, &1))
        {:ok, loaded}

      {:error, :workspace, changeset, _changes} ->
        {:error, :workspace, changeset}

      {:error, _step, changeset, _changes} ->
        {:error, :session, changeset}
    end
  end

  def industries, do: Planner.industries()
  def agent_labels, do: Planner.agent_labels()

  def list_session_findings(session_id, opts \\ %{}) do
    session_id
    |> findings_query(opts)
    |> Repo.all()
  end

  def list_findings_browser_sessions do
    Session
    |> order_by(desc: :inserted_at)
    |> preload(:workspace)
    |> Repo.all()
  end

  def list_finding_categories do
    Finding
    |> group_by([f], f.category)
    |> order_by([f], asc: f.category)
    |> select([f], f.category)
    |> Repo.all()
  end

  def browse_findings(opts \\ %{}) do
    filters = normalize_findings_filters(opts)
    base_query = findings_browser_query(filters)
    total_count = Repo.aggregate(base_query, :count, :id)
    total_pages = max(div(total_count + @findings_page_size - 1, @findings_page_size), 1)
    page = min(filters.page, total_pages)

    entries =
      base_query
      |> order_by([f, _s, _w], desc: f.inserted_at, desc: f.id)
      |> limit(^@findings_page_size)
      |> offset(^((page - 1) * @findings_page_size))
      |> Repo.all()

    %{
      entries: entries,
      filters: %{filters | page: page},
      total_count: total_count,
      total_pages: total_pages,
      page: page,
      page_size: @findings_page_size
    }
  end

  def browse_proof_bundles(opts \\ %{}) do
    filters = normalize_proof_filters(opts)
    base_query = proof_bundles_query(filters)
    total_count = Repo.aggregate(base_query, :count, :id)
    total_pages = max(div(total_count + @proofs_page_size - 1, @proofs_page_size), 1)
    page = min(filters.page, total_pages)

    entries =
      base_query
      |> order_by([proof, _task, _session, _workspace], desc: proof.generated_at, desc: proof.id)
      |> limit(^@proofs_page_size)
      |> offset(^((page - 1) * @proofs_page_size))
      |> Repo.all()

    %{
      entries: entries,
      filters: %{filters | page: page},
      total_count: total_count,
      total_pages: total_pages,
      page: page,
      page_size: @proofs_page_size
    }
  end

  def auto_fix_for_finding(%Finding{} = finding), do: AutoFix.generate(finding)

  def approve_finding(%Finding{} = finding) do
    metadata =
      Map.merge(finding.metadata || %{}, %{
        "approved_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case update_finding(finding, %{status: "approved", metadata: metadata}) do
      {:ok, updated} ->
        emit_finding_event(:approved, updated)
        record_finding_memory(:approved, updated)
        emit_platform_finding_event("finding.approved", updated)
        {:ok, updated}

      other ->
        other
    end
  end

  def approve_finding(id) when is_integer(id) do
    case get_finding(id) do
      nil -> {:error, :not_found}
      finding -> approve_finding(finding)
    end
  end

  def reject_finding(finding_or_id, reason \\ nil)

  def reject_finding(%Finding{} = finding, reason) do
    metadata =
      finding.metadata
      |> Kernel.||(%{})
      |> Map.merge(%{
        "rejected_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })
      |> maybe_put_metadata("rejection_reason", reason)

    case update_finding(finding, %{status: "rejected", metadata: metadata}) do
      {:ok, updated} ->
        emit_finding_event(:rejected, updated)
        record_finding_memory(:rejected, updated)
        emit_platform_finding_event("finding.rejected", updated)
        {:ok, updated}

      other ->
        other
    end
  end

  def reject_finding(id, reason) when is_integer(id) do
    case get_finding(id) do
      nil -> {:error, :not_found}
      finding -> reject_finding(finding, reason)
    end
  end

  def escalate_finding(%Finding{} = finding) do
    metadata =
      Map.merge(finding.metadata || %{}, %{
        "escalated_at" =>
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case update_finding(finding, %{status: "escalated", metadata: metadata}) do
      {:ok, updated} ->
        emit_finding_event(:escalated, updated)
        record_finding_memory(:escalated, updated)
        {:ok, updated}

      other ->
        other
    end
  end

  @doc """
  Complete a task, gating on open/blocked findings.

  Returns `{:error, :unresolved_findings, findings}` if any findings on the
  session are still in `open` or `blocked` status.
  Returns `{:ok, task}` if the task is safe to mark done.
  """
  def complete_task(%Task{} = task) do
    unresolved = unresolved_findings(task.session_id)

    if unresolved == [] do
      Multi.new()
      |> Multi.update(:task, Task.changeset(task, %{status: "done"}))
      |> Multi.run(:proof, fn repo, %{task: updated_task} ->
        persist_proof_bundle(repo, updated_task)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{task: updated_task, proof: proof}} ->
          record_task_memory(:completed, updated_task,
            proof_id: proof.id,
            previous_status: task.status
          )

          record_proof_memory(proof)
          Platform.persist_proof_generated(proof)
          {:ok, updated_task}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    else
      _ = maybe_block_task(task)
      {:error, :unresolved_findings, unresolved}
    end
  end

  def complete_task(task_id) when is_integer(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> complete_task(task)
    end
  end

  @doc """
  Build a structured proof bundle for a completed task.

  The proof bundle is the canonical audit artifact for a task:
  security findings, invocation summary, cost, risk score, deploy readiness,
  and compliance attestations.
  """
  def proof_bundle(task_id) when is_integer(task_id) do
    case Repo.get(Task, task_id) do
      nil ->
        {:error, :not_found}

      task ->
        case latest_proof_bundle_for_task(task.id) do
          %ProofBundle{} = proof -> {:ok, proof.bundle}
          nil -> generate_proof_bundle(task_id) |> unwrap_proof_bundle()
        end
    end
  end

  def proof_bundle(task_id) when is_binary(task_id) do
    case Integer.parse(task_id) do
      {parsed, ""} -> proof_bundle(parsed)
      _error -> {:error, :not_found}
    end
  end

  def generate_proof_bundle(task_id) when is_integer(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> generate_proof_bundle(task)
    end
  end

  def generate_proof_bundle(task_id) when is_binary(task_id) do
    case Integer.parse(task_id) do
      {parsed, ""} -> generate_proof_bundle(parsed)
      _error -> {:error, :not_found}
    end
  end

  def generate_proof_bundle(%Task{} = task) do
    Repo.transaction(fn ->
      with {:ok, proof} <- persist_proof_bundle(Repo, Repo.get!(Task, task.id)) do
        proof
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, proof} ->
        record_proof_memory(proof)
        Platform.persist_proof_generated(proof)
        {:ok, proof}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def pause_task(task_or_id, created_by \\ "system")

  def pause_task(task_id, created_by) when is_integer(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> pause_task(task, created_by)
    end
  end

  def pause_task(%Task{} = task, created_by) do
    packet = resume_packet_for_task(task)

    summary =
      "Paused #{task.title} with #{length(packet["unresolved_findings"])} unresolved finding(s)."

    Multi.new()
    |> Multi.update(:task, Task.changeset(task, %{status: "paused"}))
    |> Multi.insert(:checkpoint, fn %{task: updated_task} ->
      TaskCheckpoint.changeset(%TaskCheckpoint{}, %{
        session_id: updated_task.session_id,
        task_id: updated_task.id,
        checkpoint_type: "pause",
        summary: summary,
        payload: packet,
        created_by: created_by
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{task: updated_task, checkpoint: checkpoint}} ->
        record_task_memory(:paused, updated_task, previous_status: task.status)
        record_checkpoint_memory(checkpoint)
        {:ok, %{task: updated_task, checkpoint: checkpoint, resume_packet: packet}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  def resume_task(task_or_id, created_by \\ "system")

  def resume_task(task_id, created_by) when is_integer(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> resume_task(task, created_by)
    end
  end

  def resume_task(%Task{} = task, created_by) do
    packet = resume_packet_for_task(task)

    summary =
      "Resumed #{task.title} with #{length(packet["unresolved_findings"])} unresolved finding(s)."

    Multi.new()
    |> Multi.update(:task, Task.changeset(task, %{status: "in_progress"}))
    |> Multi.insert(:checkpoint, fn %{task: updated_task} ->
      TaskCheckpoint.changeset(%TaskCheckpoint{}, %{
        session_id: updated_task.session_id,
        task_id: updated_task.id,
        checkpoint_type: "resume",
        summary: summary,
        payload: packet,
        created_by: created_by
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{task: updated_task, checkpoint: checkpoint}} ->
        record_task_memory(:resumed, updated_task, previous_status: task.status)
        record_checkpoint_memory(checkpoint)
        {:ok, %{task: updated_task, checkpoint: checkpoint, resume_packet: packet}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  def resume_packet(task_id) when is_integer(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> {:ok, resume_packet_for_task(task)}
    end
  end

  def proof_summary_for_task(nil), do: nil

  def proof_summary_for_task(%Task{id: task_id}) do
    task_id |> latest_proof_bundle_for_task() |> proof_summary()
  end

  def proof_summary_for_task(task_id) when is_integer(task_id) do
    task_id |> latest_proof_bundle_for_task() |> proof_summary()
  end

  @doc """
  Return a structured audit log for a session: all invocations and findings
  in chronological order.
  """
  def audit_log(session_id) do
    session = get_session(session_id)

    if is_nil(session) do
      {:error, :not_found}
    else
      invocations =
        Repo.all(
          from(i in Invocation, where: i.session_id == ^session_id, order_by: i.inserted_at)
        )

      findings =
        Repo.all(from(f in Finding, where: f.session_id == ^session_id, order_by: f.inserted_at))

      tasks =
        Repo.all(from(t in Task, where: t.session_id == ^session_id, order_by: t.position))

      events =
        (Enum.map(invocations, &audit_invocation_entry/1) ++
           Enum.map(findings, &audit_finding_entry/1))
        |> Enum.sort_by(& &1.timestamp)

      {:ok,
       %{
         session_id: session_id,
         session_title: session.title,
         domain_pack: get_in(session, [Access.key(:execution_brief), "domain_pack"]),
         risk_tier: session.risk_tier,
         started_at: session.inserted_at,
         tasks: Enum.map(tasks, &task_audit_entry/1),
         events: events,
         summary: %{
           total_invocations: length(invocations),
           total_findings: length(findings),
           blocked_findings: Enum.count(findings, &(&1.status == "blocked")),
           total_cost_cents: session.spent_cents || 0
         }
       }}
    end
  end

  defp compute_risk_score(findings) do
    weights = %{"critical" => 1.0, "high" => 0.7, "medium" => 0.4, "low" => 0.1}

    raw =
      findings
      |> Enum.filter(&(&1.status not in ["approved", "resolved"]))
      |> Enum.reduce(0.0, fn f, acc -> acc + Map.get(weights, f.severity, 0.0) end)

    Float.round(min(raw / max(length(findings), 1), 1.0), 2)
  end

  defp build_compliance_attestations(nil, _findings), do: []

  defp build_compliance_attestations(session, findings) do
    domain_pack = get_in(session, [Access.key(:execution_brief), "domain_pack"])
    packs = List.wrap(domain_pack) ++ ["baseline"]

    Enum.map(packs, fn pack ->
      pack_findings = Enum.filter(findings, &String.starts_with?(&1.rule_id, pack))
      blocked = Enum.filter(pack_findings, &(&1.status == "blocked"))

      %{
        pack: pack,
        status: if(blocked == [], do: "passed", else: "failed"),
        findings_count: length(pack_findings),
        blocked_count: length(blocked)
      }
    end)
  end

  defp derive_test_outcomes(invocations) do
    outcomes = Enum.map(invocations, &get_in(&1.metadata, ["outcome"]))
    passed = Enum.count(outcomes, &(&1 == "passed"))
    failed = Enum.count(outcomes, &(&1 == "failed"))
    %{"passed" => passed, "failed" => failed, "recorded" => length(invocations)}
  end

  defp finding_bundle_entry(f) do
    %{
      id: f.id,
      rule_id: f.rule_id,
      severity: f.severity,
      category: f.category,
      status: f.status,
      plain_message: f.plain_message,
      auto_resolved: f.auto_resolved
    }
  end

  defp audit_invocation_entry(i) do
    %{
      type: "invocation",
      timestamp: i.inserted_at,
      source: i.source,
      tool: i.tool,
      provider: i.provider,
      model: i.model,
      decision: i.decision,
      cost_cents: i.estimated_cost_cents,
      tokens: i.input_tokens + i.output_tokens
    }
  end

  defp audit_finding_entry(f) do
    %{
      type: "finding",
      timestamp: f.inserted_at,
      rule_id: f.rule_id,
      severity: f.severity,
      category: f.category,
      status: f.status,
      plain_message: f.plain_message
    }
  end

  defp task_audit_entry(t) do
    %{id: t.id, title: t.title, status: t.status, position: t.position}
  end

  defp unresolved_findings(session_id) do
    Finding
    |> where([finding], finding.session_id == ^session_id)
    |> where([finding], finding.status in ["open", "blocked"])
    |> Repo.all()
  end

  defp maybe_block_task(%Task{status: "blocked"}), do: :ok
  defp maybe_block_task(%Task{} = task), do: update_task(task, %{status: "blocked"})

  defp unwrap_proof_bundle({:ok, %ProofBundle{} = proof}), do: {:ok, proof.bundle}
  defp unwrap_proof_bundle(other), do: other

  defp persist_proof_bundle(repo, %Task{} = task) do
    session =
      Session
      |> repo.get(task.session_id)
      |> repo.preload(:workspace)

    findings =
      Finding
      |> where([finding], finding.session_id == ^task.session_id)
      |> order_by([finding], desc: finding.inserted_at)
      |> repo.all()

    invocations =
      Invocation
      |> where([invocation], invocation.task_id == ^task.id)
      |> order_by([invocation], desc: invocation.inserted_at)
      |> repo.all()

    snapshot = build_proof_bundle_snapshot(task, session, findings, invocations)

    attrs = %{
      session_id: task.session_id,
      task_id: task.id,
      version: next_proof_bundle_version(repo, task.id),
      status: task.status,
      risk_score: snapshot["risk_score"],
      deploy_ready: snapshot["deploy_ready"],
      open_findings_count: get_in(snapshot, ["security_findings", "open"]) || 0,
      blocked_findings_count: get_in(snapshot, ["security_findings", "blocked"]) || 0,
      approved_findings_count: get_in(snapshot, ["finding_resolution_summary", "approved"]) || 0,
      bundle: snapshot,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %ProofBundle{}
    |> ProofBundle.changeset(attrs)
    |> repo.insert()
  end

  defp next_proof_bundle_version(repo, task_id) do
    ProofBundle
    |> where([proof], proof.task_id == ^task_id)
    |> select([proof], max(proof.version))
    |> repo.one()
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  defp build_proof_bundle_snapshot(task, session, findings, invocations) do
    total_cost = Enum.sum(Enum.map(invocations, &(&1.estimated_cost_cents || 0)))
    blocked = Enum.filter(findings, &(&1.status == "blocked"))
    open = Enum.filter(findings, &(&1.status == "open"))
    approved = Enum.filter(findings, &(&1.status == "approved"))
    resolved = Enum.filter(findings, &(&1.status in ["approved", "resolved", "rejected"]))
    details = Enum.map(findings, &finding_bundle_entry/1)
    risk_score = compute_risk_score(findings)
    deploy_ready = blocked == [] and open == [] and task.status == "done"
    compliance_attestations = build_compliance_attestations(session, findings)
    test_outcomes = derive_test_outcomes(invocations)

    %{
      "task_id" => task.id,
      "task_title" => task.title,
      "session_id" => task.session_id,
      "agent" => get_in(session, [Access.key(:execution_brief), "agent"]) || "unknown",
      "status" => task.status,
      "duration_ms" => get_in(task.metadata || %{}, ["duration_ms"]),
      "cost_cents" => total_cost,
      "invocation_count" => length(invocations),
      "security_findings" => %{
        "total" => length(findings),
        "blocked" => length(blocked),
        "open" => length(open),
        "resolved" => length(resolved),
        "details" => details
      },
      "test_outcomes" => test_outcomes,
      "diff_summary" => %{
        "agent_runs" => length(invocations),
        "findings_total" => length(findings),
        "auto_resolved" => Enum.count(details, & &1.auto_resolved),
        "manual_review" => Enum.count(details, &(&1.status in ["approved", "rejected"]))
      },
      "risk_score" => risk_score,
      "deploy_ready" => deploy_ready,
      "rollback_instructions" =>
        "git revert HEAD  # revert changes from task #{task.id} if needed",
      "compliance_attestations" => compliance_attestations,
      "validation_gate" => task.validation_gate,
      "invocation_summary" => build_invocation_summary(invocations, total_cost),
      "finding_resolution_summary" => %{
        "approved" => length(approved),
        "resolved" => length(resolved),
        "open" => length(open),
        "blocked" => length(blocked)
      },
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_invocation_summary(invocations, total_cost) do
    %{
      "total" => length(invocations),
      "providers" =>
        invocations
        |> Enum.group_by(&(&1.provider || "unknown"))
        |> Enum.into(%{}, fn {provider, rows} -> {provider, length(rows)} end),
      "tools" =>
        invocations
        |> Enum.group_by(&(&1.tool || "unknown"))
        |> Enum.into(%{}, fn {tool, rows} -> {tool, length(rows)} end),
      "cost_cents" => total_cost,
      "latest_run_at" =>
        invocations
        |> Enum.map(& &1.inserted_at)
        |> Enum.max_by(&DateTime.to_unix/1, fn -> nil end)
    }
  end

  defp proof_summary(nil), do: nil

  defp proof_summary(%ProofBundle{} = proof) do
    domain_pack =
      proof.session_id
      |> get_session()
      |> case do
        nil -> nil
        session -> get_in(session.execution_brief || %{}, ["domain_pack"])
      end

    %{
      "id" => proof.id,
      "task_id" => proof.task_id,
      "version" => proof.version,
      "status" => proof.status,
      "risk_score" => proof.risk_score,
      "deploy_ready" => proof.deploy_ready,
      "open_findings_count" => proof.open_findings_count,
      "blocked_findings_count" => proof.blocked_findings_count,
      "approved_findings_count" => proof.approved_findings_count,
      "domain_pack" => domain_pack,
      "generated_at" => proof.generated_at
    }
  end

  defp resume_packet_for_task(%Task{} = task) do
    session = get_session_context(task.session_id)
    relevant_findings = Enum.filter(session.findings, &(&1.metadata["task_id"] in [nil, task.id]))
    memory_hits = Memory.retrieve_for_task(session, task, findings: relevant_findings)
    latest_proof = latest_proof_bundle_for_task(task.id)
    latest_invocations = list_task_invocations(task.id, 5)

    %{
      "task_id" => task.id,
      "task_title" => task.title,
      "task_status" => task.status,
      "validation_gate" => task.validation_gate,
      "session_id" => task.session_id,
      "budget_summary" => %{
        "spent_cents" => session.spent_cents,
        "budget_cents" => session.budget_cents,
        "daily_budget_cents" => session.daily_budget_cents
      },
      "unresolved_findings" =>
        relevant_findings
        |> Enum.filter(&(&1.status in ["open", "blocked", "escalated"]))
        |> Enum.map(&finding_bundle_entry/1),
      "latest_invocations" => Enum.map(latest_invocations, &audit_invocation_entry/1),
      "proof_summary" => proof_summary(latest_proof),
      "memory_hits" => memory_hits.entries
    }
  end

  def list_task_invocations(task_id, limit \\ 5) do
    Invocation
    |> where([invocation], invocation.task_id == ^task_id)
    |> order_by([invocation], desc: invocation.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp record_brief_memory(%Session{workspace_id: nil}), do: :ok

  defp record_brief_memory(%Session{} = session) do
    brief = session.execution_brief || %{}

    Memory.record(%{
      workspace_id: session.workspace_id,
      session_id: session.id,
      record_type: "brief",
      title: "Execution brief created",
      summary: session.title,
      body: brief_body(session, brief),
      tags: [brief["domain_pack"], session.risk_tier, "brief"],
      source_type: "session",
      source_id: session.id,
      metadata: %{
        "domain_pack" => brief["domain_pack"],
        "risk_tier" => session.risk_tier,
        "occupation" => brief["occupation"]
      }
    })
  end

  defp brief_body(session, brief) do
    [
      session.objective,
      brief["recommended_stack"],
      Enum.join(List.wrap(brief["acceptance_criteria"]), "\n"),
      Enum.join(List.wrap(brief["open_questions"]), "\n")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp record_task_memory(action, %Task{} = task, extra \\ []) do
    case get_session_with_workspace(task.session_id) do
      nil ->
        :ok

      session ->
        Memory.record(%{
          workspace_id: session.workspace_id,
          session_id: session.id,
          task_id: task.id,
          record_type: "task",
          title: task_memory_title(action, task),
          summary: "#{task.title} is now #{task.status}",
          body: task.validation_gate || "",
          tags: [task.status, session.risk_tier, "task"],
          source_type: "task",
          source_id: task.id,
          metadata: %{
            "action" => to_string(action),
            "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"]),
            "previous_status" => Keyword.get(extra, :previous_status),
            "proof_id" => Keyword.get(extra, :proof_id)
          }
        })
    end
  end

  defp task_memory_title(:created, task), do: "Task created: #{task.title}"
  defp task_memory_title(:completed, task), do: "Task completed: #{task.title}"
  defp task_memory_title(:paused, task), do: "Task paused: #{task.title}"
  defp task_memory_title(:resumed, task), do: "Task resumed: #{task.title}"
  defp task_memory_title(:updated, task), do: "Task updated: #{task.title}"
  defp task_memory_title(_action, task), do: "Task changed: #{task.title}"

  defp record_finding_memory(action, %Finding{} = finding) do
    case get_session_with_workspace(finding.session_id) do
      nil ->
        :ok

      session ->
        Memory.record(%{
          workspace_id: session.workspace_id,
          session_id: session.id,
          task_id: finding.metadata["task_id"],
          record_type: "finding",
          title: "Finding #{to_string(action)}: #{finding.title}",
          summary: finding.plain_message,
          body: "#{finding.rule_id} (#{finding.severity}/#{finding.status})",
          tags: [finding.rule_id, finding.severity, finding.status, "finding"],
          source_type: "finding",
          source_id: finding.id,
          metadata:
            %{
              "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"]),
              "action" => to_string(action),
              "status" => finding.status,
              "rule_id" => finding.rule_id
            }
            |> Map.merge(finding.metadata || %{})
        })
    end
  end

  defp record_proof_memory(%ProofBundle{} = proof) do
    proof = Repo.preload(proof, task: [], session: :workspace)

    Memory.record(%{
      workspace_id: proof.session.workspace_id,
      session_id: proof.session_id,
      task_id: proof.task_id,
      record_type: "proof",
      title: "Proof bundle v#{proof.version} for #{proof.task.title}",
      summary: "Risk #{proof.risk_score}, deploy ready: #{proof.deploy_ready}",
      body: Jason.encode!(proof.bundle, pretty: true),
      tags: [proof.status, (proof.deploy_ready && "deploy-ready") || "not-ready", "proof"],
      source_type: "proof_bundle",
      source_id: proof.id,
      metadata: %{
        "domain_pack" => get_in(proof.session.execution_brief || %{}, ["domain_pack"]),
        "version" => proof.version,
        "risk_score" => proof.risk_score,
        "deploy_ready" => proof.deploy_ready
      }
    })
  end

  defp record_checkpoint_memory(%TaskCheckpoint{} = checkpoint) do
    session = get_session_with_workspace(checkpoint.session_id)
    task = Repo.get(Task, checkpoint.task_id)

    if session && task do
      Memory.record(%{
        workspace_id: session.workspace_id,
        session_id: session.id,
        task_id: task.id,
        record_type: "checkpoint",
        title: "Task #{checkpoint.checkpoint_type}: #{task.title}",
        summary: checkpoint.summary,
        body: Jason.encode!(checkpoint.payload, pretty: true),
        tags: [checkpoint.checkpoint_type, "checkpoint"],
        source_type: "task_checkpoint",
        source_id: checkpoint.id,
        metadata: %{
          "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"]),
          "created_by" => checkpoint.created_by
        }
      })
    end
  end

  def record_runtime_findings(session_id, findings, opts \\ []) when is_list(findings) do
    case get_session(session_id) do
      nil ->
        {:error, :session_not_found}

      %Session{} = session ->
        findings
        |> Enum.reduce_while({:ok, []}, fn finding, {:ok, acc} ->
          finding
          |> runtime_finding_attrs(opts)
          |> create_finding()
          |> case do
            {:ok, persisted} -> {:cont, {:ok, [persisted | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
        |> case do
          {:ok, persisted} ->
            persisted = Enum.reverse(persisted)
            emit_first_finding_recorded(session, persisted, opts)
            Enum.each(persisted, &Webhook.notify(&1, session))
            {:ok, persisted}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp insert_many(repo, schema, rows, foreign_key, foreign_id) do
    rows
    |> Enum.map(&Map.put(&1, foreign_key, foreign_id))
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      case repo.insert(schema.changeset(struct(schema), row)) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp insert_task_edges(repo, session_id, tasks) do
    tasks
    |> Platform.TaskGraph.build_edges()
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      attrs = Map.put(attrs, :session_id, session_id)

      case repo.insert(
             ControlKeel.Platform.TaskEdge.changeset(%ControlKeel.Platform.TaskEdge{}, attrs)
           ) do
        {:ok, edge} -> {:cont, {:ok, [edge | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, edges} -> {:ok, Enum.reverse(edges)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp emit_mission_created(plan, %Session{} = session) do
    brief = plan.session.execution_brief || %{}
    compiler = brief["compiler"] || brief[:compiler] || %{}

    :telemetry.execute(
      [:controlkeel, :intent, :mission, :created],
      %{count: 1},
      %{
        session_id: session.id,
        workspace_id: session.workspace_id,
        risk_tier: session.risk_tier,
        domain_pack: brief["domain_pack"] || brief[:domain_pack],
        provider: compiler["provider"] || compiler[:provider]
      }
    )
  end

  defp emit_first_finding_recorded(_session, [], _opts), do: :ok

  defp emit_first_finding_recorded(%Session{} = session, persisted, opts) do
    first_finding = List.first(persisted)

    :telemetry.execute(
      [:controlkeel, :session, :first_finding_recorded],
      %{count: 1},
      %{
        session_id: session.id,
        workspace_id: session.workspace_id,
        finding_id: first_finding && first_finding.id,
        scanner: opts[:scanner] || "fast_path"
      }
    )
  end

  defp emit_platform_finding_event(event, finding) do
    Platform.emit_event(
      event,
      %{
        "workspace_id" => workspace_id_for_session(finding.session_id),
        "session_id" => finding.session_id,
        "finding_id" => finding.id,
        "rule_id" => finding.rule_id,
        "severity" => finding.severity,
        "status" => finding.status
      },
      workspace_id: workspace_id_for_session(finding.session_id)
    )
  end

  defp workspace_id_for_session(session_id) do
    case get_session(session_id) do
      nil -> nil
      session -> session.workspace_id
    end
  end

  defp emit_finding_event(action, %Finding{} = finding) do
    :telemetry.execute(
      [:controlkeel, :finding, action],
      %{count: 1},
      %{
        finding_id: finding.id,
        session_id: finding.session_id,
        rule_id: finding.rule_id,
        severity: finding.severity,
        category: finding.category,
        status: finding.status
      }
    )
  end

  defp runtime_finding_attrs(%Scanner.Finding{} = finding, opts) do
    metadata =
      finding.metadata
      |> Map.merge(%{
        "scanner" => finding.metadata["scanner"] || opts[:scanner] || "fast_path",
        "path" => opts[:path],
        "kind" => opts[:kind],
        "task_id" => opts[:task_id],
        "source" => opts[:source],
        "phase" => opts[:phase]
      })
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    %{
      title: finding_title(finding),
      severity: finding.severity,
      category: finding.category,
      rule_id: finding.rule_id,
      plain_message: finding.plain_message,
      status: status_for_decision(finding.decision),
      auto_resolved: false,
      metadata: metadata,
      session_id: opts[:session_id]
    }
  end

  defp finding_title(%Scanner.Finding{rule_id: "cost.budget_guard"}), do: "Budget cap reached"

  defp finding_title(%Scanner.Finding{rule_id: "cost.budget_warning"}),
    do: "Budget almost exhausted"

  defp finding_title(%Scanner.Finding{category: "security", rule_id: rule_id}) do
    humanize_rule(rule_id)
  end

  defp finding_title(%Scanner.Finding{category: "privacy", rule_id: rule_id}) do
    humanize_rule(rule_id)
  end

  defp finding_title(%Scanner.Finding{category: "compliance", rule_id: rule_id}) do
    humanize_rule(rule_id)
  end

  defp finding_title(%Scanner.Finding{rule_id: rule_id}), do: humanize_rule(rule_id)

  defp humanize_rule(rule_id) do
    rule_id
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_for_decision("block"), do: "blocked"
  defp status_for_decision("escalate_to_human"), do: "escalated"
  defp status_for_decision("warn"), do: "open"
  defp status_for_decision(_decision), do: "open"

  defp findings_query(session_id, opts) do
    from(f in Finding, where: f.session_id == ^session_id, order_by: [desc: f.inserted_at])
    |> maybe_filter_finding(:severity, Map.get(opts, :severity) || Map.get(opts, "severity"))
    |> maybe_filter_finding(:status, Map.get(opts, :status) || Map.get(opts, "status"))
  end

  defp findings_browser_query(filters) do
    from(f in Finding,
      join: s in assoc(f, :session),
      join: w in assoc(s, :workspace),
      preload: [session: {s, workspace: w}]
    )
    |> maybe_search_findings(filters.q)
    |> maybe_filter_finding(:severity, filters.severity)
    |> maybe_filter_finding(:status, filters.status)
    |> maybe_filter_finding(:category, filters.category)
    |> maybe_filter_session(filters.session_id)
  end

  defp proof_bundles_query(filters) do
    from(proof in ProofBundle,
      join: task in assoc(proof, :task),
      join: session in assoc(proof, :session),
      join: workspace in assoc(session, :workspace),
      preload: [task: task, session: {session, workspace: workspace}]
    )
    |> maybe_search_proofs(filters.q)
    |> maybe_filter_proof_session(filters.session_id)
    |> maybe_filter_proof_task(filters.task_id)
    |> maybe_filter_proof_ready(filters.deploy_ready)
    |> maybe_filter_proof_risk(filters.risk_tier)
  end

  defp normalize_findings_filters(opts) do
    opts =
      Enum.into(opts, %{}, fn {key, value} -> {to_string(key), value} end)

    %{
      q: normalize_filter_value(opts["q"]),
      severity: normalize_filter_value(opts["severity"]),
      status: normalize_filter_value(opts["status"]),
      category: normalize_filter_value(opts["category"]),
      session_id: normalize_session_filter(opts["session_id"]),
      page: normalize_page(opts["page"])
    }
  end

  defp normalize_proof_filters(opts) do
    opts =
      Enum.into(opts, %{}, fn {key, value} -> {to_string(key), value} end)

    %{
      q: normalize_filter_value(opts["q"]),
      session_id: normalize_session_filter(opts["session_id"]),
      task_id: normalize_session_filter(opts["task_id"]),
      deploy_ready: normalize_boolean_filter(opts["deploy_ready"]),
      risk_tier: normalize_filter_value(opts["risk_tier"]),
      page: normalize_page(opts["page"])
    }
  end

  defp normalize_filter_value(nil), do: nil

  defp normalize_filter_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_session_filter(nil), do: nil

  defp normalize_session_filter(value) when is_integer(value), do: value

  defp normalize_session_filter(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_page(nil), do: 1
  defp normalize_page(value) when is_integer(value), do: max(value, 1)

  defp normalize_page(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> 1
    end
  end

  defp normalize_boolean_filter(nil), do: nil
  defp normalize_boolean_filter(true), do: true
  defp normalize_boolean_filter(false), do: false

  defp normalize_boolean_filter(value) do
    case String.downcase(to_string(value)) do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp maybe_search_findings(query, nil), do: query
  defp maybe_search_findings(query, ""), do: query

  defp maybe_search_findings(query, value) do
    pattern = "%" <> String.downcase(value) <> "%"

    from([f, s, w] in query,
      where:
        like(fragment("lower(?)", f.title), ^pattern) or
          like(fragment("lower(?)", f.plain_message), ^pattern) or
          like(fragment("lower(?)", f.rule_id), ^pattern) or
          like(fragment("lower(?)", f.category), ^pattern) or
          like(fragment("lower(?)", s.title), ^pattern) or
          like(fragment("lower(?)", w.name), ^pattern)
    )
  end

  defp maybe_search_proofs(query, nil), do: query
  defp maybe_search_proofs(query, ""), do: query

  defp maybe_search_proofs(query, value) do
    pattern = "%" <> String.downcase(value) <> "%"

    from([proof, task, session, workspace] in query,
      where:
        like(fragment("lower(?)", task.title), ^pattern) or
          like(fragment("lower(?)", session.title), ^pattern) or
          like(fragment("lower(?)", workspace.name), ^pattern) or
          like(fragment("lower(?)", proof.status), ^pattern)
    )
  end

  defp maybe_filter_finding(query, _field, nil), do: query
  defp maybe_filter_finding(query, _field, ""), do: query

  defp maybe_filter_finding(query, field_name, value) do
    from(f in query, where: field(f, ^field_name) == ^value)
  end

  defp maybe_filter_session(query, nil), do: query

  defp maybe_filter_session(query, session_id) do
    from([f, _s, _w] in query, where: f.session_id == ^session_id)
  end

  defp maybe_filter_proof_session(query, nil), do: query

  defp maybe_filter_proof_session(query, session_id) do
    from([proof, _task, _session, _workspace] in query, where: proof.session_id == ^session_id)
  end

  defp maybe_filter_proof_task(query, nil), do: query

  defp maybe_filter_proof_task(query, task_id) do
    from([proof, _task, _session, _workspace] in query, where: proof.task_id == ^task_id)
  end

  defp maybe_filter_proof_ready(query, nil), do: query

  defp maybe_filter_proof_ready(query, deploy_ready) do
    from([proof, _task, _session, _workspace] in query,
      where: proof.deploy_ready == ^deploy_ready
    )
  end

  defp maybe_filter_proof_risk(query, nil), do: query
  defp maybe_filter_proof_risk(query, ""), do: query

  defp maybe_filter_proof_risk(query, risk_tier) do
    from([_proof, _task, session, _workspace] in query, where: session.risk_tier == ^risk_tier)
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
