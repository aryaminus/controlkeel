defmodule ControlKeelWeb.BenchmarksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import Phoenix.LiveViewTest

  test "index renders suites, recent runs, and launches a benchmark run", %{conn: conn} do
    existing_run = benchmark_run_fixture()

    {:ok, view, html} = live(conn, ~p"/benchmarks")

    assert html =~ "Benchmark engine"
    assert has_element?(view, "#benchmark-runner")
    assert has_element?(view, "#benchmark-runs")
    assert has_element?(view, "#policy-train-form")
    assert has_element?(view, "#policy-training-runs")
    assert has_element?(view, "#active-router-artifact")
    assert has_element?(view, "a[href=\"/benchmarks/runs/#{existing_run.id}\"]")

    render_submit(
      form(view, "#benchmark-runner",
        benchmark: %{
          "suite" => "vibe_failures_v1",
          "subjects" => "controlkeel_validate",
          "baseline_subject" => "controlkeel_validate"
        }
      )
    )

    {path, _flash} = assert_redirect(view)
    assert path =~ "/benchmarks/runs/"
  end

  test "show renders the persisted scenario matrix", %{conn: conn} do
    run =
      benchmark_run_fixture(%{
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
      })

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert html =~ "Scenario matrix"
    assert html =~ "Catch rate"
    assert has_element?(view, "#benchmark-matrix")
    assert has_element?(view, "#scenario-hardcoded_api_key_python_webhook")
    assert has_element?(view, "a[href=\"/api/v1/benchmarks/runs/#{run.id}/export?format=csv\"]")
  end
end
