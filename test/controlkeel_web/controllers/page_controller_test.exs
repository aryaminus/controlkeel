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

    test "anonymous visitors get the branding page", %{conn: conn} do
      conn = get(conn, ~p"/")
      body = html_response(conn, 200)

      assert body =~ "Turn team knowledge into"
      assert body =~ "Install ControlKeel"
      refute body =~ "data-app-home"
    end

    test "signed-in users get the unified home shell", %{
      conn: conn,
      user: user
    } do
      {:ok, org} =
        Accounts.create_org_with_owner(user.id, %{name: "Acme Corp", slug: "acme-corp"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> get(~p"/")

      body = html_response(conn, 200)

      assert body =~ "data-app-home"
      assert body =~ ~s(data-home-fallback="/#{org.slug}")
      assert body =~ ~s(data-home-has-orgs="true")
      assert body =~ "Opening your workspace"
      refute body =~ "Turn team knowledge into"
    end

    test "signed-in users without an org get the inline creation form", %{
      conn: conn
    } do
      {:ok, fresh} = Accounts.create_user(%{email: "fresh@example.com"})

      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => fresh.id})
        |> get(~p"/")

      body = html_response(conn, 200)

      assert body =~ "data-app-home"
      assert body =~ ~s(data-home-has-orgs="false")
      assert body =~ "No organizations yet"
      assert body =~ ~s(action="/orgs")
      refute body =~ "Turn team knowledge into"
    end
  end

  describe "POST /orgs" do
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

      {:ok, user} = Accounts.create_user(%{email: "creator@example.com"})

      {:ok, user: user}
    end

    test "anonymous visitors are redirected to login", %{conn: conn} do
      conn = post(conn, ~p"/orgs", %{"org" => %{"name" => "Nope"}})

      assert redirected_to(conn, 302) == "/auth/login"
    end

    test "creates the org and lands on it", %{conn: conn, user: user} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> post(~p"/orgs", %{"org" => %{"name" => "Fresh Co"}})

      assert redirected_to(conn, 302) == "/fresh-co"

      assert [%{org: org, role: "owner"}] = Accounts.list_orgs_for_user(user.id)
      assert org.slug == "fresh-co"
    end

    test "failures re-render the home with the form shown", %{conn: conn, user: user} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
        |> post(~p"/orgs", %{"org" => %{"name" => ""}})

      body = html_response(conn, 422)

      assert body =~ "data-app-home"
      assert body =~ ~s(data-home-show-form="true")
      assert body =~ "No organizations yet"
    end
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
