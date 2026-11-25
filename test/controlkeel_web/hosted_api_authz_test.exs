defmodule ControlKeelWeb.HostedApiAuthzTest do
  @moduledoc """
  Hosted API authorization for bootstrap and `:local` credentials: both
  authorize only in `:local` runtime mode — cloud fails closed.

  (Formerly `break_glass_test.exs`: the break-glass bootstrap config that
  these dead keys referenced was removed when hosted bootstrap was made
  local-only in PR #257 / `49e05110`; nothing reads
  `:break_glass_enabled` / `:break_glass_workspace_id` anymore.)
  """
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeelWeb.APIHelpers

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)

    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      Application.put_env(:controlkeel, :runtime_mode, previous)
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
