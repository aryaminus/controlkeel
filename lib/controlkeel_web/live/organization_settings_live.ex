defmodule ControlKeelWeb.OrganizationSettingsLive do
  @moduledoc """
  Organization settings at `/organizations/:slug/settings`.

  General panel mirrors the former (never-rendered) settings modal from
  `OrganizationDetailLive`: name (admin+), status and monthly budget
  (owner-only), immutable slug. Roles are re-checked server-side on save.

  ## Access

  Any active member can view (local mode is unrestricted). Saving requires
  an admin+ membership; status and budget additionally require owner.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Organization not found.", ~p"/organizations")}

      org ->
        mode = Mode.current()
        user = socket.assigns[:current_user]

        cond do
          mode == :local ->
            mount_ok(socket, org, true, true)

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
                can_manage = !!Accounts.role_at_least?(membership.role, "admin")
                is_owner = membership.role == "owner"
                mount_ok(socket, org, can_manage, is_owner)
            end
        end
    end
  end

  defp mount_ok(socket, org, can_manage, is_owner) do
    budget_cents = Accounts.org_budget_cents(org) || 0

    {:ok,
     socket
     |> assign(:page_title, "Settings — #{org.name}")
     |> assign(
       :breadcrumbs,
       [
         %{label: "Organizations", to: ~p"/organizations"},
         %{label: org.name, to: ~p"/organizations/#{org.slug}"},
         %{label: "Settings", to: nil}
       ]
     )
     |> assign(:org, org)
     |> assign(:can_manage, can_manage)
     |> assign(:is_owner, is_owner)
     |> assign(:settings_form, settings_form(org, budget_cents))
     |> assign(:settings_error, nil)}
  end

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    org = socket.assigns.org
    is_owner = socket.assigns.is_owner

    # Re-check server-side: members/viewers can mount this page, so without
    # this guard they could forge a `save_settings` event and rename the org
    # (Accounts.update_org/2 does not check the actor). Status/budget stay
    # owner-locked via is_owner.
    if socket.assigns.can_manage do
      org_attrs =
        %{name: params["name"]}
        |> maybe_add_owner_field("status", params["status"], is_owner)

      with {:ok, org} <- Accounts.update_org(org, org_attrs),
           {:ok, org} <- maybe_set_budget(org, params["budget_cents"], is_owner) do
        budget_cents = Accounts.org_budget_cents(org) || 0

        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:settings_form, settings_form(org, budget_cents))
         |> assign(:settings_error, nil)
         |> put_flash(:info, "Settings saved.")}
      else
        {:error, %Ecto.Changeset{} = cs} ->
          msg = Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
          {:noreply, assign(socket, :settings_error, msg)}

        {:error, reason} ->
          {:noreply, assign(socket, :settings_error, format_error(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, "You don't have permission to change organization settings.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-8">
      <.page_title title="Organization settings" />

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>General</.section_title>
        <p class="mt-1 text-xs text-muted-foreground">
          Name is editable by admins and owners. Status and budget are owner-only.
        </p>

        <.form
          for={@settings_form}
          phx-submit="save_settings"
          id="org-settings-form"
          class="mt-4 max-w-md space-y-4"
        >
          <div>
            <.input
              field={@settings_form[:name]}
              type="text"
              label="Organization name"
              required
              disabled={!@can_manage}
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
            <%= unless @can_manage do %>
              <p class="mt-1 text-xs text-muted-foreground">Only admins and owners can rename.</p>
            <% end %>
          </div>

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
              min="0"
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

          <.button type="submit" disabled={!@can_manage}>Save</.button>
        </.form>
      </section>
    </section>
    """
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
        Accounts.set_org_budget_cents(org.id, cents)

      _ ->
        {:error, "Budget must be a non-negative integer (in cents)."}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
