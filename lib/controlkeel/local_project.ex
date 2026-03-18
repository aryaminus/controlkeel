defmodule ControlKeel.LocalProject do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.ProjectBinding

  def init(attrs, project_root \\ File.cwd!()) when is_map(attrs) do
    root = Path.expand(project_root)

    case ProjectBinding.read(root) do
      {:ok, binding} ->
        case Mission.get_session(binding["session_id"]) do
          nil ->
            create_and_bind(attrs, root)

          _session ->
            with :ok <- ProjectBinding.ensure_gitignore(root),
                 :ok <- ProjectBinding.ensure_mcp_wrapper(root) do
              {:ok, binding, :existing}
            end
        end

      {:error, :not_found} ->
        create_and_bind(attrs, root)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def load(project_root \\ File.cwd!()) do
    root = Path.expand(project_root)

    with {:ok, binding} <- ProjectBinding.read(root),
         session when not is_nil(session) <- Mission.get_session_context(binding["session_id"]) do
      {:ok, binding, session}
    else
      nil -> {:error, :session_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def default_init_attrs(project_root, overrides \\ %{}) do
    root = Path.expand(project_root)
    project_name = Map.get(overrides, "project_name", Path.basename(root))

    %{
      "project_name" => project_name,
      "industry" => Map.get(overrides, "industry", "web"),
      "agent" => Map.get(overrides, "agent", "claude"),
      "idea" =>
        Map.get(overrides, "idea", "Build the first governed workflow for #{project_name}"),
      "users" => Map.get(overrides, "users", "project operators"),
      "data" => Map.get(overrides, "data", "repo code and configuration"),
      "features" => Map.get(overrides, "features", "validation, budgets, release checks"),
      "budget" => Map.get(overrides, "budget", "$30/month"),
      "project_root" => root
    }
  end

  defp create_and_bind(attrs, root) do
    launch_attrs = default_init_attrs(root, attrs)

    with {:ok, session} <- Mission.create_launch(launch_attrs),
         :ok <- ProjectBinding.ensure_gitignore(root),
         :ok <- ProjectBinding.ensure_mcp_wrapper(root),
         {:ok, binding} <-
           ProjectBinding.write(
             %{
               "workspace_id" => session.workspace_id,
               "session_id" => session.id,
               "agent" => Map.get(launch_attrs, "agent", "claude"),
               "attached_agents" => %{}
             },
             root
           ) do
      emit_initialized(session, root, launch_attrs)
      {:ok, binding, :created}
    end
  end

  defp emit_initialized(session, root, launch_attrs) do
    :telemetry.execute(
      [:controlkeel, :local_project, :initialized],
      %{count: 1},
      %{
        session_id: session.id,
        workspace_id: session.workspace_id,
        project_root: root,
        agent: Map.get(launch_attrs, "agent", "claude")
      }
    )
  end
end
