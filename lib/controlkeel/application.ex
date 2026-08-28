defmodule ControlKeel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @supervisor_name ControlKeel.Supervisor
  @mcp_backend_ready_key :controlkeel_mcp_backend_ready

  def start_link do
    opts = [strategy: :one_for_one, name: @supervisor_name]

    if mcp_stdio_mode?() do
      mcp_stdio_detach_extra_loggers()
      :persistent_term.put(@mcp_backend_ready_key, :booting)

      children =
        base_children() ++ [mcp_stdio_server_child(), mcp_stdio_deferred_boot_task_child()]

      case Supervisor.start_link(children, opts) do
        {:ok, supervisor} ->
          {:ok, supervisor}

        other ->
          maybe_clear_mcp_backend_ready_term()
          other
      end
    else
      maybe_clear_mcp_backend_ready_term()

      case Supervisor.start_link(base_children(), opts) do
        {:ok, supervisor} ->
          result =
            with :ok <- maybe_run_migrations(),
                 :ok <- start_late_children(supervisor),
                 :ok <- maybe_seed_local_defaults() do
              :ok
            end

          case result do
            :ok ->
              {:ok, supervisor}

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
  end

  def config_change(changed, _new, removed) do
    ControlKeelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @doc false
  def mcp_backend_boot_status do
    :persistent_term.get(@mcp_backend_ready_key, :ready)
  end

  defp base_children do
    [
      ControlKeelWeb.Telemetry
    ]
  end

  defp late_children do
    local_repo_children() ++
      cloud_repo_children() ++
      analytics_children() ++
      cloud_emitter_children() ++
      mailer_test_inbox_children() ++
      retention_scheduler_children() ++
      db_maintenance_children() ++
      autonomy_scheduler_children() ++
      [ControlKeel.Cloud.RateLimiter, ControlKeel.Cloud.Usage.Meter] ++
      [ControlKeel.Mcp.StreamableSessions] ++
      [
        {DNSCluster, query: Application.get_env(:controlkeel, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ControlKeel.PubSub},
        ControlKeel.Skills.Activation,
        ControlKeel.Memory.Store.Sqlite,
        ControlKeel.Governance.CopilotChannel,
        ControlKeel.Cloud.SyncEngine,
        {DynamicSupervisor, strategy: :one_for_one, name: ControlKeel.MCP.Supervisor},
        ControlKeel.MCP.ToolGroupTracker,
        ControlKeelWeb.Endpoint
      ]
  end

  defp mcp_stdio_server_child do
    {ControlKeel.MCP.Server,
     [
       name: ControlKeel.MCP.Server.stdio_registered_name(),
       input: :stdio,
       output: :stdio
     ]}
  end

  defp mcp_stdio_rest_children do
    local_repo_children() ++
      cloud_repo_children() ++
      analytics_children() ++
      cloud_emitter_children() ++
      [
        {Phoenix.PubSub, name: ControlKeel.PubSub},
        ControlKeel.Skills.Activation,
        ControlKeel.Memory.Store.Sqlite,
        ControlKeel.Governance.CopilotChannel,
        ControlKeel.Cloud.SyncEngine,
        ControlKeel.MCP.ToolGroupTracker
      ]
  end

  defp mcp_stdio_deferred_boot_task_child do
    %{
      id: :controlkeel_mcp_deferred_boot,
      start: {Task, :start_link, [&mcp_stdio_deferred_boot!/0]},
      restart: :temporary
    }
  end

  defp mcp_stdio_deferred_boot! do
    sup = GenServer.whereis(@supervisor_name)

    result =
      Enum.reduce_while(mcp_stdio_rest_children(), :ok, fn child, :ok ->
        case Supervisor.start_child(sup, child) do
          {:ok, _pid} -> {:cont, :ok}
          {:ok, _pid, _info} -> {:cont, :ok}
          :ignore -> {:cont, :ok}
          {:error, {:already_started, _pid}} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    result =
      case result do
        :ok -> maybe_run_migrations()
        {:error, _} = err -> err
      end

    result =
      case result do
        :ok -> maybe_seed_local_defaults()
        {:error, _} = err -> err
      end

    case result do
      :ok ->
        :persistent_term.put(@mcp_backend_ready_key, :ready)

      {:error, reason} ->
        :persistent_term.put(@mcp_backend_ready_key, {:failed, reason})
        require Logger
        Logger.error("[MCP] deferred backend boot failed: #{inspect(reason)}")
    end
  end

  defp maybe_clear_mcp_backend_ready_term do
    _ = :persistent_term.erase(@mcp_backend_ready_key)
    :ok
  end

  defp mcp_stdio_mode? do
    System.get_env("CK_MCP_MODE") in ~w(1 true TRUE yes YES)
  end

  # Phoenix dev helpers sometimes register extra :logger handlers that print to stdout.
  # MCP stdio requires stdout to be JSON-RPC only; keep :default (stderr via runtime.exs)
  # and :ssl_handler, drop the rest if present.
  defp mcp_stdio_detach_extra_loggers do
    allowed = MapSet.new([:default, :ssl_handler])

    for hid <- :logger.get_handler_ids(),
        not MapSet.member?(allowed, hid) do
      _ = :logger.remove_handler(hid)
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
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

  # Best-effort provisioning of the local-mode default org + workspace at boot.
  # Gated to release runtime (like migrations) so it runs when the binary /
  # release boots, not on every Application.start (test, iex, dev). In cloud /
  # self-hosted it is a no-op. Never blocks boot: on any failure it logs and
  # returns :ok, leaving session creation's defensive check as the safety net.
  defp maybe_seed_local_defaults do
    if skip_migrations?() or
         not (ControlKeel.Runtime.local?() and ControlKeel.Runtime.local_repo_configured?()) do
      :ok
    else
      case ControlKeel.Bootstrap.LocalDefaults.ensure() do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          require Logger
          Logger.warning("[bootstrap] default org/workspace seed failed: #{inspect(reason)}")
          :ok
      end
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
    # Migrate the active repo for the current runtime mode. In :local mode that
    # is `ControlKeel.Repo.Local` (SQLite). In :cloud / :self_hosted mode it is
    # `ControlKeel.CloudRepo` (Postgres). Routing through the dispatcher's
    # `active/0` guarantees the same repo serves queries and owns migrations,
    # so a cloud deploy can no longer auto-migrate SQLite while serving reads
    # from Postgres (the original issue #44 defect).
    repos =
      if ControlKeel.Runtime.cloud_repo_enabled?() do
        [ControlKeel.CloudRepo]
      else
        [ControlKeel.Repo.Local]
      end

    repos
    |> Enum.reduce_while(:ok, fn repo, :ok ->
      case Ecto.Migrator.with_repo(
             repo,
             &Ecto.Migrator.run(&1, :up, all: true, log: false),
             pool_size: 2,
             log: false
           ) do
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

  # Only start the SQLite repo when it is actually configured. A prod
  # cloud/self-hosted release intentionally leaves Repo.Local without a
  # :database/:url, so starting it unconditionally would crash boot. See
  # ControlKeel.Runtime.local_repo_configured?/0.
  defp local_repo_children do
    if ControlKeel.Runtime.local_repo_configured?(), do: [ControlKeel.Repo.Local], else: []
  end

  defp cloud_emitter_children do
    if Application.get_env(:controlkeel, :cloud_emitter_enabled, true) do
      [ControlKeel.Cloud.Telemetry.Emitter.Supervisor] ++ cloud_sender_periodic_children()
    else
      []
    end
  end

  defp cloud_sender_periodic_children do
    if Application.get_env(:controlkeel, :cloud_sender_periodic_enabled, true) do
      [ControlKeel.Cloud.Telemetry.Sender.Periodic]
    else
      []
    end
  end

  defp retention_scheduler_children do
    if ControlKeel.Memory.RetentionScheduler.enabled?() do
      [ControlKeel.Memory.RetentionScheduler]
    else
      []
    end
  end

  defp db_maintenance_children do
    if ControlKeel.Ops.Database.enabled?() do
      [ControlKeel.Ops.Database]
    else
      []
    end
  end

  defp autonomy_scheduler_children do
    if ControlKeel.Autonomy.Scheduler.enabled?() and not mcp_stdio_mode?() do
      [
        {Task.Supervisor, name: ControlKeel.Autonomy.TaskSupervisor},
        ControlKeel.Autonomy.Scheduler
      ]
    else
      []
    end
  end

  defp mailer_test_inbox_children do
    if Application.get_env(:controlkeel, :mailer_adapter) == :test do
      [ControlKeel.Mailer.TestInbox]
    else
      []
    end
  end
end
