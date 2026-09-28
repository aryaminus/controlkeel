defmodule ControlKeelWeb.ObservabilityEvalsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Observability
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

    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/evals")

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

    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/evals")

    view
    |> element("#observability-evals-save")
    |> render_click()

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Nothing new to save"
  end

  test "unknown workspace slug redirects instead of crashing", %{conn: conn} do
    {org, _ws, _session} = org_bound_session_fixture()

    assert {:error,
            {:live_redirect, %{to: "/organizations", flash: %{"error" => "Workspace not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/no-such-ws/evals")
  end

  test "mismatched org slug redirects", %{conn: conn} do
    {_org, ws, _session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/organizations"}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/evals")
  end

  describe "cloud mode role gates" do
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

    defp cloud_evals_setup(suffix) do
      {:ok, org} = Accounts.create_org(%{name: "EvalCo #{suffix}", slug: "evalco-#{suffix}"})

      {:ok, admin} = Accounts.create_user(%{email: "evals-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} = Accounts.create_user(%{email: "evals-viewer-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: viewer.id,
        org_id: org.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      ws = workspace_fixture(%{org_id: org.id})
      session = session_fixture(%{workspace: ws})

      finding_fixture(%{
        session: session,
        title: "Eval candidate finding",
        severity: "high",
        status: "open",
        category: "security",
        rule_id: "security.evals"
      })

      %{org: org, workspace: ws, admin: admin, viewer: viewer}
    end

    defp session_conn(conn, user, org) do
      Plug.Test.init_test_session(conn, %{
        "current_user_id" => user.id,
        "current_org_id" => org.id
      })
    end

    test "viewers keep read access to the evals page", %{conn: conn} do
      %{org: org, workspace: ws, viewer: viewer} =
        cloud_evals_setup(System.unique_integer([:positive]))

      {:ok, _view, html} =
        live(session_conn(conn, viewer, org), "/#{org.slug}/workspaces/#{ws.slug}/evals")

      assert html =~ "Eval candidates"
    end

    test "viewers cannot save candidates", %{conn: conn} do
      %{org: org, workspace: ws, viewer: viewer} =
        cloud_evals_setup(System.unique_integer([:positive]))

      {:ok, view, _html} =
        live(session_conn(conn, viewer, org), "/#{org.slug}/workspaces/#{ws.slug}/evals")

      view
      |> element("#observability-evals-save")
      |> render_click()

      assert render(view) =~ "Admin or owner role required."
      assert Observability.saved_eval_candidates(workspace_id: ws.id).count == 0
    end

    test "admins can save candidates", %{conn: conn} do
      %{org: org, workspace: ws, admin: admin} =
        cloud_evals_setup(System.unique_integer([:positive]))

      {:ok, view, _html} =
        live(session_conn(conn, admin, org), "/#{org.slug}/workspaces/#{ws.slug}/evals")

      view
      |> element("#observability-evals-save")
      |> render_click()

      assert render(view) =~ "Saved 1 candidate(s)"
    end
  end
end
