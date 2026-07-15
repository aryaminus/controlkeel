defmodule ControlKeelWeb.CloudOnboardingLive do
  @moduledoc """
  First-run onboarding for a brand-new OAuth user with no org/membership.

  Creates a personal org + active owner membership, then hands off to
  `/auth/complete/:token` (the existing session-establishing flow) to set
  `current_org_id` and land on `/cloud/projects`.

  Reachable only by an authenticated user — no `current_user` redirects to
  `/auth/login`. Mounted under the `:load_if_available` hook so a signed-in
  user with no membership can reach it without looping (Gap 2.1).
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeelWeb.AuthController

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Set up your workspace",
        name: "",
        error: nil
      )

    if socket.assigns[:current_user] do
      {:ok, socket}
    else
      {:ok, push_navigate(socket, to: ~p"/auth/login")}
    end
  end

  @impl true
  def handle_event("save", %{"name" => raw_name}, socket) do
    name = raw_name |> to_string() |> String.trim()
    user = socket.assigns.current_user

    cond do
      name == "" ->
        {:noreply, assign(socket, :error, "Enter a name for your workspace.")}

      true ->
        case Accounts.create_org_with_owner(user, %{name: name, slug: slugify(name)}) do
          {:ok, {org, _membership}} ->
            token = AuthController.sign_completion_token(user.id, org.id)
            {:noreply, redirect(socket, to: ~p"/auth/complete/#{token}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :error, format_changeset_error(changeset))}
        end
    end
  end

  @impl true
  def handle_event("change", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name, error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="ck-shell" style="max-width: 480px; margin: 4rem auto;">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">ControlKeel Cloud</p>
          <h1 class="ck-section-title">Set up your workspace</h1>
          <p class="ck-lead ck-lead-tight">Name your personal organization to get started.</p>
        </div>
      </div>

      <.form
        for={%{}}
        id="onboarding-form"
        phx-submit="save"
        phx-change="change"
        class="mt-6 flex flex-col gap-4"
      >
        <div>
          <label class="block text-sm font-medium text-zinc-300 mb-1">Organization name</label>
          <input
            type="text"
            name="name"
            value={@name}
            placeholder="Acme"
            autocomplete="organization"
            class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-lime-300"
          />
          <%= if @error do %>
            <p class="mt-1 text-sm text-red-400">{@error}</p>
          <% end %>
        </div>

        <button
          type="submit"
          class="rounded-lg bg-lime-300 px-5 py-2.5 text-sm font-semibold text-zinc-950 hover:bg-lime-200 transition"
        >
          Create workspace
        </button>
      </.form>
    </section>
    """
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp format_changeset_error(changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)

    cond do
      msg = get_in(errors, [:slug]) ->
        List.first(msg)

      msg = get_in(errors, [:name]) ->
        List.first(msg)

      true ->
        "That name is taken. Try another."
    end
  end
end
