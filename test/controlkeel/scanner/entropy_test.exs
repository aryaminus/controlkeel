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
            "python3 /private/tmp/claude-501/-Users-dev-project/" <>
              "b9a03b32-c585-4e51-a261-af2dc0fe1bfe/scratchpad/patch.py"
          ] do
        assert Entropy.detect(content, %{"kind" => "shell"}, [@low_rule]) == [], content
      end
    end

    test "a token inside a path is still detected" do
      content = "curl repos/acme/aB3dE9fG2hJ4kL6mN8pQ0rS/comments"
      assert [_] = Entropy.detect(content, %{"kind" => "shell"}, [@low_rule])
    end
  end
end
