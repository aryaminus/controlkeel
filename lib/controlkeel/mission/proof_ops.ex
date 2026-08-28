defmodule ControlKeel.Mission.ProofOps do
  @moduledoc """
  Proof-bundle read/query operations extracted from the `Mission` context.

  Owns the read paths (`get_proof_bundle*`, `latest_proof_bundle*`,
  `browse_proof_bundles`, `proof_bundle`) that only need Repo + the
  ProofBundle/Task schemas. Generation and verification stay in `Mission`
  (they depend on transactional helpers that belong with the task lifecycle).
  `Mission` delegates to this module, so existing `Mission.*` call sites keep
  working.
  """

  import Ecto.Query, only: [where: 3, order_by: 3, limit: 2, offset: 2]

  alias ControlKeel.Mission
  alias ControlKeel.Mission.ProofBundle
  alias ControlKeel.Repo

  @proofs_page_size 20

  def get_proof_bundle(id), do: Repo.get(ProofBundle, id)
  def get_proof_bundle!(id), do: Repo.get!(ProofBundle, id)

  def get_proof_bundle_with_context(id) do
    ProofBundle
    |> Repo.get(id)
    |> case do
      nil -> nil
      proof -> Repo.preload(proof, task: [], session: :workspace)
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

  def browse_proof_bundles(opts \\ %{}) do
    filters = Mission.normalize_proof_filters(opts)
    base_query = Mission.proof_bundles_query(filters)
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

  # Query building lives in `Mission` (kept public for reuse by finding/proof
  # browsing); this module only owns the pure read accessors.
end
