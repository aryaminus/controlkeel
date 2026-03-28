defmodule ControlKeel.ACPRegistryTest do
  use ExUnit.Case, async: false

  alias ControlKeel.ACPRegistry
  alias ControlKeel.AgentIntegration

  setup do
    cache_path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-acp-registry-#{System.unique_integer([:positive])}.json"
      )

    previous_url = Application.get_env(:controlkeel, :acp_registry_url)
    previous_cache = Application.get_env(:controlkeel, :acp_registry_cache_path)
    previous_ttl = Application.get_env(:controlkeel, :acp_registry_ttl_seconds)

    Application.put_env(:controlkeel, :acp_registry_cache_path, cache_path)
    Application.put_env(:controlkeel, :acp_registry_ttl_seconds, 60)

    on_exit(fn ->
      File.rm_rf(cache_path)

      restore_env(:acp_registry_url, previous_url)
      restore_env(:acp_registry_cache_path, previous_cache)
      restore_env(:acp_registry_ttl_seconds, previous_ttl)
    end)

    %{cache_path: cache_path}
  end

  test "sync caches the registry and enriches matching integrations", %{cache_path: cache_path} do
    bypass = Bypass.open()

    Application.put_env(
      :controlkeel,
      :acp_registry_url,
      "http://localhost:#{bypass.port}/registry.json"
    )

    Bypass.expect_once(bypass, "GET", "/registry.json", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.put_resp_header("etag", "\"test-etag\"")
      |> Plug.Conn.resp(200, Jason.encode!(registry_body()))
    end)

    assert {:ok, status} = ACPRegistry.sync()
    assert status["entry_count"] == 2
    assert status["matched_integrations"] >= 1
    assert File.exists?(cache_path)

    cline =
      AgentIntegration.get("cline")
      |> ACPRegistry.enrich_integration()

    assert cline.registry_match
    assert cline.registry_version == "2.11.0"
    assert cline.registry_url == "https://github.com/cline/cline"
    refute cline.registry_stale
  end

  test "sync reuses the cache on 304 responses", %{cache_path: cache_path} do
    bypass = Bypass.open()

    Application.put_env(
      :controlkeel,
      :acp_registry_url,
      "http://localhost:#{bypass.port}/registry.json"
    )

    Bypass.expect_once(bypass, "GET", "/registry.json", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.put_resp_header("etag", "\"test-etag\"")
      |> Plug.Conn.resp(200, Jason.encode!(registry_body()))
    end)

    assert {:ok, _status} = ACPRegistry.sync()

    Bypass.expect_once(bypass, "GET", "/registry.json", fn conn ->
      assert Plug.Conn.get_req_header(conn, "if-none-match") == ["\"test-etag\""]
      Plug.Conn.resp(conn, 304, "")
    end)

    assert {:ok, status} = ACPRegistry.sync()
    assert status["entry_count"] == 2
    assert status["cache_path"] == cache_path
  end

  test "stale cache still enriches integrations without a network fetch", %{
    cache_path: cache_path
  } do
    stale_payload = %{
      "source_url" => "https://example.com/registry.json",
      "fetched_at" => "2020-01-01T00:00:00Z",
      "etag" => "\"stale\"",
      "registry" => registry_body(),
      "stale" => true
    }

    File.mkdir_p!(Path.dirname(cache_path))
    File.write!(cache_path, Jason.encode!(stale_payload, pretty: true) <> "\n")

    status = ACPRegistry.status()
    assert status["stale"]
    assert status["entry_count"] == 2

    cursor =
      AgentIntegration.get("cursor")
      |> ACPRegistry.enrich_integration()

    assert cursor.registry_match
    assert cursor.registry_stale
  end

  defp registry_body do
    %{
      "version" => "1.0.0",
      "agents" => [
        %{
          "id" => "cline",
          "name" => "Cline",
          "version" => "2.11.0",
          "repository" => "https://github.com/cline/cline"
        },
        %{
          "id" => "cursor",
          "name" => "Cursor",
          "version" => "0.1.0",
          "website" => "https://cursor.com"
        }
      ]
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:controlkeel, key)
  defp restore_env(key, value), do: Application.put_env(:controlkeel, key, value)
end
