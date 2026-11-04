defmodule ControlKeelWeb.ServiceAccountAuditTest do
  @moduledoc """
  Credential lifecycle is exactly what a customer audits. The
  WorkspaceServiceAccountsLive admin UI called the raw Platform functions,
  which record nothing — while the JSON API and CLI paths already used the
  NHI-audited wrappers. This pins the UI to the audited path (issue #250).
  """
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Platform

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)
    :ok
  end

  defp workspace_with_owner do
    suffix = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{suffix}", slug: "org-#{suffix}"})

    workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: org.id})
    %{owner: owner, org: org, workspace: workspace}
  end

  defp conn_for(user, org) do
    build_conn()
    |> Plug.Test.init_test_session(%{"current_user_id" => user.id, "current_org_id" => org.id})
  end

  test "creating a service account through the UI writes an NHI audit event" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    render_hook(view, "create", %{"sa" => %{"name" => "audit-test", "scopes" => "workspace:read"}})

    [account] = Platform.list_service_accounts(ws.id)

    events = Platform.list_nhi_audit_events(account.id)

    assert Enum.any?(events, &(&1.event_type == "provisioned")),
           "expected a 'provisioned' NHI audit event, got: #{inspect(Enum.map(events, & &1.event_type))}"
  end

  test "rotating through the UI writes an NHI audit event" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    render_hook(view, "create", %{
      "sa" => %{"name" => "rotate-test", "scopes" => "workspace:read"}
    })

    [account] = Platform.list_service_accounts(ws.id)

    render_hook(view, "rotate", %{"id" => to_string(account.id)})

    events = Platform.list_nhi_audit_events(account.id)

    assert Enum.any?(events, &(&1.event_type == "token_rotated")),
           "expected a 'token_rotated' NHI audit event, got: #{inspect(Enum.map(events, & &1.event_type))}"
  end

  test "revoking through the UI writes an NHI audit event" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    render_hook(view, "create", %{
      "sa" => %{"name" => "revoke-test", "scopes" => "workspace:read"}
    })

    [account] = Platform.list_service_accounts(ws.id)

    render_hook(view, "revoke", %{"id" => to_string(account.id)})

    events = Platform.list_nhi_audit_events(account.id)

    assert Enum.any?(events, &(&1.event_type == "deprovisioned")),
           "expected a 'deprovisioned' NHI audit event, got: #{inspect(Enum.map(events, & &1.event_type))}"
  end
end
