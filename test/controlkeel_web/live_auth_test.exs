defmodule ControlKeelWeb.LiveAuthTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  # Issue #141, R3: in cloud mode every authenticated surface except the
  # /organizations onboarding page requires at least one active membership.
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

  defp memberless_conn do
    {:ok, user} =
      Accounts.create_user(%{email: "lonely-#{System.unique_integer([:positive])}@example.com"})

    build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  defp member_conn(role \\ "viewer") do
    {:ok, org} =
      Accounts.create_org(%{name: "Home", slug: "home-#{System.unique_integer([:positive])}"})

    {:ok, user} =
      Accounts.create_user(%{email: "member-#{System.unique_integer([:positive])}@example.com"})

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org.id,
      role: role,
      status: "active"
    })
    |> Repo.insert!()

    conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
    {conn, user, org}
  end

  test "memberless users are redirected to /organizations on authenticated pages" do
    assert {:error, {:redirect, %{to: "/organizations"}}} =
             live(memberless_conn(), ~p"/proofs")
  end

  test "memberless users can open /organizations (onboarding surface)" do
    {:ok, _view, html} = live(memberless_conn(), ~p"/organizations")
    assert html =~ "Organizations"
  end

  test "users with a membership render authenticated pages" do
    {conn, _user, _org} = member_conn()
    {:ok, _view, html} = live(conn, ~p"/proofs")
    refute html =~ "Join or create an organization"
  end

  test "role changes from another org do not overwrite the current org membership" do
    {:ok, org_a} =
      Accounts.create_org(%{name: "Org A", slug: "org-a-#{System.unique_integer([:positive])}"})

    {:ok, org_b} =
      Accounts.create_org(%{name: "Org B", slug: "org-b-#{System.unique_integer([:positive])}"})

    {:ok, user} =
      Accounts.create_user(%{email: "multi-#{System.unique_integer([:positive])}@example.com"})

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org_a.id,
      role: "viewer",
      status: "active"
    })
    |> Repo.insert!()

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org_b.id,
      role: "admin",
      status: "active"
    })
    |> Repo.insert!()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{current_user_id: user.id, current_org_id: org_a.id})

    {:ok, view, html} = live(conn, ~p"/cloud/projects")
    refute html =~ "+ Create workspace"

    Phoenix.PubSub.broadcast(
      ControlKeel.PubSub,
      Accounts.membership_topic(user.id),
      {:membership_changed, %{user_id: user.id, org_id: org_b.id}}
    )

    refute render(view) =~ "+ Create workspace"
  end

  test "unauthenticated users are still sent to login, not /organizations" do
    assert {:error, {:redirect, %{to: "/auth/login"}}} = live(build_conn(), ~p"/proofs")
  end
end
