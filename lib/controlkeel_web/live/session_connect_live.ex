defmodule ControlKeelWeb.SessionConnectLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Proxy

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(session) ->
        cond do
          not ControlKeel.Accounts.session_accessible?(session, current_user) ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          check_session_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()
            {:ok, assign_session(socket, session)}
        end
    end
  end

  defp check_session_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
    end
  end

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(workspace.id))
    |> assign(:breadcrumbs, [
      %{label: org.name, to: "/#{org.slug}"},
      %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
      %{
        label: session.title,
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
      },
      %{label: "Connect", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Connect")
    |> assign(:session, session)
    |> assign(:endpoints, session_endpoints(session))
  end

  defp session_endpoints(session) do
    urls = Proxy.endpoint_urls(session)

    [
      {"OpenAI",
       [
         {"Responses", urls.openai_responses},
         {"Chat", urls.openai_chat},
         {"Completions", urls.openai_completions},
         {"Embeddings", urls.openai_embeddings},
         {"Models", urls.openai_models},
         {"Realtime", urls.openai_realtime}
       ]},
      {"Anthropic",
       [
         {"Messages", urls.anthropic_messages}
       ]},
      {"Gemini",
       [
         {"Chat", urls.gemini_chat},
         {"Models", urls.gemini_models}
       ]}
    ]
  end

  @impl true
  def handle_event("copy_endpoint", %{"url" => url}, socket) when is_binary(url) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: url})
     |> put_flash(:info, "Endpoint copied to the clipboard.")}
  end

  def handle_event("copy_endpoint", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> {:noreply, socket}
      session -> {:noreply, assign_session(socket, session)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title
        title="Connect"
        subtitle="Copy a session-scoped endpoint into any OpenAI-compatible client. Paste one as the base URL and the client runs through this session's governance: policy checks, budget metering, and a full audit trail. Treat these URLs like passwords — the token in each one grants access to this session."
      />

      <%= for {provider, items} <- @endpoints do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            {provider}
          </p>
          <ul class="mt-3 divide-y divide-border border-y list-none p-0 m-0">
            <%= for {label, href} <- items do %>
              <li>
                <button
                  type="button"
                  phx-click="copy_endpoint"
                  phx-value-url={href}
                  aria-label={"Copy #{provider} #{label} endpoint"}
                  class="flex w-full cursor-pointer items-center justify-between gap-3 px-4 py-3 text-left transition hover:bg-muted/30"
                >
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-foreground">{label}</span>
                    <span class="block truncate font-mono text-xs text-muted-foreground">
                      {href}
                    </span>
                  </span>
                  <.icon name="hero-clipboard" class="size-4 shrink-0 text-muted-foreground" />
                </button>
              </li>
            <% end %>
          </ul>
        </section>
      <% end %>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)
end
