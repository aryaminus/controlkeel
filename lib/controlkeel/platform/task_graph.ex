defmodule ControlKeel.Platform.TaskGraph do
  @moduledoc false

  alias ControlKeel.Mission.Decomposition

  def build_edges(tasks) when is_list(tasks) do
    architecture =
      Enum.find(tasks, &(track(&1) == "architecture"))

    release =
      Enum.find(tasks, &(track(&1) == "release"))

    feature_tasks = Enum.filter(tasks, &(track(&1) == "feature"))

    architecture_edges =
      if architecture do
        Enum.map(feature_tasks, fn task ->
          edge_attrs(architecture, task, "blocks")
        end)
      else
        []
      end

    release_edges =
      if release do
        feature_tasks
        |> Enum.map(fn task -> edge_attrs(task, release, "blocks") end)
        |> then(fn edges ->
          if architecture do
            [edge_attrs(architecture, release, "soft_gate") | edges]
          else
            edges
          end
        end)
      else
        []
      end

    Enum.uniq_by(architecture_edges ++ release_edges, &{&1.from_task_id, &1.to_task_id})
  end

  def ready_task_ids(tasks, edges) do
    done_ids =
      tasks
      |> Enum.filter(&(&1.status in ["done", "verified"]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    incoming =
      Enum.group_by(edges, & &1.to_task_id)

    tasks
    |> Enum.filter(fn task ->
      task.status in ["queued", "ready", "in_progress"] and
        Map.get(incoming, task.id, [])
        |> Enum.all?(fn edge -> MapSet.member?(done_ids, edge.from_task_id) end)
    end)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
  end

  defp edge_attrs(from_task, to_task, dependency_type) do
    %{
      session_id: from_task.session_id,
      from_task_id: from_task.id,
      to_task_id: to_task.id,
      dependency_type: dependency_type,
      metadata: %{
        "from_track" => track(from_task),
        "to_track" => track(to_task),
        "decomposition" =>
          Decomposition.edge_summary(
            %{
              from_task_id: from_task.id,
              to_task_id: to_task.id,
              dependency_type: dependency_type
            },
            [from_task, to_task]
          )
      }
    }
  end

  defp track(task) do
    metadata = Map.get(task, :metadata, %{}) || %{}
    metadata["track"] || metadata[:track]
  end
end
