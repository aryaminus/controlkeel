defmodule ControlKeelWeb.OrganizationMembersLive do
  @moduledoc """
  Member management for an org at `/organizations/:slug/members`.

  Admin+owner only. Allows:
    - List active and pending memberships (preloaded with the user)
    - Invite a new member by email + role (creates pending Membership;
      raw invitation token is displayed once for copy-paste, since the
      real mailer is deferred to P1c)
    - Revoke a membership (last-owner protected)
    - Change a role (last-owner protected)

  Access is resolved per-URL via
  `Accounts.get_active_membership(user.id, org.id)` (NOT the session's
  pinned `current_membership`). Local mode has no membership table and
  is unrestricted. Cloud/self_hosted requires the signed-in user to hold
  an active admin+ membership for this specific org; others are redirected
  to `/organizations`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
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
            mount_ok(socket, org, nil)

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

  defp mount_ok(socket, org, membership) do
    local_mode = Mode.current() == :local
    can_manage = membership && Accounts.role_at_least?(membership.role, "admin")
    memberships = if(local_mode, do: [], else: load_memberships(org.id))

    {:ok,
     socket
     |> assign(:page_title, "Members — #{org.name}")
     |> assign(:org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:can_manage, can_manage)
     |> assign(:current_role, membership && membership.role)
     |> assign(:current_user, socket.assigns[:current_user])
     |> assign(:active_tab, :members)
     |> assign(:memberships, memberships)
     |> assign(:member_count, Accounts.count_memberships_for_org(org.id))
     |> assign(:active_owner_count, count_active_owners(memberships))
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:invite_token, nil)
     |> assign(:invite_error, nil)
     |> assign(:show_invite_modal, false)
     |> assign(:show_revoke_modal, false)
     |> assign(:revoke_target, nil)
     |> assign(:page_action, page_actions(local_mode, can_manage))}
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
      <.page_title title="Members" />

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

      <.invite_modal
        :if={@show_invite_modal}
        form={@invite_form}
        error={@invite_error}
        role_options={invite_role_options(@current_role)}
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

  # ── Private ─────────────────────────────────────────────────────────

  defp page_actions(local_mode, can_manage) do
    actions =
      []
      |> maybe_add_action(invite_page_action(local_mode, can_manage))

    if actions == [], do: nil, else: actions
  end

  defp maybe_add_action(actions, nil), do: actions
  defp maybe_add_action(actions, action), do: actions ++ [action]

  defp invite_page_action(local_mode, can_manage) do
    if local_mode || not can_manage do
      nil
    else
      %{label: "Invite member", event: "open_invite", icon: "hero-plus"}
    end
  end

  defp load_memberships(org_id) do
    Accounts.list_memberships_for_org(org_id)
    |> Repo.preload(:user)
  end

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

  defp redirect_with_flash(socket, kind, message, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, message)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
