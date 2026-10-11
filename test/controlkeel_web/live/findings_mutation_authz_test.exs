defmodule ControlKeelWeb.FindingsMutationAuthzTest do
  @moduledoc """
  Findings disposition is governance state, so every mutation must be gated on
  the caller holding at least the `admin` role in the finding's own workspace.

  Before this change the handlers loaded any finding by id
  (`Mission.get_finding/1`, a bare `Repo.get`) with no tenant check and no role
  check, so a crafted LiveView event could approve/escalate/reject a finding in
  another organization, and any viewer could mutate disposition.
  """
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)
    :ok
  end

  # Owner of org + a workspace + a finding in that workspace. Returns the owner
  # plus an `actor` user who is a member of the org with the given role (default
  # "owner" keeps using the owner as the actor).
  defp owner_with_finding(role \\ "owner") do
    suffix = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{suffix}", slug: "org-#{suffix}"})

    workspace = workspace_fixture(%{org_id: org.id})
    session = session_fixture(%{workspace: workspace})

    finding =
      finding_fixture(%{
        session: session,
        title: "Governance finding",
        rule_id: "security.authz",
        category: "security",
        severity: "high",
        status: "open",
        plain_message: "Finding owned by #{suffix}"
      })

    actor =
      if role == "owner" do
        owner
      else
        add_member(org, owner, role, suffix)
      end

    %{owner: owner, actor: actor, org: org, workspace: workspace, finding: finding}
  end

  # Invites a user at the given role and accepts, yielding an active membership.
  defp add_member(org, inviter, role, suffix) do
    {:ok, member} = Accounts.create_user(%{email: "member-#{role}-#{suffix}@example.com"})

    {:ok, _membership, token} =
      Accounts.invite_member(member.id, org.id, role: role, invited_by_user_id: inviter.id)

    {:ok, _accepted} = Accounts.accept_invitation(token, member.id)
    member
  end

  defp conn_for(user) do
    build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
  end

  test "a viewer cannot approve a finding" do
    %{actor: actor, finding: finding} = owner_with_finding("viewer")

    {:ok, view, _html} = live(conn_for(actor), ~p"/findings")

    render_hook(view, "approve", %{"id" => finding.id})

    assert render(view) =~ "could not approve"
    assert Mission.get_finding(finding.id).status == "open"
  end

  test "a viewer cannot escalate a finding" do
    %{actor: actor, finding: finding} = owner_with_finding("viewer")

    {:ok, view, _html} = live(conn_for(actor), ~p"/findings")

    render_hook(view, "escalate", %{"id" => finding.id})

    assert render(view) =~ "could not escalate"
    assert Mission.get_finding(finding.id).status == "open"
  end

  test "an admin can approve a finding in their workspace" do
    %{actor: actor, finding: finding} = owner_with_finding("admin")

    {:ok, view, _html} = live(conn_for(actor), ~p"/findings")

    render_hook(view, "approve", %{"id" => finding.id})

    assert Mission.get_finding(finding.id).status == "approved"
  end

  # Builds a second, unrelated org with its own admin member, so the actor
  # passes the /findings route gate (has a membership) but has no authority
  # in the finding's workspace — the genuine cross-tenant case.
  defp foreign_admin do
    suffix = System.unique_integer([:positive])
    {:ok, member} = Accounts.create_user(%{email: "foreign-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(member.id, %{
        name: "Other #{suffix}",
        slug: "other-#{suffix}"
      })

    workspace_fixture(%{org_id: org.id})
    member
  end

  test "an admin of another org cannot approve a finding (cross-tenant write)" do
    %{finding: finding} = owner_with_finding("admin")
    foreign = foreign_admin()

    {:ok, view, _html} = live(conn_for(foreign), ~p"/findings")

    render_hook(view, "approve", %{"id" => finding.id})

    assert Mission.get_finding(finding.id).status == "open"
  end

  test "an admin of another org cannot escalate a finding" do
    %{finding: finding} = owner_with_finding("admin")
    foreign = foreign_admin()

    {:ok, view, _html} = live(conn_for(foreign), ~p"/findings")

    render_hook(view, "escalate", %{"id" => finding.id})

    assert Mission.get_finding(finding.id).status == "open"
  end

  test "an admin of another org cannot read autofix content for a foreign finding" do
    %{finding: finding} = owner_with_finding("admin")
    foreign = foreign_admin()

    {:ok, view, _html} = live(conn_for(foreign), ~p"/findings")

    render_hook(view, "view_fix", %{"id" => finding.id})

    html = render(view)
    refute html =~ "agent_prompt"
    assert html =~ "could not load that fix"
  end
end
