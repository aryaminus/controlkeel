defmodule ControlKeel.CLI.Dispatch.SkillsPluginsHooks do
  @moduledoc false

  alias ControlKeel.ProviderBroker
  alias ControlKeel.Skills
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :plugin_export, args: [plugin], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, target} <- plugin_target(plugin),
         {:ok, plan} <- Skills.export(target, root, scope: "export") do
      {:ok,
       [
         "Exported #{plugin} plugin bundle.",
         "Target: #{plan.target}",
         "Output: #{plan.output_dir}"
       ] ++ Enum.map(plan.instructions, &"  #{&1}")}
    else
      {:error, reason} ->
        {:error, "Failed to export plugin bundle: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :plugin_install, args: [plugin], options: options}, project_root) do
    root = options[:project_root] || project_root
    scope = options[:scope] || "project"
    mode = options[:mode] || "local"

    with {:ok, target} <- plugin_target(plugin) do
      case Skills.install(target, root, scope: scope) do
        {:ok, %{destination: destination} = result} ->
          {:ok,
           [
             "Installed #{plugin} plugin bundle.",
             "Target: #{target}",
             "Scope: #{scope}",
             "Destination: #{destination}",
             "MCP mode: #{mode} (use #{plugin_mcp_hint(mode)})"
           ] ++
             maybe_cli_line("Marketplace", Map.get(result, :marketplace_destination))}

        {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
          {:ok,
           [
             "Prepared #{plugin} plugin bundle.",
             "Target: #{plan.target}",
             "Scope: #{scope}",
             "Output: #{plan.output_dir}",
             "MCP mode: #{mode} (use #{plugin_mcp_hint(mode)})"
           ] ++ Enum.map(plan.instructions, &"  #{&1}")}

        {:error, reason} ->
          {:error, "Failed to install plugin bundle: #{format_cli_error(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, "Failed to install plugin bundle: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :skills_list, options: options}, project_root) do
    root = options[:project_root] || project_root
    analysis = Skills.analyze(root)
    selected_target = options[:target]

    skills =
      if selected_target do
        Enum.filter(analysis.skills, &(selected_target in (&1.compatibility_targets || [])))
      else
        analysis.skills
      end

    with {:ok, format} <- effective_cli_format(options) do
      case format do
        "json" ->
          {:ok,
           [
             Jason.encode!(
               skills_list_payload(root, selected_target, skills, analysis.diagnostics)
             )
           ]}

        _text ->
          {:ok, format_skills_list(skills, analysis.diagnostics)}
      end
    else
      {:error, reason} -> {:error, format_cli_error(reason)}
    end
  end

  def run_command(%{command: :skills_validate, options: options}, project_root) do
    root = options[:project_root] || project_root
    result = Skills.validate(root)

    {:ok,
     [
       "Skills valid: #{if(result.valid?, do: "yes", else: "no")}",
       "Total skills: #{result.total}",
       "Warnings: #{result.warning_count}",
       "Errors: #{result.error_count}"
     ] ++
       Enum.map(result.diagnostics, fn diagnostic ->
         "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
       end)}
  end

  def run_command(%{command: :skills_export, options: options}, project_root) do
    root = options[:project_root] || project_root
    target = options[:target] || "open-standard"

    case Skills.export(target, root, scope: options[:scope]) do
      {:ok, plan} ->
        {:ok,
         [
           "Exported #{plan.target} bundle.",
           "Output: #{plan.output_dir}"
         ] ++ Enum.map(plan.instructions, &"  #{&1}")}

      {:error, :unknown_target} ->
        {:error, "Unknown skill export target: #{target}"}

      {:error, reason} ->
        {:error, "Failed to export skills: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_install, options: options}, project_root) do
    root = options[:project_root] || project_root
    target = options[:target] || "open-standard"

    case Skills.install(target, root, scope: options[:scope]) do
      {:ok, %{destination: destination} = result} ->
        lines = [
          "Installed #{result.target} skills.",
          "Destination: #{destination}"
        ]

        lines =
          if Map.has_key?(result, :agent_destination) do
            lines ++ ["Agent destination: #{result.agent_destination}"]
          else
            lines
          end

        {:ok, lines}

      {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
        {:ok,
         [
           "Prepared #{plan.target} bundle.",
           "Output: #{plan.output_dir}"
         ] ++ Enum.map(plan.instructions, &"  #{&1}")}

      {:error, :unknown_target} ->
        {:error, "Unknown skill install target: #{target}"}

      {:error, reason} ->
        {:error, "Failed to install skills: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_doctor, options: options}, project_root) do
    root = options[:project_root] || project_root
    analysis = Skills.analyze(root, report_identical_duplicates: true)
    integrations = Skills.agent_integrations()
    provider_status = ProviderBroker.status(root)
    {:ok, format} = effective_cli_format(options)

    attach_clients =
      integrations
      |> Enum.filter(&(&1.support_class == "attach_client"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    runtimes =
      integrations
      |> Enum.filter(&(&1.support_class == "headless_runtime"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    frameworks =
      integrations
      |> Enum.filter(&(&1.support_class == "framework_adapter"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    manifests = Skills.export_manifests(root)

    manifest_lines =
      case manifests do
        [] ->
          ["Export manifests: none (no controlkeel/dist/*/.controlkeel-manifest.json found)."]

        list ->
          ["Export manifests: #{length(list)}"] ++
            Enum.map(Enum.take(list, 10), fn %{path: path, manifest: manifest} ->
              target = Map.get(manifest, "target") || "unknown"
              scope = Map.get(manifest, "scope") || "unknown"
              ver = Map.get(manifest, "controlkeel_version") || "unknown"
              at = Map.get(manifest, "installed_at") || "unknown"
              rel = Path.relative_to(path, Path.expand(root))
              "  - #{target} (scope=#{scope}, ck=#{ver}, at=#{at}) — #{rel}"
            end)
      end

    duplicate_copy_count =
      Enum.count(analysis.diagnostics, &(&1.code == "duplicate_skill_copy"))

    shadowed_copy_count =
      Enum.count(analysis.diagnostics, &(&1.code == "shadowed_skill"))

    # Identical copies across distinct host dirs are expected distribution:
    # each host loads only its native directory. Only content drift (shadowed
    # copies) is a real problem — a warning that fires on healthy state just
    # teaches operators to ignore it.
    token_hint =
      cond do
        shadowed_copy_count > 0 ->
          [
            "",
            "⚠️  SHADOWED SKILL COPIES:",
            "  Found #{shadowed_copy_count} skill name(s) with DIFFERING content across dirs.",
            "  Hosts may load a different version than CK's preferred one — review and align them.",
            "  Run 'controlkeel skills doctor --prune-duplicates' to collapse redundant copies."
          ]

        duplicate_copy_count > 0 ->
          [
            "",
            "ℹ️  #{duplicate_copy_count} identical skill copies across host dirs (expected distribution —",
            "  each host loads only its native directory; CK counts each skill once).",
            "  Run 'controlkeel skills doctor --prune-duplicates' only to collapse user-level duplicates."
          ]

        true ->
          []
      end

    prune_result =
      if options[:prune_duplicates] == true and duplicate_copy_count > 0 do
        prune_duplicate_skills(root)
      else
        []
      end

    case format do
      "json" ->
        payload = %{
          "project_root" => Path.expand(root),
          "trusted_project_skills" => analysis.trusted_project?,
          "catalog_size" => length(analysis.skills),
          "duplicate_identical_skill_copies" => duplicate_copy_count,
          "shadowed_skill_copies" => shadowed_copy_count,
          "identical_copies_expected" => shadowed_copy_count == 0,
          "provider" => provider_status,
          "attachable_clients" => attach_clients,
          "headless_runtimes" => runtimes,
          "framework_adapters" => frameworks,
          "export_manifests" => manifests,
          "diagnostics" => Enum.map(analysis.diagnostics, &skill_diagnostic_payload/1)
        }

        {:ok, [Jason.encode!(payload)]}

      _ ->
        {:ok,
         [
           "Project root: #{Path.expand(root)}",
           "Trusted project skills: #{if(analysis.trusted_project?, do: "yes", else: "no")}",
           "Catalog size: #{length(analysis.skills)}",
           "Duplicate identical skill copies: #{duplicate_copy_count}",
           "Hint: token audit deduplicates effective CK skills, but host-native skill directories can still add context overhead"
         ] ++
           token_hint ++
           prune_result ++
           [
             "Provider source: #{provider_status["selected_source"]}",
             "Provider: #{provider_status["selected_provider"]}",
             "Auth mode: #{provider_status["selected_auth_mode"]}",
             "Auth owner: #{provider_status["selected_auth_owner"]}",
             "Bootstrap mode: #{provider_status["bootstrap"]["mode"]}",
             "Attachable clients: #{attach_clients}",
             "Headless runtimes: #{if(runtimes == "", do: "none", else: runtimes)}",
             "Framework adapters: #{if(frameworks == "", do: "none", else: frameworks)}"
           ] ++
           manifest_lines ++
           Enum.map(analysis.diagnostics, fn diagnostic ->
             "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
           end)}
    end
  end

  def run_command(%{command: :token_audit, options: options}, project_root) do
    root = options[:project_root] || project_root
    mode = options[:mode] || "full"
    {:ok, format} = effective_cli_format(options)

    case mode do
      mode when mode in ["full", "rules", "skills", "tools"] ->
        audit_result =
          ControlKeel.MCP.Tools.CkTokenAudit.call(%{
            "project_root" => root,
            "mode" => mode
          })

        case audit_result do
          {:ok, result} ->
            output_lines = format_token_audit(result, mode, format)
            {:ok, output_lines}

          {:error, error} ->
            {:error, ["Token audit failed: #{inspect(error)}"]}
        end

      _ ->
        {:error, ["Invalid mode: #{mode}. Use: full, rules, skills, or tools"]}
    end
  end

  def run_command(%{command: :tool_groups_suggest, options: options}, project_root) do
    root = options[:project_root] || project_root
    {:ok, format} = effective_cli_format(options)
    apply_preference = options[:apply] || false

    case ControlKeel.MCP.ToolGroupTracker.suggest_groups(root) do
      %{suggested: groups, reason: reason, usage_stats: stats} ->
        output_lines = format_tool_groups_suggest(groups, reason, stats, format)

        if apply_preference do
          case ControlKeel.Project.Binding.put_tool_groups(root, groups) do
            {:ok, _binding} ->
              {:ok, output_lines ++ ["", "✓ Tool groups preference saved to project binding"]}

            {:error, error} ->
              {:error, output_lines ++ ["", "✗ Failed to save preference: #{inspect(error)}"]}
          end
        else
          {:ok, output_lines}
        end

      _ ->
        {:error, ["Failed to suggest tool groups"]}
    end
  end

  # Finds duplicate skill copies and removes user-level copies (always redundant).
  # Project-level host-specific copies are listed but not removed — the user's
  # primary host directory is kept, compat .agents/skills/ is kept.
  defp prune_duplicate_skills(project_root) do
    {:ok, %{removed: removed, kept_project_groups: groups}} =
      Skills.prune_duplicate_skills(project_root)

    user_lines =
      if removed != [] do
        ["", "✓ Pruned #{length(removed)} user-level duplicate skill copy(s):"] ++
          Enum.map(removed, &"  rm -rf #{&1}")
      else
        []
      end

    project_lines =
      if groups != [] do
        ["", "ℹ️  Project-level host-specific copies (kept — your primary host needs these):"] ++
          Enum.flat_map(groups, &["  #{&1.host_dir}/skills/: #{Enum.join(&1.skills, ", ")}"]) ++
          ["  # To remove extras: keep only your primary host dir + .agents/skills/"]
      else
        []
      end

    if user_lines == [] and project_lines == [] do
      ["No duplicate skill copies found."]
    else
      user_lines ++ project_lines
    end
  end
end
