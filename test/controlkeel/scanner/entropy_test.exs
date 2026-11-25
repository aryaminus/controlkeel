defmodule ControlKeel.Scanner.EntropyTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Policy.Rule
  alias ControlKeel.Scanner.Entropy

  @rule %Rule{
    id: "secret.high_entropy_token",
    category: "security",
    severity: "high",
    action: "block",
    plain_message: "Secret",
    matcher: %{"type" => "entropy", "threshold" => 4.5}
  }

  test "timestamped migration filenames are not secret tokens" do
    content = "cat priv/repo/migrations/20261012152141_add_workspace_to_benchmarks.exs"
    assert Entropy.detect(content, %{"kind" => "shell"}, [@rule]) == []
  end

  test "unrelated high entropy values remain detected" do
    content = "TOKEN=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789+/"
    assert [_] = Entropy.detect(content, %{"kind" => "shell"}, [@rule])
  end

  describe "relative paths" do
    @low_rule %{@rule | matcher: %{"type" => "entropy", "threshold" => 3.5}}

    test "API and session paths of words, numbers and UUIDs are not tokens" do
      for content <- [
            "gh api repos/acme/widget-service/pulls/367/comments",
            "cat /private/tmp/claude-501/-Users-dev-project/" <>
              "b9a03b32-c585-4e51-a261-af2dc0fe1bfe/tasks/bj4kk839p.output",
            "open repos/acme/widget-service/blob/a46c78ec/lib/router.ex",
            "python3 scripts/secret_scan.py /private/tmp/claude-501/-Users-dev-project/" <>
              "b9a03b32-c585-4e51-a261-af2dc0fe1bfe/scratchpad/patch.py",
            "gpg --batch --passphrase-file /private/tmp/claude-501/-Users-dev-project/" <>
              "b9a03b32-c585-4e51-a261-af2dc0fe1bfe/scratchpad/passphrase --symmetric notes.txt",
            "PASSWORD_FILE=/private/tmp/claude-501/-Users-dev-project/" <>
              "b9a03b32-c585-4e51-a261-af2dc0fe1bfe/scratchpad/pw ./run.sh",
            "python3 /private/tmp/claude-501/-Users-dev-project/" <>
              "b9a03b32-c585-4e51-a261-af2dc0fe1bfe/scratchpad/patch.py"
          ] do
        assert Entropy.detect(content, %{"kind" => "shell"}, [@low_rule]) == [], content
      end
    end

    test "a token inside a path is still detected" do
      for content <- [
            "curl repos/acme/aB3dE9fG2hJ4kL6mN8pQ0rS/comments",
            "curl repos/acme/k3j9x8w2v7q1m5n4/comments",
            "curl repos/acme/x7k2p9/q8m3n6/comments"
          ] do
        assert [_] = Entropy.detect(content, %{"kind" => "shell"}, [@low_rule]), content
      end
    end

    test "slash-containing credentials are still detected" do
      for content <- [
            "curl -H 'Authorization: Bearer AbCdEfGhIjKlMnOp/QrStUvWxYz/012345678901' https://example.test",
            "export TOKEN=AbCdEfGhIjKlMnOp/QrStUvWxYz/012345678901",
            "docker login --username alice --password 'ABCDEFGHIJKLMNOP/QRSTUVWXYZ/0123456789' registry.example",
            "tool --api-key qwertyuiopasdfgh/zxcvbnmlkjhg/1234567890",
            "echo QwErTyUiOpAsDf/GhJkLzXcVbNm/123456789012"
          ] do
        assert [_ | _] = Entropy.detect(content, %{"kind" => "shell"}, [@low_rule]), content
      end
    end
  end
end
