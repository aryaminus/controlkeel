defmodule ControlKeelWeb.OrganizationDetailLive do
  @moduledoc """
  Member management for an org at `/organizations/:slug`.

  Admin+owner only. Allows:
    - List active and pending memberships (preloaded with the user)
    - Invite a new member by email + role (creates pending Membership;
      raw invitation token is displayed once for copy-paste, since the
      real mailer is deferred to P1c)
    - Revoke a membership (last-owner protected)
    - Change a role (last-owner protected)

  ## Access

  Resolved per-URL via `Accounts.get_active_membership(user.id, org.id)`
  (NOT the session's pinned `current_membership`). Local mode has no
  membership table and is unrestricted. Cloud/self_hosted requires the
  signed-in user to hold an active admin+ membership for this specific
  org; others are redirected to `/organizations`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @valid_roles ~w(owner admin member viewer)

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
                mount_ok(socket, org, membership)
            end
        end
    end
  end

  defp mount_ok(socket, org, membership \\ nil) do
    local_mode = Mode.current() == :local
    budget_cents = Accounts.org_budget_cents(org) || 0
    member_count = Accounts.count_memberships_for_org(org.id)
    can_manage = membership && Accounts.role_at_least?(membership.role, "admin")
    memberships = if(local_mode, do: [], else: load_memberships(org.id))

    {:ok,
     socket
     |> assign(:page_title, "Organization Detail — #{org.name}")
     |> assign(:org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:budget_cents, budget_cents)
     |> assign(:member_count, member_count)
     |> assign(:can_manage, can_manage)
     |> assign(:current_role, membership && membership.role)
     |> assign(:memberships, memberships)
     |> assign(:workspaces, load_workspaces(org.id))
     |> assign(:active_tab, :workspaces)
     |> assign(:show_new_workspace, false)
     |> assign(
       :new_workspace_form,
       to_form(
         %{
           "name" => "",
           "slug" => "",
           "industry" => "",
           "budget_cents" => "0"
         },
         as: :workspace
       )
     )
     |> assign(:new_workspace_error, nil)
     |> assign(:active_owner_count, count_active_owners(memberships))
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:invite_token, nil)
     |> assign(:invite_error, nil)
     |> assign(:show_invite_modal, false)
     |> assign(:show_revoke_modal, false)
     |> assign(:revoke_target, nil)
     |> assign(:is_owner, !!(local_mode || (membership && membership.role == "owner")))
     |> assign(:show_settings_modal, false)
     |> assign(:settings_form, settings_form(org, budget_cents))
     |> assign(:settings_error, nil)
     |> assign(:page_action, page_actions(local_mode, can_manage))
     |> assign(:current_user, socket.assigns[:current_user])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :active_tab, normalize_tab(params["tab"]))}
  end

  @impl true
  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :show_settings_modal, true)}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_settings_modal, false)
     |> assign(:settings_error, nil)}
  end

  def handle_event("new_workspace", _params, socket) do
    {:noreply, assign(socket, :show_new_workspace, true)}
  end

  def handle_event("close_new_workspace", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_workspace, false)
     |> assign(:new_workspace_error, nil)}
  end

  def handle_event("validate_workspace", %{"workspace" => params}, socket) do
    {:noreply, assign(socket, :new_workspace_form, to_form(params, as: :workspace))}
  end

  def handle_event("save_workspace", %{"workspace" => params}, socket) do
    if socket.assigns.local_mode do
      {:noreply,
       socket
       |> assign(:show_new_workspace, false)
       |> put_flash(
         :error,
         "Only the default workspace is available in local mode. Upgrade to cloud mode to create additional workspaces."
       )}
    else
      org = socket.assigns.org

      params =
        params |> Map.put("slug", resolve_workspace_slug(params)) |> Map.put("org_id", org.id)

      case create_workspace(params) do
        {:ok, workspace} ->
          {:noreply,
           socket
           |> assign(:show_new_workspace, false)
           |> assign(:new_workspace_error, nil)
           |> assign(:workspaces, load_workspaces(org.id))
           |> put_flash(:info, "Workspace #{workspace.name} created.")}

        {:error, %Ecto.Changeset{} = cs} ->
          msg =
            cs.errors
            |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

          {:noreply, assign(socket, :new_workspace_error, msg)}

        {:error, reason} ->
          {:noreply, assign(socket, :new_workspace_error, inspect(reason))}
      end
    end
  end

  def handle_event("save_settings", %{"settings" => params}, socket) do
    org = socket.assigns.org
    is_owner = socket.assigns.is_owner

    # The Settings button is only rendered for can_manage/local_mode, but
    # re-check server-side. Members/viewers can mount this LiveView, so without
    # this guard they could forge a `save_settings` event and rename the org
    # (the name field has no other server-side authz; Accounts.update_org/2
    # does not check the actor). Status/budget stay owner-locked via is_owner.
    if socket.assigns.can_manage || socket.assigns.local_mode do
      org_attrs =
        %{name: params["name"]}
        |> maybe_add_owner_field("status", params["status"], is_owner)

      with {:ok, org} <- Accounts.update_org(org, org_attrs),
           {:ok, org} <- maybe_set_budget(org, params["budget_cents"], is_owner) do
        budget_cents = Accounts.org_budget_cents(org) || 0

        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:budget_cents, budget_cents)
         |> assign(:settings_form, settings_form(org, budget_cents))
         |> assign(:settings_error, nil)
         |> assign(:show_settings_modal, false)
         |> put_flash(:info, "Settings saved.")}
      else
        {:error, %Ecto.Changeset{} = cs} ->
          msg =
            cs.errors
            |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

          {:noreply, assign(socket, :settings_error, msg)}

        {:error, reason} ->
          {:noreply, assign(socket, :settings_error, inspect(reason))}
      end
    else
      {:noreply,
       socket
       |> assign(:show_settings_modal, false)
       |> put_flash(:error, "You don't have permission to change organization settings.")}
    end
  end

  def handle_event("open_invite", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("close_invite", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_invite_modal, false)
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:invite_error, nil)}
  end

  @impl true
  def handle_event("invite", %{"invite" => %{"email" => raw_email, "role" => role}}, socket) do
    email = raw_email |> to_string() |> String.downcase() |> String.trim()
    role = if role in @valid_roles, do: role, else: "member"

    with :ok <- validate_email(email),
         {:ok, user} <- find_or_create_user(email),
         {:ok, _membership, raw_token} <-
           Accounts.invite_member(user.id, socket.assigns.org.id,
             role: role,
             invited_by_user_id: socket.assigns.current_user.id
           ) do
      # Best-effort email delivery. Token banner remains as visible fallback,
      # so a mailer failure does not block the operator from completing the invite.
      _ = ControlKeel.Mailer.deliver_invitation(%{email: user.email}, raw_token)

      {:noreply,
       socket
       |> refresh_memberships(socket.assigns.org.id)
       |> assign(:invite_token, raw_token)
       |> assign(:invite_error, nil)
       |> assign(:show_invite_modal, false)
       |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:invite_error, format_error(reason))
         |> assign(:invite_token, nil)}
    end
  end

  def handle_event("confirm_revoke", %{"membership-id" => id}, socket) do
    if Accounts.role_at_least?(socket.assigns[:current_role] || "", "admin") do
      case Integer.parse(id) do
        {membership_id, ""} ->
          target = Enum.find(socket.assigns.memberships, &(&1.id == membership_id))

          if is_nil(target) do
            {:noreply, put_flash(socket, :error, "Membership not found.")}
          else
            is_self =
              socket.assigns.current_user &&
                target.user_id == socket.assigns.current_user.id

            active_owners =
              Enum.count(
                socket.assigns.memberships,
                &(&1.role == "owner" and &1.status == "active")
              )

            is_last_owner = is_self and target.role == "owner" and active_owners <= 1

            {:noreply,
             socket
             |> assign(:show_revoke_modal, true)
             |> assign(:revoke_target, target)
             |> assign(:revoke_is_self, is_self)
             |> assign(:revoke_is_last_owner, is_last_owner)}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "Invalid membership.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to revoke memberships.")}
    end
  end

  def handle_event("execute_revoke", %{"membership-id" => id}, socket) do
    with {membership_id, ""} <- Integer.parse(id),
         {:ok, _} <- Accounts.revoke_membership(membership_id, socket.assigns.current_user.id) do
      {:noreply,
       socket
       |> refresh_memberships(socket.assigns.org.id)
       |> assign(:show_revoke_modal, false)
       |> assign(:revoke_target, nil)
       |> assign(:revoke_is_self, false)
       |> assign(:revoke_is_last_owner, false)
       |> put_flash(:info, "Membership revoked.")}
    else
      {:error, :last_owner_protected} ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "Cannot revoke the last owner of this organization.")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "You don't have permission to revoke memberships.")}

      {:error, :cannot_self_revoke} ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "Only owners can revoke their own membership.")}

      {:error, :cannot_revoke_owner} ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "Only owners can revoke other owners.")}

      {:error, :cannot_revoke_admin} ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "Only owners can revoke admins.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "Membership not found.")}

      _ ->
        {:noreply,
         socket
         |> assign(:show_revoke_modal, false)
         |> put_flash(:error, "Could not revoke membership.")}
    end
  end

  def handle_event("cancel_revoke", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_revoke_modal, false)
     |> assign(:revoke_target, nil)}
  end

  def handle_event(
        "change-role",
        %{"membership-id" => id, "role" => new_role},
        socket
      ) do
    with {membership_id, ""} <- Integer.parse(id),
         {:ok, _} <-
           Accounts.update_membership_role(
             membership_id,
             new_role,
             socket.assigns.current_user.id
           ) do
      {:noreply,
       socket
       |> refresh_memberships(socket.assigns.org.id)
       |> put_flash(:info, "Role updated.")}
    else
      {:error, :last_owner_protected} ->
        {:noreply,
         put_flash(socket, :error, "Cannot demote the last owner of this organization.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to change roles.")}

      {:error, :invalid_role} ->
        {:noreply, put_flash(socket, :error, "Invalid role.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Membership not found.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_event("dismiss-token", _params, socket) do
    {:noreply, assign(socket, :invite_token, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <div class="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div class="space-y-2">
          <div class="flex flex-wrap items-center gap-3">
            <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
              {@org.name}
            </h1>

            <span class={[
              "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              @org.status == "active" && "bg-success/10 text-success ring-success/20",
              @org.status != "active" && "bg-muted text-muted-foreground ring-border"
            ]}>
              {@org.status}
            </span>
          </div>

          <%= if @local_mode do %>
            <p class="text-sm text-muted-foreground">
              View organization details below. Member management is unavailable in local mode.
            </p>
          <% else %>
            <p class="text-sm text-muted-foreground">
              Invite teammates, adjust roles, and keep ownership boundaries clear.
            </p>
          <% end %>
        </div>

        <div class="flex flex-wrap gap-x-8 gap-y-3">
          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Slug
            </span>
            <span class="font-mono text-sm text-foreground">{@org.slug}</span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Members
            </span>
            <span class="text-sm font-semibold text-foreground">{@member_count}</span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Monthly budget
            </span>
            <span class="text-sm font-semibold text-foreground">
              <%= if @budget_cents > 0 do %>
                {"$#{Float.round(@budget_cents / 100, 2)}"}
              <% else %>
                <span class="text-muted-foreground">—</span>
              <% end %>
            </span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Created
            </span>
            <span class="text-sm text-foreground">
              {Calendar.strftime(@org.inserted_at, "%b %d, %Y")}
            </span>
          </div>
        </div>
      </div>

      <%= if @invite_token do %>
        <div class="rounded-2xl border border-primary/30 bg-primary/10 p-5">
          <p class="text-sm font-medium text-primary">
            Invitation token issued. Share it with the invitee — it will not be shown again.
          </p>
          <pre class="mt-2 overflow-x-auto rounded-xl bg-background/70 px-4 py-2 font-mono text-xs text-muted-foreground"><code id="invite-token-value">/invitations/{@invite_token}</code></pre>
          <button
            type="button"
            phx-click="dismiss-token"
            class="mt-3 text-xs font-medium text-muted-foreground transition hover:text-foreground"
          >
            Dismiss
          </button>
        </div>
      <% end %>

      <div class="flex border-b border-border">
        <.link
          patch={~p"/organizations/#{@org.slug}"}
          class={tab_class(@active_tab == :workspaces)}
        >
          Workspaces
        </.link>
        <.link
          patch={~p"/organizations/#{@org.slug}?tab=members"}
          class={tab_class(@active_tab == :members)}
        >
          Members
        </.link>
      </div>

      <%= if @active_tab == :workspaces do %>
        <div class="flex items-center justify-between gap-3">
          <p class="text-sm text-muted-foreground">
            Workspaces group sessions, findings, and budgets under this organization.
          </p>
          <button
            type="button"
            phx-click="new_workspace"
            class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
          >
            <.icon name="hero-plus" class="size-4" /> New Workspace
          </button>
        </div>

        <%= if @workspaces == [] do %>
          <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
            <.icon name="hero-squares-2x2" class="mx-auto size-10 text-muted-foreground" />
            <p class="mt-4 text-base font-medium text-foreground">No workspaces yet.</p>
            <p class="mt-1 text-sm text-muted-foreground">
              Workspaces group sessions, findings, and budgets under this organization.
            </p>
          </section>
        <% else %>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <%= for ws <- @workspaces do %>
              <.link
                href={~p"/organizations/#{@org.slug}/workspaces/#{ws.id}"}
                class="group block rounded-2xl border bg-card p-5 shadow-card transition hover:border-primary/40 hover:shadow-card"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="flex min-w-0 items-center gap-2">
                    <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-info/10 text-info">
                      <.icon name="hero-squares-2x2" class="size-4" />
                    </span>
                    <h3 class="truncate text-base font-semibold text-foreground transition group-hover:text-primary">
                      {ws.name}
                    </h3>
                  </div>
                  <span class={[
                    "shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    ws.status == "active" && "bg-success/10 text-success ring-success/20",
                    ws.status != "active" && "bg-muted text-muted-foreground ring-border"
                  ]}>
                    {ws.status}
                  </span>
                </div>
                <p class="mt-1 truncate font-mono text-xs text-muted-foreground">{ws.slug}</p>
                <dl class="mt-4 grid grid-cols-2 gap-3 border-t pt-4">
                  <div>
                    <dt class="text-xs font-medium text-muted-foreground">Sessions</dt>
                    <dd class="mt-1 text-lg font-semibold text-foreground/90">
                      {length(ws.sessions)}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs font-medium text-muted-foreground">Budget</dt>
                    <dd class="mt-1 text-lg font-semibold text-foreground/90">
                      {format_cents(ws.budget_cents)}
                    </dd>
                  </div>
                </dl>
              </.link>
            <% end %>
          </div>
        <% end %>
      <% else %>
        <%= if @local_mode do %>
          <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
            <.icon name="hero-users" class="mx-auto size-10 text-muted-foreground" />
            <p class="mt-4 text-base font-medium text-foreground">
              Member management is not available in local mode.
            </p>
            <p class="mt-1 text-sm text-muted-foreground">
              Switch to cloud or self-hosted mode to invite teammates and manage roles.
            </p>
          </section>
        <% else %>
          <section class="rounded-2xl border bg-card shadow-card overflow-clip">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-border text-left text-sm">
                <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
                  <tr>
                    <th class="px-5 py-3 font-semibold">Email</th>
                    <th class="px-5 py-3 font-semibold">Role</th>
                    <th class="px-5 py-3 font-semibold">Status</th>
                    <th class="px-5 py-3 font-semibold w-px whitespace-nowrap"></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-border">
                  <%= if @memberships == [] do %>
                    <tr>
                      <td colspan="4" class="px-5 py-12 text-center">
                        <p class="text-base font-medium text-foreground">No members yet.</p>
                        <p class="mt-1 text-sm text-muted-foreground">
                          Invite teammates to collaborate on this organization.
                        </p>
                      </td>
                    </tr>
                  <% else %>
                    <%= for m <- @memberships do %>
                      <tr
                        id={"membership-#{m.id}"}
                        class={[
                          "transition hover:bg-muted/30",
                          @current_user && m.user_id == @current_user.id && "bg-primary/5"
                        ]}
                      >
                        <td class="max-w-sm px-5 py-4 font-medium text-foreground">
                          <div class="flex flex-wrap items-center gap-2">
                            {(m.user && m.user.email) || "—"}
                            <%= if @current_user && m.user_id == @current_user.id do %>
                              <span class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
                                you
                              </span>
                            <% end %>
                          </div>
                        </td>
                        <td class="px-5 py-4">
                          <%= if @can_manage do %>
                            <% is_self = @current_user && m.user_id == @current_user.id %>
                            <% state =
                              role_select_state(@current_role, m.role, is_self, @active_owner_count) %>
                            <form id={"role-form-#{m.id}"} phx-change="change-role">
                              <input type="hidden" name="membership-id" value={m.id} />
                              <select
                                name="role"
                                disabled={state.disabled}
                                class={[
                                  "rounded-lg border bg-background px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1",
                                  if(state.disabled,
                                    do: "cursor-not-allowed text-muted-foreground opacity-60",
                                    else: "text-foreground focus:border-primary focus:ring-primary"
                                  )
                                ]}
                              >
                                <option
                                  :for={{value, label} <- state.options}
                                  value={value}
                                  selected={m.role == value}
                                >
                                  {label}
                                </option>
                              </select>
                            </form>
                          <% else %>
                            <span class="text-sm text-muted-foreground">{m.role}</span>
                          <% end %>
                        </td>
                        <td class="px-5 py-4">
                          <span class={[
                            "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                            m.status == "active" &&
                              "bg-success/10 text-success ring-success/20",
                            m.status == "pending" &&
                              "bg-warning/10 text-warning ring-warning/20",
                            m.status == "revoked" && "bg-muted text-muted-foreground ring-border"
                          ]}>
                            {m.status}
                          </span>
                        </td>
                        <td class="px-4 py-4 text-right whitespace-nowrap w-px">
                          <%= if can_revoke?(@current_role, m, @current_user) do %>
                            <button
                              type="button"
                              phx-click="confirm_revoke"
                              phx-value-membership-id={m.id}
                              class="text-sm font-medium text-destructive transition hover:text-destructive"
                            >
                              Revoke
                            </button>
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>
        <% end %>
      <% end %>

      <.invite_modal
        :if={@show_invite_modal}
        form={@invite_form}
        error={@invite_error}
        role_options={invite_role_options(@current_role)}
      />

      <.settings_modal
        :if={@show_settings_modal}
        form={@settings_form}
        org={@org}
        is_owner={@is_owner}
        error={@settings_error}
      />

      <.new_workspace_modal
        :if={@show_new_workspace}
        local_mode={@local_mode}
        form={@new_workspace_form}
        error={@new_workspace_error}
      />

      <%= if @show_revoke_modal and @revoke_target do %>
        <div
          id="revoke-member-modal"
          class="relative z-50"
          phx-mounted={Phoenix.LiveView.JS.show(to: "#revoke-member-modal")}
          phx-remove={Phoenix.LiveView.JS.hide(to: "#revoke-member-modal")}
        >
          <div
            class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
            phx-click="cancel_revoke"
            aria-label="Close modal"
          />

          <div class="fixed inset-0 flex items-center justify-center p-4">
            <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
              <div class="mb-5 flex items-center gap-3">
                <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-destructive/15">
                  <.icon name="hero-exclamation-triangle" class="size-5 text-destructive" />
                </span>
                <h2 class="text-lg font-semibold text-foreground">Revoke membership</h2>
              </div>

              <%= if @revoke_is_last_owner do %>
                <div class="rounded-xl border border-[var(--ck-warning)]/30 bg-[var(--ck-warning)]/5 p-4">
                  <p class="text-sm text-[var(--ck-warning)]">
                    <strong>You are the only owner of this organization.</strong>
                    You cannot revoke your own membership without transferring ownership to another member first.
                  </p>
                </div>
                <div class="mt-5 flex justify-end">
                  <button
                    type="button"
                    phx-click="cancel_revoke"
                    class="rounded-full bg-muted px-5 py-2 text-sm font-medium text-foreground transition hover:bg-muted"
                  >
                    Close
                  </button>
                </div>
              <% else %>
                <div class="space-y-3">
                  <%= if @revoke_is_self do %>
                    <p class="text-sm text-muted-foreground">
                      You are about to
                      <strong class="text-foreground">revoke your own membership</strong>
                      in <strong class="text-foreground">{@org.name}</strong>.
                      You will lose access to this organization immediately.
                    </p>
                  <% else %>
                    <p class="text-sm text-muted-foreground">
                      You are about to revoke membership for <strong class="text-foreground">{@revoke_target.user && @revoke_target.user.email}</strong>.
                      They will lose access to <strong class="text-foreground">{@org.name}</strong>
                      immediately.
                    </p>
                  <% end %>
                  <p class="text-xs text-muted-foreground">
                    This action can be undone by re-inviting the member later.
                  </p>
                </div>

                <div class="mt-6 flex items-center justify-end gap-3 border-t pt-4">
                  <button
                    type="button"
                    phx-click="cancel_revoke"
                    class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    phx-click="execute_revoke"
                    phx-value-membership-id={@revoke_target.id}
                    class="inline-flex items-center gap-2 rounded-full bg-destructive px-5 py-2 text-sm font-semibold text-foreground shadow-lg shadow-destructive/20 transition hover:-translate-y-0.5 hover:bg-destructive"
                  >
                    <.icon name="hero-trash" class="size-4" />
                    {if @revoke_is_self, do: "Revoke my membership", else: "Revoke membership"}
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </section>
    """
  end

  attr :form, :map, required: true
  attr :error, :string, default: nil
  attr :role_options, :list, default: [{"viewer", "viewer"}, {"member", "member"}]

  defp invite_modal(assigns) do
    ~H"""
    <div
      id="invite-member-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#invite-member-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#invite-member-modal")}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click="close_invite"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">Invite member</h2>
            <button
              type="button"
              phx-click="close_invite"
              class="rounded-md text-muted-foreground transition hover:text-foreground"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <.form for={@form} phx-submit="invite" id="invite-form" class="space-y-4">
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              placeholder="teammate@example.com"
              required
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />

            <.input
              field={@form[:role]}
              type="select"
              label="Role"
              options={@role_options}
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />

            <%= if @error do %>
              <p class="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">{@error}</p>
            <% end %>

            <div class="flex items-center justify-end gap-3 pt-4">
              <button
                type="button"
                phx-click="close_invite"
                class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
              >
                Send invitation
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :org, :map, required: true
  attr :is_owner, :boolean, default: false
  attr :error, :string, default: nil

  defp settings_modal(assigns) do
    ~H"""
    <div
      id="org-settings-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#org-settings-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#org-settings-modal")}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click="close_settings"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">Settings</h2>
            <button
              type="button"
              phx-click="close_settings"
              class="rounded-md text-muted-foreground transition hover:text-foreground"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <.form for={@form} phx-submit="save_settings" id="org-settings-form" class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Organization name"
              required
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />

            <div>
              <.input
                field={@form[:status]}
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
                field={@form[:budget_cents]}
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

            <%= if @error do %>
              <p class="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">{@error}</p>
            <% end %>

            <div class="flex items-center justify-end gap-3 pt-4">
              <button
                type="button"
                phx-click="close_settings"
                class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
              >
                Save
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  attr :local_mode, :boolean, default: false
  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp new_workspace_modal(assigns) do
    ~H"""
    <div
      id="new-workspace-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#new-workspace-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#new-workspace-modal")}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click="close_new_workspace"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">New Workspace</h2>
            <button
              type="button"
              phx-click="close_new_workspace"
              class="rounded-md text-muted-foreground transition hover:text-foreground"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <%= if @local_mode do %>
            <div class="rounded-xl border border-warning/30 bg-warning/10 p-4">
              <div class="flex items-center gap-2">
                <.icon name="hero-lock-closed" class="size-4 text-warning" />
                <p class="text-sm font-semibold text-warning">Local mode</p>
              </div>
              <p class="mt-2 text-sm text-foreground/80">
                Only the default workspace is available in local mode.
              </p>
              <p class="mt-1 text-sm text-muted-foreground">
                Upgrade to cloud mode to create additional workspaces.
              </p>
            </div>
          <% else %>
            <.form
              for={@form}
              phx-submit="save_workspace"
              phx-change="validate_workspace"
              id="new-workspace-form"
              class="space-y-4"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Workspace name"
                required
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:slug]}
                type="text"
                label="Slug"
                placeholder="Auto-generated from name"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:industry]}
                type="select"
                label="Industry"
                options={industry_options()}
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:budget_cents]}
                type="number"
                label="Monthly budget (cents)"
                min="0"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <%= if @error do %>
                <p class="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {@error}
                </p>
              <% end %>

              <div class="flex items-center justify-end gap-3 pt-4">
                <button
                  type="button"
                  phx-click="close_new_workspace"
                  class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
                >
                  Create
                </button>
              </div>
            </.form>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp page_actions(local_mode, can_manage) do
    actions =
      []
      |> maybe_add_action(settings_page_action(local_mode, can_manage))
      |> maybe_add_action(invite_page_action(local_mode, can_manage))

    if actions == [], do: nil, else: actions
  end

  defp maybe_add_action(actions, nil), do: actions
  defp maybe_add_action(actions, action), do: actions ++ [action]

  defp settings_page_action(local_mode, can_manage) do
    if local_mode || can_manage do
      %{label: "Settings", event: "open_settings", icon: "hero-cog-6-tooth"}
    else
      nil
    end
  end

  defp invite_page_action(local_mode, can_manage) do
    if local_mode || not can_manage do
      nil
    else
      %{label: "Invite member", event: "open_invite", icon: "hero-plus"}
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
          {:error, _} = err -> err
        end

      _ ->
        {:error, "Budget must be a non-negative integer (in cents)."}
    end
  end

  defp load_memberships(org_id) do
    Accounts.list_memberships_for_org(org_id)
    |> Repo.preload(:user)
  end

  defp load_workspaces(org_id) do
    Mission.list_workspaces_for_org(org_id)
    |> Repo.preload(:sessions)
  end

  defp create_workspace(attrs) do
    attrs
    |> Map.put_new("agent", "claude")
    |> Map.put_new("compliance_profile", "general")
    |> Map.put_new("status", "active")
    |> Mission.create_workspace()
  end

  defp resolve_workspace_slug(params) do
    case Map.get(params, "slug", "") do
      slug when is_binary(slug) and slug != "" -> slug
      _ -> slugify(Map.get(params, "name", ""))
    end
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp slugify(_), do: ""

  defp industry_options do
    [
      {"General", "general"},
      {"Web", "web"},
      {"Security", "security"},
      {"Finance", "finance"}
    ]
  end

  defp normalize_tab(tab) when tab in ["members"], do: :members
  defp normalize_tab(_tab), do: :workspaces

  defp refresh_memberships(socket, org_id) do
    memberships = load_memberships(org_id)

    # The viewer's own role may have just changed (self-demotion) or their
    # membership been revoked. Rebind the permission-derived assigns from the
    # refreshed list so the table re-renders with the correct controls without
    # a full reload.
    viewer_role =
      case socket.assigns[:current_user] do
        %{id: uid} ->
          case Enum.find(memberships, &(&1.user_id == uid)) do
            nil -> nil
            m -> m.role
          end

        _ ->
          nil
      end

    can_manage = viewer_role && Accounts.role_at_least?(viewer_role, "admin")

    socket
    |> assign(:memberships, memberships)
    |> assign(:member_count, Accounts.count_memberships_for_org(org_id))
    |> assign(:active_owner_count, count_active_owners(memberships))
    |> assign(:current_role, viewer_role)
    |> assign(:can_manage, can_manage)
    |> assign(:page_action, page_actions(socket.assigns[:local_mode], can_manage))
  end

  defp count_active_owners(memberships) do
    Enum.count(memberships, &(&1.role == "owner" and &1.status == "active"))
  end

  defp tab_class(active?) do
    base = "text-sm font-medium transition-colors px-3 py-1.5 rounded-t-lg border-b-2"

    if active? do
      "#{base} text-primary border-primary"
    else
      "#{base} border-transparent text-muted-foreground hover:text-foreground"
    end
  end

  defp format_cents(nil), do: "—"
  defp format_cents(0), do: "—"
  defp format_cents(cents) when is_integer(cents), do: "$#{Float.round(cents / 100, 2)}"

  # Decides, per row, whether the role <select> is locked and which options it
  # offers. Mirrors the authorization rules in
  # `Accounts.update_membership_role/3` so the UI never offers a choice the
  # server would reject.
  #
  # admin viewer:
  #   - owner target                       -> locked
  #   - other admin target                 -> locked
  #   - self (admin)                       -> self-demit to member/viewer only
  #   - member/viewer targets              -> member/viewer only
  # owner viewer:
  #   - self + last owner                  -> locked (last-owner protection)
  #   - everything else                    -> all four roles
  defp role_select_state(current_role, target_role, is_self, active_owner_count) do
    cond do
      current_role == "admin" ->
        cond do
          target_role == "owner" ->
            %{disabled: true, options: [{"owner", "owner"}]}

          target_role == "admin" and is_self ->
            # Keep current role visible; only allow stepping down.
            %{
              disabled: false,
              options: [{"admin", "admin"}, {"member", "member"}, {"viewer", "viewer"}]
            }

          target_role == "admin" ->
            %{disabled: true, options: [{"admin", "admin"}]}

          true ->
            %{disabled: false, options: [{"member", "member"}, {"viewer", "viewer"}]}
        end

      current_role == "owner" ->
        is_last_owner = is_self and target_role == "owner" and active_owner_count <= 1

        if is_last_owner do
          %{disabled: true, options: [{"owner", "owner"}]}
        else
          %{
            disabled: false,
            options: [
              {"owner", "owner"},
              {"admin", "admin"},
              {"member", "member"},
              {"viewer", "viewer"}
            ]
          }
        end

      true ->
        # member/viewer viewers don't manage roles; lock as a safety net.
        %{disabled: true, options: [{target_role, target_role}]}
    end
  end

  defp can_revoke?(nil, _target, _current_user), do: false
  defp can_revoke?(_role, %{status: "revoked"}, _current_user), do: false
  defp can_revoke?("owner", _target, _current_user), do: true

  defp can_revoke?("admin", target, %{id: uid}),
    do: target.role in ["member", "viewer"] and target.user_id != uid

  defp can_revoke?(_, _, _), do: false

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end

  defp validate_email(""), do: {:error, "Email is required"}

  defp validate_email(email) do
    if Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email),
      do: :ok,
      else: {:error, "Invalid email format"}
  end

  defp find_or_create_user(email) do
    case Accounts.get_user_by_email(email) do
      nil -> Accounts.create_user(%{email: email})
      user -> {:ok, user}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(:already_member), do: "This user is already a member or has a pending invite."
  defp format_error(:unauthorized), do: "You don't have permission to invite at that role."
  defp format_error(%Ecto.Changeset{}), do: "Could not invite member."
  defp format_error(reason), do: inspect(reason)

  # Owners can invite at any role; admins only member/viewer (matches the
  # role-change matrix and the server-side guard in `invite_member/3`).
  defp invite_role_options("owner"),
    do: [{"viewer", "viewer"}, {"member", "member"}, {"admin", "admin"}, {"owner", "owner"}]

  defp invite_role_options(_), do: [{"viewer", "viewer"}, {"member", "member"}]
end
