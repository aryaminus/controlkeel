defmodule ControlKeel.Governance.AgentMonitorTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.AgentMonitor

  setup do
    start_supervised!(AgentMonitor)
    :ok
  end

  test "track records an event" do
    AgentMonitor.track("agent_a", :api_call, metadata: %{status: 200})

    assert {:ok, events} = AgentMonitor.get_events("agent_a")
    assert length(events) == 1
    assert List.first(events).event_type == :api_call
  end

  test "track records events for multiple agents" do
    AgentMonitor.track("agent_a", :api_call)
    AgentMonitor.track("agent_b", :file_modification)

    assert {:ok, events_a} = AgentMonitor.get_events("agent_a")
    assert {:ok, events_b} = AgentMonitor.get_events("agent_b")
    assert length(events_a) == 1
    assert length(events_b) == 1
  end

  test "get_events filters by event_type" do
    AgentMonitor.track("agent_c", :api_call)
    AgentMonitor.track("agent_c", :file_modification)
    AgentMonitor.track("agent_c", :api_call)

    assert {:ok, api_events} = AgentMonitor.get_events("agent_c", event_type: :api_call)
    assert length(api_events) == 2
  end

  test "get_events respects limit" do
    for i <- 1..10 do
      AgentMonitor.track("agent_d", :api_call, metadata: %{i: i})
    end

    assert {:ok, events} = AgentMonitor.get_events("agent_d", limit: 3)
    assert length(events) == 3
  end

  test "get_active_agents lists tracked agents with status" do
    AgentMonitor.track("active_agent", :api_call)

    assert {:ok, agents} = AgentMonitor.get_active_agents()
    assert is_list(agents)
    assert Enum.any?(agents, &(&1.agent_id == "active_agent"))
  end

  test "get_feed returns global event stream" do
    AgentMonitor.track("feed_a", :api_call)
    AgentMonitor.track("feed_b", :file_modification)

    assert {:ok, feed} = AgentMonitor.get_feed()
    assert length(feed) == 2
  end

  test "events include timestamp and metadata" do
    AgentMonitor.track("meta_agent", :api_call, metadata: %{key: "value"})

    assert {:ok, [event]} = AgentMonitor.get_events("meta_agent")
    assert %DateTime{} = event.timestamp
    assert event.metadata.key == "value"
  end

  test "get_events returns empty for unknown agent" do
    assert {:ok, events} = AgentMonitor.get_events("nonexistent")
    assert events == []
  end
end
