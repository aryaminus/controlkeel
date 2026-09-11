defmodule ControlKeelWeb.WorkspaceReposLive do
  @moduledoc """
  Workspace GitHub repository bindings at `/:org_slug/workspaces/:ws_slug/repos`.

  Admin+owner of the workspace's org can bind / unbind / list
  `WorkspaceGithubRepo` records. The page rejects access if the workspace
  belongs to a different org than the visitor's current_org_id.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug}, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      {:ok,
       socket
       |> assign(:page_title, "Repositories — #{workspace.name}")
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(
         :breadcrumbs,
         [
           %{label: "Organizations", to: ~p"/organizations"},
           %{label: workspace.org.name, to: ~p"/#{workspace.org.slug}"},
           %{
             label: workspace.name,
             to: ~p"/#{workspace.org.slug}/workspaces/#{workspace.slug}"
           },
           %{label: "Repositories", to: nil}
         ]
       )
       |> assign(:repos, Mission.list_github_repos(workspace.id))
       |> assign(:bind_form, to_form(empty_bind_params(), as: :bind))
       |> assign(:bind_error, nil)}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  @impl true
  def handle_event("bind", %{"bind" => params}, socket) do
    owner = params["owner"] |> to_string() |> String.trim()
    repo = params["repo"] |> to_string() |> String.trim()
    branch = params["default_branch"] |> to_string() |> String.trim()
    inst_id_raw = params["installation_id"] |> to_string() |> String.trim()

    opts = [
      default_branch: nil_if_empty(branch),
      installation_id: parse_int_or_nil(inst_id_raw)
    ]

    cond do
      owner == "" or repo == "" ->
        {:noreply, assign(socket, :bind_error, "Owner and repo are required.")}

      true ->
        case Mission.bind_github_repo(socket.assigns.workspace.id, owner, repo, opts) do
          {:ok, _binding} ->
            {:noreply,
             socket
             |> assign(:repos, Mission.list_github_repos(socket.assigns.workspace.id))
             |> assign(:bind_form, to_form(empty_bind_params(), as: :bind))
             |> assign(:bind_error, nil)
             |> put_flash(:info, "Bound #{owner}/#{repo}.")}

          {:error, %Ecto.Changeset{} = cs} ->
            msg =
              cs.errors
              |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

            {:noreply, assign(socket, :bind_error, msg)}
        end
    end
  end

  def handle_event("unbind", %{"owner" => owner, "repo" => repo}, socket) do
    case Mission.unbind_github_repo(socket.assigns.workspace.id, owner, repo) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:repos, Mission.list_github_repos(socket.assigns.workspace.id))
         |> put_flash(:info, "Unbound #{owner}/#{repo}.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Binding not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-12 pb-16 max-[900px]:w-[min(100%-1.25rem,1180px)] max-[900px]:pt-6"
      style="max-width: 920px; margin: 4rem auto;"
    >
      <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
        <div>
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            {@workspace.name}
          </p>
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">GitHub repositories</h1>
          <p class="text-muted-foreground text-[1.05rem] leading-[1.7] max-w-[48rem]">
            Bind GitHub repos so sessions, findings, and proofs can reference them.
            For governance via the GitHub App, set <code>installation_id</code>.
          </p>
        </div>
      </div>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Bind a repository</h2>
        <.form for={@bind_form} phx-submit="bind" class="flex flex-col gap-3">
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-sm font-medium text-muted-foreground mb-1">Owner</label>
              <input
                type="text"
                name="bind[owner]"
                value={@bind_form[:owner].value || ""}
                placeholder="acme"
                required
                class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-muted-foreground mb-1">Repo</label>
              <input
                type="text"
                name="bind[repo]"
                value={@bind_form[:repo].value || ""}
                placeholder="payments"
                required
                class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
              />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-sm font-medium text-muted-foreground mb-1">
                Default branch (optional)
              </label>
              <input
                type="text"
                name="bind[default_branch]"
                value={@bind_form[:default_branch].value || ""}
                placeholder="main"
                class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-muted-foreground mb-1">
                Installation ID (optional)
              </label>
              <input
                type="number"
                name="bind[installation_id]"
                value={@bind_form[:installation_id].value || ""}
                class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
              />
            </div>
          </div>
          <%= if @bind_error do %>
            <p class="text-muted-foreground">{@bind_error}</p>
          <% end %>
          <button type="submit" class="self-start">Bind repository</button>
        </.form>
      </div>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Bound repositories</h2>
        <%= if @repos == [] do %>
          <p class="max-w-[48rem]">No repositories bound yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Owner / Repo</th>
                <th>Default branch</th>
                <th>Installation ID</th>
                <th>Bound at</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for r <- @repos do %>
                <tr id={"binding-#{r.id}"}>
                  <td><code>{r.owner}/{r.repo}</code></td>
                  <td>{r.default_branch || "—"}</td>
                  <td>{r.installation_id || "—"}</td>
                  <td>{format_dt(r.inserted_at)}</td>
                  <td>
                    <button
                      type="button"
                      phx-click="unbind"
                      phx-value-owner={r.owner}
                      phx-value-repo={r.repo}
                      data-confirm={"Unbind #{r.owner}/#{r.repo}?"}
                    >
                      Unbind
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </section>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  defp check_workspace_access(%Workspace{org_id: nil}, _assigns),
    do: {:error, "Workspace is not bound to an org yet."}

  defp check_workspace_access(%Workspace{org_id: ws_org_id}, %{
         current_org_id: org_id,
         current_membership: membership
       })
       when is_integer(ws_org_id) and ws_org_id == org_id do
    if membership && Accounts.role_at_least?(membership.role, "admin") do
      :ok
    else
      {:error, "Admin or owner role required to manage repositories."}
    end
  end

  defp check_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp empty_bind_params do
    %{"owner" => "", "repo" => "", "default_branch" => "", "installation_id" => ""}
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value

  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_int_or_nil(_), do: nil

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
