defmodule ControlKeel.Mission.Decomposition do
  @moduledoc false

  @node_types ~w(analyze synthesize implement delegate review_gate)
  @execution_modes ~w(serial parallel recursive human_gate)
  @context_strategies ~w(focused wide_scan evidence_first resume_from_proof)

  def session_summary(tasks, edges) do
    tasks = normalize_list(tasks)
    edges = normalize_list(edges)
    task_summaries = Enum.map(tasks, &task_summary(&1, tasks, edges))

    %{
      "strategy" => "bounded_recursive_delivery_v1",
      "node_count" => length(task_summaries),
      "edge_count" => length(edges),
      "root_count" => Enum.count(task_summaries, &(&1["incoming_dependencies"] == 0)),
      "max_depth" =>
        Enum.max_by(task_summaries, & &1["depth"], fn -> %{"depth" => 0} end)["depth"],
      "branching_nodes" => Enum.count(task_summaries, &(&1["outgoing_dependencies"] > 1)),
      "review_required_nodes" => Enum.count(task_summaries, & &1["review_required"]),
      "delegated_nodes" => Enum.count(task_summaries, &(&1["node_type"] == "delegate")),
      "recursive_nodes" => Enum.count(task_summaries, &(&1["execution_mode"] == "recursive")),
      "node_types" => count_by(task_summaries, "node_type"),
      "execution_modes" => count_by(task_summaries, "execution_mode"),
      "context_strategies" => count_by(task_summaries, "context_strategy"),
      "trace_ready" => task_summaries != []
    }
  end

  def task_summary(task, tasks \\ [], edges \\ [])

  def task_summary(task, tasks, edges) when is_map(task) do
    tasks = normalize_list(tasks)
    edges = normalize_list(edges)
    metadata = stringify_keys(Map.get(task, :metadata, %{}) || %{})
    decomposition = metadata |> Map.get("decomposition", %{}) |> stringify_keys()
    defaults = default_decomposition(task, metadata)
    incoming = Enum.filter(edges, &(&1.to_task_id == task.id))
    outgoing = Enum.filter(edges, &(&1.from_task_id == task.id))

    %{
      "node_type" =>
        normalize_enum(decomposition["node_type"], @node_types, defaults["node_type"]),
      "execution_mode" =>
        normalize_enum(
          decomposition["execution_mode"],
          @execution_modes,
          defaults["execution_mode"]
        ),
      "context_strategy" =>
        normalize_enum(
          decomposition["context_strategy"],
          @context_strategies,
          defaults["context_strategy"]
        ),
      "review_required" =>
        normalize_boolean(decomposition["review_required"], defaults["review_required"]),
      "manager_note" =>
        normalize_string(decomposition["manager_note"]) || defaults["manager_note"],
      "trace_label" =>
        normalize_string(decomposition["trace_label"]) || default_trace_label(task),
      "depth" => depth_for(task.id, tasks, edges),
      "incoming_dependencies" => length(incoming),
      "outgoing_dependencies" => length(outgoing),
      "blocking_children" => Enum.count(outgoing, &(&1.dependency_type == "blocks")),
      "soft_gates" => Enum.count(incoming ++ outgoing, &(&1.dependency_type == "soft_gate"))
    }
  end

  def edge_summary(edge, tasks \\ []) when is_map(edge) and is_list(tasks) do
    from_task = Enum.find(tasks, &(&1.id == edge.from_task_id))
    to_task = Enum.find(tasks, &(&1.id == edge.to_task_id))

    %{
      "relation" =>
        case edge.dependency_type do
          "soft_gate" -> "review_gate"
          _other -> "sequence"
        end,
      "from_node_type" => task_type(from_task),
      "to_node_type" => task_type(to_task)
    }
  end

  def default_metadata_for_task(track, phase) do
    defaults =
      default_decomposition(%{id: nil}, %{"track" => track, "security_workflow_phase" => phase})

    %{
      "node_type" => defaults["node_type"],
      "execution_mode" => defaults["execution_mode"],
      "context_strategy" => defaults["context_strategy"],
      "review_required" => defaults["review_required"],
      "manager_note" => defaults["manager_note"]
    }
  end

  defp task_type(nil), do: nil
  defp task_type(task), do: task_summary(task)["node_type"]

  defp default_trace_label(task) do
    case Map.get(task, :title) do
      value when is_binary(value) and value != "" -> value
      _other -> "task"
    end
  end

  defp depth_for(task_id, tasks, edges) do
    task_ids = MapSet.new(Enum.map(tasks, & &1.id))

    incoming =
      edges
      |> Enum.filter(
        &(MapSet.member?(task_ids, &1.from_task_id) and MapSet.member?(task_ids, &1.to_task_id))
      )
      |> Enum.group_by(& &1.to_task_id, & &1.from_task_id)

    do_depth(task_id, incoming, MapSet.new())
  end

  defp do_depth(task_id, incoming, seen) do
    if MapSet.member?(seen, task_id) do
      0
    else
      predecessors = Map.get(incoming, task_id, [])

      case predecessors do
        [] ->
          0

        values ->
          1 + Enum.max(Enum.map(values, &do_depth(&1, incoming, MapSet.put(seen, task_id))))
      end
    end
  end

  defp default_decomposition(_task, metadata) do
    track = normalize_string(metadata["track"])
    phase = normalize_string(metadata["security_workflow_phase"])

    cond do
      phase == "discovery" ->
        %{
          "node_type" => "analyze",
          "execution_mode" => "serial",
          "context_strategy" => "wide_scan",
          "review_required" => true,
          "manager_note" => "Discover broadly, then narrow scope before mutation."
        }

      phase == "triage" ->
        %{
          "node_type" => "synthesize",
          "execution_mode" => "serial",
          "context_strategy" => "evidence_first",
          "review_required" => true,
          "manager_note" => "Compress evidence into severity, ownership, and next-step decisions."
        }

      phase == "reproduction" ->
        %{
          "node_type" => "delegate",
          "execution_mode" => "recursive",
          "context_strategy" => "evidence_first",
          "review_required" => true,
          "manager_note" => "Keep reproduction isolated and artifact-driven."
        }

      phase == "patch" ->
        %{
          "node_type" => "implement",
          "execution_mode" => "serial",
          "context_strategy" => "focused",
          "review_required" => false,
          "manager_note" => "Draft the smallest viable remediation diff."
        }

      phase in ["validation", "disclosure"] ->
        %{
          "node_type" => "review_gate",
          "execution_mode" => "human_gate",
          "context_strategy" => "resume_from_proof",
          "review_required" => true,
          "manager_note" => "Gate release on evidence, proof, and redaction state."
        }

      track == "architecture" ->
        %{
          "node_type" => "analyze",
          "execution_mode" => "serial",
          "context_strategy" => "wide_scan",
          "review_required" => true,
          "manager_note" => "Frame the solution before parallel implementation begins."
        }

      track in ["feature", "patch"] ->
        %{
          "node_type" => "implement",
          "execution_mode" => "serial",
          "context_strategy" => "focused",
          "review_required" => false,
          "manager_note" => "Keep edits scoped to the current slice."
        }

      track in ["verify", "release"] ->
        %{
          "node_type" => "review_gate",
          "execution_mode" => "human_gate",
          "context_strategy" => "resume_from_proof",
          "review_required" => true,
          "manager_note" => "Verify and govern the release boundary before completion."
        }

      true ->
        %{
          "node_type" => "synthesize",
          "execution_mode" => "serial",
          "context_strategy" => "focused",
          "review_required" => false,
          "manager_note" => "Decompose work into the next bounded step."
        }
    end
  end

  defp count_by(entries, key) do
    entries
    |> Enum.group_by(&Map.get(&1, key))
    |> Enum.reject(fn {value, _rows} -> is_nil(value) end)
    |> Enum.into(%{}, fn {value, rows} -> {value, length(rows)} end)
  end

  defp normalize_enum(value, allowed, default) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in allowed, do: trimmed, else: default
  end

  defp normalize_enum(_value, _allowed, default), do: default

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_value), do: nil

  defp normalize_boolean(value, _default) when value in [true, false], do: value
  defp normalize_boolean(_value, default), do: default

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(_value), do: []

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {to_string(key), normalize_value(value)}
    end)
  end

  defp stringify_keys(_other), do: %{}

  defp normalize_value(value) when is_map(value), do: stringify_keys(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
