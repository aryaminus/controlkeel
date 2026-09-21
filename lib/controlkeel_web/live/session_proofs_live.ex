defmodule ControlKeelWeb.SessionProofsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(session) ->
        cond do
          not ControlKeel.Accounts.session_accessible?(session, current_user) ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          check_session_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()
            {:ok, assign_session(socket, session)}
        end
    end
  end

  defp check_session_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
    end
  end

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org
    browser = Mission.browse_proof_bundles(%{"session_id" => session.id})

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(workspace.id))
    |> assign(:breadcrumbs, [
      %{label: org.name, to: "/#{org.slug}"},
      %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
      %{
        label: session.title,
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
      },
      %{label: "Proofs", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Proofs")
    |> assign(:session, session)
    |> assign(:browser, browser)
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> {:noreply, socket}
      session -> {:noreply, assign_session(socket, session)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title title="Proofs" />

      <div class="bg-card border rounded-2xl shadow-card overflow-visible">
        <table class="min-w-full divide-y divide-border text-left text-sm border-separate border-spacing-0">
          <thead class="text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
            <tr>
              <th class="bg-muted px-5 py-3 font-semibold first:rounded-tl-2xl">Task</th>
              <th class="bg-muted px-5 py-3 font-semibold">Version</th>
              <th class="bg-muted px-5 py-3 font-semibold">Risk</th>
              <th class="bg-muted px-5 py-3 font-semibold">Verification</th>
              <th class="bg-muted px-5 py-3 font-semibold">Deploy ready</th>
              <th class="bg-muted px-5 py-3 font-semibold last:rounded-tr-2xl">Updated</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= for proof <- @browser.entries do %>
              <tr id={"proof-row-#{proof.id}"} class="transition hover:bg-muted/30">
                <td class="px-5 py-4">
                  <.link
                    navigate={
                      ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/proofs/#{proof.id}"
                    }
                    class="font-medium text-foreground hover:text-primary"
                  >
                    {proof.task.title}
                  </.link>
                  <span class={[
                    "mt-1 inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    proof.status == "generated" && "bg-success/10 text-success ring-success/20",
                    proof.status == "failed" &&
                      "bg-destructive/10 text-destructive ring-destructive/20",
                    proof.status not in ["generated", "failed"] &&
                      "bg-muted text-muted-foreground ring-border"
                  ]}>
                    {proof.status}
                  </span>
                </td>
                <td class="px-5 py-4 whitespace-nowrap text-muted-foreground">v{proof.version}</td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span class={[
                    "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    proof.session.risk_tier == "high" &&
                      "bg-destructive/10 text-destructive ring-destructive/20",
                    proof.session.risk_tier == "moderate" &&
                      "bg-warning/10 text-warning ring-warning/20",
                    proof.session.risk_tier == "low" &&
                      "bg-success/10 text-success ring-success/20",
                    proof.session.risk_tier not in ["low", "moderate", "high"] &&
                      "bg-muted text-muted-foreground ring-border"
                  ]}>
                    {proof.session.risk_tier || "unknown"}
                  </span>
                  <span class="ml-2 inline-flex rounded-full border bg-muted/[0.05] px-2 py-0.5 text-xs text-muted-foreground">
                    {proof.risk_score}
                  </span>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <% ver = get_in(proof.bundle, ["verification_assessment"]) || %{} %>
                  <span class="text-xs font-semibold text-muted-foreground">
                    {ver["status"] || "n/a"}
                  </span>
                  <span :if={ver["score"]} class="ml-2 text-xs tabular-nums text-muted-foreground">
                    {ver["score"]}
                  </span>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span class={[
                    "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ring-1",
                    proof.deploy_ready && "bg-success/10 text-success ring-success/20",
                    !proof.deploy_ready && "bg-warning/10 text-warning ring-warning/20"
                  ]}>
                    {if proof.deploy_ready, do: "ready", else: "review required"}
                  </span>
                </td>
                <td class="px-5 py-4 text-muted-foreground whitespace-nowrap font-mono tabular-nums tracking-tight text-xs">
                  {event_timestamp(proof.generated_at || proof.inserted_at)}
                </td>
              </tr>
            <% end %>
            <%= if @browser.entries == [] do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No proofs yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Generate a proof from a task to create a deploy-ready audit artifact.
                  </p>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp event_timestamp(nil), do: "unknown"
  defp event_timestamp(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%Y-%m-%d")
end
