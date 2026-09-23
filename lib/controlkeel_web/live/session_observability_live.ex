defmodule ControlKeelWeb.SessionObservabilityLive do
  @moduledoc """
  Session observability page under the organization layout: one route
  stacking the run overview, timeline, and memory stages
  (`/:org_slug/workspaces/:ws_slug/sessions/:id/observability`).
  Replaces the former tabbed `/observability/sessions/:id/*` family
  (docs/issues/observability-route-consolidation.md).
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Observability
  alias ControlKeel.Platform
  alias ControlKeelWeb.SessionObservabilityMemory
  alias ControlKeelWeb.SessionObservabilityOverview
  alias ControlKeelWeb.SessionObservabilityTimeline
  alias ControlKeelWeb.SessionScope

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    session = SessionScope.fetch_session(id)

    cond do
      is_nil(session) ->
        {:ok, SessionScope.session_not_found(socket)}

      not Accounts.session_accessible?(session, current_user) ->
        {:ok, SessionScope.session_not_found(socket)}

      SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
        {:ok, SessionScope.session_not_found(socket)}

      true ->
        with {:ok, run} <- Observability.session_run(id),
             {:ok, timeline} <- Observability.timeline(id, limit: 50),
             {:ok, memory_context} <- Observability.memory_context(id, limit: 20) do
          {:ok,
           socket
           |> assign(:page_title, "Observability — #{run.session.title}")
           |> assign(:org_slug, org_slug)
           |> assign(:ws_slug, ws_slug)
           |> assign(:run, run)
           |> assign(:timeline, timeline)
           |> assign(:memory_context, memory_context)
           |> assign(:audit_exports, Platform.list_audit_exports(session.id))
           |> assign_session_nav(session)}
        else
          _ -> {:ok, SessionScope.session_not_found(socket)}
        end
    end
  end

  defp assign_session_nav(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    crumbs =
      if org && workspace do
        [
          %{label: org.name, to: "/#{org.slug}"},
          %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
          %{
            label: session.title,
            to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
          },
          %{label: "Observability", to: nil}
        ]
      else
        []
      end

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:breadcrumbs, crumbs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="session-observability-page" class="w-full space-y-8">
      <div class="space-y-2">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
          Session observability
        </h1>
        <p class="text-sm text-muted-foreground">
          Run overview, governed event timeline, and memory context for this session, stacked on one page.
        </p>
      </div>

      <SessionObservabilityOverview.overview_panel
        run={@run}
        audit_exports={@audit_exports}
        org_slug={@org_slug}
        ws_slug={@ws_slug}
      />

      <SessionObservabilityTimeline.timeline_panel timeline={@timeline} />

      <SessionObservabilityMemory.memory_panel memory_context={@memory_context} />
    </section>
    """
  end
end
