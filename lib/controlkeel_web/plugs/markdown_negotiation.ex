defmodule ControlKeelWeb.Plugs.MarkdownNegotiation do
  @moduledoc """
  Plug that adds `Vary: Accept` header to responses and serves key pages
  as markdown when the client sends `Accept: text/markdown`.

  This satisfies the Is Agentic markdown content negotiation requirement.
  """
  import Plug.Conn

  @markdown_pages %{
    "/" => :home,
    "/docs/getting-started" => :getting_started,
    "/docs/agents" => :docs_agents,
    "/docs/governance" => :docs_governance,
    "/docs/observability" => :docs_observability,
    "/docs/skills" => :docs_skills,
    "/about" => :about,
    "/contact" => :contact,
    "/developers" => :developers
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "vary", "Accept, Accept-Encoding")

    if wants_markdown?(conn) do
      case Map.get(@markdown_pages, conn.request_path) do
        nil ->
          conn

        page ->
          conn
          |> put_resp_content_type("text/markdown")
          |> send_resp(200, page_to_markdown(page))
          |> halt()
      end
    else
      conn
    end
  end

  defp wants_markdown?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(fn accept -> String.contains?(accept, "text/markdown") end)
  end

  defp page_to_markdown(:home) do
    """
    # ControlKeel

    Open source governance for AI coding agents.

    ## Turn team knowledge into agent guardrails

    Static docs don't enforce anything. ControlKeel turns your policies, review taste, and domain rules into live findings, proofs, approval gates, and budgets that work across every supported agent.

    ### Policy gates for agents

    Convert domain knowledge and review decisions into typed memory, policy checks, governed findings, and approval gates.

    ### Evidence, not vibes

    Proof bundles, benchmark runs, and cost signals show whether agent workflows are getting safer and cheaper.

    ### Host-agnostic control

    Keep governance state outside the chat window so teams can move between supported agents without losing context.

    ## How it works

    From intent to evidence in four steps:

    1. **Capture intent** — Set scope, policy, risk, and budget
    2. **Agent works** — Use the host your team already likes
    3. **CK validates** — Findings, proofs, and gates fire as needed
    4. **Improve the loop** — Evals show what changed

    ## Get started

    Install in under five minutes. No account required for local mode.

    - Installation: https://controlkeel.com/docs/getting-started
    - GitHub: https://github.com/aryaminus/controlkeel
    - API docs: https://controlkeel.com/developers
    - OpenAPI spec: https://controlkeel.com/openapi.json

    ## API

    REST API available at `/api/v1` with endpoints for sessions, tasks, findings, proofs, benchmarks, skills, and memory.

    Authentication via `Authorization` header with API key.

    ## Contact

    - GitHub Issues: https://github.com/aryaminus/controlkeel/issues
    - Email: See https://controlkeel.com/contact
    """
  end

  defp page_to_markdown(:getting_started) do
    """
    # Getting Started with ControlKeel

    Install to first finding in five minutes.

    ControlKeel turns project rules, domain knowledge, and security boundaries into findings, proofs, approval gates, budgets, evals, and durable context across supported hosts.

    ## Install

    """ <>
      Enum.map_join(ControlKeel.Skills.install_channels(), "\n", &install_channel_markdown/1) <>
      """

      ## Quick Start

      1. Run `controlkeel` to boot the local web app
      2. In your project, run `controlkeel setup`, then `controlkeel attach opencode`
      3. Binding auto-bootstraps on first use
      4. Run `controlkeel attach doctor` and `controlkeel status`
      5. Trigger a controlled validation, then check findings

      ## API

      REST API at `/api/v1`. See https://controlkeel.com/openapi.json for the full specification.
      """
  end

  defp page_to_markdown(:docs_agents) do
    """
    # How agents use CK

    Every supported agent host, how it attaches to ControlKeel, and how ControlKeel runs it back.

    ## Supported agents

    - `controlkeel attach codex-cli` installs native Codex skills and the CK operator agent.
    - `controlkeel attach vscode` and `controlkeel attach copilot` prepare repo-native skills plus MCP config.
    - OpenCode is the recommended quick start; Cursor, Windsurf, Kiro, Amp, Gemini CLI, Continue, and Aider use the same portable bundle path.
    - Learn more on GitHub: https://github.com/aryaminus/controlkeel

    ## Host catalog

    Generated from the same integration catalog as the HTML page.

    """ <>
      Enum.map_join(ControlKeel.Skills.agent_integrations(), "\n", &integration_markdown/1)
  end

  defp page_to_markdown(:docs_governance) do
    """
    # How it governs

    The delivery lifecycle, proof loop, and operating modes behind every governed change.

    ## Governed delivery lifecycle

    Every change moves through the same loop, from stated intent to recorded evidence:

    - Intent intake and execution briefs at `/new/session`
    - Task graph, validation, and findings during execution
    - Proof bundles, Ship Dashboard, and benchmarks as evidence

    ## Proof console loop

    Governance state lives outside the chat window, so evidence stays reviewable after the session ends:

    - Session Control for active task state, risk, and approvals
    - Findings turn policy violations into reviewable work
    - Proof Browser for immutable evidence and rollback guidance
    - Ship Dashboard and benchmarks for outcome evidence

    ## Autonomy and findings

    Severity maps to expected human gates; findings stay readable in plain language. LLM advisory is optional and needs a provider. See `docs/autonomy-and-findings.md`.

    ## Operating modes

    - Local mode ships with SQLite, Ollama, or heuristic fallback.
    - Cloud mode connects orgs, projects, users, webhooks, and service accounts as shared governance evidence.
    - Use benchmarks to collect bounded evidence before claiming a workflow is safer, cheaper, or faster.

    ## Occupation-first onboarding

    Start from what best describes your work. ControlKeel picks the domain pack, interview language, and governance posture behind the scenes, so non-experts don't need to choose a framework first.

    ## Project rescue

    If another tool already touched the repo, bootstrap it, run `controlkeel watch`, and use findings, proofs, and `ck_validate` to recover. Add governed proxy only when the tool points at compatible OpenAI or Anthropic endpoints.
    """
  end

  defp page_to_markdown(:docs_observability) do
    """
    # Observability

    Evidence, not impressions — how ControlKeel turns agent work into costs, regressions, benchmarks, and durable improvements.

    ## Why observability

    Agent output is cheap to produce and expensive to verify. Without evidence, every claim about a workflow — it costs less, it regresses less, it ships safer — is an impression. Observability is how ControlKeel replaces impressions with measurements: sessions emit telemetry as the agent works, and that telemetry becomes views you can act on.

    In practice this gives you:

    - Spend visibility per model, tool, source, and provider over rolling windows.
    - Regression detection — advisory eval candidates derived from grouped problems and feedback evidence.
    - Benchmarks with explicit execution gating, so claims are backed by runs you chose to make.
    - Memory quality signals — stale entries and duplicate clusters surfaced before they pollute context.
    - Ranked recommendations for the next improvement action.
    - Immutable evidence exports — session JSON and audit logs for review or compliance.

    ## The evidence loop

    1. **Collect.** Sessions record events, spend, findings, and proofs as the agent works.
    2. **Aggregate.** Telemetry rolls up per workspace into costs, trends, and period comparisons.
    3. **Detect.** Anomalies become eval candidates; grouped problems and feedback mark regressions; memory scans flag staleness and duplicates.
    4. **Prove.** Benchmark drafts turn evidence into runnable scenarios; execution is gated behind an explicit flag.
    5. **Improve.** Surviving outcomes drive promotions and memory writes, and the improved memory serves the next session.

    ## Reading a single session

    Use the session observability view (`/:org_slug/workspaces/:ws_slug/sessions/:id/observability`) when the question is about one run — what happened, what it cost, and what it touched. It brings together run state, memory context, the event timeline, and downloadable session and audit evidence.

    ## Monitoring a workspace

    Use `/:org_slug/workspaces/:ws_slug/observability` for ongoing signal across workspace sessions. Each page has a terminal parallel. The benchmark workflow groups drafts, scenarios, history, and regressions on its benchmark page; these sections map to the following commands:

    | Page | Terminal |
    |---|---|
    | Overview — `/:org_slug/workspaces/:ws_slug/observability` | `controlkeel obs` |
    | Loop — `/:org_slug/workspaces/:ws_slug/observability/loop` | `controlkeel obs loop` |
    | Costs — `/:org_slug/workspaces/:ws_slug/observability/costs` | `controlkeel obs costs` |
    | Trends — `/:org_slug/workspaces/:ws_slug/observability/trends` | `controlkeel obs trends --days 30` |
    | Compare — `/:org_slug/workspaces/:ws_slug/observability/compare` | `controlkeel obs compare` |
    | Evals — `/:org_slug/workspaces/:ws_slug/observability/evals` | `controlkeel obs evals` |
    | Imports — `/:org_slug/workspaces/:ws_slug/observability/imports` | `controlkeel obs imports` |
    | Memory quality — `/:org_slug/workspaces/:ws_slug/observability/memory-quality` | `controlkeel obs memory-quality` |
    | Recommendations — `/:org_slug/workspaces/:ws_slug/observability/recommendations` | `controlkeel obs recommend` |
    | Promotions — `/:org_slug/workspaces/:ws_slug/observability/promotions` | `controlkeel obs promotions` |
    | Benchmark — drafts — `/:org_slug/workspaces/:ws_slug/observability/benchmark#benchmarks-drafts` | `controlkeel obs benchmarks drafts` |
    | Benchmark — scenarios — `/:org_slug/workspaces/:ws_slug/observability/benchmark#benchmarks-scenarios` | `controlkeel obs benchmarks scenarios` |
    | Benchmark — history — `/:org_slug/workspaces/:ws_slug/observability/benchmark#benchmarks-history` | `controlkeel obs benchmarks history` |
    | Benchmark — regressions — `/:org_slug/workspaces/:ws_slug/observability/benchmark#benchmarks-regressions` | `controlkeel obs regressions` |

    ## CLI reference

    Run these commands from a project with ControlKeel set up. Running `controlkeel obs` is equivalent to `controlkeel obs status`. The `loop-status` spelling is also accepted as an alias for `loop`.

    | Command | Purpose |
    |---|---|
    | `controlkeel obs status` | Show the current project's observability overview. |
    | `controlkeel obs run <session-id>` | Show observability details for one session. |
    | `controlkeel obs loop` | Inspect learning-loop status and diagnostics. |
    | `controlkeel obs problems` | Review grouped workspace problems. |
    | `controlkeel obs costs` | Inspect workspace spend; optionally group with `--by`. |
    | `controlkeel obs imports` | List imported telemetry snapshots. |
    | `controlkeel obs trends` | Review telemetry trends over a day window with `--days`. |
    | `controlkeel obs regressions` | Review regression signals; supports `--days` and `--limit`. |
    | `controlkeel obs recommend` | Show ranked next-step recommendations. |
    | `controlkeel obs evals` | List advisory eval candidates. |
    | `controlkeel obs evals save` | Save current eval candidates locally. |
    | `controlkeel obs evals persisted` | List saved eval candidates. |
    | `controlkeel obs benchmarks draft` | Generate local benchmark drafts from workspace evidence. |
    | `controlkeel obs benchmarks drafts` | List benchmark drafts and their review state. |
    | `controlkeel obs benchmarks approve <draft-id>` | Approve a draft. |
    | `controlkeel obs benchmarks reject <draft-id>` | Reject a draft. |
    | `controlkeel obs benchmarks archive <draft-id>` | Archive a draft. |
    | `controlkeel obs benchmarks materialize` | Create benchmark suites and scenarios from approved drafts; does not run them. |
    | `controlkeel obs benchmarks scenarios` | List observability benchmark scenarios. |
    | `controlkeel obs benchmarks run` | Preview with `--dry-run`; actual execution requires explicit `--execute`. |
    | `controlkeel obs benchmarks history` | Review prior observability benchmark runs. |
    | `controlkeel obs promotions` | Review advisory memory promotion candidates. |
    | `controlkeel obs compare` | Compare workspace telemetry periods; optionally group with `--by`. |
    | `controlkeel obs timeline [session-id]` | Show a session event timeline; defaults to the current session. |
    | `controlkeel obs memory [session-id]` | Show session memory context; defaults to the current session. |
    | `controlkeel obs memory-quality` | Find stale or duplicate memory records; configure age with `--stale-days`. |
    | `controlkeel obs export <session-id>` | Export a session observability envelope. |
    | `controlkeel obs import <file>` | Validate an envelope with `--dry-run` or persist it with `--persist`. |

    Supported flags vary by command. Common options include `--format` or `--json` for output, `--limit` for list sizes, and `--project-root` to select a project. Benchmark runs also accept `--suite`, `--subjects`, `--baseline-subject`, and `--scenario-slugs`.

    ## Proving an improvement

    The benchmark workflow is how a claim becomes evidence, and it is deliberately human-gated at every step that spends money or changes memory:

    1. Generate drafts from workspace evidence: `controlkeel obs benchmarks draft`
    2. Review the generated scenarios before anything runs — the web benchmark page shows the same drafts with full context.
    3. Approve the draft: `controlkeel obs benchmarks approve <id>`
    4. Dry-run first: `controlkeel obs benchmarks run --dry-run`
    5. Execute explicitly: `controlkeel obs benchmarks run --suite <suite> --subjects <subject-ids> --execute`
    6. Read the outcome in history, watch for regressions, and promote what survived: `controlkeel obs benchmarks history`, `controlkeel obs regressions`, `controlkeel obs promotions`

    ## Safety and automation

    Benchmark execution is CLI-only and refuses to run without an explicit `--execute` flag — a dry-run can never silently become a real run. Promotions and memory writes follow the same human-gated pattern: evidence proposes, a person disposes.

    For read-only inspection, agents should call the structured `ck_observability` MCP tool to receive typed report data. Draft approval, materialization, benchmark execution, and other mutations still require their dedicated governed workflows.
    """
  end

  defp page_to_markdown(:docs_skills) do
    """
    # Skills

    Portable workflow guidance that keeps every attached agent operating inside ControlKeel's governed loop.

    ## What skills are

    A ControlKeel skill is a plain `SKILL.md` bundle in the [AgentSkills format](https://agentskills.io/specification): a name, a description, and a governed workflow body — how to align on a goal, validate before an edit, bundle proof, or ship.

    The agent sees each skill's description with the task at hand and activates the one whose trigger conditions match. Once loaded, the skill's body steers the session: which CK calls to make, when to stop for a human, and what evidence to leave behind.

    Skills live in three scopes:

    - **Built-in** — shipped with ControlKeel, always available.
    - **User** — installed under your home directory (`~/.agents/skills`, `~/.codex/skills`, `~/.claude/skills`, and other host paths); travel with you across projects.
    - **Project** — inside a governed repository (`.agents/skills` and host peers). Only surfaced for trusted bindings, so one repo cannot inject instructions into another.

    When the same skill appears in several scopes with identical content, one definition wins — preferencing built-ins — and duplicates can be pruned automatically.

    ## Available skills

    Generated from the same registry as the HTML page and the CLI.

    #{Enum.map_join(ControlKeel.Skills.catalog(), "\n", &skill_markdown/1)}

    ## CLI reference

    Run these commands from a project with ControlKeel set up. Exports and installs write under `controlkeel/dist/<target>` and record a manifest.

    | Command | Purpose |
    |---|---|
    | `controlkeel skills list` | List the registry with diagnostics; `--json` for machine output, `--target <target>` to filter. |
    | `controlkeel skills validate` | Check every skill's frontmatter and structure; report warnings and errors with codes. |
    | `controlkeel skills export --target <target>` | Write a host-format skill bundle; defaults to open-standard. |
    | `controlkeel skills install --target <target>` | Install the bundle into the host's expected skills directory. |
    | `controlkeel token audit --mode skills` | Measure the token cost of your skill surface; modes: full, rules, skills, tools. |
    | `controlkeel skills doctor` | Diagnose catalog health, install manifests, attach clients, runtimes, and provider status. |

    ## How agents use skills

    Attaching a host writes skills to that host's native directory and registers them: a session-start hook surfaces the registry, and the host's skill mechanism makes each trigger available.

    - **Trigger.** The agent decides from the description; no one re-reads the whole catalog per task.
    - **Load.** The loaded body changes session behavior — align before building, validate before editing, bundle proof before shipping.
    - **Query over MCP.** `ck_skill_list`, `ck_skill_load`, `ck_skill_validate`, and `ck_token_audit` expose the same registry as typed tools.
    - **Manage over API.** REST endpoints at `/api/v1/skills` list, fetch, export, install, and prune duplicates. See https://controlkeel.com/developers

    Trust is scoped: project-level skills only load for a bound, trusted project — `CONTROLKEEL_TRUST_PROJECT_SKILLS` flips opt-in scoping explicitly.
    """
  end

  defp skill_markdown(skill) do
    """
    ### `#{skill.name}` (#{skill.scope})

    #{skill.description}
    """
  end

  defp page_to_markdown(:about) do
    """
    # About ControlKeel

    ControlKeel is an open-source agent control plane for governed AI engineering.

    ## What We Do

    We turn your policies, review taste, and domain rules into live findings, proofs, approval gates, and budgets that work across every supported AI coding agent.

    ## The Problem

    AI coding agents are powerful but ungoverned. Teams ship code faster than they can review it, and static documentation doesn't enforce anything. Agent output is cheap; reviewability, release safety, and cost control are not.

    ## Our Approach

    ControlKeel sits between the agent and the codebase, enforcing governance in real time:

    - **Findings** turn policy violations into reviewable work
    - **Proof bundles** provide immutable evidence of what happened
    - **Approval gates** ensure humans review high-risk changes
    - **Budgets** prevent runaway agent costs
    - **Benchmarks** measure whether workflows are improving

    ## Open Source

    ControlKeel is open source under the MIT license.

    - GitHub: https://github.com/aryaminus/controlkeel
    - License: MIT
    """
  end

  defp page_to_markdown(:contact) do
    """
    # Contact ControlKeel

    ## Support

    - **GitHub Issues**: https://github.com/aryaminus/controlkeel/issues
      Report bugs, request features, or ask questions.

    - **GitHub Discussions**: https://github.com/aryaminus/controlkeel/discussions
      Community conversations and support.

    ## Security

    To report security vulnerabilities, please use GitHub's private vulnerability reporting:
    https://github.com/aryaminus/controlkeel/security/advisories/new

    ## Business

    For partnership inquiries or enterprise support:
    - Email: support@controlkeel.com

    ## Community

    - GitHub: https://github.com/aryaminus/controlkeel
    - Documentation: https://controlkeel.com/docs/getting-started
    - API Reference: https://controlkeel.com/openapi.json
    """
  end

  defp page_to_markdown(:developers) do
    """
    # ControlKeel Developer Portal

    ## API Reference

    ControlKeel provides a REST API at `/api/v1` for programmatic access to governance features.

    ### Authentication

    All API requests require an `Authorization` header:
    ```
    Authorization: Bearer <your-api-key>
    ```

    ### OpenAPI Specification

    Full API specification available at: `/openapi.json`

    ### Key Endpoints

    | Method | Path | Description |
    |--------|------|-------------|
    | GET | /api/v1/sessions | List recent sessions |
    | POST | /api/v1/sessions | Create a session |
    | GET | /api/v1/sessions/:id | Get session details |
    | POST | /api/v1/validate | Validate content against policy |
    | GET | /api/v1/findings | List findings |
    | POST | /api/v1/findings | Create a finding |
    | GET | /api/v1/proofs | List proof bundles |
    | GET | /api/v1/benchmarks | List benchmarks |
    | GET | /api/v1/skills | List agent skills |
    | GET | /api/v1/memory/search | Search memory |
    | POST | /api/v1/memory | Create memory record |
    | GET | /api/v1/budget | Get budget status |
    | POST | /api/v1/route-agent | Route task to best agent |
    | GET | /api/v1/providers | List AI providers |

    ## MCP Server

    ControlKeel exposes an MCP (Model Context Protocol) server at `/mcp` for native integration with AI agents like Claude, ChatGPT, and others.

    ## Machine-Readable Metadata

    - **llms.txt**: `/llms.txt` — Product description for AI agents
    - **OpenAPI**: `/openapi.json` — Full API specification
    - **Sitemap**: `/sitemap.xml` — All indexable URLs

    ## SDKs and Tools

    - CLI: `npm i -g @aryaminus/controlkeel`
    - GitHub: https://github.com/aryaminus/controlkeel
    """
  end

  defp install_channel_markdown(channel) do
    """
    ### #{channel.label}
    ```
    #{channel.command}
    ```
    """
  end

  defp integration_markdown(integration) do
    """
    ### #{integration.label} (#{integration.support_class})

    - Attach: `#{attach_hint(integration)}`
    - Uses CK via: #{markdown_targets(integration.agent_uses_ck_via)}
    - Scope: #{markdown_targets(integration.supported_scopes)}
    - Install: #{integration.install_experience}
    - Auto-bootstrap: #{if integration.auto_bootstrap, do: "yes", else: "no"}
    - Execution: #{integration.execution_support || "inbound_only"}
    - Review: #{integration.review_experience}
    - Required CK tools: #{markdown_targets(integration.required_mcp_tools)}
    - MCP / skills: #{integration.mcp_mode} / #{integration.skills_mode}
    - Confidence: #{integration.confidence_level}
    """
  end

  defp attach_hint(integration) do
    integration.attach_command || integration.runtime_export_command || "reference only"
  end

  defp markdown_targets([]), do: "none"
  defp markdown_targets(nil), do: "none"
  defp markdown_targets(values), do: Enum.join(values, ", ")
end
