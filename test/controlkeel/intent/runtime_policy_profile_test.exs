defmodule ControlKeel.Intent.RuntimePolicyProfileTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Intent.RuntimePolicyProfile

  test "resolves full_access profile with strict preflight and mandatory post-action" do
    profile = RuntimePolicyProfile.resolve("full_access")

    assert profile["mode"] == "full_access"
    assert profile["preflight"] == "strict"
    assert profile["post_action"] == "mandatory"
    assert profile["interactive_gate"] == false
    assert profile["human_checkpoint"] == false
  end

  test "resolves approval_required profile with interactive gate and human checkpoint" do
    profile = RuntimePolicyProfile.resolve("approval_required")

    assert profile["mode"] == "approval_required"
    assert profile["preflight"] == "standard"
    assert profile["post_action"] == "optional"
    assert profile["interactive_gate"] == true
    assert profile["human_checkpoint"] == true
  end

  test "resolves auto_accept_edits profile with deny on dangerous tools" do
    profile = RuntimePolicyProfile.resolve("auto_accept_edits")

    assert profile["mode"] == "auto_accept_edits"
    assert profile["preflight"] == "standard"
    assert profile["interactive_gate"] == false
    assert profile["deny_shell_network_deploy_by_default"] == true
  end

  test "normalizes kebab-case mode names" do
    assert RuntimePolicyProfile.resolve("full-access")["mode"] == "full_access"
    assert RuntimePolicyProfile.resolve("approval-required")["mode"] == "approval_required"
    assert RuntimePolicyProfile.resolve("auto-accept-edits")["mode"] == "auto_accept_edits"
  end

  test "supervised maps to approval_required" do
    assert RuntimePolicyProfile.resolve("supervised")["mode"] == "approval_required"
  end

  test "nil and empty fall back to full_access" do
    assert RuntimePolicyProfile.resolve(nil)["mode"] == "full_access"
    assert RuntimePolicyProfile.resolve("")["mode"] == "full_access"
  end

  test "modes returns all profile keys" do
    assert "full_access" in RuntimePolicyProfile.modes()
    assert "approval_required" in RuntimePolicyProfile.modes()
    assert "auto_accept_edits" in RuntimePolicyProfile.modes()
  end
end
