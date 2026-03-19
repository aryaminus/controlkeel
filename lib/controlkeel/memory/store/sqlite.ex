defmodule ControlKeel.Memory.Store.Sqlite do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Memory.Embeddings
  alias ControlKeel.Memory.{Embedding, Record}
  alias ControlKeel.Repo
  alias Ecto.Adapters.SQL

  @candidate_multiplier 8

  def search(query, opts \\ []) do
    top_k = opts[:top_k] || Application.get_env(:controlkeel, :memory_top_k, 5)
    candidate_limit = max(top_k * @candidate_multiplier, 25)
    lexical = lexical_hits(query, opts, candidate_limit)
    records = load_records(Map.keys(lexical), query, opts, candidate_limit)
    embeddings = load_embeddings(records)

    {semantic_available, query_embedding} =
      case Embeddings.embed(query) do
        {:ok, payload} -> {true, payload.embedding}
        _error -> {false, nil}
      end

    entries =
      records
      |> Enum.map(&score_record(&1, lexical, embeddings, query_embedding, opts))
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(top_k)

    %{
      entries: entries,
      query: query,
      total_count: length(entries),
      semantic_available: semantic_available
    }
  end

  defp lexical_hits(query, opts, limit) when is_binary(query) do
    if sqlite_fts_available?() and String.trim(query) != "" do
      match = fts_query(query)

      sql = """
      SELECT mr.id, bm25(memory_records_fts)
      FROM memory_records_fts
      JOIN memory_records mr ON mr.id = memory_records_fts.memory_record_id
      WHERE memory_records_fts MATCH ?
      #{filter_sql(opts)}
      ORDER BY bm25(memory_records_fts), mr.inserted_at DESC
      LIMIT ?
      """

      case SQL.query(Repo, sql, filter_params(match, opts) ++ [limit]) do
        {:ok, %{rows: rows}} ->
          rows
          |> Enum.with_index(1)
          |> Enum.into(%{}, fn {[id, _rank], index} -> {id, 1.0 / index} end)

        _error ->
          %{}
      end
    else
      %{}
    end
  end

  defp load_records([], query, opts, limit), do: fallback_records(query, opts, limit)

  defp load_records(ids, query, opts, limit) do
    records =
      Record
      |> where([r], r.id in ^ids)
      |> maybe_scope_records(opts)
      |> Repo.all()

    if records == [] do
      fallback_records(query, opts, limit)
    else
      records
    end
  end

  defp fallback_records(query, opts, limit) do
    tokens = tokenize_query(query)

    Record
    |> maybe_scope_records(opts)
    |> maybe_apply_token_filter(tokens)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_scope_records(query, opts) do
    query
    |> where([r], is_nil(r.archived_at))
    |> maybe_scope(:workspace_id, opts[:workspace_id])
    |> maybe_scope(:session_id, opts[:session_id])
    |> maybe_scope(:task_id, opts[:task_id])
    |> maybe_scope(:record_type, opts[:record_type])
  end

  defp maybe_scope(query, _field, nil), do: query

  defp maybe_scope(query, field, value) do
    from(r in query, where: field(r, ^field) == ^value)
  end

  defp maybe_apply_token_filter(query, []), do: query

  defp maybe_apply_token_filter(query, tokens) do
    conditions =
      Enum.reduce(tokens, dynamic(false), fn token, dynamic ->
        pattern = "%" <> String.downcase(token) <> "%"

        dynamic(
          [r],
          ^dynamic or
            like(fragment("lower(?)", r.title), ^pattern) or
            like(fragment("lower(?)", r.summary), ^pattern) or
            like(fragment("lower(?)", r.body), ^pattern)
        )
      end)

    where(query, ^conditions)
  end

  defp load_embeddings(records) do
    ids = Enum.map(records, & &1.id)

    Embedding
    |> where([e], e.memory_record_id in ^ids)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.memory_record_id)
    |> Enum.into(%{}, fn {id, [latest | _rest]} -> {id, latest.embedding} end)
  end

  defp score_record(record, lexical, embeddings, query_embedding, opts) do
    lexical_score = Map.get(lexical, record.id, fallback_lexical_score(record))
    semantic_score = cosine_similarity(query_embedding, Map.get(embeddings, record.id))
    workspace_bonus = if(record.workspace_id == opts[:workspace_id], do: 0.75, else: 0.0)
    session_bonus = if(record.session_id == opts[:session_id], do: 0.35, else: 0.0)

    domain_bonus =
      if record.metadata["domain_pack"] && record.metadata["domain_pack"] == opts[:domain_pack] do
        0.2
      else
        0.0
      end

    recency_bonus = recency_bonus(record.inserted_at)

    score =
      lexical_score + semantic_score * 1.5 + workspace_bonus + session_bonus + domain_bonus +
        recency_bonus

    %{
      id: record.id,
      record_type: record.record_type,
      title: record.title,
      summary: record.summary,
      body: record.body,
      tags: record.tags,
      source_type: record.source_type,
      source_id: record.source_id,
      session_id: record.session_id,
      task_id: record.task_id,
      workspace_id: record.workspace_id,
      metadata: record.metadata,
      inserted_at: record.inserted_at,
      lexical_score: Float.round(lexical_score, 4),
      semantic_score: Float.round(semantic_score, 4),
      score: Float.round(score, 4)
    }
  end

  defp recency_bonus(inserted_at) do
    age_seconds =
      max(DateTime.diff(DateTime.utc_now(), inserted_at || DateTime.utc_now(), :second), 0)

    Float.round(max(0.0, 0.25 - age_seconds / 604_800), 4)
  end

  defp fallback_lexical_score(record) do
    size =
      [record.title, record.summary, record.body]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
      |> byte_size()

    min(size / 500, 0.2)
  end

  defp cosine_similarity(nil, _vector), do: 0.0
  defp cosine_similarity(_vector, nil), do: 0.0

  defp cosine_similarity(left, right) when length(left) == length(right) and left != [] do
    numerator = Enum.zip_with(left, right, &(&1 * &2)) |> Enum.sum()
    left_mag = :math.sqrt(Enum.reduce(left, 0.0, &(&1 * &1 + &2)))
    right_mag = :math.sqrt(Enum.reduce(right, 0.0, &(&1 * &1 + &2)))

    if left_mag == 0.0 or right_mag == 0.0 do
      0.0
    else
      numerator / (left_mag * right_mag)
    end
  end

  defp cosine_similarity(_left, _right), do: 0.0

  defp sqlite_fts_available? do
    case SQL.query(
           Repo,
           "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memory_records_fts'",
           []
         ) do
      {:ok, %{rows: [[_name]]}} -> true
      _ -> false
    end
  end

  defp fts_query(query) do
    query
    |> tokenize_query()
    |> Enum.map(&"#{&1}*")
    |> Enum.join(" OR ")
  end

  defp tokenize_query(query) do
    ~r/[\p{L}\p{N}_-]+/u
    |> Regex.scan(query)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp filter_sql(opts) do
    clauses =
      []
      |> maybe_clause("mr.workspace_id = ?", opts[:workspace_id])
      |> maybe_clause("mr.session_id = ?", opts[:session_id])
      |> maybe_clause("mr.task_id = ?", opts[:task_id])
      |> maybe_clause("mr.record_type = ?", opts[:record_type])
      |> Kernel.++(["mr.archived_at IS NULL"])

    " AND " <> Enum.join(clauses, " AND ")
  end

  defp filter_params(match, opts) do
    [match]
    |> maybe_param(opts[:workspace_id])
    |> maybe_param(opts[:session_id])
    |> maybe_param(opts[:task_id])
    |> maybe_param(opts[:record_type])
  end

  defp maybe_clause(clauses, _sql, nil), do: clauses
  defp maybe_clause(clauses, sql, _value), do: clauses ++ [sql]

  defp maybe_param(params, nil), do: params
  defp maybe_param(params, value), do: params ++ [value]
end
