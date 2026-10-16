defmodule ControlKeelWeb.PolicyStudioLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Platform
  alias ControlKeel.Platform.PolicySet
  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    # Policy sets execute inside whichever workspace they are assigned to, so
    # reading and creating them is an org-admin action. This was explicitly
    # deferred ("tighten both in a future auth pass", #117) and that pass had not
    # happened; see issue #249. Local mode has no membership table and stays open.
    case admin_access?(socket) do
      :ok ->
        {:ok,
         socket
         |> assign(:page_title, "Policy Studio")
         |> assign(:open_packs, MapSet.new())
         |> assign(:show_packs_dialog, false)
         |> assign_packs()
         |> assign_policy_sets()
         |> assign(:show_create_modal, false)
         |> assign_policy_set_form(empty_policy_set_changeset(), "", nil)}

      {:error, :unauthenticated} ->
        {:ok, redirect_with_flash(socket, :error, "Sign in to manage policies.", ~p"/auth/login")}

      {:error, :forbidden} ->
        {:ok,
         redirect_with_flash(
           socket,
           :error,
           "You don't have permission to manage policies.",
           ~p"/organizations"
         )}
    end
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
    # Defence in depth: mount already denies non-admins, but a mutation must
    # never rely on the page having been rendered to an authorized viewer.
    if admin_access?(socket) != :ok do
      {:noreply, put_flash(socket, :error, "You don't have permission to manage policies.")}
    else
      do_save_policy_set(params, socket)
    end
  end

  defp do_save_policy_set(params, socket) do
    {attrs, changeset, raw, ui_error} = prepare_policy_set(params, :insert)

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
  def render(assigns) do
    ~H"""
    <section>
      <.page_title
        title="Policy Studio"
        subtitle="Every agent action passes through these policy packs before it executes."
        class="mb-8"
      />

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_260px]">
        <section>
          <div class="flex items-center justify-between mb-4">
            <.section_title>Custom policy sets</.section_title>
            <.button phx-click="open_create_modal">
              <.icon name="hero-plus" class="size-3.5" /> New policy set
            </.button>
          </div>

          <%= if @policy_sets == [] do %>
            <p class="mt-4 text-sm text-muted-foreground">
              No custom policy sets yet. Use the New policy set button to create one.
            </p>
          <% else %>
            <ul class="mt-4 divide-y divide-border bg-card p-5 rounded-2xl shadow-card">
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
                    {length(Platform.PolicySet.rule_entries(set))} rules · scope: {set.scope}
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
                  <% entries = Enum.filter(Platform.PolicySet.rule_entries(set), &is_binary(&1["id"])) %>
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
        </section>

        <aside class="self-start rounded-2xl border bg-card p-5 shadow-card">
          <h3 class="text-base font-semibold text-foreground">Built-in policy packs</h3>
          <p class="mt-2 text-sm text-muted-foreground">
            <span class="mr-1 inline-flex rounded-full bg-destructive/10 px-2.5 py-1 align-middle text-xs font-semibold text-destructive ring-1 ring-destructive/20">
              {@block_count} rules
            </span>
            block agent actions when violated; other rules only warn.
          </p>
          <p class="mt-2 text-xs text-muted-foreground">
            {@pack_count} packs · {@rule_count} rules total, shipped with ControlKeel.
          </p>
          <.button variant="outline" phx-click="open_packs_dialog" class="mt-4 w-full">
            View packs
          </.button>
        </aside>
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

        <div>
          <label
            for="policy-set-scope"
            class="mb-1.5 flex items-center gap-1.5 text-sm font-medium text-foreground/90"
          >
            Scope
          </label>
          <select
            id="policy-set-scope"
            name="policy_set[scope]"
            class="h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-base transition-colors outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 md:text-sm"
          >
            <option value="workspace" selected={@form[:scope].value in [nil, "workspace"]}>
              Workspace
            </option>
            <option value="global" selected={@form[:scope].value == "global"}>
              Global
            </option>
          </select>
        </div>

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

  defp assign_packs(socket) do
    packs = PackLoader.all_packs()
    all_rules = packs |> Map.values() |> List.flatten()

    blocked_rules =
      packs
      |> Enum.map(fn {name, rules} -> {name, Enum.filter(rules, &(&1.action == "block"))} end)
      |> Enum.reject(fn {_name, rules} -> rules == [] end)
      |> Enum.sort_by(fn {name, _} -> pack_sort_order(name) end)

    socket
    |> assign(:packs, Enum.sort_by(packs, fn {name, _} -> pack_sort_order(name) end))
    |> assign(:pack_names, MapSet.new(Map.keys(packs)))
    |> assign(:pack_count, map_size(packs))
    |> assign(:rule_count, length(all_rules))
    |> assign(:block_count, Enum.count(all_rules, &(&1.action == "block")))
    |> assign(:blocked_rules, blocked_rules)
  end

  # Resolves whether the viewer may read/create policy sets. Authority is
  # derived from `(user, current org)` — never from the ambient cookie alone.
  defp admin_access?(socket) do
    cond do
      Mode.current() == :local ->
        :ok

      is_nil(socket.assigns[:current_user]) ->
        {:error, :unauthenticated}

      true ->
        case socket.assigns[:current_org_id] do
          org_id when is_integer(org_id) ->
            case ControlKeel.Accounts.get_active_membership(
                   socket.assigns.current_user.id,
                   org_id
                 ) do
              %{role: role} ->
                if ControlKeel.Accounts.role_at_least?(role, "admin"),
                  do: :ok,
                  else: {:error, :forbidden}

              _ ->
                {:error, :forbidden}
            end

          _ ->
            {:error, :forbidden}
        end
    end
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.redirect(to: path)
  end

  defp assign_policy_sets(socket) do
    # Visibility of workspace assignments is scoped to the viewer's org. The
    # underlying policy-set rows remain global (see issue #249): they carry no
    # tenant column yet, so the role gate above is what prevents one org from
    # creating rules that execute in another's workspace.
    assignments_by_set =
      Platform.list_workspace_policy_assignments()
      |> Enum.group_by(& &1.policy_set_id)

    policy_sets =
      Platform.list_policy_sets()
      |> Enum.map(fn set ->
        Map.put(set, :workspace_policy_sets, Map.get(assignments_by_set, set.id, []))
      end)

    assign(socket, :policy_sets, policy_sets)
  end

  defp assignment_summary(assignment) do
    suffix = if assignment.enabled, do: "", else: ", disabled"
    "workspace ##{assignment.workspace_id} (precedence #{assignment.precedence}#{suffix})"
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
end
