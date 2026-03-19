defmodule ControlKeel.Memory.Store.Pgvector do
  @moduledoc false

  alias ControlKeel.Memory.Store.Sqlite
  alias ControlKeel.Repo
  alias Ecto.Adapters.SQL

  def available? do
    to_string(Repo.__adapter__()) == "Elixir.Ecto.Adapters.Postgres" and pgvector_enabled?()
  end

  def search(query, opts \\ []) do
    if available?() do
      search_pgvector(query, opts)
    else
      Sqlite.search(query, opts)
    end
  end

  defp search_pgvector(query, opts) do
    case ControlKeel.Memory.Embeddings.embed(query) do
      {:ok, payload} ->
        top_k = opts[:top_k] || 5
        vector = Jason.encode!(payload.embedding)

        sql = """
        SELECT mr.id, 1 - (me.embedding_text::vector <=> $1::vector) AS similarity
        FROM memory_records mr
        JOIN memory_embeddings me ON me.memory_record_id = mr.id
        WHERE mr.archived_at IS NULL
          AND ($2::bigint IS NULL OR mr.workspace_id = $2)
          AND ($3::bigint IS NULL OR mr.session_id = $3)
          AND ($4::bigint IS NULL OR mr.task_id = $4)
          AND ($5::text IS NULL OR mr.record_type = $5)
        ORDER BY me.embedding_text::vector <=> $1::vector
        LIMIT $6
        """

        case SQL.query(Repo, sql, [
               vector,
               opts[:workspace_id],
               opts[:session_id],
               opts[:task_id],
               opts[:record_type],
               top_k
             ]) do
          {:ok, %{rows: rows}} ->
            base = Sqlite.search(query, Keyword.put(opts, :top_k, top_k * 2))

            similarity_map =
              rows
              |> Enum.into(%{}, fn [id, similarity] -> {id, similarity || 0.0} end)

            entries =
              base.entries
              |> Enum.map(fn entry ->
                similarity = Map.get(similarity_map, entry.id, entry.semantic_score)
                Map.put(entry, :semantic_score, Float.round(similarity, 4))
              end)
              |> Enum.sort_by(
                &{Map.has_key?(similarity_map, &1.id), &1.semantic_score, &1.score},
                :desc
              )
              |> Enum.take(top_k)

            %{base | entries: entries, total_count: length(entries), semantic_available: true}

          _error ->
            Sqlite.search(query, opts)
        end

      _error ->
        Sqlite.search(query, opts)
    end
  end

  defp pgvector_enabled? do
    case SQL.query(Repo, "SELECT 1 FROM pg_extension WHERE extname = 'vector' LIMIT 1", []) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end
end
