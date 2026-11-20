defmodule ControlKeelWeb.WorkspaceServiceAccountsLive do
  @moduledoc """
  Service-account management for a workspace at `/:org_slug/workspaces/:ws_slug/service-accounts`.

  Admin+owner of the workspace's org can list, create, rotate, and revoke
  service accounts. Plaintext tokens are shown exactly once at creation
  and rotation time; the DB stores only a hash.

  Cross-org access is rejected at mount, and every mutation re-checks that
  the target service account belongs to this workspace (LiveView event
  payloads are client-controlled, so an id alone must never authorize an
  action). Plaintext tokens are shown exactly once at creation
  and rotation time; the DB stores only a hash.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Platform
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Service accounts", "admin") do
      {:ok, socket} ->
        workspace = socket.assigns.workspace

        {:ok,
         socket
         |> assign(:page_title, "Service accounts — #{workspace.name}")
         |> assign(:accounts, Platform.list_service_accounts(workspace.id))
         |> assign(:new_token, nil)
         |> assign(:new_token_for, nil)
         |> assign(:create_form, to_form(%{"name" => "", "scopes" => ""}, as: :sa))
         |> assign(:create_error, nil)}

      {:error, socket} ->
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
      case Platform.provision_agent_identity(
             socket.assigns.workspace.id,
             %{
               "name" => name,
               "scopes" => scopes
             },
             actor: nhi_actor(socket),
             created_by_user_id: created_by_user_id(socket)
           ) do
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
         %ServiceAccount{} <-
           Platform.get_service_account_for_workspace(sa_id, socket.assigns.workspace.id),
         {:ok, _} <- Platform.revoke_agent_identity(sa_id, actor: nhi_actor(socket)) do
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
         %ServiceAccount{} <-
           Platform.get_service_account_for_workspace(sa_id, socket.assigns.workspace.id),
         {:ok, %{service_account: sa, token: token}} <-
           Platform.rotate_agent_identity_token(sa_id, actor: nhi_actor(socket)) do
      {:noreply,
       socket
       |> assign(:accounts, Platform.list_service_accounts(socket.assigns.workspace.id))
       |> assign(:new_token, token)
       |> assign(:new_token_for, sa.name)
       |> put_flash(:info, "Rotated token for #{sa.name}.")}
    else
      {:error, :expired} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This token has expired and cannot be rotated. Create a new service account or extend its expiry first."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not rotate token.")}
    end
  end

  def handle_event("dismiss-token", _params, socket) do
    {:noreply, assign(socket, :new_token, nil) |> assign(:new_token_for, nil)}
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

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
          <.button type="button" variant="secondary" phx-click="dismiss-token">
            Dismiss
          </.button>
        </div>
      <% end %>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Create service account</h2>
        <.form for={@create_form} phx-submit="create" class="flex flex-col gap-3">
          <.input field={@create_form[:name]} type="text" label="Name" required />
          <div>
            <.input
              field={@create_form[:scopes]}
              type="text"
              label="Scopes (space or comma separated)"
              placeholder="mcp:access context:read findings:write"
            />
            <p class="mt-1 text-xs text-muted-foreground">
              Use <code>admin</code> for full access, or scope strings like <code>mcp:access</code>.
            </p>
          </div>
          <%= if @create_error do %>
            <p class="text-muted-foreground">{@create_error}</p>
          <% end %>
          <.button type="submit" class="self-start">Create</.button>
        </.form>
      </div>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Service accounts</h2>
        <%= if @accounts == [] do %>
          <p class="max-w-[48rem]">No service accounts yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Scopes</th>
                <th>Status</th>
                <th>Expires</th>
                <th>Last used</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for sa <- @accounts do %>
                <tr id={"sa-#{sa.id}"}>
                  <td>{sa.name}</td>
                  <td><code>{ServiceAccount.scope_list(sa) |> Enum.join(" ")}</code></td>
                  <td>
                    <%= if ServiceAccount.expired?(sa) do %>
                      <span
                        data-sa-status="expired"
                        class="inline-flex items-center rounded-full bg-warning/10 px-2.5 py-0.5 text-xs font-medium text-warning ring-1 ring-inset ring-warning/20"
                      >
                        expired
                      </span>
                    <% else %>
                      {sa.status}
                    <% end %>
                  </td>
                  <td>{format_datetime(sa.expires_at, "never")}</td>
                  <td>{format_datetime(sa.last_used_at, "never")}</td>
                  <td>
                    <%= if sa.status == "active" do %>
                      <%= if not ServiceAccount.expired?(sa) do %>
                        <.button
                          type="button"
                          variant="secondary"
                          phx-click="rotate"
                          phx-value-id={sa.id}
                        >
                          Rotate
                        </.button>
                      <% end %>
                      <.button
                        type="button"
                        variant="destructive"
                        phx-click="revoke"
                        phx-value-id={sa.id}
                        data-confirm={"Revoke #{sa.name}?"}
                      >
                        Revoke
                      </.button>
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

  # Credential lifecycle is exactly what a customer audits, so these mutations go
  # through the NHI-audited wrappers (provision/revoke/rotate_agent_identity) rather
  # than the raw Platform functions, which record nothing. The API and CLI paths
  # already used the wrappers; this LiveView was the odd one out (issue #250).
  defp nhi_actor(socket) do
    case socket.assigns[:current_user] do
      %{email: email} -> "web:#{email}"
      _ -> "web:unknown"
    end
  end

  defp created_by_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end
end
