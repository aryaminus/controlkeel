defmodule ControlKeel.Memory do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Memory.{Embeddings, Record, Store}
  alias ControlKeel.Repo

  @record_types ~w(brief task finding proof checkpoint budget decision incident)

  def record_types, do: @record_types

  def get_record(id), do: Repo.get(Record, id)
  def get_record!(id), do: Repo.get!(Record, id)

  def record(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, record} <-
           %Record{}
           |> Record.changeset(attrs)
           |> Repo.insert() do
      _ = Embeddings.upsert_record_embedding(record)
      {:ok, record}
    end
  end

  def archive_record(%Record{} = record) do
    record
    |> Record.changeset(%{archived_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def archive_record(id) when is_integer(id) do
    case get_record(id) do
      nil -> {:error, :not_found}
      record -> archive_record(record)
    end
  end

  def search(query, opts \\ []) when is_binary(query) do
    Store.search(query, normalize_search_opts(opts))
  end

  def retrieve_for_task(session, task, opts \\ [])

  def retrieve_for_task(_session, nil, _opts) do
    %{entries: [], query: nil, total_count: 0, semantic_available: false}
  end

  def retrieve_for_task(session, task, opts) do
    findings = opts[:findings] || []
    domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])

    query =
      [
        session.objective,
        task.title,
        task.validation_gate,
        Enum.map(findings, & &1.category) |> Enum.uniq() |> Enum.join(" "),
        domain_pack
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    search(
      query,
      workspace_id: session.workspace_id,
      session_id: session.id,
      task_id: task.id,
      domain_pack: domain_pack,
      top_k: opts[:top_k] || Store.top_k()
    )
  end

  def list_related_to_task(task_id, limit \\ 5) when is_integer(task_id) do
    Record
    |> where([r], r.task_id == ^task_id and is_nil(r.archived_at))
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp normalize_attrs(attrs) do
    attrs =
      Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

    %{
      workspace_id: attrs["workspace_id"],
      session_id: attrs["session_id"],
      task_id: attrs["task_id"],
      record_type: normalize_record_type(attrs["record_type"]),
      title: attrs["title"] || "Untitled memory record",
      summary: attrs["summary"] || attrs["title"] || "Recorded event",
      body: attrs["body"] || attrs["summary"] || "",
      tags: normalize_tags(attrs["tags"], attrs["metadata"]),
      source_type: attrs["source_type"] || "system",
      source_id: normalize_source_id(attrs["source_id"]),
      metadata: normalize_metadata(attrs["metadata"]),
      archived_at: attrs["archived_at"]
    }
  end

  defp normalize_search_opts(opts) do
    opts
    |> Enum.into(%{})
    |> Enum.into([], fn {key, value} -> {key, value} end)
  end

  defp normalize_tags(value, _metadata) when is_list(value), do: Enum.map(value, &to_string/1)

  defp normalize_tags(_value, metadata) when is_map(metadata) do
    metadata
    |> Map.take(["domain_pack", "rule_id", "status"])
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp normalize_tags(_value, _metadata), do: []

  defp normalize_record_type(nil), do: "decision"

  defp normalize_record_type(value) do
    value = to_string(value)
    if value in @record_types, do: value, else: "decision"
  end

  defp normalize_source_id(nil), do: nil
  defp normalize_source_id(value) when is_binary(value), do: value
  defp normalize_source_id(value), do: to_string(value)

  defp normalize_metadata(metadata) when is_map(metadata) do
    Enum.into(metadata, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), normalize_metadata(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp normalize_metadata(_value), do: %{}
end
