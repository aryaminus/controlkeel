defmodule ControlKeelWeb.OrganizationSettingsLive do
  @moduledoc """
  Organization settings at `/:org_slug/settings`.

  Secondary navigation over setting groups, mirroring the workspace settings
  pattern (`?tab=` query param + `push_patch`). Three groups today: General
  (name, status, budget), Members (roster, roles, invites — admin+ by the
  page-wide gate) and Policy sets (org-owned policy sets — the former global
  Policy Studio, now scoped to the organization).

  Member management lives here (moved from the org overview page when the
  overview became the org dashboard): invite by email, role changes, and
  revocation are admin+ gated by `can_manage?`, with the same last-owner
  protections as before.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Intent
  alias ControlKeel.Platform
  alias ControlKeel.Platform.PolicySet
  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode
  alias ControlKeelWeb.OrgAccess

  @tabs ["general", "members", "policy_sets"]

  @valid_roles ~w(owner admin member viewer)

  @impl true
  def mount(%{"org_slug" => slug} = params, _session, socket) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user], "admin") do
      {:ok, org, membership} ->
        mount_ok(socket, org, membership, normalize_tab(params["tab"]))

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  @impl true
  def handle_params(%{"org_slug" => slug} = params, _uri, socket) do
    socket =
      case socket.assigns[:org] do
        %{slug: ^slug} ->
          socket

        _ ->
          case OrgAccess.resolve(slug, socket.assigns[:current_user], "admin") do
            {:ok, org, membership} ->
              {:ok, socket} = mount_ok(socket, org, membership, nil)
              assign(socket, :scope_error, nil)

            {:error, error} ->
              assign(socket, :scope_error, error)
          end
      end

    {:noreply, assign(socket, :active_tab, normalize_tab(params["tab"]))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp normalize_tab("policy_sets"), do: "policy_sets"
  defp normalize_tab("members"), do: "members"
  defp normalize_tab(_tab), do: "general"

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, push_patch(socket, to: ~p"/#{socket.assigns.org.slug}/settings?tab=#{tab}")}
  end

  def handle_event("set_tab", _params, socket), do: {:noreply, socket}

  @impl true
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
    if can_manage?(socket.assigns) do
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
  def handle_event("open_packs_dialog", _params, socket) do
    {:noreply, assign(socket, :show_packs_dialog, true)}
  end

  @impl true
  def handle_event("close_packs_dialog", _params, socket) do
    {:noreply, assign(socket, :show_packs_dialog, false)}
  end

  @impl true
  def handle_event("toggle_pack", %{"name" => name}, socket) do
    if MapSet.member?(socket.assigns.pack_names, name) do
      open_packs = socket.assigns.open_packs

      open_packs =
        if MapSet.member?(open_packs, name) do
          MapSet.delete(open_packs, name)
        else
          MapSet.put(open_packs, name)
        end

      {:noreply, assign(socket, :open_packs, open_packs)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign_policy_set_form(empty_policy_set_changeset(), "", nil)}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign_policy_set_form(empty_policy_set_changeset(), "", nil)}
  end

  @impl true
  def handle_event("validate_policy_set", %{"policy_set" => params}, socket) do
    {_attrs, changeset, raw, ui_error} = prepare_policy_set(params, :validate)

    {:noreply, assign_policy_set_form(socket, changeset, raw, ui_error)}
  end

  @impl true
  def handle_event("save_policy_set", %{"policy_set" => params}, socket) do
    {attrs, changeset, raw, ui_error} = prepare_policy_set(params, :insert)
    attrs = Map.put(attrs, "org_id", socket.assigns.org.id)

    if ui_error do
      {:noreply, assign_policy_set_form(socket, changeset, raw, ui_error)}
    else
      case Platform.create_policy_set(attrs) do
        {:ok, set} ->
          {:noreply,
           socket
           |> put_flash(:info, "Created policy set ##{set.id}.")
           |> assign(:show_create_modal, false)
           |> assign_policy_set_form(empty_policy_set_changeset(), "", nil)
           |> assign_policy_sets()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           assign_policy_set_form(socket, Map.put(changeset, :action, :insert), raw, nil)}
      end
    end
  end

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    if can_manage?(socket.assigns) do
      do_save_settings(socket, params)
    else
      {:noreply,
       put_flash(socket, :error, "You don't have permission to change organization settings.")}
    end
  end

  defp do_save_settings(socket, params) do
    org = socket.assigns.org
    is_owner = is_owner?(socket.assigns)

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

  defp mount_ok(socket, org, membership, active_tab) do
    local_mode = Mode.current() == :local
    budget_cents = Accounts.org_budget_cents(org) || 0
    memberships = if(local_mode, do: [], else: load_memberships(org.id))

    {:ok,
     socket
     |> assign(:page_title, "Organization Settings - #{org.name}")
     |> assign(:org, org)
     |> assign(:nav_org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:current_membership, membership)
     |> assign(:current_user, socket.assigns[:current_user])
     |> assign(:memberships, memberships)
     |> assign(:active_owner_count, count_active_owners(memberships))
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:invite_token, nil)
     |> assign(:invite_error, nil)
     |> assign(:show_invite_modal, false)
     |> assign(:show_revoke_modal, false)
     |> assign(:revoke_target, nil)
     |> assign(:settings_form, settings_form(org, budget_cents))
     |> assign(:settings_error, nil)
     |> assign(:tabs, @tabs)
     |> assign(:active_tab, active_tab || "general")
     |> assign(:open_packs, MapSet.new())
     |> assign(:show_packs_dialog, false)
     |> assign(:show_create_modal, false)
     |> assign_packs()
     |> assign_policy_sets()
     |> assign_policy_set_form(empty_policy_set_changeset(), "", nil)}
  end

  defp is_owner?(%{local_mode: true}), do: true
  defp is_owner?(%{current_membership: %{role: "owner"}}), do: true
  defp is_owner?(_assigns), do: false

  defp can_manage?(%{local_mode: true}), do: true

  defp can_manage?(%{current_membership: %{role: role}}),
    do: Accounts.role_at_least?(role, "admin")

  defp can_manage?(_assigns), do: false

  defp current_role(%{current_membership: %{role: role}}), do: role
  defp current_role(_assigns), do: nil

  # ── Members tab -------------------------------------------------------

  defp load_memberships(org_id) do
    Accounts.list_memberships_for_org(org_id)
    |> Repo.preload(:user)
  end

  defp refresh_memberships(socket, org_id) do
    memberships = load_memberships(org_id)

    # The viewer's own role may have just changed (self-demotion) or their
    # membership been revoked. Rebind the page-local membership from the
    # refreshed list so permission-derived controls re-render without a full
    # reload.
    viewer_membership =
      case socket.assigns[:current_user] do
        %{id: uid} ->
          Enum.find(memberships, &(&1.user_id == uid and &1.status == "active"))

        _ ->
          nil
      end

    socket
    |> assign(:memberships, memberships)
    |> assign(:active_owner_count, count_active_owners(memberships))
    |> assign(:current_membership, viewer_membership)
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

  # --- Policy sets ------------------------------------------------------

  defp assign_packs(socket) do
    packs = PackLoader.all_packs()
    all_rules = packs |> Map.values() |> List.flatten()

    socket
    |> assign(:packs, Enum.sort_by(packs, fn {name, _} -> pack_sort_order(name) end))
    |> assign(:pack_names, MapSet.new(Map.keys(packs)))
    |> assign(:pack_count, map_size(packs))
    |> assign(:rule_count, length(all_rules))
    |> assign(:block_count, Enum.count(all_rules, &(&1.action == "block")))
  end

  defp assign_policy_sets(%{assigns: %{org: org}} = socket) do
    assignments_by_set =
      Platform.list_org_policy_assignments(org.id)
      |> Enum.group_by(& &1.policy_set_id)

    policy_sets =
      Platform.list_policy_sets(org.id)
      |> Enum.map(fn set ->
        Map.put(set, :workspace_policy_sets, Map.get(assignments_by_set, set.id, []))
      end)

    assign(socket, :policy_sets, policy_sets)
  end

  defp assignment_summary(assignment) do
    workspace = assignment.workspace || %{name: "workspace ##{assignment.workspace_id}"}
    suffix = if assignment.enabled, do: "", else: ", disabled"
    "#{workspace.name} (precedence #{assignment.precedence}#{suffix})"
  end

  defp empty_policy_set_changeset do
    PolicySet.changeset(%PolicySet{}, %{})
  end

  defp assign_policy_set_form(socket, changeset, raw_rules_json, rules_error) do
    socket
    |> assign(:changeset, changeset)
    |> assign(:form, to_form(changeset, as: :policy_set))
    |> assign(:rules_json, raw_rules_json)
    |> assign(:rules_error, rules_error)
  end

  defp prepare_policy_set(params, action) do
    # Allowlist the fields the create form actually posts. Status and
    # metadata are server defaults (create_policy_set), never client input;
    # org_id is injected from the resolved org in save_policy_set.
    params = Map.take(params, ["name", "description", "rules_json"])

    {raw, attrs} = Map.pop(params, "rules_json")
    raw = raw || ""

    {attrs, ui_error} =
      case decode_rule_entries(raw) do
        {:ok, rules} -> {Map.put(attrs, "rules", rules), nil}
        {:error, message} -> {Map.put(attrs, "rules", %{"entries" => []}), message}
      end

    changeset =
      %PolicySet{}
      |> PolicySet.changeset(attrs)
      |> Map.put(:action, action)

    {attrs, changeset, raw, ui_error}
  end

  defp decode_rule_entries(""), do: {:ok, %{"entries" => []}}

  defp decode_rule_entries(raw) do
    case Jason.decode(raw) do
      {:ok, %{"entries" => _entries} = wrapped} ->
        {:ok, wrapped}

      {:ok, entries} when is_list(entries) ->
        {:ok, %{"entries" => entries}}

      {:ok, _other} ->
        {:error, ~s(must be an array of rule entries or {"entries": [...]})}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "invalid JSON: " <> Exception.message(error)}
    end
  end

  defp pack_label("baseline"), do: "Baseline — Secrets & OWASP"
  defp pack_label("cost"), do: "Cost — Budget guardrails"
  defp pack_label("software"), do: "Software — Code hygiene"
  defp pack_label("healthcare"), do: "Healthcare — HIPAA / PHI"
  defp pack_label("education"), do: "Education — FERPA / COPPA"
  defp pack_label("finance"), do: "Finance — PCI-DSS / SOX"
  defp pack_label("hr"), do: "HR — EEOC / Employee PII"
  defp pack_label("legal"), do: "Legal — Privilege / Retention"
  defp pack_label("marketing"), do: "Marketing — Consent / CAN-SPAM"
  defp pack_label("sales"), do: "Sales — CRM / Contact PII"
  defp pack_label("realestate"), do: "Real Estate — Transaction / PII"
  defp pack_label("gdpr"), do: "GDPR — EU Data Protection"

  defp pack_label(name) do
    if name in Intent.supported_packs(),
      do: Intent.pack_label(name),
      else: String.capitalize(name)
  end

  defp pack_description("baseline"),
    do: "Always active. Detects secrets, injection, and XSS in all agent output."

  defp pack_description("cost"),
    do: "Always active. Warns at 80% of budget, blocks at 100%."

  defp pack_description("software"),
    do: "Active for software domain. Catches debug endpoints, auth bypass, eval, open CORS."

  defp pack_description("healthcare"),
    do: "Active when domain pack is healthcare. Flags PHI patterns and HIPAA-sensitive data."

  defp pack_description("education"),
    do: "Active when domain pack is education. Flags student data and FERPA-sensitive content."

  defp pack_description("finance"),
    do: "Active when domain pack is finance. Flags payment card data and SOX-sensitive records."

  defp pack_description("hr"),
    do:
      "Active when domain pack is HR. Flags employee PII, candidate data handling, and automated screening risks."

  defp pack_description("legal"),
    do:
      "Active when domain pack is legal. Flags attorney-client privilege risks, unencrypted document handling, and retention violations."

  defp pack_description("marketing"),
    do:
      "Active when domain pack is marketing. Flags missing consent mechanisms, CAN-SPAM violations, and unsecured contact lists."

  defp pack_description("sales"),
    do:
      "Active when domain pack is sales. Flags CRM contact PII, quota audit risks, and data portability gaps."

  defp pack_description("realestate"),
    do:
      "Active when domain pack is real estate. Flags client PII, unencrypted transaction docs, and Fair Housing compliance gaps."

  defp pack_description("gdpr"),
    do:
      "Active for EU data handling. Flags missing consent, right-to-delete gaps, and cross-border data transfer risks."

  defp pack_description(name) when is_binary(name) do
    if name in Intent.supported_packs() do
      pack = Intent.Domains.pack(name)

      "Active when domain pack is #{Intent.pack_label(name)}. Focus areas: #{Enum.join(pack.compliance, ", ")}."
    else
      "Domain-specific policy rules."
    end
  end

  defp pack_description(_), do: "Domain-specific policy rules."

  defp pack_sort_order("baseline"), do: 0
  defp pack_sort_order("cost"), do: 1
  defp pack_sort_order("software"), do: 2
  defp pack_sort_order(_), do: 3

  defp status_pill_class("active"), do: "bg-success/10 text-success ring-success/20"
  defp status_pill_class("disabled"), do: "bg-warning/10 text-warning ring-warning/20"

  defp status_pill_class(_), do: "bg-muted text-muted-foreground ring-border"

  defp rule_name(id) do
    id |> String.split(".") |> List.last() |> String.replace("_", " ")
  end

  # An unresolved org scope renders the shared not-found panel from the org
  # layout (see `ControlKeelWeb.OrgAccess`); this page body stays empty. The
  # assign is always present (defaulted to nil by the layout hook), so the
  # clause must match only a real error map.
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-8">
      <div class="grid gap-6 lg:grid-cols-[200px_minmax(0,1fr)]">
        <nav
          class="rounded-2xl border bg-card shadow-card lg:self-start lg:p-3"
          aria-label="Organization settings sections"
        >
          <ul class="flex gap-1 list-none m-0 overflow-x-auto p-2 lg:flex-col lg:gap-1 lg:p-0">
            <%= for tab <- @tabs do %>
              <li class="shrink-0">
                <button
                  type="button"
                  phx-click="set_tab"
                  phx-value-tab={tab}
                  aria-current={@active_tab == tab && "page"}
                  class={[
                    "w-full whitespace-nowrap rounded-lg px-3 py-2 text-left text-sm transition",
                    @active_tab == tab &&
                      "bg-primary/10 font-semibold text-primary",
                    @active_tab != tab &&
                      "text-muted-foreground hover:bg-muted hover:text-foreground"
                  ]}
                >
                  {tab_label(tab)}
                </button>
              </li>
            <% end %>
          </ul>
        </nav>

        <%= case @active_tab do %>
          <% "policy_sets" -> %>
            <.policy_sets_panel
              org={@org}
              policy_sets={@policy_sets}
              pack_count={@pack_count}
              rule_count={@rule_count}
              block_count={@block_count}
            />
          <% "members" -> %>
            <.members_panel
              memberships={@memberships}
              local_mode={@local_mode}
              invite_token={@invite_token}
              current_user={@current_user}
              active_owner_count={@active_owner_count}
              can_manage={can_manage?(assigns)}
              current_role={current_role(assigns)}
            />
          <% _ -> %>
            <.general_panel
              org={@org}
              settings_form={@settings_form}
              settings_error={@settings_error}
              local_mode={@local_mode}
              current_membership={@current_membership}
            />
        <% end %>
      </div>
    </section>

    <.invite_modal
      :if={@show_invite_modal}
      form={@invite_form}
      error={@invite_error}
      role_options={invite_role_options(current_role(assigns))}
    />

    <%= if @show_revoke_modal and @revoke_target do %>
      <.revoke_member_modal
        org_name={@org.name}
        revoke_target={@revoke_target}
        revoke_is_self={@revoke_is_self}
        revoke_is_last_owner={@revoke_is_last_owner}
      />
    <% end %>

    <.packs_dialog :if={@show_packs_dialog} packs={@packs} open_packs={@open_packs} />

    <.create_policy_set_modal
      :if={@show_create_modal}
      form={@form}
      rules_json={@rules_json}
      rules_error={@rules_error}
    />
    """
  end

  defp tab_label("general"), do: "General"
  defp tab_label("members"), do: "Members"
  defp tab_label("policy_sets"), do: "Policy sets"

  # ── Members panel & modals --------------------------------------------

  attr :memberships, :list, required: true
  attr :local_mode, :boolean, default: false
  attr :invite_token, :string, default: nil
  attr :current_user, :any, default: nil
  attr :active_owner_count, :integer, default: 0
  attr :can_manage, :boolean, required: true
  attr :current_role, :string, required: true

  defp members_panel(assigns) do
    ~H"""
    <section>
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between mb-8">
        <div class="space-y-1">
          <.section_title>
            Members
          </.section_title>
          <p class="text-sm text-muted-foreground">
            Manage organization members and their roles.
          </p>
        </div>

        <button
          :if={@can_manage and not @local_mode}
          type="button"
          id="invite-member-button"
          phx-click="open_invite"
          class="inline-flex items-center justify-center gap-1 rounded-xl bg-primary/15 hover:bg-primary/25 text-primary border border-primary/20 px-4 py-2 text-sm font-semibold transition active:scale-[0.98] cursor-pointer shadow-sm shrink-0"
        >
          + Invite member
        </button>
      </div>

      <%= if @invite_token do %>
        <div class="mb-6 rounded-2xl border border-primary/30 bg-primary/10 p-5">
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
        <div class="rounded-2xl border border-border/80 bg-card shadow-card p-6">
          <p class="text-sm text-muted-foreground">
            Member management is not available in local mode. Switch to cloud or self-hosted mode
            to invite teammates and manage roles.
          </p>
        </div>
      <% else %>
        <div class="rounded-2xl border border-border/80 bg-card shadow-card overflow-clip">
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
                            role_select_state(
                              @current_role,
                              m.role,
                              is_self,
                              @active_owner_count
                            ) %>
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
                        <span class="inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold capitalize ring-1 ring-inset #{status_pill_class(m.status)}">
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
    <.modal id="invite-member-modal" title="Invite member" on_close="close_invite">
      <.form for={@form} phx-submit="invite" id="invite-form" class="space-y-4">
        <.input_component
          field={@form[:email]}
          label="Email"
          type="email"
          placeholder="teammate@example.com"
          required
        />

        <.input_component field={@form[:role]} label="Role" type="select" options={@role_options} />

        <%= if @error do %>
          <p class="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">{@error}</p>
        <% end %>

        <div class="flex items-center justify-end gap-3 border-t pt-4">
          <.button variant="outline" phx-click="close_invite">Cancel</.button>
          <.button type="submit">Send invitation</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :org_name, :string, required: true
  attr :revoke_target, :map, required: true
  attr :revoke_is_self, :boolean, required: true
  attr :revoke_is_last_owner, :boolean, required: true

  defp revoke_member_modal(assigns) do
    ~H"""
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
                  in <strong class="text-foreground">{@org_name}</strong>.
                  You will lose access to this organization immediately.
                </p>
              <% else %>
                <p class="text-sm text-muted-foreground">
                  You are about to revoke membership for
                  <strong class="text-foreground">{@revoke_target.user && @revoke_target.user.email}</strong>.
                  They will lose access to <strong class="text-foreground">{@org_name}</strong>
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
    """
  end

  attr :org, :map, required: true
  attr :settings_form, :map, required: true
  attr :settings_error, :string, default: nil
  attr :current_membership, :map, default: nil
  attr :local_mode, :boolean, default: false

  defp general_panel(assigns) do
    ~H"""
    <section>
      <div class="space-y-1 mb-8">
        <.section_title>
          General
        </.section_title>
        <p class="text-sm text-muted-foreground">
          Organization identity, status, and spend limits.
        </p>
      </div>

      <.form
        for={@settings_form}
        phx-submit="save_settings"
        id="org-settings-form"
        class="space-y-6"
      >
        <div class="rounded-2xl border border-border/80 bg-card shadow-card divide-y divide-border/60">
          <div class="p-6 grid grid-cols-1 gap-4 sm:grid-cols-[1fr_minmax(0,1.2fr)] sm:items-center">
            <div>
              <label
                for={@settings_form[:name].id || "settings_name"}
                class="block text-sm font-semibold text-foreground"
              >
                Organization name
              </label>
              <p class="mt-1 text-xs text-muted-foreground">
                Shown in the sidebar and breadcrumbs.
              </p>
            </div>
            <div>
              <input
                type="text"
                id={@settings_form[:name].id || "settings_name"}
                name={@settings_form[:name].name || "settings[name]"}
                value={@settings_form[:name].value}
                required
                class="w-full rounded-xl border border-input/60 bg-background/50 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary transition"
              />
              <%= for msg <- @settings_form[:name].errors do %>
                <p class="mt-1 text-xs text-destructive">{msg}</p>
              <% end %>
            </div>
          </div>

          <div class="p-6 grid grid-cols-1 gap-4 sm:grid-cols-[1fr_minmax(0,1.2fr)] sm:items-center">
            <div>
              <label
                for={@settings_form[:status].id || "settings_status"}
                class="block text-sm font-semibold text-foreground"
              >
                Status
              </label>
              <p class="mt-1 text-xs text-muted-foreground">
                Inactive organizations stop accepting new sessions.
              </p>
            </div>
            <div>
              <div class="relative w-full">
                <select
                  id={@settings_form[:status].id || "settings_status"}
                  name={@settings_form[:status].name || "settings[status]"}
                  disabled={!panel_owner?(@current_membership, @local_mode)}
                  class="w-full appearance-none rounded-xl border border-input/60 bg-background/50 pl-3.5 pr-10 py-2.5 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary transition cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <option
                    value="active"
                    selected={to_string(@settings_form[:status].value) != "disabled"}
                  >
                    Active
                  </option>
                  <option
                    value="disabled"
                    selected={to_string(@settings_form[:status].value) == "disabled"}
                  >
                    Disabled
                  </option>
                </select>
                <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3.5 text-muted-foreground">
                  <.icon name="hero-chevron-down" class="size-4" />
                </div>
              </div>
              <%= unless panel_owner?(@current_membership, @local_mode) do %>
                <p class="mt-1 text-xs text-muted-foreground">Only owners can change status.</p>
              <% end %>
            </div>
          </div>

          <div class="p-6 grid grid-cols-1 gap-4 sm:grid-cols-[1fr_minmax(0,1.2fr)] sm:items-center">
            <div>
              <label
                for={@settings_form[:budget_cents].id || "settings_budget_cents"}
                class="block text-sm font-semibold text-foreground"
              >
                Monthly budget
              </label>
              <p class="mt-1 text-xs text-muted-foreground">
                Spend cap in cents. 0 means no limit.
              </p>
            </div>
            <div>
              <div class="relative w-full">
                <input
                  type="number"
                  id={@settings_form[:budget_cents].id || "settings_budget_cents"}
                  name={@settings_form[:budget_cents].name || "settings[budget_cents]"}
                  value={@settings_form[:budget_cents].value}
                  min="0"
                  disabled={!panel_owner?(@current_membership, @local_mode)}
                  class="w-full rounded-xl border border-input/60 bg-background/50 pl-3.5 pr-28 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary transition disabled:cursor-not-allowed disabled:opacity-50"
                />
                <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3.5 text-sm text-muted-foreground">
                  cents / mo
                </div>
              </div>
              <%= unless panel_owner?(@current_membership, @local_mode) do %>
                <p class="mt-1 text-xs text-muted-foreground">Only owners can change budget.</p>
              <% end %>
            </div>
          </div>

          <div class="p-6 grid grid-cols-1 gap-4 sm:grid-cols-[1fr_minmax(0,1.2fr)] sm:items-center">
            <div>
              <span class="block text-sm font-semibold text-foreground">
                Slug
              </span>
              <p class="mt-1 text-xs text-muted-foreground">
                Used in URLs and the API.
              </p>
            </div>
            <div class="flex items-center gap-3">
              <span class="inline-flex items-center rounded-lg border border-border/80 bg-muted/40 px-3 py-1.5 font-mono text-xs text-foreground shadow-sm">
                {@org.slug}
              </span>
              <span class="text-xs text-muted-foreground">
                Cannot be changed
              </span>
            </div>
          </div>
        </div>

        <%= if @settings_error do %>
          <p class="rounded-lg bg-destructive/10 px-4 py-2.5 text-sm text-destructive border border-destructive/20">
            {@settings_error}
          </p>
        <% end %>

        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between pt-1">
          <p class="text-xs sm:text-sm text-muted-foreground">
            Changes apply to all workspaces.
          </p>
          <button
            type="submit"
            class="inline-flex items-center justify-center rounded-xl bg-primary/15 hover:bg-primary/25 text-primary border border-primary/20 px-5 py-2.5 text-sm font-semibold transition active:scale-[0.98] cursor-pointer shadow-sm disabled:pointer-events-none disabled:opacity-50"
          >
            Save changes
          </button>
        </div>
      </.form>
    </section>
    """
  end

  # General panel's owner gate is a pure view helper over the page assigns.
  defp panel_owner?(_membership, true), do: true
  defp panel_owner?(%Accounts.Membership{role: "owner"}, _local_mode), do: true
  defp panel_owner?(_membership, _local_mode), do: false

  attr :org, :map, required: true
  attr :policy_sets, :list, required: true
  attr :pack_count, :integer, required: true
  attr :rule_count, :integer, required: true
  attr :block_count, :integer, required: true

  defp policy_sets_panel(assigns) do
    ~H"""
    <section>
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between mb-8">
        <div class="space-y-1">
          <.section_title>
            Policy sets
          </.section_title>
          <p class="text-sm text-muted-foreground">
            Every agent action passes through these policy packs before it executes.
          </p>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <button
            type="button"
            phx-click="open_packs_dialog"
            class="inline-flex items-center justify-center rounded-xl border border-border/80 bg-background/50 hover:bg-muted/40 px-4 py-2 text-sm font-semibold text-foreground transition cursor-pointer shadow-sm"
          >
            View packs
          </button>
          <button
            type="button"
            phx-click="open_create_modal"
            class="inline-flex items-center justify-center gap-1 rounded-xl bg-primary/15 hover:bg-primary/25 text-primary border border-primary/20 px-4 py-2 text-sm font-semibold transition active:scale-[0.98] cursor-pointer shadow-sm"
          >
            + New policy set
          </button>
        </div>
      </div>

      <div class="rounded-2xl border border-border/80 bg-card shadow-card divide-y divide-border/60">
        <%= if @policy_sets == [] do %>
          <div class="p-6">
            <p class="text-sm text-muted-foreground">
              No custom policy sets yet. Use the New policy set button to create one.
            </p>
          </div>
        <% else %>
          <%= for set <- @policy_sets do %>
            <div class="p-6 flex items-center justify-between gap-4">
              <div class="space-y-1">
                <h3 class="text-base font-semibold text-foreground">{set.name}</h3>
                <%= if set.description not in [nil, ""] do %>
                  <p class="text-sm text-muted-foreground">{set.description}</p>
                <% end %>
                <p class="text-xs sm:text-sm text-muted-foreground">
                  {length(ControlKeel.Platform.PolicySet.rule_entries(set))} rules ·
                  <%= if set.workspace_policy_sets != [] do %>
                    Applied to {Enum.map_join(set.workspace_policy_sets, ", ", &assignment_summary/1)}
                  <% else %>
                    Not applied to any workspace yet
                  <% end %>
                </p>
                <% entries =
                  Enum.filter(ControlKeel.Platform.PolicySet.rule_entries(set), &is_binary(&1["id"])) %>
                <%= if entries != [] do %>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <%= for rule <- entries do %>
                      <.rule_tag
                        action={rule["action"]}
                        title={"#{rule["action"]}, #{rule["category"]}"}
                        class="px-2.5 py-1 text-xs font-medium"
                      >
                        {rule_name(rule["id"])}
                      </.rule_tag>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <div class="shrink-0">
                <span
                  title={set.status}
                  class={"inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold capitalize ring-1 ring-inset #{status_pill_class(set.status)}"}
                >
                  {set.status}
                </span>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <p class="mt-6 text-xs sm:text-sm text-muted-foreground">
        <span class="font-semibold text-destructive">{@block_count} rules</span>
        block agent actions when violated; other rules only warn. {@pack_count} packs · {@rule_count} rules total, shipped with ControlKeel.
      </p>
    </section>
    """
  end

  defp rules_json_placeholder do
    ~S([
  {
    "id": "shell.destructive_rm_rf",
    "category": "security",
    "severity": "critical",
    "action": "block",
    "plain_message": "Recursive force-delete commands are blocked in this workspace.",
    "matcher": { "type": "regex", "patterns": ["rm\\s+-rf\\s+/"] }
  }
])
  end

  attr :form, :map, required: true
  attr :rules_json, :string, default: ""
  attr :rules_error, :string, default: nil

  defp create_policy_set_modal(assigns) do
    ~H"""
    <.modal id="policy-set-create-modal" title="New policy set" on_close="close_create_modal">
      <.form
        for={@form}
        phx-change="validate_policy_set"
        phx-submit="save_policy_set"
        id="policy-set-form"
        class="space-y-4"
      >
        <.input_component
          field={@form[:name]}
          label="Name"
          placeholder="no-rm-rf"
          required
        />

        <.input_component
          field={@form[:description]}
          label="Description"
          placeholder="Example: no rm -rf rules"
          required
        />

        <.textarea
          name="policy_set[rules_json]"
          value={@rules_json}
          label="Rules JSON (optional)"
          placeholder={rules_json_placeholder()}
          spellcheck="false"
          class="min-h-40 font-mono text-xs"
          errors={if @rules_error, do: [@rules_error], else: []}
        />

        <div class="flex items-center justify-end gap-3 border-t pt-4">
          <.button variant="outline" phx-click="close_create_modal">Cancel</.button>
          <.button type="submit">Create policy set</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :packs, :list, required: true
  attr :open_packs, :any, required: true

  defp packs_dialog(assigns) do
    ~H"""
    <.modal
      id="packs-dialog"
      title="Built-in policy packs"
      on_close="close_packs_dialog"
      width="max-w-3xl"
    >
      <div class="divide-y divide-border">
        <%= for {name, rules} <- @packs do %>
          <% open? = MapSet.member?(@open_packs, name) %>
          <% panel_id = "pack-panel-#{name}"
          label_id = "#{panel_id}-label" %>
          <article class="py-2 first:pt-0 last:pb-0">
            <h3 class="m-0">
              <button
                type="button"
                phx-click="toggle_pack"
                phx-value-name={name}
                aria-expanded={open?}
                aria-controls={panel_id}
                class="flex w-full cursor-pointer select-none items-center justify-between gap-4 py-2 text-left"
              >
                <span id={label_id} class="text-base font-semibold text-foreground">
                  {pack_label(name)}
                </span>
                <span class="flex items-center gap-2">
                  <span class="text-xs text-muted-foreground">
                    {length(rules)} rules
                  </span>
                  <svg
                    aria-hidden="true"
                    class={"size-4 text-muted-foreground transition-transform duration-200 #{if open?, do: "rotate-180", else: ""}"}
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </span>
              </button>
            </h3>
            <%= if open? do %>
              <div id={panel_id} role="region" aria-labelledby={label_id} class="pb-2 pl-1">
                <p class="text-sm text-muted-foreground">{pack_description(name)}</p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <%= for rule <- rules do %>
                    <.rule_tag
                      action={rule.action}
                      title={rule.action <> ", " <> rule.category}
                      class="px-2.5 py-1 text-xs font-medium"
                    >
                      {rule_name(rule.id)}
                    </.rule_tag>
                  <% end %>
                </div>
              </div>
            <% end %>
          </article>
        <% end %>
      </div>
    </.modal>
    """
  end
end
