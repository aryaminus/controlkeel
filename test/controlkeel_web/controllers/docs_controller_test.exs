defmodule ControlKeelWeb.DocsControllerTest do
  use ControlKeelWeb.ConnCase, async: true

  describe "GET /docs" do
    test "renders the documentation overview with sidebar nav", %{conn: conn} do
      conn = get(conn, ~p"/docs")
      body = html_response(conn, 200)

      assert body =~ "Documentation for ControlKeel"
      assert body =~ "Browse documentation"
      assert body =~ "docs-sidebar"
      assert body =~ "Breadcrumb"
      assert body =~ ~p"/docs/getting-started"
      assert body =~ ~p"/docs/agents"
      assert body =~ ~p"/docs/governance"

      # Only the index link is marked current.
      assert body =~ ~r{href="/docs"[^>]*aria-current="page"}
      refute body =~ ~r{href="/docs/getting-started"[^>]*aria-current="page"}
    end
  end

  describe "GET /docs/getting-started" do
    test "renders install channels and post-install guidance", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")
      body = html_response(conn, 200)

      assert body =~ "Install to first finding in five minutes"
      assert body =~ "controlkeel setup"
      assert body =~ "controlkeel attach opencode"
      assert body =~ "After install"
      assert body =~ "Bind your project"
      assert body =~ "Verify and inspect"
      assert body =~ "Local stdio MCP exposes the full local tool set"
      assert body =~ ~r{href="/docs/getting-started"[^>]*aria-current="page"}
    end

    test "renders each install channel command as copyable", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")
      body = html_response(conn, 200)

      assert body =~ "install-channel-"
      assert body =~ "data-copy-command"
      assert body =~ "hero-clipboard-document"
    end
  end

  describe "GET /docs/agents" do
    test "renders the agent catalog and other supported agents", %{conn: conn} do
      conn = get(conn, ~p"/docs/agents")
      body = html_response(conn, 200)

      assert body =~ "How agents use CK"
      assert body =~ "Supported agents"
      assert body =~ "controlkeel attach codex-cli"
      assert body =~ "controlkeel attach opencode"
      assert body =~ "Get CK:"
      assert body =~ ~r{href="/docs/agents"[^>]*aria-current="page"}
    end
  end

  describe "GET /docs/governance" do
    test "renders the governance document sections", %{conn: conn} do
      conn = get(conn, ~p"/docs/governance")
      body = html_response(conn, 200)

      assert body =~ "How it governs"
      assert body =~ "Governed delivery lifecycle"
      assert body =~ "Proof console loop"
      assert body =~ "Autonomy and findings"
      assert body =~ "Operating modes"
      assert body =~ "Occupation-first onboarding"
      assert body =~ "Project rescue"
      assert body =~ ~r{href="/docs/governance"[^>]*aria-current="page"}
    end
  end

  describe "legacy guide URL" do
    test "GET /getting-started redirects to /docs/getting-started", %{conn: conn} do
      conn = get(conn, "/getting-started")

      assert redirected_to(conn, 302) == ~p"/docs/getting-started"
    end
  end

  describe "markdown negotiation" do
    test "GET /docs/agents with text/markdown returns markdown", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/markdown")
        |> get(~p"/docs/agents")

      body = response(conn, 200)

      assert body =~ "# How agents use CK"
      assert body =~ "## Host catalog"
      assert body =~ "### OpenCode"
      assert body =~ "controlkeel attach opencode"
      assert response_content_type(conn, :markdown)
    end

    test "GET /docs/governance with text/markdown returns markdown", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/markdown")
        |> get(~p"/docs/governance")

      body = response(conn, 200)

      assert body =~ "# How it governs"
      assert body =~ "## Proof console loop"
      assert body =~ "## Project rescue"
    end
  end
end
