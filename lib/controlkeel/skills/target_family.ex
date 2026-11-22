defmodule ControlKeel.Skills.TargetFamily do
  @moduledoc false

  @family_targets %{
    "codex" => ["codex", "codex-plugin", "codex-cli", "t3code", "codex-app-server"],
    "claude" => ["claude-standalone", "claude-plugin", "claude-code", "claude-dispatch"],
    "copilot" => ["copilot-plugin", "github-repo", "copilot", "copilot-cli", "vscode"],
    "cursor" => ["cursor", "cursor-native", "cursor-agent"],
    "windsurf" => ["windsurf", "windsurf-native"],
    "cline" => ["cline", "cline-native"],
    "continue" => ["continue", "continue-native"],
    "roo" => ["roo-code", "roo-native"],
    "goose" => ["goose", "goose-native"],
    "kilo" => ["kilo", "kilo-native"],
    "open-standard" => ["open-standard"],
    "droid" => ["droid", "droid-bundle"]
  }

  @render_fallback_order Map.keys(@family_targets)

  def family_for(nil), do: nil

  def family_for(target) do
    normalized = normalize(target)

    Enum.find_value(@family_targets, fn {family, targets} ->
      if normalized == family or normalized in targets, do: family, else: nil
    end)
  end

  def render_order(preferred_target \\ nil) do
    preferred_family = family_for(preferred_target)

    @render_fallback_order
    |> Enum.sort_by(fn family ->
      if family == preferred_family, do: 0, else: 1
    end)
  end

  defp normalize(target) do
    target
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
