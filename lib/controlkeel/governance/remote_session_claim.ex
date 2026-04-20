defmodule ControlKeel.Governance.RemoteSessionClaim do
  @moduledoc false

  # Short-lived CK-signed session claims for remote/pairing token compatibility.
  # Designed to work with t3code's pairing/token remote model and similar
  # provider-neutral remote access patterns.

  @default_ttl_seconds 3600
  @claim_version 1

  @doc """
  Issue a signed session claim bound to the given session and agent.
  Returns a map with the claim payload and metadata.

  The claim includes:
    - session_id, agent_id, environment_id
    - trust_level inferred from agent/provider
    - expires_at (ISO8601)
    - nonce (unique per claim)
    - version (claim schema version)
  """
  def issue(session_id, agent_id, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    environment_id = Keyword.get(opts, :environment_id)
    trust_level = Keyword.get(opts, :trust_level) || infer_trust_level(agent_id)
    nonce = generate_nonce()

    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl, :second)

    payload = %{
      "session_id" => session_id,
      "agent_id" => agent_id,
      "environment_id" => environment_id,
      "trust_level" => trust_level,
      "nonce" => nonce,
      "issued_at" => DateTime.to_iso8601(now),
      "expires_at" => DateTime.to_iso8601(expires_at),
      "version" => @claim_version
    }

    signature = sign_claim(payload)

    %{
      "claim" => Map.put(payload, "signature", signature),
      "claim_id" => "#{session_id}:#{nonce}",
      "expires_at" => DateTime.to_iso8601(expires_at),
      "ttl_seconds" => ttl
    }
  end

  @doc """
  Verify a session claim.
  Returns {:ok, claim} if valid, or {:error, reason} if invalid.
  """
  def verify(%{"claim" => claim}) when is_map(claim), do: verify(claim)

  def verify(
        %{
          "session_id" => _session_id,
          "agent_id" => _agent_id,
          "signature" => signature,
          "expires_at" => expires_at,
          "nonce" => _nonce
        } = claim
      ) do
    cond do
      expired?(expires_at) ->
        {:error, :claim_expired}

      claim["version"] != @claim_version ->
        {:error, :unsupported_version}

      not valid_signature?(claim, signature) ->
        {:error, :invalid_signature}

      true ->
        {:ok, claim}
    end
  end

  def verify(_), do: {:error, :invalid_claim_format}

  @doc """
  Check if a claim has expired.
  """
  def expired?(expires_at) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, dt, _offset} -> DateTime.compare(dt, DateTime.utc_now()) == :lt
      _ -> true
    end
  end

  def expired?(_), do: true

  @doc """
  Extract trust level from a verified claim.
  """
  def trust_level(%{"trust_level" => level}), do: level
  def trust_level(_), do: "untrusted"

  @doc """
  Should this claim enforce stricter policy defaults?
  """
  def strict_policy?(%{"trust_level" => level}) when level in ["mixed", "untrusted"], do: true
  def strict_policy?(_), do: false

  # Private

  defp sign_claim(payload) do
    # HMAC-SHA256 using the CK signing key.
    # In production, this would use a proper secret from config/vault.
    signing_key = signing_key()
    data = canonicalize(payload)

    :crypto.mac(:hmac, :sha256, signing_key, data)
    |> Base.encode64(case: :lower)
  end

  defp valid_signature?(payload, signature) do
    expected = sign_claim(Map.drop(payload, ["signature"]))
    constant_time_equals?(expected, signature)
  end

  defp constant_time_equals?(a, b)
       when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end

  defp constant_time_equals?(_, _), do: false

  defp canonicalize(payload) do
    payload
    |> Map.drop(["signature"])
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp signing_key do
    # Uses CK_SECRET_KEY env var if set, otherwise derives from system.
    # This is intentional: claims are scoped to a single CK installation.
    System.get_env("CK_SECRET_KEY") ||
      "controlkeel-claim-key:" <> (System.get_env("HOME") || "/tmp")
  end

  defp infer_trust_level(agent_id) when is_binary(agent_id) do
    case ControlKeel.AgentIntegration.get(agent_id) do
      %{support_class: "attach_client"} -> "trusted"
      %{support_class: "headless_runtime"} -> "trusted"
      %{support_class: "alias"} -> "mixed"
      _ -> "untrusted"
    end
  end

  defp infer_trust_level(_), do: "untrusted"
end
