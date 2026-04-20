defmodule ControlKeel.Governance.RemoteSessionClaimTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Governance.RemoteSessionClaim

  describe "issue/3" do
    test "issues a valid claim for a known agent" do
      result = RemoteSessionClaim.issue(1, "t3code", environment_id: "env-1")

      assert %{"claim" => claim} = result
      assert claim["session_id"] == 1
      assert claim["agent_id"] == "t3code"
      assert claim["environment_id"] == "env-1"
      assert claim["trust_level"] == "trusted"
      assert is_binary(claim["signature"])
      assert is_binary(claim["nonce"])
      assert is_binary(result["claim_id"])
      assert is_binary(result["expires_at"])
      assert result["ttl_seconds"] == 3600
    end

    test "issues claim with custom TTL" do
      result = RemoteSessionClaim.issue(1, "t3code", ttl_seconds: 300)

      assert result["ttl_seconds"] == 300
    end

    test "issues claim with mixed trust for alias agent" do
      result = RemoteSessionClaim.issue(1, "codex", environment_id: "env-1")
      claim = result["claim"]

      assert claim["trust_level"] == "mixed"
    end
  end

  describe "verify/1" do
    test "verifies a freshly issued claim" do
      result = RemoteSessionClaim.issue(1, "t3code")
      claim = result["claim"]

      assert {:ok, ^claim} = RemoteSessionClaim.verify(claim)
    end

    test "rejects claim with tampered session_id" do
      result = RemoteSessionClaim.issue(1, "t3code")
      tampered = Map.put(result["claim"], "session_id", 999)

      assert {:error, :invalid_signature} = RemoteSessionClaim.verify(tampered)
    end

    test "rejects claim with tampered agent_id" do
      result = RemoteSessionClaim.issue(1, "t3code")
      tampered = Map.put(result["claim"], "agent_id", "malicious-agent")

      assert {:error, :invalid_signature} = RemoteSessionClaim.verify(tampered)
    end

    test "rejects expired claims" do
      past = DateTime.add(DateTime.utc_now(), -1, :second) |> DateTime.to_iso8601()

      claim = %{
        "session_id" => 1,
        "agent_id" => "t3code",
        "signature" => "fake",
        "expires_at" => past,
        "nonce" => "abc123",
        "version" => 1
      }

      assert {:error, :claim_expired} = RemoteSessionClaim.verify(claim)
    end

    test "rejects invalid claim format" do
      assert {:error, :invalid_claim_format} = RemoteSessionClaim.verify(%{"foo" => "bar"})
    end
  end

  describe "trust_level/1" do
    test "extracts trust level from claim" do
      assert RemoteSessionClaim.trust_level(%{"trust_level" => "trusted"}) == "trusted"
      assert RemoteSessionClaim.trust_level(%{}) == "untrusted"
    end
  end

  describe "strict_policy?/1" do
    test "returns true for mixed and untrusted" do
      assert RemoteSessionClaim.strict_policy?(%{"trust_level" => "mixed"})
      assert RemoteSessionClaim.strict_policy?(%{"trust_level" => "untrusted"})
    end

    test "returns false for trusted" do
      refute RemoteSessionClaim.strict_policy?(%{"trust_level" => "trusted"})
    end
  end

  describe "expired?/1" do
    test "detects past dates as expired" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601()
      assert RemoteSessionClaim.expired?(past)
    end

    test "future dates are not expired" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()
      refute RemoteSessionClaim.expired?(future)
    end
  end
end
