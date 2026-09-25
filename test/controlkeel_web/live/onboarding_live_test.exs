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
             form(view, "#onboarding-wizard-form",
               launch: %{"occupation" => "healthcare", "agent" => "claude"}
             )
           ) =~ "Describe the product"

    assert render_submit(
             form(view, "#onboarding-wizard-form",
               launch: %{
                 "project_name" => "Clinic Intake",
                 "idea" =>
                   "Build a patient intake workflow for a small clinic with staff review and exports."
               }
             )
           ) =~ "Answer the guided interview"

    review_html =
      render_submit(
        form(view, "#onboarding-wizard-form",
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
    {path, flash} = assert_redirect(view)

    assert path =~ "/sessions/"
    assert flash["info"] =~ ~s(Session "Clinic Intake" created in )
    assert flash["info"] =~ "."
    # The launch marker keeps the attach banner alive on the session page.
    assert path =~ "?launched=1"

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

    render_submit(
      form(view, "#onboarding-wizard-form",
        launch: %{"occupation" => "founder", "agent" => "claude"}
      )
    )

    error_html =
      render_submit(
        form(view, "#onboarding-wizard-form",
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

    render_submit(
      form(view, "#onboarding-wizard-form",
        launch: %{"occupation" => "founder", "agent" => "claude"}
      )
    )

    error_html =
      render_submit(
        form(view, "#onboarding-wizard-form",
          launch: %{"project_name" => "Tiny", "idea" => "short"}
        )
      )

    assert error_html =~
             "Describe the product in a few concrete sentences (at least 12 characters)."

    refute error_html =~ "sk-secret-test"
  end

  test "review step explains heuristic mode and provider status without leaking secrets", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    render_submit(
      form(view, "#onboarding-wizard-form",
        launch: %{"occupation" => "founder", "agent" => "claude"}
      )
    )

    render_submit(
      form(view, "#onboarding-wizard-form",
        launch: %{
          "project_name" => "Ops Console",
          "idea" =>
            "Build an internal ops console with approvals, audit notes, and delivery tracking."
        }
      )
    )

    review_html =
      render_submit(
        form(view, "#onboarding-wizard-form",
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
    assert review_html =~ "Governance that will apply"
    assert review_html =~ "Open Questions"
    refute review_html =~ "sk-secret-test"
  end

  test "expanded domain occupations render and advance through onboarding", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/sessions/start")

    assert html =~ "Domain pack:"

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
        form(view, "#onboarding-wizard-form",
          launch: %{"occupation" => "marketing", "agent" => "claude"}
        )
      )

    assert next_html =~ "Describe the product"
  end

  test "onboarding creates the session in the default workspace", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sessions/start")

    assert render_submit(
             form(view, "#onboarding-wizard-form",
               launch: %{"occupation" => "founder", "agent" => "claude"}
             )
           ) =~ "Describe the product"

    assert render_submit(
             form(view, "#onboarding-wizard-form",
               launch: %{
                 "project_name" => "Portal Rebuild",
                 "idea" =>
                   "Rebuild the internal portal with workflow, approvals, and audit notes."
               }
             )
           ) =~ "Answer the guided interview"

    render_submit(
      form(view, "#onboarding-wizard-form",
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
    render_submit(
      form(view, "#onboarding-wizard-form",
        launch: %{"occupation" => "founder", "agent" => "claude"}
      )
    )

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
      # Memberless users never reach the launcher: require_cloud_auth
      # redirects them to /organizations where they can join or create one
      # (issue #141, R3).
      user = user_fixture()

      assert {:error, {:redirect, %{to: "/organizations"}}} =
               live(cloud_conn(user, nil), ~p"/sessions/start")
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
      refute html =~ "Owned Org"
      refute html =~ ">Core<"
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws.id}\"]")

      html =
        render_submit(
          form(view, "#onboarding-wizard-form",
            launch: %{"occupation" => "founder", "agent" => "claude"}
          )
        )

      refute html =~ "Owned Org"
      assert html =~ "Choose the domain and primary agent"

      # The /organizations index still lists the org for the member.
      assert {:ok, _orgs_view, orgs_html} = live(cloud_conn(member, org.id), ~p"/organizations")
      assert orgs_html =~ "Owned Org"
    end

    test "org picker lists only orgs with an active owner or admin membership", %{} do
      user = user_fixture()

      {:ok, owned} =
        Accounts.create_org_with_owner(user.id, %{name: "Owned Co", slug: "owned-co"})

      {:ok, administered} =
        Accounts.create_org_with_owner(user_fixture().id, %{name: "Admin Co", slug: "admin-co"})

      {:ok, viewed} =
        Accounts.create_org_with_owner(user_fixture().id, %{name: "Viewed Co", slug: "viewed-co"})

      {:ok, revoked} =
        Accounts.create_org_with_owner(user_fixture().id, %{
          name: "Revoked Co",
          slug: "revoked-co"
        })

      add_membership(user, administered, "admin", "active")
      add_membership(user, viewed, "viewer", "active")
      # An admin membership that was revoked must not grant access.
      add_membership(user, revoked, "admin", "revoked")

      {:ok, view, html} = live(cloud_conn(user, nil), ~p"/sessions/start")

      assert has_element?(view, "#onboarding-org-select option[value=\"#{owned.id}\"]")
      assert has_element?(view, "#onboarding-org-select option[value=\"#{administered.id}\"]")
      refute has_element?(view, "#onboarding-org-select option[value=\"#{viewed.id}\"]")
      refute has_element?(view, "#onboarding-org-select option[value=\"#{revoked.id}\"]")
      refute html =~ "Viewed Co"
      refute html =~ "Revoked Co"
    end

    test "blocks onboarding when the selected org has no workspaces", %{} do
      user = user_fixture()
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "No WS", slug: "no-ws"})

      {:ok, view, html} = live(cloud_conn(user, org.id), ~p"/sessions/start")

      assert html =~ "Organization and workspace"
      assert html =~ "has no workspaces yet"

      html =
        render_submit(
          form(view, "#onboarding-wizard-form",
            launch: %{"occupation" => "founder", "agent" => "claude"}
          )
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
               form(view, "#onboarding-wizard-form",
                 launch: %{"occupation" => "founder", "agent" => "claude"}
               )
             ) =~ "Describe the product"

      assert render_submit(
               form(view, "#onboarding-wizard-form",
                 launch: %{
                   "project_name" => "Cloud Portal",
                   "idea" => "Build a portal with workflow, approvals, and audit notes."
                 }
               )
             ) =~ "Answer the guided interview"

      render_submit(
        form(view, "#onboarding-wizard-form",
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

      # The selects must live inside a form: LV 1.x clients refuse to push
      # phx-change for form-less inputs, which strands the workspace options.
      assert has_element?(view, "#onboarding-scope-form #onboarding-org-select")
      assert has_element?(view, "#onboarding-scope-form #onboarding-workspace-select")

      assert has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_a.id}\"]")
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_b.id}\"]")

      # Dispatch through the element so the phx-change binding and the
      # browser-shaped payload (%{"org_id" => id, "_target" => "org_id"})
      # are exercised, not just the handler.
      org_select = element(view, "#onboarding-org-select")

      render_change(org_select, %{
        "org_id" => to_string(org_b.id),
        "_target" => "org_id"
      })

      assert has_element?(view, "#onboarding-org-select option[value=\"#{org_b.id}\"]")
      assert has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_b.id}\"]")
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_a.id}\"]")

      # Switching back also repopulates.
      render_change(org_select, %{"org_id" => to_string(org_a.id), "_target" => "org_id"})

      assert has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_a.id}\"]")
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{ws_b.id}\"]")
    end

    test "?org_slug/?ws_slug pre-select the scope for an admin (issue #183)", %{} do
      user = user_fixture()
      {:ok, org_a} = Accounts.create_org_with_owner(user.id, %{name: "Param A", slug: "param-a"})
      {:ok, org_b} = Accounts.create_org_with_owner(user.id, %{name: "Param B", slug: "param-b"})
      ws_a1 = workspace_fixture(%{org_id: org_a.id, name: "A One", slug: "a-one"})
      ws_a2 = workspace_fixture(%{org_id: org_a.id, name: "A Two", slug: "a-two"})
      ws_b = workspace_fixture(%{org_id: org_b.id, name: "Bee", slug: "bee"})

      # No params: defaults — first admin org + its first workspace.
      {:ok, view, html} = live(cloud_conn(user, nil), ~p"/sessions/start")

      assert has_element?(view, "#onboarding-org-select option[value=\"#{org_a.id}\"][selected]")

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws_a1.id}\"][selected]"
             )

      refute html =~ "not available"

      # Both params: exact pre-selection.
      {:ok, view, html} =
        live(
          cloud_conn(user, nil),
          ~p"/sessions/start?#{%{org_slug: "param-a", ws_slug: "a-two"}}"
        )

      assert has_element?(view, "#onboarding-org-select option[value=\"#{org_a.id}\"][selected]")

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws_a2.id}\"][selected]"
             )

      refute html =~ "not available"

      # Org-only param (org-scope header button): org + first workspace.
      {:ok, _view, html} =
        live(cloud_conn(user, nil), ~p"/sessions/start?#{%{org_slug: "param-b"}}")

      assert html =~ "Param B"
      assert html =~ "Bee"
    end

    test "invalid or unauthorized scope params keep the defaults with a notice (issue #183)",
         %{} do
      user = user_fixture()
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Mine", slug: "mine"})
      ws = workspace_fixture(%{org_id: org.id, name: "Solo", slug: "solo"})

      other = user_fixture()
      {:ok, theirs} = Accounts.create_org_with_owner(other.id, %{name: "Theirs", slug: "theirs"})
      add_membership(user, theirs, "member", "active")
      their_ws = workspace_fixture(%{org_id: theirs.id, name: "Nope", slug: "nope"})

      # Unknown org slug.
      {:ok, view, html} = live(cloud_conn(user, nil), ~p"/sessions/start?#{%{org_slug: "ghost"}}")

      assert html =~ "Organization &quot;ghost&quot; is not available to you"
      assert has_element?(view, "#onboarding-org-select option[value=\"#{org.id}\"][selected]")

      # Non-admin org: the param is ignored even though the user is a member.
      {:ok, view, html} =
        live(cloud_conn(user, nil), ~p"/sessions/start?#{%{org_slug: "theirs", ws_slug: "nope"}}")

      assert html =~ "is not available to you"
      assert has_element?(view, "#onboarding-org-select option[value=\"#{org.id}\"][selected]")
      refute has_element?(view, "#onboarding-workspace-select option[value=\"#{their_ws.id}\"]")

      # Valid org, foreign workspace slug.
      {:ok, view, html} =
        live(cloud_conn(user, nil), ~p"/sessions/start?#{%{org_slug: "mine", ws_slug: "nope"}}")

      assert html =~ "does not belong to that organization"
      assert has_element?(view, "#onboarding-org-select option[value=\"#{org.id}\"][selected]")

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws.id}\"][selected]"
             )
    end

    test "picker errors keep the previous valid selection (issue #183)", %{} do
      user = user_fixture()
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Stable", slug: "stable"})
      _ws_one = workspace_fixture(%{org_id: org.id, name: "One", slug: "one"})
      ws_two = workspace_fixture(%{org_id: org.id, name: "Two", slug: "two"})

      {:ok, view, _html} = live(cloud_conn(user, nil), ~p"/sessions/start")

      org_select = element(view, "#onboarding-org-select")
      ws_select = element(view, "#onboarding-workspace-select")

      # Pick the second workspace, then re-select the same org: the choice
      # survives instead of resetting to the first workspace.
      render_change(ws_select, %{
        "workspace_id" => to_string(ws_two.id),
        "_target" => "workspace_id"
      })

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws_two.id}\"][selected]"
             )

      render_change(org_select, %{"org_id" => to_string(org.id), "_target" => "org_id"})

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws_two.id}\"][selected]"
             )

      # Malformed org/workspace ids never blank the selects.
      render_change(org_select, %{"org_id" => "999999", "_target" => "org_id"})

      assert has_element?(view, "#onboarding-org-select option[value=\"#{org.id}\"][selected]")

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws_two.id}\"][selected]"
             )

      assert render(view) =~ "That organization is not available."

      render_change(ws_select, %{"workspace_id" => "bogus", "_target" => "workspace_id"})

      assert has_element?(
               view,
               "#onboarding-workspace-select option[value=\"#{ws_two.id}\"][selected]"
             )

      assert render(view) =~ "That workspace is not available."
    end

    test "recent sessions and continue-from-session stay scoped to the viewer (issue #183)",
         %{} do
      user = user_fixture()
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Scoped", slug: "scoped"})
      ws = workspace_fixture(%{org_id: org.id, name: "Main", slug: "main"})
      session_fixture(%{workspace: ws, title: "My Recent Session"})

      other = user_fixture()
      {:ok, other_org} = Accounts.create_org_with_owner(other.id, %{name: "Far", slug: "far"})
      other_ws = workspace_fixture(%{org_id: other_org.id, name: "Far WS", slug: "far-ws"})
      foreign = session_fixture(%{workspace: other_ws, title: "Someone Elses Session"})

      {:ok, view, _html} = live(cloud_conn(user, org.id), ~p"/sessions/start")

      # The continue-from-session picker lives on step 2.
      html =
        render_submit(
          form(view, "#onboarding-wizard-form",
            launch: %{"occupation" => "founder", "agent" => "claude"}
          )
        )

      assert html =~ "My Recent Session"
      refute html =~ "Someone Elses Session"

      recent_select = element(view, "#onboarding-recent-session-select")

      # A foreign session id is denied (and never leaks its brief), and a
      # non-numeric id errors instead of crashing the LiveView.
      render_change(recent_select, %{
        "recent_mission_id" => to_string(foreign.id),
        "_target" => "recent_mission_id"
      })

      assert has_element?(view, "#onboarding-org-select option[value=\"#{org.id}\"][selected]")
      assert render(view) =~ "Selected session not found."

      render_change(recent_select, %{
        "recent_mission_id" => "not-a-number",
        "_target" => "recent_mission_id"
      })

      assert render(view) =~ "Selected session not found."
    end
  end

  defp add_membership(user, org, role, status) do
    {:ok, _} =
      ControlKeel.Accounts.Membership.changeset(%ControlKeel.Accounts.Membership{}, %{
        user_id: user.id,
        org_id: org.id,
        role: role,
        status: status,
        accepted_at: DateTime.utc_now()
      })
      |> ControlKeel.Repo.insert()
  end
end
