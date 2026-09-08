defmodule ControlKeelWeb.OnboardingLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures
  import ControlKeel.AccountsFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  test "user can complete onboarding, regenerate, and create a mission", %{conn: conn} do
    # The shared (async: false) sandbox may carry sessions from earlier tests;
    # assert against the delta, not an absolute empty list.
    initial_session_count = length(Mission.list_sessions())

    {:ok, view, html} = live(conn, ~p"/sessions/start")

    assert html =~ "Choose the domain and primary agent"
    assert html =~ "Founder / Product Builder"

    assert render_submit(
             form(view, "form", launch: %{"occupation" => "healthcare", "agent" => "claude"})
           ) =~ "Describe the product"

    assert render_submit(
             form(view, "form",
               launch: %{
                 "project_name" => "Clinic Intake",
                 "idea" =>
                   "Build a patient intake workflow for a small clinic with staff review and exports."
               }
             )
           ) =~ "Answer the guided interview"

    review_html =
      render_submit(
        form(view, "form",
          launch: %{
            "interview_answers" => %{
              "who_uses_it" => "Front desk staff and clinic admins",
              "data_involved" => "Patient names, insurance notes, scheduling details",
              "first_release" => "Intake form, review queue, export",
              "constraints" => "Local-first deploy, approval before production"
            }
          }
        )
      )

    assert review_html =~ "Review the compiled brief"
    assert review_html =~ "Acceptance criteria"
    assert review_html =~ "Production boundary"
    assert review_html =~ "Local-first deploy"
    assert review_html =~ "approval before production"
    # Review step must not persist a session.
    assert length(Mission.list_sessions()) == initial_session_count

    regenerated_html = render_click(element(view, "button[phx-click=\"regenerate\"]"))
    assert regenerated_html =~ "Review the compiled brief"
    # Regenerate must not persist a session either.
    assert length(Mission.list_sessions()) == initial_session_count

    render_click(element(view, "button[phx-click=\"accept\"]"))
    {path, _flash} = assert_redirect(view)

    assert path =~ "/sessions/"

    redirected_html =
      conn
      |> Phoenix.ConnTest.recycle()
      |> get(path)
      |> html_response(200)

    assert redirected_html =~ "Clinic Intake"
    # Accept creates exactly one new session.
    assert length(Mission.list_sessions()) == initial_session_count + 1
  end

  test "onboarding UI prevents duplicate project names", %{conn: conn} do
    _session = session_fixture(%{title: "Existing Project"})

    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    error_html =
      render_submit(
        form(view, "form",
          launch: %{
            "project_name" => "Existing Project",
            "idea" => "Build a new portal with workflow."
          }
        )
      )

    assert error_html =~ "This project name is already used by an existing session."
  end

  test "validation errors render and provider keys are not exposed in the browser", %{conn: conn} do
    original = Application.get_env(:controlkeel, ControlKeel.Intent)

    on_exit(fn ->
      if original do
        Application.put_env(:controlkeel, ControlKeel.Intent, original)
      else
        Application.delete_env(:controlkeel, ControlKeel.Intent)
      end
    end)

    Application.put_env(
      :controlkeel,
      ControlKeel.Intent,
      %{
        providers: %{
          openai: %{api_key: "sk-secret-test", base_url: "http://127.0.0.1:1", model: "o3"}
        }
      }
    )

    {:ok, view, html} = live(conn, ~p"/sessions/start")
    refute html =~ "sk-secret-test"

    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    error_html =
      render_submit(form(view, "form", launch: %{"project_name" => "Tiny", "idea" => "short"}))

    assert error_html =~
             "Describe the product in a few concrete sentences (at least 12 characters)."

    refute error_html =~ "sk-secret-test"
  end

  test "review step explains heuristic mode and provider status without leaking secrets", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    render_submit(
      form(view, "form",
        launch: %{
          "project_name" => "Ops Console",
          "idea" =>
            "Build an internal ops console with approvals, audit notes, and delivery tracking."
        }
      )
    )

    review_html =
      render_submit(
        form(view, "form",
          launch: %{
            "interview_answers" => %{
              "who_uses_it" => "Operators and engineering leads",
              "data_involved" => "Internal ticket metadata, release notes, and approval history",
              "first_release" => "Dashboard, approvals, searchable notes",
              "constraints" => "Local-first setup, no API key required for first run"
            }
          }
        )
      )

    assert review_html =~ "Compiler Info"
    assert review_html =~ "Objective"
    assert review_html =~ "Acceptance criteria"
    assert review_html =~ "Production boundary"
    assert review_html =~ "Open Questions"
    refute review_html =~ "sk-secret-test"
  end

  test "expanded domain occupations render and advance through onboarding", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    assert has_element?(view, "option[value=\"hr\"]")
    assert has_element?(view, "option[value=\"legal\"]")
    assert has_element?(view, "option[value=\"marketing\"]")
    assert has_element?(view, "option[value=\"sales\"]")
    assert has_element?(view, "option[value=\"realestate\"]")
    assert has_element?(view, "option[value=\"government\"]")
    assert has_element?(view, "option[value=\"insurance\"]")
    assert has_element?(view, "option[value=\"ecommerce\"]")
    assert has_element?(view, "option[value=\"logistics\"]")
    assert has_element?(view, "option[value=\"manufacturing\"]")
    assert has_element?(view, "option[value=\"nonprofit\"]")

    next_html =
      render_submit(
        form(view, "form", launch: %{"occupation" => "marketing", "agent" => "claude"})
      )

    assert next_html =~ "Describe the product"
    assert next_html =~ "Marketing / Content"
  end

  test "onboarding creates the session in the default workspace", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    assert render_submit(
             form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"})
           ) =~ "Describe the product"

    assert render_submit(
             form(view, "form",
               launch: %{
                 "project_name" => "Portal Rebuild",
                 "idea" =>
                   "Rebuild the internal portal with workflow, approvals, and audit notes."
               }
             )
           ) =~ "Answer the guided interview"

    render_submit(
      form(view, "form",
        launch: %{
          "interview_answers" => %{
            "who_uses_it" => "Internal staff across teams",
            "data_involved" => "Portal content, approvals, and activity logs",
            "first_release" => "Rebuilt navigation, approvals, search",
            "constraints" => "Local-first deploy, approval before merge"
          }
        }
      )
    )

    render_click(element(view, "button[phx-click=\"accept\"]"))
    {path, _flash} = assert_redirect(view)
    assert path =~ "/sessions/"

    session_id =
      path
      |> String.split("/sessions/")
      |> List.last()
      |> String.split("?")
      |> List.first()

    session = Mission.get_session_with_workspace(String.to_integer(session_id))
    assert session.workspace.slug == "default-workspace"
  end

  test "user can continue from an existing session in onboarding", %{conn: conn} do
    session =
      session_fixture(%{
        title: "Saved Project",
        objective: "Original project objective",
        execution_brief: %{
          "idea" => "Original project objective",
          "compiler" => %{
            "interview_answers" => %{
              "who_uses_it" => "Original users",
              "constraints" => "Original constraints"
            }
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    # Step 1
    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    # Step 2: Select the existing session from dropdown
    render_change(view, :select_mission, %{recent_mission_id: to_string(session.id)})

    # Verify project name is populated
    assert has_element?(view, "input[name=\"launch[project_name]\"][value=\"Saved Project\"]")
    assert render(view) =~ "Original project objective"
  end

  describe "cloud mode /sessions/start" do
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

    defp cloud_conn(user, org_id) do
      build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_id" => user.id,
        "current_org_id" => org_id
      })
    end

    test "blocks onboarding when the user has no organizations", %{} do
      user = user_fixture()

      {:ok, view, html} = live(cloud_conn(user, nil), ~p"/sessions/start")

      assert html =~ "Organization and workspace"
      assert html =~ "admin or owner of at least one organization"

      html =
        render_submit(
          form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"})
        )

      assert html =~ "admin or owner of at least one organization"
      assert html =~ "Choose the domain and primary agent"
    end

    test "excludes orgs where the user is only a member or viewer from the picker", %{} do
      owner = user_fixture()
      member = user_fixture()

      {:ok, org} =
        Accounts.create_org_with_owner(owner.id, %{name: "Owned Org", slug: "owned-org"})

      ws = workspace_fixture(%{org_id: org.id, name: "Core", slug: "core"})

      {:ok, _membership} =
        ControlKeel.Accounts.Membership.changeset(%ControlKeel.Accounts.Membership{}, %{
          user_id: member.id,
          org_id: org.id,
          role: "member",
          status: "active",
          accepted_at: DateTime.utc_now()
        })
        |> ControlKeel.Repo.insert()

      {:ok, view, html} = live(cloud_conn(member, org.id), ~p"/sessions/start")

      assert html =~ "Organization and workspace"
      assert html =~ "admin or owner of at least one organization"
      # Scope to main content: the sidebar context switcher legitimately
      # lists orgs the user belongs to (including member/viewer roles).
      main = view |> element("main") |> render()
      refute main =~ "Owned Org"
      refute main =~ ">Core<"
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws.id}\"]")

      html =
        render_submit(
          form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"})
        )

      main = view |> element("main") |> render()
      refute main =~ "Owned Org"
      assert html =~ "Choose the domain and primary agent"

      # The /organizations index still lists the org for the member.
      assert {:ok, _orgs_view, orgs_html} = live(cloud_conn(member, org.id), ~p"/organizations")
      assert orgs_html =~ "Owned Org"
    end

    test "blocks onboarding when the selected org has no workspaces", %{} do
      user = user_fixture()
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "No WS", slug: "no-ws"})

      {:ok, view, html} = live(cloud_conn(user, org.id), ~p"/sessions/start")

      assert html =~ "Organization and workspace"
      assert html =~ "has no workspaces yet"

      html =
        render_submit(
          form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"})
        )

      assert html =~ "has no workspaces yet"
      assert html =~ "Choose the domain and primary agent"
    end

    test "renders the org/workspace selector and creates the mission in the selected workspace",
         %{} do
      user = user_fixture()
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Acme", slug: "acme"})
      ws = workspace_fixture(%{org_id: org.id, name: "Backend", slug: "backend"})

      {:ok, view, html} = live(cloud_conn(user, org.id), ~p"/sessions/start")

      assert html =~ "Organization and workspace"
      assert has_element?(view, "#onboarding-org-select option[value=\"#{org.id}\"]")
      assert has_element?(view, "#onboarding-workspace-select option[value=\"#{ws.id}\"]")

      assert render_submit(
               form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"})
             ) =~ "Describe the product"

      assert render_submit(
               form(view, "form",
                 launch: %{
                   "project_name" => "Cloud Portal",
                   "idea" => "Build a portal with workflow, approvals, and audit notes."
                 }
               )
             ) =~ "Answer the guided interview"

      render_submit(
        form(view, "form",
          launch: %{
            "interview_answers" => %{
              "who_uses_it" => "Operators across teams",
              "data_involved" => "Portal content, approvals, and audit logs",
              "first_release" => "Portal, approvals, search",
              "constraints" => "Cloud deploy, approval before merge"
            }
          }
        )
      )

      render_click(element(view, "button[phx-click=\"accept\"]"))
      {path, _flash} = assert_redirect(view)
      assert path =~ "/sessions/"

      session_id =
        path
        |> String.split("/sessions/")
        |> List.last()
        |> String.split("?")
        |> List.first()

      session = Mission.get_session_with_workspace(String.to_integer(session_id))
      assert session.workspace_id == ws.id
      assert session.workspace.slug == "backend"
    end

    test "changing the org repopulates the workspace options", %{} do
      user = user_fixture()
      {:ok, org_a} = Accounts.create_org_with_owner(user.id, %{name: "Org A", slug: "org-a"})
      {:ok, org_b} = Accounts.create_org_with_owner(user.id, %{name: "Org B", slug: "org-b"})
      ws_a = workspace_fixture(%{org_id: org_a.id, name: "Alpha WS", slug: "alpha-ws"})
      ws_b = workspace_fixture(%{org_id: org_b.id, name: "Beta WS", slug: "beta-ws"})

      {:ok, view, _html} = live(cloud_conn(user, org_a.id), ~p"/sessions/start")

      assert has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_a.id}\"]")
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_b.id}\"]")

      render_change(view, :select_org, %{org_id: to_string(org_b.id)})

      assert has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_b.id}\"]")
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_a.id}\"]")
    end
  end
end
