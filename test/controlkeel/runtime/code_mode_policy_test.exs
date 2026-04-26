defmodule ControlKeel.Runtime.CodeModePolicyTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Runtime.CodeModePolicy

  test "build defaults to sandboxed default-deny generated script policy" do
    policy = CodeModePolicy.build(risk_tier: "medium")

    assert policy["mode"] == "generated_script"
    assert policy["status"] == "advisory_contract"
    assert policy["sandbox_required"] == true
    assert policy["approval_required"] == false
    assert "network" in policy["default_denied_capabilities"]
    assert "secrets" in policy["default_denied_capabilities"]
    assert policy["allowed_capabilities"] == []
    assert policy["limits"]["max_network_requests"] == 0
    assert policy["rate_policy"]["respect_retry_after"] == true
    assert "generated_source" in policy["proof_artifacts"]
  end

  test "build allows reviewed network only with an allowlist and approval" do
    policy =
      CodeModePolicy.build(
        risk_tier: "medium",
        requested_capabilities: ["read_api", "network", "secrets"],
        network_allowlist: ["api.example.test"]
      )

    assert policy["approval_required"] == true
    assert policy["allowed_capabilities"] == ["read_api", "network"]
    assert policy["network_allowlist"] == ["api.example.test"]
    assert policy["limits"]["max_network_requests"] == 10
    assert policy["rate_policy"]["max_requests_per_minute"] == 30
    refute "secrets" in policy["allowed_capabilities"]
  end

  test "critical risk keeps network disabled even when requested" do
    policy =
      CodeModePolicy.build(
        risk_tier: "critical",
        requested_capabilities: ["network"],
        network_allowlist: ["api.example.test"]
      )

    assert policy["approval_required"] == true
    refute "network" in policy["allowed_capabilities"]
    assert policy["limits"]["max_network_requests"] == 0
    assert policy["rate_policy"]["max_requests_per_minute"] == 0
  end

  test "network request without allowlist stays denied but still requires approval" do
    policy = CodeModePolicy.build(risk_tier: "medium", requested_capabilities: ["network"])

    assert policy["approval_required"] == true
    assert policy["network_allowlist"] == []
    refute "network" in policy["allowed_capabilities"]
    assert policy["limits"]["max_network_requests"] == 0
  end

  test "normalizes malformed inputs safely" do
    policy =
      CodeModePolicy.build(
        risk_tier: "surprising",
        requested_capabilities: [:read_api, 123, nil, ""],
        network_allowlist: ["", :api_example]
      )

    assert policy["approval_required"] == true
    assert policy["allowed_capabilities"] == ["read_api"]
    assert policy["network_allowlist"] == ["api_example"]
    assert policy["rate_policy"]["respect_retry_after"] == true
  end

  test "detects briefs that mention code-mode or large API orchestration" do
    assert CodeModePolicy.relevant_brief?(%{
             "recommended_stack" => "Typed runtime with code-mode OpenAPI orchestration"
           })

    refute CodeModePolicy.relevant_brief?(%{"recommended_stack" => "Phoenix CRUD forms"})
  end
end
