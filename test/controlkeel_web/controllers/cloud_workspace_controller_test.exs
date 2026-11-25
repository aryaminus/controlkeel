defmodule ControlKeelWeb.CloudWorkspaceControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Enrollment
  alias ControlKeel.Cloud.RateLimiter
  alias ControlKeel.Cloud.Workspace.KeyRegistry
  alias ControlKeel.Repo

  defp fresh_identity do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    pub_b64 = Base.encode64(pub)
    priv_b64 = Base.encode64(priv)
    fp = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)

    %{
      workspace_id:
        "ws_" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false, case: :lower),
      algorithm: "ed25519",
      public_key: pub_b64,
      private_key: priv_b64,
      fingerprint: fp
    }
  end

  defp insert_org(slug \\ nil) do
    s = slug || "org-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, org} =
      %Accounts.Org{}
      |> Accounts.Org.changeset(%{name: s, slug: s, status: "active"})
      |> Repo.insert()

    org
  end

  # invite_member/3 now requires a named inviter to hold an active membership
  # in the org (authorize_invite_role/3). These enrollment tests model an
  # inviter who belongs to the org, so seed an active owner membership.
  defp make_owner(org, user) do
    {:ok, _} =
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        org_id: org.id,
        user_id: user.id,
        role: "owner",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    :ok
  end

  setup %{conn: conn} do
    # The register route is per-IP throttled. Reset the shared ETS buckets so
    # this file cannot trip the burst by accumulating hits across tests.
    ControlKeel.Cloud.RateLimiter.reset()
    conn = put_req_header(conn, "content-type", "application/json")
    {:ok, conn: conn}
  end

  describe "POST /cloud/v1/workspaces/register" do
    test "creates a registration with valid proof", %{conn: conn} do
      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity, name: "alpha")

      conn = post(conn, ~p"/cloud/v1/workspaces/register", envelope)
      assert json_response(conn, 201)["workspace_id"] == identity.workspace_id

      assert {:ok, key} = KeyRegistry.fetch(identity.workspace_id)
      assert key.fingerprint == identity.fingerprint
      assert key.name == "alpha"
      assert key.org_id == nil
    end

    test "re-registration is idempotent and returns 200", %{conn: conn} do
      identity = fresh_identity()
      {:ok, envelope1} = Enrollment.build(identity, name: "first")

      conn1 = post(conn, ~p"/cloud/v1/workspaces/register", envelope1)
      assert json_response(conn1, 201)

      # Build a fresh envelope (new nonce / timestamp); same identity.
      {:ok, envelope2} = Enrollment.build(identity, name: "second")
      conn2 = post(conn, ~p"/cloud/v1/workspaces/register", envelope2)
      assert json_response(conn2, 200)["workspace_id"] == identity.workspace_id

      {:ok, key} = KeyRegistry.fetch(identity.workspace_id)
      assert key.name == "second"
    end

    test "binds workspace to an org when invite_token is valid", %{conn: conn} do
      org = insert_org()

      {:ok, inviter_user} =
        %Accounts.User{}
        |> Accounts.User.changeset(%{email: "inviter@example.com", status: "active"})
        |> Repo.insert()

      :ok = make_owner(org, inviter_user)

      {:ok, invitee_user} =
        %Accounts.User{}
        |> Accounts.User.changeset(%{email: "invitee@example.com", status: "active"})
        |> Repo.insert()

      {:ok, _membership, raw_token} =
        Accounts.invite_member(invitee_user.id, org.id,
          role: "member",
          invited_by_user_id: inviter_user.id
        )

      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity, invite_token: raw_token)

      conn = post(conn, ~p"/cloud/v1/workspaces/register", envelope)
      body = json_response(conn, 201)
      assert body["workspace_id"] == identity.workspace_id
      assert body["org_id"] == org.id

      {:ok, key} = KeyRegistry.fetch(identity.workspace_id)
      assert key.org_id == org.id
    end

    test "rejects forged proof signature", %{conn: conn} do
      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity)

      # Tamper the workspace_id; the signed payload still references the
      # original. This trips the payload-mismatch check first.
      tampered = Map.put(envelope, "workspace_id", "ws_attacker")
      conn = post(conn, ~p"/cloud/v1/workspaces/register", tampered)

      assert json_response(conn, 400)["error"] == "proof_payload_mismatch"
    end

    test "rejects malformed body", %{conn: conn} do
      conn = post(conn, ~p"/cloud/v1/workspaces/register", %{"hello" => "world"})
      assert json_response(conn, 400)["error"] == "missing_fields"
    end

    test "rejects unknown invite_token", %{conn: conn} do
      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity, invite_token: "not-a-real-token")

      conn = post(conn, ~p"/cloud/v1/workspaces/register", envelope)
      assert json_response(conn, 400)["error"] == "invalid_invite_token"
    end

    test "binds enrolled key to mission_workspace when invite is scoped (CK-CLOUD-ENROLL-LINK-001)",
         %{conn: conn} do
      org = insert_org()
      mws = insert_mission_workspace(org)

      {:ok, inviter} =
        %Accounts.User{}
        |> Accounts.User.changeset(%{
          email: "inviter-#{System.unique_integer([:positive])}@example.com",
          status: "active"
        })
        |> Repo.insert()

      :ok = make_owner(org, inviter)

      {:ok, invitee} =
        %Accounts.User{}
        |> Accounts.User.changeset(%{
          email: "invitee-#{System.unique_integer([:positive])}@example.com",
          status: "active"
        })
        |> Repo.insert()

      {:ok, _membership, raw_token} =
        Accounts.invite_member(invitee.id, org.id,
          role: "member",
          invited_by_user_id: inviter.id,
          mission_workspace_id: mws.id
        )

      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity, invite_token: raw_token)

      conn = post(conn, ~p"/cloud/v1/workspaces/register", envelope)
      body = json_response(conn, 201)
      assert body["mission_workspace_id"] == mws.id

      {:ok, key} = KeyRegistry.fetch(identity.workspace_id)
      assert key.org_id == org.id
      assert key.mission_workspace_id == mws.id

      # fetch_by_mission_workspace now resolves to the enrolled key
      assert {:ok, ^key} = KeyRegistry.fetch_by_mission_workspace(mws.id)
    end

    test "unscoped invite leaves mission_workspace_id nil", %{conn: conn} do
      org = insert_org()

      {:ok, inviter} =
        %Accounts.User{}
        |> Accounts.User.changeset(%{
          email: "inv2-#{System.unique_integer([:positive])}@example.com",
          status: "active"
        })
        |> Repo.insert()

      :ok = make_owner(org, inviter)

      {:ok, invitee} =
        %Accounts.User{}
        |> Accounts.User.changeset(%{
          email: "inv2t-#{System.unique_integer([:positive])}@example.com",
          status: "active"
        })
        |> Repo.insert()

      {:ok, _m, raw_token} =
        Accounts.invite_member(invitee.id, org.id, role: "member", invited_by_user_id: inviter.id)

      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity, invite_token: raw_token)

      conn = post(conn, ~p"/cloud/v1/workspaces/register", envelope)
      body = json_response(conn, 201)
      assert body["mission_workspace_id"] == nil

      {:ok, key} = KeyRegistry.fetch(identity.workspace_id)
      assert key.mission_workspace_id == nil
    end

    test "returns 429 with Retry-After once the per-IP bucket is exhausted", %{conn: conn} do
      # Drain the same bucket the router plug uses for this client IP.
      for _ <- 1..20 do
        RateLimiter.hit_key("ip:cloud_register:127.0.0.1", burst: 20, refill_per_sec: 0.5)
      end

      conn = post(conn, ~p"/cloud/v1/workspaces/register", %{})

      assert json_response(conn, 429)["error"] == "rate_limited"
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) >= 1
    end
  end

  defp insert_mission_workspace(org) do
    n = Integer.to_string(System.unique_integer([:positive]))

    {:ok, ws} =
      %ControlKeel.Mission.Workspace{}
      |> ControlKeel.Mission.Workspace.changeset(%{
        name: "Project #{n}",
        slug: "project-#{n}",
        org_id: org.id,
        industry: "technology",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "baseline",
        status: "active"
      })
      |> Repo.insert()

    ws
  end
end
