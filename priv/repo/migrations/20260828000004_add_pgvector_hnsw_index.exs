defmodule ControlKeel.Repo.Migrations.AddPgvectorHnswIndex do
  @moduledoc """
  Adds an HNSW index for cosine vector search on `memory_embeddings`.

  Cloud (Postgres + pgvector) semantic search currently sequential-scans:
  `ORDER BY me.embedding_text::vector <=> $1::vector`. This migration creates
  an HNSW expression index with `vector_cosine_ops` so that ORDER BY is
  index-backed. `embedding_text` stores JSON arrays (`[0.1,0.2,...]`), which
  is exactly pgvector's text literal format, so the cast in the index
  expression matches the query expression.

  Local (SQLite) is a no-op — local semantic search is pure-Elixir cosine.

  Idempotent: skips when the `vector` extension is absent (plain Postgres
  without pgvector installed) or the index already exists.
  """
  use Ecto.Migration

  @index_name "memory_embeddings_hnsw_cosine_idx"

  def up do
    if postgres?() do
      # Best-effort: don't fail when pgvector isn't installed on the image
      # (e.g. plain Postgres in test-postgres). CREATE EXTENSION vector fails
      # with feature_not_supported if the .so isn't present.
      execute("""
      DO $$ BEGIN
        BEGIN
          CREATE EXTENSION vector;
          EXCEPTION WHEN duplicate_object THEN NULL;
          WHEN OTHERS THEN NULL;
        END;
        IF EXISTS (
          SELECT 1 FROM pg_extension WHERE extname = 'vector'
        ) AND NOT EXISTS (
          SELECT 1 FROM pg_indexes
          WHERE tablename = 'memory_embeddings' AND indexname = '#{@index_name}'
        ) THEN
          EXECUTE 'CREATE INDEX #{@index_name} ON memory_embeddings ' ||
                  'USING hnsw ((embedding_text::vector) vector_cosine_ops)';
        END IF;
      END $$;
      """)
    end
  end

  def down do
    if postgres?() do
      execute("DROP INDEX IF EXISTS #{@index_name}")
    end
  end

  defp postgres?, do: repo().__adapter__() == Ecto.Adapters.Postgres
end
