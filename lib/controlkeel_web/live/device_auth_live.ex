defmodule ControlKeelWeb.DeviceAuthLive do
  @moduledoc """
  Browser approval page for the RFC 8628 device flow (issue #251).

  The user opens `verification_uri`, signs in (auth-gated), enters the short
  `user_code` shown by their CLI, and approves or denies the device. Per RFC
  8628 §5.4 the page must make clear that authorizing a *device* grants it
  access to their account, and per §5.1 the user code is rate-limited.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts.DeviceAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Authorize device",
       form: to_form(%{"user_code" => ""}, as: :device)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Allow deep-linking straight to /device?user_code=...
    {:noreply,
     assign(socket, form: to_form(%{"user_code" => params["user_code"] || ""}, as: :device))}
  end

  @impl true
  def handle_event("lookup", %{"device" => %{"user_code" => code}}, socket) do
    case DeviceAuth.fetch_by_user_code(code) do
      {:ok, authorization} ->
        {:noreply, assign(socket, :pending, authorization)}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many attempts. Wait a moment and try again.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That code is invalid or has expired.")}
    end
  end

  def handle_event("approve", _params, socket) do
    case socket.assigns[:pending] do
      nil ->
        {:noreply, put_flash(socket, :error, "Look up a code first.")}

      authorization ->
        case DeviceAuth.approve(authorization, socket.assigns.current_user.id) do
          {:ok, _} ->
            {:noreply,
             assign(socket, :pending, nil)
             |> put_flash(:info, "Device authorized. Return to your terminal.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "That device request is no longer valid.")}
        end
    end
  end

  def handle_event("deny", _params, socket) do
    case socket.assigns[:pending] do
      nil ->
        {:noreply, put_flash(socket, :error, "Look up a code first.")}

      authorization ->
        case DeviceAuth.deny(authorization, socket.assigns.current_user.id) do
          {:ok, _} ->
            {:noreply, assign(socket, :pending, nil) |> put_flash(:info, "Device denied.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "That device request is no longer valid.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md py-16">
      <h1 class="text-2xl font-semibold">Authorize a device</h1>
      <p class="mt-2 text-sm text-muted-foreground">
        Your terminal is waiting to sign in. Enter the code it showed you.
        <strong>Only approve a device you started yourself.</strong>
      </p>

      <div :if={is_nil(@pending)} class="mt-6">
        <.form for={@form} phx-submit="lookup">
          <.input field={@form[:user_code]} label="Device code" autocomplete="off" />
          <button type="submit" class="mt-3 rounded bg-primary px-4 py-2 text-primary-foreground">
            Continue
          </button>
        </.form>
      </div>

      <div :if={@pending} class="mt-6 rounded-lg border border-border p-4">
        <p class="text-sm">
          Authorize <span class="font-semibold">{@pending.client_name || "a ControlKeel CLI"}</span>
          to access your account?
        </p>
        <div class="mt-4 flex gap-2">
          <button
            type="button"
            phx-click="approve"
            class="rounded bg-primary px-4 py-2 text-primary-foreground"
          >
            Allow
          </button>
          <button type="button" phx-click="deny" class="rounded border border-border px-4 py-2">
            Deny
          </button>
        </div>
      </div>
    </div>
    """
  end
end
