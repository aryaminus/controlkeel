defmodule ControlKeelWeb.ReviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission

  test "review live renders alignment context from plan refinement", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    task =
      task_fixture(%{session: session, status: "queued", title: "Collaborative review packet"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Implementation plan with human context",
               "research_summary" => "Mapped review and plan-refinement seams.",
               "alignment_context" => [
                 "PM confirmed the rollout should stay behind approval gates.",
                 "Support asked for reviewer-visible rollback notes before merge."
               ],
               "consulted_roles" => ["PM", "Support", "Security"],
               "options_considered" => ["Patch review packet", "Create separate planning surface"],
               "selected_option" => "Patch review packet",
               "rejected_options" => ["Create separate planning surface"],
               "implementation_steps" => [
                 "Persist alignment fields",
                 "Render them in browser review"
               ],
               "validation_plan" => ["mix test test/controlkeel_web/live/review_live_test.exs"]
             })

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, %{id: review.session_id}, "/reviews/#{review.id}"))

    assert html =~ "Human context gathered before execution"
    assert html =~ "PM confirmed the rollout should stay behind approval gates."
    assert html =~ "Support asked for reviewer-visible rollback notes before merge."
    assert html =~ "PM"
    assert html =~ "Support"
    assert html =~ "Security"
  end

  test "review live renders semantic boundary fields from plan refinement", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Semantic boundary review"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Implementation plan with semantic boundaries",
               "research_summary" => "Mapped review metadata rendering.",
               "options_considered" => ["Render metadata", "Leave MCP-only"],
               "selected_option" => "Render metadata",
               "rejected_options" => ["Leave MCP-only"],
               "implementation_steps" => ["Add card", "Test rendering"],
               "validation_plan" => ["mix test test/controlkeel_web/live/review_live_test.exs"],
               "allowed_semantic_changes" => ["Add review metadata display"],
               "forbidden_semantic_changes" => ["Change execution gating behavior"],
               "invariant_boundaries" => ["Approved plans still gate execution"],
               "requires_reapproval_if" => ["Planner semantics change"],
               "harness_quality_checks" => ["Proof metadata is preserved"]
             })

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, %{id: review.session_id}, "/reviews/#{review.id}"))

    assert html =~ "Agent execution guardrails"
    assert html =~ "Allowed semantic changes"
    assert html =~ "Add review metadata display"
    assert html =~ "Forbidden semantic changes"
    assert html =~ "Change execution gating behavior"
    assert html =~ "Invariant boundaries"
    assert html =~ "Approved plans still gate execution"
    assert html =~ "Requires re-approval if"
    assert html =~ "Planner semantics change"
    assert html =~ "Harness quality checks"
    assert html =~ "Proof metadata is preserved"
  end

  test "review live renders respond header controls, textareas, and audit trail timeline", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Respond UI test"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Plan submission for UI test"
             })

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, %{id: review.session_id}, "/reviews/#{review.id}"))

    assert html =~ "Respond"
    assert html =~ "Pending"
    assert html =~ "Approve"
    assert html =~ "Deny"
    assert html =~ "Feedback notes"
    assert html =~ "Annotations"
    assert html =~ "placeholder=\"Add notes...\""
    assert html =~ "Audit trail"
    assert html =~ "Submitted"
  end

  test "respond with no review loaded flashes an error instead of raising" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, review: nil, flash: %{}}
    }

    assert {:noreply, socket} =
             ControlKeelWeb.ReviewLive.handle_event(
               "respond",
               %{
                 "review_response" => %{"decision" => "approved"}
               },
               socket
             )

    assert socket.assigns.flash["error"] == "Review not found."
  end

  test "review live renders later resubmissions as revisions", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Revision rendering"})

    assert {:ok, parent} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Original plan submission",
               "title" => "Original plan"
             })

    assert {:ok, revision} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Revised plan submission",
               "title" => "Revised plan",
               "previous_review_id" => parent.id
             })

    {:ok, view, html} =
      live(conn, org_session_path(org, ws, %{id: parent.session_id}, "/reviews/#{parent.id}"))

    assert html =~ "Revisions"
    assert html =~ "Later resubmissions of this review"
    assert html =~ "Revised plan"

    assert view
           |> element("#review-revisions-card a[href*='reviews/#{revision.id}']")
           |> render()

    assert html =~ String.capitalize(revision.status)
  end

  test "review live rejects reviews from sessions outside the current org", %{conn: conn} do
    # Cloud-mode org scoping: the session belongs to a workspace of another
    # org, so the signed-in user must not see the review (issue #83).
    original = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original)
      end
    end)

    alias ControlKeel.Accounts
    alias ControlKeel.Repo

    {:ok, my_org} =
      Accounts.create_org(%{name: "Mine", slug: "mine-#{System.unique_integer([:positive])}"})

    {:ok, user} =
      Accounts.create_user(%{email: "me-#{System.unique_integer([:positive])}@example.com"})

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: my_org.id,
      role: "admin",
      status: "active"
    })
    |> Repo.insert!()

    {:ok, other_org} =
      Accounts.create_org(%{name: "Theirs", slug: "theirs-#{System.unique_integer([:positive])}"})

    other_workspace = workspace_fixture(%{org_id: other_org.id})
    other_session = session_fixture(%{workspace: other_workspace})

    task = task_fixture(%{session: other_session, status: "queued", title: "Cross-org plan"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Should be invisible cross-org"
             })

    conn =
      conn
      |> Plug.Test.init_test_session(%{current_user_id: user.id, current_org_id: my_org.id})

    {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Review not found."}}}} =
      live(
        conn,
        "/#{other_org.slug}/workspaces/#{other_workspace.slug}/sessions/#{other_session.id}/reviews/#{review.id}"
      )
  end

  test "review live denies cross-org access with a user-only session (issue #141, R5)", %{
    conn: conn
  } do
    # Same shape as above, but the session map carries only current_user_id —
    # the production shape, since nothing ever writes current_org_id. The
    # socket must derive the default org (org B) and still deny the org-A
    # review.
    original = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original)
      end
    end)

    alias ControlKeel.Accounts
    alias ControlKeel.Repo

    {:ok, my_org} =
      Accounts.create_org(%{name: "Mine", slug: "mine2-#{System.unique_integer([:positive])}"})

    {:ok, user} =
      Accounts.create_user(%{email: "me2-#{System.unique_integer([:positive])}@example.com"})

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: my_org.id,
      role: "viewer",
      status: "active"
    })
    |> Repo.insert!()

    {:ok, other_org} =
      Accounts.create_org(%{
        name: "Theirs",
        slug: "theirs2-#{System.unique_integer([:positive])}"
      })

    other_workspace = workspace_fixture(%{org_id: other_org.id})
    other_session = session_fixture(%{workspace: other_workspace})

    task = task_fixture(%{session: other_session, status: "queued", title: "No-seed plan"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Should be invisible without seeded org"
             })

    conn = conn |> Plug.Test.init_test_session(%{current_user_id: user.id})

    {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Review not found."}}}} =
      live(
        conn,
        "/#{other_org.slug}/workspaces/#{other_workspace.slug}/sessions/#{other_session.id}/reviews/#{review.id}"
      )
  end

  test "review detail renders the session sidebar with Reviews active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Sidebar nav check"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Plan submission for sidebar check"
             })

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, %{id: review.session_id}, "/reviews/#{review.id}"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Deploy review"
    refute html =~ "Service accounts"
  end
end
