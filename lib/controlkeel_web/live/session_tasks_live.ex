defmodule ControlKeelWeb.SessionTasksLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case SessionScope.fetch_session(id) do
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
    task_graph = Mission.session_task_graph(session.id)
    task_title_by_id = Map.new(task_graph.tasks, &{&1.id, &1.title})
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
      %{label: "Tasks", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Tasks")
    |> assign(:session, session)
    |> assign(:current_task, current)
    |> assign(:current_proof_summary, current |> Mission.proof_summary_for_task())
    |> assign(:latest_proofs, Mission.latest_proof_bundles_for_session(session.id))
    |> assign(:task_graph, task_graph)
    |> assign(:task_title_by_id, task_title_by_id)
    |> assign(
      :active_findings,
      Enum.count(session.findings || [], &(&1.status in ["open", "blocked"]))
    )
  end

  @impl true
  def handle_info(:refresh, socket) do
    opts = [invocations_limit: 0, reviews_limit: 0]

    case Mission.get_session_context(socket.assigns.session.id, opts) do
      nil ->
        {:noreply, SessionScope.session_not_found(socket)}

      session ->
        case SessionScope.reauthorize(socket, session) do
          {:ok, session} ->
            if connected?(socket), do: schedule_refresh()
            {:noreply, assign_session(socket, session)}

          {:error, :not_found} ->
            {:noreply, SessionScope.session_not_found(socket)}
        end
    end
  end

  @impl true
  def handle_event("complete_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         %{} = task <- Enum.find(socket.assigns.session.tasks, &(&1.id == task_id)),
         {:ok, task} <- Mission.complete_task(task.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task completed: #{task.title}.")
       |> refresh_session_after_mutation()}
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
         %{} = task <- Enum.find(socket.assigns.session.tasks, &(&1.id == task_id)),
         {:ok, _proof} <- Mission.generate_proof_bundle(task.id),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Proof bundle generated.")
       |> assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not generate proof bundle.")}
    end
  end

  @impl true
  def handle_event("pause_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         %{} = task <- Enum.find(socket.assigns.session.tasks, &(&1.id == task_id)),
         {:ok, _result} <- Mission.pause_task(task.id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task paused.")
       |> assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not pause task.")}
    end
  end

  @impl true
  def handle_event("resume_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         %{} = task <- Enum.find(socket.assigns.session.tasks, &(&1.id == task_id)),
         {:ok, _result} <- Mission.resume_task(task.id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task resumed.")
       |> assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not resume task.")}
    end
  end

  defp refresh_session_after_mutation(socket) do
    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> socket
      session -> assign_session(socket, session)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between">
        <.page_title title="Tasks" />

        <div
          class="relative"
          phx-click-away={
            JS.hide(to: "#task-dependencies-popover")
            |> JS.set_attribute({"aria-expanded", "false"}, to: "#task-dependencies-button")
          }
        >
          <.button
            id="task-dependencies-button"
            variant="outline"
            aria-haspopup="dialog"
            aria-expanded="false"
            aria-controls="task-dependencies-popover"
            phx-click={
              JS.toggle(to: "#task-dependencies-popover")
              |> JS.toggle_attribute({"aria-expanded", "true", "false"})
            }
            class="gap-2 rounded-xl px-4 py-2 text-xs uppercase tracking-[0.14em] shadow-sm"
          >
            <.icon name="hero-link" class="size-4" /> Dependencies
            <span class="inline-flex items-center rounded-full bg-muted px-2 py-0.5 text-[0.65rem] text-muted-foreground">
              {length(@task_graph.edges)}
            </span>
          </.button>

          <div
            id="task-dependencies-popover"
            class="hidden absolute right-0 top-full z-30 mt-2 w-full max-w-2xl rounded-2xl border bg-card shadow-2xl shadow-black/20"
            style="width: min(72rem, 98vw)"
          >
            <div class="max-h-[60vh] overflow-y-auto pr-1">
              <%= if @task_graph.edges == [] do %>
                <p class="text-sm text-muted-foreground" id="mission-task-deps-empty">
                  No dependency edges are recorded yet. When tasks include architecture, feature, and release tracks, edges appear here grouped by source.
                </p>
              <% else %>
                <div
                  class="divide-y divide-border overflow-hidden rounded-xl border"
                  id="mission-task-edges"
                >
                  <%= for {from_id, edges} <- @task_graph.edges |> Enum.group_by(& &1.from_task_id) |> Enum.sort_by(fn {id, _} -> id end) do %>
                    <div class="bg-muted/[0.03] p-3">
                      <div class="flex items-center gap-2 text-sm font-medium text-foreground">
                        <span class="size-2 rounded-full bg-primary shrink-0"></span>
                        {Map.get(@task_title_by_id, from_id, "Task #{from_id}")}
                        <span class="text-xs text-muted-foreground">blocks</span>
                        <span class="ml-auto text-xs text-muted-foreground">
                          {length(edges)} downstream
                        </span>
                      </div>
                      <ul class="mt-2 grid gap-1.5">
                        <%= for edge <- Enum.sort_by(edges, & &1.to_task_id) do %>
                          <li class="flex items-center gap-2 pl-4 text-sm">
                            <span class="text-muted-foreground">→</span>
                            <span class="text-foreground">
                              {Map.get(
                                @task_title_by_id,
                                edge.to_task_id,
                                "Task #{edge.to_task_id}"
                              )}
                            </span>
                            <span class={[
                              "inline-flex items-center rounded-full border px-2 py-0.5 text-[0.65rem]",
                              edge.dependency_type == "soft_gate" &&
                                "border-dashed bg-muted/[0.05] text-muted-foreground",
                              edge.dependency_type != "soft_gate" &&
                                "bg-muted/[0.05] text-muted-foreground"
                            ]}>
                              {edge.dependency_type}
                            </span>
                          </li>
                        <% end %>
                      </ul>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-card border rounded-2xl shadow-card overflow-visible">
        <table class="min-w-full divide-y divide-border text-left text-sm border-separate border-spacing-0">
          <thead class="text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
            <tr>
              <th class="bg-muted px-5 py-3 font-semibold first:rounded-tl-2xl">Task</th>
              <th class="bg-muted px-5 py-3 font-semibold">Status</th>
              <th class="bg-muted px-5 py-3 font-semibold">Confidence</th>
              <th class="bg-muted px-5 py-3 font-semibold">Ready</th>
              <th class="bg-muted px-5 py-3 font-semibold">Validation gate</th>
              <th class="bg-muted px-5 py-3 font-semibold w-px whitespace-nowrap last:rounded-tr-2xl">
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= for task <- @session.tasks do %>
              <tr
                id={"task-row-#{task.id}"}
                class={[
                  "transition hover:bg-muted/30",
                  @current_task && @current_task.id == task.id &&
                    "bg-primary/5 ring-1 ring-primary/20"
                ]}
              >
                <td class="max-w-sm px-5 py-4">
                  <div class="flex items-center gap-2">
                    <span class={[
                      "size-3 rounded-full inline-block shrink-0 ring-1 ring-border shadow-sm",
                      task.status in ["done", "verified"] && "bg-success",
                      task.status == "in_progress" && "bg-primary",
                      task.status == "queued" && "bg-warning",
                      task.status == "paused" && "bg-info",
                      task.status == "blocked" && "bg-destructive"
                    ]}>
                    </span>
                    <span class="font-medium text-foreground">{task.title}</span>
                    <span
                      :if={@current_task && @current_task.id == task.id}
                      class="inline-flex items-center rounded-full bg-primary px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wider text-primary-foreground"
                    >
                      Current
                    </span>
                  </div>
                  <div class="mt-1 flex flex-wrap gap-1.5">
                    <span
                      :if={Map.get(@latest_proofs, task.id)}
                      class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground"
                    >
                      {task_verification_label(task, Map.get(@latest_proofs, task.id))}
                    </span>
                    <span
                      :if={done_unverified?(task) and is_nil(Map.get(@latest_proofs, task.id))}
                      class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground"
                    >
                      needs verification
                    </span>
                  </div>
                  <%= if task.rollback_boundary do %>
                    <p class="mt-1 text-xs text-muted-foreground">
                      Rollback: {task.rollback_boundary}
                    </p>
                  <% end %>
                  <%= if task.status == "in_progress" and @active_findings > 0 do %>
                    <p class="mt-1 text-xs text-warning">
                      {@active_findings} unresolved finding{if @active_findings != 1, do: "s"}
                    </p>
                  <% end %>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span class={task_status_pill_class(task.status)}>{task_status_label(task)}</span>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span
                    :if={task.confidence_score}
                    class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground"
                  >
                    {trunc(task.confidence_score * 100)}% confidence
                  </span>
                  <span :if={!task.confidence_score} class="text-xs text-muted-foreground">—</span>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span
                    :if={task.id in @task_graph.ready_task_ids}
                    class="inline-flex items-center rounded-full bg-success/10 text-success ring-1 ring-success/20 px-2.5 py-1 text-xs font-semibold"
                  >
                    Ready
                  </span>
                  <span
                    :if={task.id not in @task_graph.ready_task_ids}
                    class="inline-flex items-center rounded-full bg-muted text-muted-foreground ring-1 ring-border px-2.5 py-1 text-xs"
                  >
                    Blocked
                  </span>
                </td>
                <td class="px-5 py-4 text-muted-foreground">
                  <div class="max-w-[12ch] truncate whitespace-nowrap" title={task.validation_gate}>
                    {task.validation_gate}
                  </div>
                </td>
                <td class="px-4 text-right whitespace-nowrap w-px">
                  <div id={"task-actions-wrapper-#{task.id}"} class="relative inline-flex">
                    <button
                      id={"task-actions-#{task.id}"}
                      type="button"
                      aria-label={"Actions for #{task.title}"}
                      aria-haspopup="menu"
                      aria-expanded="false"
                      phx-click={
                        JS.toggle(to: "#task-menu-#{task.id}")
                        |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                        |> JS.toggle_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                      }
                      class="inline-flex size-8 shrink-0 items-center justify-center rounded-lg border border-border bg-card text-foreground shadow-sm transition hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    >
                      <.icon name="hero-ellipsis-horizontal" class="size-5 shrink-0" />
                    </button>
                    <div
                      id={"task-menu-#{task.id}"}
                      class={[
                        "hidden absolute right-0 z-50 w-48 rounded-xl border bg-card p-1.5 shadow-2xl shadow-black/20",
                        if task == List.last(@session.tasks) do
                          "bottom-full mb-1"
                        else
                          "top-full mt-1"
                        end
                      ]}
                      phx-click-away={
                        JS.hide(to: "#task-menu-#{task.id}")
                        |> JS.remove_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                        |> JS.set_attribute({"aria-expanded", "false"},
                          to: "#task-actions-#{task.id}"
                        )
                      }
                    >
                      <button
                        :if={task.status not in ["done", "verified"]}
                        type="button"
                        class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                        phx-click={
                          JS.hide(to: "#task-menu-#{task.id}")
                          |> JS.remove_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                          |> JS.set_attribute({"aria-expanded", "false"},
                            to: "#task-actions-#{task.id}"
                          )
                          |> JS.push("complete_task", value: %{id: task.id})
                        }
                      >
                        Complete
                      </button>
                      <button
                        type="button"
                        class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                        phx-click={
                          JS.hide(to: "#task-menu-#{task.id}")
                          |> JS.remove_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                          |> JS.set_attribute({"aria-expanded", "false"},
                            to: "#task-actions-#{task.id}"
                          )
                          |> JS.push("generate_proof", value: %{id: task.id})
                        }
                      >
                        Generate proof
                      </button>
                      <button
                        :if={task.status in ["queued", "in_progress", "blocked"]}
                        type="button"
                        class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                        phx-click={
                          JS.hide(to: "#task-menu-#{task.id}")
                          |> JS.remove_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                          |> JS.set_attribute({"aria-expanded", "false"},
                            to: "#task-actions-#{task.id}"
                          )
                          |> JS.push("pause_task", value: %{id: task.id})
                        }
                      >
                        Pause
                      </button>
                      <button
                        :if={task.status == "paused"}
                        type="button"
                        class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                        phx-click={
                          JS.hide(to: "#task-menu-#{task.id}")
                          |> JS.remove_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                          |> JS.set_attribute({"aria-expanded", "false"},
                            to: "#task-actions-#{task.id}"
                          )
                          |> JS.push("resume_task", value: %{id: task.id})
                        }
                      >
                        Resume
                      </button>
                      <.link
                        :if={Map.get(@latest_proofs, task.id)}
                        navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, task.id).id}"}
                        class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                        phx-click={
                          JS.hide(to: "#task-menu-#{task.id}")
                          |> JS.remove_class("z-50", to: "#task-actions-wrapper-#{task.id}")
                          |> JS.set_attribute({"aria-expanded", "false"},
                            to: "#task-actions-#{task.id}"
                          )
                        }
                      >
                        View proof
                      </.link>
                    </div>
                  </div>
                </td>
              </tr>
            <% end %>
            <%= if @session.tasks == [] do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No tasks yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Tasks for this session will appear here.
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

  defp current_task(tasks) do
    Enum.find(tasks, &(&1.status == "in_progress")) ||
      Enum.find(tasks, &(&1.status == "paused")) ||
      Enum.find(tasks, &(&1.status == "blocked")) ||
      Enum.find(tasks, &(&1.status == "queued"))
  end

  defp task_status_label(%{status: "verified"}), do: "verified"
  defp task_status_label(%{status: "done"}), do: "done, unverified"

  defp task_status_label(%{status: status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp task_status_label(_task), do: "unknown"

  defp task_status_pill_class("verified"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp task_status_pill_class("done"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp task_status_pill_class(_status),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-muted text-muted-foreground ring-border"

  defp done_unverified?(%{status: "done"}), do: true
  defp done_unverified?(_task), do: false

  defp task_verification_label(_task, %{"verification_status" => "strong"}),
    do: "verification strong"

  defp task_verification_label(_task, %{"verification_status" => "moderate"}),
    do: "verification moderate"

  defp task_verification_label(_task, %{"verification_status" => "weak"}), do: "verification weak"

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
    do: if(done_unverified?(task), do: "unverified", else: "verification pending")

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end
end
