defmodule ControlKeelWeb.CommandPill do
  use Phoenix.Component

  import ControlKeelWeb.CoreComponents, only: [icon: 1]

  attr :command, :string, required: true

  def command_pill(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 text-muted-foreground text-xs font-mono border rounded-lg px-3 py-2 bg-[rgba(255,255,255,0.015)]">
      <span>{@command}</span>
      <button
        type="button"
        phx-click="copy_command"
        phx-value-command={@command}
        class="cursor-pointer hover:text-primary transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
        aria-label="Copy command"
        title="Copy command"
      >
        <.icon name="hero-clipboard" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  @doc """
  LiveView lifecycle hook that handles the `copy_command` event without
  injecting `handle_event/3` clauses into the host module.

  Mount with:

      on_mount ControlKeelWeb.CommandPill
  """
  def on_mount(:default, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :copy_command, :handle_event, fn
       "copy_command", %{"command" => command}, socket ->
         {:halt,
          socket
          |> Phoenix.LiveView.push_event("copy-to-clipboard", %{text: command})
          |> Phoenix.LiveView.put_flash(:info, "Copied command to clipboard.")}

       _event, _params, socket ->
         {:cont, socket}
     end)}
  end
end
