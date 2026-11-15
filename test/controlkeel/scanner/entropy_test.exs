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
end
