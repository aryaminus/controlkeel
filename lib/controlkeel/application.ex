defmodule ControlKeel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  def start_link do
    children =
      [
        ControlKeelWeb.Telemetry,
        ControlKeel.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:controlkeel, :ecto_repos), skip: skip_migrations?()}
      ] ++
        analytics_children() ++
        [
          {DNSCluster, query: Application.get_env(:controlkeel, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: ControlKeel.PubSub},
          ControlKeel.Skills.Activation,
          {DynamicSupervisor, strategy: :one_for_one, name: ControlKeel.MCP.Supervisor},
          # Start a worker by calling: ControlKeel.Worker.start_link(arg)
          # {ControlKeel.Worker, arg},
          # Start to serve requests, typically the last entry
          ControlKeelWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ControlKeel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    ControlKeelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp analytics_children do
    if Application.get_env(:controlkeel, :analytics_telemetry_handler, true) do
      [ControlKeel.Analytics.TelemetryHandler]
    else
      []
    end
  end
end
