defmodule ControlKeelWeb.ObservabilityEvalsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  test "save button flashes a summary after saving candidates", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.evals"
    })

    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability/evals")

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Saved 1 candidate(s)"
  end

  test "repeat save flashes a nothing-new message", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.evals"
    })

    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability/evals")

    view
    |> element("#observability-evals-save")
    |> render_click()

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Nothing new to save"
  end

  describe "save-candidates authorization (cloud mode)" do
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

    setup %{conn: conn} do
      suffix = System.unique_integer([:positive])

      {:ok, org} =
        Accounts.create_org(%{name: "EvalsCo #{suffix}", slug: "evalsco-#{suffix}"})

      {:ok, admin} =
        Accounts.create_user(%{email: "evals-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} =
        Accounts.create_user(%{email: "evals-viewer-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: viewer.id,
        org_id: org.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})

      {:ok, conn: conn, org: org, workspace: workspace, admin: admin, viewer: viewer}
    end

    test "viewers see no save button and are denied save-candidates", %{
      conn: conn,
      org: org,
      workspace: workspace,
      viewer: viewer
    } do
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})

      {:ok, view, _html} =
        live(conn, "/#{org.slug}/workspaces/#{workspace.slug}/observability/evals")

      refute has_element?(view, "#observability-evals-save")

      denied_html = render_click(view, "save-candidates")
      assert denied_html =~ "Admin or owner role required."
    end

    test "admins can save candidates", %{
      conn: conn,
      org: org,
      workspace: workspace,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})
      session = session_fixture(%{workspace: workspace})

      finding_fixture(%{
        session: session,
        title: "Cloud eval candidate finding",
        severity: "high",
        status: "open",
        category: "security",
        rule_id: "security.evals_cloud"
      })

      {:ok, view, _html} =
        live(conn, "/#{org.slug}/workspaces/#{workspace.slug}/observability/evals")

      assert has_element?(view, "#observability-evals-save")

      saved_html = render_click(view, "save-candidates")
      assert saved_html =~ "Saved 1 candidate(s)"
    end
  end
end
