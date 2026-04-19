defmodule ControlKeel.Help do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.ProtocolInterop

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
        "continue",
        "aider"
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
        "controlkeel service-account create --workspace-id 1 --name ci-mcp --scopes \"#{Enum.join(ProtocolInterop.hosted_mcp_scopes(), " ")}\"",
        "controlkeel registry status acp",
        "controlkeel help attach"
      ],
      next_steps: [
        "Use local stdio MCP for native repo-local attachments.",
        "Use service accounts plus `POST /oauth/token` and `POST /mcp` for hosted remote access.",
        "Use the A2A surface only for the narrow governed capabilities CK advertises."
      ],
      related: ["attach", "providers", "skills"]
    }
  ]

  def usage_text do
    """
    ControlKeel CLI

    Guided help:
      controlkeel help                     Show the overview and common entry points
      controlkeel help <topic>             Show guided help for a topic such as attach, codex, review, findings, run, skills, providers, troubleshooting, or mcp
      controlkeel help <question ...>      Route a free-form question such as:
                                          - controlkeel help how do i attach codex
                                          - controlkeel help why is my task blocked
                                          - controlkeel help ck_context not connected
                                          - controlkeel help what can controlkeel do

    Commands:
      controlkeel                     Start the web app
      controlkeel serve               Start the web app
      controlkeel setup [options]     Bootstrap the project and show detected hosts,
                                      provider state, core loop, and suggested next steps
      controlkeel init [options]      Initialize ControlKeel in the current project
      controlkeel attach <agent>      Register ControlKeel MCP server with your coding tool
                                      Native skills install by default unless --mcp-only
                                      Flags: --mcp-only, --no-native, --with-skills,
                                             --scope user|project
                                      Supported: #{supported_attach_agents_text()}
      controlkeel attach doctor [--project-root /abs/path]
                                      Run post-attach health checks and verification hints
      controlkeel review diff [options]
                                      Review a git diff between two refs before merge
      controlkeel review pr [options] Review a PR patch from --patch <file> or --stdin
      controlkeel review socket [options]
                  Review a Socket report from --report <file> or --stdin
      controlkeel review plan submit [options]
                                      Submit a plan for browser review from --body-file <file> or --stdin
      controlkeel review plan open --id <review-id>
                                      Print the browser review URL and current state
      controlkeel review plan respond <review-id> --decision approved|denied [--feedback-notes ...]
                                      Record an approval or denial for a submitted plan review
      controlkeel release-ready [options]
                                      Check proof-backed release readiness for a session
      controlkeel govern install github
                                      Scaffold repo-native GitHub governance workflows
      controlkeel plugin export codex|claude|copilot|openclaw|augment|droid
                                      Export a first-class plugin bundle for a supported agent
      controlkeel plugin install codex|claude|copilot|openclaw [--scope user|project] [--mode local|hosted]
                                      Install a plugin bundle with local and hosted MCP templates
      controlkeel agents doctor       Show bidirectional execution and install readiness
      controlkeel agents list [--json]
                                      List runnable/attached agent integrations
      controlkeel route-agent --task "..." [--risk-tier low|medium|high|critical] [--budget-remaining-cents N] [--allowed-agents a,b] [--domain-pack software] [--json]
                                      Ask CK router for a best-fit agent recommendation
      controlkeel task complete <task-id>
                                      Mark a task complete (gated by unresolved findings)
      controlkeel task claim <task-id> [--execution-mode agent|human|runtime]
                                      Claim a task run and mark in progress
      controlkeel task heartbeat <task-id> [--progress N] [--note "..."]
                                      Record task heartbeat/progress metadata
      controlkeel task checks <task-id> --checks '[{"check_type":"ci","status":"passed"}]'
                                      Record structured task checks for the active run
      controlkeel task report <task-id> [--status done|failed|blocked|paused|in_progress] [--output '{...}'] [--metadata '{...}']
                                      Report task run outcome/output metadata
      controlkeel run task <id> [--agent auto|<id>] [--mode auto|embedded|handoff|runtime] [--sandbox local|docker|e2b|nono]
                                      Run or hand off a governed task through a supported agent
      controlkeel run session <id> [--agent auto|<id>] [--mode auto|embedded|handoff|runtime] [--sandbox local|docker|e2b|nono]
                                      Run all ready tasks for a governed session
      controlkeel sandbox status       Show execution sandbox adapter availability
      controlkeel sandbox config local|docker|e2b|nono
                                      Set the default execution sandbox adapter
      controlkeel registry sync acp  Refresh the cached ACP registry metadata
      controlkeel registry status acp
                                      Show ACP registry cache freshness and matches
      controlkeel status              Show current session status
      controlkeel update [options]    Check for a newer GitHub release and refresh attached surfaces
      controlkeel context [options]   Show governed session context via the CK context surface
      controlkeel validate [options]  Validate proposed content via the CK validation surface
      controlkeel findings [options]  List findings for the current session
      controlkeel approve <id>        Approve a finding in the current session
      controlkeel proofs [options]    List proof bundles for the current session
      controlkeel proof <id>          Show a proof bundle by proof id or task id
      controlkeel audit-log <id>      Export a session audit log as json|csv|pdf
      controlkeel pause <task-id>     Pause a task and capture a resume packet
      controlkeel resume <task-id>    Resume a paused or blocked task
      controlkeel memory search <q>   Search typed memory for the current session
      controlkeel skills list         List skills, diagnostics, and compatibility targets
      controlkeel skills validate     Validate the catalog for the current project
      controlkeel skills export       Export native skill/plugin bundles
      controlkeel skills install      Install skills for a native target
      controlkeel skills doctor       Show trust, catalog, and install health
      controlkeel benchmark list [--domain-pack pack]
                                      List built-in suites and recent runs
      controlkeel benchmark run [options]
                                      Run a benchmark suite and persist the matrix
      controlkeel benchmark show <id> Show a benchmark run with subject summaries
      controlkeel benchmark import <run-id> <subject> <json-file>
                                      Import manual benchmark output for a subject
      controlkeel benchmark export <run-id> [--format json|csv]
                                      Export a benchmark run
      controlkeel policy list         List recent policy artifacts and training runs
      controlkeel policy train --type router|budget_hint
                                      Train a new policy artifact
      controlkeel policy show <id>    Show a policy artifact
      controlkeel policy promote <id> Promote a policy artifact if gates pass
      controlkeel policy archive <id> Archive a policy artifact
      controlkeel service-account create|list|revoke|rotate
                                      Manage workspace-scoped machine credentials
      controlkeel policy-set create|list|apply
                                      Manage enterprise policy sets and assignments
      controlkeel webhook create|list|replay
                                      Manage outbound CI/CD webhooks and deliveries
      controlkeel graph show <id>     Show the persisted task DAG for a session
      controlkeel execute <id>        Materialize ready tasks and task runs
      controlkeel worker start [--service-account-token TOKEN]
                                      Poll ready work for a workspace service account
      controlkeel provider list|show|default|set-key|set-base-url|set-model|doctor
                                      Inspect and configure CK provider brokerage
      controlkeel runtime export <id> [--project-root /abs/path]
                                      Export headless/runtime bundles such as Devin, Cloudflare Workers, Executor, or virtual-bash
      controlkeel bootstrap [--project-root /abs/path] [--ephemeral-ok]
                                      Auto-create project or ephemeral binding on first use
      controlkeel watch [--interval N] [--status]
                                      Stream findings and budget live (default: 2000ms), or print one-shot status with --status
      controlkeel mcp [--project-root /abs/path]
                                      Run the MCP server for a project
      controlkeel deploy analyze [--project-root /abs/path]
                                      Analyze project stack and generate deployment files
      controlkeel deploy cost [--stack phoenix|react|rails|node|python|static]
                                      Compare hosting costs across 9 platforms
      controlkeel deploy dns <stack>   Show DNS and SSL setup guide
      controlkeel deploy migration <stack>
                                      Show database migration guide
      controlkeel deploy scaling <stack>
                                      Show scaling and infrastructure guide
      controlkeel cost optimize [--session-id ID] [--provider PROVIDER] [--model MODEL]
                                      Get cost optimization suggestions
      controlkeel cost compare [--tokens N]
                                      Compare agent costs for a token budget
      controlkeel precommit-check [--domain-pack PACK] [--enforce]
                                      Scan staged files for policy violations
      controlkeel precommit-install [--enforce]
                                      Install git pre-commit hook
      controlkeel precommit-uninstall  Remove ControlKeel pre-commit hook
      controlkeel progress [--session-id ID]
                                      Show session progress, tasks, and findings
      controlkeel findings translate [--session-id ID]
                                      Translate findings to plain English
      controlkeel circuit-breaker status [--agent-id ID]
                                      Show circuit breaker status for agents
      controlkeel circuit-breaker trip <agent-id>
                                      Manually trip circuit breaker
      controlkeel circuit-breaker reset <agent-id>
                                      Reset circuit breaker for an agent
      controlkeel agents monitor [--agent-id ID]
                                      Show live agent activity and events
      controlkeel outcome record <session-id> <outcome>
                                      Record an agent outcome (deploy_success, test_pass, etc.)
      controlkeel outcome score <agent-id>
                                      Show agent score from outcomes
      controlkeel outcome leaderboard  Show agent leaderboard by outcome scores
      controlkeel help [topic or question]
                                      Show guided help for a topic or question
      controlkeel version             Show the current version
      controlkeel update --apply      Apply a safe self update when the install channel supports it
      controlkeel update --sync-attached
                                      Refresh attached plugins, hooks, skills, agents, and commands
    """
  end

  def render([]), do: general_help()

  def render(args) when is_list(args) do
    query =
      args
      |> Enum.join(" ")
      |> String.trim()

    if query == "" do
      general_help()
    else
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

  defp general_help do
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

    Topics:
      - overview
      - getting-started
      - attach
      - codex
      - review
      - findings
      - run
      - skills
      - providers
      - troubleshooting
      - mcp
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
    @topics
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
    AgentIntegration.attach_catalog()
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

  defp supported_attach_agents_text do
    AgentIntegration.attach_catalog()
    |> Enum.map(& &1.id)
    |> Enum.join(", ")
  end
end
