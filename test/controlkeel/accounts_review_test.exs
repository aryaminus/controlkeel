defmodule ControlKeel.AccountsReviewTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.MissionFixtures

  setup do
    {:ok, alice} = Accounts.create_user(%{email: "alice@example.com", name: "Alice"})
    {:ok, bob} = Accounts.create_user(%{email: "bob@example.com", name: "Bob"})
    {:ok, carol} = Accounts.create_user(%{email: "carol@example.com", name: "Carol"})
    {:ok, outsider} = Accounts.create_user(%{email: "outsider@example.com", name: "Out"})

    {:ok, org} = Accounts.create_org(%{name: "Team", slug: "team"})

    workspace = MissionFixtures.workspace_fixture()
    {:ok, _} = Accounts.assign_workspace_to_org(workspace.id, org.id)

    session = MissionFixtures.session_fixture(%{workspace: workspace})
    review = MissionFixtures.review_fixture(%{session: session, title: "Plan review"})

    # Activate Alice as admin, Bob as member, Carol as member.
    {alice, "admin"} = activate(alice, org, "admin")
    {bob, "member"} = activate(bob, org, "member")
    {carol, "member"} = activate(carol, org, "member")

    {:ok,
     alice: alice,
     bob: bob,
     carol: carol,
     outsider: outsider,
     org: org,
     workspace: workspace,
     session: session,
     review: review}
  end

  describe "assign_review/3" do
    test "assigns the review to a member and writes an audit event", %{
      review: review,
      alice: alice,
      bob: bob
    } do
      assert {:ok, updated} =
               Accounts.assign_review(review.id, bob.id,
                 actor_user_id: alice.id,
                 note: "please review"
               )

      assert updated.assigned_user_id == bob.id
      assert updated.assigned_by_user_id == alice.id
      assert %DateTime{} = updated.assigned_at

      [event] = Accounts.review_audit_events(review.id)
      assert event.event_type == "assigned"
      assert event.actor_user_id == alice.id
      assert event.target_user_id == bob.id
      assert event.note == "please review"
    end

    test "rejects assignment to a non-member", %{review: review, alice: alice, outsider: outsider} do
      assert {:error, :assignee_not_member} =
               Accounts.assign_review(review.id, outsider.id, actor_user_id: alice.id)
    end

    test "rejects assignment when workspace has no org", %{alice: alice, bob: bob} do
      solo_ws =
        MissionFixtures.workspace_fixture(%{slug: "solo-#{System.unique_integer([:positive])}"})

      solo_session = MissionFixtures.session_fixture(%{workspace: solo_ws})
      solo_review = MissionFixtures.review_fixture(%{session: solo_session, title: "Solo"})

      assert {:error, :workspace_unaffiliated} =
               Accounts.assign_review(solo_review.id, bob.id, actor_user_id: alice.id)
    end

    test "reassignment records a 'reassigned' event", %{
      review: review,
      alice: alice,
      bob: bob,
      carol: carol
    } do
      {:ok, _} = Accounts.assign_review(review.id, bob.id, actor_user_id: alice.id)
      {:ok, reassigned} = Accounts.assign_review(review.id, carol.id, actor_user_id: alice.id)

      assert reassigned.assigned_user_id == carol.id

      event_types = Accounts.review_audit_events(review.id) |> Enum.map(& &1.event_type)
      assert event_types == ["assigned", "reassigned"]
    end

    test "carries required_role onto the review row", %{review: review, alice: alice, bob: bob} do
      {:ok, updated} =
        Accounts.assign_review(review.id, bob.id,
          actor_user_id: alice.id,
          required_role: "admin"
        )

      assert updated.required_role == "admin"
    end
  end

  describe "decide_review/4" do
    setup %{review: review, alice: alice, bob: bob} do
      {:ok, _} = Accounts.assign_review(review.id, bob.id, actor_user_id: alice.id)
      :ok
    end

    test "assignee can approve", %{review: review, bob: bob} do
      assert {:ok, decided} =
               Accounts.decide_review(review.id, bob.id, :approved, feedback_notes: "lgtm")

      assert decided.status == "approved"
      assert decided.decided_by_user_id == bob.id
      assert decided.feedback_notes == "lgtm"
      assert decided.reviewed_by == "user:#{bob.id}"

      approval =
        Accounts.review_audit_events(review.id)
        |> Enum.find(&(&1.event_type == "approved"))

      assert approval.actor_source == "user"
      assert approval.actor_identifier == Integer.to_string(bob.id)
    end

    test "assignee can deny", %{review: review, bob: bob} do
      assert {:ok, decided} = Accounts.decide_review(review.id, bob.id, :denied)
      assert decided.status == "denied"
    end

    test "another member cannot decide for the assignee", %{review: review, carol: carol} do
      assert {:error, :not_assigned} = Accounts.decide_review(review.id, carol.id, :approved)
    end

    test "admin can override and decide regardless of assignment", %{review: review, alice: alice} do
      assert {:ok, decided} = Accounts.decide_review(review.id, alice.id, :approved)
      assert decided.decided_by_user_id == alice.id
    end

    test "non-member is rejected with :not_a_member", %{review: review, outsider: outsider} do
      assert {:error, :not_a_member} = Accounts.decide_review(review.id, outsider.id, :approved)
    end

    test "rejects double-decision with :already_decided", %{review: review, bob: bob} do
      {:ok, _} = Accounts.decide_review(review.id, bob.id, :approved)
      assert {:error, :already_decided} = Accounts.decide_review(review.id, bob.id, :denied)
    end

    test "required_role gates the decider", %{
      review: review,
      alice: alice,
      bob: bob,
      carol: carol
    } do
      {:ok, _} =
        Accounts.assign_review(review.id, carol.id,
          actor_user_id: alice.id,
          required_role: "admin"
        )

      # Carol is assigned but only a member — fails required_role check.
      assert {:error, :insufficient_role} = Accounts.decide_review(review.id, carol.id, :approved)

      # Bob would otherwise be blocked by assignment, but he's also just a
      # member — fails because he's not assigned and also fails role check.
      assert {:error, :not_assigned} = Accounts.decide_review(review.id, bob.id, :approved)

      # Alice as admin meets the role requirement AND can override the
      # assignee restriction.
      assert {:ok, decided} = Accounts.decide_review(review.id, alice.id, :approved)
      assert decided.status == "approved"
    end

    test "rejected decisions still produce an audit trail entry", %{review: review, carol: carol} do
      _ = Accounts.decide_review(review.id, carol.id, :approved)
      events = Accounts.review_audit_events(review.id)

      assert Enum.any?(events, fn e ->
               e.event_type == "denied" and e.actor_user_id == carol.id and
                 e.note =~ "rejected by policy: not_assigned"
             end)
    end

    test "approval audit captures actor_role", %{review: review, alice: alice} do
      {:ok, _} = Accounts.decide_review(review.id, alice.id, :approved)

      events = Accounts.review_audit_events(review.id)

      approval =
        Enum.find(events, fn e ->
          e.event_type == "approved" and e.actor_user_id == alice.id
        end)

      assert approval != nil
      assert approval.actor_role == "admin"
    end
  end

  describe "Mission.respond_review/2 audit integration" do
    test "live review response records an immutable decision audit event", %{review: review} do
      assert {:ok, updated} =
               Mission.respond_review(review, %{
                 "decision" => "approved",
                 "feedback_notes" => "ship it",
                 "reviewed_by" => "mcp"
               })

      assert updated.status == "approved"

      [event] = Accounts.review_audit_events(review.id)
      assert event.event_type == "approved"
      assert event.actor_source == "mcp"
      assert event.actor_identifier == "mcp"
      assert event.note == "ship it"
      assert event.recorded_at == updated.responded_at

      [session_event | _] = Mission.list_session_events(review.session_id)
      assert session_event["event_type"] == "review.approved"
      assert session_event["review_id"] == review.id
      assert session_event["payload"]["review_id"] == review.id
    end
  end

  describe "review decision-time metadata" do
    test "review submission stores policy and artifact snapshots", %{session: session} do
      body = "Implementation plan with invariant boundaries"

      {:ok, invocation} =
        Mission.create_invocation(%{
          source: "agent",
          tool: "ck_review_submit",
          provider: "openai",
          model: "gpt-5.5",
          estimated_cost_cents: 1,
          decision: "allow",
          metadata: %{},
          session_id: session.id
        })

      assert {:ok, review} =
               Mission.submit_review(%{
                 "session_id" => session.id,
                 "submission_body" => body,
                 "review_type" => "plan"
               })

      assert review.metadata["policy_snapshot"]["version"] == 1
      assert is_binary(review.metadata["policy_snapshot"]["packs_hash"])

      assert review.metadata["artifact_snapshot"]["content_sha256"] ==
               ControlKeel.Policy.Snapshot.hash(body)

      assert review.metadata["artifact_snapshot"]["kind"] == "plan"
      assert review.metadata["model_provenance"]["source"] == "latest_invocation"
      assert review.metadata["model_provenance"]["invocation_id"] == invocation.id
      assert review.metadata["model_provenance"]["provider"] == "openai"
      assert review.metadata["model_provenance"]["model"] == "gpt-5.5"
    end

    test "finding creation stores explicit model provenance", %{session: session} do
      assert {:ok, finding} =
               Mission.create_finding(%{
                 session_id: session.id,
                 title: "Model-linked finding",
                 severity: "high",
                 category: "governance",
                 rule_id: "governance.model_provenance.fixture",
                 plain_message: "Decision should carry model provenance.",
                 metadata: %{"provider" => "anthropic", "model" => "claude-sonnet-4.6"}
               })

      assert finding.metadata["model_provenance"]["provider"] == "anthropic"
      assert finding.metadata["model_provenance"]["model"] == "claude-sonnet-4.6"
    end

    test "trace packet preserves decision-time metadata after mutable state changes", %{
      session: session
    } do
      body = "Original plan body with invariant boundaries"

      assert {:ok, review} =
               Mission.submit_review(%{
                 "session_id" => session.id,
                 "submission_body" => body,
                 "review_type" => "plan"
               })

      original_policy_hash = review.metadata["policy_snapshot"]["packs_hash"]
      original_artifact_hash = review.metadata["artifact_snapshot"]["content_sha256"]

      assert {:ok, _updated} =
               Mission.respond_review(review, %{
                 "decision" => "approved",
                 "feedback_notes" => "ship it",
                 "reviewed_by" => "test"
               })

      {:ok, packet} = Mission.trace_improvement_packet(session.id)

      trace_review =
        Enum.find(get_in(packet, ["trace", "reviews"]) || [], &(&1["id"] == review.id))

      assert trace_review["policy_snapshot"]["packs_hash"] == original_policy_hash
      assert trace_review["artifact_snapshot"]["content_sha256"] == original_artifact_hash
      assert trace_review["status"] == "approved"

      # Mutate current mutable state — simulate a later change by
      # clearing the policy pack cache. The stored snapshot must survive.
      ControlKeel.Policy.PackLoader.clear_cache()

      # Re-read the trace packet — stored decision metadata must be stable.
      {:ok, packet2} = Mission.trace_improvement_packet(session.id)

      trace_review2 =
        Enum.find(get_in(packet2, ["trace", "reviews"]) || [], &(&1["id"] == review.id))

      assert trace_review2["policy_snapshot"]["packs_hash"] == original_policy_hash
      assert trace_review2["artifact_snapshot"]["content_sha256"] == original_artifact_hash
    end
  end

  describe "review_audit_events/1 ordering" do
    test "events appear oldest first", %{review: review, alice: alice, bob: bob, carol: carol} do
      {:ok, _} = Accounts.assign_review(review.id, bob.id, actor_user_id: alice.id)
      Process.sleep(1100)
      {:ok, _} = Accounts.assign_review(review.id, carol.id, actor_user_id: alice.id)
      Process.sleep(1100)
      {:ok, _} = Accounts.decide_review(review.id, carol.id, :approved)

      types = Accounts.review_audit_events(review.id) |> Enum.map(& &1.event_type)
      assert types == ["assigned", "reassigned", "approved"]
    end
  end

  defp activate(user, org, role) do
    {:ok, _membership, raw_token} = Accounts.invite_member(user.id, org.id, role: role)
    {:ok, _} = Accounts.accept_invitation(raw_token, user.id)
    {user, role}
  end
end
