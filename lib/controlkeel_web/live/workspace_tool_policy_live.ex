defmodule ControlKeelWeb.WorkspaceToolPolicyLive do
  @moduledoc """
  Per-workspace MCP tool policy at `/:org_slug/workspaces/:ws_slug/tool-policy`.

  Admin+owner can choose one of three modes:
    - `inherit` — fall back to global policy (the default)
    - `allowlist` — only tools in the list are allowed
    - `denylist` — listed tools are denied; everything else allowed

  Cross-org access is rejected at mount.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Tool policy", "admin") do
      {:ok, socket} ->
        workspace = socket.assigns.workspace
        policy = Accounts.get_workspace_tool_policy(workspace.id)
        tools = WorkspaceToolPolicy.decode_tools(policy)

        {:ok,
         socket
         |> assign(:page_title, "Tool policy — #{workspace.name}")
         |> assign(:policy, policy)
         |> assign(:modes, WorkspaceToolPolicy.modes())
         |> assign(
           :form,
           to_form(
             %{
               "mode" => policy.mode,
               "tools" => Enum.join(tools, "\n")
             },
             as: :policy
           )
         )
         |> assign(:saved, false)
         |> assign(:error, nil)}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_event("submit", %{"policy" => %{"mode" => mode, "tools" => raw}}, socket) do
    tools = parse_tools(raw)

    case Accounts.set_workspace_tool_policy(socket.assigns.workspace.id, mode, tools) do
      {:ok, policy} ->
        {:noreply,
         socket
         |> assign(:policy, policy)
         |> assign(:saved, true)
         |> assign(:error, nil)
         |> put_flash(:info, "Tool policy saved (#{policy.mode}).")}

      {:error, %Ecto.Changeset{} = cs} ->
        msg = Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, assign(socket, :error, msg) |> assign(:saved, false)}
    end
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  def render(assigns) do
    ~H"""
    <section
      class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-12 pb-16 max-[900px]:w-[min(100%-1.25rem,1180px)] max-[900px]:pt-6"
      style="max-width: 720px; margin: 4rem auto;"
    >
      <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
        <div>
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            {@workspace.name}
          </p>
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Tool policy</h1>
          <p class="text-muted-foreground text-[1.05rem] leading-[1.7] max-w-[48rem]">
            Restrict which MCP tools agents in this workspace may invoke. <code>inherit</code>
            falls back to the global allowlist; <code>allowlist</code>
            and <code>denylist</code>
            override it.
          </p>
        </div>
      </div>

      <.form
        for={@form}
        phx-submit="submit"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6 flex flex-col gap-4"
      >
        <div>
          <label class="block text-sm font-medium text-muted-foreground mb-1">Mode</label>
          <select
            name="policy[mode]"
            class="w-full rounded-lg border bg-card px-4 py-2 text-foreground"
          >
            <%= for m <- @modes do %>
              <option value={m} selected={@form[:mode].value == m}>{m}</option>
            <% end %>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-muted-foreground mb-1">
            Tool names (one per line)
          </label>
          <textarea
            name="policy[tools]"
            rows="8"
            placeholder="ck_validate&#10;ck_finding&#10;ck_context"
            class="w-full rounded-lg border bg-card px-4 py-2 text-foreground font-mono"
          >{@form[:tools].value || ""}</textarea>
          <p class="mt-1 text-xs text-muted-foreground">
            Used by <code>allowlist</code>
            and <code>denylist</code>
            modes. Ignored under <code>inherit</code>.
          </p>
        </div>

        <%= if @error do %>
          <p class="text-muted-foreground">{@error}</p>
        <% end %>

        <%= if @saved do %>
          <p class="text-muted-foreground">Saved.</p>
        <% end %>

        <button type="submit" class="self-start">Save policy</button>
      </.form>
    </section>
    """
  end

  # ── Private ────────────────────────────────────────────────────────

  defp parse_tools(raw) when is_binary(raw) do
    raw
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_tools(_), do: []
end
