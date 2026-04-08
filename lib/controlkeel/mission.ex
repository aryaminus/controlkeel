defmodule ControlKeel.Mission do
  @moduledoc "Mission planning, persistence, and control-tower orchestration."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.AutoFix
  alias ControlKeel.Intent.ExecutionBrief
  alias ControlKeel.Memory
  alias ControlKeel.Notifications.Webhook
  alias ControlKeel.Platform
  alias ControlKeel.SessionTranscript
  alias ControlKeel.SecurityWorkflow
  alias ControlKeel.Repo
  alias ControlKeel.WorkspaceContext

  alias ControlKeel.Mission.{
    Finding,
    Invocation,
    Planner,
    ProofBundle,
    Review,
    Session,
    Task,
    TaskCheckpoint,
    Workspace
  }

  alias ControlKeel.Scanner

  @findings_page_size 20
  @proofs_page_size 20
  @plan_phases ~w(ticket research_packet design_options narrowed_decision implementation_plan code_backed_plan)
  @execution_ready_plan_phases ~w(implementation_plan code_backed_plan)

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

  def attach_session_runtime_context(session_or_id, context)

  def attach_session_runtime_context(session_id, context) when is_integer(session_id) do
    case get_session(session_id) do
      nil -> {:error, :not_found}
      session -> attach_session_runtime_context(session, context)
    end
  end

  def attach_session_runtime_context(%Session{} = session, context) when is_map(context) do
    update_session(session, %{metadata: merge_runtime_context(session.metadata || %{}, context)})
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

  def attach_task_runtime_context(task_or_id, context)

  def attach_task_runtime_context(task_id, context) when is_integer(task_id) do
    case get_task(task_id) do
      nil -> {:error, :not_found}
      task -> attach_task_runtime_context(task, context)
    end
  end

  def attach_task_runtime_context(%Task{} = task, context) when is_map(context) do
    update_task(task, %{metadata: merge_runtime_context(task.metadata || %{}, context)})
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)
  def change_task(%Task{} = task, attrs \\ %{}), do: Task.changeset(task, attrs)

  def list_reviews, do: Repo.all(Review)
  def get_review(id), do: Repo.get(Review, id)
  def get_review!(id), do: Repo.get!(Review, id)

  def get_review_with_context(id) do
    Review
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      review ->
        Repo.preload(review, [:previous_review, :revisions, task: [], session: :workspace])
    end
  end

  def list_reviews_for_session(session_id) when is_integer(session_id) do
    Review
    |> where([review], review.session_id == ^session_id)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> Repo.all()
    |> Repo.preload([:previous_review, task: []])
  end

  def latest_review_for_task(task_id, review_type \\ nil)

  def latest_review_for_task(task_id, nil) when is_integer(task_id) do
    Review
    |> where([review], review.task_id == ^task_id)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> limit(1)
    |> Repo.one()
  end

  def latest_review_for_task(task_id, review_type)
      when is_integer(task_id) and is_binary(review_type) do
    Review
    |> where([review], review.task_id == ^task_id and review.review_type == ^review_type)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> limit(1)
    |> Repo.one()
  end

  def review_gate_status(%Task{} = task) do
    gate = get_in(task.metadata || %{}, ["review_gate"]) || %{}

    %{
      "phase" => gate["phase"] || "execution",
      "execution_ready" => Map.get(gate, "execution_ready", true),
      "latest_review_id" => gate["latest_review_id"],
      "latest_review_status" => gate["latest_review_status"],
      "latest_review_type" => gate["latest_review_type"],
      "latest_plan_phase" => gate["latest_plan_phase"],
      "plan_quality_status" => gate["plan_quality_status"],
      "plan_quality_score" => gate["plan_quality_score"],
      "planning_depth" => gate["planning_depth"],
      "grill_questions" => gate["grill_questions"] || []
    }
  end

  def execution_ready?(%Task{} = task) do
    review_gate_status(task)["execution_ready"] != false
  end

  def execution_ready?(task_id) when is_integer(task_id) do
    case get_task(task_id) do
      nil -> false
      task -> execution_ready?(task)
    end
  end

  def submit_review(attrs) do
    with {:ok, normalized} <- normalize_review_submission(attrs) do
      Multi.new()
      |> maybe_supersede_pending_reviews(normalized)
      |> Multi.insert(:review, Review.changeset(%Review{}, normalized.attrs))
      |> maybe_track_task_review_gate(normalized)
      |> maybe_track_review_runtime_context(normalized)
      |> Repo.transaction()
      |> case do
        {:ok, %{review: review}} ->
          review = get_review_with_context(review.id)
          record_review_memory(:submitted, review)
          {:ok, review}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def respond_review(review_or_id, attrs)

  def respond_review(review_id, attrs) when is_integer(review_id) do
    case get_review(review_id) do
      nil -> {:error, :not_found}
      review -> respond_review(review, attrs)
    end
  end

  def respond_review(%Review{} = review, attrs) do
    with {:ok, normalized} <- normalize_review_response(attrs) do
      review_attrs = merge_review_response_attrs(review, normalized.review_attrs)

      Multi.new()
      |> Multi.update(:review, Review.changeset(review, review_attrs))
      |> maybe_apply_review_response_gate(review, normalized)
      |> Repo.transaction()
      |> case do
        {:ok, %{review: updated}} ->
          updated = get_review_with_context(updated.id)
          action = if updated.status == "approved", do: :approved, else: :denied
          record_review_memory(action, updated)
          {:ok, updated}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

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

  def record_regression_result(attrs) when is_map(attrs) do
    with {:ok, normalized} <- normalize_regression_result(attrs),
         {:ok, invocation} <-
           create_invocation(%{
             source: "external_qa",
             tool: "regression_test",
             provider: normalized["engine"],
             model: nil,
             estimated_cost_cents: 0,
             decision: regression_decision(normalized["outcome"]),
             metadata: regression_metadata(normalized),
             session_id: normalized["session_id"],
             task_id: normalized["task_id"]
           }) do
      {:ok,
       %{
         "recorded" => true,
         "invocation_id" => invocation.id,
         "session_id" => invocation.session_id,
         "task_id" => invocation.task_id,
         "engine" => normalized["engine"],
         "flow_name" => normalized["flow_name"],
         "outcome" => normalized["outcome"],
         "summary" => normalized["summary"],
         "evidence" => normalized["evidence"]
       }}
    end
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
          invocations: from(i in Invocation, order_by: [desc: i.inserted_at]),
          reviews: from(r in Review, order_by: [desc: r.inserted_at, desc: r.id])
        ])
    end
  end

  def list_session_events(session_id, limit \\ 10) when is_integer(session_id) do
    SessionTranscript.recent_events(session_id, limit: limit)
  end

  def transcript_summary(session_id) when is_integer(session_id) do
    SessionTranscript.summary(session_id)
  end

  def workspace_context(session_or_id, opts \\ [])

  def workspace_context(%Session{} = session, opts) do
    fallback_root = Keyword.get(opts, :fallback_root, File.cwd!())

    session
    |> WorkspaceContext.resolve_project_root(fallback_root)
    |> WorkspaceContext.build()
  end

  def workspace_context(session_id, opts) when is_integer(session_id) do
    case get_session(session_id) do
      nil -> WorkspaceContext.build(nil)
      session -> workspace_context(session, opts)
    end
  end

  def find_task_by_runtime_context(agent_id, thread_id, host_session_id \\ nil)

  def find_task_by_runtime_context(agent_id, thread_id, host_session_id)
      when is_binary(agent_id) and is_binary(thread_id) do
    Task
    |> Repo.all()
    |> Enum.find(fn task ->
      runtime_context_matches?(task.metadata, agent_id, thread_id, host_session_id)
    end)
  end

  def find_task_by_runtime_context(_agent_id, _thread_id, _host_session_id), do: nil

  def find_session_by_runtime_context(agent_id, thread_id, host_session_id \\ nil)

  def find_session_by_runtime_context(agent_id, thread_id, host_session_id)
      when is_binary(agent_id) and is_binary(thread_id) do
    Session
    |> Repo.all()
    |> Enum.find(fn session ->
      runtime_context_matches?(session.metadata, agent_id, thread_id, host_session_id)
    end)
  end

  def find_session_by_runtime_context(_agent_id, _thread_id, _host_session_id), do: nil

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

  def security_case_summary(findings) when is_list(findings) do
    cases = Enum.filter(findings, &SecurityWorkflow.vulnerability_case?/1)
    proof = SecurityWorkflow.proof_summary(cases)

    %{
      "case_count" => length(cases),
      "unresolved" => proof["unresolved"],
      "critical_unresolved" => proof["critical_unresolved"],
      "patch_status" => count_by_metadata(cases, "patch_status"),
      "disclosure_status" => count_by_metadata(cases, "disclosure_status"),
      "maintainer_scope" => count_by_metadata(cases, "maintainer_scope"),
      "exploitability_status" => count_by_metadata(cases, "exploitability_status")
    }
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
    security_summary = base_query |> Repo.all() |> security_case_summary()

    entries =
      base_query
      |> order_by([f, _s, _w], desc: f.inserted_at, desc: f.id)
      |> limit(^@findings_page_size)
      |> offset(^((page - 1) * @findings_page_size))
      |> Repo.all()

    %{
      entries: entries,
      filters: %{filters | page: page},
      security_summary: security_summary,
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

  def trace_improvement_packet(session_id, opts \\ []) when is_integer(session_id) do
    with %Session{} = session <- get_session_context(session_id) do
      task_id = Keyword.get(opts, :task_id)
      task = trace_packet_task(session, task_id)

      if is_nil(task) and is_integer(task_id) do
        {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
      else
        invocations = trace_packet_invocations(session, task)
        reviews = trace_packet_reviews(session, task)
        findings = trace_packet_findings(session, task)
        recent_events = list_session_events(session.id, Keyword.get(opts, :events_limit, 25))
        transcript = transcript_summary(session.id)
        latest_proof = trace_packet_proof(task)
        test_outcomes = derive_test_outcomes(invocations)

        verification_assessment =
          cond do
            match?(%ProofBundle{}, latest_proof) and
                is_map(latest_proof.bundle["verification_assessment"]) ->
              latest_proof.bundle["verification_assessment"]

            match?(%Task{}, task) ->
              derive_verification_assessment(task, findings, invocations, reviews, test_outcomes)

            true ->
              nil
          end

        planning_continuity =
          if match?(%Task{}, task) do
            derive_planning_continuity(task, reviews)
          else
            nil
          end

        failure_patterns =
          derive_trace_failure_patterns(
            findings,
            verification_assessment,
            planning_continuity,
            test_outcomes,
            reviews
          )

        {:ok,
         %{
           "session_id" => session.id,
           "session_title" => session.title,
           "task_id" => task && task.id,
           "task_title" => task && task.title,
           "trace_summary" => %{
             "invocations" => length(invocations),
             "reviews" => length(reviews),
             "findings" => length(findings),
             "recent_events" => length(recent_events),
             "proof_available" => not is_nil(latest_proof)
           },
           "trace" => %{
             "invocations" => Enum.map(invocations, &trace_invocation_entry/1),
             "reviews" => Enum.map(reviews, &trace_review_entry/1),
             "findings" => Enum.map(findings, &trace_finding_entry/1),
             "recent_events" => recent_events,
             "transcript_summary" => transcript
           },
           "verification_assessment" => verification_assessment,
           "planning_continuity" => planning_continuity,
           "test_outcomes" => test_outcomes,
           "failure_patterns" => failure_patterns,
           "eval_candidates" => Enum.map(failure_patterns, &trace_eval_candidate/1)
         }}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def failure_mode_clusters(session_id, opts \\ []) when is_integer(session_id) do
    with %Session{} = session <- get_session_with_workspace(session_id) do
      session_limit = Keyword.get(opts, :session_limit, 5)
      same_domain_only = Keyword.get(opts, :same_domain_only, true)
      domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])

      sessions =
        recent_sessions_for_failure_clusters(
          session.workspace_id,
          session.id,
          session_limit,
          same_domain_only,
          domain_pack
        )

      packets =
        Enum.map(sessions, fn cluster_session ->
          {:ok, packet} = trace_improvement_packet(cluster_session.id)
          packet
        end)

      patterns =
        Enum.flat_map(packets, fn packet ->
          Enum.map(packet["failure_patterns"] || [], fn pattern ->
            Map.merge(pattern, %{
              "session_id" => packet["session_id"],
              "session_title" => packet["session_title"],
              "task_id" => packet["task_id"],
              "task_title" => packet["task_title"]
            })
          end)
        end)

      clusters = build_failure_clusters(patterns)

      {:ok,
       %{
         "workspace_id" => session.workspace_id,
         "source_session_id" => session.id,
         "sessions_analyzed" => length(sessions),
         "same_domain_only" => same_domain_only,
         "domain_pack" => domain_pack,
         "cluster_count" => length(clusters),
         "clusters" => clusters,
         "eval_candidates" => Enum.map(clusters, &cluster_eval_candidate/1)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def skill_evolution_packet(session_id, opts \\ []) when is_integer(session_id) do
    with %Session{} = session <- get_session_with_workspace(session_id) do
      session_limit = Keyword.get(opts, :session_limit, 5)
      same_domain_only = Keyword.get(opts, :same_domain_only, true)
      current_skill_name = Keyword.get(opts, :current_skill_name, "trace-evolved-skill")
      current_skill_content = Keyword.get(opts, :current_skill_content, "")
      domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])

      sessions =
        recent_sessions_for_failure_clusters(
          session.workspace_id,
          session.id,
          session_limit,
          same_domain_only,
          domain_pack
        )

      packets =
        Enum.map(sessions, fn skill_session ->
          {:ok, packet} = trace_improvement_packet(skill_session.id)
          packet
        end)

      patterns =
        Enum.flat_map(packets, fn packet ->
          Enum.map(packet["failure_patterns"] || [], fn pattern ->
            Map.merge(pattern, %{
              "session_id" => packet["session_id"],
              "session_title" => packet["session_title"],
              "task_id" => packet["task_id"],
              "task_title" => packet["task_title"]
            })
          end)
        end)

      clusters = build_failure_clusters(patterns)
      anti_patterns = Enum.map(clusters, &skill_anti_pattern/1)
      reinforced_practices = derive_reinforced_practices(packets)

      guidance =
        build_skill_guidance(anti_patterns, reinforced_practices, current_skill_content)

      draft =
        render_evolved_skill_document(
          current_skill_name,
          guidance,
          anti_patterns,
          reinforced_practices,
          packets,
          clusters
        )

      {:ok,
       %{
         "workspace_id" => session.workspace_id,
         "source_session_id" => session.id,
         "same_domain_only" => same_domain_only,
         "domain_pack" => domain_pack,
         "sessions_analyzed" => length(sessions),
         "source_summary" => %{
           "cluster_count" => length(clusters),
           "failure_pattern_count" => length(patterns),
           "strong_runs" =>
             Enum.count(packets, &(get_in(&1, ["verification_assessment", "status"]) == "strong")),
           "weak_runs" =>
             Enum.count(packets, fn packet ->
               get_in(packet, ["verification_assessment", "status"]) in ["weak", nil]
             end)
         },
         "anti_patterns" => anti_patterns,
         "reinforced_practices" => reinforced_practices,
         "guidance" => guidance,
         "merge_strategy" => %{
           "recommendation" =>
             "Prefer updating one strong, deduplicated skill tree instead of adding sibling docs for each failure cluster.",
           "current_skill_name" => current_skill_name,
           "current_skill_supplied" => String.trim(current_skill_content) != "",
           "notes" => [
             "Merge repeated lessons into shared Do/Avoid/Verification sections.",
             "Keep failure-specific examples as evidence, not as competing skill files.",
             "Retire overlapping guidance once the consolidated skill draft absorbs it."
           ]
         },
         "suggested_skill_document" => draft
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def experience_history_index(session_id, opts \\ []) when is_integer(session_id) do
    with %Session{} = session <- get_session_with_workspace(session_id) do
      session_limit = Keyword.get(opts, :session_limit, 10)
      same_domain_only = Keyword.get(opts, :same_domain_only, true)
      domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])

      sessions =
        recent_sessions_for_failure_clusters(
          session.workspace_id,
          session.id,
          session_limit,
          same_domain_only,
          domain_pack
        )
        |> Enum.map(&get_session_context(&1.id))
        |> Enum.reject(&is_nil/1)

      {:ok,
       %{
         "workspace_id" => session.workspace_id,
         "source_session_id" => session.id,
         "same_domain_only" => same_domain_only,
         "domain_pack" => domain_pack,
         "sessions_analyzed" => length(sessions),
         "artifact_types" => ["session_summary", "audit_log", "trace_packet", "proof_summary"],
         "sessions" => Enum.map(sessions, &experience_index_entry/1),
         "usage_hint" =>
           "Call ck_experience_read with a source_session_id and artifact_type to inspect one prior run in detail."
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def experience_history_read(session_id, opts \\ []) when is_integer(session_id) do
    with %Session{} = session <- get_session_with_workspace(session_id),
         {:ok, target_session} <- experience_target_session(session, opts),
         {:ok, artifact_type} <- experience_artifact_type(opts),
         {:ok, artifact} <- experience_artifact(target_session, artifact_type, opts) do
      {:ok,
       %{
         "workspace_id" => session.workspace_id,
         "source_session_id" => session.id,
         "target_session_id" => target_session.id,
         "artifact_type" => artifact_type,
         "content" => encode_pretty_json(artifact),
         "structured_content" => artifact
       }}
    else
      _ -> {:error, :not_found}
    end
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

      reviews =
        Repo.all(from(r in Review, where: r.session_id == ^session_id, order_by: r.inserted_at))

      tasks =
        Repo.all(from(t in Task, where: t.session_id == ^session_id, order_by: t.position))

      events =
        (Enum.map(invocations, &audit_invocation_entry/1) ++
           Enum.map(findings, &audit_finding_entry/1) ++
           Enum.flat_map(reviews, &audit_review_entries/1))
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
           total_reviews: length(reviews),
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

  defp trace_packet_task(_session, nil), do: nil

  defp trace_packet_task(%Session{} = session, task_id) do
    Enum.find(session.tasks || [], &(&1.id == task_id))
  end

  defp trace_packet_invocations(%Session{} = session, nil), do: session.invocations || []

  defp trace_packet_invocations(%Session{} = session, %Task{id: task_id}) do
    Enum.filter(session.invocations || [], &(&1.task_id == task_id))
  end

  defp trace_packet_reviews(%Session{} = session, nil), do: session.reviews || []

  defp trace_packet_reviews(%Session{} = session, %Task{id: task_id}) do
    Enum.filter(session.reviews || [], &(&1.task_id == task_id))
  end

  defp trace_packet_findings(%Session{} = session, nil), do: session.findings || []

  defp trace_packet_findings(%Session{} = session, %Task{id: task_id}) do
    Enum.filter(session.findings || [], fn finding ->
      get_in(finding.metadata || %{}, ["task_id"]) == task_id
    end)
  end

  defp trace_packet_proof(nil), do: nil

  defp trace_packet_proof(%Task{id: task_id}) do
    latest_proof_bundle_for_task(task_id)
  end

  defp trace_invocation_entry(invocation) do
    %{
      "id" => invocation.id,
      "source" => invocation.source,
      "tool" => invocation.tool,
      "provider" => invocation.provider,
      "decision" => invocation.decision,
      "task_id" => invocation.task_id,
      "estimated_cost_cents" => invocation.estimated_cost_cents,
      "inserted_at" => invocation.inserted_at,
      "metadata" => invocation.metadata || %{}
    }
  end

  defp trace_review_entry(review) do
    %{
      "id" => review.id,
      "review_type" => review.review_type,
      "status" => review.status,
      "task_id" => review.task_id,
      "feedback_notes" => review.feedback_notes,
      "annotations" => review.annotations || %{},
      "plan_refinement" => get_in(review.metadata || %{}, ["plan_refinement"]) || %{},
      "inserted_at" => review.inserted_at
    }
  end

  defp trace_finding_entry(finding) do
    %{
      "id" => finding.id,
      "rule_id" => finding.rule_id,
      "title" => finding.title,
      "category" => finding.category,
      "severity" => finding.severity,
      "status" => finding.status,
      "plain_message" => finding.plain_message,
      "task_id" => get_in(finding.metadata || %{}, ["task_id"]),
      "inserted_at" => finding.inserted_at
    }
  end

  defp derive_trace_failure_patterns(
         findings,
         verification_assessment,
         planning_continuity,
         test_outcomes,
         reviews
       ) do
    finding_patterns =
      findings
      |> Enum.filter(&(&1.status in ["open", "blocked", "escalated"]))
      |> Enum.map(fn finding ->
        %{
          "type" => "finding",
          "code" => finding.rule_id,
          "title" => finding.title,
          "severity" => finding.severity,
          "summary" => finding.plain_message,
          "source_id" => finding.id
        }
      end)

    verification_patterns =
      verification_assessment
      |> case do
        %{"suspicious_test_changes" => suspicious} when is_list(suspicious) ->
          Enum.map(suspicious, fn signal ->
            %{
              "type" => "verification",
              "code" => signal["code"],
              "title" => signal["summary"],
              "severity" => signal["severity"] || "medium",
              "summary" => signal["recommendation"] || signal["summary"],
              "source_id" => signal["review_id"]
            }
          end)

        _ ->
          []
      end

    planning_patterns =
      planning_continuity
      |> case do
        %{"drift_signals" => signals} when is_list(signals) ->
          Enum.map(signals, fn signal ->
            %{
              "type" => "planning",
              "code" => signal["code"],
              "title" => signal["summary"],
              "severity" => "medium",
              "summary" => signal["summary"],
              "source_id" => planning_continuity["approved_plan_review_id"]
            }
          end)

        _ ->
          []
      end

    regression_patterns =
      (test_outcomes["latest_failures"] || [])
      |> Enum.map(fn failure ->
        %{
          "type" => "regression",
          "code" => "external_regression_failure",
          "title" => failure["flow_name"] || "External regression failure",
          "severity" => if(failure["outcome"] == "flaky", do: "medium", else: "high"),
          "summary" => failure["summary"] || "Regression evidence failed.",
          "source_id" => failure["external_run_id"]
        }
      end)

    denied_review_patterns =
      reviews
      |> Enum.filter(&(&1.status == "denied"))
      |> Enum.map(fn review ->
        %{
          "type" => "review",
          "code" => "review_denied",
          "title" => review.title,
          "severity" => "medium",
          "summary" => review.feedback_notes || "A human denied this review.",
          "source_id" => review.id
        }
      end)

    finding_patterns ++
      verification_patterns ++ planning_patterns ++ regression_patterns ++ denied_review_patterns
  end

  defp trace_eval_candidate(pattern) do
    %{
      "pattern_type" => pattern["type"],
      "source_code" => pattern["code"],
      "title" => eval_title(pattern),
      "why" => pattern["summary"],
      "suggested_check_type" => eval_check_type(pattern),
      "assertion_hint" => eval_assertion_hint(pattern),
      "source_id" => pattern["source_id"]
    }
  end

  defp recent_sessions_for_failure_clusters(
         workspace_id,
         source_session_id,
         session_limit,
         same_domain_only,
         domain_pack
       ) do
    sessions =
      Session
      |> where([session], session.workspace_id == ^workspace_id)
      |> order_by([session], desc: session.inserted_at, desc: session.id)
      |> limit(^max(session_limit, 1))
      |> Repo.all()

    sessions
    |> Enum.reject(&is_nil(&1.workspace_id))
    |> Enum.filter(fn candidate ->
      candidate.id == source_session_id or
        not same_domain_only or
        get_in(candidate.execution_brief || %{}, ["domain_pack"]) == domain_pack
    end)
  end

  defp build_failure_clusters(patterns) do
    patterns
    |> Enum.group_by(fn pattern -> {pattern["type"], pattern["code"]} end)
    |> Enum.map(fn {{type, code}, rows} ->
      severity = rows |> Enum.map(&(&1["severity"] || "low")) |> Enum.max_by(&severity_rank/1)
      sessions = rows |> Enum.map(& &1["session_id"]) |> Enum.uniq()
      titles = rows |> Enum.map(& &1["title"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      %{
        "type" => type,
        "code" => code,
        "severity" => severity,
        "count" => length(rows),
        "session_count" => length(sessions),
        "titles" => Enum.take(titles, 3),
        "summary" => cluster_summary(rows),
        "examples" =>
          rows
          |> Enum.take(3)
          |> Enum.map(fn row ->
            %{
              "session_id" => row["session_id"],
              "session_title" => row["session_title"],
              "task_id" => row["task_id"],
              "task_title" => row["task_title"],
              "source_id" => row["source_id"],
              "summary" => row["summary"]
            }
          end)
      }
    end)
    |> Enum.sort_by(fn cluster ->
      {-severity_rank(cluster["severity"]), -cluster["count"], cluster["code"]}
    end)
  end

  defp cluster_eval_candidate(cluster) do
    %{
      "cluster_code" => cluster["code"],
      "pattern_type" => cluster["type"],
      "title" => "Cluster regression: #{List.first(cluster["titles"]) || cluster["code"]}",
      "suggested_check_type" => eval_check_type(%{"type" => cluster["type"]}),
      "assertion_hint" =>
        "Add an eval that prevents recurrence of `#{cluster["code"]}` across similar traces.",
      "session_count" => cluster["session_count"],
      "example_source_ids" =>
        Enum.map(cluster["examples"] || [], & &1["source_id"]) |> Enum.reject(&is_nil/1)
    }
  end

  defp skill_anti_pattern(cluster) do
    %{
      "code" => cluster["code"],
      "type" => cluster["type"],
      "severity" => cluster["severity"],
      "summary" => cluster["summary"],
      "do" => anti_pattern_do_line(cluster),
      "avoid" => anti_pattern_avoid_line(cluster),
      "verify" => anti_pattern_verify_line(cluster),
      "session_count" => cluster["session_count"],
      "count" => cluster["count"],
      "titles" => cluster["titles"],
      "example_source_ids" =>
        Enum.map(cluster["examples"] || [], & &1["source_id"]) |> Enum.reject(&is_nil/1)
    }
  end

  defp anti_pattern_do_line(%{"type" => "finding", "code" => code}) do
    cond do
      String.contains?(code, "sql_injection") ->
        "Use parameterized queries and keep untrusted input out of query string assembly."

      String.contains?(code, "auth") or String.contains?(code, "access") ->
        "Make authorization checks explicit at the boundary where privileged state changes occur."

      true ->
        "Encode the guardrail for `#{code}` directly in the main workflow instead of relying on memory."
    end
  end

  defp anti_pattern_do_line(%{"type" => "verification", "code" => code}) do
    cond do
      String.contains?(code, "skip") or String.contains?(code, "focused") ->
        "Keep the full intended test surface active when validating a fix."

      String.contains?(code, "assertion") ->
        "Preserve strong assertions that prove the behavior instead of only checking execution success."

      String.contains?(code, "mock") ->
        "Use mocks as seams, not as substitutes for the behavior the change is supposed to prove."

      true ->
        "Tighten verification around `#{code}` with objective checks that are hard to game."
    end
  end

  defp anti_pattern_do_line(%{"type" => "planning"}) do
    "Carry design choices, rejected options, and implementation boundaries forward into execution."
  end

  defp anti_pattern_do_line(%{"type" => "regression"}) do
    "Promote recurrent external regression failures into named flow checks owned by the main skill."
  end

  defp anti_pattern_do_line(%{"type" => "review"}) do
    "Add explicit human-review checkpoints where the same denial pattern keeps recurring."
  end

  defp anti_pattern_do_line(%{"code" => code}) do
    "Add an explicit workflow rule that prevents recurrence of `#{code}`."
  end

  defp anti_pattern_avoid_line(%{"type" => "finding", "code" => code}) do
    cond do
      String.contains?(code, "sql_injection") ->
        "Avoid raw SQL concatenation and other string-built query paths."

      true ->
        "Avoid leaving `#{code}` prevention implicit or scattered across multiple docs."
    end
  end

  defp anti_pattern_avoid_line(%{"type" => "verification", "code" => code}) do
    cond do
      String.contains?(code, "skip") or String.contains?(code, "focused") ->
        "Avoid skipping, narrowing, or focusing tests just to get a green run."

      String.contains?(code, "assertion") ->
        "Avoid removing assertions that are carrying behavioral proof."

      String.contains?(code, "mock") ->
        "Avoid inflating mocks until the test only proves the mock."

      true ->
        "Avoid verification drift around `#{code}`."
    end
  end

  defp anti_pattern_avoid_line(%{"type" => "planning"}) do
    "Avoid jumping from a vague ticket to implementation without a narrowed design decision."
  end

  defp anti_pattern_avoid_line(%{"type" => "regression"}) do
    "Avoid treating flaky or failed external runs as non-signals."
  end

  defp anti_pattern_avoid_line(%{"type" => "review"}) do
    "Avoid repeating a denied pattern without turning it into a permanent gate."
  end

  defp anti_pattern_avoid_line(%{"code" => code}) do
    "Avoid letting `#{code}` remain a one-off lesson."
  end

  defp anti_pattern_verify_line(%{"type" => "finding", "code" => code}) do
    cond do
      String.contains?(code, "sql_injection") ->
        "Validate with deterministic query-safety checks and regression coverage on the affected path."

      true ->
        "Add a reusable eval or scanner rule for `#{code}` and keep it in the permanent suite."
    end
  end

  defp anti_pattern_verify_line(%{"type" => "verification"}) do
    "Review the diff for proof laundering and require assertions, active tests, and meaningful coverage to remain intact."
  end

  defp anti_pattern_verify_line(%{"type" => "planning"}) do
    "Check that implementation and proof both reference the approved plan phase and boundary decisions."
  end

  defp anti_pattern_verify_line(%{"type" => "regression"}) do
    "Replay the affected user flow through external regression tooling before marking the task ready."
  end

  defp anti_pattern_verify_line(%{"type" => "review"}) do
    "Require a human-approved review artifact before rollout when this denial mode appears."
  end

  defp anti_pattern_verify_line(%{"code" => code}) do
    "Turn `#{code}` into a durable eval candidate and keep it in the regression suite."
  end

  defp derive_reinforced_practices(packets) do
    packets
    |> Enum.flat_map(fn packet ->
      verification = packet["verification_assessment"] || %{}
      evidence_sources = get_in(verification, ["evidence", "evidence_sources"]) || []
      status = verification["status"]
      failures = packet["failure_patterns"] || []

      []
      |> maybe_add_reinforced_practice(
        status == "strong" and "internal_checks" in evidence_sources,
        "Keep internal checks as first-pass proof before escalating to richer review or regression layers."
      )
      |> maybe_add_reinforced_practice(
        status == "strong" and "external_regression" in evidence_sources,
        "Preserve external regression coverage for critical user flows once it exists."
      )
      |> maybe_add_reinforced_practice(
        status == "strong" and "human_review" in evidence_sources,
        "Retain human review as a calibrating signal on high-risk or ambiguous tasks."
      )
      |> maybe_add_reinforced_practice(
        failures == [] and status in ["strong", "moderate"],
        "Promote clean, low-drift runs into the main skill instead of leaving them as isolated successful traces."
      )
    end)
    |> Enum.uniq()
    |> Enum.map(fn summary ->
      %{"summary" => summary}
    end)
  end

  defp maybe_add_reinforced_practice(list, true, summary), do: [summary | list]
  defp maybe_add_reinforced_practice(list, false, _summary), do: list

  defp build_skill_guidance(anti_patterns, reinforced_practices, current_skill_content) do
    existing = normalized_sentences(current_skill_content)

    %{
      "do" =>
        anti_patterns
        |> Enum.map(& &1["do"])
        |> Kernel.++(Enum.map(reinforced_practices, & &1["summary"]))
        |> dedupe_guidance(existing),
      "avoid" =>
        anti_patterns
        |> Enum.map(& &1["avoid"])
        |> dedupe_guidance(existing),
      "verify" =>
        anti_patterns
        |> Enum.map(& &1["verify"])
        |> dedupe_guidance(existing)
    }
  end

  defp dedupe_guidance(lines, existing) do
    lines
    |> Enum.reject(&is_nil_or_blank/1)
    |> Enum.uniq()
    |> Enum.reject(fn line -> normalize_sentence(line) in existing end)
  end

  defp normalized_sentences(content) when is_binary(content) do
    content
    |> String.split(~r/[\n\r]+/, trim: true)
    |> Enum.map(&normalize_sentence/1)
    |> MapSet.new()
  end

  defp normalized_sentences(_), do: MapSet.new()

  defp normalize_sentence(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  defp render_evolved_skill_document(
         skill_name,
         guidance,
         anti_patterns,
         reinforced_practices,
         packets,
         clusters
       ) do
    description =
      "Evolved from ControlKeel traces. Use when similar recurring failures, regressions, or planning drift patterns are present."

    [
      "---",
      "name: #{skill_name}",
      "description: #{description}",
      "---",
      "",
      "# #{humanize_skill_name(skill_name)}",
      "",
      "## Instructions",
      "",
      "Prefer one consolidated workflow over many overlapping notes. Update this skill when new recurring failures appear instead of spawning sibling docs.",
      "",
      "## Do",
      render_bullet_lines(guidance["do"]),
      "",
      "## Avoid",
      render_bullet_lines(guidance["avoid"]),
      "",
      "## Verification",
      render_numbered_lines(guidance["verify"]),
      "",
      "## Failure Patterns Observed",
      render_cluster_lines(clusters),
      "",
      "## Reinforced Practices",
      render_bullet_lines(Enum.map(reinforced_practices, & &1["summary"])),
      "",
      "## Trace Provenance",
      "- Sessions analyzed: #{length(packets)}",
      "- Recurring clusters: #{length(clusters)}",
      "- Anti-patterns distilled: #{length(anti_patterns)}"
    ]
    |> Enum.join("\n")
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp render_bullet_lines([]), do: "- No new guidance synthesized.\n"
  defp render_bullet_lines(lines), do: Enum.map_join(lines, "\n", &"- #{&1}")

  defp render_numbered_lines([]), do: "1. Run the existing verification suite.\n"

  defp render_numbered_lines(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {line, idx} -> "#{idx}. #{line}" end)
  end

  defp render_cluster_lines([]), do: "- No recurring failure clusters detected.\n"

  defp render_cluster_lines(clusters) do
    Enum.map_join(clusters, "\n", fn cluster ->
      title = List.first(cluster["titles"] || []) || cluster["code"]
      "- #{title} (`#{cluster["code"]}`) across #{cluster["session_count"]} session(s)"
    end)
  end

  defp humanize_skill_name(name) do
    name
    |> to_string()
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp is_nil_or_blank(nil), do: true
  defp is_nil_or_blank(text) when is_binary(text), do: String.trim(text) == ""
  defp is_nil_or_blank(_), do: false

  defp experience_index_entry(%Session{} = session) do
    tasks = session.tasks || []
    findings = session.findings || []
    reviews = session.reviews || []
    invocations = session.invocations || []
    latest_task = List.first(tasks)

    %{
      "session_id" => session.id,
      "title" => session.title,
      "inserted_at" => session.inserted_at,
      "risk_tier" => session.risk_tier,
      "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"]),
      "task_count" => length(tasks),
      "finding_count" => length(findings),
      "review_count" => length(reviews),
      "invocation_count" => length(invocations),
      "latest_task" =>
        if(latest_task,
          do: %{
            "task_id" => latest_task.id,
            "title" => latest_task.title,
            "status" => latest_task.status,
            "proof_summary" => proof_summary_for_task(latest_task)
          },
          else: nil
        ),
      "artifacts" =>
        [
          %{"artifact_type" => "session_summary", "source_session_id" => session.id},
          %{"artifact_type" => "audit_log", "source_session_id" => session.id}
        ] ++ experience_task_artifacts(latest_task)
    }
  end

  defp experience_task_artifacts(nil), do: []

  defp experience_task_artifacts(%Task{} = task) do
    [
      %{
        "artifact_type" => "trace_packet",
        "source_session_id" => task.session_id,
        "task_id" => task.id
      },
      %{
        "artifact_type" => "proof_summary",
        "source_session_id" => task.session_id,
        "task_id" => task.id
      }
    ]
  end

  defp experience_target_session(%Session{} = source_session, opts) do
    target_session_id = Keyword.get(opts, :source_session_id, source_session.id)

    case get_session_context(target_session_id) do
      %Session{} = target_session
      when target_session.workspace_id == source_session.workspace_id ->
        {:ok, target_session}

      _ ->
        {:error, :not_found}
    end
  end

  defp experience_artifact_type(opts) do
    case Keyword.get(opts, :artifact_type) do
      type when type in ["session_summary", "audit_log", "trace_packet", "proof_summary"] ->
        {:ok, type}

      nil ->
        {:error, :not_found}

      _other ->
        {:error, :not_found}
    end
  end

  defp experience_artifact(%Session{} = session, "session_summary", _opts) do
    {:ok, experience_index_entry(session)}
  end

  defp experience_artifact(%Session{} = session, "audit_log", _opts) do
    audit_log(session.id)
  end

  defp experience_artifact(%Session{} = session, "trace_packet", opts) do
    with {:ok, task_id} <- experience_task_id(session, opts) do
      trace_improvement_packet(session.id, task_id: task_id, events_limit: 50)
    end
  end

  defp experience_artifact(%Session{} = session, "proof_summary", opts) do
    with {:ok, task_id} <- experience_task_id(session, opts) do
      {:ok,
       %{
         "task_id" => task_id,
         "task_title" => task_title(session.tasks || [], task_id),
         "proof_summary" => proof_summary_for_task(task_id)
       }}
    end
  end

  defp experience_task_id(%Session{} = session, opts) do
    task_id =
      Keyword.get(opts, :task_id) ||
        case session.tasks || [] do
          [%Task{id: id} | _] -> id
          _ -> nil
        end

    cond do
      is_nil(task_id) ->
        {:error, :not_found}

      Enum.any?(session.tasks || [], &(&1.id == task_id)) ->
        {:ok, task_id}

      true ->
        {:error, :not_found}
    end
  end

  defp task_title(tasks, task_id) do
    tasks
    |> Enum.find(&(&1.id == task_id))
    |> case do
      %Task{title: title} -> title
      _ -> nil
    end
  end

  defp encode_pretty_json(data) do
    Jason.encode!(data, pretty: true)
  end

  defp cluster_summary(rows) do
    rows
    |> Enum.map(& &1["summary"])
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_summary, count} -> count end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp severity_rank("critical"), do: 4
  defp severity_rank("high"), do: 3
  defp severity_rank("medium"), do: 2
  defp severity_rank("low"), do: 1
  defp severity_rank(_other), do: 0

  defp eval_title(%{"type" => "finding", "title" => title}), do: "Prevent recurrence: #{title}"
  defp eval_title(%{"type" => "regression", "title" => title}), do: "Regression case: #{title}"
  defp eval_title(%{"type" => "planning", "title" => title}), do: "Plan alignment: #{title}"
  defp eval_title(%{"title" => title}), do: title

  defp eval_check_type(%{"type" => "finding"}), do: "deterministic_rule"
  defp eval_check_type(%{"type" => "verification"}), do: "trace_verification"
  defp eval_check_type(%{"type" => "planning"}), do: "plan_alignment"
  defp eval_check_type(%{"type" => "regression"}), do: "regression_replay"
  defp eval_check_type(%{"type" => "review"}), do: "human_review_regression"
  defp eval_check_type(_pattern), do: "behavior_check"

  defp eval_assertion_hint(%{"type" => "finding", "code" => code}) do
    "Ensure future runs do not reproduce finding `#{code}` on similar inputs."
  end

  defp eval_assertion_hint(%{"type" => "verification", "code" => code}) do
    "Verify the trace does not contain suspicious verification signal `#{code}`."
  end

  defp eval_assertion_hint(%{"type" => "planning", "code" => code}) do
    "Verify implementation traces stay aligned with approved plan constraints and avoid `#{code}`."
  end

  defp eval_assertion_hint(%{"type" => "regression", "title" => title}) do
    "Replay the failing flow `#{title}` and require a passing outcome."
  end

  defp eval_assertion_hint(%{"type" => "review"}) do
    "The updated run should address the denial feedback and pass human review."
  end

  defp eval_assertion_hint(_pattern), do: "Convert this failure pattern into a reusable eval."

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
    regression_runs = Enum.filter(invocations, &regression_invocation?/1)

    flaky =
      Enum.count(regression_runs, &(get_in(&1.metadata, ["regression", "outcome"]) == "flaky"))

    skipped =
      Enum.count(regression_runs, &(get_in(&1.metadata, ["regression", "outcome"]) == "skipped"))

    engines =
      regression_runs
      |> Enum.group_by(&(get_in(&1.metadata, ["regression", "engine"]) || "unknown"))
      |> Enum.into(%{}, fn {engine, rows} -> {engine, length(rows)} end)

    latest_failures =
      regression_runs
      |> Enum.filter(fn invocation ->
        get_in(invocation.metadata, ["regression", "outcome"]) in ["failed", "flaky"]
      end)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(5)
      |> Enum.map(fn invocation ->
        regression = invocation.metadata["regression"] || %{}

        %{
          "flow_name" => regression["flow_name"],
          "engine" => regression["engine"],
          "outcome" => regression["outcome"],
          "summary" => regression["summary"],
          "commit_sha" => regression["commit_sha"],
          "external_run_id" => regression["external_run_id"],
          "evidence" => regression["evidence"] || %{},
          "recorded_at" => invocation.inserted_at
        }
      end)

    %{
      "passed" => passed,
      "failed" => failed,
      "recorded" => length(invocations),
      "external_recorded" => length(regression_runs),
      "flaky" => flaky,
      "skipped" => skipped,
      "blocking_failures" => failed + flaky,
      "engines" => engines,
      "latest_failures" => latest_failures
    }
  end

  defp derive_verification_assessment(task, findings, invocations, reviews, test_outcomes) do
    suspicious_test_changes = suspicious_test_changes(reviews)
    approved_reviews = Enum.count(reviews, &(&1.status == "approved"))
    passed_checks = Enum.count(invocations, &(get_in(&1.metadata, ["outcome"]) == "passed"))
    external_regressions = test_outcomes["external_recorded"] || 0
    blocking_failures = test_outcomes["blocking_failures"] || 0
    skipped = test_outcomes["skipped"] || 0
    open_or_blocked = Enum.count(findings, &(&1.status in ["open", "blocked"]))

    evidence_sources =
      []
      |> maybe_add_evidence_source(passed_checks > 0, "internal_checks")
      |> maybe_add_evidence_source(external_regressions > 0, "external_regression")
      |> maybe_add_evidence_source(approved_reviews > 0, "human_review")

    score =
      0
      |> maybe_add_score(task.status == "done", 10)
      |> maybe_add_score(passed_checks > 0, 20)
      |> maybe_add_score(external_regressions > 0 and blocking_failures == 0, 30)
      |> maybe_add_score(approved_reviews > 0, 20)
      |> maybe_add_score(open_or_blocked == 0, 10)
      |> maybe_add_score(length(evidence_sources) >= 2, 10)
      |> maybe_subtract_score(blocking_failures > 0, 35)
      |> maybe_subtract_score(skipped > 0, 10)
      |> maybe_subtract_score(has_suspicious_severity?(suspicious_test_changes, "high"), 30)
      |> maybe_subtract_score(has_suspicious_severity?(suspicious_test_changes, "medium"), 10)
      |> clamp_score()

    %{
      "score" => score,
      "status" => verification_status(score),
      "verification_ready" =>
        blocking_failures == 0 and not has_suspicious_severity?(suspicious_test_changes, "high"),
      "evidence" => %{
        "passed_checks" => passed_checks,
        "external_regressions" => external_regressions,
        "approved_reviews" => approved_reviews,
        "evidence_sources" => evidence_sources
      },
      "signals" =>
        verification_signals(
          score,
          evidence_sources,
          blocking_failures,
          skipped,
          suspicious_test_changes
        ),
      "suspicious_test_changes" => suspicious_test_changes
    }
  end

  defp derive_planning_continuity(task, reviews) do
    latest_plan = Enum.find(reviews, &(&1.review_type == "plan"))

    approved_plan =
      Enum.find(reviews, &(&1.review_type == "plan" and &1.status == "approved"))

    latest_execution_review =
      Enum.find(reviews, &(&1.review_type in ["diff", "completion"]))

    approved_refinement =
      get_in(approved_plan || %{}, [Access.key(:metadata), "plan_refinement"]) || %{}

    approved_quality = approved_refinement["quality"] || %{}
    execution_ready_plan = plan_execution_ready?(approved_refinement, approved_quality)

    linked_execution_review? =
      case {latest_execution_review, approved_plan} do
        {%Review{} = execution_review, %Review{} = plan_review} ->
          review_lineage_includes?(execution_review, plan_review.id, reviews)

        _ ->
          nil
      end

    drift_signals =
      []
      |> maybe_put_planning_signal(
        task.status == "done" and is_nil(approved_plan),
        "no_approved_plan",
        "Task completed without an approved plan review."
      )
      |> maybe_put_planning_signal(
        (task.status == "done" and approved_plan) && not execution_ready_plan,
        "approved_plan_not_execution_ready",
        "The latest approved plan did not reach an execution-ready refinement phase."
      )
      |> maybe_put_planning_signal(
        latest_execution_review && approved_plan && linked_execution_review? == false,
        "execution_review_unlinked",
        "Later diff/completion review is not linked back to the approved plan review."
      )
      |> maybe_put_planning_signal(
        match?(%Review{review_type: "plan", status: "denied"}, latest_plan),
        "latest_plan_denied",
        "The latest plan review was denied, so implementation drift is likely."
      )

    status =
      cond do
        execution_ready_plan and linked_execution_review? in [true, nil] and drift_signals == [] ->
          "aligned"

        approved_plan ->
          "partial"

        true ->
          "missing"
      end

    %{
      "status" => status,
      "execution_aligned" => status == "aligned",
      "latest_plan_review_id" => latest_plan && latest_plan.id,
      "latest_plan_phase" =>
        get_in(latest_plan || %{}, [Access.key(:metadata), "plan_refinement", "phase"]),
      "latest_plan_depth" =>
        get_in(latest_plan || %{}, [Access.key(:metadata), "plan_refinement", "depth"]),
      "approved_plan_review_id" => approved_plan && approved_plan.id,
      "approved_plan_phase" => approved_refinement["phase"],
      "approved_plan_depth" => approved_refinement["depth"],
      "approved_plan_ready" => execution_ready_plan,
      "execution_review_id" => latest_execution_review && latest_execution_review.id,
      "execution_review_linked" => linked_execution_review?,
      "drift_signals" => drift_signals
    }
  end

  defp maybe_put_planning_signal(signals, nil, _code, _summary), do: signals
  defp maybe_put_planning_signal(signals, false, _code, _summary), do: signals

  defp maybe_put_planning_signal(signals, true, code, summary) do
    [%{"code" => code, "summary" => summary} | signals]
  end

  defp review_lineage_includes?(%Review{} = review, target_review_id, reviews) do
    reviews_by_id = Map.new(reviews, &{&1.id, &1})

    Stream.unfold(review.previous_review_id, fn
      nil ->
        nil

      review_id ->
        {review_id,
         Map.get(reviews_by_id, review_id) && Map.get(reviews_by_id, review_id).previous_review_id}
    end)
    |> Enum.member?(target_review_id)
  end

  defp suspicious_test_changes(reviews) do
    reviews
    |> Enum.filter(&(&1.review_type in ["diff", "completion"]))
    |> Enum.flat_map(fn review ->
      review.submission_body
      |> diff_file_changes()
      |> Enum.flat_map(&suspicious_signals_for_file(&1, review))
    end)
    |> Enum.uniq_by(&Map.take(&1, ["code", "file", "line"]))
  end

  defp diff_file_changes(body) when is_binary(body) do
    body
    |> String.split("\n", trim: false)
    |> Enum.reduce({nil, []}, fn line, {current_file, acc} ->
      cond do
        String.starts_with?(line, "diff --git ") ->
          file = diff_file_path(line)
          {file, maybe_start_file_entry(acc, file)}

        String.starts_with?(line, "+++ b/") ->
          file = String.replace_prefix(line, "+++ b/", "")
          {file, maybe_start_file_entry(acc, file)}

        current_file && String.starts_with?(line, "+") && not String.starts_with?(line, "+++") ->
          {current_file,
           update_file_entry(acc, current_file, :added, String.trim_leading(line, "+"))}

        current_file && String.starts_with?(line, "-") && not String.starts_with?(line, "---") ->
          {current_file,
           update_file_entry(acc, current_file, :removed, String.trim_leading(line, "-"))}

        true ->
          {current_file, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.filter(&test_related_file?(&1["file"]))
  end

  defp diff_file_changes(_body), do: []

  defp maybe_start_file_entry(entries, nil), do: entries

  defp maybe_start_file_entry(entries, file) do
    if Enum.any?(entries, &(&1["file"] == file)) do
      entries
    else
      [%{"file" => file, "added" => [], "removed" => []} | entries]
    end
  end

  defp update_file_entry(entries, file, key, line) do
    Enum.map(entries, fn entry ->
      if entry["file"] == file do
        Map.update!(entry, Atom.to_string(key), &[line | &1])
      else
        entry
      end
    end)
  end

  defp suspicious_signals_for_file(file_change, review) do
    added = Enum.reverse(file_change["added"] || [])
    removed = Enum.reverse(file_change["removed"] || [])
    file = file_change["file"]

    []
    |> maybe_add_suspicious_signal(
      Enum.find(added, &skip_added?/1),
      "test_skip_added",
      "high",
      file,
      review.id,
      "The diff adds a skipped test marker in #{file}. This can make green checks less trustworthy."
    )
    |> maybe_add_suspicious_signal(
      Enum.find(added, &focus_added?/1),
      "test_focus_added",
      "high",
      file,
      review.id,
      "The diff adds a focused test marker in #{file}. Focused tests can hide broader regressions in CI."
    )
    |> maybe_add_suspicious_signal(
      Enum.find(removed, &assertion_removed?/1),
      "assertion_removed",
      "medium",
      file,
      review.id,
      "The diff removes an assertion from #{file}. Passing tests may no longer prove the same behavior."
    )
    |> maybe_add_suspicious_signal(
      Enum.find(added, &mock_heavy_added?/1),
      "mock_intensity_increase",
      "low",
      file,
      review.id,
      "The diff increases mocks or stubs in #{file}. Check that verification still exercises real behavior."
    )
  end

  defp maybe_add_suspicious_signal(signals, nil, _code, _severity, _file, _review_id, _summary),
    do: signals

  defp maybe_add_suspicious_signal(signals, line, code, severity, file, review_id, summary) do
    [
      %{
        "code" => code,
        "severity" => severity,
        "file" => file,
        "review_id" => review_id,
        "line" => String.trim(line),
        "summary" => summary
      }
      | signals
    ]
  end

  defp diff_file_path(line) do
    case String.split(line, " ", parts: 4) do
      ["diff", "--git", _old, "b/" <> file] -> file
      _other -> nil
    end
  end

  defp test_related_file?(file) when is_binary(file) do
    String.contains?(file, "/test/") or
      String.contains?(file, "/tests/") or
      String.contains?(file, "/spec/") or
      String.contains?(file, "/__tests__/") or
      String.ends_with?(file, "_test.exs") or
      String.ends_with?(file, ".spec.js") or
      String.ends_with?(file, ".spec.ts") or
      String.ends_with?(file, ".test.js") or
      String.ends_with?(file, ".test.ts") or
      String.ends_with?(file, ".test.tsx") or
      String.ends_with?(file, ".test.jsx")
  end

  defp test_related_file?(_file), do: false

  defp skip_added?(line) do
    Regex.match?(~r/\b(?:it|test|describe|context)\.skip\b/, line) or
      Regex.match?(~r/\bx(?:it|describe|context)\b/, line) or
      Regex.match?(~r/@tag\s+:skip\b/, line) or
      Regex.match?(~r/@tag\s+skip:\s*true\b/, line) or
      Regex.match?(~r/@pytest\.mark\.skip\b/, line) or
      Regex.match?(~r/\bpending\b/, line)
  end

  defp focus_added?(line) do
    Regex.match?(~r/\b(?:it|test|describe|context)\.only\b/, line) or
      Regex.match?(~r/\bf(?:it|describe|context)\b/, line) or
      Regex.match?(~r/@tag\s+:focus\b/, line) or
      Regex.match?(~r/@tag\s+focus:\s*true\b/, line) or
      Regex.match?(~r/\bonly:\s*true\b/, line)
  end

  defp assertion_removed?(line) do
    Regex.match?(~r/\b(assert|refute|expect|toEqual|toBe|should)\b/, line)
  end

  defp mock_heavy_added?(line) do
    Regex.match?(~r/\b(mock|stub|spy|fake|allow\(|double\(|patch\()\b/i, line)
  end

  defp maybe_add_evidence_source(sources, true, source), do: sources ++ [source]
  defp maybe_add_evidence_source(sources, false, _source), do: sources

  defp maybe_add_score(score, true, amount), do: score + amount
  defp maybe_add_score(score, false, _amount), do: score
  defp maybe_subtract_score(score, true, amount), do: score - amount
  defp maybe_subtract_score(score, false, _amount), do: score
  defp clamp_score(score), do: score |> max(0) |> min(100)

  defp verification_status(score) when score >= 70, do: "strong"
  defp verification_status(score) when score >= 45, do: "moderate"
  defp verification_status(_score), do: "weak"

  defp has_suspicious_severity?(signals, severity) do
    Enum.any?(signals, &(&1["severity"] == severity))
  end

  defp verification_signals(
         score,
         evidence_sources,
         blocking_failures,
         skipped,
         suspicious_test_changes
       ) do
    []
    |> maybe_add_verification_signal(
      score < 45,
      "Verification evidence is weak. The task may be functionally green without strong proof."
    )
    |> maybe_add_verification_signal(
      length(evidence_sources) < 2,
      "Proof relies on a narrow evidence mix. Prefer multiple evidence sources such as regression runs, explicit checks, and review."
    )
    |> maybe_add_verification_signal(
      blocking_failures > 0,
      "Blocking verification failures were recorded for this task."
    )
    |> maybe_add_verification_signal(
      skipped > 0,
      "Some regression flows were skipped, which weakens release confidence."
    )
    |> maybe_add_verification_signal(
      suspicious_test_changes != [],
      "The submitted diff contains test-related changes that may weaken proof strength."
    )
  end

  defp maybe_add_verification_signal(signals, true, message), do: signals ++ [message]
  defp maybe_add_verification_signal(signals, false, _message), do: signals

  defp finding_bundle_entry(f) do
    entry = %{
      id: f.id,
      rule_id: f.rule_id,
      severity: f.severity,
      category: f.category,
      status: f.status,
      plain_message: f.plain_message,
      auto_resolved: f.auto_resolved
    }

    if SecurityWorkflow.vulnerability_case?(f) do
      Map.put(entry, :security_lifecycle, SecurityWorkflow.vulnerability_case_summary(f))
    else
      entry
    end
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

  defp audit_review_entries(review) do
    submitted = %{
      type: "review_submitted",
      timestamp: review.inserted_at,
      review_id: review.id,
      review_type: review.review_type,
      status: review.status,
      task_id: review.task_id,
      title: review.title,
      submitted_by: review.submitted_by
    }

    case review.responded_at do
      %DateTime{} = responded_at ->
        [
          submitted,
          %{
            type: "review_responded",
            timestamp: responded_at,
            review_id: review.id,
            review_type: review.review_type,
            status: review.status,
            task_id: review.task_id,
            reviewed_by: review.reviewed_by,
            feedback_notes: review.feedback_notes
          }
        ]

      _other ->
        [submitted]
    end
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

    reviews =
      Review
      |> where([review], review.task_id == ^task.id)
      |> order_by([review], desc: review.inserted_at, desc: review.id)
      |> repo.all()

    snapshot = build_proof_bundle_snapshot(task, session, findings, invocations, reviews)

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

  defp build_proof_bundle_snapshot(task, session, findings, invocations, reviews) do
    total_cost = Enum.sum(Enum.map(invocations, &(&1.estimated_cost_cents || 0)))
    blocked = Enum.filter(findings, &(&1.status == "blocked"))
    open = Enum.filter(findings, &(&1.status == "open"))
    approved = Enum.filter(findings, &(&1.status == "approved"))
    resolved = Enum.filter(findings, &(&1.status in ["approved", "resolved", "rejected"]))
    details = Enum.map(findings, &finding_bundle_entry/1)
    risk_score = compute_risk_score(findings)
    test_outcomes = derive_test_outcomes(invocations)
    planning_continuity = derive_planning_continuity(task, reviews)

    verification_assessment =
      derive_verification_assessment(task, findings, invocations, reviews, test_outcomes)

    deploy_ready =
      blocked == [] and open == [] and task.status == "done" and
        (test_outcomes["blocking_failures"] || 0) == 0 and
        verification_assessment["verification_ready"] != false and
        planning_continuity["execution_aligned"] != false

    compliance_attestations = build_compliance_attestations(session, findings)
    latest_review = List.first(reviews)
    security_workflow? = SecurityWorkflow.security_domain?(session)
    security_summary = SecurityWorkflow.proof_summary(findings)

    security_release_ready? =
      not security_workflow? or security_summary["unresolved"] == 0

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
      "planning_continuity" => planning_continuity,
      "verification_assessment" => verification_assessment,
      "diff_summary" => %{
        "agent_runs" => length(invocations),
        "findings_total" => length(findings),
        "auto_resolved" => Enum.count(details, & &1.auto_resolved),
        "manual_review" => Enum.count(details, &(&1.status in ["approved", "rejected"])),
        "suspicious_test_changes" =>
          length(verification_assessment["suspicious_test_changes"] || [])
      },
      "risk_score" => risk_score,
      "deploy_ready" => deploy_ready,
      "rollback_instructions" =>
        "git revert HEAD  # revert changes from task #{task.id} if needed",
      "compliance_attestations" => compliance_attestations,
      "validation_gate" => task.validation_gate,
      "invocation_summary" => build_invocation_summary(invocations, total_cost),
      "review_summary" => %{
        "total" => length(reviews),
        "pending" => Enum.count(reviews, &(&1.status == "pending")),
        "approved" => Enum.count(reviews, &(&1.status == "approved")),
        "denied" => Enum.count(reviews, &(&1.status == "denied")),
        "superseded" => Enum.count(reviews, &(&1.status == "superseded")),
        "latest_review_id" => latest_review && latest_review.id,
        "latest_review_type" => latest_review && latest_review.review_type,
        "latest_review_status" => latest_review && latest_review.status
      },
      "finding_resolution_summary" => %{
        "approved" => length(approved),
        "resolved" => length(resolved),
        "open" => length(open),
        "blocked" => length(blocked)
      },
      "security_workflow" =>
        if(security_workflow?,
          do: %{
            "mission_template" => get_in(session.metadata || %{}, ["mission_template"]),
            "cyber_access_mode" => SecurityWorkflow.session_cyber_access_mode(session),
            "phases" => get_in(session.metadata || %{}, ["security_workflow_phases"]) || [],
            "vulnerability_summary" => security_summary,
            "release_gate_decision" => if(security_release_ready?, do: "ready", else: "blocked"),
            "redaction_policy" =>
              get_in(session.metadata || %{}, ["proof_redaction_policy"]) || "security_default"
          },
          else: nil
        ),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> Map.update!("deploy_ready", fn deploy_ready -> deploy_ready and security_release_ready? end)
  end

  defp normalize_regression_result(attrs) do
    with {:ok, session_id} <- normalize_required_integer(attrs, "session_id"),
         {:ok, task_id} <- normalize_optional_integer(attrs, "task_id"),
         {:ok, engine} <- normalize_required_string(attrs, "engine"),
         {:ok, flow_name} <- normalize_required_string(attrs, "flow_name"),
         {:ok, outcome} <- normalize_regression_outcome(attrs),
         {:ok, evidence} <- normalize_optional_map(attrs, "evidence"),
         {:ok, metadata} <- normalize_optional_map(attrs, "metadata") do
      {:ok,
       %{
         "session_id" => session_id,
         "task_id" => task_id,
         "engine" => engine,
         "flow_name" => flow_name,
         "outcome" => outcome,
         "summary" => normalize_optional_string(attrs, "summary"),
         "environment" => normalize_optional_string(attrs, "environment"),
         "commit_sha" => normalize_optional_string(attrs, "commit_sha"),
         "external_run_id" => normalize_optional_string(attrs, "external_run_id"),
         "evidence" => evidence,
         "metadata" => metadata
       }}
    end
  end

  defp normalize_required_integer(attrs, key) do
    case fetch_known_key(attrs, key) do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer"}}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` is required"}}
    end
  end

  defp normalize_optional_integer(attrs, key) do
    case fetch_known_key(attrs, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp normalize_required_string(attrs, key) do
    case normalize_optional_string(attrs, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> {:ok, value}
    end
  end

  defp normalize_optional_string(attrs, key) do
    case fetch_known_key(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp normalize_optional_map(attrs, key) do
    case fetch_known_key(attrs, key) do
      nil -> {:ok, %{}}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an object if provided"}}
    end
  end

  defp normalize_regression_outcome(attrs) do
    case normalize_optional_string(attrs, "outcome") do
      value when value in ["passed", "failed", "flaky", "skipped"] ->
        {:ok, value}

      _ ->
        {:error, {:invalid_arguments, "`outcome` must be one of passed, failed, flaky, skipped"}}
    end
  end

  defp regression_metadata(normalized) do
    bucket =
      case normalized["outcome"] do
        "passed" -> "passed"
        "skipped" -> "passed"
        _ -> "failed"
      end

    %{
      "outcome" => bucket,
      "regression" => %{
        "engine" => normalized["engine"],
        "flow_name" => normalized["flow_name"],
        "outcome" => normalized["outcome"],
        "summary" => normalized["summary"],
        "environment" => normalized["environment"],
        "commit_sha" => normalized["commit_sha"],
        "external_run_id" => normalized["external_run_id"],
        "evidence" => normalized["evidence"]
      },
      "external_metadata" => normalized["metadata"]
    }
  end

  defp regression_decision("passed"), do: "allow"
  defp regression_decision("skipped"), do: "allow"
  defp regression_decision("flaky"), do: "warn"
  defp regression_decision("failed"), do: "warn"

  defp regression_invocation?(invocation) do
    invocation.source == "external_qa" and invocation.tool == "regression_test"
  end

  defp fetch_known_key(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, known_attr_key(key))
  end

  defp known_attr_key("session_id"), do: :session_id
  defp known_attr_key("task_id"), do: :task_id
  defp known_attr_key("engine"), do: :engine
  defp known_attr_key("flow_name"), do: :flow_name
  defp known_attr_key("outcome"), do: :outcome
  defp known_attr_key("summary"), do: :summary
  defp known_attr_key("environment"), do: :environment
  defp known_attr_key("commit_sha"), do: :commit_sha
  defp known_attr_key("external_run_id"), do: :external_run_id
  defp known_attr_key("evidence"), do: :evidence
  defp known_attr_key("metadata"), do: :metadata
  defp known_attr_key(_key), do: nil

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
      "verification_status" => get_in(proof.bundle, ["verification_assessment", "status"]),
      "verification_score" => get_in(proof.bundle, ["verification_assessment", "score"]),
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
    workspace_context = workspace_context(session)
    recent_events = list_session_events(session.id)
    transcript_summary = transcript_summary(session.id)

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
      "planning_context" => get_in(task.metadata || %{}, ["planning_context"]) || %{},
      "review_gate" => review_gate_status(task),
      "memory_hits" => memory_hits.entries,
      "workspace_context" => workspace_context,
      "workspace_cache_key" => workspace_context["cache_key"],
      "recent_events" => recent_events,
      "transcript_summary" => transcript_summary
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

    record_session_event(%{
      session_id: session.id,
      event_type: "session.created",
      actor: "system",
      summary: "Session created: #{session.title}",
      body: brief_body(session, brief),
      payload: %{
        "risk_tier" => session.risk_tier,
        "domain_pack" => brief["domain_pack"]
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

        record_session_event(%{
          session_id: session.id,
          task_id: task.id,
          event_type: task_event_type(action),
          actor: "system",
          summary: task_memory_title(action, task),
          body: task.validation_gate || "",
          payload: %{
            "status" => task.status,
            "previous_status" => Keyword.get(extra, :previous_status),
            "proof_id" => Keyword.get(extra, :proof_id)
          },
          metadata: %{
            "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"])
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

        record_session_event(%{
          session_id: session.id,
          task_id: finding.metadata["task_id"],
          event_type: finding_event_type(action),
          actor: "system",
          summary: "Finding #{to_string(action)}: #{finding.title}",
          body: finding.plain_message,
          payload: %{
            "rule_id" => finding.rule_id,
            "severity" => finding.severity,
            "status" => finding.status,
            "category" => finding.category
          },
          metadata: %{
            "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"])
          }
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

  defp record_review_memory(action, %Review{} = review) do
    review = Repo.preload(review, task: [], session: :workspace)

    Memory.record(%{
      workspace_id: review.session.workspace_id,
      session_id: review.session_id,
      task_id: review.task_id,
      record_type: "review",
      title: review_memory_title(action, review),
      summary: "#{review.review_type} review is #{review.status}",
      body: review_memory_body(review),
      tags: [review.review_type, review.status, "review"],
      source_type: "review",
      source_id: review.id,
      metadata: %{
        "task_id" => review.task_id,
        "review_type" => review.review_type,
        "status" => review.status,
        "previous_review_id" => review.previous_review_id
      }
    })

    record_session_event(%{
      session_id: review.session_id,
      task_id: review.task_id,
      event_type: review_event_type(action),
      actor: review.submitted_by || review.reviewed_by || "system",
      summary: review_memory_title(action, review),
      body: review_memory_body(review),
      payload: %{
        "review_type" => review.review_type,
        "status" => review.status,
        "previous_review_id" => review.previous_review_id
      }
    })
  end

  defp review_memory_title(:submitted, review), do: "Review submitted: #{review.title}"
  defp review_memory_title(:approved, review), do: "Review approved: #{review.title}"
  defp review_memory_title(:denied, review), do: "Review denied: #{review.title}"
  defp review_memory_title(_action, review), do: "Review updated: #{review.title}"

  defp review_memory_body(%Review{} = review) do
    [review.submission_body, review.feedback_notes]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
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

      record_session_event(%{
        session_id: session.id,
        task_id: task.id,
        event_type: "checkpoint.#{checkpoint.checkpoint_type}",
        actor: checkpoint.created_by,
        summary: checkpoint.summary,
        body: Jason.encode!(checkpoint.payload, pretty: true),
        payload: checkpoint.payload,
        metadata: %{
          "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"])
        }
      })
    end
  end

  defp record_session_event(attrs) when is_map(attrs) do
    SessionTranscript.record(
      attrs
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
      |> Map.put_new("metadata", %{})
    )
  end

  defp task_event_type(:created), do: "task.created"
  defp task_event_type(:completed), do: "task.completed"
  defp task_event_type(:paused), do: "task.paused"
  defp task_event_type(:resumed), do: "task.resumed"
  defp task_event_type(:updated), do: "task.updated"
  defp task_event_type(_action), do: "task.changed"

  defp finding_event_type(:created), do: "finding.created"
  defp finding_event_type(:approved), do: "finding.approved"
  defp finding_event_type(:rejected), do: "finding.rejected"
  defp finding_event_type(:escalated), do: "finding.escalated"
  defp finding_event_type(_action), do: "finding.updated"

  defp review_event_type(:submitted), do: "review.submitted"
  defp review_event_type(:approved), do: "review.approved"
  defp review_event_type(:denied), do: "review.denied"
  defp review_event_type(_action), do: "review.updated"

  defp normalize_review_submission(attrs) when is_map(attrs) do
    attrs = Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
    runtime_context = merged_runtime_context(attrs)

    with {:ok, task_id} <- optional_integer(Map.get(attrs, "task_id"), "task_id"),
         {:ok, session_id} <- optional_integer(Map.get(attrs, "session_id"), "session_id"),
         {:ok, previous_review_id} <-
           optional_integer(Map.get(attrs, "previous_review_id"), "previous_review_id"),
         {:ok, review_type} <- normalize_review_type(Map.get(attrs, "review_type", "plan")),
         {:ok, resolved_target} <- infer_review_target(task_id, session_id, runtime_context),
         {:ok, task} <- fetch_review_task(resolved_target.task_id),
         {:ok, session_id} <- resolve_review_session_id(resolved_target.session_id, task),
         :ok <- validate_task_belongs_to_session(task, session_id),
         {:ok, previous_review} <-
           resolve_previous_review(previous_review_id, session_id, task, review_type),
         {:ok, submission_body} <-
           required_string(Map.get(attrs, "submission_body"), "submission_body"),
         {:ok, plan_refinement} <-
           normalize_plan_refinement(attrs, review_type, task, previous_review) do
      title =
        attrs["title"] ||
          review_title(review_type, task, session_id)

      normalized_attrs =
        attrs
        |> Map.put("review_type", review_type)
        |> Map.put("title", title)
        |> Map.put("submission_body", submission_body)
        |> Map.put("session_id", session_id)
        |> maybe_put_map("annotations")
        |> maybe_put_map("metadata")
        |> maybe_put_plan_refinement(plan_refinement)
        |> put_runtime_context_metadata(runtime_context)
        |> maybe_put_string("submitted_by", "agent")
        |> maybe_put_value("task_id", task && task.id)
        |> maybe_put_value("previous_review_id", previous_review && previous_review.id)
        |> Map.put("status", "pending")

      {:ok,
       %{
         attrs: normalized_attrs,
         task: task,
         session_id: session_id,
         runtime_context: runtime_context,
         previous_review: previous_review,
         review_type: review_type,
         plan_refinement: plan_refinement
       }}
    end
  end

  defp normalize_review_response(attrs) when is_map(attrs) do
    attrs = Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

    with {:ok, decision} <-
           normalize_review_decision(Map.get(attrs, "decision") || Map.get(attrs, "status")) do
      review_attrs =
        attrs
        |> maybe_put_map("annotations")
        |> maybe_put_map("metadata")
        |> maybe_put_string("reviewed_by", "human")
        |> Map.put("status", decision)
        |> Map.put("responded_at", DateTime.utc_now() |> DateTime.truncate(:second))

      {:ok, %{decision: decision, review_attrs: review_attrs}}
    end
  end

  defp merge_review_response_attrs(%Review{} = review, review_attrs) do
    review_attrs
    |> Map.update("metadata", review.metadata || %{}, fn metadata ->
      Map.merge(review.metadata || %{}, metadata || %{})
    end)
    |> Map.update("annotations", review.annotations || %{}, fn annotations ->
      Map.merge(review.annotations || %{}, annotations || %{})
    end)
  end

  defp maybe_supersede_pending_reviews(multi, normalized) do
    Multi.run(multi, :superseded_reviews, fn repo, _changes ->
      query = superseded_reviews_query(normalized)
      {count, _rows} = repo.update_all(query, set: [status: "superseded"])
      {:ok, count}
    end)
  end

  defp maybe_track_task_review_gate(
         multi,
         %{task: %Task{} = task, review_type: "plan", plan_refinement: plan_refinement} =
           _normalized
       ) do
    Multi.update(multi, :task, fn %{review: review} ->
      metadata =
        (task.metadata || %{})
        |> put_review_gate(review, "review", false, plan_refinement)
        |> put_latest_submitted_plan(review, plan_refinement)

      Task.changeset(task, %{metadata: metadata})
    end)
  end

  defp maybe_track_task_review_gate(multi, _normalized), do: multi

  defp maybe_track_review_runtime_context(
         multi,
         %{runtime_context: runtime_context, task: task, session_id: session_id}
       )
       when is_map(runtime_context) and map_size(runtime_context) > 0 do
    multi
    |> maybe_update_runtime_task_context(task, runtime_context)
    |> maybe_update_runtime_session_context(session_id, runtime_context)
  end

  defp maybe_track_review_runtime_context(multi, _normalized), do: multi

  defp maybe_apply_review_response_gate(
         multi,
         %Review{task_id: task_id, review_type: "plan"} = review,
         %{decision: decision}
       )
       when is_integer(task_id) do
    Multi.run(multi, :task, fn repo, %{review: updated_review} ->
      case repo.get(Task, task_id) do
        nil ->
          {:ok, nil}

        task ->
          plan_refinement =
            get_in(updated_review.metadata || %{}, ["plan_refinement"]) ||
              get_in(review.metadata || %{}, ["plan_refinement"]) ||
              %{}

          plan_quality = get_in(plan_refinement, ["quality"]) || %{}

          execution_ready =
            decision == "approved" and
              plan_execution_ready?(plan_refinement, plan_quality)

          phase =
            cond do
              decision != "approved" -> "planning"
              execution_ready -> "execution"
              true -> "planning"
            end

          metadata =
            (task.metadata || %{})
            |> put_review_gate(updated_review, phase, execution_ready, plan_refinement)
            |> put_plan_decision(updated_review, plan_refinement, decision)

          task
          |> Task.changeset(%{metadata: metadata})
          |> repo.update()
      end
    end)
  end

  defp maybe_apply_review_response_gate(multi, _review, _normalized), do: multi

  defp superseded_reviews_query(%{task: %Task{id: task_id}, review_type: review_type}) do
    Review
    |> where([review], review.task_id == ^task_id)
    |> where([review], review.review_type == ^review_type)
    |> where([review], review.status == "pending")
  end

  defp superseded_reviews_query(%{
         attrs: %{"session_id" => session_id, "task_id" => nil, "review_type" => review_type}
       }) do
    Review
    |> where([review], review.session_id == ^session_id and is_nil(review.task_id))
    |> where([review], review.review_type == ^review_type)
    |> where([review], review.status == "pending")
  end

  defp fetch_review_task(nil), do: {:ok, nil}

  defp fetch_review_task(task_id) when is_integer(task_id) do
    case get_task(task_id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  defp resolve_review_session_id(nil, %Task{} = task), do: {:ok, task.session_id}

  defp resolve_review_session_id(session_id, _task) when is_integer(session_id),
    do: {:ok, session_id}

  defp resolve_review_session_id(nil, nil),
    do: {:error, {:invalid_arguments, "`session_id` is required"}}

  defp infer_review_target(task_id, session_id, runtime_context) do
    with {:ok, inferred_task_id} <-
           optional_integer(task_id || runtime_context["task_id"], "task_id"),
         {:ok, inferred_session_id} <-
           optional_integer(session_id || runtime_context["session_id"], "session_id") do
      cond do
        is_integer(inferred_task_id) ->
          case get_task(inferred_task_id) do
            nil -> {:error, :not_found}
            task -> {:ok, %{task_id: task.id, session_id: task.session_id}}
          end

        is_integer(inferred_session_id) ->
          {:ok, %{task_id: nil, session_id: inferred_session_id}}

        is_binary(runtime_context["agent_id"]) and is_binary(runtime_context["thread_id"]) ->
          resolve_review_target_from_runtime_context(runtime_context)

        true ->
          {:error, {:invalid_arguments, "`session_id` or `task_id` is required"}}
      end
    end
  end

  defp validate_task_belongs_to_session(nil, _session_id), do: :ok

  defp validate_task_belongs_to_session(%Task{session_id: task_session_id}, session_id) do
    if task_session_id == session_id do
      :ok
    else
      {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  end

  defp resolve_previous_review(previous_review_id, session_id, task, review_type) do
    review =
      cond do
        is_integer(previous_review_id) ->
          case get_review(previous_review_id) do
            nil -> :not_found
            found -> found
          end

        match?(%Task{}, task) ->
          latest_review_for_task(task.id, review_type)

        true ->
          latest_session_review(session_id, review_type)
      end

    case review do
      :not_found ->
        {:error, {:invalid_arguments, "`previous_review_id` was not found"}}

      nil ->
        {:ok, nil}

      %Review{} = found ->
        if found.session_id == session_id do
          {:ok, found}
        else
          {:error,
           {:invalid_arguments, "`previous_review_id` must belong to the current session"}}
        end
    end
  end

  defp latest_session_review(session_id, review_type) do
    Review
    |> where([review], review.session_id == ^session_id and review.review_type == ^review_type)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> limit(1)
    |> Repo.one()
  end

  defp review_title(review_type, %Task{} = task, _session_id) do
    "#{String.capitalize(review_type)} review for #{task.title}"
  end

  defp review_title(review_type, nil, session_id) do
    "#{String.capitalize(review_type)} review for session #{session_id}"
  end

  defp normalize_review_type(review_type) when review_type in ["plan", "diff", "completion"],
    do: {:ok, review_type}

  defp normalize_review_type(_review_type),
    do: {:error, {:invalid_arguments, "`review_type` must be one of: plan, diff, completion"}}

  defp normalize_review_decision("approved"), do: {:ok, "approved"}
  defp normalize_review_decision("approve"), do: {:ok, "approved"}
  defp normalize_review_decision("denied"), do: {:ok, "denied"}
  defp normalize_review_decision("deny"), do: {:ok, "denied"}

  defp normalize_review_decision(_decision),
    do: {:error, {:invalid_arguments, "`decision` must be approved or denied"}}

  defp normalize_plan_refinement(_attrs, review_type, _task, _previous_review)
       when review_type != "plan",
       do: {:ok, nil}

  defp normalize_plan_refinement(attrs, "plan", task, previous_review) do
    metadata_refinement = get_in(attrs, ["metadata", "plan_refinement"]) || %{}

    raw_refinement =
      metadata_refinement
      |> Map.merge(plan_refinement_overrides(attrs))

    with {:ok, phase} <- normalize_plan_phase(Map.get(raw_refinement, "phase", "ticket")),
         {:ok, research_summary} <-
           optional_trimmed_string(
             Map.get(raw_refinement, "research_summary"),
             "research_summary"
           ),
         {:ok, codebase_findings} <-
           optional_string_list(Map.get(raw_refinement, "codebase_findings"), "codebase_findings"),
         {:ok, prior_art_summary} <-
           optional_trimmed_string(
             Map.get(raw_refinement, "prior_art_summary"),
             "prior_art_summary"
           ),
         {:ok, options_considered} <-
           optional_string_list(
             Map.get(raw_refinement, "options_considered"),
             "options_considered"
           ),
         {:ok, selected_option} <-
           optional_trimmed_string(Map.get(raw_refinement, "selected_option"), "selected_option"),
         {:ok, rejected_options} <-
           optional_string_list(Map.get(raw_refinement, "rejected_options"), "rejected_options"),
         {:ok, implementation_steps} <-
           optional_string_list(
             Map.get(raw_refinement, "implementation_steps"),
             "implementation_steps"
           ),
         {:ok, validation_plan} <-
           optional_string_list(Map.get(raw_refinement, "validation_plan"), "validation_plan"),
         {:ok, code_snippets} <-
           optional_string_list(Map.get(raw_refinement, "code_snippets"), "code_snippets"),
         {:ok, scope_estimate} <-
           normalize_scope_estimate(Map.get(raw_refinement, "scope_estimate")) do
      depth = next_plan_depth(previous_review)

      refinement =
        %{
          "phase" => phase,
          "phase_order" => plan_phase_order(phase),
          "depth" => depth,
          "task_title" => task && task.title,
          "research_summary" => research_summary,
          "codebase_findings" => codebase_findings,
          "prior_art_summary" => prior_art_summary,
          "options_considered" => options_considered,
          "selected_option" => selected_option,
          "rejected_options" => rejected_options,
          "implementation_steps" => implementation_steps,
          "validation_plan" => validation_plan,
          "code_snippets" => code_snippets,
          "scope_estimate" => scope_estimate,
          "previous_phase" => previous_plan_phase(previous_review)
        }
        |> maybe_put_value("body_length", body_length(attrs["submission_body"]))
        |> Map.put(
          "quality",
          assess_plan_refinement(phase, scope_estimate, %{
            "research_summary" => research_summary,
            "codebase_findings" => codebase_findings,
            "prior_art_summary" => prior_art_summary,
            "options_considered" => options_considered,
            "selected_option" => selected_option,
            "rejected_options" => rejected_options,
            "implementation_steps" => implementation_steps,
            "validation_plan" => validation_plan,
            "code_snippets" => code_snippets
          })
        )

      {:ok, refinement}
    end
  end

  defp plan_refinement_overrides(attrs) do
    %{}
    |> maybe_override_refinement("phase", Map.get(attrs, "plan_phase"))
    |> maybe_override_refinement("research_summary", Map.get(attrs, "research_summary"))
    |> maybe_override_refinement("codebase_findings", Map.get(attrs, "codebase_findings"))
    |> maybe_override_refinement("prior_art_summary", Map.get(attrs, "prior_art_summary"))
    |> maybe_override_refinement("options_considered", Map.get(attrs, "options_considered"))
    |> maybe_override_refinement("selected_option", Map.get(attrs, "selected_option"))
    |> maybe_override_refinement("rejected_options", Map.get(attrs, "rejected_options"))
    |> maybe_override_refinement("implementation_steps", Map.get(attrs, "implementation_steps"))
    |> maybe_override_refinement("validation_plan", Map.get(attrs, "validation_plan"))
    |> maybe_override_refinement("code_snippets", Map.get(attrs, "code_snippets"))
    |> maybe_override_refinement("scope_estimate", Map.get(attrs, "scope_estimate"))
  end

  defp maybe_override_refinement(refinement, _key, nil), do: refinement
  defp maybe_override_refinement(refinement, key, value), do: Map.put(refinement, key, value)

  defp normalize_plan_phase(phase) when phase in @plan_phases, do: {:ok, phase}

  defp normalize_plan_phase(_phase) do
    {:error,
     {:invalid_arguments, "`plan_phase` must be one of: #{Enum.join(@plan_phases, ", ")}"}}
  end

  defp optional_trimmed_string(nil, _field), do: {:ok, nil}
  defp optional_trimmed_string("", _field), do: {:ok, nil}

  defp optional_trimmed_string(value, _field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp optional_trimmed_string(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be a string if provided"}}

  defp optional_string_list(nil, _field), do: {:ok, []}

  defp optional_string_list(values, field) when is_list(values) do
    if Enum.all?(values, &is_binary/1) do
      {:ok, values |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}
    else
      {:error, {:invalid_arguments, "`#{field}` must be an array of strings"}}
    end
  end

  defp optional_string_list(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be an array of strings if provided"}}

  defp normalize_scope_estimate(nil) do
    {:ok,
     %{
       "files_touched_estimate" => nil,
       "diff_size_estimate" => nil,
       "architectural_scope" => false
     }}
  end

  defp normalize_scope_estimate(scope_estimate) when is_map(scope_estimate) do
    with {:ok, files_touched_estimate} <-
           optional_integer(
             Map.get(scope_estimate, "files_touched_estimate"),
             "files_touched_estimate"
           ),
         {:ok, diff_size_estimate} <-
           optional_integer(Map.get(scope_estimate, "diff_size_estimate"), "diff_size_estimate"),
         {:ok, architectural_scope} <-
           optional_boolean(Map.get(scope_estimate, "architectural_scope"), "architectural_scope") do
      {:ok,
       %{
         "files_touched_estimate" => files_touched_estimate,
         "diff_size_estimate" => diff_size_estimate,
         "architectural_scope" => architectural_scope || false
       }}
    end
  end

  defp normalize_scope_estimate(_value),
    do: {:error, {:invalid_arguments, "`scope_estimate` must be an object if provided"}}

  defp optional_boolean(nil, _field), do: {:ok, nil}
  defp optional_boolean(value, _field) when is_boolean(value), do: {:ok, value}

  defp optional_boolean(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be a boolean if provided"}}

  defp assess_plan_refinement(phase, scope_estimate, fields) do
    scope_high = high_scope_plan?(scope_estimate)
    missing = plan_missing_fields(phase, fields, scope_high)
    execution_ready_phase = phase in @execution_ready_plan_phases

    score =
      100
      |> Kernel.-(length(missing) * 12)
      |> maybe_subtract_score(scope_high and phase == "implementation_plan", 8)
      |> maybe_subtract_score(
        execution_ready_phase and length(fields["validation_plan"]) == 0,
        10
      )
      |> clamp_score()

    %{
      "score" => score,
      "status" => plan_quality_status(score, missing),
      "ready" => execution_ready_phase and missing == [],
      "execution_ready_phase" => execution_ready_phase,
      "scope_high" => scope_high,
      "missing" => missing,
      "signals" => plan_quality_signals(phase, scope_high, missing),
      "grill_questions" => plan_grill_questions(phase, scope_high, missing),
      "next_phase" => next_plan_phase(phase)
    }
  end

  defp plan_missing_fields(phase, fields, scope_high) do
    missing = []

    missing =
      if phase in [
           "research_packet",
           "design_options",
           "narrowed_decision",
           "implementation_plan",
           "code_backed_plan"
         ] and
           is_nil(fields["research_summary"]) and fields["codebase_findings"] == [] and
           is_nil(fields["prior_art_summary"]) do
        ["research_summary" | missing]
      else
        missing
      end

    missing =
      if phase in [
           "design_options",
           "narrowed_decision",
           "implementation_plan",
           "code_backed_plan"
         ] and
           length(fields["options_considered"]) < 2 do
        ["options_considered" | missing]
      else
        missing
      end

    missing =
      if phase in ["narrowed_decision", "implementation_plan", "code_backed_plan"] and
           is_nil(fields["selected_option"]) do
        ["selected_option" | missing]
      else
        missing
      end

    missing =
      if phase in ["narrowed_decision", "implementation_plan", "code_backed_plan"] and
           fields["rejected_options"] == [] do
        ["rejected_options" | missing]
      else
        missing
      end

    missing =
      if phase in ["implementation_plan", "code_backed_plan"] and
           length(fields["implementation_steps"]) < 2 do
        ["implementation_steps" | missing]
      else
        missing
      end

    missing =
      if phase in ["implementation_plan", "code_backed_plan"] and
           length(fields["validation_plan"]) == 0 do
        ["validation_plan" | missing]
      else
        missing
      end

    missing =
      if phase == "code_backed_plan" and fields["code_snippets"] == [] do
        ["code_snippets" | missing]
      else
        missing
      end

    missing =
      if scope_high and phase in @execution_ready_plan_phases and fields["rejected_options"] == [] do
        ["rejected_options" | missing]
      else
        missing
      end

    missing |> Enum.reverse() |> Enum.uniq()
  end

  defp plan_quality_status(score, []), do: if(score >= 92, do: "strong", else: "moderate")
  defp plan_quality_status(score, _missing) when score >= 70, do: "moderate"
  defp plan_quality_status(_score, _missing), do: "weak"

  defp plan_quality_signals(phase, scope_high, missing) do
    []
    |> maybe_add_signal(
      scope_high,
      "Large or architectural work needs deeper planning artifacts before execution."
    )
    |> maybe_add_signal(
      phase in @execution_ready_plan_phases and missing == [],
      "Plan is execution-ready and can unlock implementation after approval."
    )
    |> Enum.concat(Enum.map(missing, &"Missing planning artifact: #{&1}."))
  end

  defp plan_grill_questions(phase, scope_high, missing) do
    base_questions =
      missing
      |> Enum.map(&grill_question_for_missing(&1, phase))
      |> Enum.reject(&is_nil/1)

    scoped_questions =
      if scope_high do
        base_questions ++
          [
            "Which boundaries or modules are most likely to break if this implementation choice is wrong?"
          ]
      else
        base_questions
      end

    phase_questions =
      case phase do
        "ticket" ->
          [
            "What exact user-visible outcome should this task produce when it is done?"
          ]

        "research_packet" ->
          [
            "Which files, modules, or flows did you inspect, and what did each one tell you?"
          ]

        "design_options" ->
          [
            "What is the strongest alternative design here, and why are you not choosing it?"
          ]

        "narrowed_decision" ->
          [
            "What assumption would most likely invalidate the chosen approach?"
          ]

        "implementation_plan" ->
          [
            "What check would tell us early that the implementation is drifting from the plan?"
          ]

        "code_backed_plan" ->
          [
            "Which exact code paths or snippets prove the plan matches the current codebase?"
          ]

        _ ->
          []
      end

    (scoped_questions ++ phase_questions)
    |> Enum.uniq()
    |> Enum.take(4)
  end

  defp grill_question_for_missing("research_summary", _phase) do
    "What did you learn from the codebase or prior art that changes how this should be built?"
  end

  defp grill_question_for_missing("options_considered", _phase) do
    "What are at least two viable approaches here, and what tradeoff separates them?"
  end

  defp grill_question_for_missing("selected_option", _phase) do
    "Which option are you actually choosing, and what makes it the best fit for this repo?"
  end

  defp grill_question_for_missing("rejected_options", _phase) do
    "Why are the rejected options worse in this codebase, not just in theory?"
  end

  defp grill_question_for_missing("implementation_steps", _phase) do
    "What is the ordered implementation sequence, and where are the likely failure points?"
  end

  defp grill_question_for_missing("validation_plan", _phase) do
    "What concrete checks, tests, or compiler signals will prove this change is correct?"
  end

  defp grill_question_for_missing("code_snippets", _phase) do
    "What existing code paths or snippets anchor this plan in the current implementation?"
  end

  defp grill_question_for_missing(_missing, _phase), do: nil

  defp maybe_add_signal(signals, true, message), do: [message | signals]
  defp maybe_add_signal(signals, false, _message), do: signals

  defp next_plan_phase("ticket"), do: "research_packet"
  defp next_plan_phase("research_packet"), do: "design_options"
  defp next_plan_phase("design_options"), do: "narrowed_decision"
  defp next_plan_phase("narrowed_decision"), do: "implementation_plan"
  defp next_plan_phase("implementation_plan"), do: "code_backed_plan"
  defp next_plan_phase(_phase), do: nil

  defp plan_phase_order(phase), do: Enum.find_index(@plan_phases, &(&1 == phase)) || 0

  defp previous_plan_phase(nil), do: nil

  defp previous_plan_phase(%Review{} = review) do
    get_in(review.metadata || %{}, ["plan_refinement", "phase"])
  end

  defp next_plan_depth(nil), do: 1

  defp next_plan_depth(%Review{} = previous_review) do
    (get_in(previous_review.metadata || %{}, ["plan_refinement", "depth"]) || 0) + 1
  end

  defp high_scope_plan?(scope_estimate) when is_map(scope_estimate) do
    (scope_estimate["files_touched_estimate"] || 0) >= 5 or
      (scope_estimate["diff_size_estimate"] || 0) >= 300 or
      scope_estimate["architectural_scope"] == true
  end

  defp high_scope_plan?(_scope_estimate), do: false

  defp body_length(nil), do: 0
  defp body_length(body) when is_binary(body), do: String.length(body)
  defp body_length(_body), do: 0

  defp plan_execution_ready?(plan_refinement, plan_quality) do
    plan_refinement["phase"] in @execution_ready_plan_phases and
      plan_quality["ready"] == true
  end

  defp put_latest_submitted_plan(metadata, _review, nil), do: metadata

  defp put_latest_submitted_plan(metadata, review, plan_refinement) do
    update_in(metadata, ["planning_context"], fn planning_context ->
      planning_context = planning_context || %{}

      Map.put(planning_context, "latest_submitted_plan", %{
        "review_id" => review.id,
        "phase" => plan_refinement["phase"],
        "depth" => plan_refinement["depth"],
        "quality" => plan_refinement["quality"]
      })
    end)
  end

  defp put_plan_decision(metadata, _review, nil, _decision), do: metadata

  defp put_plan_decision(metadata, review, plan_refinement, decision) do
    update_in(metadata, ["planning_context"], fn planning_context ->
      planning_context = planning_context || %{}

      planning_context =
        Map.put(planning_context, "latest_plan_decision", %{
          "review_id" => review.id,
          "decision" => decision,
          "phase" => plan_refinement["phase"],
          "depth" => plan_refinement["depth"],
          "quality" => plan_refinement["quality"]
        })

      if decision == "approved" do
        Map.put(planning_context, "latest_approved_plan", %{
          "review_id" => review.id,
          "phase" => plan_refinement["phase"],
          "depth" => plan_refinement["depth"],
          "quality" => plan_refinement["quality"],
          "selected_option" => plan_refinement["selected_option"],
          "validation_plan" => plan_refinement["validation_plan"]
        })
      else
        planning_context
      end
    end)
  end

  defp put_review_gate(metadata, review, phase, execution_ready, plan_refinement) do
    plan_quality = get_in(plan_refinement || %{}, ["quality"]) || %{}

    Map.put(metadata || %{}, "review_gate", %{
      "phase" => phase,
      "execution_ready" => execution_ready,
      "latest_review_id" => review.id,
      "latest_review_status" => review.status,
      "latest_review_type" => review.review_type,
      "latest_plan_phase" => plan_refinement && plan_refinement["phase"],
      "plan_quality_status" => plan_quality["status"],
      "plan_quality_score" => plan_quality["score"],
      "grill_questions" => plan_quality["grill_questions"] || [],
      "planning_depth" => plan_refinement && plan_refinement["depth"],
      "updated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    })
  end

  defp maybe_put_string(attrs, key, default) do
    value = Map.get(attrs, key, default)
    Map.put(attrs, key, value)
  end

  defp maybe_put_map(attrs, key) do
    case Map.get(attrs, key) do
      nil -> Map.put(attrs, key, %{})
      value when is_map(value) -> attrs
      _other -> Map.put(attrs, key, %{})
    end
  end

  defp maybe_put_plan_refinement(attrs, nil), do: attrs

  defp maybe_put_plan_refinement(attrs, refinement) do
    update_in(attrs, ["metadata"], fn metadata ->
      Map.put(metadata || %{}, "plan_refinement", refinement)
    end)
  end

  defp put_runtime_context_metadata(attrs, runtime_context) when map_size(runtime_context) == 0,
    do: attrs

  defp put_runtime_context_metadata(attrs, runtime_context) do
    update_in(attrs, ["metadata"], fn metadata ->
      metadata = metadata || %{}
      Map.put(metadata, "runtime_context", stringify_keys(runtime_context))
    end)
  end

  defp maybe_put_value(attrs, _key, nil), do: attrs
  defp maybe_put_value(attrs, key, value), do: Map.put(attrs, key, value)

  defp required_string(value, field) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, {:invalid_arguments, "`#{field}` is required"}}
    else
      {:ok, trimmed}
    end
  end

  defp required_string(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` is required"}}

  defp optional_integer(nil, _field), do: {:ok, nil}
  defp optional_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp optional_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{field}` must be an integer if provided"}}
    end
  end

  defp optional_integer(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be an integer if provided"}}

  defp merged_runtime_context(attrs) do
    attr_context =
      get_in(attrs, ["metadata", "runtime_context"]) ||
        Map.get(attrs, "runtime_context") ||
        %{}

    runtime_env_context()
    |> Map.merge(stringify_keys(attr_context))
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp runtime_env_context do
    %{
      "session_id" => System.get_env("CONTROLKEEL_SESSION_ID"),
      "task_id" => System.get_env("CONTROLKEEL_TASK_ID"),
      "agent_id" => System.get_env("CONTROLKEEL_AGENT_ID"),
      "thread_id" => System.get_env("CONTROLKEEL_THREAD_ID"),
      "host_session_id" => System.get_env("CONTROLKEEL_HOST_SESSION_ID"),
      "project_root" => System.get_env("CONTROLKEEL_PROJECT_ROOT"),
      "browser_embed" =>
        System.get_env("CONTROLKEEL_REVIEW_EMBED") || System.get_env("CONTROLKEEL_BROWSER_EMBED")
    }
  end

  defp resolve_review_target_from_runtime_context(runtime_context) do
    case find_task_by_runtime_context(
           runtime_context["agent_id"],
           runtime_context["thread_id"],
           runtime_context["host_session_id"]
         ) do
      %Task{} = task ->
        {:ok, %{task_id: task.id, session_id: task.session_id}}

      nil ->
        case find_session_by_runtime_context(
               runtime_context["agent_id"],
               runtime_context["thread_id"],
               runtime_context["host_session_id"]
             ) do
          %Session{} = session -> {:ok, %{task_id: nil, session_id: session.id}}
          nil -> {:error, {:invalid_arguments, "`session_id` or `task_id` is required"}}
        end
    end
  end

  defp maybe_update_runtime_task_context(multi, %Task{} = task, runtime_context) do
    Multi.run(multi, :runtime_task, fn repo, changes ->
      task_for_update = Map.get(changes, :task, task)

      task_for_update
      |> Task.changeset(%{
        metadata: merge_runtime_context(task_for_update.metadata || %{}, runtime_context)
      })
      |> repo.update()
    end)
  end

  defp maybe_update_runtime_task_context(multi, _task, _runtime_context), do: multi

  defp maybe_update_runtime_session_context(multi, session_id, runtime_context)
       when is_integer(session_id) do
    Multi.run(multi, :runtime_session, fn repo, _changes ->
      case repo.get(Session, session_id) do
        nil ->
          {:ok, nil}

        session ->
          session
          |> Session.changeset(%{
            metadata: merge_runtime_context(session.metadata || %{}, runtime_context)
          })
          |> repo.update()
      end
    end)
  end

  defp maybe_update_runtime_session_context(multi, _session_id, _runtime_context), do: multi

  defp merge_runtime_context(metadata, runtime_context) when is_map(runtime_context) do
    existing = get_in(metadata || %{}, ["runtime_context"]) || %{}

    Map.put(
      metadata || %{},
      "runtime_context",
      Map.merge(existing, stringify_keys(runtime_context))
    )
  end

  defp runtime_context_matches?(metadata, agent_id, thread_id, host_session_id) do
    context = get_in(metadata || %{}, ["runtime_context"]) || %{}

    context["agent_id"] == agent_id and
      context["thread_id"] == thread_id and
      (is_nil(host_session_id) or host_session_id == context["host_session_id"])
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
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
        "phase" => opts[:phase],
        "security_workflow_phase" => opts[:security_workflow_phase],
        "artifact_type" => opts[:artifact_type],
        "target_scope" => opts[:target_scope]
      })
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> maybe_add_vulnerability_metadata(finding, opts)

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

  defp maybe_add_vulnerability_metadata(metadata, finding, opts) do
    if finding.category == "security" and
         (opts[:domain_pack] == SecurityWorkflow.domain_pack() or
            opts[:security_workflow_phase] != nil or
            Map.get(metadata, "finding_family") == "vulnerability_case") do
      SecurityWorkflow.ensure_vulnerability_metadata(metadata, %{
        affected_component: opts[:path] || "session_artifact",
        evidence_type:
          Map.get(metadata, "evidence_type") || evidence_type_for_artifact(opts[:artifact_type]),
        maintainer_scope: opts[:maintainer_scope]
      })
    else
      metadata
    end
  end

  defp evidence_type_for_artifact("binary_report"), do: "binary_report"
  defp evidence_type_for_artifact("telemetry_rule"), do: "telemetry"
  defp evidence_type_for_artifact("diff"), do: "diff"
  defp evidence_type_for_artifact(_artifact_type), do: "source"

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
    |> maybe_filter_finding_metadata("finding_family", filters.finding_family)
    |> maybe_filter_finding_metadata("patch_status", filters.patch_status)
    |> maybe_filter_finding_metadata("disclosure_status", filters.disclosure_status)
    |> maybe_filter_finding_metadata("maintainer_scope", filters.maintainer_scope)
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
      finding_family: normalize_filter_value(opts["finding_family"]),
      patch_status: normalize_filter_value(opts["patch_status"]),
      disclosure_status: normalize_filter_value(opts["disclosure_status"]),
      maintainer_scope: normalize_filter_value(opts["maintainer_scope"]),
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

  defp maybe_filter_finding_metadata(query, _key, nil), do: query
  defp maybe_filter_finding_metadata(query, _key, ""), do: query

  defp maybe_filter_finding_metadata(query, key, value) do
    from([f, _s, _w] in query,
      where: fragment("json_extract(?, ?)", f.metadata, ^"$.#{key}") == ^value
    )
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

  defp count_by_metadata(findings, key) do
    findings
    |> Enum.reduce(%{}, fn finding, acc ->
      value = get_in(finding.metadata || %{}, [key]) || "unknown"
      Map.update(acc, value, 1, &(&1 + 1))
    end)
  end
end
