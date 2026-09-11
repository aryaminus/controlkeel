defmodule ControlKeelWeb.LayoutDefaults do
  @moduledoc """
  Provides shared assigns consumed by framework layouts.

  - `@current_path` — the LiveView's request URI path, read by the sidebar
    and breadcrumb to highlight the active nav link.
  - `@page_action` — defaults to `nil`; a LiveView overrides it with a
    primary action that the header renders. Supports:
    - `%{label: ..., to: ..., icon: ...}` — a navigation link
    - `%{label: ..., event: ..., icon: ...}` — a `phx-click` button
    - `%{label: ..., form: ..., icon: ...}` — a `type="submit"` button that
      submits the form with the given DOM id (e.g. `"benchmark-runner"`)
  - `@breadcrumbs` — defaults to `nil`; a LiveView overrides it with explicit
    breadcrumb crumbs (`%{label: ..., to: ...}` where `to: nil` renders plain
    text) when the path-derived trail would show opaque ids or dead segments.

  Attached as an `on_mount` hook on the live_sessions whose layout needs these,
  so individual LiveViews don't have to set them manually.
  """

  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(_arg, params, _session, socket) do
    session_id = params["id"] || params["sid"]

    socket =
      socket
      |> assign(:current_path, nil)
      |> assign_new(:page_action, fn -> nil end)
      |> assign_new(:breadcrumbs, fn -> nil end)
      |> assign_new(:session_id, fn -> session_id end)
      |> assign_new(:session_title, fn -> nil end)
      |> assign_new(:session_risk, fn -> nil end)
      |> attach_hook(:__current_path__, :handle_params, fn _params, uri, socket ->
        {:cont, assign(socket, :current_path, URI.parse(uri).path)}
      end)

    {:cont, socket}
  end
end
