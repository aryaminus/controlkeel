defmodule ControlKeelWeb.CloudTelemetryAuthzTest do
  @moduledoc """
  `/cloud/telemetry` renders cross-tenant data (global ingestion, MCP audit log,
  registry). It must not be reachable by an ordinary org admin — granting one
  colleague `admin` must not expose every tenant's telemetry (issue #246).

  Until a platform-operator role exists, access requires the
  CONTROLKEEL_PLATFORM_OPERATORS allowlist. Local mode is single-user and open.
  """
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      Application.put_env(:controlkeel, :runtime_mode, previous)
      System.delete_env("CONTROLKEEL_PLATFORM_OPERATORS")
    end)

    :ok
  end

  defp org_admin do
    suffix = System.unique_integer([:positive])
    {:ok, admin} = Accounts.create_user(%{email: "admin-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(admin.id, %{name: "Org #{suffix}", slug: "org-#{suffix}"})

    %{admin: admin, org: org}
  end

  defp conn_for(user) do
    build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
  end

  test "an org admin cannot reach the cross-tenant console by default" do
    %{admin: admin} = org_admin()

    # No allowlist configured ⇒ closed by default.
    assert {:error, {:redirect, %{to: "/"}}} = live(conn_for(admin), ~p"/cloud/telemetry")
  end

  test "a non-admin member cannot reach it" do
    suffix = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{suffix}", slug: "org-#{suffix}"})

    {:ok, member} = Accounts.create_user(%{email: "member-#{suffix}@example.com"})
    {:ok, _m, token} = Accounts.invite_member(member.id, org.id, role: "member")
    {:ok, _acc} = Accounts.accept_invitation(token, member.id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn_for(member), ~p"/cloud/telemetry")
  end

  test "an allowlisted operator can reach it" do
    %{admin: admin} = org_admin()
    System.put_env("CONTROLKEEL_PLATFORM_OPERATORS", "ops@example.com,#{admin.email}")

    {:ok, _view, html} = live(conn_for(admin), ~p"/cloud/telemetry")

    assert html =~ "Cloud telemetry"
  end
end
