defmodule ControlKeel.MCP.ToolGroupTracker do
  @moduledoc """
  Tracks tool usage to enable adaptive tool group selection.
  Learns which tools are actually used per project and suggests optimal groups.
  Persists usage data to disk so it survives VM restarts.
  """

  alias ControlKeel.MCP.ToolGroups

  use GenServer
  require Logger

  @table_name :tool_group_usage
  @retention_period :timer.hours(24 * 7)
  @flush_interval :timer.minutes(5)
  @persistence_dir ".controlkeel"
  @persistence_file "tool_usage.json"

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def track_tool_usage(project_root, tool_name) do
    GenServer.cast(__MODULE__, {:track_usage, project_root, tool_name})
  end

  def suggest_groups(project_root) do
    GenServer.call(__MODULE__, {:suggest_groups, project_root}, 3_000)
  end

  def reset_project(project_root) do
    GenServer.cast(__MODULE__, {:reset_project, project_root})
  end

  def flush_to_disk(project_root) do
    GenServer.call(__MODULE__, {:flush_to_disk, project_root})
  end

  def load_from_disk(project_root) do
    GenServer.call(__MODULE__, {:load_from_disk, project_root})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup()
    schedule_flush()
    {:ok, %{project_roots: MapSet.new(), loaded_roots: MapSet.new()}}
  end

  @impl true
  def handle_cast({:track_usage, project_root, tool_name}, state) do
    state =
      if is_binary(project_root) and project_root != "" and
           not MapSet.member?(state.loaded_roots, project_root) do
        do_load_from_disk(project_root)

        %{
          state
          | project_roots: MapSet.put(state.project_roots, project_root),
            loaded_roots: MapSet.put(state.loaded_roots, project_root)
        }
      else
        state
      end

    key = usage_key(project_root, tool_name)
    now = System.system_time(:second)

    case :ets.lookup(@table_name, key) do
      [{^key, _ts, count}] ->
        :ets.insert(@table_name, {key, now, count + 1})

      [] ->
        :ets.insert(@table_name, {key, now, 1})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:reset_project, project_root}, state) do
    project_root
    |> project_entries()
    |> Enum.each(fn {key, _timestamp, _count} -> :ets.delete(@table_name, key) end)

    {:noreply, %{state | loaded_roots: MapSet.delete(state.loaded_roots, project_root)}}
  end

  @impl true
  def handle_call({:suggest_groups, project_root}, _from, state) do
    groups = suggest_optimal_groups(project_root)
    {:reply, groups, state}
  end

  @impl true
  def handle_call({:flush_to_disk, project_root}, _from, state) do
    result = do_flush_to_disk(project_root)
    new_state = %{state | project_roots: MapSet.put(state.project_roots, project_root)}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:load_from_disk, project_root}, _from, state) do
    result = do_load_from_disk(project_root)

    new_state = %{
      state
      | project_roots: MapSet.put(state.project_roots, project_root),
        loaded_roots: MapSet.put(state.loaded_roots, project_root)
    }

    {:reply, result, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_all, state) do
    Enum.each(state.project_roots, &do_flush_to_disk/1)
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.project_roots, &do_flush_to_disk/1)
    :ok
  end

  # Private Functions

  defp usage_key(project_root, tool_name) do
    "#{project_root}:#{tool_name}"
  end

  defp project_entries(project_root) do
    prefix = project_root <> ":"

    @table_name
    |> :ets.tab2list()
    |> Enum.filter(fn
      {key, _timestamp, _count} when is_binary(key) -> String.starts_with?(key, prefix)
      _entry -> false
    end)
  end

  defp collect_usage_stats(project_root) do
    entries = project_entries(project_root)

    if entries == [] do
      %{total_calls: 0, unique_tools: 0}
    else
      total_calls = entries |> Enum.map(fn {_key, _ts, count} -> count end) |> Enum.sum()

      unique_tools =
        entries |> MapSet.new(fn {key, _ts, _count} -> key end) |> MapSet.size()

      %{total_calls: total_calls, unique_tools: unique_tools}
    end
  end

  defp suggest_optimal_groups(project_root) do
    used_tools =
      project_entries(project_root)
      |> Enum.map(fn {key, _timestamp, _count} ->
        String.replace_prefix(key, project_root <> ":", "")
      end)
      |> Enum.uniq()

    tool_to_group = get_tool_to_group_mapping()

    needed_groups =
      used_tools
      |> Enum.flat_map(fn tool ->
        Map.get(tool_to_group, tool, [])
      end)
      |> Enum.uniq()

    baseline_groups = ["core", "governance"]
    suggested_groups = Enum.uniq(baseline_groups ++ needed_groups)

    %{
      suggested: suggested_groups,
      reason: "Based on #{length(used_tools)} unique tools used in this project",
      usage_stats: collect_usage_stats(project_root)
    }
  end

  defp get_tool_to_group_mapping do
    ToolGroups.tool_to_group_map()
    |> Enum.map(fn {tool, group} -> {tool, [group]} end)
    |> Map.new()
  end

  defp cleanup_old_entries do
    cutoff = System.system_time(:second) - @retention_period

    :ets.select_delete(@table_name, [
      {{:_, :"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end

  defp schedule_flush do
    Process.send_after(self(), :flush_all, @flush_interval)
  end

  defp do_flush_to_disk(nil), do: {:error, :no_project_root}
  defp do_flush_to_disk(""), do: {:error, :no_project_root}

  defp do_flush_to_disk(project_root) do
    entries = project_entries(project_root)
    file_path = persistence_path(project_root)
    dir_path = Path.dirname(file_path)

    json_entries =
      Enum.map(entries, fn {key, last_used, count} ->
        %{"key" => key, "count" => count, "last_used" => last_used}
      end)

    payload = %{"version" => 1, "entries" => json_entries}

    with :ok <- File.mkdir_p(dir_path),
         :ok <- File.write(file_path, Jason.encode!(payload, pretty: true) <> "\n") do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to flush tool usage to disk: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_load_from_disk(nil), do: {:ok, 0}
  defp do_load_from_disk(""), do: {:ok, 0}

  defp do_load_from_disk(project_root) do
    file_path = persistence_path(project_root)

    case File.read(file_path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"version" => 1, "entries" => entries}} when is_list(entries) ->
            Enum.each(entries, fn %{"key" => key, "count" => count, "last_used" => last_used} ->
              case :ets.lookup(@table_name, key) do
                [] -> :ets.insert(@table_name, {key, last_used, count})
                _ -> :ok
              end
            end)

            {:ok, length(entries)}

          {:ok, _} ->
            Logger.warning("Tool usage file has unexpected format: #{file_path}")
            {:error, :invalid_format}

          {:error, %Jason.DecodeError{} = e} ->
            Logger.warning(
              "Corrupt tool usage file, starting fresh: #{file_path} (#{Exception.message(e)})"
            )

            {:error, :corrupt}
        end

      {:error, :enoent} ->
        {:ok, 0}

      {:error, reason} ->
        Logger.warning("Failed to load tool usage from disk: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp persistence_path(project_root) do
    Path.join([project_root, @persistence_dir, @persistence_file])
  end
end
