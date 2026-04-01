defmodule ControlKeel.Learning.PreferenceAdapterTest do
  use ControlKeel.DataCase

  alias ControlKeel.Learning.PreferenceAdapter
  import ControlKeel.MissionFixtures

  test "record_preference stores a user preference" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    assert {:ok, _record} =
             PreferenceAdapter.record_preference(session.id,
               workspace_id: workspace.workspace_id,
               preferences: %{"preferred_stack" => "phoenix"}
             )
  end

  test "get_preferences returns empty for session without preferences" do
    session = session_fixture()
    assert {:ok, prefs} = PreferenceAdapter.get_preferences(session.id)
    assert prefs == %{}
  end

  test "detect_preferences returns empty for session without tasks" do
    session = session_fixture()
    assert {:ok, detected} = PreferenceAdapter.detect_preferences(session.id)
    assert detected == %{}
  end

  test "apply_preferences_to_brief merges preferences into brief" do
    brief = %{"project" => "test", "stack" => "node"}
    prefs = %{"preferred_stack" => ["phoenix"], "preferred_model" => "claude"}

    result = PreferenceAdapter.apply_preferences_to_brief(brief, prefs)
    assert result["stack"] == ["phoenix"]
    assert result["model"] == "claude"
    assert result["project"] == "test"
  end

  test "apply_preferences_to_brief handles css_framework preference" do
    brief = %{}
    prefs = %{"preferred_css_framework" => "tailwind"}

    result = PreferenceAdapter.apply_preferences_to_brief(brief, prefs)
    assert result["css_framework"] == "tailwind"
  end

  test "apply_preferences_to_brief passes through unknown keys" do
    brief = %{}
    prefs = %{"custom_setting" => "value"}

    result = PreferenceAdapter.apply_preferences_to_brief(brief, prefs)
    assert result["custom_setting"] == "value"
  end
end
