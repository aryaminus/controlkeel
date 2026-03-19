defmodule ControlKeelWeb.BenchmarksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import Phoenix.LiveViewTest

  test "index renders suites, recent runs, and launches a benchmark run", %{conn: conn} do
    existing_run = benchmark_run_fixture()

    {:ok, view, html} = live(conn, ~p"/benchmarks")

    assert html =~ "Benchmark engine"
    assert has_element?(view, "#benchmark-filters")
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

  test "index filters suites by domain pack", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/benchmarks?domain_pack=hr")

    assert has_element?(view, "#benchmark-filters")
    assert has_element?(view, "#suite-domain_expansion_v1")
    refute has_element?(view, "#suite-vibe_failures_v1")
  end

  test "show renders the persisted scenario matrix", %{conn: conn} do
    run =
      benchmark_run_fixture(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hr_discriminatory_candidate_filter,legal_privileged_memo_logging"
      })

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert html =~ "Scenario matrix"
    assert html =~ "Catch rate"
    assert has_element?(view, "#benchmark-matrix")
    assert has_element?(view, "#scenario-hr_discriminatory_candidate_filter")
    assert has_element?(view, "a[href=\"/api/v1/benchmarks/runs/#{run.id}/export?format=csv\"]")
  end
end
