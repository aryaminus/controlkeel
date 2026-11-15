defmodule ControlKeelWeb.BreakGlassTest do
  @moduledoc """
  Bootstrap and local credentials authorize only in local runtime mode.
  """
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeelWeb.APIHelpers

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)

    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    Application.delete_env(:controlkeel, :break_glass_enabled)
    Application.delete_env(:controlkeel, :break_glass_workspace_id)

    on_exit(fn ->
      Application.put_env(:controlkeel, :runtime_mode, previous)
      Application.delete_env(:controlkeel, :break_glass_enabled)
      Application.delete_env(:controlkeel, :break_glass_workspace_id)
    end)

    :ok
  end

  defp bootstrap_conn do
    build_conn() |> Plug.Conn.assign(:api_auth, %{type: :bootstrap})
  end

  describe "cloud mode" do
    test "bootstrap is denied by default" do
      assert APIHelpers.authorize_workspace_for_conn(bootstrap_conn(), 1, "read") ==
               {:error, :forbidden}
    end

    test "bootstrap is denied when enabled but not scoped to a workspace" do
      Application.put_env(:controlkeel, :break_glass_enabled, true)

      assert APIHelpers.authorize_workspace_for_conn(bootstrap_conn(), 1, "read") ==
               {:error, :forbidden}
    end

    test "bootstrap is denied for a workspace outside its break-glass scope" do
      Application.put_env(:controlkeel, :break_glass_enabled, true)
      Application.put_env(:controlkeel, :break_glass_workspace_id, 7)

      assert APIHelpers.authorize_workspace_for_conn(bootstrap_conn(), 8, "read") ==
               {:error, :forbidden}
    end

    test "bootstrap remains denied for its scoped workspace when enabled" do
      Application.put_env(:controlkeel, :break_glass_enabled, true)
      Application.put_env(:controlkeel, :break_glass_workspace_id, 7)

      assert APIHelpers.authorize_workspace_for_conn(bootstrap_conn(), 7, "read") ==
               {:error, :forbidden}
    end

    test "a string workspace id does not enable hosted bootstrap" do
      Application.put_env(:controlkeel, :break_glass_enabled, true)
      Application.put_env(:controlkeel, :break_glass_workspace_id, "7")

      assert APIHelpers.authorize_workspace_for_conn(bootstrap_conn(), 7, "read") ==
               {:error, :forbidden}
    end
  end

  describe "local mode" do
    test "bootstrap remains fully authorized (single-user local)" do
      Application.put_env(:controlkeel, :runtime_mode, :local)

      assert APIHelpers.authorize_workspace_for_conn(bootstrap_conn(), 42, "read") == :ok
    end
  end

  describe "other credential types are unaffected" do
    test "an explicit local caller is denied in cloud mode" do
      conn = build_conn() |> Plug.Conn.assign(:api_auth, %{type: :local})
      assert APIHelpers.authorize_workspace_for_conn(conn, 1, "read") == {:error, :forbidden}
    end

    test "an unassigned credential still fails closed" do
      assert APIHelpers.authorize_workspace_for_conn(build_conn(), 1, "read") ==
               {:error, :forbidden}
    end
  end
end
