defmodule ControlKeelWeb.PageControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  defp create_workspace(org, name) do
    slug = String.replace(String.downcase(name), " ", "-")

    {:ok, workspace} =
      Mission.create_workspace(%{
        name: name,
        slug: slug,
        industry: "general",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "general",
        status: "active",
        org_id: org.id
      })

    workspace
  end

  defp create_session(workspace, title) do
    {:ok, session} =
      Mission.create_session(%{
        title: title,
        objective: "Ship the thing",
        risk_tier: "medium",
        status: "planned",
        budget_cents: 0,
        daily_budget_cents: 0,
        spent_cents: 0,
        workspace_id: workspace.id
      })

    session
  end

  describe "local mode GET /" do
    test "redirects to the default organization page", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert redirected_to(conn) == ~p"/#{LocalDefaults.default_org_slug()}"
    end

    test "provisions the default org on first visit", %{conn: conn} do
      assert Accounts.get_org_by_slug(LocalDefaults.default_org_slug()) == nil

      get(conn, ~p"/")

      assert Accounts.get_org_by_slug(LocalDefaults.default_org_slug()) != nil
    end
  end

  describe "cloud mode GET /" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      {:ok, user} = Accounts.create_user(%{email: "home@example.com", name: "Home"})

      {:ok, user: user}
    end

    test "renders the landing page for anonymous visitors", %{conn: conn} do
      conn = get(conn, ~p"/")
      body = html_response(conn, 200)

      assert body =~ "Turn team knowledge into"
      assert body =~ "Install ControlKeel"
      assert body =~ "Policy gates for agents"
      assert body =~ "Evidence, not vibes"
      assert body =~ "Host-agnostic control"
      assert body =~ "How it works"
      assert body =~ "Ready to govern"
    end

    test "renders the org → workspace → session tree for signed-in users", %{
      conn: conn,
      user: user
    } do
      {:ok, org} =
        Accounts.create_org_with_owner(user.id, %{name: "Acme Corp", slug: "acme-corp"})

      workspace = create_workspace(org, "Platform")
      session = create_session(workspace, "Launch checklist")

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get(~p"/")

      body = html_response(conn, 200)

      assert body =~ "Home"
      assert body =~ "Acme Corp"
      assert body =~ "Platform"
      assert body =~ "Launch checklist"
      assert body =~ ~p"/#{org.slug}"
      assert body =~ ~p"/#{org.slug}/workspaces/#{workspace.slug}"
      assert body =~ ~p"/sessions/#{session.id}"
      refute body =~ "Turn team knowledge into"
    end

    test "tree shows only orgs where the user has an active membership", %{
      conn: conn,
      user: user
    } do
      {:ok, mine} = Accounts.create_org_with_owner(user.id, %{name: "Mine Co", slug: "mine-co"})
      workspace = create_workspace(mine, "Core")
      session = create_session(workspace, "My session")

      {:ok, other} = Accounts.create_user(%{email: "other@example.com"})
      {:ok, _} = Accounts.create_org_with_owner(other.id, %{name: "Theirs Co", slug: "theirs-co"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get(~p"/")

      body = html_response(conn, 200)

      assert body =~ "Mine Co"
      assert body =~ "My session"
      assert body =~ ~p"/sessions/#{session.id}"
      refute body =~ "Theirs Co"
    end

    test "tree renders nested empty states for a member with an empty org", %{
      conn: conn,
      user: user
    } do
      {:ok, _} = Accounts.create_org_with_owner(user.id, %{name: "Empty Co", slug: "empty-co"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get(~p"/")

      body = html_response(conn, 200)

      assert body =~ "Empty Co"
      assert body =~ "No workspaces yet."
    end

    test "tree renders the org-less empty state for a member with no orgs", %{conn: conn} do
      {:ok, fresh} = Accounts.create_user(%{email: "fresh@example.com"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => fresh.id})
        |> get(~p"/")

      body = html_response(conn, 200)

      assert body =~ "No organizations yet."
      assert body =~ ~p"/organizations"
      assert body =~ ~p"/sessions/start"
    end
  end

  test "GET /getting-started renders the guide with install channels", %{conn: conn} do
    conn = get(conn, ~p"/getting-started")
    body = html_response(conn, 200)

    assert body =~ "Install to first finding in five minutes"
    assert body =~ "controlkeel attach opencode"
    assert body =~ "controlkeel setup"
    assert body =~ "controlkeel attach doctor"
    assert body =~ "controlkeel provider doctor"
    assert body =~ "controlkeel status"
    assert body =~ "controlkeel findings"
    assert body =~ "Local stdio MCP exposes the full local tool set"
    assert body =~ "Quick start"
    assert body =~ "Available where"
    assert body =~ "How it governs"
    assert body =~ "Other supported agents"
    assert body =~ "Project rescue"
  end

  describe "legacy org redirects" do
    test "GET /organizations/:slug redirects to /:slug", %{conn: conn} do
      conn = get(conn, "/organizations/acme-corp")

      assert redirected_to(conn, 302) == "/acme-corp"
    end

    test "GET /organizations/:slug/settings redirects to /:slug/settings", %{conn: conn} do
      conn = get(conn, "/organizations/acme-corp/settings")

      assert redirected_to(conn, 302) == "/acme-corp/settings"
    end
  end

  describe "workspace observability resolvers (local mode)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    test "no sessions falls back to the seeded default workspace", %{conn: conn} do
      conn = get(conn, "/observability/loop")

      assert redirected_to(conn, 302) ==
               "/#{LocalDefaults.default_org_slug()}/workspaces/#{LocalDefaults.default_workspace_slug()}/observability/loop"
    end

    test "query string survives the happy-path redirect", %{conn: conn} do
      {:ok, org} = Accounts.create_org(%{name: "Local Org", slug: "local-org"})
      workspace = create_workspace(org, "Local Workspace")
      create_session(workspace, "Local session")

      conn = get(conn, "/observability/loop?days=30")

      assert redirected_to(conn, 302) ==
               "/local-org/workspaces/local-workspace/observability/loop?days=30"
    end
  end

  describe "workspace observability resolvers (cloud mode)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    test "anonymous visitors go to /auth/login", %{conn: conn} do
      conn = get(conn, "/observability/loop")

      assert redirected_to(conn, 302) == "/auth/login"
    end

    test "signed-in users without memberships land on /organizations", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "orgless@example.com"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get("/observability/loop")

      assert redirected_to(conn, 302) == "/organizations"
      assert conn.assigns.flash["info"] =~ "Join or create an organization"
    end

    test "members with a workspace but no sessions land on their workspace", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "newsession@example.com"})

      {:ok, org} =
        Accounts.create_org_with_owner(user.id, %{name: "New Org", slug: "new-org"})

      create_workspace(org, "New Workspace")

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get("/observability/loop")

      assert redirected_to(conn, 302) ==
               "/new-org/workspaces/new-workspace/observability/loop"
    end

    test "members with no workspaces anywhere still land on /organizations", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "noworkspace@example.com"})

      {:ok, _} =
        Accounts.create_org_with_owner(user.id, %{name: "Bare Org", slug: "bare-org"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get("/observability/loop")

      assert redirected_to(conn, 302) == "/organizations"
    end

    test "cloud resolution selects the newest accessible workspace", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "multiws@example.com"})

      {:ok, org} =
        Accounts.create_org_with_owner(user.id, %{name: "Multi Org", slug: "multi-org"})

      old_workspace = create_workspace(org, "Old Workspace")
      new_workspace = create_workspace(org, "New Workspace")

      old_session = create_session(old_workspace, "Old session")

      # Backdate so ordering is deterministic (inserted_at is second-precision).
      old_session
      |> Ecto.Changeset.change(
        inserted_at:
          DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      create_session(new_workspace, "New session")

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get("/observability/loop")

      assert redirected_to(conn, 302) ==
               "/multi-org/workspaces/new-workspace/observability/loop"
    end

    test "a newer cross-tenant session never wins over the accessible workspace", %{
      conn: conn
    } do
      {:ok, user} = Accounts.create_user(%{email: "member@example.com"})

      {:ok, org} =
        Accounts.create_org_with_owner(user.id, %{name: "Member Org", slug: "member-org"})

      workspace = create_workspace(org, "Member Workspace")
      own_session = create_session(workspace, "Own session")

      {:ok, outsider} = Accounts.create_user(%{email: "outsider@example.com"})

      {:ok, other_org} =
        Accounts.create_org_with_owner(outsider.id, %{name: "Other Org", slug: "other-org"})

      other_workspace = create_workspace(other_org, "Other Workspace")
      create_session(other_workspace, "Foreign session")

      # Backdate the accessible session so the cross-tenant one is strictly
      # newest. Pre-scoping already excludes foreign workspaces from the
      # resolver's candidate list; this pins the tenant boundary even when
      # the foreign session sorts first.
      own_session
      |> Ecto.Changeset.change(
        inserted_at:
          DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get("/observability/loop")

      assert redirected_to(conn, 302) ==
               "/member-org/workspaces/member-workspace/observability/loop"
    end
  end
end
