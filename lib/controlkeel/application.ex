defmodule ControlKeel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @supervisor_name ControlKeel.Supervisor

  def start_link do
    opts = [strategy: :one_for_one, name: @supervisor_name]

    case Supervisor.start_link(base_children(), opts) do
      {:ok, supervisor} ->
        with :ok <- maybe_run_migrations(),
             :ok <- start_late_children(supervisor) do
          {:ok, supervisor}
        else
          {:error, reason} ->
            Supervisor.stop(supervisor)
            {:error, reason}

          other ->
            Supervisor.stop(supervisor)
            {:error, other}
        end

      other ->
        other
    end
  end

  def config_change(changed, _new, removed) do
    ControlKeelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp base_children do
    [
      ControlKeelWeb.Telemetry
    ]
  end

  defp late_children do
    [
      ControlKeel.Repo
    ] ++
      cloud_repo_children() ++
      [
        ControlKeel.Runtime.bus_module()
      ] ++
      analytics_children() ++
      mcp_tail_children()
  end

  # Stdio MCP only needs Repo, bus, PubSub, skills activation, and the MCP
  # supervisor. Starting ControlKeelWeb.Endpoint pulls in HTTP listeners,
  # endpoint init, and DNS cluster work that can exceed client handshake timeouts.
  defp mcp_tail_children do
    pubsub_skills_mcp = [
      {Phoenix.PubSub, name: ControlKeel.PubSub},
      ControlKeel.Skills.Activation,
      {DynamicSupervisor, strategy: :one_for_one, name: ControlKeel.MCP.Supervisor}
    ]

    if mcp_stdio_mode?() do
      pubsub_skills_mcp
    else
      [
        {DNSCluster, query: Application.get_env(:controlkeel, :dns_cluster_query) || :ignore}
      ] ++ pubsub_skills_mcp ++ [ControlKeelWeb.Endpoint]
    end
  end

  defp mcp_stdio_mode? do
    System.get_env("CK_MCP_MODE") in ~w(1 true TRUE yes YES)
  end

  defp start_late_children(supervisor) do
    Enum.reduce_while(late_children(), :ok, fn child, :ok ->
      case Supervisor.start_child(supervisor, child) do
        {:ok, _pid} -> {:cont, :ok}
        {:ok, _pid, _info} -> {:cont, :ok}
        :ignore -> {:cont, :ok}
        {:error, {:already_started, _pid}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_run_migrations do
    if skip_migrations?() do
      :ok
    else
      migration_runner().()
    end
  end

  defp skip_migrations?() do
    not release_runtime?()
  end

  defp release_runtime? do
    System.get_env("RELEASE_NAME") not in [nil, ""] or
      System.get_env("RELEASE_ROOT") not in [nil, ""] or
      System.get_env("__BURRITO") not in [nil, ""]
  end

  defp migration_runner do
    Application.get_env(:controlkeel, :application_migration_runner, &run_migrations/0)
  end

  defp run_migrations do
    Application.fetch_env!(:controlkeel, :ecto_repos)
    |> Enum.reduce_while(:ok, fn repo, :ok ->
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true), pool_size: 2) do
        {:ok, _versions, _apps} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp analytics_children do
    if Application.get_env(:controlkeel, :analytics_telemetry_handler, true) do
      [ControlKeel.Analytics.TelemetryHandler]
    else
      []
    end
  end

  defp cloud_repo_children do
    if ControlKeel.Runtime.cloud_repo_enabled?() do
      [ControlKeel.CloudRepo]
    else
      []
    end
  end
end
