defmodule ControlKeelWeb.SessionResumePacketLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

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

          SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
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

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org
    current = current_task(session.tasks)

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
      %{label: "Resume packet", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Resume packet")
    |> assign(:session, session)
    |> assign(:current_task, current)
    |> assign(:resume_packet, resume_packet(current))
    |> assign(:checkpoints, Mission.list_task_checkpoints(session.id))
  end

  defp resume_packet(nil), do: nil

  defp resume_packet(task) do
    case Mission.resume_packet(task.id) do
      {:ok, packet} -> packet
      _error -> nil
    end
  end

  defp current_task(tasks) do
    Enum.find(tasks, &(&1.status == "in_progress")) ||
      Enum.find(tasks, &(&1.status == "paused")) ||
      Enum.find(tasks, &(&1.status == "blocked")) ||
      Enum.find(tasks, &(&1.status == "queued"))
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
      <.page_title
        title="Resume packet"
        subtitle="Everything needed to pick the current task back up."
      />

      <%= if @current_task && @resume_packet do %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Current task</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {task_status_label(@current_task.status)}
            </p>
            <p class="mt-1 text-xs text-muted-foreground">{@current_task.title}</p>
          </article>

          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Unresolved findings</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {length(@resume_packet["unresolved_findings"] || [])}
            </p>
            <p class="mt-1 text-xs text-muted-foreground">Blocking this task</p>
          </article>

          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Recent runs</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {length(@resume_packet["latest_invocations"] || [])}
            </p>
            <p class="mt-1 text-xs text-muted-foreground">Latest agent invocations</p>
          </article>

          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Memory hits</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {length(@resume_packet["memory_hits"] || [])}
            </p>
            <p class="mt-1 text-xs text-muted-foreground">Relevant past decisions</p>
          </article>
        </div>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <.section_title>Where things stand</.section_title>
              <p class="mt-1 text-sm text-muted-foreground">
                Gate, budget, proof, and workspace snapshot for {@current_task.title}.
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <.link
                navigate={
                  ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/tasks"
                }
                class="inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary transition cursor-pointer"
              >
                Open tasks <.icon name="hero-arrow-right" class="size-3.5" />
              </.link>
              <.link
                navigate={
                  ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/findings"
                }
                class="inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary transition cursor-pointer"
              >
                Open findings <.icon name="hero-arrow-right" class="size-3.5" />
              </.link>
            </div>
          </div>

          <dl class="mt-5 grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4 text-sm">
            <div>
              <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Validation gate
              </dt>
              <dd class="mt-1 text-foreground">
                {@resume_packet["validation_gate"] || "No gate recorded"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Review gate
              </dt>
              <dd class="mt-1 text-foreground">
                {review_gate_label(@resume_packet["review_gate"])}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Proof evidence
              </dt>
              <dd class="mt-1 text-foreground">
                {proof_label(@resume_packet["proof_summary"])}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Budget
              </dt>
              <dd class="mt-1 text-foreground">
                {budget_label(@resume_packet["budget_summary"])}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Workspace
              </dt>
              <dd class="mt-1 font-mono text-xs text-foreground">
                {workspace_label(@resume_packet)}
              </dd>
            </div>
            <div :if={task_depth(@resume_packet)}>
              <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Graph depth
              </dt>
              <dd class="mt-1 text-foreground">{task_depth(@resume_packet)}</dd>
            </div>
          </dl>

          <div :if={decision_prompts(@resume_packet) != []} class="mt-5 border-t pt-4">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Open decisions
            </p>
            <ul class="mt-2 space-y-1 text-sm text-muted-foreground list-none p-0 m-0">
              <%= for prompt <- decision_prompts(@resume_packet) do %>
                <li>{prompt}</li>
              <% end %>
            </ul>
          </div>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>Blockers</.section_title>
          <p class="mt-1 text-sm text-muted-foreground">
            Unresolved findings captured in this packet.
          </p>
          <%= if @resume_packet["unresolved_findings"] in [nil, []] do %>
            <p class="mt-4 text-sm text-muted-foreground">No unresolved findings.</p>
          <% else %>
            <ul class="mt-4 divide-y divide-border border-y list-none p-0 m-0">
              <%= for finding <- @resume_packet["unresolved_findings"] do %>
                <li class="px-4 py-3">
                  <div class="flex flex-wrap items-center justify-between gap-2">
                    <strong class="text-sm font-medium text-foreground">
                      {finding.rule_id}
                    </strong>
                    <span class="flex items-center gap-1.5">
                      <span class={[
                        "inline-flex rounded-full px-2 py-0.5 text-[0.65rem] font-semibold capitalize ring-1",
                        finding.severity in ["critical", "high"] &&
                          "bg-destructive/10 text-destructive ring-destructive/20",
                        finding.severity in ["medium", "moderate"] &&
                          "bg-[var(--ck-warning)]/10 text-[var(--ck-warning)] ring-[var(--ck-warning)]/20",
                        finding.severity in ["low"] &&
                          "bg-[var(--ck-success)]/10 text-[var(--ck-success)] ring-[var(--ck-success)]/20",
                        finding.severity not in ["critical", "high", "medium", "moderate", "low"] &&
                          "bg-muted text-muted-foreground ring-border"
                      ]}>
                        {finding.severity}
                      </span>
                      <span class="inline-flex rounded-full px-2 py-0.5 text-[0.65rem] font-semibold capitalize ring-1 bg-muted text-muted-foreground ring-border">
                        {finding.status}
                      </span>
                    </span>
                  </div>
                  <p class="mt-1 text-sm text-muted-foreground">{finding.plain_message}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>Latest runs</.section_title>
          <p class="mt-1 text-sm text-muted-foreground">
            What the agent last executed for this task.
          </p>
          <%= if @resume_packet["latest_invocations"] in [nil, []] do %>
            <p class="mt-4 text-sm text-muted-foreground">No runs recorded yet.</p>
          <% else %>
            <ul class="mt-4 divide-y divide-border border-y list-none p-0 m-0">
              <%= for run <- @resume_packet["latest_invocations"] do %>
                <li class="px-4 py-3">
                  <div class="flex flex-wrap items-center justify-between gap-2">
                    <strong class="text-sm font-medium font-mono text-foreground">
                      {run.tool}
                    </strong>
                    <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground">
                      {run.decision}
                    </span>
                  </div>
                  <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <span>{run.provider} · {run.model}</span>
                    <span class="font-mono tabular-nums tracking-tight">
                      {run_timestamp(run.timestamp)}
                    </span>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>Relevant memory</.section_title>
          <p class="mt-1 text-sm text-muted-foreground">
            Past decisions this task can build on.
          </p>
          <%= if @resume_packet["memory_hits"] in [nil, []] do %>
            <p class="mt-4 text-sm text-muted-foreground">No matching memory recorded yet.</p>
          <% else %>
            <ul class="mt-4 space-y-3 list-none p-0 m-0">
              <%= for hit <- @resume_packet["memory_hits"] do %>
                <li>
                  <strong class="text-sm font-medium text-foreground">{hit.title}</strong>
                  <p class="text-sm text-muted-foreground">{hit.summary}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <details class="rounded-2xl border bg-card p-5 shadow-card">
          <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary cursor-pointer select-none">
            View resume packet JSON
          </summary>
          <pre class="p-4 max-h-96 overflow-auto border rounded-2xl bg-muted/[0.03] text-sm font-mono whitespace-pre-wrap break-all leading-relaxed mt-4">{Jason.encode!(@resume_packet, pretty: true)}</pre>
        </details>
      <% else %>
        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>No active task</.section_title>
          <p class="mt-1 text-sm text-muted-foreground">
            There is nothing to resume right now. Start or queue a task to capture a resume packet.
          </p>
          <.link
            navigate={
              ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/tasks"
            }
            class="mt-4 inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary transition cursor-pointer"
          >
            Open tasks <.icon name="hero-arrow-right" class="size-3.5" />
          </.link>
        </section>
      <% end %>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Checkpoint history</.section_title>
        <p class="mt-1 text-sm text-muted-foreground">
          Durable pause and resume snapshots for this session.
        </p>
        <%= if @checkpoints == [] do %>
          <p class="mt-4 text-sm text-muted-foreground">
            No checkpoints recorded yet. Pause or resume a task to record one.
          </p>
        <% else %>
          <ul class="mt-4 divide-y divide-border border-y list-none p-0 m-0">
            <%= for checkpoint <- @checkpoints do %>
              <li class="px-4 py-3">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <strong class="text-sm font-medium text-foreground">
                    {checkpoint.summary}
                  </strong>
                  <span class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.65rem] font-semibold capitalize ring-1 bg-muted text-muted-foreground ring-border">
                    {checkpoint.checkpoint_type}
                  </span>
                </div>
                <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                  <span class="inline-flex items-center rounded-md border border-input bg-background px-1.5 py-0.5">
                    {checkpoint.created_by}
                  </span>
                  <span class="font-mono tabular-nums tracking-tight">
                    {run_timestamp(checkpoint.inserted_at)}
                  </span>
                </div>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp task_status_label(status) when is_binary(status),
    do: status |> String.replace("_", " ") |> String.capitalize()

  defp task_status_label(_status), do: "Unknown"

  defp review_gate_label(%{"phase" => phase, "execution_ready" => ready}) do
    "#{phase} · #{if ready, do: "execution ready", else: "execution blocked"}"
  end

  defp review_gate_label(_gate), do: "No review gate recorded"

  defp proof_label(%{"version" => version, "deploy_ready" => deploy_ready}) do
    "v#{version} · #{if deploy_ready, do: "deploy ready", else: "review required"}"
  end

  defp proof_label(_proof), do: "No proof bundle yet"

  defp budget_label(%{"spent_cents" => spent, "budget_cents" => budget}) do
    "$#{spent / 100} of $#{budget / 100} spent"
  end

  defp budget_label(_budget), do: "No budget recorded"

  defp workspace_label(packet) do
    branch = get_in(packet, ["workspace_context", "git", "branch"]) || "no-branch"
    sha = get_in(packet, ["workspace_context", "git", "head_sha"]) || "unknown"

    "#{branch} · #{String.slice(sha, 0, 7)}"
  end

  defp task_depth(packet), do: get_in(packet, ["decomposition", "task", "depth"])

  defp decision_prompts(packet) do
    packet |> get_in(["review_gate", "decision_prompts"]) |> List.wrap() |> Enum.take(2)
  end

  defp run_timestamp(nil), do: "unknown"

  defp run_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")
end
