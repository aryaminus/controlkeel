defmodule ControlKeel.CLI.Dispatch.McpTools do
  @moduledoc false

  require Logger
  alias ControlKeel.Agent.ACPRegistry
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :mcp_guardrails_list, options: _options}, _project_root) do
    alias ControlKeel.Cloud.Guardrails

    summary = Guardrails.summary()

    header = [
      "Cloud MCP content guardrails",
      "Enabled: #{summary.enabled}",
      "Active patterns: #{summary.pattern_count}",
      ""
    ]

    pattern_rows =
      if summary.patterns == [] do
        ["No patterns active."]
      else
        ["Patterns:"] ++ Enum.map(summary.patterns, &"  #{&1}")
      end

    allow_rows =
      if summary.allow_for_tools == [] do
        []
      else
        ["", "Allow-for-tools (skipped from scanning):"] ++
          Enum.map(summary.allow_for_tools, &"  #{&1}")
      end

    {:ok, header ++ pattern_rows ++ allow_rows}
  end

  def run_command(%{command: :mcp_registry_list, options: _options}, _project_root) do
    alias ControlKeel.Cloud.Mcp.Registry

    summary = Registry.summary()
    entries = Registry.entries()
    denylist = Registry.denylist()

    header = [
      "Cloud MCP server registry",
      "Default policy: #{summary.default_policy}",
      "Allowlisted: #{summary.allowlist_count} (#{summary.requires_attestation} require attestation)",
      "Denylisted:  #{summary.denylist_count}",
      ""
    ]

    allow_rows =
      if entries == [] do
        ["Allowlist: (empty)"]
      else
        ["Allowlist:"] ++
          Enum.map(entries, fn e ->
            "  #{e.name}  attestation=#{e.attestation}#{format_url(e.url)}#{format_note(e.note)}"
          end)
      end

    deny_rows =
      if denylist == [] do
        ["Denylist: (empty)"]
      else
        ["Denylist:"] ++ Enum.map(denylist, &"  #{&1}")
      end

    {:ok, header ++ allow_rows ++ [""] ++ deny_rows}
  end

  def run_command(
        %{command: :mcp_registry_check, options: options, args: [server_name]},
        _project_root
      ) do
    alias ControlKeel.Cloud.Mcp.Registry

    attested? = Map.get(options, :attested, false)
    disposition = Registry.lookup(server_name, attested?: attested?)

    line =
      case disposition do
        :allowed ->
          "ALLOWED: #{server_name}#{if attested?, do: " (attestation provided)", else: ""}"

        {:denied, reason} ->
          "DENIED:  #{server_name} (#{reason})"
      end

    {:ok, [line]}
  end

  def run_command(%{command: :registry_sync_acp}, _project_root) do
    case ACPRegistry.sync() do
      {:ok, status} ->
        {:ok,
         [
           "Refreshed ACP registry cache.",
           "Source: #{status["registry_url"]}",
           "Fetched at: #{status["fetched_at"]}",
           "Entries: #{status["entry_count"]}",
           "Matched integrations: #{status["matched_integrations"]}",
           "Cache: #{status["cache_path"]}"
         ]}

      {:error, reason} ->
        {:error, "Failed to refresh ACP registry cache: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :registry_status_acp}, _project_root) do
    status = ACPRegistry.status()

    {:ok,
     [
       "ACP registry cache status:",
       "Source: #{status["registry_url"]}",
       "Fetched at: #{status["fetched_at"] || "never"}",
       "Entries: #{status["entry_count"]}",
       "Matched integrations: #{status["matched_integrations"]}",
       "Stale: #{if(status["stale"], do: "yes", else: "no")}",
       "Cache: #{status["cache_path"]}"
     ]}
  end

  def run_command(%{command: :mcp, options: options}, project_root) do
    root = Path.expand(options[:project_root] || project_root)

    # MCP.Server is supervised first when CK_MCP_MODE (see Application). Keep
    # binding/skills bootstrap async, but wait for the deferred backend to start
    # the Repo before it touches persistent project state.
    File.cd!(root, fn ->
      case ensure_stdio_server_running(2_000) do
        pid when is_pid(pid) ->
          ref = Process.monitor(pid)

          _ =
            Task.start(fn ->
              case await_mcp_backend_ready() do
                :ready ->
                  case ensure_local_project(root, %{}, sync_attached_agents: false) do
                    {:ok, _, _, _} ->
                      :ok

                    {:error, reason} ->
                      Logger.error(
                        "[MCP] bootstrap failed (some tools may fail until fixed): #{inspect(reason)}"
                      )
                  end

                reason ->
                  Logger.error("[MCP] bootstrap skipped: backend #{inspect(reason)}")
              end
            end)

          receive do
            {:DOWN, ^ref, :process, ^pid, :normal} ->
              :ok

            {:DOWN, ^ref, :process, ^pid, :shutdown} ->
              :ok

            {:DOWN, ^ref, :process, ^pid, reason} ->
              {:error, "MCP server stopped: #{inspect(reason)}"}
          end

        nil ->
          {:error,
           "ControlKeel MCP stdio server is not running. Ensure CK_MCP_MODE is set before the application starts (see mix ck.mcp and bin/controlkeel-mcp)."}
      end
    end)
  end

  defp await_mcp_backend_ready do
    deadline = System.monotonic_time(:millisecond) + 2_000
    wait_for_mcp_backend(deadline)
  end

  defp wait_for_mcp_backend(deadline) do
    case ControlKeel.Application.mcp_backend_boot_status() do
      :ready ->
        :ready

      :booting ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(25)
          wait_for_mcp_backend(deadline)
        else
          :booting
        end

      {:failed, _reason} = status ->
        status

      _ ->
        :ready
    end
  end
end
