defmodule ControlKeelWeb.OrganizationSettingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Platform
  alias ControlKeel.Repo

  defp create_org! do
    {:ok, org} = Accounts.create_org(%{name: "Policies Org", slug: "policies-org"})
    org
  end

  defp create_workspace(org, attrs \\ %{}) do
    MissionFixtures.workspace_fixture(
      Map.merge(%{name: "Core", slug: "core", org_id: org.id}, attrs)
    )
  end

  defp valid_rule(id \\ "shell.destructive_rm_rf") do
    %{
      "id" => id,
      "category" => "security",
      "severity" => "critical",
      "action" => "block",
      "plain_message" => "blocked",
      "matcher" => %{"type" => "regex", "patterns" => ["rm -rf"]}
    }
  end

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp add_active_membership(user_id, org_id, role) do
    %Membership{}
    |> Membership.changeset(%{user_id: user_id, org_id: org_id, role: role, status: "active"})
    |> Repo.insert!()
  end

  defp conn_for(user),
    do: build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

  # --- Tab layout ---------------------------------------------------------

  test "renders the account tab by default" do
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings")

    # Local mode has no user records: the default Account tab shows the
    # migrate-to-cloud notice instead of export/erasure.
    assert html =~ "Settings sections"
    assert html =~ "You need to migrate to cloud mode to use these settings."
    refute html =~ "org-settings-form"
  end

  test "settings sidebar has no org switcher header" do
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings")

    # The settings variant replaces the header with the back row and skips
    # the breadcrumbs header; the user menu stays (it holds the account
    # chrome), only the org switcher is org-page-only.
    refute html =~ "sidebar-org-switcher"
    refute html =~ "breadcrumbs-header"
    assert html =~ "sidebar-user-menu"
    assert html =~ "Settings sections"
  end

  test "unknown tab params fall back to the account tab" do
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=nonsense")

    assert html =~ "You need to migrate to cloud mode to use these settings."
    refute html =~ "org-settings-form"
    refute html =~ "New policy set"
  end

  test "policy_sets tab renders via query param" do
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    assert html =~ "New policy set"
    assert html =~ "View packs"
  end

  test "set_tab patches the URL and switches panels" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=general")

    view
    |> element("button[phx-value-tab='policy_sets']")
    |> render_click()

    assert_patch(view, ~p"/#{org.slug}/settings?tab=policy_sets")
    assert render(view) =~ "New policy set"

    view
    |> element("button[phx-value-tab='general']")
    |> render_click()

    assert_patch(view, ~p"/#{org.slug}/settings?tab=general")
    assert render(view) =~ "org-settings-form"
  end

  # --- Policy sets tab ----------------------------------------------------

  test "toggle_pack ignores unknown pack names" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    before_click = render(view)
    render_click(view, "toggle_pack", %{"name" => "not-a-real-pack"})

    assert render(view) == before_click
  end

  test "toggle_pack expands and collapses baseline pack" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_packs_dialog")

    trigger = element(view, "button[phx-value-name=\"baseline\"]")
    render_click(trigger)

    assert render(view) =~ "Detects secrets, injection, and XSS"

    render_click(trigger)

    refute render(view) =~ "Detects secrets, injection, and XSS"
  end

  test "shows an org-scoped empty state: other orgs' sets are invisible" do
    org = create_org!()

    # A set owned by a different org must not leak into this org's tab.
    {:ok, foreign_org} = Accounts.create_org(%{name: "Foreign", slug: "policies-foreign"})

    {:ok, _foreign_set} =
      Platform.create_policy_set(%{
        "org_id" => foreign_org.id,
        "name" => "foreign-lease",
        "description" => "Owned by another org",
        "rules" => []
      })

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    assert html =~ "No custom policy sets yet"
    refute html =~ "foreign-lease"
  end

  test "lists policy sets with status, rule count, and workspace assignments" do
    org = create_org!()
    ws = create_workspace(org)

    {:ok, set} =
      Platform.create_policy_set(%{
        "org_id" => org.id,
        "name" => "no-rm-rf",
        "description" => "Block destructive deletes",
        "rules" => [valid_rule()]
      })

    {:ok, _assignment} = Platform.apply_policy_set(ws.id, set.id, %{precedence: 10})

    {:ok, view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    assert html =~ "no-rm-rf"
    assert html =~ "active"
    assert html =~ "1 rules"
    assert html =~ "Block destructive deletes"
    assert html =~ "Core (precedence 10"
    assert has_element?(view, "span[title='block, security']", "destructive rm rf")
  end

  test "lists disabled assignments with a marker" do
    org = create_org!()
    ws = create_workspace(org, %{slug: "paused-ws", name: "Paused"})

    {:ok, set} =
      Platform.create_policy_set(%{
        "org_id" => org.id,
        "name" => "paused-set",
        "description" => "Paused controls",
        "rules" => [
          %{
            "id" => "cost.overrun",
            "category" => "cost",
            "severity" => "high",
            "action" => "warn",
            "plain_message" => "over budget",
            "matcher" => %{"type" => "budget", ratio_gte: 1.0}
          }
        ]
      })

    {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{"enabled" => false})

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    assert html =~ "paused-set"
    assert html =~ "Paused (precedence 100, disabled)"
  end

  test "renders pack labels for known domain packs in the packs dialog" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    refute render(view) =~ "Baseline"

    render_click(view, "open_packs_dialog")
    html = render(view)

    assert html =~ "Baseline"
    assert html =~ "Cost"
    assert html =~ "Software"
    assert html =~ "bg-destructive/10"
  end

  test "warn rules show warning class when pack is expanded" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_packs_dialog")
    render_click(element(view, "button[phx-value-name=\"software\"]"))

    assert render(view) =~ "bg-warning/10"
  end

  test "new policy set button opens the create modal" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    refute has_element?(view, "#policy-set-form")

    render_click(view, "open_create_modal")

    assert has_element?(view, "#policy-set-form")
    assert has_element?(view, "#policy-set-create-modal-title")
    assert render(view) =~ "New policy set"
  end

  test "creating a policy set saves it owned by the org and lists it" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")

    rules_json =
      ~s|[{"id": "shell.destructive_rm_rf", "category": "security", "severity": "critical", "action": "block", "plain_message": "blocked", "matcher": {"type": "regex", "patterns": ["rm -rf"]}}]|

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{
        "name" => "no-rm-rf-web",
        "description" => "Block destructive deletes from web",
        "rules_json" => rules_json
      }
    })

    html = render(view)

    assert html =~ "Created policy set #"
    assert html =~ "no-rm-rf-web"

    sets = Platform.list_policy_sets(org.id)
    assert Enum.any?(sets, &(&1.name == "no-rm-rf-web"))
    assert Enum.all?(sets, &(&1.org_id == org.id))
  end

  test "wrapped entries JSON is accepted like the CLI rules file format" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")

    entries =
      ~s|{"entries": [{"id": "cost.overrun", "category": "cost", "severity": "high", "action": "warn", "plain_message": "over budget", "matcher": {"type": "budget", "ratio_gte": 1.0}}]}|

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{
        "name" => "budget-warn-web",
        "description" => nil,
        "rules_json" => entries
      }
    })

    assert render(view) =~ "budget-warn-web"

    set = Enum.find(Platform.list_policy_sets(org.id), &(&1.name == "budget-warn-web"))
    assert length(Platform.PolicySet.rule_entries(set)) == 1
  end

  test "invalid rules JSON keeps the modal open with an error" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{"name" => "broken-json", "rules_json" => "{not json"}
    })

    html = render(view)

    assert has_element?(view, "#policy-set-form")
    assert html =~ "invalid JSON"
    refute Enum.any?(Platform.list_policy_sets(org.id), &(&1.name == "broken-json"))
  end

  test "non-array rules JSON shows a shape error" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")

    render_change(view, "validate_policy_set", %{
      "policy_set" => %{"name" => "shape-check", "rules_json" => "{\"id\": \"one-object\"}"}
    })

    assert render(view) =~ "must be an array of rule entries"
  end

  test "missing name shows validation error without saving" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{"name" => "", "rules_json" => ""}
    })

    html = render(view)

    assert has_element?(view, "#policy-set-form")
    assert html =~ "can&#39;t be blank"
    assert Platform.list_policy_sets(org.id) == []
  end

  test "cancel closes the create modal" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")
    assert has_element?(view, "#policy-set-form")

    render_click(view, "close_create_modal")

    refute has_element?(view, "#policy-set-form")
  end

  test "escape closes the packs dialog" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_packs_dialog")
    assert has_element?(view, "#packs-dialog")

    view |> element("#packs-dialog") |> render_keydown(%{"key" => "escape"})

    refute has_element?(view, "#packs-dialog")
  end

  test "escape closes the create modal" do
    org = create_org!()

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=policy_sets")

    render_click(view, "open_create_modal")
    assert has_element?(view, "#policy-set-form")

    view |> element("#policy-set-create-modal") |> render_keydown(%{"key" => "escape"})

    refute has_element?(view, "#policy-set-form")
  end

  # --- Members tab (moved from the org overview; admin+ by the settings gate) ---

  describe "admin viewer role controls" do
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

      owner = create_user!("owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Acme", slug: "acme"})

      admin = create_user!("admin@example.com")
      admin_m = add_active_membership(admin.id, org.id, "admin")

      member = create_user!("member@example.com")
      member_m = add_active_membership(member.id, org.id, "member")

      viewer = create_user!("viewer@example.com")
      viewer_m = add_active_membership(viewer.id, org.id, "viewer")

      owner_m = Accounts.get_active_membership(owner.id, org.id)

      {:ok,
       memberships: %{owner: owner_m, admin: admin_m, member: member_m, viewer: viewer_m},
       conn: conn_for(admin)}
    end

    test "owner row is locked (disabled)", %{conn: conn, memberships: ms} do
      {:ok, view, _html} = live(conn, ~p"/acme/settings?tab=members")

      form = element(view, "#role-form-#{ms.owner.id}") |> render()
      assert form =~ "disabled"
      assert form =~ ~s(value="owner")
      # An admin cannot reassign an owner to any other role.
      refute form =~ ~s(value="admin")
    end

    test "admin's own row allows self-demotion only (admin/member/viewer, no owner)", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/acme/settings?tab=members")

      form = element(view, "#role-form-#{ms.admin.id}") |> render()
      refute form =~ "disabled"
      # Current role stays visible; owner promotion is withheld.
      assert form =~ ~s(value="admin")
      refute form =~ ~s(value="owner")
      assert form =~ ~s(value="member")
      assert form =~ ~s(value="viewer")
    end

    test "admin can self-demit to viewer", %{conn: conn, memberships: ms} do
      {:ok, view, _html} = live(conn, ~p"/acme/settings?tab=members")

      view
      |> element("#role-form-#{ms.admin.id}")
      |> render_change(role: "viewer")

      assert render(view) =~ "Role updated."
      # Persisted as a demotion (admin -> viewer).
      assert Accounts.get_active_membership(ms.admin.user_id, ms.admin.org_id).role == "viewer"
    end

    test "member and viewer rows offer only member/viewer (no owner/admin)", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/acme/settings?tab=members")

      for target <- [:member, :viewer] do
        form = element(view, "#role-form-#{ms[target].id}") |> render()
        refute form =~ "disabled"
        refute form =~ ~s(value="owner")
        refute form =~ ~s(value="admin")
        assert form =~ ~s(value="member")
        assert form =~ ~s(value="viewer")
      end
    end

    test "admin self-demotion to viewer drops management UI immediately (no reload)", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/acme/settings?tab=members")

      # Sanity: admin can manage before the change.
      assert render(view) =~ ~s(id="role-form-#{ms.member.id}")

      view
      |> element("#role-form-#{ms.admin.id}")
      |> render_change(role: "viewer")

      html_after = render(view)
      assert html_after =~ "Role updated."

      # Demoted to viewer -> no longer admin+: all management controls gone.
      refute html_after =~ "role-form-"
      refute html_after =~ "open_invite"
      refute html_after =~ "confirm_revoke"

      assert Accounts.get_active_membership(ms.admin.user_id, ms.admin.org_id).role == "viewer"
    end

    test "changing another member's role updates that row immediately", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/acme/settings?tab=members")

      view
      |> element("#role-form-#{ms.member.id}")
      |> render_change(role: "viewer")

      assert render(view) =~ "Role updated."
      assert Accounts.get_active_membership(ms.member.user_id, ms.member.org_id).role == "viewer"
    end
  end

  describe "owner viewer role controls" do
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

      owner = create_user!("owner-a@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Omega", slug: "omega"})

      member = create_user!("member-a@example.com")
      add_active_membership(member.id, org.id, "member")

      owner_m = Accounts.get_active_membership(owner.id, org.id)

      {:ok, owner_m: owner_m, conn: conn_for(owner)}
    end

    test "sole owner cannot change their own role (locked)", %{conn: conn, owner_m: owner_m} do
      {:ok, view, _html} = live(conn, ~p"/omega/settings?tab=members")

      form = element(view, "#role-form-#{owner_m.id}") |> render()
      assert form =~ "disabled"
      assert form =~ ~s(value="owner")
    end

    test "owner with another owner can change their own role", %{conn: conn, owner_m: owner_m} do
      # Add a second active owner via direct membership insert.
      org_id = owner_m.org_id
      second = create_user!("owner-b@example.com")
      add_active_membership(second.id, org_id, "owner")

      {:ok, view, _html} = live(conn, ~p"/omega/settings?tab=members")

      form = element(view, "#role-form-#{owner_m.id}") |> render()
      refute form =~ "disabled"
      assert form =~ ~s(value="owner")
      assert form =~ ~s(value="admin")
      assert form =~ ~s(value="viewer")
    end

    test "owner self-demotion to member drops management UI immediately (no reload)", %{
      conn: conn,
      owner_m: owner_m
    } do
      # Need another owner so self-demotion isn't last-owner-protected.
      second = create_user!("owner-c@example.com")
      add_active_membership(second.id, owner_m.org_id, "owner")

      {:ok, view, _html} = live(conn, ~p"/omega/settings?tab=members")

      # Sanity: management controls present before the change.
      html_before = render(view)
      assert html_before =~ ~s(id="role-form-#{owner_m.id}")
      assert html_before =~ "confirm_revoke"

      view
      |> element("#role-form-#{owner_m.id}")
      |> render_change(role: "member")

      html_after = render(view)
      assert html_after =~ "Role updated."

      # Demoted to member -> no longer admin+: role selects and revoke
      # controls disappear from the same LiveView (no reload).
      refute html_after =~ "role-form-"
      refute html_after =~ "confirm_revoke"

      # Persisted.
      assert Accounts.get_active_membership(owner_m.user_id, owner_m.org_id).role == "member"
    end

    test "owner can open the invite modal on the members tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/omega/settings?tab=members")

      assert has_element?(view, "#invite-member-button")

      view
      |> element("#invite-member-button")
      |> render_click()

      assert has_element?(view, "#invite-member-modal")
    end
  end

  describe "members tab in local mode" do
    test "shows the local-mode notice instead of the roster" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      org = create_org!()

      {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=members")

      assert html =~ "Member management is not available in local mode."
      assert html =~ "Switch to cloud or self-hosted mode to invite teammates and manage roles."
    end
  end

  # --- Account tab (docs/dsar-erasure-plan.md, Slice 3) --------------------

  describe "account tab" do
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

      owner = create_user!("owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Acme", slug: "acme"})
      conn = build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})

      {:ok, conn: conn, org: org}
    end

    test "account tab is first in the sidebar and renders export + erasure in cloud mode", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/acme/settings?tab=account")

      assert html =~ "Settings sections"
      # Account sits under the Personal group; the org sections follow in
      # the Organization group (button order proves the grouping).
      assert html =~ "Personal"
      assert html =~ "Organization"
      assert :binary.match(html, ~s(phx-value-tab="account")) |> elem(0) <
               :binary.match(html, ~s(phx-value-tab="general")) |> elem(0)
      assert :binary.match(html, ~s(phx-value-tab="account")) |> elem(0) <
               :binary.match(html, ~s(phx-value-tab="general")) |> elem(0)

      assert html =~ "Download my data"
      assert html =~ ~s(/me/export.json)
      assert html =~ "account-erasure-danger-zone"
      assert html =~ "Erase my account"
    end

    test "member role lands on the account tab and cannot open org sections", %{
      org: org
    } do
      member = create_user!("member-#{System.unique_integer([:positive])}@example.com")
      add_active_membership(member.id, org.id, "member")

      conn = build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => member.id})

      # Account is the default tab: the member renders it directly, with no
      # redirect needed.
      {:ok, _view, html} = live(conn, ~p"/acme/settings")

      assert html =~ "Erase my account"
      # Org sections are admin+: the member's sidebar offers only the
      # Personal group — no org section buttons at all.
      assert html =~ "Personal"
      assert html =~ ~s(phx-value-tab="account")
      refute html =~ ~s(phx-value-tab="general")
      refute html =~ ~s(phx-value-tab="members")
    end
  end

  test "account tab shows the migrate notice in local mode" do
    Application.put_env(:controlkeel, :runtime_mode, :local)
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=account")

    # Local mode has no user records and /me/* is blocked: the tab renders a
    # migrate-to-cloud notice instead of export/erasure.
    assert html =~ "You need to migrate to cloud mode to use these settings."
    assert html =~ ~s(phx-value-tab="account")
    refute html =~ "Erase my account"
    refute html =~ "account-erasure-danger-zone"
  end

  # --- Organization deletion (docs/dsar-erasure-plan.md, Slice 3) ----------

  describe "organization deletion surface in local mode" do
    test "hides the danger zone on the general tab" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      org = create_org!()

      {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=general")

      assert html =~ "Settings sections"
      refute html =~ "org-delete-danger-zone"
      refute html =~ "Delete organization"
    end

    test "refuses delete_org events and keeps the org" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      org = create_org!()

      {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=general")

      # The danger zone is not rendered; a crafted event must be refused
      # server-side without touching data.
      render_submit(view, "delete_org", %{"delete_org" => %{"confirm_slug" => org.slug}})

      assert Repo.get(Accounts.Org, org.id)
    end
  end

  describe "organization deletion in cloud mode" do
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

      owner = create_user!("owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Doomed", slug: "doomed"})

      admin = create_user!("admin@example.com")
      admin_m = add_active_membership(admin.id, org.id, "admin")

      member = create_user!("member@example.com")
      add_active_membership(member.id, org.id, "member")

      owner_conn =
        build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})

      {:ok, org: org, admin_conn: conn_for(admin), admin_m: admin_m, owner_conn: owner_conn}
    end

    test "danger zone is hidden from non-owners", %{admin_conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/doomed/settings?tab=general")

      refute html =~ "org-delete-danger-zone"
      assert html =~ "Doomed"
    end

    test "refuses non-owners server-side", %{admin_conn: conn, admin_m: admin_m} do
      assert admin_m.role == "admin"

      {:ok, view, _html} = live(conn, ~p"/doomed/settings?tab=general")

      # Even a crafted event from a non-owner hits the server-side gate.
      html = render_submit(view, "delete_org", %{"delete_org" => %{"confirm_slug" => "doomed"}})

      assert html =~ "Only organization owners can delete the organization."
      assert Repo.get(Accounts.Org, org_id_from_admin_m(admin_m))
    end

    test "owner deletes the organization and lands on /new/org", %{owner_conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/doomed/settings?tab=general")

      render_submit(view, "delete_org", %{"delete_org" => %{"confirm_slug" => "doomed"}})

      assert_redirect(view, "/new/org")
      assert Repo.get(Accounts.Org, org.id) == nil
    end
  end

  defp org_id_from_admin_m(m), do: m.org_id
end
