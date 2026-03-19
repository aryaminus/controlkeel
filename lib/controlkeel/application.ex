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
      ControlKeelWeb.Telemetry,
      ControlKeel.Repo
    ] ++ analytics_children()
  end

  defp late_children do
    [
      {DNSCluster, query: Application.get_env(:controlkeel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ControlKeel.PubSub},
      ControlKeel.Skills.Activation,
      {DynamicSupervisor, strategy: :one_for_one, name: ControlKeel.MCP.Supervisor},
      ControlKeelWeb.Endpoint
    ]
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
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
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
end
