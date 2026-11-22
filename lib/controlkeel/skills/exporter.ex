defmodule ControlKeel.Skills.Exporter do
  @moduledoc false

  alias ControlKeel.Ops.Distribution
  alias ControlKeel.Skills
  alias ControlKeel.Skills.Installer
  alias ControlKeel.Skills.SkillExportPlan
  alias ControlKeel.Skills.SkillTarget
  alias ControlKeel.Utils.Yaml, as: UtilsYaml

  import ControlKeel.Skills.Exporter.Shared

  def export(target_id, project_root, opts \\ []) do
    with %SkillTarget{} = target <- SkillTarget.get(target_id),
         analysis <- Skills.validate(project_root, trust_project_skills: true),
         root <- export_root(project_root, target.id),
         :ok <- reset_export_root(root),
         skills = Installer.canonical_skills(analysis.skills, project_root),
         {:ok, writes, instructions} <-
           write_target(target, root, project_root, skills, opts) do
      :telemetry.execute(
        [:controlkeel, :skills, :exported],
        %{count: 1},
        %{
          target: target.id,
          scope: Keyword.get(opts, :scope, target.default_scope),
          project_root: Path.expand(project_root),
          skill_count: length(analysis.skills)
        }
      )

      manifest_path =
        write_export_manifest(
          root,
          target.id,
          Keyword.get(opts, :scope, target.default_scope),
          writes,
          instructions
        )

      {:ok,
       %SkillExportPlan{
         target: target.id,
         output_dir: root,
         scope: Keyword.get(opts, :scope, target.default_scope),
         writes: writes,
         instructions: instructions,
         native_available: target.native,
         manifest_path: manifest_path
       }}
    else
      nil -> {:error, :unknown_target}
      {:error, reason} -> {:error, reason}
    end
  end

  def write_export_manifest(root, target_id, scope, writes, instructions \\ []) do
    manifest_path = Path.join(root, ".controlkeel-manifest.json")

    payload = %{
      "schema_version" => 1,
      "controlkeel_version" => to_string(Application.spec(:controlkeel, :vsn) || "unknown"),
      "target" => target_id,
      "scope" => scope,
      "installed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "output_dir" => root,
      "writes" =>
        Enum.map(writes || [], fn write ->
          %{
            "path" => Map.get(write, "path"),
            "kind" => Map.get(write, "kind")
          }
        end),
      "instructions" => List.wrap(instructions)
    }

    File.write!(manifest_path, Jason.encode!(payload, pretty: true) <> "\n")
    manifest_path
  end

  defp write_target(%SkillTarget{id: "open-standard"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.OpenStandard.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "codex"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.Codex.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "codex-plugin"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.CodexPlugin.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "claude-standalone"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.ClaudeStandalone.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "claude-plugin"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.ClaudeCode.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "cline-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.ClineNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "cursor-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.Cursor.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "windsurf-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.Windsurf.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "continue-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.ContinueNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "letta-code-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.LettaCodeNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "pi-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.PiNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "roo-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.RooNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "goose-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.GooseNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "copilot-plugin"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.CopilotPlugin.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "github-repo"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.GithubRepo.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "droid-bundle"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.DroidBundle.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "opencode-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.OpenCode.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "kiro-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.KiroNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "kilo-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.KiloNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "amp-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.AmpNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "augment-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.AugmentNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "devin-runtime"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.DevinRuntime.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "warp-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.WarpNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "devin-terminal-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.DevinTerminalNative.write(root, project_root, skills, opts)
  end

  defp write_target(%SkillTarget{id: "antigravity-cli-native"}, root, project_root, skills, opts) do
    ControlKeel.Skills.Exporter.AntigravityCliNative.write(root, project_root, skills, opts)
  end

  @doc false
  def write_skill_tree(skills, destination_root) do
    File.mkdir_p!(destination_root)

    Enum.each(skills, fn skill ->
      destination = Path.join(destination_root, skill.name)

      unless same_path?(skill.skill_dir, destination) do
        replace_directory!(skill.skill_dir, destination)
      end
    end)
  end

  def export_root(project_root, target) do
    Path.join(Path.expand(project_root), "controlkeel/dist/#{target}")
  end

  def reset_export_root(root) do
    case File.rm_rf(root) do
      {:ok, _removed} ->
        ensure_directory(root)

      {:error, :eexist, _path} ->
        # Older standalone builds occasionally race with pre-existing dist targets.
        # Treat an already-present directory as recoverable and reuse it after mkdir_p.
        ensure_directory(root)

      {:error, reason, path} ->
        {:error, {reason, path}}
    end
  end

  def ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, :eexist, existing} ->
        if existing == path and File.dir?(path) do
          :ok
        else
          {:error, {:eexist, existing}}
        end

      {:error, reason, existing} ->
        {:error, {reason, existing}}
    end
  end

  def replace_directory!(source_root, destination_root) do
    File.rm_rf!(destination_root)
    File.mkdir_p!(destination_root)

    source_root
    |> File.ls!()
    |> Enum.each(fn entry ->
      copy_path!(Path.join(source_root, entry), Path.join(destination_root, entry))
    end)
  end

  def copy_path!(source, destination) do
    cond do
      File.dir?(source) ->
        File.mkdir_p!(destination)

        source
        |> File.ls!()
        |> Enum.each(fn entry ->
          copy_path!(Path.join(source, entry), Path.join(destination, entry))
        end)

      true ->
        File.mkdir_p!(Path.dirname(destination))
        File.cp!(source, destination)
    end
  end

  @doc false
  def with_common_assets(root, project_root, opts, writes, instructions) do
    {writes, instructions} =
      if Enum.any?(writes, &(&1["kind"] == "mcp")) do
        hosted_path = Path.join(root, ".mcp.hosted.json")

        File.write!(
          hosted_path,
          Jason.encode!(hosted_mcp_payload(opts), pretty: true) <> "\n"
        )

        {
          writes ++ [%{"path" => hosted_path, "kind" => "mcp-hosted"}],
          instructions ++ ["Hosted MCP template: #{hosted_path}"]
        }
      else
        {writes, instructions}
      end

    install_guide = Path.join(root, "CONTROLKEEL_INSTALL.md")
    File.write!(install_guide, install_guide_contents(project_root, opts))

    {:ok, writes ++ [%{"path" => install_guide, "kind" => "install-guide"}],
     instructions ++ ["Bundle install guide: #{install_guide}"]}
  end

  @doc false
  def mcp_payload(project_root, opts) do
    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "command" => mcp_command(project_root, opts),
          "args" => mcp_args(project_root, opts)
        }
      }
    }
  end

  def devin_terminal_config_payload(project_root, opts) do
    mcp_payload(project_root, opts)
  end

  @doc false
  def opencode_mcp_payload(project_root, opts) do
    %{
      "mcp" => %{
        "controlkeel" => %{
          "type" => "local",
          "command" => [mcp_command(project_root, opts) | mcp_args(project_root, opts)]
        }
      }
    }
  end

  def devin_terminal_agent_contents do
    """
    ---
    name: controlkeel-operator
    description: Govern Devin for Terminal work with ControlKeel validation, findings, reviews, and budget checks.
    allowed-tools:
      - read
      - edit
      - grep
      - glob
      - exec
    ---

    You are a ControlKeel-governed Devin subagent.

    Always start by loading `ck_context`, then use `ck_validate` before risky code, config, or shell changes.
    Use `ck_review_submit` before implementation plans or completion gates, `ck_finding` for issues you discover, and `ck_budget` before expensive multi-step work.
    """
  end

  def devin_terminal_hooks_manifest do
    %{
      "hooks" => %{
        "PreToolUse" => [
          %{
            "matcher" => ".*",
            "hooks" => [
              %{
                "type" => "command",
                "command" =>
                  ~s|sh "${DEVIN_PROJECT_DIR:-$(pwd)}/.devin/hooks/ck-validate-shell.sh"|,
                "timeout" => 15
              }
            ]
          }
        ],
        "UserPromptSubmit" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" =>
                  ~s|sh "${DEVIN_PROJECT_DIR:-$(pwd)}/.devin/hooks/ck-user-prompt-submit.sh"|,
                "timeout" => 10
              }
            ]
          }
        ],
        "Stop" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => ~s|sh "${DEVIN_PROJECT_DIR:-$(pwd)}/.devin/hooks/ck-stop.sh"|,
                "timeout" => 10
              }
            ]
          }
        ]
      }
    }
  end

  def devin_terminal_hook_scripts do
    [
      {"ck-validate-shell.sh", &shell_gate_hook_contents/0},
      {"ck-user-prompt-submit.sh", &codex_user_prompt_submit_hook_contents/0},
      {"ck-stop.sh", &stop_hook_contents/0}
    ]
  end

  def warp_native_mcp_payload(project_root, opts) do
    root =
      if portable_project_root?(opts) do
        Distribution.portable_project_root()
      else
        Path.expand(project_root)
      end

    project_root_arg =
      case opts[:scope] do
        "user" -> "<PROJECT_ROOT>"
        _ -> root
      end

    working_directory =
      case opts[:scope] do
        "user" -> "<PROJECT_ROOT>"
        _ -> root
      end

    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "command" => mcp_command(project_root, opts),
          "args" => ["mcp", "--project-root", project_root_arg],
          "env" => %{},
          "working_directory" => working_directory
        }
      }
    }
  end

  def hosted_mcp_payload(opts) do
    base_url = Keyword.get(opts, :hosted_base_url, "https://your-controlkeel.example")
    client_id = Keyword.get(opts, :oauth_client_id, "ck-sa-<service-account-id>")

    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "transport" => "http",
          "url" => "#{base_url}/mcp",
          "oauth" => %{
            "grant_type" => "client_credentials",
            "token_endpoint" => "#{base_url}/oauth/token",
            "client_id" => client_id,
            "client_secret_env" => "CONTROLKEEL_SERVICE_ACCOUNT_SECRET",
            "resource" => "#{base_url}/mcp",
            "scope" => Enum.join(ControlKeel.Mcp.ProtocolInterop.hosted_mcp_scopes(), " ")
          }
        }
      }
    }
  end

  @doc false
  def mcp_command(project_root, opts) do
    if portable_project_root?(opts) do
      "controlkeel"
    else
      root = Path.expand(project_root)

      case source_repo_stdio_mcp_launcher(root) do
        {:ok, path} ->
          path

        :error ->
          # Portable default: bare `controlkeel` resolved by the host via PATH,
          # never a machine-specific absolute wrapper path. The bootstrap
          # wrapper bakes an absolute CK_PROJECT_ROOT that breaks when a
          # project-local MCP config (e.g. .opencode/mcp.json, .codex/config) is
          # committed, shared with a teammate, or the project folder is moved.
          # The MCP server resolves the real root from CK_PROJECT_ROOT or its
          # working directory at runtime (stdio_project_root/0).
          "controlkeel"
      end
    end
  end

  @doc false
  def mcp_args(project_root, opts) do
    if portable_project_root?(opts) do
      ["mcp", "--project-root", Distribution.portable_project_root()]
    else
      root = Path.expand(project_root)

      case source_repo_stdio_mcp_launcher(root) do
        {:ok, _} ->
          []

        :error ->
          # Relative "." keeps the config portable across machines; the host
          # resolves it against the workspace cwd, and the server falls back to
          # CK_PROJECT_ROOT when set.
          ["mcp", "--project-root", Distribution.portable_project_root()]
      end
    end
  end

  # When opening the ControlKeel *repository* as the workspace, prefer the repo
  # `bin/controlkeel-mcp` launcher (MIX_QUIET, no per-connect `mix compile`) over
  # `controlkeel/bin/…` wrappers that may be older Python shims from prior installs.
  def source_repo_stdio_mcp_launcher(root) do
    marker = Path.join(root, "lib/controlkeel/application.ex")
    launcher = Path.join(root, "bin/controlkeel-mcp")

    if File.exists?(marker) and File.exists?(launcher) do
      {:ok, Path.expand(launcher)}
    else
      :error
    end
  end

  def portable_project_root?(opts) do
    Keyword.get(opts, :portable_project_root, false)
  end

  def install_guide_contents(project_root, opts) do
    project_root_line =
      if portable_project_root?(opts) do
        "`.` (portable release bundle mode; replace with your governed project root if needed)"
      else
        "`#{Path.expand(project_root)}`"
      end

    """
    # Install ControlKeel

    Use one of these supported install paths before loading this bundle:

    #{Distribution.install_markdown_all()}

    GitHub releases: <#{Distribution.github_releases_url()}>

    ## MCP runtime

    This bundle expects the ControlKeel MCP runtime to be reachable through:

    - `controlkeel mcp --project-root #{project_root_line}`
    - Hosted MCP alternative: use the generated `.mcp.hosted.json` template with a workspace service account (`POST /oauth/token` + `POST /mcp`)

    ### Developing the ControlKeel repository (local / no GitHub release)

    When your workspace is this `controlkeel` source tree, `bin/controlkeel-mcp` uses **your checkout only** via `mix ck.mcp` (a plain `mix release` `bin/controlkeel` does not expose an `mcp` subcommand). It intentionally does **not** prefer a global `controlkeel` on `PATH`, so you are not debugging a stale Homebrew build while iterating locally. To force a different executable that implements `controlkeel mcp` (e.g. a Burrito build), set `CONTROLKEEL_BIN` in the MCP server env—do not set it to `_build/.../rel/.../bin/controlkeel` from assemble-only releases.

    ControlKeel can auto-bootstrap the governed project binding on first use. If you already ran `controlkeel init` or `controlkeel bootstrap` inside the target repository, the generated project wrapper under `controlkeel/bin/` can be used instead of the plain `controlkeel` binary.

    ## Provider access

    ControlKeel resolves model access in this order:

    1. Agent bridge when the host client exposes one
    2. CK provider profile or stored key
    3. Local Ollama
    4. Heuristic/no-LLM fallback

    If no model provider is available, MCP governance, findings, proof, benchmark, and policy surfaces still work; only true LLM-backed features degrade.

    ## Required CK tool surface

    #{Enum.map_join(Distribution.required_mcp_tools(), "\n", &"- `#{&1}`")}
    """
  end

  def roo_rule_contents do
    """
    # ControlKeel governance for Roo Code

    - Read `AGENTS.md` before large refactors, risky edits, schema changes, or release work.
    - Prefer ControlKeel MCP tools for validation, findings, budgets, proofs, and routing.
    - Do not bypass a blocked ControlKeel finding without an explicit human approval step.
    """
  end

  def roo_command_contents do
    """
    # ControlKeel review

    1. Read `AGENTS.md`, `.roomodes`, and any Roo guidance files in the workspace.
    2. Gather context before editing files.
    3. Use `ck_context` for task, workspace, transcript, and resume context, then `ck_validate` before and after risky changes.
    4. Summarize findings, risk, proof state, and benchmark impact before finishing.
    """
  end

  def roo_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the plan to `.roo/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .roo/review-plan.md --submitted-by roo-code --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Do not execute until the review is approved.
    """
  end

  def roo_guidance_contents do
    """
    # ControlKeel + Roo Code

    Use ControlKeel as the governance layer for risky work. Treat CK findings as the safety boundary, not optional advice.

    Start with `controlkeel-governance`, then load domain skills as needed.
    """
  end

  def roo_cloud_guidance_contents do
    """
    # ControlKeel + Roo cloud agents

    When Roo cloud or remote agents are involved:

    1. Keep the human-readable plan in the repo.
    2. Submit plan or completion packets through ControlKeel review.
    3. Return blocked findings and proof state with the final handoff.
    """
  end

  def roo_modes_contents do
    """
    customModes:
      - slug: controlkeel-operator
        name: ControlKeel Operator
        roleDefinition: >
          You are Roo Code operating inside a ControlKeel-governed repository. Use
          ControlKeel MCP tools for validation, findings, budgets, proofs, and routing
          before finalizing risky work.
        whenToUse: Use for governed code changes, validation, benchmark, or release work.
        description: Governed Roo Code mode backed by ControlKeel MCP.
        groups:
          - read
          - edit
          - command
          - mcp
        source: project
    """
  end

  def goose_hints_contents do
    """
    This repository is governed by ControlKeel.

    @AGENTS.md

    Use ControlKeel MCP tools before risky edits, schema changes, auth changes, deployment work, or benchmark-sensitive changes.

    Always run validation and findings review before marking work complete.
    """
  end

  def goose_workflow_contents do
    """
    name: controlkeel-review
    description: Review the task through ControlKeel validation, findings, and proof surfaces before completion.
    steps:
      - Read AGENTS.md and .goosehints.
      - Gather repo and task context before editing.
      - Use ControlKeel MCP tools for validation, findings, budgets, routing, and proofs.
      - Summarize risk, findings, and proof state before handoff.
    """
  end

  def goose_command_contents do
    """
    # ControlKeel review

    Use this command when Goose needs a governed review pass before finalizing work.

    1. Read `.goosehints` and `AGENTS.md`.
    2. Use `ck_context` for task, workspace, and transcript context, then `ck_validate`.
    3. Summarize blocked findings and proof status.
    """
  end

  def goose_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the plan to `goose/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file goose/review-plan.md --submitted-by goose --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Do not execute until the review is approved.
    """
  end

  def goose_extension_yaml(project_root, opts) do
    goose_extension_config(project_root, opts)
    |> UtilsYaml.document()
  end

  def goose_extension_config(project_root, opts) do
    %{
      "extensions" => %{
        "controlkeel" => %{
          "enabled" => true,
          "type" => "stdio",
          "name" => "ControlKeel",
          "description" => "ControlKeel governance MCP server",
          "cmd" => mcp_command(project_root, opts),
          "args" => mcp_args(project_root, opts),
          "timeout" => 300
        }
      }
    }
  end

  def kilo_config_snippet(project_root, opts) do
    %{
      "mcp" => %{
        "controlkeel" => %{
          "type" => "local",
          "command" => [mcp_command(project_root, opts) | mcp_args(project_root, opts)],
          "enabled" => true
        }
      }
    }
  end

  def kilo_command_contents do
    """
    # ControlKeel review

    1. Read `AGENTS.md` and any repo-local Kilo guidance before making risky edits.
    2. Call `ck_context` for task, workspace, transcript, and resume context.
    3. Run `ck_validate` before and after risky code, config, shell, or deploy work.
    4. Summarize blocked findings, proof state, and review status before completion.
    """
  end

  def droid_profile_contents do
    """
    ---
    name: controlkeel
    description: Govern risky code and release work through ControlKeel validation, proofs, and browser review.
    model: inherit
    ---

    # ControlKeel Droid

    Use ControlKeel governance, findings, proofs, budgets, and benchmark workflows before making risky code or deployment changes.

    Start each task by reading `AGENTS.md`, then use ControlKeel MCP tools for validation and finding escalation.
    """
  end

  def droid_review_command_contents do
    """
    ---
    description: Run a governed ControlKeel review for the current Droid task
    disable-model-invocation: true
    ---

    # ControlKeel review

    Review the current task or PR goal through ControlKeel before risky work or final completion.

    1. Read `AGENTS.md` and any repo-local context first.
    2. Call `ck_context` for mission, workspace, memory, and review state.
    3. Call `ck_validate` before and after risky changes.
    4. Summarize findings, verification strength, risk, and next steps before continuing.
    """
  end

  def droid_submit_plan_command_contents do
    """
    ---
    description: Submit the current Droid plan to ControlKeel and wait for approval
    disable-model-invocation: true
    ---

    # ControlKeel submit-plan

    1. Save the current implementation plan to `.factory/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .factory/review-plan.md --submitted-by droid --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Do not begin implementation until the review is approved.
    """
  end

  def droid_annotate_command_contents do
    """
    ---
    description: Submit focused file-risk notes to ControlKeel before risky Droid edits
    disable-model-invocation: true
    ---

    # ControlKeel annotate

    1. Save the target file path, risks, and focused notes to `.factory/annotate.md`.
    2. Run `controlkeel review plan submit --title "File annotation review" --body-file .factory/annotate.md --submitted-by droid --json`.
    3. Wait for the response before applying risky edits.
    """
  end

  def droid_last_command_contents do
    """
    ---
    description: Re-open the latest ControlKeel review tracked in Droid
    disable-model-invocation: true
    ---

    # ControlKeel last

    1. Read the last stored review id from your notes or prior command output.
    2. Run `controlkeel review plan open --id <review_id> --json`.
    3. If the review is still pending, ask the user for approval in this conversation, then record it with `controlkeel review plan respond <review_id> --decision approved --json`.
    """
  end

  def devin_runtime_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Devin + ControlKeel

    Use this runtime export when Devin runs as a hosted coding environment instead of a local editor attach flow.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so Devin can ingest ControlKeel policy and workflow context.

    ## Recommended Devin setup

    - Use Devin's custom MCP flow and point it at the bundled `devin/controlkeel-mcp.json`
    - Prefer service accounts or shared runtime secrets for any OAuth-backed MCPs you add in Devin
    - Use webhook events such as `finding.created`, `task.completed`, `task.failed`, and `proof.generated` to sync governance state into CI or issue workflows
    """
  end

  def devin_terminal_readme_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Devin for Terminal + ControlKeel

    Use this native bundle when Devin runs locally in your shell and reads repo-local `.devin/` assets.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so Devin can ingest ControlKeel policy and workflow context.

    ## Recommended Devin for Terminal setup

    - Keep `.devin/config.json` checked in for project-scoped MCP and governance defaults.
    - Keep `.devin/hooks.v1.json` and `.devin/hooks/` checked in so lifecycle guidance stays repo-visible.
    - Keep `.agents/skills/` and `.devin/agents/` checked in so Devin can discover CK skills and governed subagents.
    - Use `devin mcp get controlkeel` to inspect the ControlKeel MCP registration after attach.
    """
  end

  def warp_native_readme_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    project_root_note =
      case opts[:scope] do
        "user" ->
          "Replace `<PROJECT_ROOT>` in `.warp/controlkeel-mcp.json` with the repo path you want Warp to govern before importing it."

        _ ->
          "The generated `.warp/controlkeel-mcp.json` already points at this repo and sets `working_directory` explicitly, matching Warp's local MCP guidance."
      end

    """
    # Warp + ControlKeel

    Use this native bundle when you want Warp's local Oz agents to discover ControlKeel skills and repo rules directly from the repository.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so Warp project rules apply automatically.

    ## Recommended Warp setup

    - Keep `.agents/skills/` checked in; Warp scans open-standard Agent Skills directories.
    - Import or copy `.warp/controlkeel-mcp.json` into Warp Settings > MCP Servers or Warp Drive > MCP Servers.
    - #{project_root_note}
    - If you already use Claude Code, Codex CLI, Gemini CLI, or OpenCode inside Warp's third-party utility bar, keep using the existing CK attach flow for those hosts separately. This bundle is for Warp's own local Oz agents.
    """
  end

  def codex_plugin_manifest do
    %{
      "name" => "controlkeel",
      "version" => app_version(),
      "description" =>
        "ControlKeel governance skills, commands, agents, and MCP bridge for Codex.",
      "author" => %{
        "name" => "ControlKeel",
        "email" => "opensource@controlkeel.local",
        "url" => "https://github.com/aryaminus/controlkeel"
      },
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => "https://github.com/aryaminus/controlkeel",
      "license" => "Apache-2.0",
      "keywords" => ["governance", "security", "agent-skills", "mcp"],
      "skills" => "./skills/",
      "hooks" => "./hooks.json",
      "commands" => "./commands/",
      "mcpServers" => "./.mcp.json",
      "apps" => "./.app.json",
      "interface" => %{
        "displayName" => "ControlKeel",
        "shortDescription" => "Govern agent work with MCP, skills, and proofs.",
        "longDescription" =>
          "ControlKeel makes agent-built work secure, scoped, validated, and production-ready across MCP, proof, findings, budgets, and routing.",
        "developerName" => "ControlKeel",
        "category" => "Developer Tools",
        "capabilities" => ["Write", "Interactive", "Governance"],
        "websiteURL" => "https://github.com/aryaminus/controlkeel",
        "privacyPolicyURL" => "https://github.com/aryaminus/controlkeel",
        "termsOfServiceURL" => "https://github.com/aryaminus/controlkeel",
        "defaultPrompt" => [
          "Load ControlKeel governance and validate the current task.",
          "Review the repo through ControlKeel before a risky change.",
          "Use CK routing and proofs to complete this task safely."
        ],
        "brandColor" => "#0f766e"
      }
    }
  end

  def codex_marketplace_manifest do
    %{
      "name" => "controlkeel",
      "interface" => %{"displayName" => "ControlKeel"},
      "plugins" => [
        %{
          "name" => "controlkeel",
          "source" => %{"source" => "local", "path" => "./plugins/controlkeel"},
          "policy" => %{"installation" => "AVAILABLE", "authentication" => "ON_USE"},
          "category" => "Developer Tools"
        }
      ]
    }
  end

  def codex_app_manifest do
    %{
      "name" => "controlkeel",
      "description" => "Codex plugin companion app metadata for hosted MCP and skills delivery.",
      "protocols" => ["mcp"]
    }
  end

  @doc false
  def claude_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance skills, subagents, and MCP bridge.",
      "version" => app_version(),
      "author" => %{
        "name" => "ControlKeel",
        "email" => "opensource@controlkeel.local",
        "url" => "https://github.com/aryaminus/controlkeel"
      },
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => "https://github.com/aryaminus/controlkeel",
      "license" => "Apache-2.0",
      "keywords" => ["governance", "mcp", "skills", "security"],
      "category" => "governance",
      "agents" => "./agents/",
      "skills" => "./skills/",
      "commands" => "./commands/",
      "hooks" => "./hooks/hooks.json",
      "mcpServers" => "./.mcp.json"
    }
  end

  @doc false
  def claude_marketplace_manifest do
    %{
      "name" => "controlkeel",
      "owner" => %{
        "name" => "ControlKeel",
        "email" => "opensource@controlkeel.local"
      },
      "metadata" => %{
        "description" =>
          "ControlKeel governance plugin: skills, subagents, MCP tools, and lifecycle hooks for AI agent governance.",
        "version" => app_version()
      },
      "plugins" => [
        %{
          "name" => "controlkeel",
          "source" => "./",
          "description" => "ControlKeel governance skills, subagents, and MCP bridge.",
          "version" => app_version(),
          "category" => "governance",
          "keywords" => ["governance", "mcp", "skills", "security"]
        }
      ]
    }
  end

  def copilot_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance skills, agents, and MCP bridge.",
      "version" => app_version(),
      "author" => %{"name" => "ControlKeel", "email" => "opensource@controlkeel.local"},
      "license" => "Apache-2.0",
      "keywords" => ["governance", "security", "skills"],
      "skills" => "skills",
      "agents" => "agents",
      "commands" => "commands",
      "hooks" => "hooks.json",
      "mcpServers" => ".mcp.json",
      "tags" => ["governance", "security", "skills"]
    }
  end

  @doc false
  def claude_hooks_manifest do
    %{
      "hooks" => %{
        "PreToolUse" => [
          %{
            "matcher" => "Bash",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/ck-validate-shell.sh",
                "timeout" => 15
              }
            ]
          },
          %{
            "matcher" => "Write|Edit",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/ck-validate-write.sh",
                "timeout" => 10
              }
            ]
          }
        ],
        "UserPromptSubmit" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/ck-user-prompt-submit.sh",
                "timeout" => 10
              }
            ]
          }
        ],
        "Stop" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/ck-stop.sh",
                "timeout" => 10
              }
            ]
          }
        ],
        "PostCompact" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/ck-post-compact.sh",
                "timeout" => 10
              }
            ]
          }
        ],
        "PreCompact" => [
          %{
            "hooks" => [
              %{"type" => "command", "command" => "./hooks/ck-pre-compact.sh", "timeout" => 5}
            ]
          }
        ],
        "PermissionRequest" => [
          %{
            "matcher" => "ExitPlanMode",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/controlkeel-review.sh",
                "timeout" => 345_600
              }
            ]
          }
        ]
      }
    }
  end

  def claude_manual_settings do
    %{
      "hooks" => %{
        "PreToolUse" => [
          %{
            "matcher" => "Bash",
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/pre-tool-use-bash.sh"),
                "timeout" => 10
              }
            ]
          },
          %{
            "matcher" => "Write|Edit",
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/pre-tool-use-write.sh"),
                "timeout" => 10
              }
            ]
          }
        ],
        "Stop" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/stop.sh"),
                "timeout" => 10
              }
            ]
          }
        ],
        "PostCompact" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/post-compact.sh"),
                "timeout" => 5
              }
            ]
          }
        ],
        "PreCompact" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/pre-compact.sh"),
                "timeout" => 5
              }
            ]
          }
        ],
        "UserPromptSubmit" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/user-prompt-submit.sh"),
                "timeout" => 10
              }
            ]
          }
        ],
        "PermissionRequest" => [
          %{
            "matcher" => "ExitPlanMode",
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".claude/hooks/permission-request.sh")
              }
            ]
          }
        ]
      }
    }
  end

  def copilot_hooks_manifest do
    %{
      "version" => 1,
      "hooks" => %{
        "preToolUse" => [
          %{
            "type" => "command",
            "bash" => "./bin/ck-validate-shell.sh",
            "timeoutSec" => 15,
            "comment" =>
              "Validates shell commands with ControlKeel; silent unless a command is blocked."
          }
        ]
      }
    }
  end

  def empty_hooks_manifest do
    %{"hooks" => %{}}
  end

  @doc false
  def codex_hooks_manifest do
    %{
      "hooks" => %{
        "PreToolUse" => [
          %{
            "matcher" => "Bash",
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".codex/hooks/ck-validate-shell.sh"),
                "timeout" => 15
              }
            ]
          }
        ],
        "UserPromptSubmit" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".codex/hooks/ck-user-prompt-submit.sh"),
                "timeout" => 10
              }
            ]
          }
        ],
        "Stop" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".codex/hooks/ck-stop.sh"),
                "timeout" => 10
              }
            ]
          }
        ]
      }
    }
  end

  @doc false
  def codex_hook_scripts do
    [
      {"ck-validate-shell.sh", &shell_gate_hook_contents/0},
      {"ck-user-prompt-submit.sh", &codex_user_prompt_submit_hook_contents/0},
      {"ck-stop.sh", &stop_hook_contents/0}
    ]
  end

  @doc false
  def claude_plugin_hook_scripts do
    [
      {"ck-validate-shell.sh", &shell_gate_hook_contents/0},
      {"ck-validate-write.sh", &claude_plugin_validate_write_hook_contents/0},
      {"ck-user-prompt-submit.sh", &claude_plugin_user_prompt_submit_hook_contents/0},
      {"ck-stop.sh", &stop_hook_contents/0},
      {"ck-post-compact.sh", &claude_plugin_post_compact_hook_contents/0},
      {"ck-pre-compact.sh", &claude_plugin_pre_compact_hook_contents/0}
    ]
  end

  @doc """
  Stop hook shared by every host. It never blocks the turn and stays silent
  unless the project's blocked-finding count has risen since the last report
  in this host session, so stale findings do not nag on every stop and
  long-running or auto-approved loops can always finish.

  `format` selects the host's reply shape: `:system_message` (Claude Code,
  Codex, Devin, Antigravity) or `:cursor_followup` (Cursor, whose stop hook
  can only answer with a follow-up prompt, so it fires at most once per rise).
  """
  def stop_hook_contents(format \\ :system_message) do
    reply =
      case format do
        :cursor_followup ->
          ~S|printf '{"followup_message":"ControlKeel recorded %s blocked finding(s) for this project. Review them with ck_context before treating the work as done."}\n' "$blocked"|

        :system_message ->
          ~S|printf '{"systemMessage":"ControlKeel has %s blocked finding(s) for this project. Review them with ck_context or the findings page before treating the work as done."}\n' "$blocked"|
      end

    """
    #!/usr/bin/env sh
    #{hook_runtime_helpers()}

    input=$(cat)
    continuing="false"
    host_session=""

    if command -v jq >/dev/null 2>&1; then
      continuing=$(printf '%s' "$input" | jq -r 'if (.stop_hook_active == true) or ((.loop_count // 0) > 0) then "true" else "false" end' 2>/dev/null || printf 'false')
      host_session=$(printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null || printf '')
    elif command -v python3 >/dev/null 2>&1; then
      continuing=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if d.get('stop_hook_active') or (d.get('loop_count') or 0) > 0 else 'false')" 2>/dev/null || printf 'false')
      host_session=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id') or d.get('conversation_id') or '')" 2>/dev/null || printf '')
    fi

    [ "$continuing" = "false" ] || exit 0

    context=$(CONTROLKEEL_HOOK_TIMEOUT_SECONDS="${CONTROLKEEL_STOP_HOOK_TIMEOUT_SECONDS:-3}" ck_run context --json 2>/dev/null || true)
    [ -n "$context" ] || exit 0

    blocked="0"
    if command -v jq >/dev/null 2>&1; then
      blocked=$(printf '%s' "$context" | jq -r '.active_findings.blocked // 0' 2>/dev/null || printf '0')
    elif command -v python3 >/dev/null 2>&1; then
      blocked=$(printf '%s' "$context" | python3 -c "import sys,json; print(int(json.load(sys.stdin).get('active_findings', {}).get('blocked', 0)))" 2>/dev/null || printf '0')
    fi

    case "$blocked" in
      ''|*[!0-9]*) exit 0 ;;
    esac

    # Remember the last count reported to this host session in a private,
    # user-owned directory. Resetting to 0 when findings clear means a new
    # blocked finding is reported; staying at the last reported count keeps
    # fluctuations below it quiet.
    state_dir=$(ck_state_dir) || exit 0
    state_key=$(printf '%s' "${host_session:-default}" | tr -c 'A-Za-z0-9_-' '_')
    state_file="$state_dir/stop-${state_key}"
    reported=$(cat "$state_file" 2>/dev/null || printf '0')
    case "$reported" in
      ''|*[!0-9]*) reported=0 ;;
    esac

    if [ "$blocked" -eq 0 ]; then
      [ "$reported" -eq 0 ] || ck_write_state "$state_file" 0
      exit 0
    fi

    [ "$blocked" -gt "$reported" ] || exit 0
    ck_write_state "$state_file" "$blocked"

    #{reply}
    exit 0
    """
  end

  def claude_plugin_post_compact_hook_contents do
    ~S"""
    #!/usr/bin/env sh
    set -u

    printf '%s\n' '{"systemMessage":"Context was compacted. You are in a ControlKeel-governed session: always call ck_context before proceeding, ck_validate before code or shell changes, and ck_finding for any issues you discover. Resume any in-progress work only after re-loading governance state."}'
    exit 0
    """
  end

  def claude_plugin_pre_compact_hook_contents do
    """
    #!/usr/bin/env sh
    set -u

    printf '%s\n' '{"systemMessage":"Context compaction is starting. Preserve the active ControlKeel decision gate, approved decisions, blocked findings, proof obligations, governed manifest, and next valid action in the compaction summary."}'
    exit 0
    """
  end

  def claude_plugin_validate_write_hook_contents do
    """
    #!/usr/bin/env sh
    #{hook_runtime_helpers()}

    input=$(cat)
    tool_name=""
    file_path=""

    if command -v jq >/dev/null 2>&1; then
      tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
      file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    elif command -v python3 >/dev/null 2>&1; then
      tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
      file_path=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
    fi

    if [ -z "$file_path" ]; then
      exit 0
    fi

    sensitive_pattern='\.env$|credentials|secret|\.pem$|\.key$|id_rsa|\.token$|passw'
    if printf '%s' "$file_path" | grep -qiE "$sensitive_pattern"; then
      result=$(ck_run validate --content "${tool_name:-Write} to ${file_path}" --kind config --json 2>/dev/null || true)
      if [ -n "$result" ]; then
        if printf '%s' "$result" | grep -q '"decision":"block"'; then
          printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"ControlKeel blocked write to sensitive file: %s. Review ck_finding before retrying."}}\n' "$file_path"
          exit 0
        fi
      fi
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Writing to potentially sensitive file: %s. Verify this is intentional and that ck_validate was called for this change."}}\n' "$file_path"
      exit 0
    fi

    exit 0
    """
  end

  def claude_plugin_user_prompt_submit_hook_contents do
    """
    #!/usr/bin/env sh
    #{hook_runtime_helpers()}

    input=$(cat)
    prompt=""

    if command -v jq >/dev/null 2>&1; then
      prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
    elif command -v python3 >/dev/null 2>&1; then
      prompt=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt', ''))" 2>/dev/null)
    fi

    if [ -z "$prompt" ]; then
      exit 0
    fi

    if printf '%s' "$prompt" | grep -Eiq '(^|[^A-Za-z0-9_-])(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|PGP) PRIVATE KEY|api[_-]?key[[:space:]]*[:=]|password[[:space:]]*[:=])'; then
      printf '%s\n' '{"decision":"block","reason":"Potential secret material detected in the prompt. Remove credentials or private keys before continuing."}'
      exit 0
    fi

    if printf '%s' "$prompt" | grep -Eiq '(rm[[:space:]]+-rf|drop[[:space:]]+database|delete[[:space:]]+everything|wipe[[:space:]]+the[[:space:]]+repo)'; then
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"The prompt asks for destructive work. Pause to confirm scope, preserve evidence, and use ck_validate before executing risky shell or config steps."}}'
      exit 0
    fi

    exit 0
    """
  end

  @doc """
  Shell gate shared by every host with a pre-shell hook. Read-only commands
  skip validation, a ControlKeel block denies the command, a warning goes to
  the agent rather than the person, and an unreachable ControlKeel is
  mentioned once per host session instead of on every command.

  `format` is `:claude` (Claude Code, Codex, Devin, Antigravity), `:cursor`,
  or `:copilot`, matching each host's hook reply shape.
  """
  def shell_gate_hook_contents(format \\ :claude) do
    {deny, warn, unavailable, allow} =
      case format do
        :claude ->
          {~S|'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"ControlKeel blocked this shell command. Review ck_validate findings before retrying."}}'|,
           ~S|'{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"ControlKeel flagged this shell command with a warning. Check ck_validate if the risk matters for this task."}}'|,
           ~S|'{"systemMessage":"ControlKeel is not reachable, so shell commands are not being validated in this session."}'|,
           nil}

        :cursor ->
          {~S|'{"permission":"deny","user_message":"ControlKeel blocked this shell command.","agent_message":"ControlKeel blocked this shell command. Check ck_validate for details."}'|,
           ~S|'{"permission":"allow","agent_message":"ControlKeel flagged this shell command with a warning. Check ck_validate if the risk matters for this task."}'|,
           ~S|'{"permission":"allow","user_message":"ControlKeel is not reachable, so shell commands are not being validated in this session."}'|,
           ~S|'{"permission":"allow"}'|}

        :copilot ->
          {~S|'{"permissionDecision":"deny","permissionDecisionReason":"ControlKeel blocked this shell command. Review ck_validate findings before retrying."}'|,
           nil, nil, nil}
      end

    emit = fn
      nil -> "exit 0"
      json -> "printf '%s\\n' #{json}\n      exit 0"
    end

    """
    #!/usr/bin/env sh
    #{hook_runtime_helpers()}

    input=$(cat)
    command_text=""
    host_session=""

    if command -v jq >/dev/null 2>&1; then
      command_text=$(printf '%s' "$input" | jq -r '
        (.tool_input.command // .command // .input.command //
          (if ((.toolName // "") | test("^(bash|shell|powershell)$")) then
            ((.toolArgs // "{}") | (try fromjson catch {}) | .command)
          else empty end)) // empty' 2>/dev/null)
      host_session=$(printf '%s' "$input" | jq -r '.session_id // .conversation_id // .sessionId // empty' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
      command_text=$(printf '%s' "$input" | python3 -c "
    import sys, json
    d = json.load(sys.stdin)
    c = (d.get('tool_input') or {}).get('command') or d.get('command') or (d.get('input') or {}).get('command')
    if not c and str(d.get('toolName', '')) in ('bash', 'shell', 'powershell'):
        try:
            c = json.loads(d.get('toolArgs') or '{}').get('command')
        except Exception:
            c = None
    print(c or '')
    " 2>/dev/null)
      host_session=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id') or d.get('conversation_id') or d.get('sessionId') or '')" 2>/dev/null)
    fi

    if [ -z "$command_text" ] || ck_readonly_command "$command_text"; then
      #{emit.(allow)}
    fi

    result=$(ck_run validate --content "$command_text" --kind shell --json 2>/dev/null)
    validation_status=$?

    if printf '%s' "$result" | grep -q '"decision":"block"'; then
      #{emit.(deny)}
    fi

    if printf '%s' "$result" | grep -q '"decision":"warn"'; then
      #{emit.(warn || allow)}
    fi

    if [ "$validation_status" -ne 0 ] || ! printf '%s' "$result" | grep -q '"decision":"allow"'; then
      if ck_first_time "unreachable-${host_session:-$PPID}"; then
        #{emit.(unavailable || allow)}
      fi
    fi

    #{emit.(allow)}
    """
  end

  def codex_user_prompt_submit_hook_contents do
    ~S"""
    #!/usr/bin/env sh
    set -u

    input=$(cat)
    prompt=""

    if command -v jq >/dev/null 2>&1; then
      prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
    elif command -v python3 >/dev/null 2>&1; then
      prompt=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt', ''))" 2>/dev/null)
    fi

    if [ -z "$prompt" ]; then
      exit 0
    fi

    if printf '%s' "$prompt" | grep -Eiq '(^|[^A-Za-z0-9_-])(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|PGP) PRIVATE KEY)'; then
      printf '%s\n' '{"decision":"block","reason":"Potential secret material detected in the prompt. Remove credentials or private keys before continuing."}'
      exit 0
    fi

    if printf '%s' "$prompt" | grep -Eiq '(rm[[:space:]]+-rf|drop[[:space:]]+database|delete[[:space:]]+everything|wipe[[:space:]]+the[[:space:]]+repo)'; then
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"The prompt asks for destructive work. Pause to confirm scope, preserve evidence, and use ck_validate before executing risky shell or config steps."}}'
      exit 0
    fi

    exit 0
    """
  end

  @doc false
  def review_bridge_shell_contents(submitted_by) do
    """
    #!/usr/bin/env sh
    #{hook_runtime_helpers()}

    tmp_body=$(mktemp)
    trap 'rm -f "$tmp_body"' EXIT INT TERM

    cat >"$tmp_body"

    : "${CONTROLKEEL_AGENT_ID:=#{submitted_by}}"
    export CONTROLKEEL_AGENT_ID

    submit_output=$(ck_run review plan submit --stdin --submitted-by "#{submitted_by}" --json <"$tmp_body")
    printf "%s\\n" "$submit_output"

    if command -v jq >/dev/null 2>&1; then
      review_id=$(printf "%s\\n" "$submit_output" | jq -r '.review.id // empty')
    else
      review_id=$(printf "%s\\n" "$submit_output" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p' | head -n 1)
    fi

    if [ -z "$review_id" ]; then
      echo "ControlKeel hook could not parse the submitted review id." >&2
      exit 0
    fi

    ck_run review plan wait --id "$review_id" --json
    """
  end

  @doc false
  def review_bridge_powershell_contents(submitted_by) do
    """
    $plan = [Console]::In.ReadToEnd()
    $tempPath = Join-Path $env:TEMP ("controlkeel-plan-" + [Guid]::NewGuid().ToString() + ".md")

    try {
      Set-Content -Path $tempPath -Value $plan -NoNewline
      if (-not $env:CONTROLKEEL_AGENT_ID) {
        $env:CONTROLKEEL_AGENT_ID = "#{submitted_by}"
      }

      $submitOutput = & controlkeel review plan submit --stdin --submitted-by #{submitted_by} --json < $tempPath
      $submitOutput | ForEach-Object { Write-Output $_ }
      $submitJson = $submitOutput | ConvertFrom-Json

      if (-not $submitJson.review.id) {
        Write-Error "ControlKeel hook could not parse the submitted review id."
        exit 1
      }

      $reviewId = $submitJson.review.id
      & controlkeel review plan wait --id $reviewId --json
      exit $LASTEXITCODE
    }
    finally {
      if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force
      }
    }
    """
  end

  def cline_rule_contents do
    """
    ---
    name: controlkeel-governance
    description: Keep ControlKeel governance active for risky edits, validation, proof capture, and release-sensitive work.
    ---

    # ControlKeel governance

    - Prefer ControlKeel MCP tools before risky edits, schema changes, auth changes, or release work.
    - Read `AGENTS.md` before large repo-wide changes.
    - Run validation and findings review before marking work complete.
    - Keep proof and benchmark surfaces current when asked to compare or attest behavior.
    """
  end

  def cline_workflow_contents do
    """
    ---
    description: Review the current task through ControlKeel validation, findings, and proof surfaces before finalizing.
    ---

    # ControlKeel review workflow

    1. Read `AGENTS.md` for ControlKeel governance context.
    2. Gather repo and task context before changing files.
    3. Use ControlKeel MCP tools for validation, findings, budget, and routing when relevant.
    4. Summarize risk, findings, and proof status before completing the task.
    """
  end

  def cline_command_contents do
    """
    # ControlKeel review

    Use this command when Cline should run a governed review pass before completing risky work.

    1. Read `AGENTS.md` and the current `.clinerules/` guidance.
    2. Use `ck_context` for task, workspace, and transcript context, then `ck_validate` before presenting a conclusion.
    3. Summarize findings, proof status, and any blockers.
    """
  end

  def cline_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the current plan to `.cline/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .cline/review-plan.md --submitted-by cline --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Do not execute until the review is approved.
    """
  end

  @doc false
  def cursor_rule_contents do
    """
    ---
    description: Govern Cursor work with ControlKeel MCP, findings, budgets, proofs, and routing.
    ---

    Always call ControlKeel before risky edits, shell commands, auth changes, or release work.
    Load `controlkeel-governance` first, then add domain-specific skills as needed.
    """
  end

  @doc false
  def cursor_command_contents do
    """
    # ControlKeel review

    Use ControlKeel before finalizing risky edits, schema changes, auth changes, or release work.

    1. Call `ck_context` for mission, workspace, transcript, and resume context.
    2. Call `ck_validate`.
    3. Summarize findings, proof status, and follow-up work.
    """
  end

  @doc false
  def cursor_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the current plan to `.cursor/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .cursor/review-plan.md --submitted-by cursor --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Only implement after approval.
    """
  end

  @doc false
  def cursor_diff_review_command_contents do
    """
    # /controlkeel-diff-review

    Use this command to submit the current diff for ControlKeel governance review before committing.

    1. Capture the current diff: `git diff --staged` (or `git diff` for unstaged).
    2. Call `ck_validate` with `content` set to the diff and `kind: "code"`.
    3. If validation passes, call `ck_review_submit` with `review_type: "diff"`, `submission_body` set to the diff, and `submitted_by: "cursor"`.
    4. Read the returned review.id. Present the diff summary to the user and ask for approval in this conversation.
    5. After approval, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json` (or `ck_review_feedback`).
    6. Only commit after approval.
    """
  end

  @doc false
  def cursor_completion_review_command_contents do
    """
    # /controlkeel-completion-review

    Use this command when the current task is ready for completion review.

    1. Call `ck_context` to gather mission, findings, proof, and budget state.
    2. Summarize what was accomplished, what remains, and any open findings.
    3. Call `ck_review_submit` with `review_type: "completion"`, the summary as `submission_body`, and `submitted_by: "cursor"`.
    4. If there are unresolved blocked findings, surface them before submitting.
    5. Wait for review with `ck_review_status`.
    6. After approval, call `ck_outcome_tracker` with `mode: "record"` to record the session outcome.
    """
  end

  @doc false
  def cursor_background_agent_contents do
    """
    # ControlKeel background agent governance

    When Cursor background agents are enabled, follow this protocol:

    ## Before execution
    1. Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached`.
    2. Call `ck_context` with `session_id: 1` to load mission state and active findings.
    3. Draft the plan, including scope estimate and validation approach.
    4. Call `ck_review_submit` with `review_type: "plan"` before executing.
    5. Wait for approval via `ck_review_status` before proceeding.

    ## During execution
    6. Call `ck_validate` before every risky edit, shell command, or config change.
    7. Use `ck_memory_record` to persist key decisions for future agents.
    8. Call `ck_budget` before expensive operations to stay within limits.
    9. Call `ck_finding` if you discover any unscanned issue.

    ## Handoff
    10. Call `ck_context` again to verify final state.
    11. Return proof status, unresolved findings, budget remaining, and any blocked work.
    12. Call `ck_outcome_tracker` with `mode: "record"` to record the session result.
    """
  end

  def cursor_plugin_manifest(_project_root, opts) do
    version = Keyword.get(opts, :version, app_version())

    # Distributable Cursor plugins must stay portable: marketplace installs land in
    # arbitrary governed projects, not only the ControlKeel source checkout.
    server = %{
      "command" => "controlkeel",
      "args" => ["mcp", "--project-root", "."],
      "env" => %{
        "CK_PROJECT_ROOT" => "${workspaceFolder}",
        "CK_MCP_MODE" => "1",
        "LOGGER_LEVEL" => "warning",
        "MIX_QUIET" => "1"
      }
    }

    slug = Distribution.github_repo_slug()

    %{
      "name" => "controlkeel",
      "version" => version,
      "description" =>
        "ControlKeel governance for Cursor — validation, findings, budgets, proofs, memory, agent routing, and human review via MCP.",
      "author" => %{"name" => "ControlKeel"},
      "license" => "Apache-2.0",
      "homepage" => "https://github.com/#{slug}",
      "repository" => "https://github.com/#{slug}.git",
      "keywords" => [
        "governance",
        "security",
        "compliance",
        "validation",
        "code-review",
        "mcp",
        "budget",
        "proof",
        "agent-routing"
      ],
      "rules" => "./rules/",
      "skills" => "./skills/",
      "agents" => "./agents/",
      "commands" => "./commands/",
      "hooks" => "./hooks/hooks.json",
      "mcpServers" => %{"controlkeel" => server}
    }
  end

  @doc false
  def cursor_agent_contents do
    """
    ---
    name: controlkeel-governor
    description: >-
      A governance-focused agent that enforces ControlKeel policies, validates
      changes, manages findings, and ensures budget compliance.
    ---

    # ControlKeel Governor Agent

    You are a governance agent powered by ControlKeel. Your role is to ensure all code changes, deployments, and decisions follow the governance protocol.

    ## Behavior

    1. Always start by calling `controlkeel update --json`; if `update_available` is `true`, surface a concise CK upgrade notice and consider `controlkeel update --sync-attached` before risky work.
    2. Always start by calling `ck_context` to understand the current mission state.
    3. Validate all proposed changes with `ck_validate` before approving them.
    4. Track findings with `ck_finding` and ensure blocked items are resolved.
    5. Monitor budget with `ck_budget` and flag overspend risks.
    6. Route tasks to the best-fit agent using `ck_route`.
    7. Record decisions in governed memory via `ck_memory_record`.
    8. Submit reviews via `ck_review_submit` for human approval gates.

    ## When delegated to

    If another agent delegates work to you:
    - Load context with `ck_context`
    - Validate the delegated task
    - Return a governance assessment with findings, risk level, and recommendations
    - Record the outcome via `ck_outcome_tracker`
    """
  end

  @doc false
  def cursor_mcp_payload(project_root, opts) do
    base = mcp_payload(project_root, opts)

    case get_in(base, ["mcpServers", "controlkeel"]) do
      server when is_map(server) ->
        env = %{
          "CK_PROJECT_ROOT" => "${workspaceFolder}",
          "CK_MCP_MODE" => "1",
          "LOGGER_LEVEL" => "warning",
          "MIX_QUIET" => "1"
        }

        server =
          server
          |> Map.put("env", env)
          |> Map.put("command", cursor_ide_mcp_command(project_root, opts))

        put_in(base, ["mcpServers", "controlkeel"], server)

      _ ->
        base
    end
  end

  # Cursor does not guarantee cwd == workspace for stdio MCP. Prefer
  # `${workspaceFolder}/…` (expanded by the host) over `./…` so the launcher path
  # resolves even when the process starts outside the repo.
  def cursor_ide_mcp_command(project_root, opts) do
    if portable_project_root?(opts) do
      "controlkeel"
    else
      root = Path.expand(project_root)

      case source_repo_stdio_mcp_launcher(root) do
        {:ok, _} ->
          "${workspaceFolder}/bin/controlkeel-mcp"

        :error ->
          # Match mcp_command/2: bare `controlkeel` on PATH with portable args.
          # Never bake controlkeel/bin/controlkeel-mcp wrapper paths into
          # .cursor/mcp.json — Path.relative_to/2 can fail across /var vs
          # /private/var symlinks and leak machine-specific absolute paths.
          "controlkeel"
      end
    end
  end

  @doc false
  def write_cursor_plugin_bundle!(root, project_root, opts) do
    plugin_json_path = Path.join(root, ".cursor-plugin/plugin.json")
    current_version = app_version()

    # Skip the entire bundle write if the running binary is older than what's
    # already on disk — prevents an installed homebrew/npm binary from
    # overwriting a newer source-synced version on every Stop hook invocation.
    if version_downgrade_for_path?(current_version, plugin_json_path) do
      :ok
    else
      Enum.each(
        [
          {Path.join(root, ".cursor/rules"), Path.join(root, ".cursor-plugin/rules")},
          {Path.join(root, ".agents/skills"), Path.join(root, ".cursor-plugin/skills")},
          {Path.join(root, ".cursor/agents"), Path.join(root, ".cursor-plugin/agents")},
          {Path.join(root, ".cursor/commands"), Path.join(root, ".cursor-plugin/commands")}
        ],
        fn {from, to} ->
          if File.exists?(from) do
            File.rm_rf!(to)
            File.mkdir_p!(Path.dirname(to))
            File.cp_r!(from, to)
          end
        end
      )

      plugin_hook_dir = Path.join(root, ".cursor-plugin/hooks")
      File.mkdir_p!(plugin_hook_dir)

      File.write!(
        Path.join(plugin_hook_dir, "hooks.json"),
        Jason.encode!(cursor_plugin_hooks_manifest(), pretty: true) <> "\n"
      )

      for {name, contents_fn} <- cursor_hook_scripts() do
        path = Path.join(plugin_hook_dir, name)
        File.write!(path, contents_fn.())
        File.chmod!(path, 0o755)
      end

      File.write!(
        plugin_json_path,
        Jason.encode!(cursor_plugin_manifest(project_root, opts), pretty: true) <> "\n"
      )
    end
  end

  # Returns true when the running binary's version is strictly older than the
  # version already recorded in the given plugin.json file on disk.
  @doc false
  def version_downgrade_for_path?(current_version, plugin_json_path) do
    with {:ok, raw} <- File.read(plugin_json_path),
         {:ok, data} <- Jason.decode(raw),
         recorded when is_binary(recorded) <- Map.get(data, "version") do
      parse_plugin_vsn(current_version) < parse_plugin_vsn(recorded)
    else
      _ -> false
    end
  end

  def parse_plugin_vsn(vsn) when is_binary(vsn) do
    vsn
    |> String.split(".")
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, _} -> n
        :error -> 0
      end
    end)
  end

  @doc false
  def cursor_hooks_manifest do
    %{
      "version" => 1,
      "hooks" => %{
        "beforeShellExecution" => [
          %{
            "command" => repo_hook_command(".cursor/hooks/ck-validate-shell.sh"),
            "timeout" => 15,
            "failClosed" => false
          }
        ],
        "preToolUse" => [
          %{
            "command" => repo_hook_command(".cursor/hooks/ck-validate-write.sh"),
            "matcher" => "Write|StrReplace|Delete",
            "timeout" => 15,
            "failClosed" => false
          }
        ],
        "stop" => [
          %{
            "command" => repo_hook_command(".cursor/hooks/ck-stop.sh"),
            "timeout" => 10,
            "loop_limit" => 1,
            "failClosed" => false
          }
        ]
      }
    }
  end

  def cursor_plugin_hooks_manifest do
    %{
      "version" => 1,
      "hooks" => %{
        "beforeShellExecution" => [
          %{
            "command" => repo_hook_command(".cursor-plugin/hooks/ck-validate-shell.sh"),
            "timeout" => 15,
            "failClosed" => false
          }
        ],
        "preToolUse" => [
          %{
            "command" => repo_hook_command(".cursor-plugin/hooks/ck-validate-write.sh"),
            "matcher" => "Write|StrReplace|Delete",
            "timeout" => 15,
            "failClosed" => false
          }
        ],
        "stop" => [
          %{
            "command" => repo_hook_command(".cursor-plugin/hooks/ck-stop.sh"),
            "timeout" => 10,
            "loop_limit" => 1,
            "failClosed" => false
          }
        ]
      }
    }
  end

  @doc false
  def cursor_hook_scripts do
    [
      {"ck-validate-shell.sh", &cursor_validate_shell_hook_contents/0},
      {"ck-validate-write.sh", &cursor_validate_write_hook_contents/0},
      {"ck-stop.sh", &cursor_stop_hook_contents/0}
    ]
  end

  def hook_runtime_helpers do
    ~S"""
    set -u

    # Private, user-owned state for hooks that must remember something across
    # invocations (the last reported finding count, one-time notices).
    ck_state_dir() {
      ck_dir="${CONTROLKEEL_HOOK_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-}/.local/state}/controlkeel/hooks}"
      [ -n "${HOME:-}${CONTROLKEEL_HOOK_STATE_DIR:-}${XDG_STATE_HOME:-}" ] || return 1
      (umask 077 && mkdir -p "$ck_dir") 2>/dev/null || return 1
      if [ -L "$ck_dir" ] || [ ! -O "$ck_dir" ]; then return 1; fi
      printf '%s' "$ck_dir"
    }

    ck_write_state() {
      ck_tmp="$1.$$"
      (umask 077 && printf '%s' "$2" > "$ck_tmp") 2>/dev/null && mv -f "$ck_tmp" "$1" 2>/dev/null
      rm -f "$ck_tmp" 2>/dev/null
      return 0
    }

    # Succeeds only the first time <key> is seen, so a notice shows once.
    ck_first_time() {
      ck_once_dir=$(ck_state_dir) || return 1
      ck_once_key=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_')
      [ -e "$ck_once_dir/once-$ck_once_key" ] && return 1
      ck_write_state "$ck_once_dir/once-$ck_once_key" 1
      return 0
    }

    # Plain read-only commands skip validation: no shell metacharacters and a
    # first word that only reads. Anything else goes through ck_validate.
    ck_readonly_command() {
      case "$1" in
        *[\;\&\|\>\<\`\$\(\)]*|'') return 1 ;;
      esac
      set -f
      # shellcheck disable=SC2086
      set -- $1
      set +f
      case "$1" in
        ls|cat|head|tail|wc|pwd|grep|rg|which|type|file|stat|du|df|tree|sort|uniq|cut|diff|less|more) ;;
        find)
          case " $* " in
            *" -delete "*|*" -exec "*|*" -execdir "*|*" -ok "*|*" -okdir "*|*" -fprint"*) return 1 ;;
          esac
          ;;
        git)
          case "${2:-}" in
            status|diff|log|show|blame|rev-parse|ls-files|grep|shortlog|describe) ;;
            *) return 1 ;;
          esac
          ;;
        *) return 1 ;;
      esac
      return 0
    }

    ck_bin() {
      if [ -n "${CONTROLKEEL_BIN:-}" ] && [ -x "${CONTROLKEEL_BIN:-}" ]; then
        printf '%s\n' "$CONTROLKEEL_BIN"
        return 0
      fi

      repo_root="${CK_PROJECT_ROOT:-}"
      if [ -z "$repo_root" ] && command -v git >/dev/null 2>&1; then
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
      fi

      if [ -n "$repo_root" ] && [ -x "$repo_root/bin/controlkeel" ]; then
        printf '%s\n' "$repo_root/bin/controlkeel"
        return 0
      fi

      if command -v controlkeel >/dev/null 2>&1; then
        command -v controlkeel
        return 0
      fi

      return 1
    }

    ck_run() {
      seconds="${CONTROLKEEL_HOOK_TIMEOUT_SECONDS:-4}"
      bin=$(ck_bin 2>/dev/null || true)
      if [ -z "$bin" ]; then
        return 127
      fi

      if command -v perl >/dev/null 2>&1; then
        perl -e 'alarm shift; exec @ARGV' "$seconds" "$bin" "$@"
      elif command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$bin" "$@"
      else
        "$bin" "$@"
      fi
    }
    """
  end

  def cursor_validate_shell_hook_contents, do: shell_gate_hook_contents(:cursor)

  def cursor_validate_write_hook_contents do
    """
    #!/usr/bin/env sh
    #{hook_runtime_helpers()}

    input=$(cat)

    file_path=""
    if command -v jq >/dev/null 2>&1; then
      file_path=$(printf '%s' "$input" | jq -r '.input.path // empty')
    elif command -v python3 >/dev/null 2>&1; then
      file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input',{}).get('path',''))" 2>/dev/null)
    fi

    sensitive_pattern='\.env|credentials|secret|\.pem|\.key|id_rsa|token|password'
    if printf '%s' "$file_path" | grep -qiE "$sensitive_pattern"; then
      result=$(ck_run validate --content "Writing to $file_path" --kind config --json 2>/dev/null || true)
      if [ -n "$result" ]; then
        if printf '%s' "$result" | grep -q '"decision":"block"'; then
          printf '{"permission":"deny","user_message":"ControlKeel blocked write to sensitive file: %s"}\n' "$file_path"
          exit 0
        fi
      fi
      printf '{"permission":"allow","agent_message":"Writing to potentially sensitive file %s. Make sure this change is intended."}\n' "$file_path"
      exit 0
    fi

    printf '{"permission":"allow"}\n'
    exit 0
    """
  end

  def cursor_stop_hook_contents, do: stop_hook_contents(:cursor_followup)

  @doc false
  def windsurf_rule_contents do
    """
    # ControlKeel for Windsurf

    Use ControlKeel as the governance layer for risky repository changes.
    Prefer CK MCP tools for context, validation, findings, budgets, routing, and proof-aware completion.
    """
  end

  @doc false
  def windsurf_command_contents do
    """
    # ControlKeel review

    Use this command in Windsurf before exiting plan mode or finalizing risky work.

    1. Gather mission, workspace, and recent transcript context with `ck_context`.
    2. Validate with `ck_validate`.
    3. If a human plan review is needed, submit it through ControlKeel and wait for approval.
    """
  end

  @doc false
  def windsurf_workflow_contents do
    """
    # ControlKeel review workflow

    1. Stay in planning until ControlKeel approves the plan.
    2. Use ControlKeel MCP tools before risky edits.
    3. Surface blocked findings immediately.
    4. Finish with proof and risk status.
    """
  end

  @doc false
  def windsurf_hook_manifest do
    %{
      "version" => 1,
      "hooks" => [
        %{
          "event" => "ExitPlanMode",
          "type" => "command",
          "command" => repo_hook_command(".windsurf/hooks/controlkeel-review.sh"),
          "timeoutSec" => 345_600
        }
      ]
    }
  end

  @doc false
  def windsurf_workspace_hook_manifest do
    %{
      "version" => 1,
      "hooks" => [
        %{
          "event" => "ExitPlanMode",
          "type" => "command",
          "command" => repo_hook_command(".windsurf/hooks/controlkeel-review.sh"),
          "timeoutSec" => 345_600
        }
      ]
    }
  end

  def augment_rule_contents do
    """
    # ControlKeel governance for Augment

    - Prefer ControlKeel MCP tools before risky edits, shell commands, auth changes, or release work.
    - Use `/controlkeel-submit-plan` before leaving planning for non-trivial changes.
    - Use `/controlkeel-review` before declaring work complete.
    - Use `/controlkeel-annotate` for file-specific risk notes and `/controlkeel-last` to reopen the latest review.
    - Stay autonomous where possible, but respect ControlKeel review gates and blocked findings.
    """
  end

  def augment_review_command_contents do
    """
    ---
    description: Run a governed ControlKeel review for the current Augment task
    ---

    Read `.augment/rules/controlkeel.md`, use ControlKeel MCP tools, and summarize blocked findings, proof status, and follow-up work before completing the task.
    """
  end

  def augment_submit_plan_command_contents do
    """
    ---
    description: Submit the current Augment plan to ControlKeel and wait for approval
    ---

    1. Save the current plan to `.augment/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .augment/review-plan.md --submitted-by augment --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Do not implement until the review is approved.
    """
  end

  def augment_settings_snippet(project_root, opts) do
    %{
      "mcpServers" => mcp_payload(project_root, opts)["mcpServers"],
      "note" =>
        "Merge this into ~/.augment/settings.json if you want persistent ControlKeel MCP registration outside per-workspace --mcp-config usage."
    }
  end

  def continue_prompt_contents do
    """
    # ControlKeel Continue Prompt

    Start with `controlkeel-governance`, use CK MCP tools before risky work, and surface blocked findings immediately.
    Keep proofs and budget state current before marking a task complete.
    """
  end

  def continue_plan_prompt_contents do
    """
    # ControlKeel Continue Plan Mode

    Stay in plan mode until ControlKeel has reviewed and approved the plan. Use MCP tools for context gathering, but do not switch into implementation until approval returns.
    """
  end

  def continue_review_prompt_contents do
    """
    # ControlKeel Continue Review

    Before finalizing, summarize:
    - unresolved findings
    - proof status
    - budget or routing concerns
    - any human review follow-up
    """
  end

  def continue_headless_prompt_contents do
    """
    # ControlKeel Continue Headless

    In headless runs, prefer structured CLI calls:
    - `controlkeel review plan submit --json`
    - `controlkeel review plan respond <id> --decision approved --json` (after inline approval)
    - `controlkeel findings --format json`
    """
  end

  def continue_command_contents do
    """
    name: controlkeel-review
    description: Review the current task through ControlKeel validation, findings, and proof state.
    prompt: |
      Read AGENTS.md, run CK context/validation, and summarize blocked findings and proof state before completion.
    """
  end

  def continue_submit_plan_command_contents do
    """
    name: controlkeel-submit-plan
    description: Submit the current plan to ControlKeel and wait for review.
    prompt: |
      Save the plan to `.continue/review-plan.md`, run `controlkeel review plan submit --body-file .continue/review-plan.md --submitted-by continue --json`. Read the returned review.id and browser_url. Present the plan summary to the user and ask for approval in this conversation. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    """
  end

  def letta_mcp_helper_contents(project_root, opts) do
    command = mcp_command(project_root, opts)
    args = Enum.map_join(mcp_args(project_root, opts), " ", &shell_escape/1)

    """
    #!/usr/bin/env sh
    set -eu

    exec #{shell_escape(command)} #{args} "$@"
    """
  end

  def letta_readme_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Letta Code + ControlKeel

    This bundle prepares the real Letta-native surfaces ControlKeel can support today:

    - project skills in `.agents/skills`
    - checked-in hook settings in `.letta/settings.json`
    - repo-local MCP registration helper in `.letta/controlkeel-mcp.sh`
    - portable MCP reference in `.mcp.json`

    ## Skills

    Letta's primary project skill path is `.agents/skills`, with legacy `.skills` compatibility and optional `--skills` / `--skill-sources` overrides.

    ## Hooks

    - `.letta/settings.json` is the shared project settings file
    - `.letta/settings.local.json` is for personal/local overrides and should stay untracked
    - `.letta/settings.local.example.json` is a starter local permissions file

    ## MCP

    Add the local ControlKeel stdio server from inside the repo:

    ```text
    /mcp add --transport stdio controlkeel ./.letta/controlkeel-mcp.sh
    ```

    If you want hosted MCP instead, point Letta at the CK HTTP endpoint:

    ```text
    /mcp add --transport http controlkeel-hosted https://your-controlkeel.example/mcp
    ```

    ## Headless

    Letta's headless path is useful for CI or outer-loop automation:

    ```bash
    letta -p "Review the current repo with ControlKeel" --output-format json
    letta -p --output-format stream-json --input-format stream-json
    ```

    ## Remote / listener

    Letta's remote/listener surface is `letta server`. Use that when you want a long-lived remote agent service rather than a local interactive session.

    ## Project root

    `#{project_root}`
    """
  end

  def shell_escape(value) do
    escaped = String.replace(value, "'", "'\"'\"'")
    "'#{escaped}'"
  end

  def continue_mcp_server_contents(project_root, opts) do
    %{
      "name" => "controlkeel",
      "transport" => "stdio",
      "command" => mcp_command(project_root, opts),
      "args" => mcp_args(project_root, opts)
    }
    |> UtilsYaml.document()
  end

  def codex_agent_contents(project_root, skills, opts) do
    _project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    name = "controlkeel-operator"
    description = "Operate inside a ControlKeel-governed project with CK skills and MCP tools."
    nickname_candidates = ["Atlas", "Delta", "Echo"]
    model = "o4-mini"
    model_reasoning_effort = "medium"

    developer_instructions = "Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached` after upgrading. Start with the `controlkeel-governance` skill, then add domain-specific skills as needed."

    [skills]
    preload = [#{Enum.map_join(skills, ", ", &~s("#{&1.name}"))}]
    """
  end

  @doc false
  def codex_agent_specs(project_root, skills, opts) do
    [
      {"controlkeel-operator.toml", codex_agent_contents(project_root, skills, opts)},
      {"controlkeel-reviewer.toml", codex_reviewer_agent_contents()},
      {"controlkeel-docs-researcher.toml", codex_docs_researcher_agent_contents()}
    ]
  end

  def codex_reviewer_agent_contents do
    """
    name = "controlkeel-reviewer"
    description = "Review-focused Codex agent for correctness, security, regressions, and missing tests in ControlKeel-governed work."
    nickname_candidates = ["Atlas Review", "Delta Review", "Echo Review"]
    model = "o4-mini"
    model_reasoning_effort = "high"
    sandbox_mode = "read-only"

    developer_instructions = "Stay in review mode. Prioritize correctness, security, behavioral regressions, and missing validation coverage. Lead with concrete findings, cite evidence, and avoid style-only feedback unless it hides a real bug. Use ControlKeel governance context and surface blocked findings clearly."
    """
  end

  def codex_docs_researcher_agent_contents do
    """
    name = "controlkeel-docs-researcher"
    description = "Documentation-focused Codex agent for verifying APIs, config surfaces, and host behavior before CK integration changes land."
    nickname_candidates = ["Atlas Docs", "Delta Docs", "Echo Docs"]
    model = "o4-mini"
    model_reasoning_effort = "medium"
    sandbox_mode = "read-only"

    developer_instructions = "Use documentation and config evidence to confirm APIs, host behavior, and integration assumptions before changes land. Return concise conclusions with specific references, and do not edit application code."
    """
  end

  def claude_agent_contents(skills) do
    """
    ---
    name: controlkeel-operator
    description: Use ControlKeel governance, findings, proofs, budgets, and benchmarks inside this project.
    color: "#06b6d4"
    effort: high
    memory: project
    initialPrompt: /controlkeel-governance
    tools:
      "*": true
    mcpServers: ["controlkeel"]
    skills:
    #{Enum.map_join(skills, "\n", &"  - #{&1.name}")}
    ---

    # ControlKeel Operator

    You are the specialized operator for ControlKeel-governed work.

    Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached` after upgrading.
    Always begin with the `controlkeel-governance` skill and then load domain-specific skills as needed.
    Surface findings clearly, respect blocks, and use CK proof, benchmark, and budget tooling before declaring work complete.
    """
  end

  @doc false
  def claude_plugin_agent_contents(skills) do
    """
    ---
    name: controlkeel-operator
    description: Use ControlKeel governance, findings, proofs, budgets, and benchmarks inside this project.
    color: "#06b6d4"
    effort: high
    memory: project
    initialPrompt: /controlkeel-governance
    tools:
      "*": true
    skills:
    #{Enum.map_join(skills, "\n", &"  - #{&1.name}")}
    ---

    # ControlKeel Operator

    You are the specialized operator for ControlKeel-governed work.

    Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached` after upgrading.
    Always begin with the `controlkeel-governance` skill and then load domain-specific skills as needed.
    Surface findings clearly, respect blocks, and use CK proof, benchmark, and budget tooling before declaring work complete.
    """
  end

  def copilot_agent_contents(skills) do
    """
    ---
    description: Operate inside a ControlKeel-governed repository and use CK skills and MCP tools proactively.
    tools:
      "*": true
    ---

    # ControlKeel Operator

    Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached` after upgrading.
    Start by loading the `controlkeel-governance` skill. Use these supporting skills when relevant:

    #{Enum.map_join(skills, "\n", &"- `#{&1.name}` — #{&1.description}")}

    Prefer CK MCP tools for validation, routing, findings, budgets, proofs, and benchmark control.
    """
  end

  def augment_agent_contents(skills) do
    """
    ---
    name: controlkeel-operator
    description: Operate inside a ControlKeel-governed repository and use CK tools proactively.
    color: "#06b6d4"
    tools:
      "*": true
    ---

    # ControlKeel Operator

    Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached` after upgrading.
    Start with the `controlkeel-governance` skill. Use these supporting skills when relevant:

    #{Enum.map_join(skills, "\n", &"- `#{&1.name}` — #{&1.description}")}

    Prefer CK MCP tools for plan review, validation, findings, budgets, routing, and proof state.
    Stay autonomous, but do not bypass explicit ControlKeel review gates.
    """
  end

  @doc false
  def instructions_only_contents(target, _project_root, opts) do
    project_root_hint =
      if portable_project_root?(opts) do
        "this portable ControlKeel bundle directory (`#{Distribution.portable_project_root()}`)"
      else
        "this repository (your IDE workspace / `CK_PROJECT_ROOT`)"
      end

    """
    # ControlKeel Companion Instructions

    This project is governed by ControlKeel. Prefer the ControlKeel MCP server for validation, findings, budgets, proof context, workspace snapshots, transcript state, and routing.

    Project root: #{project_root_hint}
    Target: `#{target}`
    Primary CK loop: `#{ControlKeel.CLI.SetupAdvisor.core_loop()}`

    Required workflow:
    1. Call `ck_context` at the start of a task for mission, workspace, transcript, and resume context.
    2. Call `ck_validate` before writing code, config, shell, or deploy content.
    3. Submit plans or approval packets with `ck_review_submit` and check `ck_review_status` before execution.
    4. Record any human-review issue with `ck_finding`.
    5. Check `ck_budget` before expensive model or multi-agent work, and keep `ck_context` compact unless full raw context is needed.
    6. Before AFK or delegated implementation, split large work into human-approved vertical slices with explicit dependencies; prefer durable behavior-first issues, stable deep-module interfaces, and branch-level automated review plus human QA before merge.
    7. Use `ck_route`, `ck_skill_list`, and `ck_skill_load` to delegate or activate specialized CK workflows.

    Install ControlKeel:
    #{Enum.map_join(Distribution.install_channels(), "\n", fn channel -> "- #{channel.label}: `#{channel.command}`" end)}

    ControlKeel auto-bootstraps project binding on first use. Provider access resolves through agent bridge, CK-owned provider profiles, local Ollama, then heuristic fallback.
    """
  end

  def same_path?(left, right) do
    Path.expand(left) == Path.expand(right)
  end

  # ── OpenCode native helpers ────────────────────────────────────────────────

  @doc false
  def opencode_plugin_contents do
    ~S"""
    import type { Plugin } from "@opencode-ai/plugin"
    import { tool } from "@opencode-ai/plugin"

    /**
     * ControlKeel Review Bridge for OpenCode
     *
     * Host-specific adapter behavior:
     * - injects a submit_plan review tool for planning agents
     * - suppresses plan_exit in favor of ControlKeel browser review
     * - keeps the review tool primary-agent only by default
     * - routes plan submission and wait decisions through the CK CLI
     */
    export const ControlKeelGovernance: Plugin = async ({ project, client, $, directory }) => {
      const extractJsonCandidates = (output: string) => {
        const trimmed = output.trim()
        if (!trimmed) {
          return []
        }

        const lines = trimmed
          .split(/\r?\n/)
          .map((line) => line.trimEnd())
          .filter((line) => line.trim().length > 0)

        const candidates: string[] = []
        const seen = new Set<string>()

        const pushCandidate = (candidate: string) => {
          const normalized = candidate.trim()
          if (!normalized || seen.has(normalized)) {
            return
          }

          seen.add(normalized)
          candidates.push(normalized)
        }

        pushCandidate(trimmed)

        for (let i = 0; i < lines.length; i += 1) {
          const line = lines[i].trimStart()
          if (line.startsWith("{") || line.startsWith("[")) {
            pushCandidate(line)
            pushCandidate(lines.slice(i).join("\n"))
          }
        }

        return candidates
      }

      const parseJson = (output: string) => {
        const trimmed = output.trim()
        if (!trimmed) {
          throw new Error("ControlKeel returned empty output")
        }

        try {
          return JSON.parse(trimmed)
        } catch (_error) {
          for (const candidate of extractJsonCandidates(trimmed)) {
            try {
              return JSON.parse(candidate)
            } catch (_fallbackError) {
            }
          }

          throw new Error(`ControlKeel returned invalid JSON: ${output}`)
        }
      }

      // CLI commands emit a `{command, data, status, version}` envelope; unwrap it so
      // callers can read `review.id`, `session_id`, `browser_url` at the top level.
      // Older flat payloads pass through unchanged.
      const parseCliJson = (output: string) => {
        const payload = parseJson(output)

        if (
          payload != null &&
          typeof payload === "object" &&
          !Array.isArray(payload) &&
          payload.data != null &&
          typeof payload.data === "object"
        ) {
          return payload.data
        }

        return payload
      }

      const toText = async (output: unknown) => {
        if (typeof output === "string") {
          return output
        }

        if (output instanceof Uint8Array) {
          return new TextDecoder().decode(output)
        }

        if (output instanceof ArrayBuffer) {
          return new TextDecoder().decode(new Uint8Array(output))
        }

        if (output == null) {
          return ""
        }

        if (typeof output === "object") {
          if (typeof (output as { text?: unknown }).text === "function") {
            try {
              const direct = await (output as { text: () => Promise<string> }).text()
              if (typeof direct === "string") {
                return direct
              }
            } catch (_error) {
            }
          }

          const stdout = (output as { stdout?: unknown }).stdout
          if (typeof stdout === "string") {
            return stdout
          }

          if (stdout instanceof Uint8Array) {
            return new TextDecoder().decode(stdout)
          }

          if (stdout instanceof ArrayBuffer) {
            return new TextDecoder().decode(new Uint8Array(stdout))
          }

          if (stdout && typeof (stdout as { text?: unknown }).text === "function") {
            try {
              const streamed = await (stdout as { text: () => Promise<string> }).text()
              if (typeof streamed === "string") {
                return streamed
              }
            } catch (_error) {
            }
          }
        }

        return String(output)
      }

      const parseVersion = (output: string) => {
        const match = output.match(/(\d+)\.(\d+)\.(\d+)/)
        if (!match) {
          return null
        }

        return {
          major: Number(match[1]),
          minor: Number(match[2]),
          patch: Number(match[3]),
        }
      }

      const versionAtLeast = (
        current: { major: number; minor: number; patch: number },
        required: { major: number; minor: number; patch: number }
      ) => {
        if (current.major !== required.major) {
          return current.major > required.major
        }

        if (current.minor !== required.minor) {
          return current.minor > required.minor
        }

        return current.patch >= required.patch
      }

      const ensurePlanSubmitSupport = async () => {
        let versionOutput = ""

        try {
          const versionProc = Bun.spawn(["controlkeel", "version"], {
            stdout: "pipe",
            stderr: "pipe",
          })
          versionOutput = await new Response(versionProc.stdout).text()
          const versionExit = await versionProc.exited
          if (versionExit !== 0) {
            throw new Error(`controlkeel version exited with code ${versionExit}`)
          }
        } catch (error) {
          throw new Error(
            "Failed to run `controlkeel version`. Install ControlKeel >= 0.1.26 and ensure `controlkeel` is on PATH."
          )
        }

        const parsed = parseVersion(versionOutput)
        const required = { major: 0, minor: 1, patch: 26 }

        if (!parsed || !versionAtLeast(parsed, required)) {
          throw new Error(
            `ControlKeel CLI ${versionOutput.trim() || "unknown"} is too old for plan-review submit. Install >= 0.1.26.`
          )
        }
      }

      const normalizeReviewId = (value: string | number | null | undefined, label: string) => {
        if (value == null || value === "") return null

        if (typeof value === "number") {
          if (!Number.isFinite(value) || !Number.isInteger(value) || value <= 0) {
            throw new Error(`${label} must be a positive finite integer. Omit it to let ControlKeel infer scope from the bound project.`)
          }

          return String(value)
        }

        const trimmed = String(value).trim()
        if (/^[1-9]\d*$/.test(trimmed)) return trimmed

        throw new Error(`${label} must be a positive integer string. Omit it to let ControlKeel infer scope from the bound project.`)
      }

      const resolveReviewScope = async (
        explicitTaskId?: string | number | null,
        explicitSessionId?: string | number | null
      ) => {
        const normalizedExplicitTaskId = normalizeReviewId(explicitTaskId, "task_id")
        const normalizedExplicitSessionId = normalizeReviewId(explicitSessionId, "session_id")

        if (normalizedExplicitTaskId || normalizedExplicitSessionId) {
          return {
            taskId: normalizedExplicitTaskId,
            sessionId: normalizedExplicitSessionId,
            source: "explicit",
          }
        }

        const envTaskId = normalizeReviewId(process.env.CONTROLKEEL_TASK_ID, "CONTROLKEEL_TASK_ID")
        const envSessionId = normalizeReviewId(process.env.CONTROLKEEL_SESSION_ID, "CONTROLKEEL_SESSION_ID")

        if (envTaskId || envSessionId) {
          return {
            taskId: envTaskId,
            sessionId: envSessionId,
            source: "env",
          }
        }

        const contextEnv = process.env.LOGGER_LEVEL
          ? process.env
          : { ...process.env, LOGGER_LEVEL: "warning" }

        const contextProc = Bun.spawn(["controlkeel", "context", "--json", "--project-root", directory], {
          stdout: "pipe",
          stderr: "pipe",
          env: contextEnv,
        })
        const contextOut = await new Response(contextProc.stdout).text()
        const contextErr = await new Response(contextProc.stderr).text()
        const contextExit = await contextProc.exited

        if (contextExit !== 0) {
          throw new Error(
            `controlkeel context --json failed with exit code ${contextExit}${contextErr.trim() ? `: ${contextErr.trim()}` : ""}`
          )
        }

        const contextPayload = parseCliJson([contextOut, contextErr].filter(Boolean).join("\n"))
        const contextTaskId = contextPayload?.current_task?.id
        const contextSessionId = contextPayload?.session_id

        if (contextTaskId || contextSessionId) {
          return {
            taskId: contextTaskId != null ? String(contextTaskId) : null,
            sessionId: contextSessionId != null ? String(contextSessionId) : null,
            source: "context",
          }
        }

        try {
          const bindingPayload = parseJson(await Bun.file(`${directory}/controlkeel/project.json`).text())
          const bindingSessionId = bindingPayload?.session_id

          if (bindingSessionId) {
            return {
              taskId: null,
              sessionId: String(bindingSessionId),
              source: "binding",
            }
          }
        } catch (_error) {
        }

        throw new Error(
          "ControlKeel could not infer review scope. Set CONTROLKEEL_TASK_ID or CONTROLKEEL_SESSION_ID, or pass task_id/session_id to submit_plan."
        )
      }

      const submitPlan = async (
        body: string,
        submittedBy: string,
        title?: string,
        waitTimeoutSeconds?: number,
        taskId?: string | number | null,
        sessionId?: string | number | null
      ) => {
        await ensurePlanSubmitSupport()

        const reviewScope = await resolveReviewScope(taskId, sessionId)
        const waitTimeout = Number(waitTimeoutSeconds ?? process.env.CONTROLKEEL_REVIEW_WAIT_TIMEOUT ?? 30)
        const waitTimeoutSecondsSafe = Number.isFinite(waitTimeout) && waitTimeout > 0 ? waitTimeout : 30

        // Write body to temp file to avoid stdin piping issues
        const tmpFile = `${directory}/.opencode/review-plan-${Date.now()}.md`
        await Bun.write(tmpFile, body)

        try {
          const submitArgs = ["controlkeel", "review", "plan", "submit", "--body-file", tmpFile, "--submitted-by", submittedBy, "--json"]
          if (title) submitArgs.push("--title", title)
          if (reviewScope.taskId) submitArgs.push("--task-id", reviewScope.taskId)
          else if (reviewScope.sessionId) submitArgs.push("--session-id", reviewScope.sessionId)

          const submitEnv = process.env.LOGGER_LEVEL
            ? process.env
            : { ...process.env, LOGGER_LEVEL: "warning" }

          const submitProc = Bun.spawn(submitArgs, {
            stdout: "pipe",
            stderr: "pipe",
            env: submitEnv,
          })
          const submitOut = await new Response(submitProc.stdout).text()
          const submitErr = await new Response(submitProc.stderr).text()
          const submitExit = await submitProc.exited

          if (submitExit !== 0) {
            throw new Error(
              `controlkeel review plan submit failed with exit code ${submitExit}${submitErr.trim() ? `: ${submitErr.trim()}` : ""}`
            )
          }

          const submitPayload = parseCliJson([submitOut, submitErr].filter(Boolean).join("\n"))

          if (typeof submitPayload?.error === "string" && submitPayload.error.includes("session_id")) {
            throw new Error(
              "ControlKeel plan submission requires review context. Set CONTROLKEEL_TASK_ID (preferred) or CONTROLKEEL_SESSION_ID, or pass --task-id/--session-id manually."
            )
          }

          const reviewId = submitPayload?.review?.id
          if (!reviewId) {
            throw new Error("ControlKeel did not return a review id")
          }

          const openEnv = process.env.LOGGER_LEVEL
            ? process.env
            : { ...process.env, LOGGER_LEVEL: "warning" }

          let openPayload = null

          try {
            const openProc = Bun.spawn(["controlkeel", "review", "plan", "open", "--id", String(reviewId), "--json"], {
              stdout: "pipe",
              stderr: "pipe",
              env: openEnv,
            })
            const openOut = await new Response(openProc.stdout).text()
            const openErr = await new Response(openProc.stderr).text()
            const openExit = await openProc.exited

            if (openExit === 0) {
              openPayload = parseCliJson([openOut, openErr].filter(Boolean).join("\n"))
            } else {
              openPayload = {
                error: `controlkeel review plan open failed with exit code ${openExit}${openErr.trim() ? `: ${openErr.trim()}` : ""}`,
              }
            }
          } catch (error) {
            openPayload = { error: error instanceof Error ? error.message : String(error) }
          }

          const browserUrl =
            openPayload?.browser_url ??
            submitPayload?.browser_url ??
            submitPayload?.url ??
            submitPayload?.review?.browser_url ??
            null

          const buildPlanResult = (overrides = {}) => ({
            reviewId,
            browserUrl: overrides.browserUrl ?? browserUrl,
            status: overrides.status ?? submitPayload?.review?.status ?? "pending",
            feedbackNotes:
              overrides.feedbackNotes ?? submitPayload?.review?.feedback_notes ?? null,
            opened: overrides.opened ?? (openPayload?.opened === true),
            timedOut: overrides.timedOut ?? false,
            waitSkipped: overrides.waitSkipped ?? false,
            manualApprovalRequired: overrides.manualApprovalRequired ?? false,
            reason: overrides.reason ?? null,
            guidance: overrides.guidance ?? null,
          })

          // If the server auto-approved, skip the entire open/wait flow
          const autoApproved = submitPayload?.auto_approved === true
          const autoApproveReason = submitPayload?.auto_approve_reason ?? null

          if (autoApproved) {
            return buildPlanResult({
              status: "approved",
              waitSkipped: true,
              manualApprovalRequired: false,
              reason: "auto_approved",
              guidance: autoApproveReason
                ? `Plan auto-approved: ${autoApproveReason}`
                : "Plan was auto-approved by ControlKeel (low risk, no blocked findings, within policy).",
            })
          }

          const openError = typeof openPayload?.open_error === "string" ? openPayload.open_error.trim() : ""
          const openFailure = typeof openPayload?.error === "string" ? openPayload.error.trim() : ""
          const browserNotOpened = openPayload?.opened !== true
          const serverUnavailable = openPayload?.server_serving === false

          const remoteLocalhostMismatch =
            typeof browserUrl === "string" &&
            browserUrl.includes("localhost") &&
            openPayload?.remote === true

          // Default: always return inline approval guidance.
          const browserAvailable =
            browserUrl && !serverUnavailable && !openError && !openFailure && !remoteLocalhostMismatch && !browserNotOpened

          if (!browserAvailable) {
            return buildPlanResult({
              waitSkipped: true,
              manualApprovalRequired: true,
              reason:
                !browserUrl
                  ? "browser_url_unavailable"
                  : serverUnavailable
                    ? "review_server_unavailable"
                    : browserNotOpened
                      ? "browser_not_opened"
                      : "browser_unreachable",
              guidance:
                "Ask the user for explicit approval in this conversation. " +
                "Present the plan summary and ask: 'Do you approve this plan? (yes/no)'. " +
                "After the user says yes, record it with: `controlkeel review plan respond <review_id> --decision approved --feedback-notes \"User approved in chat\" --json` " +
                "or call `ck_review_feedback` with review_id=<review_id> decision=\"approved\".",
            })
          }

          // Browser is available. If the caller explicitly passed wait_timeout_seconds,
          // honor it (opt-in blocking). Otherwise, return immediately with inline guidance.
          if (waitTimeoutSeconds == null) {
            return buildPlanResult({
              waitSkipped: true,
              manualApprovalRequired: false,
              reason: "browser_available_inline_default",
              guidance:
                "Browser review is available at: " + browserUrl + "\n" +
                "You can: (a) ask the user to approve inline in this conversation, or (b) pass wait_timeout_seconds to block until the browser review is completed. " +
                "To record inline approval: `controlkeel review plan respond <review_id> --decision approved --feedback-notes \"User approved in chat\" --json`.",
            })
          }

          // Opt-in blocking: caller explicitly asked to wait for browser review.

          const waitEnv = process.env.LOGGER_LEVEL
            ? process.env
            : { ...process.env, LOGGER_LEVEL: "warning" }

          const waitProc = Bun.spawn(["controlkeel", "review", "plan", "wait", "--id", String(reviewId), "--timeout", String(waitTimeoutSecondsSafe), "--json"], {
            stdout: "pipe",
            stderr: "pipe",
            env: waitEnv,
          })
          const waitOut = await new Response(waitProc.stdout).text()
          const waitErr = await new Response(waitProc.stderr).text()
          const waitExit = await waitProc.exited
          const waitPayload = parseCliJson([waitOut, waitErr].filter(Boolean).join("\n"))
          const waitMessage = typeof waitPayload?.message === "string" ? waitPayload.message.toLowerCase() : ""
          const waitError = typeof waitPayload?.error === "string" ? waitPayload.error.toLowerCase() : ""
          const waitTimedOut = waitMessage.includes("timeout") || waitError.includes("timed out")
          const waitPending = waitPayload?.review?.status === "pending"

          if (waitExit !== 0) {
            if (waitTimedOut && waitPending) {
              return buildPlanResult({
                browserUrl: waitPayload?.browser_url ?? submitPayload?.browser_url,
                status: "pending",
                feedbackNotes: waitPayload?.review?.feedback_notes ?? null,
                timedOut: true,
                waitSkipped: false,
                manualApprovalRequired: true,
                reason: "review_timeout",
                guidance:
                  "Plan review is still pending after timeout. Show the `browser_url` to the user if reachable. If browser review is unavailable or the user explicitly approves in chat, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes \"User approved in chat after timeout/browser issue\" --json` (or `ck_review_feedback`) before proceeding.",
              })
            }

            throw new Error(
              `controlkeel review plan wait failed with exit code ${waitExit}${waitErr.trim() ? `: ${waitErr.trim()}` : ""}`
            )
          }

          return buildPlanResult({
            browserUrl: waitPayload?.browser_url ?? browserUrl,
            status: waitPayload?.review?.status,
            feedbackNotes: waitPayload?.review?.feedback_notes ?? null,
            waitSkipped: false,
            manualApprovalRequired: false,
          })
        } finally {
          // Clean up temp file
          try { await Bun.file(tmpFile).unlink?.() ?? (await $`rm -f ${tmpFile}`.quiet()) } catch {}
        }
      }

      return {
        "shell.env": async (input, output) => {
          output.env.CONTROLKEEL_PROJECT_ROOT = directory
          output.env.CONTROLKEEL_AGENT_ID = "opencode"

          if (input.sessionID) {
            output.env.CONTROLKEEL_THREAD_ID = input.sessionID
          }
        },

        config: async (config) => {
          const primaryTools = config.experimental?.primary_tools ?? []
          if (!primaryTools.includes("submit_plan")) {
            config.experimental = {
              ...config.experimental,
              primary_tools: [...primaryTools, "submit_plan"],
            }
          }
        },

        "tool.definition": async (input, output) => {
          if (input.toolID === "plan_exit") {
            output.description =
              "Do not call this tool. Use submit_plan so ControlKeel can collect approval in the browser review flow."
          }
        },

        "experimental.chat.system.transform": async (_input, output) => {
          output.system.push(
            "For multi-step, destructive, or deploy-related work, submit the plan with submit_plan and wait for ControlKeel approval. Small, low-risk edits can proceed directly."
          )
        },

        tool: {
          "submit_plan": tool({
            description:
              "Submit a plan to ControlKeel for browser review. The tool waits for approval before execution continues.",
            args: {
              plan: tool.schema.string().describe("Markdown plan body to submit for review."),
              title: tool.schema.string().optional(),
              wait_timeout_seconds: tool.schema.number().int().positive().optional(),
              task_id: tool.schema.number().int().positive().optional(),
              session_id: tool.schema.number().int().positive().optional(),
            },
            async execute(args) {
              const result = await submitPlan(
                args.plan,
                "opencode",
                args.title,
                args.wait_timeout_seconds,
                args.task_id,
                args.session_id
              )
              return JSON.stringify(result)
            },
          }),
        },
      }
    }
    """
  end

  @doc false
  def opencode_agent_contents(skills) do
    """
    ---
    name: controlkeel-operator
    description: Use ControlKeel governance, findings, proofs, budgets, and benchmarks inside this project.
    color: "#06b6d4"
    effort: high
    memory: project
    initialPrompt: /controlkeel-governance
    tools:
      "*": true
    skills:
    #{Enum.map_join(skills, "\n", &"  - #{&1.name}")}
    ---

    # ControlKeel Operator

    You are the specialized operator for ControlKeel-governed work.

    Call `controlkeel update --json` once at startup. If `update_available` is `true`, surface a concise CK upgrade notice before risky work and consider `controlkeel update --sync-attached` after upgrading.
    Always begin with the `controlkeel-governance` skill and then load domain-specific skills as needed.
    Surface findings clearly, respect blocks, and use CK proof, benchmark, and budget tooling before declaring work complete.
    """
  end

  @doc false
  def opencode_command_contents do
    """
    ---
    description: Run ControlKeel governance review on the current project
    agent: controlkeel-operator
    ---

    Review the current project for governance compliance. Run `ck_validate` to check
    for security findings, budget status, and proof readiness. Summarize the results
    and highlight any blockers that need attention before shipping.

    Focus on:
    1. Open findings by severity
    2. Budget remaining vs. spent
    3. Proof coverage for completed tasks
    4. Any policy violations that block release
    """
  end

  @doc false
  def opencode_submit_plan_command_contents do
    """
    ---
    description: Submit the current plan to ControlKeel for approval
    ---

    Save the current plan to a markdown file, then submit it through ControlKeel.

    Recommended flow:
    1. Save the plan to `.opencode/review-plan.md`
    2. Ensure `controlkeel version` reports `>= 0.1.26`
    3. Run `controlkeel review plan submit --body-file .opencode/review-plan.md --submitted-by opencode --task-id <task_id> --json` (or use `--session-id <session_id>`)
    4. Read the returned `review.id`, `browser_url`, and `auto_approved`
    5. If `auto_approved` is true, the plan was approved automatically (low risk, no blocked findings). Proceed.
    6. Otherwise, present the plan summary to the user and ask for approval in this conversation
    7. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json` (or `ck_review_feedback`)
    8. Do not execute until the review is approved

    Auto-approval: For low-risk work (small scope, no security concerns, within established patterns), the server may auto-approve. Check `auto_approved` in the response.

    Fallback when the `submit_plan` tool is stale in a long-running OpenCode session:
    - If the tool returns an error like `ControlKeel CLI [object Object] is too old`, run the CLI flow above directly.
    - Restart OpenCode after plugin updates so `.opencode/plugins/controlkeel-governance.ts` is reloaded.
    """
  end

  @doc false
  def opencode_package_manifest do
    %{
      "name" => "@aryaminus/controlkeel-opencode",
      "version" => app_version(),
      "type" => "module",
      "description" => "ControlKeel OpenCode adapter bundle",
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => %{
        "type" => "git",
        "url" => "git+https://github.com/aryaminus/controlkeel.git"
      },
      "bugs" => %{"url" => "https://github.com/aryaminus/controlkeel/issues"},
      "keywords" => ["controlkeel", "opencode", "plugin", "governance", "mcp"],
      "exports" => %{
        "." => "./index.js",
        "./plugin" => "./index.js"
      },
      "main" => "./index.js",
      "dependencies" => %{
        "@opencode-ai/plugin" => "1.3.13"
      },
      "files" => [".opencode", ".agents/skills", "AGENTS.md", "README.md", "index.js"],
      "publishConfig" => %{"access" => "public"},
      "license" => "Apache-2.0"
    }
  end

  @doc false
  def opencode_package_entry_contents do
    ~S"""
    import { tool } from "@opencode-ai/plugin"

    /**
     * Published OpenCode package entrypoint for ControlKeel.
     *
     * This mirrors the repo-local plugin in `.opencode/plugins/controlkeel-governance.ts`
     * but ships as plain JavaScript for npm-based installs.
     */
    export const ControlKeelGovernance = async ({ $, directory }) => {
      const extractJsonCandidates = (output) => {
        const trimmed = output.trim()
        if (!trimmed) {
          return []
        }

        const lines = trimmed
          .split(/\r?\n/)
          .map((line) => line.trimEnd())
          .filter((line) => line.trim().length > 0)

        const candidates = []
        const seen = new Set()

        const pushCandidate = (candidate) => {
          const normalized = candidate.trim()
          if (!normalized || seen.has(normalized)) {
            return
          }

          seen.add(normalized)
          candidates.push(normalized)
        }

        pushCandidate(trimmed)

        for (let i = 0; i < lines.length; i += 1) {
          const line = lines[i].trimStart()
          if (line.startsWith("{") || line.startsWith("[")) {
            pushCandidate(line)
            pushCandidate(lines.slice(i).join("\n"))
          }
        }

        return candidates
      }

      const parseJson = (output) => {
        const trimmed = output.trim()
        if (!trimmed) {
          throw new Error("ControlKeel returned empty output")
        }

        try {
          return JSON.parse(trimmed)
        } catch (_error) {
          for (const candidate of extractJsonCandidates(trimmed)) {
            try {
              return JSON.parse(candidate)
            } catch (_fallbackError) {
            }
          }

          throw new Error(`ControlKeel returned invalid JSON: ${output}`)
        }
      }

      // CLI commands emit a `{command, data, status, version}` envelope; unwrap it so
      // callers can read `review.id`, `session_id`, `browser_url` at the top level.
      // Older flat payloads pass through unchanged.
      const parseCliJson = (output) => {
        const payload = parseJson(output)

        if (
          payload != null &&
          typeof payload === "object" &&
          !Array.isArray(payload) &&
          payload.data != null &&
          typeof payload.data === "object"
        ) {
          return payload.data
        }

        return payload
      }

      const toText = async (output) => {
        if (typeof output === "string") {
          return output
        }

        if (output instanceof Uint8Array) {
          return new TextDecoder().decode(output)
        }

        if (output instanceof ArrayBuffer) {
          return new TextDecoder().decode(new Uint8Array(output))
        }

        if (output == null) {
          return ""
        }

        if (typeof output === "object") {
          if (typeof output.text === "function") {
            try {
              const direct = await output.text()
              if (typeof direct === "string") {
                return direct
              }
            } catch (_error) {
            }
          }

          const stdout = output.stdout
          if (typeof stdout === "string") {
            return stdout
          }

          if (stdout instanceof Uint8Array) {
            return new TextDecoder().decode(stdout)
          }

          if (stdout instanceof ArrayBuffer) {
            return new TextDecoder().decode(new Uint8Array(stdout))
          }

          if (stdout && typeof stdout.text === "function") {
            try {
              const streamed = await stdout.text()
              if (typeof streamed === "string") {
                return streamed
              }
            } catch (_error) {
            }
          }
        }

        return String(output)
      }

      const parseVersion = (output) => {
        const match = output.match(/(\d+)\.(\d+)\.(\d+)/)
        if (!match) {
          return null
        }

        return {
          major: Number(match[1]),
          minor: Number(match[2]),
          patch: Number(match[3]),
        }
      }

      const versionAtLeast = (current, required) => {
        if (current.major !== required.major) {
          return current.major > required.major
        }

        if (current.minor !== required.minor) {
          return current.minor > required.minor
        }

        return current.patch >= required.patch
      }

      const ensurePlanSubmitSupport = async () => {
        let versionOutput = ""

        try {
          const versionProc = Bun.spawn(["controlkeel", "version"], {
            stdout: "pipe",
            stderr: "pipe",
          })
          versionOutput = await new Response(versionProc.stdout).text()
          const versionExit = await versionProc.exited
          if (versionExit !== 0) {
            throw new Error(`controlkeel version exited with code ${versionExit}`)
          }
        } catch (_error) {
          throw new Error(
            "Failed to run `controlkeel version`. Install ControlKeel >= 0.1.26 and ensure `controlkeel` is on PATH."
          )
        }

        const parsed = parseVersion(versionOutput)
        const required = { major: 0, minor: 1, patch: 26 }

        if (!parsed || !versionAtLeast(parsed, required)) {
          throw new Error(
            `ControlKeel CLI ${versionOutput.trim() || "unknown"} is too old for plan-review submit. Install >= 0.1.26.`
          )
        }
      }

      const normalizeReviewId = (value, label) => {
        if (value == null || value === "") return null

        if (typeof value === "number") {
          if (!Number.isFinite(value) || !Number.isInteger(value) || value <= 0) {
            throw new Error(`${label} must be a positive finite integer. Omit it to let ControlKeel infer scope from the bound project.`)
          }

          return String(value)
        }

        const trimmed = String(value).trim()
        if (/^[1-9]\d*$/.test(trimmed)) return trimmed

        throw new Error(`${label} must be a positive integer string. Omit it to let ControlKeel infer scope from the bound project.`)
      }

      const resolveReviewScope = async (explicitTaskId, explicitSessionId) => {
        const normalizedExplicitTaskId = normalizeReviewId(explicitTaskId, "task_id")
        const normalizedExplicitSessionId = normalizeReviewId(explicitSessionId, "session_id")

        if (normalizedExplicitTaskId || normalizedExplicitSessionId) {
          return {
            taskId: normalizedExplicitTaskId,
            sessionId: normalizedExplicitSessionId,
            source: "explicit",
          }
        }

        const envTaskId = normalizeReviewId(process.env.CONTROLKEEL_TASK_ID, "CONTROLKEEL_TASK_ID")
        const envSessionId = normalizeReviewId(process.env.CONTROLKEEL_SESSION_ID, "CONTROLKEEL_SESSION_ID")

        if (envTaskId || envSessionId) {
          return {
            taskId: envTaskId,
            sessionId: envSessionId,
            source: "env",
          }
        }

        const contextEnv = process.env.LOGGER_LEVEL
          ? process.env
          : { ...process.env, LOGGER_LEVEL: "warning" }

        const contextProc = Bun.spawn(["controlkeel", "context", "--json", "--project-root", directory], {
          stdout: "pipe",
          stderr: "pipe",
          env: contextEnv,
        })
        const contextOut = await new Response(contextProc.stdout).text()
        const contextErr = await new Response(contextProc.stderr).text()
        const contextExit = await contextProc.exited

        if (contextExit !== 0) {
          throw new Error(
            `controlkeel context --json failed with exit code ${contextExit}${contextErr.trim() ? `: ${contextErr.trim()}` : ""}`
          )
        }

        const contextPayload = parseCliJson([contextOut, contextErr].filter(Boolean).join("\n"))
        const contextTaskId = contextPayload?.current_task?.id
        const contextSessionId = contextPayload?.session_id

        if (contextTaskId || contextSessionId) {
          return {
            taskId: contextTaskId != null ? String(contextTaskId) : null,
            sessionId: contextSessionId != null ? String(contextSessionId) : null,
            source: "context",
          }
        }

        try {
          const bindingPayload = parseJson(await Bun.file(`${directory}/controlkeel/project.json`).text())
          const bindingSessionId = bindingPayload?.session_id

          if (bindingSessionId) {
            return {
              taskId: null,
              sessionId: String(bindingSessionId),
              source: "binding",
            }
          }
        } catch (_error) {
        }

        throw new Error(
          "ControlKeel could not infer review scope. Set CONTROLKEEL_TASK_ID or CONTROLKEEL_SESSION_ID, or pass task_id/session_id to submit_plan."
        )
      }

      const submitPlan = async (body, submittedBy, title, waitTimeoutSeconds, taskId, sessionId) => {
        await ensurePlanSubmitSupport()

        const reviewScope = await resolveReviewScope(taskId, sessionId)
        const waitTimeout = Number(waitTimeoutSeconds ?? process.env.CONTROLKEEL_REVIEW_WAIT_TIMEOUT ?? 30)
        const waitTimeoutSecondsSafe = Number.isFinite(waitTimeout) && waitTimeout > 0 ? waitTimeout : 30

        // Write body to temp file to avoid stdin piping issues
        const tmpFile = `${directory}/.opencode/review-plan-${Date.now()}.md`
        await Bun.write(tmpFile, body)

        try {
          const submitArgs = ["controlkeel", "review", "plan", "submit", "--body-file", tmpFile, "--submitted-by", submittedBy, "--json"]
          if (title) submitArgs.push("--title", title)
          if (reviewScope.taskId) submitArgs.push("--task-id", reviewScope.taskId)
          else if (reviewScope.sessionId) submitArgs.push("--session-id", reviewScope.sessionId)

          const submitEnv = process.env.LOGGER_LEVEL
            ? process.env
            : { ...process.env, LOGGER_LEVEL: "warning" }

          const submitProc = Bun.spawn(submitArgs, {
            stdout: "pipe",
            stderr: "pipe",
            env: submitEnv,
          })
          const submitOut = await new Response(submitProc.stdout).text()
          const submitErr = await new Response(submitProc.stderr).text()
          const submitExit = await submitProc.exited

          if (submitExit !== 0) {
            throw new Error(
              `controlkeel review plan submit failed with exit code ${submitExit}${submitErr.trim() ? `: ${submitErr.trim()}` : ""}`
            )
          }

          const submitPayload = parseCliJson([submitOut, submitErr].filter(Boolean).join("\n"))

          if (typeof submitPayload?.error === "string" && submitPayload.error.includes("session_id")) {
            throw new Error(
              "ControlKeel plan submission requires review context. Set CONTROLKEEL_TASK_ID (preferred) or CONTROLKEEL_SESSION_ID, or pass --task-id/--session-id manually."
            )
          }

          const reviewId = submitPayload?.review?.id
          if (!reviewId) {
            throw new Error("ControlKeel did not return a review id")
          }

          const openEnv = process.env.LOGGER_LEVEL
            ? process.env
            : { ...process.env, LOGGER_LEVEL: "warning" }

          let openPayload = null

          try {
            const openProc = Bun.spawn(["controlkeel", "review", "plan", "open", "--id", String(reviewId), "--json"], {
              stdout: "pipe",
              stderr: "pipe",
              env: openEnv,
            })
            const openOut = await new Response(openProc.stdout).text()
            const openErr = await new Response(openProc.stderr).text()
            const openExit = await openProc.exited

            if (openExit === 0) {
              openPayload = parseCliJson([openOut, openErr].filter(Boolean).join("\n"))
            } else {
              openPayload = {
                error: `controlkeel review plan open failed with exit code ${openExit}${openErr.trim() ? `: ${openErr.trim()}` : ""}`,
              }
            }
          } catch (error) {
            openPayload = { error: error instanceof Error ? error.message : String(error) }
          }

          const browserUrl =
            openPayload?.browser_url ??
            submitPayload?.browser_url ??
            submitPayload?.url ??
            submitPayload?.review?.browser_url ??
            null

          const buildPlanResult = (overrides = {}) => ({
            reviewId,
            browserUrl: overrides.browserUrl ?? browserUrl,
            status: overrides.status ?? submitPayload?.review?.status ?? "pending",
            feedbackNotes:
              overrides.feedbackNotes ?? submitPayload?.review?.feedback_notes ?? null,
            opened: overrides.opened ?? (openPayload?.opened === true),
            timedOut: overrides.timedOut ?? false,
            waitSkipped: overrides.waitSkipped ?? false,
            manualApprovalRequired: overrides.manualApprovalRequired ?? false,
            reason: overrides.reason ?? null,
            guidance: overrides.guidance ?? null,
          })

          // If the server auto-approved, skip the entire open/wait flow
          const autoApproved = submitPayload?.auto_approved === true
          const autoApproveReason = submitPayload?.auto_approve_reason ?? null

          if (autoApproved) {
            return buildPlanResult({
              status: "approved",
              waitSkipped: true,
              manualApprovalRequired: false,
              reason: "auto_approved",
              guidance: autoApproveReason
                ? `Plan auto-approved: ${autoApproveReason}`
                : "Plan was auto-approved by ControlKeel (low risk, no blocked findings, within policy).",
            })
          }

          const openError = typeof openPayload?.open_error === "string" ? openPayload.open_error.trim() : ""
          const openFailure = typeof openPayload?.error === "string" ? openPayload.error.trim() : ""
          const browserNotOpened = openPayload?.opened !== true
          const serverUnavailable = openPayload?.server_serving === false

          const remoteLocalhostMismatch =
            typeof browserUrl === "string" &&
            browserUrl.includes("localhost") &&
            openPayload?.remote === true

          // Default: always return inline approval guidance.
          const browserAvailable =
            browserUrl && !serverUnavailable && !openError && !openFailure && !remoteLocalhostMismatch && !browserNotOpened

          if (!browserAvailable) {
            return buildPlanResult({
              waitSkipped: true,
              manualApprovalRequired: true,
              reason:
                !browserUrl
                  ? "browser_url_unavailable"
                  : serverUnavailable
                    ? "review_server_unavailable"
                    : browserNotOpened
                      ? "browser_not_opened"
                      : "browser_unreachable",
              guidance:
                "Ask the user for explicit approval in this conversation. " +
                "Present the plan summary and ask: 'Do you approve this plan? (yes/no)'. " +
                "After the user says yes, record it with: `controlkeel review plan respond <review_id> --decision approved --feedback-notes \"User approved in chat\" --json` " +
                "or call `ck_review_feedback` with review_id=<review_id> decision=\"approved\".",
            })
          }

          // Browser is available. If the caller explicitly passed wait_timeout_seconds,
          // honor it (opt-in blocking). Otherwise, return immediately with inline guidance.
          if (waitTimeoutSeconds == null) {
            return buildPlanResult({
              waitSkipped: true,
              manualApprovalRequired: false,
              reason: "browser_available_inline_default",
              guidance:
                "Browser review is available at: " + browserUrl + "\n" +
                "You can: (a) ask the user to approve inline in this conversation, or (b) pass wait_timeout_seconds to block until the browser review is completed. " +
                "To record inline approval: `controlkeel review plan respond <review_id> --decision approved --feedback-notes \"User approved in chat\" --json`.",
            })
          }

          // Opt-in blocking: caller explicitly asked to wait for browser review.

          const waitEnv = process.env.LOGGER_LEVEL
            ? process.env
            : { ...process.env, LOGGER_LEVEL: "warning" }

          const waitProc = Bun.spawn(["controlkeel", "review", "plan", "wait", "--id", String(reviewId), "--timeout", String(waitTimeoutSecondsSafe), "--json"], {
            stdout: "pipe",
            stderr: "pipe",
            env: waitEnv,
          })
          const waitOut = await new Response(waitProc.stdout).text()
          const waitErr = await new Response(waitProc.stderr).text()
          const waitExit = await waitProc.exited
          const waitPayload = parseCliJson([waitOut, waitErr].filter(Boolean).join("\n"))
          const waitMessage = typeof waitPayload?.message === "string" ? waitPayload.message.toLowerCase() : ""
          const waitError = typeof waitPayload?.error === "string" ? waitPayload.error.toLowerCase() : ""
          const waitTimedOut = waitMessage.includes("timeout") || waitError.includes("timed out")
          const waitPending = waitPayload?.review?.status === "pending"

          if (waitExit !== 0) {
            if (waitTimedOut && waitPending) {
              return buildPlanResult({
                browserUrl: waitPayload?.browser_url ?? submitPayload?.browser_url,
                status: "pending",
                feedbackNotes: waitPayload?.review?.feedback_notes ?? null,
                timedOut: true,
                waitSkipped: false,
                manualApprovalRequired: true,
                reason: "review_timeout",
                guidance:
                  "Plan review is still pending after timeout. Show the `browser_url` to the user if reachable. If browser review is unavailable or the user explicitly approves in chat, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes \"User approved in chat after timeout/browser issue\" --json` (or `ck_review_feedback`) before proceeding.",
              })
            }

            throw new Error(
              `controlkeel review plan wait failed with exit code ${waitExit}${waitErr.trim() ? `: ${waitErr.trim()}` : ""}`
            )
          }

          return buildPlanResult({
            browserUrl: waitPayload?.browser_url ?? browserUrl,
            status: waitPayload?.review?.status,
            feedbackNotes: waitPayload?.review?.feedback_notes ?? null,
            waitSkipped: false,
            manualApprovalRequired: false,
          })
        } finally {
          // Clean up temp file
          try { await Bun.file(tmpFile).unlink?.() ?? (await $`rm -f ${tmpFile}`.quiet()) } catch {}
        }
      }

      return {
        "shell.env": async (input, output) => {
          output.env.CONTROLKEEL_PROJECT_ROOT = directory
          output.env.CONTROLKEEL_AGENT_ID = "opencode"

          if (input.sessionID) {
            output.env.CONTROLKEEL_THREAD_ID = input.sessionID
          }
        },

        config: async (config) => {
          const primaryTools = config.experimental?.primary_tools ?? []
          if (!primaryTools.includes("submit_plan")) {
            config.experimental = {
              ...config.experimental,
              primary_tools: [...primaryTools, "submit_plan"],
            }
          }
        },

        "tool.definition": async (input, output) => {
          if (input.toolID === "plan_exit") {
            output.description =
              "Do not call this tool. Use submit_plan so ControlKeel can collect approval in the browser review flow."
          }
        },

        "experimental.chat.system.transform": async (_input, output) => {
          output.system.push(
            "For multi-step, destructive, or deploy-related work, submit the plan with submit_plan and wait for ControlKeel approval. Small, low-risk edits can proceed directly."
          )
        },

        tool: {
          "submit_plan": tool({
            description:
              "Submit a plan to ControlKeel for browser review. The tool waits for approval before execution continues.",
            args: {
              plan: tool.schema.string().describe("Markdown plan body to submit for review."),
              title: tool.schema.string().optional(),
              wait_timeout_seconds: tool.schema.number().int().positive().optional(),
              task_id: tool.schema.number().int().positive().optional(),
              session_id: tool.schema.number().int().positive().optional(),
            },
            async execute(args) {
              const result = await submitPlan(
                args.plan,
                "opencode",
                args.title,
                args.wait_timeout_seconds,
                args.task_id,
                args.session_id
              )
              return JSON.stringify(result)
            },
          }),
        },
      }
    }

    export default ControlKeelGovernance
    """
  end

  @doc false
  def opencode_package_readme_contents do
    """
    # ControlKeel OpenCode plugin

    Direct install:

    ```json
    {
      "plugin": ["@aryaminus/controlkeel-opencode"]
    }
    ```

    This npm package exposes the ControlKeel OpenCode governance plugin entrypoint.
    For the full repo-local experience with commands, agents, and MCP config, also run:

    ```bash
    controlkeel attach opencode
    ```

    The repo-local command bundle now includes:
    - `/controlkeel-review`
    - `/controlkeel-submit-plan`
    - `/controlkeel-annotate`
    - `/controlkeel-last`
    """
  end

  # ── Gemini CLI native helpers ──────────────────────────────────────────────

  def pi_extension_manifest(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    %{
      "name" => "controlkeel-pi-review",
      "version" => app_version(),
      "project_root" => project_root,
      "phase_model" => "file_plan_mode",
      "review_command" => "controlkeel-review",
      "submit_command" => "controlkeel-submit-plan",
      "browser_review" => true,
      "mcp" => %{
        "path" => ".pi/mcp.json",
        "hosted_template" => ".mcp.hosted.json"
      },
      "phase_config" => ".pi/controlkeel.json",
      "actions" => [
        %{
          "id" => "submit-plan-review",
          "label" => "Submit plan review",
          "command" =>
            "controlkeel review plan submit --body-file ${plan_file} --submitted-by pi --json"
        },
        %{
          "id" => "open-browser-review",
          "label" => "Open browser review",
          "command" => "controlkeel review plan open --id ${review_id} --json"
        },
        %{
          "id" => "wait-plan-review",
          "label" => "Wait for review decision",
          "command" => "controlkeel review plan wait --id ${review_id} --json"
        }
      ],
      "state" => %{
        "review_state_file" => ".pi/controlkeel-state.json",
        "progress_file" => "PLAN.md"
      }
    }
  end

  def pi_phase_manifest(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    %{
      "project_root" => project_root,
      "phases" => %{
        "planning" => %{
          "phase_model" => "file_plan_mode",
          "plan_file" => "PLAN.md",
          "allowed_tools" => [
            "read",
            "grep",
            "find",
            "ls",
            "write",
            "edit",
            "controlkeel-submit-plan"
          ],
          "write_scope" => ["PLAN.md"],
          "prompt" =>
            "Plan mode active. Only PLAN.md may be edited. Use controlkeel-submit-plan when the plan is ready."
        },
        "execution" => %{
          "phase_model" => "file_plan_mode",
          "progress_marker" => "[DONE:n]",
          "prompt" =>
            "Execution mode active after approval. Follow the approved plan in PLAN.md and mark completed steps with [DONE:n]."
        }
      }
    }
  end

  def pi_package_manifest do
    %{
      "name" => "@aryaminus/controlkeel-pi-extension",
      "version" => app_version(),
      "description" => "ControlKeel Pi adapter bundle",
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => %{
        "type" => "git",
        "url" => "git+https://github.com/aryaminus/controlkeel.git"
      },
      "bugs" => %{"url" => "https://github.com/aryaminus/controlkeel/issues"},
      "keywords" => ["controlkeel", "pi", "extension", "governance", "mcp"],
      "main" => "./pi-extension.json",
      "exports" => %{
        "." => "./pi-extension.json",
        "./manifest" => "./pi-extension.json"
      },
      "files" => [".pi", "pi-extension.json", "PI.md", "README.md"],
      "publishConfig" => %{"access" => "public"},
      "controlkeel" => %{
        "host" => "pi",
        "extension_manifest" => "pi-extension.json",
        "phase_config" => ".pi/controlkeel.json"
      },
      "license" => "Apache-2.0"
    }
  end

  def pi_package_readme_contents do
    """
    # ControlKeel Pi extension

    Direct install on Pi builds that support npm-backed extensions:

    ```bash
    pi install npm:@aryaminus/controlkeel-pi-extension
    ```

    Short form:

    ```bash
    pi -e npm:@aryaminus/controlkeel-pi-extension
    ```

    For the full repo-local planning, commands, and MCP configuration, also run:

    ```bash
    controlkeel attach pi
    ```

    The repo-local command bundle now includes:
    - `/controlkeel-review`
    - `/controlkeel-submit-plan`
    - `/controlkeel-annotate`
    - `/controlkeel-last`
    """
  end

  def pi_command_contents do
    """
    # /controlkeel-review

    Use this command when Pi has a plan, diff, or completion packet that needs approval before execution.

    Workflow:
    1. Save the current plan to a markdown file in the repo, for example `.pi/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .pi/review-plan.md --submitted-by pi --json`.
    3. Open the returned `browser_url` and wait for approval or denial notes.
    4. Poll `controlkeel review plan open --id <review_id> --json` or use `ck_review_status`.
    5. Do not continue execution until the review is approved.
    """
  end

  def pi_submit_plan_command_contents do
    """
    # /controlkeel-submit-plan

    Use this command from Pi planning mode after the current plan has been written to `PLAN.md`.

    Workflow:
    1. Confirm the plan file is up to date.
    2. Run `controlkeel review plan submit --body-file PLAN.md --submitted-by pi --json`.
    3. Read the returned `review.id` and `browser_url` (if available).
    4. Present the plan summary to the user and ask for approval in this conversation.
    5. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    6. Only switch into execution after approval.
    """
  end

  @doc false
  def codex_diff_review_command_contents do
    """
    # /controlkeel-diff-review

    Submit the current diff for ControlKeel browser review.

    Suggested flow:
    1. Save the diff to `.codex/review.diff`
    2. Run `controlkeel review plan submit --title "Diff review" --body-file .codex/review.diff --submitted-by codex-cli --json`
    3. Open or wait on the returned review id before finalizing
    """
  end

  @doc false
  def codex_completion_review_command_contents do
    """
    # /controlkeel-completion-review

    Submit the final completion summary for ControlKeel approval.

    Suggested flow:
    1. Save the completion notes to `.codex/completion.md`
    2. Run `controlkeel review plan submit --title "Completion review" --body-file .codex/completion.md --submitted-by codex-cli --json`
    3. Present the completion summary to the user and ask for approval in this conversation.
    4. After approval, record it with `controlkeel review plan respond <review_id> --decision approved --json`.
    5. Present the task as complete after approval is recorded.
    """
  end

  @doc false
  def codex_review_command_contents do
    """
    # /controlkeel-review

    Run a general ControlKeel review flow for the current task or working tree.

    Suggested flow:
    1. Save the current summary to `.codex/review.md`
    2. Run `controlkeel review plan submit --title "Codex review" --body-file .codex/review.md --submitted-by codex-cli --json`
    3. Present the summary to the user and ask for approval in this conversation.
    4. After approval, record it with `controlkeel review plan respond <review_id> --decision approved --json`.
    """
  end

  @doc false
  def codex_annotate_command_contents do
    """
    # /controlkeel-annotate <file>

    Use this when a single file needs focused human review notes.

    Suggested flow:
    1. Save the relevant notes to `.codex/annotate.md`
    2. Mention the target file path and risks at the top of the note
    3. Run `controlkeel review plan submit --title "File annotation review" --body-file .codex/annotate.md --submitted-by codex-cli --json`
    4. Wait for the response before applying risky edits
    """
  end

  @doc false
  def codex_last_command_contents do
    """
    # /controlkeel-last

    Re-open the most recent ControlKeel review decision you are tracking for this task.

    Suggested flow:
    1. Read the last stored review id from your working notes or command output
    2. Run `controlkeel review plan open --id <review_id> --json`
    3. If still pending, ask the user for approval in this conversation, then record it with `controlkeel review plan respond <review_id> --decision approved --json`.
    """
  end

  @doc false
  def host_review_command_contents(host_label, submitted_by) do
    """
    # /controlkeel-review

    Use this command in #{host_label} when the current work needs an explicit ControlKeel review pass.

    Suggested flow:
    1. Save the current summary or diff notes to a temporary markdown file in the repo.
    2. Run `controlkeel review plan submit --title "#{host_label} review" --body-file <path> --submitted-by #{submitted_by} --json`
    3. Open or wait on the returned review id before continuing risky work.
    """
  end

  @doc false
  def host_submit_plan_command_contents(host_label, submitted_by, suggested_path) do
    """
    # /controlkeel-submit-plan

    Use this command in #{host_label} when the current plan is ready for ControlKeel approval.

    Suggested flow:
    1. Save the current plan to `#{suggested_path}`.
    2. Run `controlkeel review plan submit --body-file #{suggested_path} --submitted-by #{submitted_by} --json`
    3. Read the returned `review.id`, `browser_url`, and `auto_approved`
    4. If `auto_approved` is true, the plan was approved automatically. Proceed.
    5. Otherwise, present the plan summary to the user and ask for approval in this conversation.
    6. After the user approves, record it with `controlkeel review plan respond <review_id> --decision approved --feedback-notes "User approved in chat" --json`.
    7. Do not begin implementation until approval is returned.
    """
  end

  @doc false
  def host_annotate_command_contents(host_label, submitted_by, suggested_path) do
    """
    # /controlkeel-annotate <file>

    Use this command in #{host_label} when a specific file needs focused human notes.

    Suggested flow:
    1. Save the file path, risks, and requested annotation context to `#{suggested_path}`.
    2. Run `controlkeel review plan submit --title "File annotation review" --body-file #{suggested_path} --submitted-by #{submitted_by} --json`
    3. Wait for the response before applying risky edits.
    """
  end

  @doc false
  def host_last_command_contents(host_label) do
    """
    # /controlkeel-last

    Use this command in #{host_label} to reopen the latest ControlKeel review you are tracking for the current task.

    Suggested flow:
    1. Read the last stored review id from your notes or prior command output.
    2. Run `controlkeel review plan open --id <review_id> --json`
    3. If the review is still pending, ask the user for approval in this conversation, then record it with `controlkeel review plan respond <review_id> --decision approved --json`.
    """
  end

  def copilot_plan_review_command_contents do
    """
    ---
    description: Submit a plan to ControlKeel browser review and wait for approval
    ---

    When you are in plan mode, send the plan through ControlKeel before executing:

    1. Save the plan to `.github/controlkeel-plan.md`
    2. Run `controlkeel review plan submit --body-file .github/controlkeel-plan.md --submitted-by copilot --json`
    3. Present the plan summary to the user and ask for approval in this conversation.
    4. After approval, record it with `controlkeel review plan respond <review_id> --decision approved --json`.
    5. Do not implement until the review is approved.
    """
  end

  # ── Kiro native helpers ────────────────────────────────────────────────────

  def kiro_steering_contents do
    """
    # ControlKeel Governance

    This project uses ControlKeel for governance, security, and compliance management.

    ## Rules

    1. **Always** run `controlkeel findings` after making significant code changes.
    2. **Never** approve or merge changes with unresolved critical or high findings.
    3. Reference specific policy rules when flagging issues in code reviews.
    4. Summarize budget impact when token/cost tracking is enabled.
    5. Check proof coverage before marking tasks as complete.

    ## Available Tools

    - `controlkeel findings` — List open governance findings
    - `controlkeel validate` — Run full governance validation
    - `controlkeel budget` — Check remaining budget and spend history
    - `controlkeel approve <finding-id>` — Approve a finding (requires operator confirmation)
    """
  end

  def kiro_command_contents do
    """
    # ControlKeel review

    Use this Kiro command to run a governed review pass:

    1. Read `.kiro/steering/controlkeel.md`.
    2. Use `ck_context` for task, workspace, and transcript context, then `ck_validate`.
    3. Surface blocked findings and proof status before completion.
    """
  end

  # ── Amp native helpers ─────────────────────────────────────────────────────

  def amp_skill_contents do
    """
    ---
    name: controlkeel-governance
    description: "Operate inside a ControlKeel-governed session. Use this before code edits, shell execution, delegation, deploy work, or any task that needs CK validation, findings, budget, proof, or routing context."
    license: Apache-2.0
    compatibility:
      - codex
      - claude-standalone
      - claude-plugin
      - copilot-plugin
      - github-repo
      - open-standard
    allowed-tools:
      - ck_validate
      - ck_context
      - ck_finding
      - ck_budget
      - ck_route
      - ck_skill_list
      - ck_skill_load
    metadata:
      author: controlkeel
      version: "2.0"
      category: governance
    ---

    # ControlKeel Governance For Amp

    Prefer this skill whenever you need to review a plan, annotate risky edits, or check the latest governed state.

    ## Core governance loop

    1. **Start**: Call `ck_context` with `session_id: 1` to load mission, risk, budget, proof, memory, and active findings.
    2. **Before mutations**: Call `ck_validate` before writing code, config, shell commands, or deploy artifacts.
    3. **Findings**: If you discover a problem, call `ck_finding` to persist it.
    4. **Budget**: Call `ck_budget` before expensive model calls or bulk operations; keep context compact until full raw context is necessary.
    5. **Planning shape**: Prefer human-approved vertical slices/tracer bullets with explicit dependencies before AFK implementation; issues should be behavior-first and every generated branch needs automated review plus human QA.
    6. **Routing**: Call `ck_route` before delegating sub-work to another agent.

    ## Commands

    - `/controlkeel-submit-plan` — submit plan before risky work
    - `/controlkeel-review` — review before completion
    - `/controlkeel-annotate` — file-specific risk notes
    - `/controlkeel-last` — reopen the most recent active review

    ## MCP expectations

    - `ck_context` for task, workspace, transcript, and resume context
    - `ck_review_submit`, `ck_review_status`, and `ck_review_feedback` for review transport
    - `ck_validate` and `ck_finding` for governance results
    """
  end

  def amp_plugin_contents do
    ~S"""
    /**
     * ControlKeel Governance Plugin for Amp Neo
     *
     * Uses the documented @ampcode/plugin API:
     * - tool.call hooks for policy/permission gating
     * - tool.result hooks for proof breadcrumbs
     * - custom tools for CK validation and plan submission
     * - command palette actions for review helpers
     *
     * CK does not adopt Amp's no-permission default as policy. High-risk shell
     * and file-mutating tool calls are checked with ControlKeel before execution.
     */
    import type { PluginAPI } from '@ampcode/plugin'

    type ValidationResult = {
      allowed?: boolean
      decision?: string
      findings?: Array<{ severity?: string; rule_id?: string; plain_message?: string }>
      summary?: string
    }

    const riskyShell = /\b(rm\s+-rf|sudo\b|chmod\s+777|chown\b|curl\b.*\|\s*(sh|bash)|wget\b.*\|\s*(sh|bash)|ssh\b|scp\b|rsync\b|docker\b|kubectl\b|terraform\b|flyctl\b|vercel\b|netlify\b|deploy\b|mix\s+ecto\.(drop|reset)|git\s+push\s+--force)\b/i

    export default function (amp: PluginAPI) {
      amp.on('session.start', async (event, ctx) => {
        const thread = event.thread?.id ?? ctx.thread?.id ?? 'unknown-thread'
        ctx.logger.log(`[CK] Amp Neo session started: ${thread}`)
      })

      amp.on('tool.call', async (event, ctx) => {
        const shell = amp.helpers.shellCommandFromToolCall(event)
        const files = amp.helpers.filesModifiedByToolCall(event)
        const fileList = files?.map((file) => amp.helpers.filePathFromURI(file)) ?? []

        const shellNeedsGate = Boolean(shell && riskyShell.test(shell.command))
        const fileNeedsGate = fileList.length > 0

        if (!shellNeedsGate && !fileNeedsGate) {
          return { action: 'allow' }
        }

        try {
          const content = shell?.command ?? `Files modified by ${event.tool}:\n${fileList.join('\n')}`
          const kind = shell ? 'shell' : 'text'
          const result = await runControlKeelValidation(ctx, content, kind)

          if (isBlocked(result)) {
            const message = formatBlockedMessage(result)
            await ctx.ui.notify(message)
            return { action: 'reject-and-continue', message }
          }

          ctx.logger.log(`[CK] allowed ${event.tool} after validation: ${result.summary ?? result.decision ?? 'ok'}`)
          return { action: 'allow' }
        } catch (error) {
          const message = `[CK] validation unavailable for ${event.tool}; allowing but recording warning: ${String(error)}`
          ctx.logger.log(message)
          await safeNotify(ctx, message)
          return { action: 'allow' }
        }
      })

      amp.on('tool.result', async (event, ctx) => {
        if (event.status === 'error') {
          ctx.logger.log(`[CK] tool failed: ${event.tool} ${event.error ?? ''}`)
        }
      })

      amp.on('agent.start', async (event) => {
        if (!/controlkeel|ck_|governance|review|approval/i.test(event.message)) {
          return
        }

        return {
          message: {
            content:
              '[CK] Governed reminder: call ck_context at task start, ck_validate before risky shell/file/deploy actions, and submit plans for human approval when policy requires it.',
            display: true,
          },
        }
      })

      amp.registerTool({
        name: 'ck_validate',
        description:
          'Run ControlKeel validation or status checks for the current Amp Neo thread. Use before risky code, config, shell, or deploy work.',
        inputSchema: {
          type: 'object',
          properties: {
            content: { type: 'string', description: 'Content, command, plan, or diff to validate' },
            kind: {
              type: 'string',
              enum: ['text', 'code', 'config', 'shell'],
              description: 'Artifact kind to route through CK policy',
            },
          },
          required: ['content'],
        },
        async execute(input, ctx) {
          const content = typeof input.content === 'string' ? input.content : ''
          const kind = typeof input.kind === 'string' ? input.kind : 'text'
          const result = await runControlKeelValidation(amp, content, kind)
          return JSON.stringify(result, null, 2)
        },
      })

      amp.registerTool({
        name: 'submit_plan',
        description: 'Submit a plan to ControlKeel for human review before risky implementation.',
        inputSchema: {
          type: 'object',
          properties: {
            plan: { type: 'string', description: 'Markdown plan body' },
            title: { type: 'string', description: 'Short review title' },
          },
          required: ['plan'],
        },
        async execute(input, ctx) {
          const plan = typeof input.plan === 'string' ? input.plan : ''
          const title = typeof input.title === 'string' ? input.title : 'Amp plan review'
          const planPath = '.amp/controlkeel-plan.md'
          await amp.$`mkdir -p .amp`
          await Bun.write(planPath, plan)
          const { stdout, stderr, exitCode } = await amp.$`controlkeel review plan submit --title ${title} --body-file ${planPath} --submitted-by amp --json`
          if (exitCode !== 0) return `ControlKeel plan submission failed: ${stderr}`
          return stdout
        },
      })

      amp.registerCommand(
        'controlkeel-review',
        {
          title: 'Review current project',
          category: 'ControlKeel',
          description: 'Show ControlKeel findings, proof, and budget status.',
        },
        async (ctx) => {
          const { stdout, stderr, exitCode } = await ctx.$`controlkeel status --json`
          await ctx.ui.notify(exitCode === 0 ? stdout : `ControlKeel status failed: ${stderr}`)
        },
      )

      amp.registerCommand(
        'controlkeel-last',
        {
          title: 'Open latest review',
          category: 'ControlKeel',
          description: 'Open the latest active ControlKeel review if available.',
        },
        async (ctx) => {
          const { stdout, stderr, exitCode } = await ctx.$`controlkeel review last --json`
          await ctx.ui.notify(exitCode === 0 ? stdout : `ControlKeel last review failed: ${stderr}`)
        },
      )
    }

    async function runControlKeelValidation(ctx: { $: PluginAPI['$'] }, content: string, kind: string): Promise<ValidationResult> {
      const { stdout, stderr, exitCode } = await ctx.$`controlkeel validate --kind ${kind} --content ${content} --json`
      if (exitCode !== 0) {
        throw new Error(stderr || stdout || `controlkeel validate exited ${exitCode}`)
      }
      return JSON.parse(stdout) as ValidationResult
    }

    function isBlocked(result: ValidationResult): boolean {
      return result.allowed === false || result.decision === 'block' || result.findings?.some((finding) => ['critical', 'high'].includes(String(finding.severity))) === true
    }

    function formatBlockedMessage(result: ValidationResult): string {
      const finding = result.findings?.find((item) => ['critical', 'high'].includes(String(item.severity)))
      if (finding) {
        return `[CK] blocked by ${finding.rule_id ?? 'policy'} (${finding.severity}): ${finding.plain_message ?? result.summary ?? 'validation failed'}`
      }
      return `[CK] blocked: ${result.summary ?? result.decision ?? 'validation failed'}`
    }

    async function safeNotify(ctx: { ui: { notify(message: string): Promise<void> } }, message: string): Promise<void> {
      try {
        await ctx.ui.notify(message)
      } catch {
        // UI is optional in remote/headless Amp contexts.
      }
    }
    """
  end

  def amp_command_contents do
    """
    # /controlkeel-review

    Use this command to run a full ControlKeel review, then summarize:
    - blocked findings
    - proof status
    - budget or routing concerns
    """
  end

  def amp_package_manifest do
    %{
      "name" => "@aryaminus/controlkeel-amp",
      "version" => app_version(),
      "private" => true,
      "description" => "ControlKeel Amp plugin bundle",
      "files" => [".amp"],
      "license" => "Apache-2.0"
    }
  end

  def antigravity_hook_scripts do
    [
      {"ck-validate-shell.sh", &shell_gate_hook_contents/0},
      {"ck-stop.sh", &stop_hook_contents/0}
    ]
  end

  # One named group so attach can replace ControlKeel's entries without
  # touching other groups in the workspace `hooks.json`.
  def antigravity_hooks_manifest do
    %{
      "controlkeel-governance" => %{
        "PreToolUse" => [
          %{
            "matcher" => "run_command",
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".agents/hooks/ck-validate-shell.sh"),
                "timeout" => 15
              }
            ]
          }
        ],
        "Stop" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => repo_hook_command(".agents/hooks/ck-stop.sh"),
                "timeout" => 10
              }
            ]
          }
        ]
      }
    }
  end

  def antigravity_mcp_config(project_root, opts) do
    %{
      "mcpServers" => %{
        "controlkeel" => mcp_payload(project_root, opts)
      }
    }
  end

  def antigravity_rules_contents do
    """
    # ControlKeel Governance Rules

    ## Pre-commit Governance
    - Always call `ck_validate` before shell commands, file writes, or config changes.
    - Run `ck_context` at session start to reacquire governance state.
    - Use `ck_review_submit` before broad mutations; wait for approval before proceeding.

    ## Security
    - Never commit secrets, API keys, or tokens.
    - Use `ck_finding` to record any security issues discovered during work.
    - Check `ck_budget` before expensive multi-phase or delegated work.

    ## Code Quality
    - Run `ck_git_diff` before committing to validate changes against policy.
    - Use `ck_git_commit` instead of raw git commit to validate commit messages.

    ## Review Gates
    - Submit plans via `ck_review_submit` for human approval before implementation.
    - Poll `ck_review_status` until approved/denied before proceeding.
    - Record outcomes with `ck_outcome_tracker` before ending the session.
    """
  end

  @doc false
  def app_version do
    ControlKeel.CLI.version()
  end
end
