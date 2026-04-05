defmodule ControlKeel.LocalProject do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ProjectBinding
  alias ControlKeel.SessionTranscript

  def init(attrs, project_root \\ File.cwd!()) when is_map(attrs) do
    root = ProjectRoot.resolve(project_root)

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
    root = ProjectRoot.resolve(project_root)

    with {:ok, binding, _mode} <- ProjectBinding.read_effective(root),
         session when not is_nil(session) <- Mission.get_session_context(binding["session_id"]) do
      {:ok, binding, session}
    else
      nil -> {:error, :session_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_or_bootstrap(project_root \\ File.cwd!(), overrides \\ %{}, opts \\ []) do
    root = ProjectRoot.resolve(project_root)

    case load(root) do
      {:ok, binding, session} ->
        {:ok, binding, session, :existing}

      {:error, :not_found} ->
        bootstrap(root, overrides, opts)

      {:error, :session_not_found} ->
        bootstrap(root, overrides, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def bootstrap(project_root \\ File.cwd!(), overrides \\ %{}, opts \\ []) do
    root = ProjectRoot.resolve(project_root)
    ephemeral_ok? = Keyword.get(opts, :ephemeral_ok, true)
    bootstrap_metadata = %{"auto_bootstrapped" => true}
    launch_attrs = default_init_attrs(root, overrides)

    with {:ok, session} <- Mission.create_launch(launch_attrs) do
      case create_binding(root, session, launch_attrs, bootstrap_metadata) do
        {:ok, binding, mode} ->
          {:ok, binding, Mission.get_session_context(session.id), mode}

        {:error, reason}
        when reason in [:project_write_failed, :gitignore_failed, :wrapper_failed] ->
          if ephemeral_ok? do
            create_ephemeral_binding(root, session, launch_attrs, bootstrap_metadata)
          else
            {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def default_init_attrs(project_root, overrides \\ %{}) do
    root = ProjectRoot.resolve(project_root)
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
           ),
         {:ok, _updated_session} <-
           Mission.attach_session_runtime_context(session.id, %{"project_root" => root}) do
      record_bootstrap_event(session, root, "project")
      emit_initialized(session, root, launch_attrs)
      {:ok, binding, :created}
    end
  end

  defp create_binding(root, session, launch_attrs, bootstrap_metadata) do
    with :ok <- ensure_project_files(root),
         {:ok, binding} <-
           ProjectBinding.write(
             %{
               "workspace_id" => session.workspace_id,
               "session_id" => session.id,
               "agent" => Map.get(launch_attrs, "agent", "claude"),
               "attached_agents" => %{},
               "bootstrap" => Map.put(bootstrap_metadata, "mode", "project")
             },
             root
           ),
         {:ok, _updated_session} <-
           Mission.attach_session_runtime_context(session.id, %{"project_root" => root}) do
      record_bootstrap_event(session, root, "project")
      emit_initialized(session, root, launch_attrs)
      {:ok, binding, :bootstrapped_project}
    else
      {:error, _reason} = error -> normalize_project_write_error(error)
    end
  end

  defp create_ephemeral_binding(root, session, launch_attrs, bootstrap_metadata) do
    with {:ok, binding} <-
           ProjectBinding.write_ephemeral(
             %{
               "workspace_id" => session.workspace_id,
               "session_id" => session.id,
               "agent" => Map.get(launch_attrs, "agent", "claude"),
               "attached_agents" => %{},
               "bootstrap" => Map.put(bootstrap_metadata, "mode", "ephemeral")
             },
             root
           ),
         {:ok, _updated_session} <-
           Mission.attach_session_runtime_context(session.id, %{"project_root" => root}) do
      record_bootstrap_event(session, root, "ephemeral")
      emit_initialized(session, root, launch_attrs)
      {:ok, binding, Mission.get_session_context(session.id), :bootstrapped_ephemeral}
    end
  end

  defp ensure_project_files(root) do
    with :ok <- ProjectBinding.ensure_gitignore(root),
         :ok <- ProjectBinding.ensure_mcp_wrapper(root) do
      :ok
    else
      {:error, _reason} = error -> error
      error -> {:error, error}
    end
  end

  defp normalize_project_write_error({:error, :enoent}), do: {:error, :project_write_failed}
  defp normalize_project_write_error({:error, :eacces}), do: {:error, :project_write_failed}
  defp normalize_project_write_error({:error, :eperm}), do: {:error, :project_write_failed}
  defp normalize_project_write_error({:error, reason}), do: {:error, reason}

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

  defp record_bootstrap_event(session, root, mode) do
    SessionTranscript.record(%{
      session_id: session.id,
      event_type: "session.bootstrap",
      actor: "system",
      summary: "ControlKeel bootstrapped the project workspace.",
      body: "Project root: #{root}",
      payload: %{"mode" => mode, "project_root" => root}
    })
  end
end
