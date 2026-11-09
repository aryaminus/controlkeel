defmodule ControlKeel.Cloud.RuntimeContext do
  @moduledoc """
  Public context for the cloud-agent runtime loop.

  Builds and tracks `ControlKeel.Cloud.RunPackage` records that represent a
  task handed off to a downstream cloud runtime. This module is the persistence
  layer for Phase 5 — the HTTP/CLI dispatch and the callback endpoint live in
  follow-on slices.

  **Authorization gate (CK-CLOUD-AUTHZ-001):** `create_package/1` now checks
  whether the workspace's org authorizes the caller before creating a run
  package. Workspaces must belong to an org and require an active membership
  with role >= member, passed via the `user_id` key.

  Per architectural decision D2, runtime authorization continues to flow
  through service-account-style tokens. The callback token issued here is
  single-use and bound to one package; it is hashed at rest using the same
  SHA-256 helper Service Accounts already use, so the format is consistent.

  Naming: this module is `ControlKeel.Cloud.RuntimeContext` rather than
  `ControlKeel.Cloud.Runtime` to avoid colliding with `ControlKeel.Runtime`
  (the local-vs-cloud runtime mode helper).
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Cloud.Scope
  alias ControlKeel.Accounts
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Repo

  @doc """
  Create a new cloud run package and return `{:ok, package, raw_callback_token}`.

  The raw token is returned exactly once — the caller delivers it to the cloud
  runtime out of band (in the dispatch HTTP body, typically). The package row
  stores only the SHA-256 hash.

  Required attrs:

    - `workspace_id`
    - `runtime_target` (one of `RunPackage.valid_runtimes/0`)
    - `budget_cents_allocated` (>= 0)

  Optional attrs: `session_id`, `task_id`, `scopes` (list or string), `proof_refs`
  (list or string), `payload` (map for runtime-specific fields).
  """
  @spec create_package(map()) ::
          {:ok, RunPackage.t(), String.t()}
          | {:error,
             Ecto.Changeset.t()
             | :unbound_workspace
             | :unauthorized
             | :not_found
             | :org_suspended}
  def create_package(attrs) when is_map(attrs) do
    workspace_id = Arguments.parse_integer(attrs[:workspace_id] || attrs["workspace_id"])

    with :ok <- authorize_workspace(workspace_id, attrs) do
      raw_token = generate_token()

      attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put_new("status", "pending")
        |> Map.put_new("external_id", generate_external_id())
        |> Map.put("callback_token_hash", token_hash(raw_token))
        |> normalize_list("scopes")
        |> normalize_list("proof_refs")

      case %RunPackage{}
           |> RunPackage.changeset(attrs)
           |> Repo.insert() do
        {:ok, package} -> {:ok, package, raw_token}
        {:error, _} = err -> err
      end
    end
  end

  @doc "Generate a user-facing pkg_<ulid> identifier."
  @spec generate_external_id() :: String.t()
  def generate_external_id, do: "pkg_" <> ControlKeel.Cloud.Telemetry.Envelope.ulid()

  @doc "Fetch a package by its user-facing pkg_<ulid> external id."
  @spec get_by_external_id(String.t()) :: RunPackage.t() | nil
  def get_by_external_id(external_id) when is_binary(external_id) do
    Repo.get_by(RunPackage, external_id: external_id)
  end

  @doc "Fetch a package by external id, only if it belongs to `workspace_id`."
  @spec get_by_external_id(String.t(), integer()) :: RunPackage.t() | nil
  def get_by_external_id(external_id, workspace_id)
      when is_binary(external_id) and is_integer(workspace_id) do
    Scope.get_by_in_workspace(RunPackage, [external_id: external_id], workspace_id)
  end

  @doc "Get a package by id."
  @spec get_package(integer()) :: RunPackage.t() | nil
  def get_package(id), do: Repo.get(RunPackage, id)

  @doc "Get a package by id, only if it belongs to `workspace_id`."
  @spec get_package(integer(), integer()) :: RunPackage.t() | nil
  def get_package(id, workspace_id) when is_integer(id) and is_integer(workspace_id) do
    Scope.get_in_workspace(RunPackage, id, workspace_id)
  end

  @doc """
  Authenticate a raw callback token, returning the matching package.

  Returns `:not_found` when no row matches, `{:terminal, package}` when the
  package is in a terminal status (callbacks for completed/failed/cancelled
  packages are rejected to prevent late updates from overwriting evidence).
  """
  @spec authenticate_callback(String.t()) ::
          {:ok, RunPackage.t()} | :not_found | {:terminal, RunPackage.t()}
  def authenticate_callback(raw_token) when is_binary(raw_token) do
    hash = token_hash(raw_token)

    case Repo.get_by(RunPackage, callback_token_hash: hash) do
      nil ->
        :not_found

      %RunPackage{} = package ->
        if RunPackage.terminal?(package), do: {:terminal, package}, else: {:ok, package}
    end
  end

  @doc "List packages for a workspace, newest first."
  @spec list_for_workspace(integer(), keyword()) :: [RunPackage.t()]
  def list_for_workspace(workspace_id, opts \\ []) when is_integer(workspace_id) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    RunPackage
    |> where([p], p.workspace_id == ^workspace_id)
    |> maybe_filter_status(status_filter)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Transition a package's status.

  Returns `{:error, :terminal}` if the package has already reached a terminal
  status (no late updates allowed).
  """
  @spec transition_status(RunPackage.t() | integer(), String.t(), keyword()) ::
          {:ok, RunPackage.t()}
          | {:error, :not_found | :terminal | :invalid_status | Ecto.Changeset.t()}
  def transition_status(package_or_id, new_status, opts \\ [])

  def transition_status(%RunPackage{id: id}, new_status, opts) do
    transition_status(id, new_status, opts)
  end

  def transition_status(id, new_status, opts) when is_integer(id) do
    cond do
      new_status not in RunPackage.valid_statuses() ->
        {:error, :invalid_status}

      true ->
        # Always re-read so a stale in-memory struct cannot trick the terminal
        # gate into letting a second update through.
        case Repo.get(RunPackage, id) do
          nil ->
            {:error, :not_found}

          %RunPackage{} = fresh ->
            if RunPackage.terminal?(fresh) do
              {:error, :terminal}
            else
              attrs =
                %{status: new_status}
                |> maybe_put_field(:result_summary, Keyword.get(opts, :result_summary))
                |> maybe_put_field(:error_summary, Keyword.get(opts, :error_summary))
                |> maybe_put_field(:proof_refs, encode_list(Keyword.get(opts, :proof_refs)))
                |> maybe_put_timestamp(new_status)

              fresh
              |> RunPackage.changeset(attrs)
              |> Repo.update()
            end
        end
    end
  end

  @doc "Count packages by status for a workspace."
  @spec status_counts(integer()) :: %{String.t() => non_neg_integer()}
  def status_counts(workspace_id) when is_integer(workspace_id) do
    RunPackage
    |> where([p], p.workspace_id == ^workspace_id)
    |> group_by([p], p.status)
    |> select([p], {p.status, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Count packages by status across ALL workspaces.

  **Admin only.** Use `status_counts/1` for tenant-facing surfaces.
  """
  @spec global_status_counts() :: %{String.t() => non_neg_integer()}
  def global_status_counts do
    RunPackage
    |> group_by([p], p.status)
    |> select([p], {p.status, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Newest-first list of recent run packages across ALL workspaces.

  **Admin only.** Use `list_for_workspace/2` for tenant-facing surfaces.
  """
  @spec global_recent(keyword()) :: [RunPackage.t()]
  def global_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    RunPackage
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Dispatch a freshly-created run package to its runtime via the configured
  `RuntimeDispatcher` (defaulting to `RuntimeDispatcher.Manual`).

  `raw_token` is the callback token returned from `create_package/1`. It is
  passed to the dispatcher so a runtime-specific implementation can include
  it in whatever envelope it uses (HTTP body, queue message, etc.).
  ControlKeel itself never stores the raw token — only the SHA-256 hash on
  the package — so dispatch must happen with the in-memory token returned
  at create time.

  On `{:ok, metadata}` the package transitions `pending → dispatched`, the
  metadata is stored under `payload["dispatch_metadata"]`, and the updated
  package is returned. On `{:error, reason}` the package transitions to
  `failed` with the reason captured in `error_summary`.
  """
  @spec dispatch_package(RunPackage.t(), String.t(), keyword()) ::
          {:ok, RunPackage.t()} | {:error, term()}
  def dispatch_package(%RunPackage{} = package, raw_token, opts \\ [])
      when is_binary(raw_token) do
    dispatcher = ControlKeel.Cloud.RuntimeDispatcher.for_runtime(package.runtime_target)
    dispatcher_opts = Keyword.put(opts, :raw_token, raw_token)

    case dispatcher.dispatch(package, dispatcher_opts) do
      {:ok, metadata} when is_map(metadata) ->
        merged_payload =
          (package.payload || %{})
          |> Map.put("dispatch_metadata", metadata)

        case package
             |> RunPackage.changeset(%{
               status: "dispatched",
               payload: merged_payload,
               dispatched_at: now()
             })
             |> Repo.update() do
          {:ok, updated} -> {:ok, updated}
          {:error, _} = err -> err
        end

      {:error, reason} ->
        summary = "dispatch_failed: #{format_reason(reason)}"

        _ =
          package
          |> RunPackage.changeset(%{
            status: "failed",
            error_summary: summary,
            completed_at: now()
          })
          |> Repo.update()

        {:error, reason}

      other ->
        {:error, {:invalid_dispatcher_return, other}}
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  @doc """
  Persist findings reported by a cloud runtime callback against the
  originating package's session.

  Each input is a map with the user-facing finding attrs (`title`,
  `severity`, `category`, `rule_id`, `plain_message`, optional `metadata`).
  Provenance is tagged into metadata so an auditor can trace a finding back
  to the cloud package and runtime that produced it.

  Returns `{:ok, [finding_id]}` when every finding inserts, or
  `{:error, {reason, attempted_index}}` on the first failure so the caller
  can decide whether to surface a partial-success error.
  """
  @spec ingest_findings(RunPackage.t(), [map()]) ::
          {:ok, [integer()]} | {:error, {atom() | Ecto.Changeset.t(), non_neg_integer()}}
  def ingest_findings(%RunPackage{session_id: nil}, _findings), do: {:ok, []}
  def ingest_findings(%RunPackage{}, []), do: {:ok, []}

  def ingest_findings(%RunPackage{session_id: session_id} = package, findings)
      when is_integer(session_id) and is_list(findings) do
    findings
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, idx}, {:ok, acc} ->
      case insert_callback_finding(package, attrs) do
        {:ok, %{id: id}} -> {:cont, {:ok, [id | acc]}}
        {:error, reason} -> {:halt, {:error, {reason, idx}}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      err -> err
    end
  end

  defp insert_callback_finding(%RunPackage{} = package, attrs) when is_map(attrs) do
    str = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    user_metadata =
      case Map.get(str, "metadata") do
        m when is_map(m) -> m
        _ -> %{}
      end

    metadata =
      Map.merge(user_metadata, %{
        "source" => "cloud_runtime_callback",
        "cloud_package_id" => package.id,
        "runtime_target" => package.runtime_target
      })

    finding_attrs = %{
      title: str["title"],
      severity: str["severity"],
      category: str["category"],
      rule_id: str["rule_id"],
      plain_message: str["plain_message"],
      status: str["status"] || "open",
      auto_resolved: str["auto_resolved"] || false,
      metadata: metadata,
      session_id: package.session_id
    }

    ControlKeel.Mission.create_finding(finding_attrs)
  end

  # ─────────────── authorization ───────────────

  defp authorize_workspace(nil, _attrs), do: :ok

  defp authorize_workspace(workspace_id, attrs) when is_integer(workspace_id) do
    user_id = Arguments.parse_integer(attrs[:user_id] || attrs["user_id"])

    case Accounts.authorize_cloud_execution(workspace_id, user_id: user_id) do
      {:ok, :authorized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ─────────────── helpers ───────────────

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, statuses) when is_list(statuses),
    do: where(query, [p], p.status in ^statuses)

  defp maybe_filter_status(query, status) when is_binary(status),
    do: where(query, [p], p.status == ^status)

  defp maybe_put_field(attrs, _key, nil), do: attrs
  defp maybe_put_field(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_put_timestamp(attrs, "dispatched"),
    do: Map.put(attrs, :dispatched_at, now())

  defp maybe_put_timestamp(attrs, status) when status in ~w(completed failed cancelled),
    do: Map.put(attrs, :completed_at, now())

  defp maybe_put_timestamp(attrs, _other), do: attrs

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp normalize_list(attrs, key) do
    case Map.get(attrs, key) do
      nil -> attrs
      value -> Map.put(attrs, key, encode_list(value))
    end
  end

  defp encode_list(nil), do: nil
  defp encode_list(value) when is_binary(value), do: value
  defp encode_list(value) when is_list(value), do: Enum.map_join(value, ",", &to_string/1)

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp token_hash(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
