defmodule ControlKeelWeb.SkillsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.MCP.Tools.CkTokenAudit
  alias ControlKeel.Project.Local
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Skills
  alias ControlKeel.Skills.SkillTarget

  @audit_modes ~w(full skills rules tools)
  @all_scopes ["export", "user", "project"]
  @scope_labels %{"export" => "Export", "user" => "User", "project" => "Project"}

  @impl true
  def mount(_params, _session, socket) do
    project_root = File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Skills Studio")
     |> assign(:selected, nil)
     |> assign(:last_result, nil)
     |> assign(:last_export_target, nil)
     |> assign(:target_options, target_options())
     |> assign(:scope_options, scope_options("open-standard"))
     |> assign_analysis(project_root)
     |> assign_doctor(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:action_form, action_form())
     |> assign(:prune_preview, nil)
     |> assign(:audit_mode, "full")
     |> assign(:audit_mode_options, @audit_modes)
     |> assign(:audit_result, nil)
     |> assign(:audit_error, nil)
     |> assign(:audit_sort, %{})
     |> assign(:skill_search, "")
     |> assign(:target_search, "")}
  end

  @impl true
  def handle_event("select_skill", %{"name" => name}, socket) do
    selected = Enum.find(socket.assigns.skills, &(&1.name == name))
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("search_skills", %{"skill_search" => search}, socket) do
    skills = socket.assigns.skills
    like = String.downcase(String.trim(search))

    filtered =
      if like == "" do
        skills
      else
        Enum.filter(skills, fn skill ->
          String.contains?(String.downcase(skill.name), like) or
            (skill.description && String.contains?(String.downcase(skill.description), like))
        end)
      end

    {:noreply,
     socket
     |> assign(:skill_search, search)
     |> assign(:filtered_skills, filtered)}
  end

  def handle_event("search_targets", %{"target_search" => search}, socket) do
    targets = socket.assigns.targets
    like = String.downcase(String.trim(search))

    filtered =
      if like == "" do
        targets
      else
        Enum.filter(targets, fn target ->
          String.contains?(String.downcase(target.label), like) or
            (target.description && String.contains?(String.downcase(target.description), like))
        end)
      end

    {:noreply,
     socket
     |> assign(:target_search, search)
     |> assign(:filtered_targets, filtered)}
  end

  def handle_event("validate_project", %{"project" => %{"project_root" => project_root}}, socket) do
    project_root = String.trim(project_root)

    {:noreply,
     socket
     |> assign_analysis(project_root)
     |> assign_doctor(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:selected, nil)}
  end

  def handle_event("update_action_form", %{"skill_action" => params}, socket) do
    params = normalize_action_params(params)

    {:noreply,
     socket
     |> assign(:action_form, action_form(params))
     |> assign(:scope_options, scope_options(params["target"]))}
  end

  def handle_event("bootstrap_project", _params, socket) do
    project_root = socket.assigns.project_root

    case Local.load_or_bootstrap(project_root, %{}, ephemeral_ok: true) do
      {:ok, _binding, _session, mode} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Bootstrapped project (#{mode}). Project-local skills are allowed now."
         )
         |> assign_analysis(project_root)
         |> assign_doctor(project_root)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to bootstrap project: #{inspect(reason)}")}
    end
  end

  def handle_event("copy_command", %{"command" => command}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: command})
     |> put_flash(:info, "Copied command to clipboard.")}
  end

  def handle_event("preview_prune", _params, socket) do
    preview = Skills.prune_duplicate_skills_preview(socket.assigns.project_root)

    socket =
      if preview.user_level == [] do
        socket
        |> assign(:prune_preview, nil)
        |> put_flash(:info, "No user-level duplicate skill copies to prune.")
      else
        preview = Map.put(preview, :project_root, socket.assigns.project_root)
        assign(socket, :prune_preview, preview)
      end

    {:noreply, socket}
  end

  def handle_event("cancel_prune", _params, socket) do
    {:noreply, assign(socket, :prune_preview, nil)}
  end

  def handle_event("confirm_prune", _params, socket) do
    case socket.assigns.prune_preview do
      %{project_root: previewed_root} ->
        if previewed_root != socket.assigns.project_root do
          {:noreply,
           socket
           |> assign(:prune_preview, nil)
           |> put_flash(
             :error,
             "Project root changed since the preview. Re-run the prune preview."
           )}
        else
          {:ok, %{removed: removed}} = Skills.prune_duplicate_skills(previewed_root)
          count = length(removed)

          {:noreply,
           socket
           |> assign(:prune_preview, nil)
           |> put_flash(
             :info,
             "Pruned #{count} user-level duplicate skill #{pluralize("copy", count)}."
           )
           |> assign_analysis(previewed_root)
           |> assign_doctor(previewed_root)}
        end

      _preview_without_root ->
        {:noreply, socket}
    end
  end

  def handle_event("run_audit", %{"mode" => mode}, socket) do
    mode = if mode in @audit_modes, do: mode, else: "full"

    case CkTokenAudit.call(%{"project_root" => socket.assigns.project_root, "mode" => mode}) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:audit_mode, mode)
         |> assign(:audit_result, result)
         |> assign(:audit_error, nil)
         |> assign(:audit_sort, %{})}

      {:error, {:invalid_arguments, message}} ->
        {:noreply,
         socket
         |> assign(:audit_mode, mode)
         |> assign(:audit_result, nil)
         |> assign(:audit_error, message)}
    end
  end

  def handle_event("sort_audit", %{"table" => table, "key" => key}, socket) do
    {current_key, current_dir} =
      Map.get(socket.assigns.audit_sort, table, {"estimated_tokens", :desc})

    {key, dir} =
      cond do
        current_key == key and current_dir == :desc -> {key, :asc}
        current_key == key and current_dir == :asc -> {key, :desc}
        true -> {key, :desc}
      end

    {:noreply, assign(socket, :audit_sort, Map.put(socket.assigns.audit_sort, table, {key, dir}))}
  end

  def handle_event("export", params, socket) do
    project_root = socket.assigns.project_root
    params = normalize_action_params(params)
    target = params["target"]
    scope = params["scope"]

    result =
      case Skills.export(target, project_root, scope: scope) do
        {:ok, plan} ->
          {:info, "Exported #{plan.target} bundle to #{plan.output_dir}."}

        {:error, reason} ->
          {:error, "Failed to export skills: #{inspect(reason)}"}
      end

    last_export_target =
      if elem(result, 0) == :info, do: target, else: socket.assigns.last_export_target

    {:noreply,
     socket
     |> put_flash(elem(result, 0), elem(result, 1))
     |> assign(:last_result, result)
     |> assign(:last_export_target, last_export_target)
     |> assign(:action_form, action_form(params))
     |> assign(:scope_options, scope_options(target))
     |> assign_analysis(project_root)
     |> assign_doctor(project_root)}
  end

  def handle_event("install", params, socket) do
    project_root = socket.assigns.project_root
    params = normalize_action_params(params)
    target = params["target"]
    scope = params["scope"]

    result =
      case Skills.install(target, project_root, scope: scope) do
        {:ok, %{destination: destination} = install} ->
          agent_line =
            if Map.has_key?(install, :agent_destination) do
              " Agent: #{install.agent_destination}."
            else
              ""
            end

          marketplace_line =
            if Map.has_key?(install, :marketplace_destination) do
              " Marketplace: #{install.marketplace_destination}."
            else
              ""
            end

          {:info,
           "Installed #{install.target} skills to #{destination}.#{agent_line}#{marketplace_line}"}

        {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
          {:info, "Prepared #{plan.target} bundle at #{plan.output_dir}."}

        {:error, reason} ->
          {:error, "Failed to install skills: #{inspect(reason)}"}
      end

    {:noreply,
     socket
     |> put_flash(elem(result, 0), elem(result, 1))
     |> assign(:last_result, result)
     |> assign(:action_form, action_form(params))
     |> assign(:scope_options, scope_options(target))
     |> assign_analysis(project_root)
     |> assign_doctor(project_root)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-[min(1180px,calc(100%-2rem))] mx-auto">
      <div class="space-y-1">
        <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
          Skills Studio
        </h2>
        <p class="text-muted-foreground">
          Native skills and plugin operator console
        </p>
      </div>

      <div class="mt-12 space-y-10">
        <div class="grid grid-cols-2 gap-4">
          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-lg font-semibold text-primary tracking-[0.14em] uppercase mb-3">
              How this works
            </p>
            <ul class="text-muted-foreground text-sm leading-[1.7] list-disc px-4 grid gap-1">
              <li>Skills live in `priv/skills/`, validated and cataloged at startup.</li>
              <li>`ck_skill_list` / `ck_skill_load` are the universal MCP fallback.</li>
              <li>Native targets generated from the catalog — no hand-maintained lists.</li>
              <li>Project-local skills load only when the project is trusted or allowed.</li>
              <li>
                Can export or install the same capability set for Codex, Claude Code, Cline, Copilot / VS Code, and MCP-only tools.
              </li>
            </ul>
          </div>

          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <.form
              for={@project_form}
              id="skills-project-form"
              phx-submit="validate_project"
              class="flex flex-col justify-between h-full"
            >
              <div>
                <.input
                  field={@project_form[:project_root]}
                  type="text"
                  label="Project root"
                  placeholder="/absolute/path/to/project"
                  class="p-3 w-full focus:outline-border border-r-2"
                />
              </div>
              <div class="flex items-end">
                <button
                  type="submit"
                  class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full bg-primary text-[#11170d] font-bold transition-[transform,box-shadow] duration-150 ease-in-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] cursor-pointer"
                  id="skills-project-submit"
                >
                  Refresh catalog
                </button>
              </div>
            </.form>
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4">
          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Total skills
            </p>
            <strong>{@total_skills || length(@skills)}</strong>
          </div>
          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Skill warnings
            </p>
            <strong>{@warning_count || Enum.count(@diagnostics, &(&1.level == "warn"))}</strong>
          </div>
          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Skill errors
            </p>
            <strong>{@error_count || Enum.count(@diagnostics, &(&1.level == "error"))}</strong>
          </div>
          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Health
            </p>
            <div class="flex items-center gap-2 mt-1">
              <span class={
                if @valid?,
                  do:
                    "border rounded-full px-3 py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]",
                  else:
                    "border rounded-full px-3 py-[0.45rem] text-[0.8rem] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
              }>
                {if @valid?, do: "✓ valid", else: "✗ needs fix"}
              </span>
            </div>
            <p class="text-xs text-muted-foreground mt-2">
              {@total_skills || length(@skills)} total · {@warning_count || 0} warnings · {@error_count ||
                0} errors
            </p>
            <p :if={@validated_at} class="text-xs text-muted-foreground">
              validated {Calendar.strftime(@validated_at, "%H:%M:%S UTC")}
            </p>
          </div>

          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Identical copies
            </p>
            <strong class={if @identical_count > 0, do: "text-[#fff0bf]", else: "text-[#d2ffe7]"}>
              {@identical_count}
            </strong>
            <p class="text-xs text-muted-foreground">expected distribution</p>
          </div>

          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Shadowed copies
            </p>
            <strong class={if @shadowed_count > 0, do: "text-[#ffd6cb]", else: "text-[#d2ffe7]"}>
              {@shadowed_count}
            </strong>
            <p class="text-xs text-muted-foreground">needs fix</p>
          </div>

          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Local skills
            </p>
            <strong>{if @trusted_project?, do: "allowed", else: "gated"}</strong>
            <p :if={not @trusted_project?} class="text-xs text-muted-foreground mt-2">
              Project-local skills are skipped until ControlKeel trusts this project. Bootstrapping writes a project binding and allows them.
            </p>
            <button
              :if={not @trusted_project?}
              type="button"
              id="skills-bootstrap-button"
              phx-click="bootstrap_project"
              class="mt-3 inline-flex items-center justify-center gap-[0.4rem] px-4 py-2 rounded-full border bg-transparent text-sm font-semibold transition-[transform,background] duration-150 ease-in-out hover:bg-card hover:-translate-y-px cursor-pointer"
            >
              Bootstrap project
            </button>
          </div>

          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Bootstrap
            </p>
            <strong>{@bootstrap_mode}</strong>
          </div>

          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Duplicate copies
            </p>
            <strong class={if @duplicate_copy_count > 0, do: "text-[#ffd6cb]", else: ""}>
              {@duplicate_copy_count}
            </strong>
            <p class="text-xs text-muted-foreground">
              {@identical_count} identical · {@shadowed_count} shadowed
            </p>
            <button
              :if={@identical_count > 0}
              type="button"
              id="skills-prune-button"
              phx-click="preview_prune"
              class="mt-3 inline-flex items-center justify-center gap-[0.4rem] px-4 py-2 rounded-full border bg-transparent text-sm font-semibold transition-[transform,background] duration-150 ease-in-out hover:bg-card hover:-translate-y-px cursor-pointer"
            >
              Prune user-level duplicates
            </button>
          </div>
        </div>

        <%= if @export_manifests != [] do %>
          <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 my-4">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              Export manifests ({length(@export_manifests)})
            </p>
            <div class="grid gap-3 mt-3">
              <%= for %{path: path, manifest: manifest} <- @export_manifests do %>
                <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.35rem]">
                  <div class="flex items-center justify-between gap-4">
                    <h3>{manifest["target"]}</h3>
                    <span class="border rounded-full px-3 py-[0.45rem] text-[0.8rem]">
                      {manifest["scope"]}
                    </span>
                  </div>
                  <p class="text-muted-foreground text-xs">
                    ck={manifest["controlkeel_version"]} &middot; {manifest["installed_at"]}
                  </p>
                  <p class="text-muted-foreground text-xs font-mono">
                    {Path.relative_to(path, @project_root)}
                  </p>
                </article>
              <% end %>
            </div>
            <p :if={@duplicate_copy_count > 0} class="text-[#ffd6cb] text-xs mt-3">
              ⚠ {duplicate_token_warning(@duplicate_copy_count)}
            </p>
          </div>
        <% end %>

        <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
            Export and install
          </p>
          <.form for={@action_form} id="skills-action-form" phx-change="update_action_form">
            <div class="grid grid-cols-2 gap-4 mt-4">
              <div>
                <.input
                  field={@action_form[:target]}
                  type="select"
                  label="Target:"
                  options={@target_options}
                  class="p-2 border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)]"
                />
              </div>
              <div>
                <.input
                  field={@action_form[:scope]}
                  type="select"
                  label="Scope:"
                  options={@scope_options}
                  class="p-2 border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] min-w-[250px]"
                />
              </div>
            </div>

            <%= if @last_result do %>
              <p class="text-muted-foreground mt-[0.85rem]">
                Last action: {elem(@last_result, 1)}
              </p>
            <% end %>

            <div class="flex flex-wrap items-center justify-end gap-4 mt-4">
              <a
                :if={@last_export_target}
                id="skills-download-bundle"
                href={"/api/v1/skills/download-bundle?project_root=#{URI.encode_www_form(@project_root)}&target=#{@last_export_target}"}
                download={"controlkeel-#{@last_export_target}.zip"}
                class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full border bg-transparent font-semibold transition-[transform,background] duration-150 ease-in-out hover:bg-card hover:-translate-y-px cursor-pointer"
              >
                Download bundle
              </a>
              <button
                type="button"
                class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full bg-primary text-[#11170d] font-bold transition-[transform,box-shadow] duration-150 ease-in-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] cursor-pointer"
                id="skills-export-button"
                phx-click="export"
                phx-value-target={@action_form.params["target"]}
                phx-value-scope={@action_form.params["scope"]}
              >
                Export bundle
              </button>
              <button
                type="button"
                class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full border bg-transparent font-semibold transition-[transform,background] duration-150 ease-in-out hover:bg-card hover:-translate-y-px cursor-pointer"
                id="skills-install-button"
                phx-click="install"
                phx-value-target={@action_form.params["target"]}
                phx-value-scope={@action_form.params["scope"]}
              >
                Install target
              </button>
            </div>
          </.form>
        </div>

        <div
          class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          id="token-audit-section"
        >
          <p class="text-lg font-semibold text-primary tracking-[0.14em] uppercase">
            Token Audit
          </p>
          <p class="text-muted-foreground text-sm mt-1">
            Rule-file, skill, and tool-schema token overhead for this project root.
          </p>

          <div class="flex flex-wrap items-center gap-2 mt-4 mb-4">
            <%= for mode <- @audit_mode_options do %>
              <button
                type="button"
                id={"audit-mode-#{mode}"}
                phx-click="run_audit"
                phx-value-mode={mode}
                class={
                  if @audit_mode == mode do
                    "rounded-full bg-primary px-4 py-2 text-sm font-bold text-[#11170d] transition hover:-translate-y-px cursor-pointer"
                  else
                    "rounded-full border bg-transparent px-4 py-2 text-sm font-semibold transition hover:bg-card cursor-pointer"
                  end
                }
              >
                {String.capitalize(mode)}
              </button>
            <% end %>
            <%= if @audit_result do %>
              <a
                href={"/api/v1/skills/token-audit?project_root=#{URI.encode_www_form(@project_root)}&mode=#{@audit_mode}&download=1"}
                download={"token-audit-#{@audit_mode}.json"}
                id="audit-download-link"
                class="rounded-full border bg-transparent px-4 py-2 text-sm font-semibold transition hover:bg-card cursor-pointer"
              >
                Download JSON
              </a>
            <% end %>
          </div>

          <div :if={@audit_error} class="text-[#ffd6cb] text-sm mb-4">
            {@audit_error}
          </div>

          <div :if={is_nil(@audit_result)} class="text-muted-foreground text-sm">
            Run an audit to see the token breakdown. Click a column header to sort a table.
          </div>

          <%= if @audit_result do %>
            <div class="flex flex-wrap gap-2 mb-4">
              <%= for chip <- audit_summary_chips(@audit_mode, @audit_result) do %>
                <span class="border rounded-full px-3 py-[0.45rem] text-xs bg-[rgba(255,255,255,0.05)]">
                  {chip}
                </span>
              <% end %>
            </div>

            <%= if @audit_mode in ~w(full rules) and @audit_result["rule_files"] not in [nil, []] do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                Rule files ({length(@audit_result["rule_files"])})
              </p>
              <div class="overflow-x-auto mb-6">
                <table class="min-w-full text-sm" id="audit-rules-table">
                  <thead>
                    <tr class="text-foreground">
                      <.audit_th table="rules" key="path" sort={@audit_sort} label="File" />
                      <.audit_th table="rules" key="word_count" sort={@audit_sort} label="Words" />
                      <.audit_th table="rules" key="char_count" sort={@audit_sort} label="Chars" />
                      <.audit_th
                        table="rules"
                        key="estimated_tokens"
                        sort={@audit_sort}
                        label="Tokens"
                      />
                      <th class="text-left py-2 pr-4">Oversized</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for rule <- audit_sorted(@audit_result["rule_files"], "rules", @audit_sort) do %>
                      <tr>
                        <td class="py-2 pr-4 font-mono text-xs">
                          {Path.relative_to(rule["path"], @project_root)}
                        </td>
                        <td class="py-2 pr-4">{rule["word_count"]}</td>
                        <td class="py-2 pr-4">{rule["char_count"]}</td>
                        <td class="py-2 pr-4">{rule["estimated_tokens"]}</td>
                        <td class="py-2 pr-4">
                          {if rule["oversized"], do: "yes", else: "no"}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>

            <%= if @audit_mode in ~w(full skills) do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                Skills ({audit_skill_rows(@audit_result) |> length()} effective of {@audit_result[
                  "installed_skill_copies"
                ] || 0} copies)
              </p>
              <div class="overflow-x-auto mb-6">
                <table class="min-w-full text-sm" id="audit-skills-table">
                  <thead>
                    <tr class="text-foreground">
                      <.audit_th
                        table="skills"
                        key="name"
                        sort={@audit_sort}
                        label="Skill"
                        id="audit-skills-sort-name"
                      />
                      <.audit_th table="skills" key="location" sort={@audit_sort} label="Location" />
                      <.audit_th table="skills" key="word_count" sort={@audit_sort} label="Words" />
                      <.audit_th
                        table="skills"
                        key="estimated_tokens"
                        sort={@audit_sort}
                        label="Tokens"
                      />
                    </tr>
                  </thead>
                  <tbody>
                    <%= for skill <- audit_sorted(audit_skill_rows(@audit_result), "skills", @audit_sort) do %>
                      <tr>
                        <td class="py-2 pr-4">{skill["name"]}</td>
                        <td class="py-2 pr-4 font-mono text-xs">{skill["location"]}</td>
                        <td class="py-2 pr-4">{skill["word_count"]}</td>
                        <td class="py-2 pr-4">{skill["estimated_tokens"]}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <%= if audit_duplicates(@audit_result) != [] do %>
                <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                  Duplicate skill groups ({length(audit_duplicates(@audit_result))})
                </p>
                <div class="overflow-x-auto mb-6">
                  <table class="min-w-full text-sm" id="audit-duplicates-table">
                    <thead>
                      <tr class="text-foreground">
                        <th class="text-left py-2 pr-4">Skill</th>
                        <th class="text-left py-2 pr-4">Copies</th>
                        <th class="text-left py-2 pr-4">Wasted tokens</th>
                        <th class="text-left py-2 pr-4">Locations</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for dup <- audit_duplicates(@audit_result) do %>
                        <tr>
                          <td class="py-2 pr-4">{dup["name"]}</td>
                          <td class="py-2 pr-4">{dup["count"]}</td>
                          <td class="py-2 pr-4 text-[#ffd6cb]">{dup["duplicate_tokens"]}</td>
                          <td class="py-2 pr-4 font-mono text-xs">
                            {Enum.join(dup["locations"] || [], ", ")}
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            <% end %>

            <%= if @audit_mode == "tools" do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                Tool schemas ({@audit_result["tool_count"]} tools · {@audit_result["total_tokens"]} tokens)
              </p>
              <div class="overflow-x-auto mb-6">
                <table class="min-w-full text-sm" id="audit-tools-table">
                  <thead>
                    <tr class="text-foreground">
                      <.audit_th table="tools" key="name" sort={@audit_sort} label="Tool" />
                      <.audit_th table="tools" key="char_count" sort={@audit_sort} label="Chars" />
                      <.audit_th
                        table="tools"
                        key="estimated_tokens"
                        sort={@audit_sort}
                        label="Tokens"
                      />
                    </tr>
                  </thead>
                  <tbody>
                    <%= for tool <- audit_sorted(@audit_result["tools"], "tools", @audit_sort) do %>
                      <tr>
                        <td class="py-2 pr-4 font-mono text-xs">{tool["name"]}</td>
                        <td class="py-2 pr-4">{tool["char_count"]}</td>
                        <td class="py-2 pr-4">{tool["estimated_tokens"]}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                Group savings
              </p>
              <div class="overflow-x-auto mb-2">
                <table class="min-w-full text-sm" id="audit-groups-table">
                  <thead>
                    <tr class="text-foreground">
                      <th class="text-left py-2 pr-4">Groups</th>
                      <th class="text-left py-2 pr-4">Tools</th>
                      <th class="text-left py-2 pr-4">Group tokens</th>
                      <th class="text-left py-2 pr-4">Savings</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for {name, group} <- audit_group_savings(@audit_result) do %>
                      <tr>
                        <td class="py-2 pr-4">
                          <span class="font-mono text-xs">
                            CK_TOOL_GROUPS={Enum.join(group["groups"], ",")}
                          </span>
                          <span class="text-muted-foreground text-xs">({name})</span>
                        </td>
                        <td class="py-2 pr-4">{group["tool_count"]}</td>
                        <td class="py-2 pr-4">{group["group_tokens"]}</td>
                        <td class="py-2 pr-4 text-[#d2ffe7]">
                          {group["savings_tokens"]} tokens ({group["savings_percent"]}%)
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>

            <%= if audit_recommendations(@audit_result) != [] do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                Recommendations
              </p>
              <ul class="text-muted-foreground text-sm list-disc px-4 grid gap-1">
                <%= for recommendation <- audit_recommendations(@audit_result) do %>
                  <li>{recommendation}</li>
                <% end %>
              </ul>
            <% end %>
          <% end %>
        </div>

        <%= if @selected do %>
          <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
              {@selected.name}
            </p>
            <p class="text-muted-foreground mb-3">{@selected.description}</p>
            <div class="flex flex-wrap gap-2 mb-3">
              <%= for target <- @selected.compatibility_targets do %>
                <span class="border bg-[rgba(255,255,255,0.05)] rounded-full px-3 py-[0.45rem] text-[0.8rem]">
                  {target}
                </span>
              <% end %>
            </div>
            <p class="text-muted-foreground mb-2">
              Required CK MCP tools: {format_targets(@selected.required_mcp_tools)}
            </p>
            <details class="mb-2">
              <summary class="cursor-pointer text-muted-foreground select-none">
                Locations ({length(selected_native_locations(@selected))})
              </summary>
              <ul class="grid gap-1 mt-2 pl-1 list-none">
                <%= for location <- selected_native_locations(@selected) do %>
                  <li class="flex gap-2 items-baseline">
                    <span class="text-[#d2ffe7] text-xs">✓</span>
                    <span class="text-muted-foreground font-mono text-xs break-all">{location}</span>
                  </li>
                <% end %>
                <li
                  :if={selected_native_locations(@selected) == []}
                  class="text-muted-foreground text-xs"
                >
                  not installed
                </li>
              </ul>
            </details>
            <p class="text-muted-foreground mb-2">
              Exported targets: {format_targets(get_in(@selected.install_state, ["exported_targets"]))}
            </p>
            <%= if selected_export_manifests(@selected, @export_manifests) != [] do %>
              <details class="mb-2">
                <summary class="cursor-pointer text-muted-foreground select-none">
                  Export manifests ({length(selected_export_manifests(@selected, @export_manifests))})
                </summary>
                <div class="grid gap-3 mt-2">
                  <%= for %{manifest: manifest} <- selected_export_manifests(@selected, @export_manifests) do %>
                    <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-3 bg-[rgba(255,255,255,0.03)]">
                      <p class="font-semibold text-sm">{manifest["target"]} ({manifest["scope"]})</p>
                      <p class="text-muted-foreground text-xs mt-1">Writes:</p>
                      <ul class="grid gap-[0.15rem] mt-1">
                        <%= for write <- manifest["writes"] || [] do %>
                          <li class="text-muted-foreground font-mono text-xs break-all">
                            [{write["kind"]}] {write["path"]}
                          </li>
                        <% end %>
                      </ul>
                      <%= if manifest["instructions"] not in [nil, []] do %>
                        <p class="text-muted-foreground text-xs mt-2">Instructions:</p>
                        <ul class="grid gap-[0.15rem] mt-1">
                          <%= for instruction <- manifest["instructions"] do %>
                            <li class="text-muted-foreground text-xs break-all">{instruction}</li>
                          <% end %>
                        </ul>
                      <% end %>
                    </article>
                  <% end %>
                </div>
              </details>
            <% end %>
            <%= if @selected.resources != [] do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mt-4">
                Resources
              </p>
              <ul class="grid gap-4 m-0 p-0 list-none">
                <%= for resource <- @selected.resources do %>
                  <li>{resource}</li>
                <% end %>
              </ul>
            <% end %>
            <%= if @selected.diagnostics != [] do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mt-4">
                Skill diagnostics
              </p>
              <ul class="grid gap-4 m-0 p-0 list-none">
                <%= for diagnostic <- @selected.diagnostics do %>
                  <li>[{diagnostic.level}] {diagnostic.code} — {diagnostic.message}</li>
                <% end %>
              </ul>
            <% end %>
            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mt-4">
              Instructions preview
            </p>
            <pre class="text-[0.72rem] leading-[1.5] whitespace-pre-wrap break-words max-h-[420px] overflow-y-auto mt-2">{@selected.body}</pre>
          </div>
        <% end %>

        <div class="space-y-4">
          <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-lg font-semibold text-primary tracking-[0.14em] uppercase">
              Available skills
            </p>

            <form phx-change="search_skills">
              <input
                type="text"
                name="skill_search"
                value={@skill_search}
                placeholder="Filter skills by name or description..."
                phx-debounce="150"
                class="mt-3 mb-4 p-3 w-full border border-input bg-background rounded-xl outline-none focus:border-primary transition-colors duration-150"
              />
            </form>

            <div
              id="skills-list"
              class="grid gap-4 m-0 p-0 list-none overflow-y-auto max-h-[500px] pr-2"
              style="scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent;"
            >
              <%= for skill <- @filtered_skills do %>
                <article
                  id={"skill-#{skill.name}"}
                  class={[
                    "border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.55rem] cursor-pointer",
                    @selected && @selected.name == skill.name && "border-primary"
                  ]}
                  phx-click="select_skill"
                  phx-value-name={skill.name}
                >
                  <div class="flex items-center justify-between gap-4">
                    <h3>{skill.name}</h3>
                    <span class={"border rounded-full px-3 py-[0.45rem] text-[0.8rem] #{scope_pill_class(skill.scope)}"}>
                      {skill.scope}
                    </span>
                  </div>
                  <p class="text-muted-foreground">{skill.description}</p>
                  <p class="text-muted-foreground mt-[0.35rem]">
                    Targets: {format_targets(skill.compatibility_targets)}
                  </p>
                </article>
              <% end %>
            </div>
            <style>
              #skills-list::-webkit-scrollbar { width: 6px; }
              #skills-list::-webkit-scrollbar-track { background: transparent; }
              #skills-list::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
              #skills-list::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }
            </style>
          </div>
        </div>

        <div class="border  rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="text-lg font-semibold text-primary tracking-[0.14em] uppercase">
            Target availability
          </p>

          <form phx-change="search_targets">
            <input
              type="text"
              name="target_search"
              value={@target_search}
              placeholder="Filter targets by name or description..."
              phx-debounce="150"
              class="mt-3 mb-4 p-3 w-full border border-input bg-background rounded-xl outline-none focus:border-primary transition-colors duration-150"
            />
          </form>

          <div
            id="targets-list"
            class="overflow-y-auto max-h-[500px] pr-2"
            style="scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent;"
          >
            <table class="min-w-full text-sm" id="skills-target-matrix">
              <thead>
                <tr class="sticky top-0 bg-card text-foreground">
                  <th class="text-left py-2 pr-4">Target</th>
                  <th class="text-left py-2 pr-4">Default scope</th>
                  <th class="text-left py-2 pr-4">Native</th>
                  <th class="text-left py-2 pr-4">Bundle</th>
                  <th class="text-left py-2 pr-4">Release asset</th>
                </tr>
              </thead>
              <tbody>
                <%= for target <- @filtered_targets do %>
                  <tr id={"skill-target-#{target.id}"}>
                    <td class="py-2 pr-4">
                      <strong>{target.label}</strong>
                      <p class="text-muted-foreground">{target.description}</p>
                    </td>
                    <td class="py-2 pr-4">{target.default_scope}</td>
                    <td class="py-2 pr-4">{if target.native, do: "yes", else: "fallback"}</td>
                    <td class="py-2 pr-4">
                      <span class={"border rounded-full px-3 py-[0.45rem] text-[0.8rem] #{bundle_pill_class(target.id)}"}>
                        {bundle_type(target.id)}
                      </span>
                    </td>
                    <td class="py-2 pr-4">
                      {if target.release_bundle, do: "published", else: "local only"}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          <style>
            #targets-list::-webkit-scrollbar { width: 6px; }
            #targets-list::-webkit-scrollbar-track { background: transparent; }
            #targets-list::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
            #targets-list::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }
          </style>
        </div>

        <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="text-lg font-semibold text-primary tracking-[0.14em] uppercase mb-2">
            Skill diagnostics
          </p>
          <div class="flex flex-wrap gap-2 mb-4">
            <span class="border rounded-full px-3 py-[0.45rem] text-xs bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              valid? {if @valid?, do: "✓ yes", else: "✗ no"} · {@total_skills} total · {@warning_count} warnings · {@error_count} errors
            </span>
            <span class="border rounded-full px-3 py-[0.45rem] text-xs bg-[rgba(255,207,107,0.12)] text-[#fff0bf]">
              shadowed_skill: {@shadowed_count}
            </span>
            <span class="border rounded-full px-3 py-[0.45rem] text-xs bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              duplicate_skill_copy: {@identical_count} identical
            </span>
            <span
              :if={@validated_at}
              class="border rounded-full px-3 py-[0.45rem] text-xs text-muted-foreground"
            >
              validated {Calendar.strftime(@validated_at, "%H:%M:%S UTC")}
            </span>
          </div>
          <div :if={@diagnostics == []} class="text-muted-foreground">
            No skill diagnostics were recorded.
          </div>
          <div
            :if={@diagnostics != []}
            class="grid gap-4 m-0 p-0 list-none overflow-y-auto max-h-[720px] pr-2"
            style="scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent;"
          >
            <%= for diagnostic <- @diagnostics do %>
              <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.55rem]">
                <div class="flex items-center justify-between gap-4">
                  <h3>{diagnostic.code}</h3>
                  <span class={"border rounded-full px-3 py-[0.45rem] text-xs #{diagnostic_pill_class(diagnostic.level)}"}>
                    {diagnostic.level}
                  </span>
                </div>
                <p class="text-muted-foreground text-xs">{diagnostic.message}</p>
                <p class="text-muted-foreground font-mono text-xs">
                  {diagnostic.path}
                </p>
              </article>
            <% end %>
          </div>
        </div>
      </div>

      <div :if={@prune_preview} id="prune-duplicates-modal" class="relative z-50">
        <div
          class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
          phx-click="cancel_prune"
          aria-label="Close modal"
        />

        <div class="fixed inset-0 flex items-center justify-center p-4">
          <div class="w-full max-w-lg rounded-2xl border bg-card/95 p-6 shadow-card max-h-[80vh] overflow-y-auto">
            <h2 class="text-lg font-semibold text-foreground mb-1">Prune user-level duplicates</h2>
            <p class="text-sm text-muted-foreground mb-4">
              Only identical copies under your home directory are removed automatically.
              Shadowed copies with differing content are never removed.
            </p>

            <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
              Will be removed ({@prune_preview.user_level_count})
            </p>
            <ul class="grid gap-1 mb-4">
              <li
                :for={dir <- @prune_preview.user_level}
                class="text-xs font-mono text-[#ffd6cb] break-all"
              >
                {dir}
              </li>
            </ul>

            <%= if @prune_preview.project_groups != [] do %>
              <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase mb-2">
                Kept (project host-specific)
              </p>
              <ul class="grid gap-1 mb-2">
                <li
                  :for={group <- @prune_preview.project_groups}
                  class="text-xs text-muted-foreground"
                >
                  {group.host_dir}/skills/: {Enum.join(group.skills, ", ")}
                </li>
              </ul>
              <p class="text-xs text-muted-foreground mb-4">
                Keep your primary host + .agents/skills/.
              </p>
            <% end %>

            <div class="flex justify-end gap-3 mt-2">
              <button
                type="button"
                phx-click="cancel_prune"
                class="rounded-full border bg-transparent px-5 py-2 text-sm font-semibold transition hover:bg-card cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                id="skills-prune-confirm"
                phx-click="confirm_prune"
                class="rounded-full bg-primary px-5 py-2 text-sm font-bold text-[#11170d] transition hover:-translate-y-px cursor-pointer"
              >
                Remove {@prune_preview.user_level_count} user-level copies
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp assign_analysis(socket, project_root) do
    validation = Skills.validate(project_root, report_identical_duplicates: true)

    socket
    |> assign(:project_root, project_root)
    |> assign(:skills, validation.skills)
    |> assign(:filtered_skills, validation.skills)
    |> assign(:diagnostics, validation.diagnostics)
    |> assign(:targets, Skills.targets())
    |> assign(:filtered_targets, Skills.targets())
    |> assign(:trusted_project?, validation.trusted_project?)
    |> assign(:valid?, validation.valid?)
    |> assign(:total_skills, validation.total)
    |> assign(:warning_count, validation.warning_count)
    |> assign(:error_count, validation.error_count)
    |> assign(:validated_at, DateTime.utc_now())
    |> assign(:skill_search, "")
    |> assign(:target_search, "")
  end

  defp assign_doctor(socket, project_root) do
    integrations = Skills.agent_integrations()
    provider_status = ProviderBroker.status(project_root)

    attachable_clients =
      integrations
      |> Enum.filter(&(&1.support_class == "attach_client"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    headless_runtimes =
      integrations
      |> Enum.filter(&(&1.support_class == "headless_runtime"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    duplicate_copy_count =
      Enum.count(socket.assigns.diagnostics, &(&1.code == "duplicate_skill_copy"))

    identical_count = duplicate_copy_count

    shadowed_count =
      Enum.count(socket.assigns.diagnostics, &(&1.code == "shadowed_skill"))

    socket
    |> assign(:provider_status, provider_status)
    |> assign(:bootstrap_mode, provider_status["bootstrap"]["mode"])
    |> assign(:attachable_clients, attachable_clients)
    |> assign(:headless_runtimes, headless_runtimes)
    |> assign(:duplicate_copy_count, duplicate_copy_count)
    |> assign(:identical_count, identical_count)
    |> assign(:shadowed_count, shadowed_count)
    |> assign(:export_manifests, Skills.export_manifests(project_root))
  end

  defp project_form(project_root), do: to_form(%{"project_root" => project_root}, as: :project)

  defp action_form(params \\ %{"target" => "open-standard", "scope" => "export"}) do
    params = normalize_action_params(params)
    to_form(params, as: :skill_action)
  end

  defp normalize_action_params(%{"target" => target} = params) when is_binary(target) do
    case SkillTarget.get(target) do
      %SkillTarget{supported_scopes: supported, default_scope: default} ->
        scope = if params["scope"] in supported, do: params["scope"], else: default
        Map.put(params, "scope", scope)

      nil ->
        params
    end
  end

  defp normalize_action_params(params), do: params

  defp scope_options(target_id) do
    case SkillTarget.get(target_id) do
      %SkillTarget{supported_scopes: supported} ->
        Enum.map(@all_scopes, fn scope ->
          label = Map.get(@scope_labels, scope, scope)

          if scope in supported do
            {label, scope}
          else
            [key: "#{label} (unsupported)", value: scope, disabled: true]
          end
        end)

      nil ->
        Enum.map(@all_scopes, &{Map.get(@scope_labels, &1, &1), &1})
    end
  end

  defp target_options do
    Enum.map(Skills.targets(), fn target ->
      {target.label <> bundle_type_suffix(target.id), target.id}
    end)
  end

  defp bundle_type_suffix(target_id) do
    if String.ends_with?(target_id, "-plugin"),
      do: " · Marketplace bundle",
      else: " · Skills bundle"
  end

  defp bundle_type(target_id) do
    if String.ends_with?(target_id, "-plugin"), do: "Marketplace", else: "Skills"
  end

  defp bundle_pill_class(target_id) do
    if String.ends_with?(target_id, "-plugin"),
      do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]",
      else: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  end

  defp selected_native_locations(selected),
    do: get_in(selected.install_state, ["native_locations"]) || []

  defp selected_export_manifests(selected, manifests) do
    exported = get_in(selected.install_state, ["exported_targets"]) || []
    Enum.filter(manifests, &(&1.manifest["target"] in exported))
  end

  defp format_targets([]), do: "none"
  defp format_targets(nil), do: "none"
  defp format_targets(values), do: Enum.join(values, ", ")

  defp scope_pill_class("builtin"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp scope_pill_class("user"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp scope_pill_class("project"), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  defp scope_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp diagnostic_pill_class("error"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp diagnostic_pill_class("warn"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp diagnostic_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp duplicate_token_warning(count) do
    "Found #{count} duplicate skill #{pluralize("copy", count)} wasting tokens. Run `controlkeel token audit --mode skills` for optimization guidance."
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"

  attr :table, :string, required: true
  attr :key, :string, required: true
  attr :sort, :map, required: true
  attr :label, :string, required: true
  attr :id, :string, default: nil

  defp audit_th(assigns) do
    ~H"""
    <th
      class="text-left py-2 pr-4 cursor-pointer select-none hover:text-primary transition-colors"
      id={@id}
      phx-click="sort_audit"
      phx-value-table={@table}
      phx-value-key={@key}
    >
      {@label}{audit_sort_indicator(@sort, @table, @key)}
    </th>
    """
  end

  defp audit_sorted(rows, table, sort_state, default_key \\ "estimated_tokens") do
    {key, dir} = Map.get(sort_state, table, {default_key, :desc})
    Enum.sort_by(rows || [], &audit_sort_value(&1, key), dir)
  end

  defp audit_sort_value(row, key) do
    case Map.get(row, key) do
      value when is_number(value) -> {0, value}
      value when is_binary(value) -> {1, String.downcase(value)}
      _ -> {2, ""}
    end
  end

  defp audit_sort_indicator(sort_state, table, key) do
    case Map.get(sort_state, table) do
      {^key, :desc} -> " ↓"
      {^key, :asc} -> " ↑"
      _ -> ""
    end
  end

  defp audit_skill_rows(result),
    do: result["effective_skills"] || result["skills"] || []

  defp audit_duplicates(result),
    do: result["skill_duplicates"] || result["duplicates"] || []

  defp audit_recommendations(result),
    do: List.wrap(result["recommendations"]) ++ List.wrap(result["skill_recommendations"])

  defp audit_group_savings(result) do
    result["group_savings"]
    |> Kernel.||(%{})
    |> Enum.sort_by(fn {_name, group} -> -group["savings_tokens"] end)
  end

  defp audit_summary_chips(mode, result) do
    case mode do
      "rules" ->
        [
          "status: #{result["status"]}",
          "#{result["total_words"]} words",
          "#{result["estimated_tokens"]} tokens"
        ]

      "skills" ->
        [
          "#{result["installed_skill_copies"]} copies → #{result["effective_skill_count"]} effective",
          "#{result["total_skill_tokens"]} skill tokens",
          "#{result["duplicate_token_count"]} wasted tokens"
        ]

      "tools" ->
        [
          "#{result["tool_count"]} tools",
          "#{result["total_tokens"]} tokens",
          "avg #{result["avg_tokens_per_tool"]}/tool"
        ]

      _ ->
        [
          "#{result["estimated_tokens"]} total tokens",
          "#{result["rule_tokens"]} rule tokens",
          "#{result["total_skill_tokens"]} skill tokens",
          "#{result["duplicate_token_count"]} wasted tokens"
        ]
    end
  end
end
