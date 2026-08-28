defmodule ControlKeel.Mission.SessionOps do
  @moduledoc """
  Session/Workspace/Task read + simple CRUD operations extracted from the
  `Mission` context.

  Owns the pure read accessors and non-transactional CRUD for sessions,
  workspaces, tasks, and workspace↔GitHub bindings. Transactional task
  lifecycle (pause/resume/complete) stays in `Mission`. Mission delegates
  to this module so existing `Mission.*` call sites keep working.
  """

  import Ecto.Query

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Mission.Task
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Mission.WorkspaceGithubRepo
  alias ControlKeel.Repo

  def list_sessions, do: Repo.all(Session)
  def get_session(id), do: Repo.get(Session, id)
  def get_session!(id), do: Repo.get!(Session, id)
  def get_session_by_proxy_token(token), do: Repo.get_by(Session, proxy_token: token)

  def get_session_with_workspace(id), do: Session |> Repo.get(id) |> Repo.preload(:workspace)

  def create_session(attrs) do
    case lookup_existing_session(attrs) do
      %Session{} = existing ->
        {:ok, existing}

      nil ->
        %Session{}
        |> Session.changeset(attrs)
        |> Repo.insert()
        |> tap(fn
          {:ok, session} -> Mission.record_brief_memory(session)
          _other -> :ok
        end)
    end
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
    update_session(session, %{
      metadata: Mission.merge_runtime_context(session.metadata || %{}, context)
    })
  end

  def delete_session(%Session{} = session), do: Repo.delete(session)

  def list_workspaces, do: Repo.all(Workspace)
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  def list_workspaces_for_org(org_id),
    do: Repo.all(from w in Workspace, where: w.org_id == ^org_id)

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

  def get_workspace_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Workspace, slug: slug)
  end

  def get_task(id), do: Repo.get(Task, id)
  def get_task!(id), do: Repo.get!(Task, id)

  @doc "Look up a task by its user-facing task_<ulid> external_id."
  @spec get_task_by_external_id(String.t()) :: Task.t() | nil
  def get_task_by_external_id(external_id) when is_binary(external_id) do
    Repo.get_by(Task, external_id: external_id)
  end

  @doc """
  Bind a GitHub repository to a workspace.

  Pass `:installation_id` if the operator has a GitHub App installation
  available; nil is fine and represents a declared-but-unauthenticated
  binding. `:default_branch` is optional and informational.
  """
  @spec bind_github_repo(integer(), String.t(), String.t(), keyword()) ::
          {:ok, WorkspaceGithubRepo.t()} | {:error, Ecto.Changeset.t()}
  def bind_github_repo(workspace_id, owner, repo, opts \\ [])
      when is_integer(workspace_id) and is_binary(owner) and is_binary(repo) do
    attrs = %{
      workspace_id: workspace_id,
      owner: owner,
      repo: repo,
      default_branch: Keyword.get(opts, :default_branch),
      installation_id: Keyword.get(opts, :installation_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %WorkspaceGithubRepo{}
    |> WorkspaceGithubRepo.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Remove a workspace↔repo binding."
  @spec unbind_github_repo(integer(), String.t(), String.t()) ::
          {:ok, WorkspaceGithubRepo.t()} | {:error, :not_found}
  def unbind_github_repo(workspace_id, owner, repo)
      when is_integer(workspace_id) and is_binary(owner) and is_binary(repo) do
    case Repo.get_by(WorkspaceGithubRepo, workspace_id: workspace_id, owner: owner, repo: repo) do
      nil -> {:error, :not_found}
      %WorkspaceGithubRepo{} = binding -> Repo.delete(binding)
    end
  end

  @doc "List all GitHub repo bindings for a workspace."
  @spec list_github_repos(integer()) :: [WorkspaceGithubRepo.t()]
  def list_github_repos(workspace_id) when is_integer(workspace_id) do
    WorkspaceGithubRepo
    |> where([r], r.workspace_id == ^workspace_id)
    |> order_by([r], asc: r.owner, asc: r.repo)
    |> Repo.all()
  end

  @doc """
  Returns true when a session (mission) already uses `name` as its title,
  case-insensitively. Used by the onboarding wizard to prevent duplicate
  project names before compile.
  """
  def project_name_taken?(nil), do: false

  def project_name_taken?(name) when is_binary(name) do
    normalized = String.downcase(String.trim(name))

    from(s in Session, where: fragment("lower(?)", s.title) == ^normalized)
    |> Repo.one() != nil
  end

  # ─── Privates ────────────────────────────────────────────────────────────────

  defp lookup_existing_session(attrs) do
    workspace_id =
      Map.get(attrs, :workspace_id) || Map.get(attrs, "workspace_id")

    external_id =
      Map.get(attrs, :external_id) || Map.get(attrs, "external_id")

    if is_integer(workspace_id) and is_binary(external_id) and external_id != "" do
      Repo.get_by(Session, workspace_id: workspace_id, external_id: external_id)
    end
  end
end
