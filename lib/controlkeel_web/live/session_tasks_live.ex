defmodule ControlKeelWeb.SessionTasksLive do
  @moduledoc """
  Task context, dependency graph, and execution checklist for a session.
  Routed at `/sessions/:id/tasks`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if Accounts.session_accessible?(session, org_id) do
          if connected?(socket), do: schedule_refresh()
          {:ok, mount_session(socket, session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        if connected?(socket), do: schedule_refresh()
        {:ok, mount_session(socket, session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply, assign_session_tasks(socket, session)}
    end
  end

  @impl true
  def handle_event("complete_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, task} <- Mission.complete_task(task_id),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task completed: #{task.title}.")
       |> assign_session_tasks(session)}
    else
      {:error, :unresolved_findings, findings} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{length(findings)} unresolved finding(s) must be approved or resolved before marking this task done."
         )}

      {:error, :proof_not_ready, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, :invalid_id} ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not complete that task.")}

      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not complete that task.")}
    end
  end

  @impl true
  def handle_event("generate_proof", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _proof} <- Mission.generate_proof_bundle(task_id),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Proof bundle generated.")
       |> assign_session_tasks(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not generate proof bundle.")}
    end
  end

  @impl true
  def handle_event("pause_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.pause_task(task_id, "session_tasks"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task paused.")
       |> assign_session_tasks(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not pause task.")}
    end
  end

  @impl true
  def handle_event("resume_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.resume_task(task_id, "session_tasks"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task resumed.")
       |> assign_session_tasks(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not resume task.")}
    end
  end

  defp mount_session(socket, session) do
    socket
    |> assign(:page_title, "#{session.title} — Tasks")
    |> assign_session_tasks(session)
  end

  defp assign_session_tasks(socket, session) do
    task_graph = Mission.session_task_graph(session.id)
    task_title_by_id = Map.new(task_graph.tasks, &{&1.id, &1.title})
    current = current_task(session.tasks)

    assign(socket,
      session: session,
      current_task: current,
      current_proof_summary: current && Mission.proof_summary_for_task(current),
      active_findings: Enum.count(session.findings || [], &(&1.status in ["open", "blocked"])),
      latest_proofs: Mission.latest_proof_bundles_for_session(session.id),
      task_graph: task_graph,
      task_title_by_id: task_title_by_id
    )
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _error -> {:error, :invalid_id}
    end
  end

  defp parse_id(_id), do: {:error, :invalid_id}

  defp current_task(nil), do: nil
  defp current_task([]), do: nil

  defp current_task(tasks) do
    Enum.find(tasks, &(&1.status == "in_progress")) ||
      Enum.find(tasks, &(&1.status == "queued")) ||
      Enum.find(tasks, &(&1.status == "paused")) ||
      List.first(tasks)
  end

  defp task_status_label(%{status: "verified"}), do: "verified"
  defp task_status_label(%{status: "done"}), do: "done, unverified"

  defp task_status_label(%{status: status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp task_status_label(_task), do: "unknown"

  defp task_status_pill_class("verified"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp task_status_pill_class("done"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp task_status_pill_class(_status),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp done_unverified?(%{status: "done"}), do: true
  defp done_unverified?(_task), do: false

  defp task_verification_label(_task, %{"verification_status" => "strong"}),
    do: "verification strong"

  defp task_verification_label(_task, %{"verification_status" => "moderate"}),
    do: "verification moderate"

  defp task_verification_label(_task, %{"verification_status" => "weak"}),
    do: "verification weak"

  defp task_verification_label(_task, %{
         bundle: %{"verification_assessment" => %{"status" => "strong"}}
       }),
       do: "verification strong"

  defp task_verification_label(
         _task,
         %{bundle: %{"verification_assessment" => %{"status" => "moderate"}}}
       ),
       do: "verification moderate"

  defp task_verification_label(_task, %{
         bundle: %{"verification_assessment" => %{"status" => "weak"}}
       }),
       do: "verification weak"

  defp task_verification_label(task, _proof_summary),
    do:
      if(done_unverified?(task), do: "needs verification evidence", else: "verification pending")

  defp task_decision_prompts(task) do
    task
    |> Mission.review_gate_status()
    |> Map.get("decision_prompts", [])
    |> Enum.take(2)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-[1180px] w-full px-4 pt-8 pb-16 space-y-8">
      <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4">
        <div class="space-y-1 min-w-0">
          <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
            {@session.title} — Tasks
          </h2>
          <p class="text-muted-foreground">
            Current task context, dependency graph, and execution checklist.
          </p>
        </div>
      </div>

      <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary pb-3 border-b">
          Current task context
        </p>
        <%= if @current_task do %>
          <div class="flex items-center justify-between gap-4 mt-4">
            <div class="flex items-center gap-3 min-w-0">
              <span class={[
                "size-2.5 rounded-full inline-block shrink-0",
                @current_task.status in ["done", "verified"] && "bg-[var(--ck-success)]",
                @current_task.status == "in_progress" && "bg-primary",
                @current_task.status == "queued" && "bg-[var(--ck-warning)]",
                @current_task.status == "paused" && "bg-info",
                @current_task.status == "blocked" && "bg-destructive"
              ]}>
              </span>
              <strong class="truncate">{@current_task.title}</strong>
            </div>
            <span class={task_status_pill_class(@current_task.status)}>
              {task_status_label(@current_task)}
            </span>
          </div>
          <p class="text-sm text-muted-foreground mt-1">{@current_task.validation_gate}</p>
          <div class="flex flex-wrap items-center gap-x-5 gap-y-2 mt-4 pt-4 border-t">
            <button
              :if={@current_task.status not in ["done", "verified"]}
              id={"current-task-complete-#{@current_task.id}"}
              type="button"
              class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-[var(--ck-success)]/15 text-[var(--ck-success)] border border-[var(--ck-success)]/30 hover:bg-[var(--ck-success)]/25 hover:text-[var(--ck-success)] cursor-pointer"
              phx-click="complete_task"
              phx-value-id={@current_task.id}
            >
              Complete
            </button>
            <button
              id={"current-task-generate-proof-#{@current_task.id}"}
              type="button"
              class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-primary/15 text-primary border border-primary/30 hover:bg-primary/25 hover:text-primary cursor-pointer"
              phx-click="generate_proof"
              phx-value-id={@current_task.id}
            >
              Generate proof
            </button>
            <button
              :if={@current_task.status in ["queued", "in_progress", "blocked"]}
              id={"current-task-pause-#{@current_task.id}"}
              type="button"
              class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground cursor-pointer"
              phx-click="pause_task"
              phx-value-id={@current_task.id}
            >
              Pause
            </button>
            <button
              :if={@current_task.status == "paused"}
              id={"current-task-resume-#{@current_task.id}"}
              type="button"
              class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground cursor-pointer"
              phx-click="resume_task"
              phx-value-id={@current_task.id}
            >
              Resume
            </button>
            <.link
              :if={Map.get(@latest_proofs, @current_task.id)}
              navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, @current_task.id).id}"}
              class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground cursor-pointer"
            >
              View proof
            </.link>
          </div>
          <%= if @current_proof_summary do %>
            <div class="flex flex-wrap gap-2 mt-3">
              <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2.5 py-1 text-xs text-muted-foreground">
                v{@current_proof_summary["version"]}
              </span>
              <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2.5 py-1 text-xs text-muted-foreground">
                risk {@current_proof_summary["risk_score"]}
              </span>
              <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2.5 py-1 text-xs text-muted-foreground">
                {task_verification_label(@current_task, @current_proof_summary)}
              </span>
              <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2.5 py-1 text-xs text-muted-foreground">
                {if @current_proof_summary["deploy_ready"],
                  do: "deploy ready",
                  else: "review required"}
              </span>
            </div>
          <% else %>
            <p :if={done_unverified?(@current_task)} class="text-sm text-muted-foreground mt-1">
              Execution finished, but CK has not verified this task yet. Add checks or regenerate proof.
            </p>
          <% end %>
        <% else %>
          <p class="text-sm text-muted-foreground mt-1">No active task context is available yet.</p>
        <% end %>

        <p class="mt-8 pt-6 border-t text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
          Task dependencies
        </p>
        <%= if @task_graph.edges == [] do %>
          <p class="text-sm text-muted-foreground mt-1" id="session-tasks-deps-empty">
            No dependency edges are recorded yet. When tasks include architecture, feature, and release tracks, edges appear here. The checklist below stays ordered by position.
          </p>
        <% else %>
          <div class="mt-4 space-y-6">
            <ul class="space-y-2 list-none p-0 m-0 mt-2" id="session-tasks-edges">
              <%= for edge <- @task_graph.edges do %>
                <li>
                  {Map.get(@task_title_by_id, edge.from_task_id, "Task #{edge.from_task_id}")}
                  <span class="text-muted-foreground"> → </span>
                  {Map.get(@task_title_by_id, edge.to_task_id, "Task #{edge.to_task_id}")}
                  <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground ml-1.5">
                    {edge.dependency_type}
                  </span>
                </li>
              <% end %>
            </ul>
            <div class="mt-6">
              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
                Ready (dependencies satisfied)
              </p>
              <p class="text-sm text-muted-foreground mt-1" id="session-tasks-ready">
                <%= if @task_graph.ready_task_ids == [] do %>
                  No tasks are ready to advance right now.
                <% else %>
                  {Enum.map_join(@task_graph.ready_task_ids, ", ", fn id ->
                    Map.get(@task_title_by_id, id, "Task #{id}")
                  end)}
                <% end %>
              </p>
            </div>
          </div>
        <% end %>

        <p class="mt-8 pt-6 border-t text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
          Task checklist
        </p>
        <ol class="space-y-3 list-none p-0 m-0 mt-3" id="session-tasks-checklist">
          <%= for task <- @session.tasks do %>
            <li class="p-4 rounded-2xl border bg-muted/[0.03] flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div>
                <div class="flex items-center gap-2 mb-1">
                  <span class={[
                    "size-2.5 rounded-full inline-block shrink-0",
                    task.status in ["done", "verified"] && "bg-[var(--ck-success)]",
                    task.status == "in_progress" && "bg-primary",
                    task.status == "queued" && "bg-[var(--ck-warning)]",
                    task.status == "paused" && "bg-info",
                    task.status == "blocked" && "bg-destructive"
                  ]}>
                  </span>
                  <strong>{task.title}</strong>
                  <span class={task_status_pill_class(task.status)}>
                    {task_status_label(task)}
                  </span>
                </div>
                <p class="text-sm text-muted-foreground">{task.validation_gate}</p>
                <%= if task.rollback_boundary do %>
                  <p class="text-xs text-muted-foreground mt-0.5">
                    Rollback: {task.rollback_boundary}
                  </p>
                <% end %>
                <%= if task.status == "in_progress" and @active_findings > 0 do %>
                  <p class="text-sm text-[var(--ck-warning)] mt-1">
                    {@active_findings} unresolved finding{if @active_findings != 1, do: "s"} — review before marking done
                  </p>
                <% end %>
                <%= for prompt <- task_decision_prompts(task) do %>
                  <p class="text-xs text-muted-foreground mt-0.5">
                    {prompt}
                  </p>
                <% end %>
              </div>
              <div class="flex flex-col items-start md:items-end gap-1 shrink-0">
                <%= if task.confidence_score do %>
                  <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.7rem] text-muted-foreground">
                    {trunc(task.confidence_score * 100)}% confidence
                  </span>
                <% end %>
                <span
                  :if={Map.get(@latest_proofs, task.id)}
                  class="text-xs text-muted-foreground"
                >
                  {task_verification_label(task, Map.get(@latest_proofs, task.id))}
                </span>
                <span
                  :if={done_unverified?(task) and is_nil(Map.get(@latest_proofs, task.id))}
                  class="text-xs text-muted-foreground"
                >
                  needs verification evidence
                </span>
                <div class="flex flex-wrap items-center justify-start md:justify-end gap-2 mt-1">
                  <%= if Map.get(@latest_proofs, task.id) do %>
                    <.link
                      navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, task.id).id}"}
                      class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground cursor-pointer"
                    >
                      View proof
                    </.link>
                  <% end %>
                  <button
                    :if={task.status not in ["done", "verified"]}
                    id={"task-complete-#{task.id}"}
                    type="button"
                    class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-[var(--ck-success)]/15 text-[var(--ck-success)] border border-[var(--ck-success)]/30 hover:bg-[var(--ck-success)]/25 hover:text-[var(--ck-success)] cursor-pointer"
                    phx-click="complete_task"
                    phx-value-id={task.id}
                  >
                    Complete
                  </button>
                  <button
                    id={"task-generate-proof-#{task.id}"}
                    type="button"
                    class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-primary/15 text-primary border border-primary/30 hover:bg-primary/25 hover:text-primary cursor-pointer"
                    phx-click="generate_proof"
                    phx-value-id={task.id}
                  >
                    Generate proof
                  </button>
                  <button
                    :if={task.status in ["queued", "in_progress", "blocked"]}
                    id={"task-pause-#{task.id}"}
                    type="button"
                    class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground cursor-pointer"
                    phx-click="pause_task"
                    phx-value-id={task.id}
                  >
                    Pause
                  </button>
                  <button
                    :if={task.status == "paused"}
                    id={"task-resume-#{task.id}"}
                    type="button"
                    class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground cursor-pointer"
                    phx-click="resume_task"
                    phx-value-id={task.id}
                  >
                    Resume
                  </button>
                </div>
              </div>
            </li>
          <% end %>
        </ol>
      </div>
    </section>
    """
  end
end
