defmodule ControlKeel.Cloud.Scope do
  @moduledoc """
  Centralized tenant-scoped query helpers for cloud surfaces.

  Every cloud-facing Repo query must enforce `workspace_id` or `org_id` at the
  database level — not just in Elixir after the fetch. This module provides the
  shared building blocks so callers never write an unscoped `Repo.get`/`Repo.get_by`
  against cloud data.

  ## Usage

      import ControlKeel.Cloud.Scope, only: [scope_workspace: 2]

      RunPackage
      |> scope_workspace(workspace_id)
      |> Repo.all()

  For single-record lookups:

      get_in_workspace(RunPackage, id, workspace_id)
      get_by_in_workspace(RunPackage, [external_id: ext_id], workspace_id)

  ## Design rules

  - `nil` workspace_id is allowed only in local mode; in cloud/self_hosted it
    should be validated by the caller before reaching these helpers.
  - All functions return `nil` or `{:error, ...}` when the record does not belong
    to the specified workspace — never the wrong tenant's record.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo

  @doc """
  Add a `WHERE workspace_id = ?` clause to any Ecto queryable.

  Pass-through when `workspace_id` is `nil` (local mode). In cloud/self_hosted
  mode the caller should already have validated the workspace_id.
  """
  @spec scope_workspace(Ecto.Queryable.t(), integer() | nil) :: Ecto.Queryable.t()
  def scope_workspace(query, nil), do: query

  def scope_workspace(query, workspace_id) when is_integer(workspace_id) do
    where(query, [x], x.workspace_id == ^workspace_id)
  end

  @doc """
  Add a `WHERE workspace_id IN (?)` clause for batch queries.

  An empty id list yields no rows — "no accessible workspaces" must not
  degrade into an unscoped fetch (issue #183).
  """
  @spec scope_workspaces(Ecto.Queryable.t(), [integer()]) :: Ecto.Queryable.t()
  def scope_workspaces(query, []), do: where(query, [x], false)

  def scope_workspaces(query, workspace_ids) when is_list(workspace_ids) do
    where(query, [x], x.workspace_id in ^workspace_ids)
  end

  @doc """
  Add a `WHERE org_id = ?` clause to any Ecto queryable.

  For schemas that use `org_id` directly (Key, etc.).
  """
  @spec scope_org(Ecto.Queryable.t(), integer() | nil) :: Ecto.Queryable.t()
  def scope_org(query, nil), do: query

  def scope_org(query, org_id) when is_integer(org_id) do
    where(query, [x], x.org_id == ^org_id)
  end

  @doc """
  Fetch a single record by primary key, only if it belongs to `workspace_id`.

  Returns `nil` when the record does not exist or belongs to a different workspace.
  """
  @spec get_in_workspace(Ecto.Queryable.t(), integer(), integer()) ::
          Ecto.Schema.t() | nil
  def get_in_workspace(schema, id, workspace_id)
      when is_atom(schema) and is_integer(id) and is_integer(workspace_id) do
    schema
    |> where([x], x.id == ^id and x.workspace_id == ^workspace_id)
    |> Repo.one()
  end

  @doc """
  Fetch a single record by clauses, adding `workspace_id` to the filter.

  Returns `nil` when no matching record exists in the specified workspace.
  """
  @spec get_by_in_workspace(Ecto.Queryable.t(), keyword() | map(), integer()) ::
          Ecto.Schema.t() | nil
  def get_by_in_workspace(schema, clauses, workspace_id)
      when is_atom(schema) and (is_list(clauses) or is_map(clauses)) and
             is_integer(workspace_id) do
    merged = add_workspace_id(clauses, workspace_id)
    Repo.get_by(schema, merged)
  end

  @doc """
  Assert that a record belongs to the given workspace.

  Returns `:ok` if the record's `workspace_id` matches.
  Returns `{:error, :workspace_scope_mismatch}` otherwise.
  """
  @spec require_workspace(struct(), integer()) ::
          :ok | {:error, :workspace_scope_mismatch}
  def require_workspace(record, expected_workspace_id)

  def require_workspace(%{workspace_id: ws_id}, expected) when ws_id == expected,
    do: :ok

  def require_workspace(_record, _expected),
    do: {:error, :workspace_scope_mismatch}

  @doc """
  Resolve a session_id to verify it belongs to `workspace_id`.

  Returns `{:ok, session}` if the session exists and belongs to the workspace.
  Returns `{:error, :not_found}` if the session does not exist.
  Returns `{:error, :workspace_scope_mismatch}` if the session belongs to another workspace.
  """
  @spec resolve_session(integer(), integer()) ::
          {:ok, Ecto.Schema.t()} | {:error, :not_found | :workspace_scope_mismatch}
  def resolve_session(session_id, workspace_id)
      when is_integer(session_id) and is_integer(workspace_id) do
    case Repo.get(ControlKeel.Mission.Session, session_id) do
      nil ->
        {:error, :not_found}

      %{workspace_id: ^workspace_id} = session ->
        {:ok, session}

      _ ->
        {:error, :workspace_scope_mismatch}
    end
  end

  # --- Private helpers ---

  defp add_workspace_id(clauses, workspace_id) when is_list(clauses) do
    Keyword.put(clauses, :workspace_id, workspace_id)
  end

  defp add_workspace_id(clauses, workspace_id) when is_map(clauses) do
    Map.put(clauses, :workspace_id, workspace_id)
  end
end
