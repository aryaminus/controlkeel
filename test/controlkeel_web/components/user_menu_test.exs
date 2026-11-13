defmodule ControlKeelWeb.UserMenuTest do
  @moduledoc """
  Component tests for the shared user menu and its account dialog
  (identity info + data export + erasure; restricted variant for local
  mode's placeholder menu).
  """

  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.UserMenu

  describe "identity menu" do
    test "renders the trigger, popover entries, and the account dialog" do
      user = %{name: "Ada Lovelace", email: "ada@example.com"}

      html = render_component(&UserMenu.user_menu/1, id: "menu", current_user: user)

      assert html =~ "data-user-menu-trigger"
      assert html =~ "aria-label=\"User menu\""
      assert html =~ "Docs"
      assert html =~ "GitHub"
      assert html =~ "Account"
      # The dialog is a sibling of the popover, wired by the Account entry.
      assert html =~ ~s(id="menu-account-dialog")
      assert html =~ "menu-account-dialog"
    end

    test "account dialog renders Account (info + danger zone) and Data (export)" do
      user = %{name: "Ada Lovelace", email: "ada@example.com"}

      html = render_component(&UserMenu.user_menu/1, id: "menu", current_user: user)

      # Account tab: read-only identity info.
      assert html =~ "Signed in as"
      assert html =~ "ada@example.com"
      assert html =~ "Ada Lovelace"
      # Erasure danger zone lives inside the Account tab.
      assert html =~ "Deleting your account is permanent."
      assert html =~ ~s(action="/me/erase")
      assert html =~ "Delete my account"
      # Data tab: Art.15 export.
      assert html =~ "Download my data"
      assert html =~ ~s(href="/me/export.json")
    end

    test "sign out opt-in renders the sign out entry" do
      user = %{name: "Ada Lovelace", email: "ada@example.com"}

      with_sign_out =
        render_component(&UserMenu.user_menu/1, id: "menu", current_user: user, sign_out: true)

      without = render_component(&UserMenu.user_menu/1, id: "menu", current_user: user)

      assert with_sign_out =~ "Sign out"
      refute without =~ "Sign out"
    end
  end

  describe "account delete error flow" do
    test "the :account_delete flash opens the dialog with a dismissible in-section banner" do
      user = %{name: "Ada Lovelace", email: "ada@example.com"}

      html =
        render_component(&UserMenu.user_menu/1,
          id: "menu",
          current_user: user,
          flash: %{account_delete: "You are the last active owner of Last Standing."}
        )

      # Dialog auto-opens: the `hidden` class is dropped when the flash is set.
      refute html =~ ~s(class="hidden relative z-50")
      # Banner carries the server message inside the danger zone.
      assert html =~ ~s(id="menu-account-dialog-delete-error")
      assert html =~ "You are the last active owner of Last Standing."
      assert html =~ ~s(role="alert")
      # Dismissible via the cross icon (JS.hide on the banner only).
      assert html =~ ~s(aria-label="Dismiss error")
    end

    test "without the flash the dialog stays hidden with no banner" do
      user = %{name: "Ada Lovelace", email: "ada@example.com"}

      html = render_component(&UserMenu.user_menu/1, id: "menu", current_user: user)

      assert html =~ ~s(class="hidden relative z-50")
      refute html =~ "Dismiss error"
      refute html =~ ~s(role="alert")
    end
  end

  describe "placeholder menu (local mode)" do
    test "renders the restricted dialog: notices instead of identity, export, erasure" do
      html =
        render_component(&UserMenu.user_menu/1,
          id: "menu",
          placeholder_label: "Local mode"
        )

      assert html =~ "Local mode"
      # Both tabs render the migrate-to-cloud notice.
      assert html =~ "You need to migrate to cloud mode to use these settings."
      refute html =~ "Signed in as"
      refute html =~ "Delete my account"
      refute html =~ "/me/export.json"
      refute html =~ "Download my data"
    end
  end
end
