defmodule ControlKeelWeb.OrganizationSettingsLive do
  @moduledoc """
  Organization settings at `/:org_slug/settings`.

  Secondary navigation over setting groups, mirroring the workspace settings
  pattern (`?tab=` query param + `push_patch`). Two groups today: General
  (name, status, budget) and Policy sets (org-owned policy sets — the former
  global Policy Studio, now scoped to the organization).
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Intent
  alias ControlKeel.Platform
  alias ControlKeel.Platform.PolicySet
  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Runtime.Mode
  alias ControlKeelWeb.OrgAccess

  @tabs ["general", "policy_sets"]

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
  defp normalize_tab(_tab), do: "general"

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply,
     push_patch(socket, to: ~p"/#{socket.assigns.org.slug}/settings?tab=#{tab}")}
  end

  def handle_event("set_tab", _params, socket), do: {:noreply, socket}

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

    {:ok,
     socket
     |> assign(:page_title, "Organization Settings - #{org.name}")
     |> assign(:org, org)
     |> assign(:nav_org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:current_membership, membership)
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
      <div class="space-y-2">
        <p class="text-sm font-medium text-primary">Organization</p>
        <h1 class="text-xl font-semibold tracking-tight text-foreground sm:text-2xl">
          Settings
        </h1>
        <p class="text-sm text-muted-foreground">
          Manage settings for {@org.name}.
        </p>
      </div>

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
  defp tab_label("policy_sets"), do: "Policy sets"

  attr :org, :map, required: true
  attr :settings_form, :map, required: true
  attr :settings_error, :string, default: nil
  attr :current_membership, :map, default: nil
  attr :local_mode, :boolean, default: false

  defp general_panel(assigns) do
    ~H"""
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
            disabled={!panel_owner?(@current_membership, @local_mode)}
            class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />
          <%= unless panel_owner?(@current_membership, @local_mode) do %>
            <p class="mt-1 text-xs text-muted-foreground">Only owners can change status.</p>
          <% end %>
        </div>

        <div>
          <.input
            field={@settings_form[:budget_cents]}
            type="number"
            label="Monthly budget (cents)"
            disabled={!panel_owner?(@current_membership, @local_mode)}
            class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />
          <%= unless panel_owner?(@current_membership, @local_mode) do %>
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
    <section class="space-y-4">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="text-sm font-semibold text-foreground">Custom policy sets</p>
          <p class="mt-1 text-xs text-muted-foreground">
            Every agent action passes through these policy packs before it executes. The
            sets below belong to {@org.name}; its workspaces can apply them.
          </p>
        </div>

        <div class="flex shrink-0 gap-2">
          <.button variant="outline" phx-click="open_packs_dialog">View packs</.button>
          <.button phx-click="open_create_modal">
            <.icon name="hero-plus" class="size-3.5" /> New policy set
          </.button>
        </div>
      </div>

      <div class="rounded-2xl border bg-card p-5 shadow-card">
        <%= if @policy_sets == [] do %>
          <p class="text-sm text-muted-foreground">
            No custom policy sets yet. Use the New policy set button to create one.
          </p>
        <% else %>
          <ul class="divide-y divide-border">
            <%= for set <- @policy_sets do %>
              <li class="py-4 first:pt-0 last:pb-0">
                <div class="flex items-center justify-between gap-4">
                  <h3 class="text-base font-semibold text-foreground">{set.name}</h3>
                  <span
                    title={set.status}
                    class={"inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 #{status_pill_class(set.status)}"}
                  >
                    {set.status}
                  </span>
                </div>
                <p class="mt-1 text-sm text-muted-foreground">
                  {length(ControlKeel.Platform.PolicySet.rule_entries(set))} rules
                  <%= if set.description not in [nil, ""] do %>
                    · {set.description}
                  <% end %>
                </p>
                <%= if set.workspace_policy_sets != [] do %>
                  <p class="mt-1 text-xs text-muted-foreground">
                    Applied to: {Enum.map_join(
                      set.workspace_policy_sets,
                      ", ",
                      &assignment_summary/1
                    )}
                  </p>
                <% else %>
                  <p class="mt-1 text-xs text-muted-foreground">
                    Not applied to any workspace yet.
                  </p>
                <% end %>
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
              </li>
            <% end %>
          </ul>
        <% end %>

        <div class="mt-4 border-t pt-4">
          <p class="text-sm text-muted-foreground">
            <span class="mr-1 inline-flex rounded-full bg-destructive/10 px-2.5 py-1 align-middle text-xs font-semibold text-destructive ring-1 ring-destructive/20">
              {@block_count} rules
            </span>
            block agent actions when violated; other rules only warn. {@pack_count} packs ·
            {@rule_count} rules total, shipped with ControlKeel.
          </p>
        </div>
      </div>
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
