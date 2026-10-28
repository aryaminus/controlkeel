defmodule ControlKeelWeb.OrganizationSettingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Platform

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

  # --- Tab layout ---------------------------------------------------------

  test "renders the general tab with the settings form by default" do
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings")

    assert html =~ "Organization settings sections"
    assert html =~ "org-settings-form"
  end

  test "unknown tab params fall back to the general tab" do
    org = create_org!()

    {:ok, _view, html} = live(build_conn(), ~p"/#{org.slug}/settings?tab=nonsense")

    assert html =~ "org-settings-form"
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

    {:ok, view, _html} = live(build_conn(), ~p"/#{org.slug}/settings")

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
end
