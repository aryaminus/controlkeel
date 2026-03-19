defmodule ControlKeel.Memory.Store do
  @moduledoc false

  alias ControlKeel.Memory.Store.{Pgvector, Sqlite}

  def mode do
    configured =
      System.get_env("CONTROLKEEL_MEMORY_STORE") ||
        Application.get_env(:controlkeel, :memory_store, "auto")

    case configured do
      "sqlite" -> :sqlite
      "pgvector" -> :pgvector
      :sqlite -> :sqlite
      :pgvector -> :pgvector
      _auto -> if(Pgvector.available?(), do: :pgvector, else: :sqlite)
    end
  end

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
    case mode() do
      :pgvector -> Pgvector.search(query, opts)
      :sqlite -> Sqlite.search(query, opts)
    end
  end
end
