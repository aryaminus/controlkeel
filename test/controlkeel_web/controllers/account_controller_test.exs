defmodule ControlKeelWeb.AccountControllerTest do
  @moduledoc """
  Self-service account endpoints backing the user-menu dialog
  (docs/dsar-erasure-plan.md, Slice 3): Art.15 export (`GET
  /me/export.json`) and Art.17 erasure (`POST /me/erase`).

  There is no `/account` page: the dialog is rendered by the framework
  layouts' user menu and posts here from any cloud LiveView. Local mode is
  a no-user environment, so both endpoints must refuse there
  (RequireCloudMode blocks `/me/*`; the controller's user check is the
  inner gate).
  """

  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.DataLifecycle
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  # The dialog endpoints are cloud-only; the suite's local-mode test below
  # flips the mode explicitly.
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

  defp conn_for(user),
    do: build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

  defp create_user!(email), do: elem(Accounts.create_user(%{email: email}), 1)

  defp add_active_membership(user_id, org_id, role) do
    %Membership{}
    |> Membership.changeset(%{user_id: user_id, org_id: org_id, role: role, status: "active"})
    |> Repo.insert!()
  end

  # ── Export (Art.15) ──────────────────────────────────────────────────────

  test "export returns the caller's own data as a JSON attachment" do
    user = create_user!("export-dl-#{System.unique_integer([:positive])}@example.com")

    conn = conn_for(user) |> get(~p"/me/export.json")

    assert conn.status == 200
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "attachment"
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

    %{"user" => %{"email" => email}} = Jason.decode!(conn.resp_body)
    assert email == user.email
  end

  test "export requires a signed-in user" do
    conn = get(build_conn(), ~p"/me/export.json")

    assert conn.status == 401
    assert %{"error" => "sign in required"} = Jason.decode!(conn.resp_body)
  end

  # ── Erasure (Art.17) ─────────────────────────────────────────────────────

  test "erases the account, clears the session, and redirects to login" do
    email = "erased-#{System.unique_integer([:positive])}@example.com"
    user = create_user!(email)

    conn =
      conn_for(user)
      |> post(~p"/me/erase", %{"erase" => %{"confirm_email" => email}})

    assert redirected_to(conn) == "/auth/login"
    assert %{"info" => "Your account has been erased."} = conn.assigns.flash
    assert get_session(conn, "current_user_id") == nil
    assert Repo.get(Accounts.User, user.id) == nil
  end

  test "refuses erasure unless the email matches exactly" do
    user = create_user!("eraser-#{System.unique_integer([:positive])}@example.com")

    conn =
      conn_for(user)
      |> post(~p"/me/erase", %{"erase" => %{"confirm_email" => "wrong@example.com"}})

    assert redirected_to(conn) == "/"
    assert %{"error" => "Type your email exactly to confirm erasure."} = conn.assigns.flash
    assert Repo.get(Accounts.User, user.id)
  end

  test "sole-owner erasure is refused with actionable copy naming the org" do
    email = "sole-owner-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.create_user(%{email: email})

    {:ok, org} =
      Accounts.create_org_with_owner(user.id, %{
        name: "Last Standing",
        slug: "last-standing-#{System.unique_integer([:positive])}"
      })

    conn =
      conn_for(user)
      |> post(~p"/me/erase", %{"erase" => %{"confirm_email" => email}})

    assert redirected_to(conn) == "/"
    flash = conn.assigns.flash["error"]
    assert flash =~ "You are the last active owner of Last Standing"
    assert flash =~ "Promote another owner"
    assert Repo.get(Accounts.User, user.id)
    assert Repo.get(Accounts.Org, org.id)
  end

  test "a second owner can erase while the org keeps its remaining owner" do
    email = "leaving-#{System.unique_integer([:positive])}@example.com"
    {:ok, owner} = Accounts.create_user(%{email: email})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{
        name: "Two Owners",
        slug: "two-owners-#{System.unique_integer([:positive])}"
      })

    {:ok, second} =
      Accounts.create_user(%{email: "second-#{System.unique_integer([:positive])}@example.com"})

    add_active_membership(second.id, org.id, "owner")

    conn =
      conn_for(owner)
      |> post(~p"/me/erase", %{"erase" => %{"confirm_email" => email}})

    assert redirected_to(conn) == "/auth/login"
    assert Repo.get(Accounts.User, owner.id) == nil
    assert Repo.get(Accounts.Org, org.id)

    # After the first owner's erasure the survivor is now the sole owner —
    # their own erasure would be refused until they promote someone else.
    assert Enum.map(DataLifecycle.sole_owner_orgs(second.id), & &1.id) == [org.id]
  end

  # ── Local mode ───────────────────────────────────────────────────────────

  test "local mode blocks /me endpoints at the plug" do
    Application.put_env(:controlkeel, :runtime_mode, :local)

    conn = get(build_conn(), ~p"/me/export.json")

    assert redirected_to(conn) == "/"
    assert %{"info" => "This feature is not available in local mode."} = conn.assigns.flash
  end
end
