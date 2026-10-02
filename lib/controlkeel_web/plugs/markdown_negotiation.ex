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

    ### Homebrew (macOS/Linux)
    ```
    brew tap aryaminus/controlkeel && brew install controlkeel
    ```

    ### npm
    ```
    npm i -g @aryaminus/controlkeel
    ```

    ### Unix
    ```
    curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
    ```

    ### PowerShell (Windows)
    ```
    irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
    ```

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

    - Intent intake and execution briefs at `/sessions/start`
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
