defmodule ControlKeel.Runtime.CodeExecutorTest do
  use ControlKeel.DataCase, async: true

  alias ControlKeel.Runtime.CodeExecutor

  test "dry_run returns policy and command without executing" do
    assert {:ok, result} =
             CodeExecutor.call(%{
               "code" => "console.log(1 + 1)",
               "language" => "javascript",
               "dry_run" => true
             })

    assert result["allowed"] == true
    assert result["dry_run"] == true
    assert result["sandbox"] == "docker"
    assert result["command"] =~ "docker sandbox"
    assert result["policy"]["sandbox_required"] == true
    assert result["output"] == ""
  end

  test "blocks local sandbox execution" do
    assert {:error, {:blocked, details}} =
             CodeExecutor.call(%{
               "code" => "print('hello')",
               "language" => "python",
               "sandbox" => "local"
             })

    assert details.reason == "sandbox_not_supported"
    assert details.message =~ "Local host execution is intentionally blocked"
  end

  test "blocks network requests even with an allowlist until an enforcing runtime exists" do
    assert {:error, {:blocked, details}} =
             CodeExecutor.call(%{
               "code" => "console.log('net')",
               "requested_capabilities" => ["network"],
               "network_allowlist" => ["api.example.test"]
             })

    assert details.reason == "network_not_supported"
    assert details.policy["network_allowlist"] == ["api.example.test"]
  end

  test "rejects unsupported languages" do
    assert {:error, {:invalid_arguments, message}} =
             CodeExecutor.call(%{"code" => "puts 1", "language" => "ruby"})

    assert message =~ "language"
  end

  test "ck_validate findings block execution" do
    assert {:error, {:blocked, details}} =
             CodeExecutor.call(%{
               "code" => "const apiKey = 'sk-live-1234567890abcdef1234567890abcdef';",
               "dry_run" => true
             })

    assert details.reason == "ck_validate_blocked"
    assert details.validation["decision"] in ["block", "warn"]
  end
end
