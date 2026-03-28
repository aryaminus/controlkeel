defmodule ControlKeel.ACPRegistry do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.RuntimePaths

  @default_registry_url "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json"
  @default_ttl_seconds 86_400
  @user_agent "ControlKeel/#{Application.spec(:controlkeel, :vsn) || "0.1.0"}"
  @registry_id_overrides %{
    "droid" => ["factory-droid"],
    "cursor" => ["cursor"],
    "cline" => ["cline"],
    "goose" => ["goose"],
    "opencode" => ["opencode"]
  }

  def sync(_opts \\ []) do
    cache = read_cache()

    headers =
      [{"user-agent", @user_agent}] ++
        case cache["etag"] do
          value when is_binary(value) and value != "" -> [{"if-none-match", value}]
          _ -> []
        end

    case Req.get(url: registry_url(), headers: headers, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body} = response} when is_map(body) ->
        payload = build_cache(body, response)
        write_cache(payload)

      {:ok, %Req.Response{status: 304}} ->
        payload =
          cache
          |> Map.put("fetched_at", now_iso8601())
          |> Map.put("stale", false)

        write_cache(payload)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def status do
    case read_cache() do
      %{} = cache ->
        stale = cache_stale?(cache)

        Map.merge(cache_summary(cache), %{
          "cache_path" => cache_path(),
          "registry_url" => cache["source_url"] || registry_url(),
          "stale" => stale
        })

      _ ->
        %{
          "cache_path" => cache_path(),
          "registry_url" => registry_url(),
          "fetched_at" => nil,
          "entry_count" => 0,
          "matched_integrations" => 0,
          "stale" => true
        }
    end
  end

  def enrich_integrations(integrations) when is_list(integrations) do
    cache = read_cache()
    stale = cache_stale?(cache)
    entries = registry_entries(cache)

    Enum.map(integrations, &enrich_integration(&1, entries, stale))
  end

  def enrich_integration(%AgentIntegration{} = integration) do
    cache = read_cache()
    enrich_integration(integration, registry_entries(cache), cache_stale?(cache))
  end

  defp enrich_integration(%AgentIntegration{} = integration, entries, stale) do
    case find_match(entries, integration) do
      nil ->
        integration

      entry ->
        %AgentIntegration{
          integration
          | registry_match: true,
            registry_id: entry["id"],
            registry_version: entry["version"],
            registry_url: entry["repository"] || entry["website"] || entry["icon"],
            registry_stale: stale
        }
    end
  end

  defp find_match(entries, %AgentIntegration{} = integration) do
    candidates =
      Enum.uniq(
        registry_candidates(integration) ++
          registry_candidates(canonical_integration(integration))
      )

    normalized_slug = normalize_slug(integration.upstream_slug)

    Enum.find(entries, fn entry ->
      entry_id = normalize_slug(entry["id"])
      repository = normalize_slug(entry["repository"])

      (normalized_slug && repository == normalized_slug) or entry_id in candidates
    end)
  end

  defp canonical_integration(%AgentIntegration{alias_of: alias_of}) when is_binary(alias_of) do
    AgentIntegration.get(alias_of)
  end

  defp canonical_integration(_integration), do: nil

  defp registry_candidates(nil), do: []

  defp registry_candidates(%AgentIntegration{} = integration) do
    default =
      [integration.id, integration.alias_of]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&normalize_slug/1)

    default ++ Map.get(@registry_id_overrides, integration.id, [])
  end

  defp cache_summary(cache) do
    entries = registry_entries(cache)

    %{
      "fetched_at" => cache["fetched_at"],
      "etag" => cache["etag"],
      "entry_count" => length(entries),
      "matched_integrations" => matched_integrations(entries)
    }
  end

  defp matched_integrations(entries) do
    AgentIntegration.catalog()
    |> Enum.count(fn integration -> find_match(entries, integration) != nil end)
  end

  defp build_cache(body, response) do
    %{
      "source_url" => registry_url(),
      "fetched_at" => now_iso8601(),
      "etag" => response_header(response.headers, "etag"),
      "registry" => body,
      "stale" => false
    }
  end

  defp read_cache do
    path = cache_path()

    with {:ok, payload} <- File.read(path),
         {:ok, decoded} <- Jason.decode(payload) do
      decoded
    else
      _ -> %{}
    end
  end

  defp write_cache(payload) do
    path = cache_path()

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode!(payload, pretty: true) <> "\n") do
      {:ok,
       Map.merge(cache_summary(payload), %{
         "cache_path" => path,
         "registry_url" => payload["source_url"] || registry_url(),
         "stale" => false
       })}
    end
  end

  defp registry_entries(%{"registry" => %{"agents" => agents}}) when is_list(agents), do: agents
  defp registry_entries(_cache), do: []

  defp cache_stale?(%{"fetched_at" => fetched_at}) when is_binary(fetched_at) do
    with {:ok, dt, _offset} <- DateTime.from_iso8601(fetched_at) do
      DateTime.diff(DateTime.utc_now(), dt, :second) > ttl_seconds()
    else
      _ -> true
    end
  end

  defp cache_stale?(_cache), do: true

  defp cache_path do
    Application.get_env(
      :controlkeel,
      :acp_registry_cache_path,
      RuntimePaths.acp_registry_cache_path()
    )
  end

  defp registry_url do
    Application.get_env(:controlkeel, :acp_registry_url, @default_registry_url)
  end

  defp ttl_seconds do
    Application.get_env(:controlkeel, :acp_registry_ttl_seconds, @default_ttl_seconds)
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace_prefix("https://github.com/", "")
    |> String.replace_prefix("http://github.com/", "")
    |> String.trim_trailing("/")
  end

  defp response_header(headers, key) do
    key = String.downcase(key)

    case headers do
      %{} = header_map ->
        header_map
        |> Map.get(key, [])
        |> List.wrap()
        |> List.first()

      _ ->
        headers
        |> Enum.find_value(fn {header_key, value} ->
          if String.downcase(to_string(header_key)) == key do
            value |> List.wrap() |> List.first()
          end
        end)
    end
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
