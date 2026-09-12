defmodule ControlKeelWeb.OrganizationSettingsLive do
  @moduledoc """
  Organization settings at `/:org_slug/settings`.

  Local mode is unrestricted. Cloud and self-hosted mode require an active
  admin or owner membership for the organization.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Organization not found.", ~p"/organizations")}

      org ->
        mode = Mode.current()
        user = socket.assigns[:current_user]

        cond do
          mode == :local ->
            mount_ok(socket, org)

          is_nil(user) ->
            {:ok,
             redirect_with_flash(
               socket,
               :error,
               "Sign in to view this organization.",
               ~p"/auth/login"
             )}

          true ->
            case Accounts.get_active_membership(user.id, org.id) do
              nil ->
                {:ok,
                 redirect_with_flash(
                   socket,
                   :error,
                   "You're not a member of that organization.",
                   ~p"/organizations"
                 )}

              membership ->
                if Accounts.role_at_least?(membership.role, "admin") do
                  mount_ok(socket, org, membership)
                else
                  {:ok,
                   redirect_with_flash(
                     socket,
                     :error,
                     "You don't have permission to change organization settings.",
                     ~p"/#{org.slug}"
                   )}
                end
            end
        end
    end
  end

  defp mount_ok(socket, org, membership \\ nil) do
    local_mode = Mode.current() == :local
    budget_cents = Accounts.org_budget_cents(org) || 0
    is_owner = local_mode || (membership && membership.role == "owner")

    {:ok,
     socket
     |> assign(:page_title, "Organization Settings - #{org.name}")
     |> assign(:org, org)
     |> assign(:nav_org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:is_owner, !!is_owner)
     |> assign(:settings_form, settings_form(org, budget_cents))
     |> assign(:settings_error, nil)
     |> assign(:page_action, nil)}
  end

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    org = socket.assigns.org
    is_owner = socket.assigns.is_owner

    org_attrs =
      %{name: params["name"]}
      |> maybe_add_owner_field("status", params["status"], is_owner)

    with {:ok, org} <- Accounts.update_org(org, org_attrs),
         {:ok, org} <- maybe_set_budget(org, params["budget_cents"], is_owner) do
      budget_cents = Accounts.org_budget_cents(org) || 0

      {:noreply,
       socket
       |> assign(:org, org)
       |> assign(:nav_org, org)
       |> assign(:page_title, "Organization Settings - #{org.name}")
       |> assign(:settings_form, settings_form(org, budget_cents))
       |> assign(:settings_error, nil)
       |> put_flash(:info, "Settings saved.")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset.errors
          |> Enum.map_join(", ", fn {field, {detail, _}} -> "#{field}: #{detail}" end)

        {:noreply, assign(socket, :settings_error, message)}

      {:error, reason} ->
        {:noreply, assign(socket, :settings_error, inspect(reason))}
    end
  end

  defp settings_form(org, budget_cents) do
    to_form(
      %{
        "name" => org.name,
        "status" => org.status,
        "budget_cents" => Integer.to_string(budget_cents)
      },
      as: :settings
    )
  end

  defp maybe_add_owner_field(attrs, _key, _value, false), do: attrs
  defp maybe_add_owner_field(attrs, _key, nil, _is_owner), do: attrs

  defp maybe_add_owner_field(attrs, key, value, true),
    do: Map.put(attrs, String.to_existing_atom(key), value)

  defp maybe_set_budget(org, _value, false), do: {:ok, org}
  defp maybe_set_budget(org, nil, _), do: {:ok, org}

  defp maybe_set_budget(org, value, true) when is_binary(value) do
    case Integer.parse(value) do
      {cents, ""} when cents >= 0 ->
        case Accounts.set_org_budget_cents(org.id, cents) do
          {:ok, updated} -> {:ok, updated}
          {:error, _} = error -> error
        end

      _ ->
        {:error, "Budget must be a non-negative integer in cents."}
    end
  end

  defp redirect_with_flash(socket, kind, message, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, message)
    |> Phoenix.LiveView.push_navigate(to: path)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-8">
      <div>
        <p class="text-sm font-medium text-primary">Organization</p>
        <h1 class="mt-1 text-2xl font-semibold tracking-tight text-foreground">Settings</h1>
        <p class="mt-2 text-sm text-muted-foreground">
          Manage the name, status, and monthly budget for {@org.name}.
        </p>
      </div>

      <section class="rounded-2xl border bg-card p-6 shadow-card">
        <.form
          for={@settings_form}
          phx-submit="save_settings"
          id="org-settings-form"
          class="space-y-5"
        >
          <.input
            field={@settings_form[:name]}
            type="text"
            label="Organization name"
            required
            class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />

          <div>
            <.input
              field={@settings_form[:status]}
              type="select"
              label="Status"
              options={[{"active", "active"}, {"disabled", "disabled"}]}
              disabled={!@is_owner}
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
            <%= unless @is_owner do %>
              <p class="mt-1 text-xs text-muted-foreground">Only owners can change status.</p>
            <% end %>
          </div>

          <div>
            <.input
              field={@settings_form[:budget_cents]}
              type="number"
              label="Monthly budget (cents)"
              disabled={!@is_owner}
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
            <%= unless @is_owner do %>
              <p class="mt-1 text-xs text-muted-foreground">Only owners can change budget.</p>
            <% end %>
          </div>

          <p class="text-xs text-muted-foreground">
            Slug <code class="text-muted-foreground">{@org.slug}</code> cannot be changed.
          </p>

          <%= if @settings_error do %>
            <p class="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">
              {@settings_error}
            </p>
          <% end %>

          <div class="flex justify-end pt-2">
            <button
              type="submit"
              class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
            >
              Save changes
            </button>
          </div>
        </.form>
      </section>
    </div>
    """
  end
end
