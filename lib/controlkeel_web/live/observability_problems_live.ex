defmodule ControlKeelWeb.ObservabilityProblemsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.CommandPill
  alias ControlKeelWeb.WorkspaceAccess

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      opts = [workspace_id: workspace.id]

      {:ok,
       socket
       |> assign(:page_title, "Observability Problems")
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(
         :breadcrumbs,
         [
           %{label: workspace.org.name, to: ~p"/#{workspace.org.slug}"},
           %{
             label: workspace.name,
             to: ~p"/#{workspace.org.slug}/workspaces/#{workspace.slug}"
           },
           %{label: "Problems", to: nil}
         ]
       )
       |> assign(:problems, Observability.problems(opts))}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  defp check_workspace_access(workspace, assigns) do
    case WorkspaceAccess.check(workspace, assigns[:current_user]) do
      :ok -> :ok
      {:error, :unbound} -> {:error, "Workspace is not bound to an org."}
      {:error, :forbidden} -> {:error, "Workspace belongs to a different organization."}
      {:error, :needs_admin} -> {:error, "Viewer role or higher required."}
    end
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-problem-list" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Problems
          </h1>
          <p class="text-sm text-muted-foreground">
            Recurring problem patterns across sessions, grouped by category and rule ID with health indicators and remediation guidance.
          </p>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <span class={health_pill_class(@problems.health)}>{@problems.health}</span>
          <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
            {@problems.count} {if @problems.count == 1, do: "group", else: "groups"}
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs problems" />

      <div class="space-y-5">
        <%= if @problems.recommendations != [] do %>
          <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
            <.section_title>Recommendations</.section_title>
            <%= for recommendation <- @problems.recommendations do %>
              <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
            <% end %>
          </section>
        <% end %>

        <%= if @problems.problems == [] do %>
          <p class="text-sm text-muted-foreground">No active problems detected.</p>
        <% else %>
          <div class="space-y-8">
            <%= for {problem, idx} <- Enum.with_index(@problems.problems) do %>
              <section
                id={"observability-problem-#{problem_key_id(problem.key)}"}
                class={[
                  "rounded-2xl border bg-card p-5 shadow-card space-y-5",
                  if(idx > 0, do: "", else: "")
                ]}
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="min-w-0 space-y-1">
                    <p class="text-lg font-semibold text-foreground/90">{problem.title}</p>
                  </div>
                  <span class={health_pill_class(problem.health)}>{problem.health}</span>
                </div>

                <dl class="grid grid-cols-2 gap-3 md:grid-cols-4 text-xs">
                  <div>
                    <dt class="text-muted-foreground">Category</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{problem.category}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Rule ID</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{problem.rule_id}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Severity</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{problem.severity}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Count</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{problem.count}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Sessions</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {problem.affected_session_count}
                    </dd>
                  </div>
                  <div class="col-span-1 md:col-span-2">
                    <dt class="text-muted-foreground">Last seen</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {format_datetime(problem.last_seen)}
                    </dd>
                  </div>
                  <div class="col-span-2">
                    <dt class="text-muted-foreground">Recommendation</dt>
                    <dd class="mt-0.5 text-sm leading-relaxed text-foreground">
                      {problem.recommendation}
                    </dd>
                  </div>
                </dl>

                <div class="space-y-3 border-t border-border pt-4">
                  <.section_title>Feedback loop</.section_title>
                  <div class="space-y-4">
                    <dl class="flex flex-wrap gap-x-8 gap-y-3 text-xs">
                      <div>
                        <dt class="text-muted-foreground">Eval</dt>
                        <dd class="mt-0.5 font-medium text-foreground">
                          {problem.feedback_loop.eval_candidate_title}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-muted-foreground">Action</dt>
                        <dd class="mt-0.5 font-medium text-foreground">
                          {problem.feedback_loop.evidence_summary}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-muted-foreground">Benchmark</dt>
                        <dd class="mt-0.5 font-medium text-foreground">
                          {problem.feedback_loop.benchmark_hint}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-muted-foreground">Human gate</dt>
                        <dd class={[
                          "mt-0.5 font-medium",
                          if(problem.feedback_loop.human_gate_required,
                            do: "text-warning",
                            else: "text-foreground"
                          )
                        ]}>
                          {if problem.feedback_loop.human_gate_required do
                            "required"
                          else
                            "not required"
                          end}
                        </dd>
                      </div>
                    </dl>
                    <div>
                      <p class="text-xs text-muted-foreground">Suggested action</p>
                      <p class="mt-0.5 text-sm text-foreground">
                        {problem.feedback_loop.suggested_action}
                      </p>
                    </div>
                  </div>
                </div>

                <%= if problem.examples && problem.examples != [] do %>
                  <div class="space-y-3 border-t border-border pt-4">
                    <.section_title>Examples</.section_title>
                    <div class="divide-y divide-border">
                      <%= for example <- problem.examples do %>
                        <div class="flex items-center justify-between gap-4 py-2.5 first:pt-0 last:pb-0">
                          <div class="min-w-0">
                            <p class="truncate text-sm font-medium text-foreground">
                              {example.title}
                            </p>
                            <p class="mt-1 text-xs text-muted-foreground">
                              {example.severity} / {example.status}
                              <span class="mx-1.5 opacity-50">•</span> session {example.session_id}
                            </p>
                          </div>
                          <.link
                            navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/sessions/#{example.session_id}/observability"}
                            class="shrink-0 inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
                          >
                            Open run <.icon name="hero-arrow-up-right" class="size-3" />
                          </.link>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </section>
            <% end %>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp problem_key_id(key) do
    key
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
