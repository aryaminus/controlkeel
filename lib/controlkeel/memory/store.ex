defmodule ControlKeel.Memory.Store do
  @moduledoc false

  alias ControlKeel.Memory.Store.{Pgvector, Sqlite}
  alias ControlKeel.Runtime

  def mode do
    configured =
      System.get_env("CONTROLKEEL_MEMORY_STORE") ||
        Application.get_env(:controlkeel, :memory_store, "auto")

    case configured do
      "sqlite" ->
        :sqlite

      "pgvector" ->
        :pgvector

      :sqlite ->
        :sqlite

      :pgvector ->
        :pgvector

      _auto ->
        if(Runtime.memory_store_mode() == :pgvector and Pgvector.available?(),
          do: :pgvector,
          else: :sqlite
        )
    end
  end

  @supported_retrieval_strategies ~w(single_vector bm25 hybrid_bm25_vector late_interaction late_interaction_rerank)a

  def retrieval_strategy do
    Application.get_env(:controlkeel, :memory_retrieval_strategy, :single_vector)
  end

  def retrieval_strategy_label do
    case retrieval_strategy() do
      :single_vector -> "single_vector"
      :bm25 -> "bm25"
      :hybrid_bm25_vector -> "hybrid_bm25_vector"
      :late_interaction -> "late_interaction"
      :late_interaction_rerank -> "late_interaction_rerank"
    end
  end

  def supported_retrieval_strategies, do: @supported_retrieval_strategies

  def top_k do
    System.get_env("CONTROLKEEL_MEMORY_TOP_K")
    |> case do
      nil ->
        5

      value ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> 5
        end
    end
  end

  def search(query, opts \\ []) do
    result =
      case mode() do
        :pgvector -> Pgvector.search(query, opts)
        :sqlite -> Sqlite.search(query, opts)
      end

    case result do
      %{} = r -> Map.put_new(r, :retrieval_strategy, retrieval_strategy_label())
      other -> other
    end
  end
end
