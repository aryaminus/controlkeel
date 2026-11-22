defmodule ControlKeel.CLI.Help do
  @moduledoc false

  alias ControlKeel.Agent.Integration
  alias ControlKeel.CLI.Catalog
  alias ControlKeel.CLI.Output

  @topics [
    %{
      id: "overview",
      title: "What ControlKeel does",
      summary:
        "ControlKeel governs agent work with project bootstrapping, MCP access, findings, reviews, proofs, agent routing, and release-readiness checks.",
      keywords: ["overview", "start", "intro", "what", "capabilities", "does", "do"],
      phrases: ["what can controlkeel do", "what does controlkeel do", "what can ck do"],
      commands: [
        "controlkeel setup",
        "controlkeel attach codex-cli",
        "controlkeel status",
        "controlkeel findings",
        "controlkeel help getting-started"
      ],
      next_steps: [
        "Use `controlkeel setup` to bootstrap the governed project and see recommended attach and runtime-export paths.",
        "Use `controlkeel attach <agent>` to wire an agent to CK.",
        "Use `controlkeel status`, `findings`, and `proofs` to inspect governed state."
      ],
      related: ["getting-started", "attach", "review", "run"]
    },
    %{
      id: "getting-started",
      title: "Getting started",
      summary:
        "Use this when you are setting up CK for the first time or want the shortest path from install to governed agent work.",
      keywords: [
        "setup",
        "set",
        "up",
        "getting-started",
        "getting",
        "started",
        "first",
        "first-run",
        "begin",
        "new",
        "install"
      ],
      phrases: ["first run", "getting started", "set up", "setup ck"],
      commands: [
        "controlkeel setup",
        "controlkeel attach codex-cli",
        "controlkeel status",
        "controlkeel help attach"
      ],
      next_steps: [
        "Run `controlkeel setup` inside the project you want to govern.",
        "Attach a client such as `codex-cli`, `claude-code`, `cursor`, or `opencode`.",
        "Check the result with `controlkeel status` and `controlkeel findings`."
      ],
      related: ["attach", "providers", "mcp"]
    },
    %{
      id: "attach",
      title: "Attach and host setup",
      summary:
        "Attach registers CK with your coding host, writes host-specific companion files, and usually installs native bundles unless you pass `--mcp-only` or `--no-native`.",
      keywords: [
        "attach",
        "agent",
        "agents",
        "host",
        "setup",
        "connect",
        "codex",
        "claude",
        "cursor",
        "copilot",
        "opencode",
        "amp",
        "kiro",
        "windsurf",
        "goose",
        "continue"
      ],
      phrases: ["connect codex", "attach codex", "attach agent", "set up codex"],
      commands: [
        "controlkeel attach codex-cli --scope project",
        "controlkeel attach claude-code",
        "controlkeel attach cursor",
        "controlkeel attach doctor",
        "controlkeel help codex"
      ],
      next_steps: [
        "Use `--scope project` when you want repo-local host files.",
        "Use `--scope user` for hosts that support shared user config such as Codex or Claude.",
        "Use `--mcp-only` when you only want MCP registration and not native companion files.",
        "Run `controlkeel attach doctor` after attach to confirm host wiring and provider readiness."
      ],
      related: ["codex", "mcp", "skills"]
    },
    %{
      id: "codex",
      title: "Codex CLI integration",
      summary:
        "Codex is a review-only host in CK. CK writes `.codex/config.toml`, `.codex/hooks.json`, native `.codex/skills`, multiple Codex custom agents, review commands, and `.agents/skills` compatibility copies for the governed repo or user scope.",
      keywords: ["codex", "openai", ".codex", "review-only", "operator"],
      phrases: ["codex cli", "attach codex", "codex config"],
      commands: [
        "controlkeel attach codex-cli --scope project",
        "controlkeel attach codex-cli --scope user",
        "controlkeel attach codex-cli --mcp-only",
        "controlkeel plugin install codex --scope project"
      ],
      next_steps: [
        "Project scope writes `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks`, `.codex/skills`, `.codex/agents`, `.codex/commands`, and `.agents/skills` into the repo.",
        "User scope writes `~/.codex/config.toml`, `~/.codex/hooks.json`, `~/.codex/hooks`, `~/.codex/skills`, `~/.codex/agents`, `~/.codex/commands`, and `~/.agents/skills`.",
        "Codex custom agents now include `controlkeel-operator`, `controlkeel-reviewer`, and `controlkeel-docs-researcher` for separate execution, review, and documentation workflows.",
        "Codex only loads repo `.codex/` layers when the project is trusted, so trust the repo if hooks or config appear to be ignored.",
        "Restart Codex after `controlkeel attach codex-cli` or `controlkeel plugin install codex` so new hooks, custom agents, and marketplace changes are reloaded."
      ],
      related: ["attach", "review", "skills", "run"]
    },
    %{
      id: "review",
      title: "Review and approvals",
      summary:
        "CK uses plan reviews, diff reviews, findings, and feedback loops to keep agent work policy-gated instead of silently shipping.",
      keywords: [
        "review",
        "approve",
        "approval",
        "plan",
        "feedback",
        "annotate",
        "diff",
        "pr",
        "blocked"
      ],
      phrases: ["task blocked", "why is my task blocked", "approve plan", "review a diff"],
      commands: [
        "controlkeel review diff --base main --head HEAD",
        "controlkeel review plan submit --stdin",
        "controlkeel review plan open --id 123",
        "controlkeel review plan respond 123 --decision approved"
      ],
      next_steps: [
        "Use `review plan submit` when an agent needs human approval on a plan.",
        "Use `review diff`, `review pr`, or `review socket` for explicit review passes.",
        "If a task is blocked, check `controlkeel findings` and open review state first."
      ],
      related: ["findings", "run", "codex"]
    },
    %{
      id: "findings",
      title: "Findings and blocked work",
      summary:
        "Findings are CK's policy and validation output. Open or blocked findings can stop task execution until they are reviewed or resolved.",
      keywords: ["finding", "findings", "blocked", "severity", "translate", "approve", "policy"],
      phrases: ["blocked by finding", "show findings", "translate findings"],
      commands: [
        "controlkeel findings",
        "controlkeel findings --severity high",
        "controlkeel findings translate",
        "controlkeel approve <finding-id>"
      ],
      next_steps: [
        "Start with `controlkeel findings` to see what is open or blocked.",
        "Use `findings translate` if you want the output rewritten into plain English.",
        "Approval only clears the governance gate when the workflow allows it; some findings still require real remediation."
      ],
      related: ["review", "run", "policy"]
    },
    %{
      id: "run",
      title: "Running agents from CK",
      summary:
        "CK can either run an agent directly, hand work off to an external host, or export a runtime package depending on the integration's execution model.",
      keywords: [
        "run",
        "execute",
        "doctor",
        "delegate",
        "task",
        "session",
        "embedded",
        "handoff",
        "runtime",
        "sandbox"
      ],
      phrases: ["run a task", "run session", "agent doctor"],
      commands: [
        "controlkeel agents doctor",
        "controlkeel run task <id> --agent codex-cli --mode embedded",
        "controlkeel run session <id>",
        "controlkeel sandbox status"
      ],
      next_steps: [
        "Use `agents doctor` to see which agents are runnable and in what mode.",
        "Use `run task` for a specific governed task or `run session` for all ready tasks.",
        "If a run does not proceed, check findings and pending reviews because CK keeps execution policy-gated."
      ],
      related: ["findings", "review", "attach"]
    },
    %{
      id: "sessions",
      title: "Sessions and mission switching",
      summary:
        "Use session commands when a project binding should point at a different mission without reinitializing the folder.",
      keywords: [
        "session",
        "sessions",
        "mission",
        "missions",
        "switch",
        "active",
        "project",
        "folder",
        "binding"
      ],
      phrases: ["switch mission", "change active mission", "list missions", "different folder"],
      commands: [
        "controlkeel session list",
        "controlkeel session switch <mission-id>",
        "controlkeel status",
        "controlkeel context --json"
      ],
      next_steps: [
        "Run `controlkeel session list` to see recent missions available to bind.",
        "Run `controlkeel session switch <mission-id>` inside the project folder that should use that mission.",
        "Run `controlkeel status` to confirm the active mission, budget, findings, and proof state now match."
      ],
      related: ["getting-started", "run", "findings"]
    },
    %{
      id: "skills",
      title: "Skills, bundles, and plugins",
      summary:
        "CK can export or install host-native bundles, open-standard skills, and plugin packages for supported agents.",
      keywords: ["skills", "skill", "bundle", "plugin", "plugins", "export", "install"],
      phrases: ["export skills", "install plugin", "native bundle"],
      commands: [
        "controlkeel skills list",
        "controlkeel skills export --target codex",
        "controlkeel skills install --target codex --scope project",
        "controlkeel plugin export codex"
      ],
      next_steps: [
        "Use `skills list` to inspect target compatibility and bundle health.",
        "Use `skills export` when you want a dist bundle without installing it yet.",
        "Use `plugin export` or `plugin install` for the hosts that ship plugin bundles."
      ],
      related: ["attach", "codex", "mcp"]
    },
    %{
      id: "providers",
      title: "Providers and model access",
      summary:
        "CK can use an attached host's provider bridge, a CK-owned provider profile, a local compatible backend, or heuristic mode when no provider is configured.",
      keywords: [
        "provider",
        "providers",
        "model",
        "openai",
        "anthropic",
        "ollama",
        "base-url",
        "api-key",
        "auth"
      ],
      phrases: ["set provider", "configure openai", "local model"],
      commands: [
        "controlkeel provider list",
        "controlkeel provider doctor",
        "controlkeel provider set-key openai --value \"$OPENAI_API_KEY\"",
        "controlkeel provider set-base-url openai --value http://127.0.0.1:1234"
      ],
      next_steps: [
        "Use `provider doctor` if CK seems unable to run model-backed advisory flows.",
        "Use `set-base-url` and `set-model` for OpenAI-compatible local or hosted backends.",
        "Some hosts, such as Codex CLI and Claude Code, can bridge provider access for CK."
      ],
      related: ["getting-started", "run", "codex"]
    },
    %{
      id: "troubleshooting",
      title: "MCP troubleshooting",
      summary:
        "Use this when CK tools return Not connected, a host says failed to connect, or attach looks successful but MCP calls fail.",
      keywords: [
        "troubleshoot",
        "troubleshooting",
        "not",
        "connected",
        "failed",
        "connect",
        "mcp",
        "doctor",
        "ck_context",
        "ck_validate"
      ],
      phrases: [
        "not connected",
        "failed to connect",
        "ck context not connected",
        "ck validate not connected"
      ],
      commands: [
        "controlkeel attach doctor",
        "controlkeel status",
        "controlkeel provider doctor",
        "controlkeel attach claude-code"
      ],
      next_steps: [
        "Run `controlkeel attach doctor` first to confirm attached and runnable host state.",
        "For Claude, run `claude mcp get controlkeel` and re-attach if status is failed.",
        "If a host cannot launch `controlkeel`, set `CONTROLKEEL_BIN` to an absolute binary path and attach again.",
        "After startup, wait 2-5 seconds and retry once to avoid transient MCP backend boot races."
      ],
      related: ["attach", "mcp", "providers", "getting-started"]
    },
    %{
      id: "worktrees",
      title: "Worktrees and parallel branches",
      summary:
        "Use git worktrees to run parallel governed slices without stomping your main working copy. CK can now surface and switch worktrees through MCP tools.",
      keywords: [
        "worktree",
        "worktrees",
        "parallel",
        "branch",
        "branches",
        "git worktree",
        "slice"
      ],
      phrases: ["use worktrees", "parallel work", "switch worktree"],
      commands: [
        "MCP: ck_worktree_list",
        "MCP: ck_worktree_switch",
        "controlkeel help mcp"
      ],
      next_steps: [
        "Prefer git worktrees for parallel agent tasks so each slice has an isolated working directory.",
        "Use `ck_worktree_list` to discover worktrees and `ck_worktree_switch` to update session metadata to the intended worktree.",
        "If your host does not expose MCP tool calling directly, attach CK and use the host's MCP tool UI to invoke these tools."
      ],
      related: ["mcp", "attach", "review"]
    },
    %{
      id: "checkpoints",
      title: "Checkpoints and workspace restore",
      summary:
        "Checkpoints capture a governed snapshot of workspace context (git state, worktree metadata, hashes) so sessions can resume, migrate, or roll back intentionally.",
      keywords: ["checkpoint", "checkpoints", "resume", "restore", "snapshot", "rollback"],
      phrases: ["create checkpoint", "restore checkpoint", "resume session"],
      commands: [
        "MCP: ck_checkpoint_create",
        "MCP: ck_checkpoint_restore",
        "MCP: ck_checkpoint_list"
      ],
      next_steps: [
        "Use `ck_checkpoint_create` before risky changes or before handing work off to another runtime.",
        "Use `ck_checkpoint_list` to find the most recent checkpoint for a session.",
        "Use `ck_checkpoint_restore` to annotate the session as restored-from-checkpoint (this is metadata-only unless you also apply repo changes separately)."
      ],
      related: ["mcp", "review", "findings"]
    },
    %{
      id: "git",
      title: "Governed git workflow",
      summary:
        "CK can now generate diffs and validate them, validate commit messages, and surface git status as MCP tools so git actions stay inside the governance loop.",
      keywords: ["git", "diff", "commit", "status", "pr", "merge"],
      phrases: ["validate diff", "commit with ck", "git status"],
      commands: [
        "MCP: ck_git_diff",
        "MCP: ck_git_commit",
        "MCP: ck_git_status",
        "controlkeel review diff"
      ],
      next_steps: [
        "Use `ck_git_diff` to get a diff + CK validation result as one governed artifact.",
        "Use `ck_git_commit` to validate commit intent before running `git commit`.",
        "If you want full PR workflows, keep using `controlkeel review diff` / `review pr` and your normal git tooling for push and PR creation."
      ],
      related: ["review", "findings", "mcp"]
    },
    %{
      id: "mcp",
      title: "MCP, hosted access, and remote clients",
      summary:
        "CK exposes a local stdio MCP server for repo-local trust and also supports hosted MCP plus a minimal A2A surface for remote machines.",
      keywords: [
        "mcp",
        "server",
        "stdio",
        "hosted",
        "oauth",
        "a2a",
        "remote",
        "service-account",
        "token"
      ],
      phrases: ["run mcp", "hosted mcp", "remote client"],
      commands: [
        "controlkeel mcp --project-root /abs/path",
        :hosted_service_account_command,
        "controlkeel registry status acp",
        "controlkeel help attach"
      ],
      next_steps: [
        "Use local stdio MCP for native repo-local attachments.",
        "Use service accounts plus `POST /oauth/token` and `POST /mcp` for hosted remote access.",
        "Use the A2A surface only for the narrow governed capabilities CK advertises."
      ],
      related: ["attach", "providers", "skills"]
    },
    %{
      id: "observability",
      title: "Observability, costs, and telemetry",
      summary:
        "Inspect telemetry, timelines, costs, memory quality, learning-loop signals, and generated benchmark candidates. Export observability envelopes for replay.",
      keywords: [
        "observability",
        "obs",
        "telemetry",
        "timeline",
        "costs",
        "memory",
        "trends",
        "problems",
        "benchmarks",
        "loop"
      ],
      phrases: ["observability export", "show costs", "memory quality", "obs status"],
      commands: [
        "controlkeel obs status",
        "controlkeel obs export <id>",
        "controlkeel obs costs --by provider",
        "controlkeel obs timeline"
      ],
      next_steps: [
        "Use `controlkeel obs status` for current session overview.",
        "Use `controlkeel obs export <id>` to create a portable envelope.",
        "Use `controlkeel obs costs --by provider` to break down spend."
      ],
      related: ["benchmarks", "learning", "providers"]
    },
    %{
      id: "cloud",
      title: "Cloud sync, orgs, and self-host",
      summary:
        "Operate cloud sync, workspace enrollment, enterprise orgs, audit exports, and self-host bundles. Manage service accounts and policy sets.",
      keywords: [
        "cloud",
        "sync",
        "org",
        "organization",
        "workspace",
        "selfhost",
        "audit",
        "service-account",
        "webhook",
        "govern"
      ],
      phrases: ["cloud sync", "create org", "selfhost verify", "cloud push"],
      commands: [
        "controlkeel cloud doctor",
        "controlkeel cloud push",
        "controlkeel org list",
        "controlkeel selfhost verify"
      ],
      next_steps: [
        "Use `cloud doctor` to check runtime mode and sync endpoint.",
        "Use `org list` and `org invite` for enterprise org management.",
        "Use `selfhost verify` before air-gapped deploys."
      ],
      related: ["mcp", "providers", "deploy"]
    },
    %{
      id: "benchmarks",
      title: "Benchmarks and eval harness",
      summary:
        "Run validation evals, benchmark suites, import manual outputs, and export results for comparison across subjects.",
      keywords: [
        "benchmark",
        "eval",
        "harness",
        "suite",
        "compare",
        "import",
        "export",
        "regression"
      ],
      phrases: ["run benchmark", "eval list", "benchmark compare", "eval run"],
      commands: [
        "controlkeel benchmark list",
        "controlkeel benchmark run --suite governance-regression",
        "controlkeel eval list",
        "controlkeel benchmark compare <run-id>"
      ],
      next_steps: [
        "Use `benchmark list` to see built-in suites.",
        "Use `benchmark run` to persist a matrix.",
        "Use `benchmark compare` to diff subjects."
      ],
      related: ["observability", "learning", "security"]
    },
    %{
      id: "deploy",
      title: "Deployment and runtime bundles",
      summary:
        "Analyze deployment posture, export runtime bundles, and inspect DNS, migrations, scaling, and hosting costs.",
      keywords: [
        "deploy",
        "runtime",
        "export",
        "dns",
        "migration",
        "scaling",
        "hosting",
        "cost",
        "analyze"
      ],
      phrases: ["deploy analyze", "runtime export", "hosting cost", "deploy dns"],
      commands: [
        "controlkeel deploy analyze --project-root .",
        "controlkeel deploy cost --stack phoenix",
        "controlkeel runtime export devin"
      ],
      next_steps: [
        "Use `deploy analyze` to generate deployment files.",
        "Use `deploy cost` to compare hosting tiers.",
        "Use `runtime export` for handoff bundles."
      ],
      related: ["cloud", "benchmarks", "providers"]
    },
    %{
      id: "learning",
      title: "Learning loop and outcomes",
      summary:
        "Record outcomes and surface learning-loop scores for routing and continuous improvement across sessions.",
      keywords: ["learning", "outcome", "leaderboard", "score", "routing", "improvement"],
      phrases: ["record outcome", "leaderboard", "learning loop", "outcome score"],
      commands: [
        "controlkeel outcome record <session-id> <outcome>",
        "controlkeel outcome leaderboard",
        "controlkeel outcome score <agent-id>"
      ],
      next_steps: [
        "Use `outcome record` after session completion.",
        "Use `outcome leaderboard` to compare agents.",
        "Use `outcome score` for single-agent history."
      ],
      related: ["run", "benchmarks", "observability"]
    },
    %{
      id: "security",
      title: "Sandbox, precommit, and security gates",
      summary:
        "Inspect sandbox adapters, precommit policy checks, and governed code execution posture. Keep execution and commits policy-gated.",
      keywords: ["security", "sandbox", "precommit", "gate", "execution", "code-mode", "policy"],
      phrases: ["sandbox status", "precommit check", "security gate", "code mode"],
      commands: [
        "controlkeel sandbox status",
        "controlkeel precommit-check --domain-pack software",
        "controlkeel precommit-install"
      ],
      next_steps: [
        "Use `sandbox status` to check adapter availability.",
        "Use `precommit-check` to scan staged files.",
        "Use `precommit-install` to add the hook."
      ],
      related: ["review", "run", "findings"]
    }
  ]

  def usage_text do
    catalog_lines =
      Catalog.all()
      |> Enum.map(fn e -> "  controlkeel #{e.path}  — #{e.summary}" end)
      |> Enum.join("\n")

    help_topics =
      Catalog.all()
      |> Enum.map(& &1.help_topic)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.join(", ")

    """
    ControlKeel CLI

    Guided help:
      controlkeel help                     Show the overview and common entry points
      controlkeel help <topic>             Show guided help for a topic such as #{help_topics}
      controlkeel help <question ...>      Route a free-form question such as:
                                           - controlkeel help how do i attach codex
                                           - controlkeel help why is my task blocked
                                           - controlkeel help ck_context not connected
                                           - controlkeel help what can controlkeel do

    Catalog (#{length(Catalog.all())} commands, #{map_size(Catalog.families())} families):
    #{catalog_lines}
    """
  end

  defp hosted_service_account_command do
    scopes =
      ["a2a:access" | ControlKeel.Mcp.ProtocolInterop.hosted_mcp_scopes()]
      |> Enum.join(" ")

    "controlkeel service-account create --workspace-id 1 --name ci-mcp --scopes \"#{scopes}\""
  end

  def render([]), do: general_help()

  def render(args) when is_list(args) do
    query =
      args
      |> Enum.join(" ")
      |> String.trim()

    cond do
      query == "" ->
        general_help()

      entry = Catalog.for_path_query(query) ->
        command_help(entry)

      true ->
        query_help(query)
    end
  end

  def unknown_command_text(argv) do
    attempted = Enum.join(argv, " ")
    query = argv |> Enum.join(" ") |> String.trim()
    suggestion = best_help_command(query)

    [
      "Unknown command: controlkeel #{attempted}",
      "",
      "Try guided help instead:",
      "  #{suggestion}",
      "  controlkeel help",
      "  controlkeel version"
    ]
    |> Enum.join("\n")
  end

  def command_parse_error(command, invalid, remainder, argv \\ []) do
    entry = Catalog.for_command(command)
    invalid_flags = Enum.map(invalid, fn {flag, _value} -> flag end)

    {reason, code, details} =
      cond do
        invalid_flags != [] ->
          {"Unknown option(s): #{Enum.join(invalid_flags, ", ")}", :invalid_option,
           %{"invalid_options" => invalid_flags}}

        remainder != [] ->
          {"Unexpected argument(s): #{Enum.join(remainder, " ")}", :unexpected_argument,
           %{"unexpected_arguments" => remainder}}

        true ->
          {"Invalid arguments", :invalid_arguments, %{}}
      end

    case entry do
      nil ->
        usage_text()

      entry ->
        message = "#{reason} for controlkeel #{entry.path}"

        if Output.json_requested?(argv) do
          Output.error_json(message, code, entry, details)
        else
          [
            message,
            "",
            "Use:",
            Enum.map(entry.examples, &"  #{&1}"),
            "",
            "Help:",
            "  controlkeel #{entry.path} --help",
            "  controlkeel help #{entry.help_topic}"
          ]
          |> List.flatten()
          |> Enum.join("\n")
        end
    end
  end

  defp command_help(entry) do
    [
      "ControlKeel command help",
      "",
      "Command: controlkeel #{entry.path}",
      "Family: #{entry.family}",
      "",
      entry.summary,
      "",
      "Examples:",
      Enum.map(entry.examples, &"  #{&1}"),
      "",
      "Inputs: #{format_atoms(entry.inputs)}",
      "Outputs: #{format_atoms(entry.outputs)}",
      "Safety: #{format_safety(entry.safety)}",
      related_lines("Related MCP tools", entry.related_mcp_tools),
      related_lines("Related skills", entry.related_skills),
      related_lines("Related hooks", entry.related_hooks),
      related_lines("Related plugins", entry.related_plugins),
      "",
      "Related help:",
      "  controlkeel help #{entry.help_topic}"
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_atoms(values), do: values |> Enum.map(&to_string/1) |> Enum.join(", ")

  defp format_safety(safety) do
    safety
    |> Enum.filter(fn {_key, value} -> value == true end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> case do
      [] -> "read-only metadata/no special risk flags"
      values -> Enum.join(values, ", ")
    end
  end

  defp related_lines(_label, []), do: nil

  defp related_lines(label, values) do
    ["", "#{label}:", Enum.map(values, &"  - #{&1}")]
  end

  defp general_help do
    topics = @topics |> Enum.map(&"      - #{&1.id}") |> Enum.join("\n")

    """
    ControlKeel help

    What CK can do:
      - bootstrap a governed project with local MCP access
      - attach supported coding hosts such as Codex, Claude, Cursor, OpenCode, and more
      - surface findings, plan reviews, proofs, and release-readiness checks
      - run or hand off governed tasks through supported agent execution paths
      - export native bundles, plugins, and hosted MCP/A2A access surfaces

    Good starting points:
      - `controlkeel help getting-started`
      - `controlkeel help attach`
      - `controlkeel help codex`
      - `controlkeel help why is my task blocked`
      - `controlkeel help run agents`
      - `controlkeel help providers`
      - `controlkeel help troubleshooting`

    Common first commands:
      - `controlkeel init`
      - `controlkeel attach codex-cli`
      - `controlkeel attach doctor`
      - `controlkeel status`
      - `controlkeel findings`
      - `controlkeel agents doctor`

    Topics (#{length(@topics)}):
    #{topics}
    """
  end

  defp query_help(query) do
    tokens = tokenize(query)
    matches = matched_topics(query, tokens)
    agent = matched_agent(tokens)

    case {matches, agent} do
      {[], nil} ->
        """
        ControlKeel help

        I could not confidently route: "#{query}"

        Try one of these:
          - `controlkeel help getting-started`
          - `controlkeel help attach`
          - `controlkeel help codex`
          - `controlkeel help review`
          - `controlkeel help findings`
          - `controlkeel help run`

        Or ask in plain language, for example:
          - `controlkeel help how do i attach codex`
          - `controlkeel help why is my task blocked`
          - `controlkeel help ck_validate not connected`
        """

      _ ->
        primary_topic = matches |> List.first() |> elem(0)
        related_topics = matches |> Enum.drop(1) |> Enum.map(fn {topic, _score} -> topic.id end)

        [
          "ControlKeel help",
          "",
          "Query: #{query}",
          "Matched topic: #{primary_topic.title}",
          agent && "Matched agent: #{agent.label}",
          "",
          "#{primary_topic.summary}",
          "",
          "Try these commands:",
          Enum.map(primary_topic.commands, &"  - `#{&1}`"),
          agent_help_block(agent),
          "",
          "Guidance:",
          Enum.map(primary_topic.next_steps, &"  - #{&1}"),
          related_help_block(primary_topic.related ++ related_topics)
        ]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
    end
  end

  defp agent_help_block(nil), do: nil

  defp agent_help_block(integration) do
    [
      "",
      "Agent-specific notes:",
      "  - attach command: `#{integration.attach_command}`",
      "  - phase model: #{integration.phase_model}",
      "  - review path: #{integration.review_experience}",
      "  - scope: #{Enum.join(integration.supported_scopes, ", ")}",
      artifact_line(integration),
      direct_install_line(integration)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp artifact_line(integration) do
    case integration.artifact_surfaces do
      [] -> nil
      surfaces -> "  - companion files: #{Enum.join(surfaces, ", ")}"
    end
  end

  defp direct_install_line(integration) do
    case integration.direct_install_methods do
      [] ->
        nil

      methods ->
        rendered =
          methods
          |> Enum.map(&format_direct_install_method/1)
          |> Enum.reject(&(&1 in [nil, ""]))

        if rendered == [] do
          nil
        else
          "  - direct installs: #{Enum.join(rendered, " | ")}"
        end
    end
  end

  defp format_direct_install_method(%{"command" => command, "label" => label})
       when is_binary(command) and is_binary(label) do
    "#{label}: #{command}"
  end

  defp format_direct_install_method(%{"command" => command}) when is_binary(command), do: command
  defp format_direct_install_method(value) when is_binary(value), do: value
  defp format_direct_install_method(_value), do: nil

  defp related_help_block([]), do: nil

  defp related_help_block(topic_ids) do
    related =
      topic_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(3)

    case related do
      [] ->
        nil

      values ->
        [
          "",
          "Related help:",
          Enum.map(values, &"  - `controlkeel help #{&1}`")
        ]
    end
  end

  defp matched_topics(query, tokens) do
    topics()
    |> Enum.map(fn topic -> {topic, topic_score(topic, query, tokens)} end)
    |> Enum.filter(fn {_topic, score} -> score > 0 end)
    |> Enum.sort_by(fn {topic, score} -> {-score, topic.id} end)
    |> Enum.take(3)
  end

  defp topic_score(topic, query, tokens) do
    id_score = if topic.id in tokens, do: 8, else: 0

    keyword_score =
      topic.keywords
      |> Enum.count(&(&1 in tokens))
      |> Kernel.*(3)

    phrase_score =
      topic.phrases
      |> Enum.count(&String.contains?(query, &1))
      |> Kernel.*(5)

    id_score + keyword_score + phrase_score
  end

  defp matched_agent(tokens) do
    Integration.attach_catalog()
    |> Enum.find(fn integration ->
      candidate_tokens =
        ([integration.id, integration.label, integration.preferred_target] ++
           integration.supported_scopes)
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(&tokenize/1)
        |> MapSet.new()

      Enum.any?(tokens, &MapSet.member?(candidate_tokens, &1))
    end)
  end

  defp best_help_command(""), do: "controlkeel help"
  defp best_help_command(query), do: "controlkeel help #{query}"

  defp tokenize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split(" ", trim: true)
  end

  defp topics do
    Enum.map(@topics, fn
      %{commands: commands} = topic ->
        %{topic | commands: Enum.map(commands, &resolve_command/1)}

      topic ->
        topic
    end)
  end

  defp resolve_command(:hosted_service_account_command), do: hosted_service_account_command()
  defp resolve_command(command), do: command
end
