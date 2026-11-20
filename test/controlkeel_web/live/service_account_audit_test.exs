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

  # ── Cross-tenant IDOR (pre-launch review A1) ─────────────────────────────
  #
  # LiveView event payloads are client-controlled, so the handlers must scope
  # every mutation to the workspace the page was mounted for. A foreign id
  # must be a no-op: no row change, no audit event, and no leaked token.

  defp foreign_workspace_with_service_account do
    suffix = System.unique_integer([:positive])
    {:ok, other_owner} = Accounts.create_user(%{email: "foreign-owner-#{suffix}@example.com"})

    {:ok, other_org} =
      Accounts.create_org_with_owner(other_owner.id, %{
        name: "Foreign #{suffix}",
        slug: "foreign-org-#{suffix}"
      })

    foreign_workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: other_org.id})

    {:ok, %{service_account: sa, token: _token}} =
      Platform.create_service_account(foreign_workspace.id, %{
        "name" => "foreign-#{suffix}",
        "scopes" => ["workspace:read"]
      })

    %{workspace: foreign_workspace, service_account: sa}
  end

  test "revoking a service account from another workspace is denied" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()
    %{service_account: foreign} = foreign_workspace_with_service_account()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    render_hook(view, "revoke", %{"id" => to_string(foreign.id)})

    reloaded = Platform.get_service_account(foreign.id)
    assert reloaded.status == "active"
    assert Platform.list_nhi_audit_events(foreign.id) == []
    assert render(view) =~ "Could not revoke service account."
  end

  test "rotating a service account from another workspace is denied and leaks no token" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()
    %{service_account: foreign} = foreign_workspace_with_service_account()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    render_hook(view, "rotate", %{"id" => to_string(foreign.id)})

    reloaded = Platform.get_service_account(foreign.id)
    assert is_nil(reloaded.rotated_at)
    assert Platform.list_nhi_audit_events(foreign.id) == []
    refute has_element?(view, "#new-token-banner")
    assert render(view) =~ "Could not rotate token."
  end

  # ── Expiry surfaced in the UI (pre-launch review A5) ────────────────────

  test "rotating an expired service account explains the expiry" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    render_hook(view, "create", %{
      "sa" => %{"name" => "expired-test", "scopes" => "workspace:read"}
    })

    [account] = Platform.list_service_accounts(ws.id)
    {:ok, _} = Platform.expire_service_account(account.id)

    render_hook(view, "rotate", %{"id" => to_string(account.id)})

    assert render(view) =~ "has expired"
    reloaded = Platform.get_service_account(account.id)
    assert is_nil(reloaded.rotated_at)
  end

  test "expired service accounts render an expired badge without a rotate button" do
    %{owner: owner, org: org, workspace: ws} = workspace_with_owner()

    {:ok, %{service_account: account, token: _token}} =
      Platform.create_service_account(ws.id, %{
        "name" => "badge-test",
        "scopes" => ["workspace:read"]
      })

    {:ok, _} = Platform.expire_service_account(account.id)

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/#{org.slug}/workspaces/#{ws.slug}/service-accounts")

    assert has_element?(view, "#sa-#{account.id} [data-sa-status='expired']")
    refute has_element?(view, "#sa-#{account.id} button[phx-click='rotate']")
    assert has_element?(view, "#sa-#{account.id} button[phx-click='revoke']")
    assert render(view) =~ "Expires"
  end
end
