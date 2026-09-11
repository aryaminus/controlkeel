defmodule ControlKeelWeb.WorkspaceWebhooksLive do
  @moduledoc """
  Outbound integration webhooks for a workspace at `/:org_slug/workspaces/:ws_slug/webhooks`.

  Admin+owner can list, create, and replay webhooks. The webhook secret
  is shown once at creation; the DB stores the plaintext for HMAC signing
  on emit (operators see it once via the create banner).

  Cross-org access is rejected at mount.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform
  alias ControlKeel.Platform.IntegrationWebhook
  alias ControlKeel.Repo

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug}, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      {:ok,
       socket
       |> assign(:page_title, "Webhooks — #{workspace.name}")
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
           %{label: "Webhooks", to: nil}
         ]
       )
       |> assign(:webhooks, Platform.list_webhooks(workspace.id))
       |> assign(:available_events, Platform.webhook_events())
       |> assign(:new_secret, nil)
       |> assign(:new_secret_for, nil)
       |> assign(:create_form, to_form(%{"name" => "", "url" => ""}, as: :wh))
       |> assign(:create_error, nil)}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  @impl true
  def handle_event("create", %{"wh" => params} = full_params, socket) do
    name = params["name"] |> to_string() |> String.trim()
    url = params["url"] |> to_string() |> String.trim()
    events = extract_events(full_params)

    cond do
      name == "" or url == "" ->
        {:noreply, assign(socket, :create_error, "Name and URL are required.")}

      true ->
        attrs = %{
          "name" => name,
          "url" => url,
          "subscribed_events" => events
        }

        case Platform.create_webhook(socket.assigns.workspace.id, attrs) do
          {:ok, webhook} ->
            {:noreply,
             socket
             |> assign(:webhooks, Platform.list_webhooks(socket.assigns.workspace.id))
             |> assign(:new_secret, webhook.secret)
             |> assign(:new_secret_for, webhook.name)
             |> assign(:create_form, to_form(%{"name" => "", "url" => ""}, as: :wh))
             |> assign(:create_error, nil)
             |> put_flash(:info, "Webhook #{webhook.name} created.")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply,
             assign(
               socket,
               :create_error,
               Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
             )}
        end
    end
  end

  def handle_event("replay", %{"id" => id}, socket) do
    with {wh_id, ""} <- Integer.parse(id),
         {:ok, _} <- Platform.replay_webhook(wh_id) do
      {:noreply, put_flash(socket, :info, "Webhook replayed.")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No prior delivery to replay for this webhook.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not replay webhook.")}
    end
  end

  def handle_event("dismiss-secret", _, socket) do
    {:noreply, assign(socket, :new_secret, nil) |> assign(:new_secret_for, nil)}
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
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Webhooks</h1>
          <p class="text-muted-foreground text-[1.05rem] leading-[1.7] max-w-[48rem]">
            Subscribe external systems to ControlKeel events. Each webhook gets a server-generated secret used to sign payloads.
          </p>
        </div>
      </div>

      <%= if @new_secret do %>
        <div
          class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6"
          id="new-secret-banner"
          style="border-color: rgba(190, 242, 100, 0.4);"
        >
          <p>
            <strong>Signing secret for {@new_secret_for}.</strong>
            Copy now — it will not be shown again.
          </p>
          <pre><code id="new-secret-value">{@new_secret}</code></pre>
          <button type="button" phx-click="dismiss-secret">
            Dismiss
          </button>
        </div>
      <% end %>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Create webhook</h2>
        <.form for={@create_form} phx-submit="create" class="flex flex-col gap-3">
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-1">Name</label>
            <input
              type="text"
              name="wh[name]"
              value={@create_form[:name].value || ""}
              required
              class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-1">Delivery URL</label>
            <input
              type="url"
              name="wh[url]"
              value={@create_form[:url].value || ""}
              required
              placeholder="https://example.com/hooks/controlkeel"
              class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-2">Events</label>
            <div class="grid grid-cols-2 gap-2">
              <%= for ev <- @available_events do %>
                <label class="flex items-center gap-2 text-sm text-muted-foreground">
                  <input type="checkbox" name="events[]" value={ev} />
                  <code>{ev}</code>
                </label>
              <% end %>
            </div>
          </div>
          <%= if @create_error do %>
            <p class="text-muted-foreground">{@create_error}</p>
          <% end %>
          <button type="submit" class="self-start">Create webhook</button>
        </.form>
      </div>

      <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
        <h2>Configured webhooks</h2>
        <%= if @webhooks == [] do %>
          <p class="max-w-[48rem]">No webhooks configured yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>URL</th>
                <th>Events</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for w <- @webhooks do %>
                <tr id={"webhook-#{w.id}"}>
                  <td>{w.name}</td>
                  <td><code>{w.url}</code></td>
                  <td><code>{IntegrationWebhook.event_list(w) |> Enum.join(", ")}</code></td>
                  <td>{w.status}</td>
                  <td>
                    <button
                      type="button"
                      phx-click="replay"
                      phx-value-id={w.id}
                    >
                      Replay last
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

  # ── Private ────────────────────────────────────────────────────────

  defp extract_events(%{"events" => events}) when is_list(events) do
    Enum.filter(events, &is_binary/1)
  end

  defp extract_events(_), do: []

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  defp check_workspace_access(%Workspace{org_id: nil}, _),
    do: {:error, "Workspace is not bound to an org."}

  defp check_workspace_access(%Workspace{org_id: ws_org}, %{
         current_org_id: org_id,
         current_membership: m
       })
       when is_integer(ws_org) and ws_org == org_id do
    if m && Accounts.role_at_least?(m.role, "admin"),
      do: :ok,
      else: {:error, "Admin or owner role required."}
  end

  defp check_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
