defmodule ControlKeel.Mission do
  @moduledoc "Mission planning, persistence, and control-tower orchestration."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.AutoFix
  alias ControlKeel.Intent.ExecutionBrief
  alias ControlKeel.Repo
  alias ControlKeel.Mission.{Finding, Invocation, Planner, Session, Task, Workspace}
  alias ControlKeel.Scanner

  @findings_page_size 20

  def list_sessions, do: Repo.all(Session)
  def get_session(id), do: Repo.get(Session, id)
  def get_session!(id), do: Repo.get!(Session, id)
  def get_session_by_proxy_token(token), do: Repo.get_by(Session, proxy_token: token)
  def get_session_with_workspace(id), do: Session |> Repo.get(id) |> Repo.preload(:workspace)

  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
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
  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
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
    |> Multi.run(:findings, fn repo, %{session: session} ->
      insert_many(repo, Finding, plan.findings, :session_id, session.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} ->
        emit_mission_created(plan, session)
        {:ok, get_session_with_details!(session.id)}

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

  def auto_fix_for_finding(%Finding{} = finding), do: AutoFix.generate(finding)

  def approve_finding(%Finding{} = finding) do
    metadata =
      Map.merge(finding.metadata || %{}, %{
        "approved_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case update_finding(finding, %{status: "approved", metadata: metadata}) do
      {:ok, updated} ->
        emit_finding_event(:approved, updated)
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
        "escalated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case update_finding(finding, %{status: "escalated", metadata: metadata}) do
      {:ok, updated} ->
        emit_finding_event(:escalated, updated)
        {:ok, updated}

      other ->
        other
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

  defp maybe_filter_finding(query, _field, nil), do: query
  defp maybe_filter_finding(query, _field, ""), do: query

  defp maybe_filter_finding(query, field_name, value) do
    from(f in query, where: field(f, ^field_name) == ^value)
  end

  defp maybe_filter_session(query, nil), do: query

  defp maybe_filter_session(query, session_id) do
    from([f, _s, _w] in query, where: f.session_id == ^session_id)
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
