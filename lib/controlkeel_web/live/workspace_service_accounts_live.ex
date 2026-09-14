defmodule ControlKeelWeb.WorkspaceServiceAccountsLive do
  @moduledoc """
  Service-account management for a workspace at `/:org_slug/workspaces/:ws_slug/service-accounts`.

  Admin+owner of the workspace's org can list, create, rotate, and revoke
  service accounts. Plaintext tokens are shown exactly once at creation
  and rotation time; the DB stores only a hash.

  Cross-org access is rejected at mount.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Platform
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeelWeb.OrgAuth

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug}, _session, socket) do
    case OrgAuth.authorize_workspace(socket, slug, ws_slug, "admin") do
      {:ok, socket, _org, workspace, _membership} ->
        {:ok,
         socket
         |> assign(:page_title, "Service accounts — #{workspace.name}")
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
             %{label: "Service accounts", to: nil}
           ]
         )
         |> assign(:accounts, Platform.list_service_accounts(workspace.id))
         |> assign(:new_token, nil)
         |> assign(:new_token_for, nil)
         |> assign(:create_form, to_form(%{"name" => "", "scopes" => ""}, as: :sa))
         |> assign(:create_error, nil)}

      {:halt, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_event("create", %{"sa" => %{"name" => name, "scopes" => raw_scopes}}, socket) do
    name = name |> to_string() |> String.trim()
    scopes = parse_scopes(raw_scopes)

    if name == "" do
      {:noreply, assign(socket, :create_error, "Name is required.")}
    else
      case Platform.create_service_account(socket.assigns.workspace.id, %{
             "name" => name,
             "scopes" => scopes
           }) do
        {:ok, %{service_account: sa, token: token}} ->
          {:noreply,
           socket
           |> assign(:accounts, Platform.list_service_accounts(socket.assigns.workspace.id))
           |> assign(:new_token, token)
           |> assign(:new_token_for, sa.name)
           |> assign(:create_form, to_form(%{"name" => "", "scopes" => ""}, as: :sa))
           |> assign(:create_error, nil)
           |> put_flash(:info, "Created service account #{sa.name}.")}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply,
           socket
           |> assign(
             :create_error,
             Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
           )}
      end
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    with {sa_id, ""} <- Integer.parse(id),
         {:ok, _} <- Platform.revoke_service_account(sa_id) do
      {:noreply,
       socket
       |> assign(:accounts, Platform.list_service_accounts(socket.assigns.workspace.id))
       |> put_flash(:info, "Service account revoked.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not revoke service account.")}
    end
  end

  def handle_event("rotate", %{"id" => id}, socket) do
    with {sa_id, ""} <- Integer.parse(id),
         {:ok, %{service_account: sa, token: token}} <- Platform.rotate_service_account(sa_id) do
      {:noreply,
       socket
       |> assign(:accounts, Platform.list_service_accounts(socket.assigns.workspace.id))
       |> assign(:new_token, token)
       |> assign(:new_token_for, sa.name)
       |> put_flash(:info, "Rotated token for #{sa.name}.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not rotate token.")}
    end
  end

  def handle_event("dismiss-token", _params, socket) do
    {:noreply, assign(socket, :new_token, nil) |> assign(:new_token_for, nil)}
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
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Service accounts</h1>
          <p class="text-muted-foreground text-[1.05rem] leading-[1.7] max-w-[48rem]">
            Machine identities for CI, MCP, and external integrations. Tokens are shown once at creation or rotation; store them securely.
          </p>
        </div>
      </div>

      <%= if @new_token do %>
        <div
          class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6"
          id="new-token-banner"
          style="border-color: rgba(190, 242, 100, 0.4);"
        >
          <p>
            <strong>Token for {@new_token_for}.</strong> Copy it now — it will not be shown again.
          </p>
          <pre><code id="new-token-value">{@new_token}</code></pre>
          <button type="button" phx-click="dismiss-token">
            Dismiss
          </button>
        </div>
      <% end %>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Create service account</h2>
        <.form for={@create_form} phx-submit="create" class="flex flex-col gap-3">
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-1">Name</label>
            <input
              type="text"
              name="sa[name]"
              value={@create_form[:name].value || ""}
              required
              class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-1">
              Scopes (space or comma separated)
            </label>
            <input
              type="text"
              name="sa[scopes]"
              value={@create_form[:scopes].value || ""}
              placeholder="mcp:access context:read findings:write"
              class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
            />
            <p class="mt-1 text-xs text-muted-foreground">
              Use <code>admin</code> for full access, or scope strings like <code>mcp:access</code>.
            </p>
          </div>
          <%= if @create_error do %>
            <p class="text-muted-foreground">{@create_error}</p>
          <% end %>
          <button type="submit" class="self-start">Create</button>
        </.form>
      </div>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Active service accounts</h2>
        <%= if @accounts == [] do %>
          <p class="max-w-[48rem]">No service accounts yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Scopes</th>
                <th>Status</th>
                <th>Last used</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for sa <- @accounts do %>
                <tr id={"sa-#{sa.id}"}>
                  <td>{sa.name}</td>
                  <td><code>{ServiceAccount.scope_list(sa) |> Enum.join(" ")}</code></td>
                  <td>{sa.status}</td>
                  <td>{format_dt(sa.last_used_at)}</td>
                  <td>
                    <%= if sa.status == "active" do %>
                      <button
                        type="button"
                        phx-click="rotate"
                        phx-value-id={sa.id}
                      >
                        Rotate
                      </button>
                      <button
                        type="button"
                        phx-click="revoke"
                        phx-value-id={sa.id}
                        data-confirm={"Revoke #{sa.name}?"}
                      >
                        Revoke
                      </button>
                    <% end %>
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

  defp parse_scopes(raw) when is_binary(raw) do
    raw
    |> String.split([" ", ","], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_scopes(_), do: []

  # Access is authorized per-URL in `ControlKeelWeb.OrgAuth` (admin+).

  defp format_dt(nil), do: "never"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
