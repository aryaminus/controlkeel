defmodule ControlKeelWeb.DeployReviewLive do
  @moduledoc """
  Deploy review for a session's project: stack analysis, hosting cost
  estimates, deployment file preview and confirmed write, and per-stack
  guides. Routed at `/sessions/:id/deploy-review`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Ops.DeploymentAdvisor
  alias ControlKeel.Ops.HostingCost
  alias ControlKeel.Project.WorkspaceContext
  alias ControlKeelWeb.DeploymentComponents

  @tabs ~w(overview costs files guides)

  @tier_order ~w(free hobby standard_1x standard_2x performance dedicated)a
  @db_tier_order ~w(none shared_small managed_small managed_medium managed_large managed_xl)a

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if Accounts.session_accessible?(session, org_id) do
          {:ok, mount_session(socket, session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        {:ok, mount_session(socket, session)}
    end
  end

  defp mount_session(socket, session) do
    server_root = socket.endpoint.config(:project_root) || File.cwd!()
    resolved_root = WorkspaceContext.resolve_project_root(session, server_root)

    {analysis, unavailable} =
      case resolved_root && DeploymentAdvisor.analyze(resolved_root) do
        {:ok, analysis} -> {analysis, false}
        _ -> {nil, true}
      end

    socket
    |> assign(:page_title, "#{session.title} — Deploy review")
    |> assign(:session, session)
    |> assign(:project_root, resolved_root)
    |> assign(:analysis, analysis)
    |> assign(:unavailable, unavailable)
    |> assign(:tab, "overview")
    |> assign(:tier_options, tier_options())
    |> assign(:db_tier_options, db_tier_options())
    |> assign(:selected_tier, "free")
    |> assign(:selected_db_tier, "managed_small")
    |> assign(:needs_db, true)
    |> assign(:bandwidth_gb, 10)
    |> assign(:storage_gb, 1)
    |> assign(:cost_estimates, nil)
    |> assign(:generated_files, nil)
    |> assign(:generate_mode, nil)
    |> assign(:confirm_write, false)
    |> assign(:write_results, nil)
    |> assign(:guides, nil)
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) when tab in @tabs do
    socket =
      if tab == "guides" and is_nil(socket.assigns.guides) and socket.assigns.analysis do
        assign(socket, :guides, load_guides(socket.assigns.analysis.stack))
      else
        socket
      end

    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("select_tier", %{"tier" => tier}, socket) do
    if known_tier?(HostingCost.available_tiers(), tier) do
      {:noreply, assign(socket, :selected_tier, tier)}
    else
      {:noreply, put_flash(socket, :error, "Unknown compute tier.")}
    end
  end

  @impl true
  def handle_event("select_db_tier", %{"db_tier" => db_tier}, socket) do
    if known_tier?(HostingCost.available_database_tiers(), db_tier) do
      {:noreply, assign(socket, :selected_db_tier, db_tier)}
    else
      {:noreply, put_flash(socket, :error, "Unknown database tier.")}
    end
  end

  @impl true
  def handle_event("toggle_db", _params, socket) do
    {:noreply, assign(socket, :needs_db, not socket.assigns.needs_db)}
  end

  @impl true
  def handle_event("set_bandwidth", %{"value" => value}, socket) do
    {:noreply, assign(socket, :bandwidth_gb, parse_non_negative_int(value, 10))}
  end

  @impl true
  def handle_event("set_storage", %{"value" => value}, socket) do
    {:noreply, assign(socket, :storage_gb, parse_non_negative_int(value, 1))}
  end

  @impl true
  def handle_event("estimate_costs", _params, %{assigns: %{analysis: nil}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("estimate_costs", _params, socket) do
    {:ok, estimates} =
      HostingCost.estimate(
        stack: socket.assigns.analysis.stack,
        tier: String.to_existing_atom(socket.assigns.selected_tier),
        needs_db: socket.assigns.needs_db,
        db_tier: String.to_existing_atom(socket.assigns.selected_db_tier),
        expected_bandwidth_gb: socket.assigns.bandwidth_gb,
        expected_storage_gb: socket.assigns.storage_gb
      )

    {:noreply, assign(socket, :cost_estimates, estimates)}
  end

  @impl true
  def handle_event("preview_files", _params, %{assigns: %{analysis: nil}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("preview_files", _params, socket) do
    {:ok, results} = generate(socket, dry_run: true)

    {:noreply,
     socket
     |> assign(:generated_files, results)
     |> assign(:generate_mode, :preview)
     |> assign(:confirm_write, false)}
  end

  @impl true
  def handle_event("arm_write", _params, %{assigns: %{generated_files: files}} = socket)
      when is_list(files) and files != [] do
    {:noreply, assign(socket, :confirm_write, true)}
  end

  @impl true
  def handle_event("arm_write", _params, socket) do
    {:noreply, put_flash(socket, :info, "Preview the files first, then write them.")}
  end

  @impl true
  def handle_event("cancel_write", _params, socket) do
    {:noreply, assign(socket, :confirm_write, false)}
  end

  @impl true
  def handle_event("confirm_write_files", _params, socket) do
    {:ok, results} = generate(socket, dry_run: false)

    written = Enum.count(results, &match?({:ok, _name, _path, _content, :written}, &1))
    skipped = Enum.count(results, &match?({:ok, _name, _path, _content, :skipped}, &1))
    failed = Enum.count(results, &match?({:error, _name, _path, _reason}, &1))

    message =
      if failed > 0 do
        "Wrote #{written}, skipped #{skipped}, failed #{failed}. Review the failed files below."
      else
        "Wrote #{written} file#{if written != 1, do: "s"}; skipped #{skipped} (already existed)."
      end

    {:noreply,
     socket
     |> assign(:write_results, results)
     |> assign(:generated_files, results)
     |> assign(:generate_mode, :write)
     |> assign(:confirm_write, false)
     |> put_flash(if(failed > 0, do: :error, else: :info), message)}
  end

  @impl true
  def handle_event("copy_generated_file", %{"name" => name}, socket) do
    source = socket.assigns.generated_files || []

    case Enum.find(source, fn
           {:ok, n, _p, _c, _s} -> n == name
           _ -> false
         end) do
      {:ok, ^name, _path, content, _status} when is_binary(content) ->
        {:noreply,
         socket
         |> push_event("copy-to-clipboard", %{text: content})
         |> put_flash(:info, "#{name} copied to the clipboard.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not copy that file.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <.page_title
        title="Deploy review"
        subtitle={"Project deploy review for #{@session.title}."}
      />

      <DeploymentComponents.unavailable_notice :if={@unavailable} />

      <%= if not @unavailable do %>
        <div class="flex flex-wrap items-center gap-2">
          <DeploymentComponents.tab_link
            :for={t <- ["overview", "costs", "files", "guides"]}
            tab={@tab}
            name={t}
          />
        </div>

        <div :if={@tab == "overview"}>
          <DeploymentComponents.overview_panel analysis={@analysis} />
        </div>

        <div :if={@tab == "costs"}>
          <DeploymentComponents.costs_panel
            analysis={@analysis}
            tiers={@tier_options}
            db_tiers={@db_tier_options}
            selected_tier={@selected_tier}
            selected_db_tier={@selected_db_tier}
            needs_db={@needs_db}
            bandwidth_gb={@bandwidth_gb}
            storage_gb={@storage_gb}
            cost_estimates={@cost_estimates}
          />
        </div>

        <div :if={@tab == "files"}>
          <DeploymentComponents.files_panel
            analysis={@analysis}
            generated_files={@generated_files}
            generate_mode={@generate_mode}
            confirm_write={@confirm_write}
          />
        </div>

        <div :if={@tab == "guides"}>
          <DeploymentComponents.guides_panel guides={@guides} />
        </div>
      <% end %>
    </div>
    """
  end

  defp generate(socket, opts) do
    DeploymentAdvisor.generate_files(
      socket.assigns.project_root,
      socket.assigns.analysis.generators,
      opts
    )
  end

  defp tier_options do
    tiers = HostingCost.available_tiers()

    for key <- @tier_order, tier = tiers[key] do
      {to_string(key), "#{tier.label} · #{tier.cpu} CPU / #{tier.memory_gb} GB"}
    end
  end

  defp db_tier_options do
    tiers = HostingCost.available_database_tiers()

    for key <- @db_tier_order, tier = tiers[key] do
      {to_string(key), "#{tier.label} (#{format_monthly(tier.monthly_cents)})"}
    end
  end

  defp known_tier?(tiers, value) when is_map(tiers) and is_binary(value) do
    Enum.any?(Map.keys(tiers), &(to_string(&1) == value))
  end

  defp format_monthly(cents) when rem(cents, 100) == 0, do: "$#{div(cents, 100)}/mo"

  defp format_monthly(cents),
    do: :erlang.float_to_binary(cents / 100, decimals: 2) <> "/mo"

  defp load_guides(stack) do
    %{
      dns_ssl: DeploymentAdvisor.dns_ssl_guide(stack),
      migration: DeploymentAdvisor.db_migration_guide(stack),
      scaling: DeploymentAdvisor.scaling_guide(stack)
    }
  end

  defp parse_non_negative_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end

  defp parse_non_negative_int(_value, default), do: default
end
