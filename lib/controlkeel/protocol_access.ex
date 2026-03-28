defmodule ControlKeel.ProtocolAccess do
  @moduledoc false

  alias ControlKeel.Platform
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeelWeb.Endpoint

  @token_salt "protocol-access"
  @default_token_ttl 3_600
  @protocol_scopes ~w(
    mcp:access
    a2a:access
    context:read
    validate:run
    finding:write
    budget:write
    route:read
    skills:read
    delegate:run
  )

  def protocol_scopes, do: @protocol_scopes

  def token_ttl_seconds do
    Application.get_env(:controlkeel, :protocol_access_token_ttl_seconds, @default_token_ttl)
  end

  def oauth_client_id(%ServiceAccount{id: id}), do: oauth_client_id(id)
  def oauth_client_id(id) when is_integer(id), do: "ck-sa-#{id}"

  def authenticate_client(client_id, client_secret)
      when is_binary(client_id) and is_binary(client_secret) do
    with {:ok, expected_id} <- parse_client_id(client_id),
         {:ok, service_account} <- Platform.authenticate_service_account(client_secret),
         true <- service_account.id == expected_id || {:error, :unauthorized} do
      {:ok, service_account}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :unauthorized}
    end
  end

  def grant_scopes(%ServiceAccount{} = service_account, requested_scope, resource_input) do
    with {:ok, resource} <- normalize_resource(resource_input) do
      available_scopes = available_scopes(service_account)

      granted_scopes =
        requested_scope
        |> requested_scopes()
        |> case do
          [] -> available_scopes
          requested -> requested
        end

      cond do
        granted_scopes == [] ->
          {:error, :invalid_scope}

        not Enum.all?(granted_scopes, &(&1 in available_scopes)) ->
          {:error, :invalid_scope}

        resource.access_scope not in granted_scopes ->
          {:error, :invalid_scope}

        true ->
          {:ok, granted_scopes, resource}
      end
    end
  end

  def issue_access_token(%ServiceAccount{} = service_account, scopes, resource_input) do
    with {:ok, resource} <- normalize_resource(resource_input) do
      claims = %{
        "service_account_id" => service_account.id,
        "workspace_id" => service_account.workspace_id,
        "scopes" => scopes,
        "aud" => resource.audience,
        "resource" => resource.id
      }

      {:ok, Phoenix.Token.sign(Endpoint, @token_salt, claims), resource}
    end
  end

  def verify_access_token(token, resource_input, required_scopes \\ [])
      when is_binary(token) and is_list(required_scopes) do
    with {:ok, resource} <- normalize_resource(resource_input),
         {:ok, claims} <-
           Phoenix.Token.verify(Endpoint, @token_salt, token, max_age: token_ttl_seconds()),
         {:ok, service_account} <- verify_active_service_account(claims),
         :ok <- verify_audience(claims, resource),
         :ok <- verify_scope_membership(claims, required_scopes) do
      {:ok,
       %{
         service_account: service_account,
         scopes: Map.get(claims, "scopes", []),
         resource: resource.id,
         audience: resource.audience,
         claims: claims
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def protected_resource_metadata(resource_input) do
    {:ok, resource} = normalize_resource(resource_input)

    %{
      "resource" => resource.audience,
      "authorization_servers" => [issuer()],
      "scopes_supported" => @protocol_scopes,
      "bearer_methods_supported" => ["header"],
      "resource_documentation" => Endpoint.url() <> "/getting-started"
    }
  end

  def authorization_server_metadata do
    %{
      "issuer" => issuer(),
      "token_endpoint" => Endpoint.url() <> "/oauth/token",
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => ["client_secret_basic", "client_secret_post"],
      "scopes_supported" => @protocol_scopes
    }
  end

  def challenge_header(resource_input, opts \\ []) do
    {:ok, resource} = normalize_resource(resource_input)

    attributes =
      [{"realm", "controlkeel"}] ++
        challenge_resource_metadata(resource, opts) ++ challenge_error_attributes(opts)

    "Bearer " <>
      Enum.map_join(attributes, ", ", fn {key, value} -> ~s(#{key}="#{value}") end)
  end

  def normalize_resource(nil), do: normalize_resource("mcp")

  def normalize_resource(resource) when is_binary(resource) do
    trimmed = String.trim(resource)
    base = Endpoint.url()

    cond do
      trimmed in ["", "mcp"] ->
        {:ok,
         %{
           id: "mcp",
           audience: base <> "/mcp",
           access_scope: "mcp:access",
           metadata_path: "/.well-known/oauth-protected-resource/mcp"
         }}

      trimmed == base <> "/mcp" ->
        normalize_resource("mcp")

      trimmed == "a2a" ->
        {:ok,
         %{
           id: "a2a",
           audience: base <> "/a2a",
           access_scope: "a2a:access",
           metadata_path: "/.well-known/oauth-protected-resource/mcp"
         }}

      trimmed == base <> "/a2a" ->
        normalize_resource("a2a")

      true ->
        {:error, :invalid_resource}
    end
  end

  defp requested_scopes(nil), do: []
  defp requested_scopes(""), do: []

  defp requested_scopes(value) when is_binary(value) do
    value
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.uniq()
  end

  defp available_scopes(%ServiceAccount{} = service_account) do
    scopes = ServiceAccount.scope_list(service_account)

    if "admin" in scopes or "*" in scopes do
      @protocol_scopes
    else
      scopes
      |> Enum.filter(&(&1 in @protocol_scopes))
      |> Enum.uniq()
    end
  end

  defp parse_client_id("ck-sa-" <> rest) do
    case Integer.parse(rest) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :unauthorized}
    end
  end

  defp parse_client_id(_other), do: {:error, :unauthorized}

  defp verify_active_service_account(%{"service_account_id" => id}) when is_integer(id) do
    case Platform.get_service_account(id) do
      %ServiceAccount{} = account ->
        if ServiceAccount.active?(account) do
          {:ok, account}
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp verify_active_service_account(_claims), do: {:error, :unauthorized}

  defp verify_audience(%{"aud" => audience}, %{audience: audience}), do: :ok
  defp verify_audience(_claims, _resource), do: {:error, :unauthorized}

  defp verify_scope_membership(claims, required_scopes) do
    granted = Map.get(claims, "scopes", [])

    if Enum.all?(required_scopes, &(&1 in granted)) do
      :ok
    else
      {:error, :insufficient_scope}
    end
  end

  defp issuer, do: Endpoint.url()

  defp challenge_error_attributes(opts) do
    case Keyword.get(opts, :error) do
      nil ->
        []

      error ->
        [{"error", error}] ++
          case Keyword.get(opts, :error_description) do
            nil -> []
            description -> [{"error_description", description}]
          end
    end
  end

  defp challenge_resource_metadata(resource, opts) do
    if Keyword.get(opts, :include_resource_metadata, true) do
      [{"resource_metadata", Endpoint.url() <> resource.metadata_path}]
    else
      []
    end
  end
end
