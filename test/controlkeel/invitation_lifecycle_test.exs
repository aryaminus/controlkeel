defmodule ControlKeel.InvitationLifecycleTest do
  @moduledoc """
  Invitation lifecycle hardening (issue #247):

    * pending invitations expire (default 14 days) and cannot be accepted after;
    * the cloud workspace enrolment path **consumes** the invite, so one token
      binds exactly one key;
    * unauthenticated token oracles are throttled per IP.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts

  setup do
    previous = Application.get_env(:controlkeel, :invitation_expiry_days)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:controlkeel, :invitation_expiry_days)
      else
        Application.put_env(:controlkeel, :invitation_expiry_days, previous)
      end
    end)

    :ok
  end

  defp org_and_invitee do
    n = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{n}@example.com"})
    {:ok, invitee} = Accounts.create_user(%{email: "invitee-#{n}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{n}", slug: "org-#{n}"})

    {owner, invitee, org}
  end

  describe "invitation expiry" do
    test "a fresh invitation is accepted" do
      {_owner, invitee, org} = org_and_invitee()
      {:ok, _m, token} = Accounts.invite_member(invitee.id, org.id)

      assert {:ok, accepted} = Accounts.accept_invitation(token, invitee.id)
      assert accepted.status == "active"
    end

    test "an expired invitation cannot be accepted" do
      Application.put_env(:controlkeel, :invitation_expiry_days, 1)
      {_owner, invitee, org} = org_and_invitee()
      {:ok, _m, token} = Accounts.invite_member(invitee.id, org.id)

      # Force the membership into the past.
      membership = Repo.get_by(Accounts.Membership, user_id: invitee.id, org_id: org.id)

      past =
        DateTime.utc_now()
        |> DateTime.add(-2 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      membership |> Accounts.Membership.changeset(%{expires_at: past}) |> Repo.update!()

      assert {:error, :invalid_token} = Accounts.accept_invitation(token, invitee.id)
    end

    test "an expired invitation is reported invalid by lookup (no oracle)" do
      Application.put_env(:controlkeel, :invitation_expiry_days, 1)
      {_owner, invitee, org} = org_and_invitee()
      {:ok, _m, token} = Accounts.invite_member(invitee.id, org.id)

      membership = Repo.get_by(Accounts.Membership, user_id: invitee.id, org_id: org.id)

      past =
        DateTime.utc_now()
        |> DateTime.add(-2 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      membership |> Accounts.Membership.changeset(%{expires_at: past}) |> Repo.update!()

      # Same error as a nonexistent token — no way to distinguish by probing.
      assert {:error, :invalid_token} = Accounts.lookup_invitation(token)
    end

    test "invite_member sets a default expiry" do
      {_owner, invitee, org} = org_and_invitee()
      {:ok, m, _token} = Accounts.invite_member(invitee.id, org.id)
      refute is_nil(m.expires_at)
    end
  end

  describe "cloud enrolment consumes the invite" do
    test "one invitation binds one enrolment" do
      {_owner, invitee, org} = org_and_invitee()
      {:ok, _m, token} = Accounts.invite_member(invitee.id, org.id)

      assert {:ok, %{org: %{id: org_id}}} = Accounts.consume_invitation_for_enrolment(token)
      assert org_id == org.id

      # Second attempt with the same token fails — it is consumed.
      assert {:error, :invalid_token} = Accounts.consume_invitation_for_enrolment(token)
    end

    test "an expired invitation cannot be consumed for enrolment" do
      Application.put_env(:controlkeel, :invitation_expiry_days, 1)
      {_owner, invitee, org} = org_and_invitee()
      {:ok, _m, token} = Accounts.invite_member(invitee.id, org.id)

      membership = Repo.get_by(Accounts.Membership, user_id: invitee.id, org_id: org.id)

      past =
        DateTime.utc_now()
        |> DateTime.add(-2 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      membership |> Accounts.Membership.changeset(%{expires_at: past}) |> Repo.update!()

      assert {:error, :invalid_token} = Accounts.consume_invitation_for_enrolment(token)
    end
  end
end
