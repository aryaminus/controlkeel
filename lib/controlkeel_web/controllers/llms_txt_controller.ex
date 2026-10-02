defmodule ControlKeelWeb.LlmsTxtController do
  use ControlKeelWeb, :controller

  @moduledoc """
  Serves /llms.txt — a machine-readable product description for AI agents.
  See https://llmstxt.org/ for the specification.
  """

  def index(conn, _params) do
    txt = """
    # ControlKeel

    > Agent control plane for governed AI engineering.

    ControlKeel turns your policies, review taste, and domain rules into live findings, proofs, approval gates, and budgets that work across every supported AI coding agent.

    ## Installation

    - Homebrew: `brew tap aryaminus/controlkeel && brew install controlkeel`
    - npm: `npm i -g @aryaminus/controlkeel`
    - Unix: `curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh`
    - PowerShell: `irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex`
    - GitHub Releases: https://github.com/aryaminus/controlkeel/releases

    ## API

    REST API base URL: `/api/v1`
    OpenAPI specification: `/openapi.json`
    Authentication: API key via `Authorization` header (Bearer or Token format)

    ### Key Endpoints

    - `GET /api/v1/sessions` — List recent sessions
    - `POST /api/v1/sessions` — Create a session
    - `GET /api/v1/sessions/:id` — Get session details
    - `POST /api/v1/validate` — Validate code/config against policy
    - `GET /api/v1/findings` — List findings
    - `POST /api/v1/findings` — Create a finding
    - `GET /api/v1/proofs` — List proof bundles
    - `GET /api/v1/benchmarks` — List benchmarks
    - `GET /api/v1/skills` — List agent skills
    - `GET /api/v1/memory/search` — Search memory records
    - `POST /api/v1/memory` — Create memory record
    - `GET /api/v1/budget` — Get budget status
    - `POST /api/v1/route-agent` — Route task to best agent
    - `GET /api/v1/providers` — List AI providers

    ## MCP

    ControlKeel exposes an MCP (Model Context Protocol) server at `/mcp` for native agent integration.

    ## Authentication

    API requests require an `Authorization` header with a valid API key.
    Format: `Authorization: Bearer <token>` or `Authorization: Token <token>`

    ## Documentation

    - Getting Started: https://controlkeel.com/docs/getting-started
    - GitHub: https://github.com/aryaminus/controlkeel
    - OpenAPI Spec: https://controlkeel.com/openapi.json

    ## Contact

    - GitHub Issues: https://github.com/aryaminus/controlkeel/issues
    - Email: See https://controlkeel.com/contact
    """

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_resp(200, txt)
  end
end
