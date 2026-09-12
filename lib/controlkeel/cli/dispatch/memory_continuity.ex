defmodule ControlKeel.CLI.Dispatch.MemoryContinuity do
  @moduledoc false

  alias ControlKeel.CLI.Output
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Project.Binding
  alias ControlKeel.Project.Root
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :session_list, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      sessions = Mission.list_recent_sessions(20)

      payload = %{
        "sessions" =>
          Enum.map(sessions, fn session ->
            %{
              "id" => session.id,
              "title" => session.title,
              "risk_tier" => session.risk_tier,
              "workspace_id" => session.workspace_id
            }
          end)
      }

      Output.render_format(format, payload, fn _ ->
        if sessions == [] do
          ["No missions found. Start one with: controlkeel init"]
        else
          ["Recent missions:"] ++
            Enum.map(sessions, fn session ->
              "##{session.id} #{session.title} — #{session.risk_tier} risk — workspace ##{session.workspace_id}"
            end)
        end
      end)
    end
  end

  # Back-compat: dispatch without options.
  def run_command(%{command: :session_list} = parsed, root) do
    run_command(Map.put(parsed, :options, []), root)
  end

  def run_command(%{command: :session_switch, args: [session_id]}, project_root) do
    with {:ok, parsed_id} <- parse_id(session_id),
         %{} = target <- Mission.get_session(parsed_id),
         {:ok, binding, _current_session, _mode} <- ensure_local_project(project_root),
         updated <-
           binding
           |> Map.put("session_id", target.id)
           |> Map.put("workspace_id", target.workspace_id),
         {:ok, written} <-
           Binding.write_effective(updated, project_root, mode: binding_write_mode(binding)),
         {:ok, _updated_session} <-
           Mission.attach_session_runtime_context(target.id, %{
             "project_root" => Root.resolve(project_root)
           }) do
      {:ok,
       [
         "Switched ControlKeel project binding to mission ##{target.id}: #{target.title}.",
         "Project root: #{written["project_root"]}."
       ]}
    else
      {:error, :invalid_id} -> {:error, "Invalid mission id: #{session_id}"}
      nil -> {:error, "Mission not found: #{session_id}"}
      {:error, reason} -> {:error, "Could not switch mission: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :memory_search, args: [query], options: options}, project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        result =
          Memory.search(query, %{
            workspace_id: session.workspace_id,
            session_id: options[:session_id] || session.id,
            record_type: options[:type]
          })

        if result.entries == [] do
          {:ok, ["No memory records matched the search query."]}
        else
          {:ok,
           Enum.map(result.entries, fn record ->
             "[#{record.record_type}] #{record.title} (score #{Float.round(record.score, 2)})"
           end)}
        end

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end
end
