defmodule ControlKeel.Budget.SpendAlertsTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget.SpendAlerts
  import ControlKeel.MissionFixtures

  setup do
    start_supervised!({SpendAlerts, auto_check: false})
    :ok
  end

  test "check_session returns no alerts for healthy session" do
    session =
      session_fixture(%{budget_cents: 10_000, daily_budget_cents: 5_000, spent_cents: 100})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert alerts == []
  end

  test "check_session fires info alert at 50% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 500})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_info))
  end

  test "check_session fires warning at 80% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 800})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_warning))
  end

  test "check_session fires critical at 95% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 950})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_critical))
  end

  test "check_session fires exceeded at 100% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 1_000})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_exceeded))
  end

  test "check_session returns ok for unknown session" do
    assert {:ok, []} = SpendAlerts.check_session(999_999_999)
  end

  test "get_alerts returns stored alerts" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 950})

    SpendAlerts.check_session(session.id)
    assert {:ok, alerts} = SpendAlerts.get_alerts(session.id)
    assert length(alerts) > 0
  end

  test "register_callback stores callback function" do
    assert :ok = SpendAlerts.register_callback(fn _alert -> :ok end)
  end

  test "alerts include budget context" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 800})

    {:ok, [alert | _]} = SpendAlerts.check_session(session.id)
    assert alert.session_id == session.id
    assert alert.budget_cents == 1_000
    assert alert.spent_cents == 800
  end
end
