defmodule ControlKeelWeb.ObservabilityExportGateTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts

  defp set_mode(mode) do
    prev = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, mode)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, prev) end)
  end

  describe "GET /observability/sessions/:id/export.json auth gate" do
    test "returns 401 in cloud mode without a membership" do
      set_mode(:cloud)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> get(~p"/observability/sessions/999999/export.json")

      assert conn.status == 401
      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "passes the gate in cloud mode with an active membership" do
      set_mode(:cloud)

      {:ok, user} = Accounts.create_user(%{email: "obs@example.com"})

      {:ok, {_org, membership}} =
        Accounts.create_org_with_owner(user, %{name: "Obs", slug: "obs-org"})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          current_user_id: user.id,
          current_org_id: membership.org_id
        })
        |> get(~p"/observability/sessions/999999/export.json")

      # Gate passed — controller returns 404 for the unknown session, not 401.
      assert conn.status == 404
    end

    test "is a passthrough in local mode (no membership required)" do
      set_mode(:local)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> get(~p"/observability/sessions/999999/export.json")

      # Gate skipped — controller returns 404 for the unknown session, not 401.
      assert conn.status == 404
    end
  end
end
