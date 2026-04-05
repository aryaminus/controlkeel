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
      "latest_review_type" => gate["latest_review_type"]
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
      Multi.new()
      |> Multi.update(:review, Review.changeset(review, normalized.review_attrs))
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
    deploy_ready = blocked == [] and open == [] and task.status == "done"
    compliance_attestations = build_compliance_attestations(session, findings)
    test_outcomes = derive_test_outcomes(invocations)
    latest_review = List.first(reviews)

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
           required_string(Map.get(attrs, "submission_body"), "submission_body") do
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
         review_type: review_type
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

  defp maybe_supersede_pending_reviews(multi, normalized) do
    Multi.run(multi, :superseded_reviews, fn repo, _changes ->
      query = superseded_reviews_query(normalized)
      {count, _rows} = repo.update_all(query, set: [status: "superseded"])
      {:ok, count}
    end)
  end

  defp maybe_track_task_review_gate(
         multi,
         %{task: %Task{} = task, review_type: "plan"} = _normalized
       ) do
    Multi.update(multi, :task, fn %{review: review} ->
      metadata = put_review_gate(task.metadata || %{}, review, "review", false)
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
         %Review{task_id: task_id, review_type: "plan"},
         %{decision: decision}
       )
       when is_integer(task_id) do
    Multi.run(multi, :task, fn repo, %{review: updated_review} ->
      case repo.get(Task, task_id) do
        nil ->
          {:ok, nil}

        task ->
          phase = if(decision == "approved", do: "execution", else: "planning")
          execution_ready = decision == "approved"
          metadata = put_review_gate(task.metadata || %{}, updated_review, phase, execution_ready)

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

  defp put_review_gate(metadata, review, phase, execution_ready) do
    Map.put(metadata || %{}, "review_gate", %{
      "phase" => phase,
      "execution_ready" => execution_ready,
      "latest_review_id" => review.id,
      "latest_review_status" => review.status,
      "latest_review_type" => review.review_type,
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
    Multi.update(multi, :runtime_task, fn _changes ->
      Task.changeset(task, %{
        metadata: merge_runtime_context(task.metadata || %{}, runtime_context)
      })
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
