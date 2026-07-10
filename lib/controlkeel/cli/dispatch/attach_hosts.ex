defmodule ControlKeel.CLI.Dispatch.AttachHosts do
  @moduledoc false

  alias ControlKeel.Agent.Execution
  alias ControlKeel.Agent.Integration
  alias ControlKeel.CLI.Claude
  alias ControlKeel.CLI.CodexConfig
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Project.Binding
  alias ControlKeel.CLI.SetupAdvisor
  alias ControlKeel.Skills
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :attach, args: ["claude-code"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "claude-code"}),
         {:ok, _scope} <- validate_attach_scope("claude-code", options),
         command_spec <- Binding.mcp_command_spec(root),
         {:ok, attached_agent} <-
           Claude.attach_local(
             root,
             command_spec.command,
             command_spec.args
           ),
         updated_binding <-
           Binding.update_attached_agent(binding, "claude_code", attached_agent),
         {:ok, _binding} <-
           Binding.write_effective(
             updated_binding,
             root,
             mode: binding_write_mode(binding)
           ) do
      emit_attach_succeeded(binding, root, attached_agent)

      {:ok,
       [
         "Attached ControlKeel to Claude Code.",
         "Verified with `claude mcp get controlkeel`."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("claude-code", root, options) ++
         attach_guidance_lines("claude-code")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["cursor"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "cursor"}),
         {:ok, _scope} <- validate_attach_scope("cursor", options),
         command_spec <- Binding.mcp_command_spec(root, portable: true),
         {:ok, attached} <- attach_to_cursor(command_spec),
         updated <- Binding.update_attached_agent(binding, "cursor", attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Cursor.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Cursor to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("cursor", root, options) ++ attach_guidance_lines("cursor")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Cursor: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["windsurf"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "windsurf"}),
         {:ok, _scope} <- validate_attach_scope("windsurf", options),
         command_spec <- Binding.mcp_command_spec(root, portable: true),
         {:ok, attached} <- attach_to_windsurf(command_spec),
         updated <- Binding.update_attached_agent(binding, "windsurf", attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Windsurf.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Windsurf to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("windsurf", root, options) ++
         attach_guidance_lines("windsurf")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Windsurf: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["codex-cli", "codex-app-server", "t3code"] do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         command_spec <- Binding.mcp_command_spec(root, portable: scope == "user"),
         config_path <- CodexConfig.path_for_scope(root, scope),
         {:ok, _} <- CodexConfig.write(config_path, command_spec),
         {:ok, install_result} <- maybe_install_codex_native(root, scope, options),
         attached <-
           %{
             "server_name" => "controlkeel",
             "ide" => agent,
             "config_path" => config_path,
             "scope" => scope,
             "target" => "codex",
             "destination" => install_result && install_result[:destination],
             "compat_destination" => install_result && install_result[:compat_destination],
             "agents_destination" => install_result && install_result[:agent_destination],
             "commands_destination" => install_result && install_result[:commands_destination],
             "config_destination" => config_path,
             "controlkeel_version" => to_string(Application.spec(:controlkeel, :vsn) || "0.2.0"),
             "attached_at" =>
               DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
           },
         updated <- Binding.update_attached_agent(binding, agent, attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to #{display_attach_agent(agent)}.",
         "MCP server written to #{config_path}.",
         "Restart #{display_attach_agent(agent)} to activate."
       ] ++
         bootstrap_lines(root) ++
         codex_attach_install_lines(install_result) ++ attach_guidance_lines(agent)}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["kiro", "kilo", "amp", "augment", "opencode", "gemini-cli", "cline"] do
    config_path_fn = %{
      "kiro" => &kiro_mcp_config_path/0,
      "kilo" => &kilo_config_path/0,
      "amp" => &amp_mcp_config_path/0,
      "augment" => &augment_mcp_config_path/0,
      "opencode" => &opencode_mcp_config_path/0,
      "gemini-cli" => &gemini_cli_config_path/0,
      "cline" => &cline_mcp_config_path/0
    }

    display_name = %{
      "kiro" => "Kiro",
      "kilo" => "Kilo Code",
      "amp" => "Amp",
      "augment" => "Augment / Auggie CLI",
      "opencode" => "OpenCode",
      "gemini-cli" => "Gemini CLI",
      "cline" => "Cline"
    }

    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         command_spec <- Binding.mcp_command_spec(root, portable: true),
         config_path <- config_path_fn[agent].(),
         {:ok, attached} <- write_ide_mcp_config(config_path, "controlkeel", command_spec, agent),
         {:ok, native_attrs, native_lines} <- install_native_attach(agent, root, scope, options),
         attached <- Map.merge(attached, native_attrs),
         updated <- Binding.update_attached_agent(binding, agent, attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to #{display_name[agent]}.",
         "MCP server written to #{attached["config_path"]}.",
         if(agent == "augment",
           do:
             "Restart Auggie or use `auggie --mcp-config #{attached["config_path"]}` to activate.",
           else: "Restart #{display_name[agent]} to activate."
         )
       ] ++
         bootstrap_lines(root) ++
         native_lines ++
         attach_guidance_lines(agent)}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to #{display_name[agent]}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["goose"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "goose"}),
         {:ok, _scope} <- validate_attach_scope("goose", options),
         command_spec <- Binding.mcp_command_spec(root, portable: true),
         {:ok, attached} <- attach_to_goose(command_spec, root),
         updated <- Binding.update_attached_agent(binding, "goose", attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Goose.",
         "Goose extension written to #{attached["config_path"]}.",
         "Restart Goose to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("goose", root, options) ++
         attach_guidance_lines("goose")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Goose: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["continue"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "continue"}),
         {:ok, _scope} <- validate_attach_scope("continue", options),
         command_spec <- Binding.mcp_command_spec(root, portable: true),
         {:ok, attached} <-
           write_continue_mcp_config(continue_config_path(), "controlkeel", command_spec),
         updated <- Binding.update_attached_agent(binding, "continue", attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Continue.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Continue to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("continue", root, options) ++
         attach_guidance_lines("continue")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Continue: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["aider"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "aider"}),
         {:ok, _scope} <- validate_attach_scope("aider", options),
         command_spec <- Binding.mcp_command_spec(root),
         {:ok, attached} <- attach_to_aider(command_spec, root),
         updated <- Binding.update_attached_agent(binding, "aider", attached),
         {:ok, _} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Aider.",
         "MCP config written to #{attached["config_path"]}."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("aider", root, options) ++
         attach_guidance_lines("aider")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Aider: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in [
             "roo-code",
             "hermes-agent",
             "openclaw",
             "droid",
             "forge",
             "pi",
             "letta-code",
             "devin-terminal",
             "warp",
             "multica",
             "antigravity-cli",
             "antigravity-ide"
           ] do
    root = options[:project_root] || project_root

    target =
      %{
        "roo-code" => "roo-native",
        "hermes-agent" => "hermes-native",
        "openclaw" => "openclaw-native",
        "droid" => "droid-bundle",
        "forge" => "forge-acp",
        "pi" => "pi-native",
        "letta-code" => "letta-code-native",
        "devin-terminal" => "devin-terminal-native",
        "warp" => "warp-native",
        "multica" => "multica-native",
        "antigravity-cli" => "antigravity-cli-native",
        "antigravity-ide" => "antigravity-cli-native"
      }[agent]

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         {:ok, result} <- attach_bundle_target(target, root, scope, options),
         attached_agent <- bundled_attached_agent(agent, target, scope, result),
         updated <- Binding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       bundle_attach_lines(agent, result) ++
         bootstrap_lines(root) ++
         attach_guidance_lines(agent)}
    else
      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["vscode", "copilot"] do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         {:ok, install_result} <- Skills.install("github-repo", root, scope: scope),
         attached_agent <- github_repo_attached_agent(agent, scope, install_result),
         updated <- Binding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <-
           Binding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      lines =
        case install_result do
          %{destination: destination} ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Installed project bundle at #{destination}.",
              "Repository MCP config written under .github and .vscode."
            ] ++ bootstrap_lines(root)

          %ControlKeel.Skills.SkillExportPlan{} = plan ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Output: #{plan.output_dir}"
            ] ++ bootstrap_lines(root)
        end

      {:ok, lines ++ attach_guidance_lines(agent)}
    else
      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :detach, args: [agent], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, format} <- effective_cli_format(options),
         {:ok, binding, _session, _mode} <- load_binding_for_detach(root),
         {:ok, agent_key, attrs} <- resolve_attached(agent, binding) do
      mcp_removed = remove_mcp_registration(agent_key, attrs, root)
      removed_paths = cleanup_agent_artifacts(attrs, root, options[:force])

      updated_binding = remove_agent_from_binding(binding, agent_key)
      remaining = map_size(updated_binding["attached_agents"] || %{})

      binding_removed =
        if remaining == 0 and not options[:keep_binding] do
          cleanup_binding_dir(root)
        else
          false
        end

      {:ok, _binding} =
        if remaining > 0 do
          Binding.write_effective(
            updated_binding,
            root,
            mode: binding_write_mode(updated_binding)
          )
        else
          {:ok, updated_binding}
        end

      payload = %{
        "agent" => agent_key,
        "scope" => attrs["scope"] || "project",
        "remaining_attached_agents" => remaining,
        "removed_paths" => removed_paths,
        "mcp_registration_removed" => mcp_removed,
        "binding_removed" => binding_removed
      }

      detach_response(format, payload)
    else
      {:error, :no_binding} ->
        {:error, "No ControlKeel binding found. Run `controlkeel init` first."}

      {:error, {:not_attached, key}} ->
        {:error, "Agent #{key} is not attached to this project."}

      {:error, reason} ->
        {:error, "Failed to detach: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :agents_discover, options: options, args: [path]}, _project_root) do
    alias ControlKeel.Cloud.AgentInventory

    scan_opts =
      case options[:max_depth] do
        n when is_integer(n) -> [max_depth: n]
        _ -> []
      end

    case AgentInventory.scan(path, scan_opts) do
      {:error, :not_found} ->
        {:error, "Path not found: #{path}"}

      {:error, :not_a_directory} ->
        {:error, "Not a directory: #{path}"}

      {:ok, hits} ->
        if Map.get(options, :json, false) do
          summary = AgentInventory.summarize(hits)
          {:ok, [Jason.encode!(%{hits: hits, summary: summary}, pretty: true)]}
        else
          summary = AgentInventory.summarize(hits)

          header = [
            "Agent inventory scan",
            "Root: #{Path.expand(path)}",
            "Total hits: #{summary.total}",
            ""
          ]

          rows =
            if summary.by_host == [] do
              ["No agent host evidence found."]
            else
              ["By host:"] ++
                Enum.map(summary.by_host, fn h ->
                  "  #{h.host}\t(#{h.count}) — #{Enum.join(h.evidence, ", ")}"
                end) ++
                ["", "Hits:"] ++
                Enum.map(hits, fn hit ->
                  "  #{hit.host}\t#{hit.path}\t#{hit.kind}\t#{hit.evidence}"
                end)
            end

          {:ok, header ++ rows}
        end
    end
  end

  def run_command(%{command: :agents_doctor, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = resolve_project_root(options, project_root)
      doctor = Execution.doctor(root)
      snapshot = SetupAdvisor.snapshot(root)

      case format do
        "json" ->
          {:ok,
           [Jason.encode!(Map.put(doctor, "detected_hosts", snapshot["detected_hosts"] || []))]}

        _ ->
          agent_lines =
            Enum.map(doctor["agents"], fn agent ->
              "  #{agent.id}: #{agent.execution_support} / #{agent.ck_runs_agent_via} attached=#{if(agent.attached, do: "yes", else: "no")} runnable=#{if(agent.runnable, do: "yes", else: "no")}"
            end)

          {:ok,
           [
             "Agent execution doctor",
             "Project root: #{doctor["project_root"]}",
             SetupAdvisor.detected_hosts_line(snapshot),
             "Attached agents: #{if(doctor["attached_agents"] == [], do: "none", else: Enum.join(doctor["attached_agents"], ", "))}",
             "Direct ready: #{length(doctor["direct_ready"])}",
             "Handoff ready: #{length(doctor["handoff_ready"])}",
             "Runtime ready: #{length(doctor["runtime_ready"])}",
             "Core loop: #{SetupAdvisor.core_loop()}",
             "Agents:"
             | agent_lines
           ]}
      end
    end
  end

  def run_command(%{command: :attach_doctor, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = resolve_project_root(options, project_root)
      doctor = Execution.doctor(root)
      snapshot = SetupAdvisor.snapshot(root)
      provider_status = ProviderBroker.status(root)

      attached = Enum.filter(doctor["agents"], & &1.attached)
      runnable_attached = Enum.count(attached, & &1.runnable)

      case format do
        "json" ->
          payload = %{
            "project_root" => doctor["project_root"],
            "detected_hosts" => snapshot["detected_hosts"] || [],
            "provider" => provider_status,
            "attached_agents" => Enum.map(attached, & &1.id),
            "runnable_attached_agents" => runnable_attached,
            "agents" => doctor["agents"],
            "core_loop" => SetupAdvisor.core_loop()
          }

          {:ok, [Jason.encode!(payload)]}

        _ ->
          attached_lines =
            if attached == [] do
              ["Attached agents: none (run `controlkeel attach <agent>`)."]
            else
              [
                "Attached agents: #{Enum.join(Enum.map(attached, & &1.id), ", ")}",
                "Runnable attached agents: #{runnable_attached}/#{length(attached)}",
                "Attached details:"
              ] ++
                Enum.map(attached, fn agent ->
                  "  #{agent.id}: runnable=#{if(agent.runnable, do: "yes", else: "no")} support=#{agent.execution_support}/#{agent.ck_runs_agent_via}"
                end)
            end

          {:ok,
           [
             "Attach health check",
             "Project root: #{doctor["project_root"]}",
             SetupAdvisor.detected_hosts_line(snapshot),
             "Provider source: #{provider_status["selected_source"]}",
             "Provider: #{provider_status["selected_provider"]}",
             "Core loop: #{SetupAdvisor.core_loop()}",
             "Verification commands:",
             "  - controlkeel status",
             "  - controlkeel agents doctor",
             "  - controlkeel provider doctor"
           ] ++ attached_lines}
      end
    end
  end

  def run_command(%{command: :agents_list, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = resolve_project_root(options, project_root)
      agents = Execution.list_agents(root)

      case format do
        "json" ->
          {:ok, [Jason.encode!(%{"agents" => agents})]}

        _ ->
          lines =
            ["Agents:"] ++
              Enum.map(agents, fn agent ->
                "  #{agent.id}: attached=#{if(agent.attached, do: "yes", else: "no")} runnable=#{if(agent.runnable, do: "yes", else: "no")} support=#{agent.execution_support}"
              end)

          {:ok, lines}
      end
    end
  end

  defp install_native_attach(agent, project_root, scope, options) do
    if native_attach_skipped?(options) do
      {:ok, %{}, []}
    else
      target = native_attach_target(agent)

      case Skills.install(target, project_root, scope: scope) do
        {:ok, %{destination: destination} = result} ->
          attrs =
            result
            |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
            |> Map.put("target", target)
            |> Map.put("scope", scope)

          {:ok, attrs,
           [
             "Prepared native companion files for #{display_attach_agent(agent)}.",
             "Destination: #{destination}"
           ]}

        {:ok, plan} ->
          if target == "instructions-only" do
            {:ok, %{"target" => target, "scope" => scope},
             [
               "Prepared native instruction snippets for #{display_attach_agent(agent)}.",
               "Instructions bundle: #{plan.output_dir}"
             ]}
          else
            {:error, {:unexpected_export_plan, target, plan.output_dir}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp native_attach_target(agent) do
    %{
      "kiro" => "kiro-native",
      "kilo" => "kilo-native",
      "amp" => "amp-native",
      "augment" => "augment-native",
      "opencode" => "opencode-native",
      "gemini-cli" => "gemini-cli-native",
      "cline" => "cline-native"
    }[agent]
  end

  defp load_binding_for_detach(root) do
    case ControlKeel.Project.Local.load(root) do
      {:ok, binding, session} -> {:ok, binding, session, "project"}
      {:error, _reason} -> {:error, :no_binding}
    end
  end

  # Resolve the *actual* key an agent was stored under in attached_agents.
  # attach is inconsistent (claude-code -> "claude_code", most others use their
  # raw dashed name), and Integration.canonical/1 returns a struct, so we
  # match against a candidate set of dash/underscore variants.
  defp resolve_attached(agent, binding) do
    agents = Map.get(binding, "attached_agents", %{})

    case Enum.find(attached_key_candidates(agent), &Map.has_key?(agents, &1)) do
      nil -> {:error, {:not_attached, agent}}
      key -> {:ok, key, Map.get(agents, key)}
    end
  end

  defp attached_key_candidates(agent) do
    canonical_id =
      case Integration.canonical(agent) do
        %{id: id} when is_binary(id) -> id
        _ -> agent
      end

    [agent, canonical_id]
    |> Enum.flat_map(&[&1, String.replace(&1, "-", "_"), String.replace(&1, "_", "-")])
    |> Enum.uniq()
  end

  # Reverse the MCP server registration attach wrote, dispatched by how each
  # host stores it. Best-effort and idempotent: a missing file/CLI is a no-op.
  defp remove_mcp_registration(agent_key, attrs, root) do
    server = attrs["server_name"] || "controlkeel"
    config_path = attrs["config_destination"] || attrs["config_path"]

    cond do
      claude_agent?(agent_key) ->
        ControlKeel.CLI.Claude.detach_local(root, server)
        true

      codex_agent?(agent_key) and is_binary(config_path) ->
        ControlKeel.CLI.CodexConfig.remove(config_path)
        true

      is_binary(config_path) and String.ends_with?(config_path, ".toml") ->
        ControlKeel.CLI.CodexConfig.remove(config_path)
        true

      is_binary(config_path) and String.ends_with?(config_path, ".json") ->
        remove_json_mcp_entry(config_path, server)
        true

      true ->
        false
    end
  rescue
    _ -> false
  end

  defp claude_agent?(key), do: key in ["claude_code", "claude-code"]

  defp codex_agent?(key),
    do: key in ["codex-cli", "codex_cli", "codex-app-server", "codex_app_server", "t3code"]

  # Remove the controlkeel entry from a JSON MCP config, handling both the dict
  # forms (mcpServers / mcp) and the array form (continue). Other servers and
  # user keys are preserved; the file is only rewritten if it actually changed.
  defp remove_json_mcp_entry(config_path, server) do
    with {:ok, body} <- File.read(config_path),
         {:ok, map} when is_map(map) <- Jason.decode(body) do
      updated =
        map
        |> drop_mcp_server("mcpServers", server)
        |> drop_mcp_server("mcp", server)

      if updated == map do
        :ok
      else
        File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n")
      end
    else
      _ -> :ok
    end
  end

  defp drop_mcp_server(map, key, server) do
    case Map.get(map, key) do
      servers when is_map(servers) ->
        Map.put(map, key, Map.delete(servers, server))

      servers when is_list(servers) ->
        Map.put(map, key, Enum.reject(servers, &(Map.get(&1, "name") == server)))

      _ ->
        map
    end
  end

  defp remove_agent_from_binding(binding, agent_key) do
    updated_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Map.delete(agent_key)

    Map.put(binding, "attached_agents", updated_agents)
  end

  # Remove project-scope files created by attach for a specific agent.
  #
  # Root cause fixed here: skills had a CK manifest, but generated agents,
  # commands, plugins, and MCP files did not. Detach now treats skill dirs as
  # manifest-owned and treats non-skill artifacts as CK-owned only when their
  # filenames are ControlKeel-specific. User-authored files in shared host dirs
  # are preserved unless --force is supplied. Legacy bindings that lack newer
  # destination metadata are handled by inferring paths from target/destination.
  defp cleanup_agent_artifacts(attrs, root, force) do
    if (attrs["scope"] || "project") == "project" do
      root_expanded = Path.expand(root)

      attrs
      |> artifact_cleanup_targets(root_expanded)
      |> Enum.flat_map(&cleanup_artifact_target(&1, root_expanded, force))
      |> Enum.uniq()
    else
      []
    end
  rescue
    _ -> []
  end

  defp artifact_cleanup_targets(attrs, root) do
    explicit = [
      {:skill_dir, attrs["skills_destination"]},
      {:skill_dir, attrs["compat_skills_destination"]},
      {:skill_dir, attrs["compat_destination"]},
      {:ck_dir, attrs["agents_destination"]},
      {:ck_dir, attrs["commands_destination"]},
      {:ck_dir, attrs["plugins_destination"]},
      {:ck_dir, attrs["rules_destination"]},
      {:mcp_file, attrs["mcp_destination"]}
    ]

    inferred = inferred_artifact_targets(attrs, root)

    (explicit ++ inferred)
    |> Enum.reject(fn {_kind, path} -> is_nil(path) or path == "" end)
    |> Enum.uniq()
  end

  defp inferred_artifact_targets(%{"target" => "opencode-native"} = attrs, _root) do
    case attrs["destination"] do
      dest when is_binary(dest) ->
        [
          {:ck_dir, Path.join(dest, "agents")},
          {:ck_dir, Path.join(dest, "commands")},
          {:ck_dir, Path.join(dest, "plugins")},
          {:mcp_file, Path.join(dest, "mcp.json")}
        ]

      _ ->
        []
    end
  end

  defp inferred_artifact_targets(_attrs, _root), do: []

  defp cleanup_artifact_target({_kind, nil}, _root, _force), do: []

  defp cleanup_artifact_target({kind, path}, root, force) do
    expanded = Path.expand(path)

    if path_within_root?(root, expanded) and File.exists?(expanded) do
      do_cleanup_artifact(kind, expanded, force)
    else
      []
    end
  rescue
    _ -> []
  end

  defp do_cleanup_artifact(:skill_dir, path, force) do
    cond do
      force -> remove_path(path)
      File.exists?(Path.join(path, ".controlkeel-skills.json")) -> remove_path(path)
      true -> []
    end
  end

  defp do_cleanup_artifact(:ck_dir, path, force) do
    if force do
      remove_path(path)
    else
      path
      |> ck_owned_children()
      |> Enum.flat_map(&remove_path/1)
      |> tap(fn _ -> remove_dir_if_empty(path) end)
    end
  end

  defp do_cleanup_artifact(:mcp_file, path, force) do
    cond do
      force ->
        remove_path(path)

      String.ends_with?(path, ".json") ->
        cleanup_json_mcp_file(path, "controlkeel")

      Path.basename(path) =~ ~r/^controlkeel/ ->
        remove_path(path)

      true ->
        []
    end
  end

  defp do_cleanup_artifact(:file, path, _force), do: remove_path(path)

  defp cleanup_json_mcp_file(path, server) do
    with {:ok, body} <- File.read(path),
         {:ok, map} when is_map(map) <- Jason.decode(body) do
      updated =
        map
        |> drop_mcp_server("mcpServers", server)
        |> drop_mcp_server("mcp", server)
        |> prune_empty_mcp_keys()

      cond do
        updated == map ->
          []

        updated == %{} ->
          remove_path(path)

        true ->
          File.write!(path, Jason.encode!(updated, pretty: true) <> "
")
          [path]
      end
    else
      _ -> []
    end
  end

  defp prune_empty_mcp_keys(map) do
    map
    |> drop_empty_map_key("mcpServers")
    |> drop_empty_map_key("mcp")
  end

  defp drop_empty_map_key(map, key) do
    case Map.get(map, key) do
      value when value == %{} or value == [] -> Map.delete(map, key)
      _ -> map
    end
  end

  defp ck_owned_children(dir) do
    patterns = [
      "controlkeel*",
      "controlkeel-*",
      "controlkeel_*"
    ]

    patterns
    |> Enum.flat_map(&Path.wildcard(Path.join(dir, &1)))
    |> Enum.filter(&File.exists?/1)
  end

  defp remove_path(path) do
    if File.exists?(path) do
      File.rm_rf!(path)
      [path]
    else
      []
    end
  end

  defp remove_dir_if_empty(path) do
    case File.ls(path) do
      {:ok, []} -> File.rmdir(path)
      _ -> :ok
    end
  end

  defp path_within_root?(root, path), do: path == root or String.starts_with?(path, root <> "/")

  defp cleanup_binding_dir(root) do
    binding_dir = Path.join(Path.expand(root), "controlkeel")

    if File.dir?(binding_dir) do
      File.rm_rf!(binding_dir)
      true
    else
      false
    end
  rescue
    _ -> false
  end

  defp detach_response("json", payload), do: {:ok, [Jason.encode!(payload, pretty: true)]}

  defp detach_response(_format, payload) do
    lines = [
      "Detached #{payload["agent"]} (scope: #{payload["scope"]}).",
      if(payload["remaining_attached_agents"] > 0,
        do: "Remaining attached agents: #{payload["remaining_attached_agents"]}",
        else: "No agents remaining. Binding directory cleaned up."
      )
    ]

    {:ok, Enum.filter(lines, &is_binary/1)}
  end
end
