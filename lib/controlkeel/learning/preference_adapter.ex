defmodule ControlKeel.Learning.PreferenceAdapter do
  @moduledoc false

  alias ControlKeel.Memory

  def record_preference(session_id, opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    preferences = Keyword.get(opts, :preferences, %{})

    attrs = %{
      workspace_id: workspace_id,
      session_id: session_id,
      record_type: "decision",
      title: "User preference recorded",
      summary: "Recorded user preferences for future personalization",
      body: "User preference: #{inspect(preferences)}",
      tags: ["user_preference", "personalization"],
      source_type: "preference_adapter",
      source_id: "pref:#{session_id}:#{System.unique_integer([:positive])}",
      metadata: %{
        preferences: preferences,
        session_id: session_id,
        recorded_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    Memory.record(attrs)
  end

  def get_preferences(session_id) do
    case Memory.search("user preference", session_id: session_id, top_k: 50) do
      %{entries: entries} ->
        preferences =
          entries
          |> Enum.filter(fn e ->
            tags = Map.get(e, :tags, [])
            "user_preference" in tags
          end)
          |> Enum.map(fn e -> Map.get(e, :metadata, %{}) |> Map.get("preferences", %{}) end)
          |> Enum.reduce(%{}, fn pref, acc ->
            Map.merge(acc, pref, fn _k, _v1, v2 -> v2 end)
          end)

        {:ok, preferences}

      _ ->
        {:ok, %{}}
    end
  end

  def detect_preferences(session_id, _opts \\ []) do
    case Memory.search("task completion session:#{session_id}", top_k: 100) do
      %{entries: entries} ->
        detected = analyze_patterns(entries)
        {:ok, detected}

      _ ->
        {:ok, %{}}
    end
  end

  def apply_preferences_to_brief(brief, preferences) when is_map(brief) and is_map(preferences) do
    Enum.reduce(preferences, brief, fn {key, value}, acc ->
      case key do
        "preferred_stack" ->
          put_in(acc, ["stack"], value)

        "preferred_css_framework" ->
          put_in(acc, ["css_framework"], value)

        "preferred_language" ->
          put_in(acc, ["language"], value)

        "preferred_model" ->
          put_in(acc, ["model"], value)

        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp analyze_patterns(entries) do
    technologies =
      entries
      |> Enum.flat_map(fn e ->
        Map.get(e, :metadata, %{})
        |> Map.get("technologies", [])
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_tech, count} -> count >= 2 end)
      |> Enum.sort_by(fn {_tech, count} -> count end, :desc)
      |> Enum.map(fn {tech, _count} -> tech end)

    css_framework =
      entries
      |> Enum.flat_map(fn e ->
        meta = Map.get(e, :metadata, %{})
        Map.get(meta, "css_framework", [])
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_fw, count} -> count >= 2 end)
      |> Enum.sort_by(fn {_fw, count} -> count end, :desc)
      |> Enum.map(fn {fw, _count} -> fw end)
      |> List.first()

    detected = %{}

    detected =
      if length(technologies) > 0 do
        Map.put(detected, "preferred_stack", Enum.take(technologies, 3))
      else
        detected
      end

    detected =
      if css_framework do
        Map.put(detected, "preferred_css_framework", css_framework)
      else
        detected
      end

    detected
  end
end
