defmodule ControlKeelWeb.BenchmarksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  defp benchmarks_path(org, ws), do: "/#{org.slug}/workspaces/#{ws.slug}/benchmarks"

  test "index renders suites, recent runs, and launches a benchmark run", %{conn: conn} do
    existing_run = benchmark_run_fixture()
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, benchmarks_path(org, ws))

    assert has_element?(view, "h1", "Benchmark engine")
    assert has_element?(view, "#benchmark-runner button[type='submit']")
    assert html =~ "OpenCode vs ControlKeel"
    assert has_element?(view, "#benchmark-runner")
    assert has_element?(view, "#benchmark-preset-opencode")
    assert has_element?(view, "#benchmark-subjects-input")
    assert has_element?(view, "#benchmark-baseline-input")
    assert has_element?(view, "#benchmark-runs")

    assert has_element?(view, "a[href=\"/benchmarks/runs/#{existing_run.id}\"]")

    render_submit(
      form(view, "#benchmark-runner",
        benchmark: %{
          "suite" => "vibe_failures_v1",
          "subjects" => ["controlkeel_validate"],
          "baseline_subject" => "controlkeel_validate"
        }
      )
    )

    {path, _flash} = assert_redirect(view)
    assert path =~ "/benchmarks/runs/"
  end

  test "index preset buttons fill subject fields", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    view |> element("#benchmark-preset-proxy") |> render_click()

    assert has_element?(
             view,
             "#benchmark-runner input[name='benchmark[subjects][]'][value='controlkeel_validate']"
           )

    assert has_element?(
             view,
             "#benchmark-runner input[name='benchmark[subjects][]'][value='controlkeel_proxy']"
           )

    view |> element("#benchmark-preset-opencode") |> render_click()

    assert has_element?(
             view,
             "#benchmark-runner input[name='benchmark[subjects][]'][value='opencode_manual']"
           )

    view |> element("#benchmark-preset-ck-only") |> render_click()
    assert render(view) =~ "benchmark-subjects-input"
  end

  test "index surfaces configured external subjects", %{conn: conn} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-benchmarks-live-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "opencode_manual",
        "label" => "OpenCode Manual Import",
        "type" => "manual_import"
      }
    ])

    original_cwd = File.cwd!()
    File.cd!(tmp_dir)

    on_exit(fn -> File.cd!(original_cwd) end)

    {org, ws, _session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, benchmarks_path(org, ws))

    assert html =~ "OpenCode Manual Import (external)"
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
    assert html =~ "Promotion integrity"
    assert has_element?(view, "#scenario-hr_discriminatory_candidate_filter")
    assert has_element?(view, "a[href=\"/api/v1/benchmarks/runs/#{run.id}/export?format=csv\"]")

    # Loop access: each subject label renders (zip alignment + subject lookup).
    assert html =~ "ControlKeel Validate"
    assert html =~ "ControlKeel Proxy Policy Scan"

    # Loop access: result fields resolve inside scenario_result/1.
    assert html =~ "findings"
    assert html =~ "latency"
    assert html =~ "overhead"

    # Status badge renders (was previously suppressed for "completed").
    assert html =~ "completed"

    # Loop access: the second scenario row renders too.
    assert has_element?(view, "#scenario-legal_privileged_memo_logging")
  end

  test "show renders the comparison panel for a multi-subject run", %{conn: conn} do
    run =
      benchmark_run_fixture(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hr_discriminatory_candidate_filter,legal_privileged_memo_logging"
      })

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert has_element?(view, "#comparison-panel")
    assert html =~ "Subject comparison"
    assert has_element?(view, "#comparison-subject-controlkeel_validate")
    assert has_element?(view, "#comparison-subject-controlkeel_proxy")
    assert has_element?(view, "#comparison-chart-controlkeel_validate")
    assert has_element?(view, "#comparison-chart-controlkeel_proxy")
    assert html =~ "baseline"

    assert html =~ "TPR"
    assert html =~ "FPR"
    assert html =~ "Youden"
    assert html =~ "CK tool calls"
    assert html =~ "Safe claim:"
    assert html =~ "Caveat:"
    assert html =~ "Δ"
  end

  test "show renders empty comparison state for a single-subject run", %{conn: conn} do
    run = benchmark_run_fixture()

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert has_element?(view, "#comparison-panel")
    assert html =~ "No comparable subjects"
    refute has_element?(view, "#comparison-subject-controlkeel_validate")
    refute has_element?(view, "#comparison-chart")
  end

  test "show renders the import panel for an awaiting-import run", %{conn: conn} do
    run = awaiting_import_run_fixture()

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert has_element?(view, "#import-panel")
    assert has_element?(view, "#import-slots")
    assert has_element?(view, "#import-slot-manual_subject-hardcoded_api_key_python_webhook")
    assert has_element?(view, "#benchmark-import-form")
    assert html =~ "Manual Subject"
  end

  test "show completes a run through the import panel", %{conn: conn} do
    run = awaiting_import_run_fixture()

    {:ok, view, _html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    html =
      view
      |> form("#benchmark-import-form",
        import: %{
          "subject" => "manual_subject",
          "scenario_slug" => "hardcoded_api_key_python_webhook",
          "payload" => Jason.encode!(%{content: "OPENAI_KEY = \"AKIAIOSFODNN7EXAMPLE\""})
        }
      )
      |> render_submit()

    assert html =~
             "Imported Manual Subject (external) result for hardcoded_api_key_python_webhook"

    refute has_element?(view, "#import-panel")

    assert has_element?(view, "#scenario-hardcoded_api_key_python_webhook")
    assert render(view) =~ "completed"
  end

  test "show import panel flashes an error for invalid JSON without navigating", %{conn: conn} do
    run = awaiting_import_run_fixture()

    {:ok, view, _html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    html =
      view
      |> form("#benchmark-import-form",
        import: %{
          "subject" => "manual_subject",
          "scenario_slug" => "hardcoded_api_key_python_webhook",
          "payload" => "not json at all"
        }
      )
      |> render_submit()

    assert html =~ "Import payload must be valid JSON"
    assert has_element?(view, "#import-panel")
    assert has_element?(view, "#benchmark-import-form")
  end

  test "importing without an open run flashes an error instead of crashing", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    html =
      render_submit(view, "import_result", %{
        "import" => %{
          "subject" => "manual_subject",
          "scenario_slug" => "hardcoded_api_key_python_webhook",
          "payload" => "{}"
        }
      })

    assert html =~ "Import requires an open benchmark run."
    assert has_element?(view, "#benchmark-runner")
  end

  test "index preset buttons fill multi-host subject fields", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    view |> element("#benchmark-preset-copilot-vs-opencode") |> render_click()
    html = render(view)
    assert html =~ "host_comparison_v1"
    assert html =~ "copilot_manual"

    view |> element("#benchmark-preset-full-compare") |> render_click()
    html = render(view)
    assert html =~ "host_comparison_v1"
    assert html =~ "gemini_manual"
    assert html =~ "codex_manual"
    assert html =~ "claude_manual"
  end

  test "multi-select subject dropdown toggles subjects on and off", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    refute has_element?(view, "#benchmark-subjects-input [role='listbox']")

    view
    |> element("#benchmark-subjects-input button[phx-click='toggle_subjects_dropdown']")
    |> render_click()

    assert has_element?(view, "#benchmark-subjects-input [role='listbox']")

    view
    |> element(
      "#benchmark-subjects-input button[role='option'][data-subject-id='controlkeel_proxy']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#benchmark-subjects-input input[name='benchmark[subjects][]'][value='controlkeel_proxy']"
           )

    view
    |> element(
      "#benchmark-subjects-input button[role='option'][data-subject-id='controlkeel_proxy']"
    )
    |> render_click()

    refute has_element?(
             view,
             "#benchmark-subjects-input input[name='benchmark[subjects][]'][value='controlkeel_proxy']"
           )
  end

  test "manually toggling a subject clears the active preset", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    assert has_element?(view, "#benchmark-preset-opencode[aria-pressed='true']")

    view |> element("#benchmark-preset-ck-only") |> render_click()
    assert has_element?(view, "#benchmark-preset-ck-only[aria-pressed='true']")

    view
    |> element("#benchmark-subjects-input button[phx-click='toggle_subjects_dropdown']")
    |> render_click()

    view
    |> element(
      "#benchmark-subjects-input button[role='option'][data-subject-id='controlkeel_proxy']"
    )
    |> render_click()

    refute has_element?(view, "#benchmark-preset-ck-only[aria-pressed='true']")
  end

  test "index renders an empty state when there are no runs", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, benchmarks_path(org, ws))

    assert html =~ "No benchmark runs yet"
  end

  test "show redirects home when the run is not found", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(conn, ~p"/benchmarks/runs/999999")

    assert flash["error"] == "Benchmark run not found."
  end

  test "unknown workspace renders the scope error panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/no-such-org/workspaces/nope/benchmarks")

    assert has_element?(view, "[data-scope-error]")
    refute has_element?(view, "#benchmark-runner")
  end

  test "workspace sidebar lists Benchmarks as the active nav item", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    assert has_element?(
             view,
             "#sidebar-org-nav a[href='#{benchmarks_path(org, ws)}'][aria-current='page']"
           )
  end

  # Running a suite spends money, so the runner is admin/owner only on the
  # workspace page (mirrors the observability benchmark page's gate).
  describe "cloud-mode mutation gating" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    defp cloud_member_conn(org, role) do
      {:ok, user} =
        ControlKeel.Accounts.create_user(%{
          email: "bench-#{role}-#{System.unique_integer([:positive])}@example.com"
        })

      %ControlKeel.Accounts.Membership{}
      |> ControlKeel.Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: role,
        status: "active"
      })
      |> ControlKeel.Repo.insert!()

      build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
    end

    test "viewer cannot see the runner form and crafted run events are refused" do
      {org, ws, _session} = org_bound_session_fixture()
      conn = cloud_member_conn(org, "viewer")

      {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

      # Read-only page: no runner, no presets.
      refute has_element?(view, "#benchmark-runner")
      refute has_element?(view, "#benchmark-preset-opencode")

      html =
        render_click(view, "run", %{
          "benchmark" => %{
            "suite" => "vibe_failures_v1",
            "subjects" => ["controlkeel_validate"],
            "baseline_subject" => "controlkeel_validate"
          }
        })

      assert html =~ "Admin or owner role required."
      assert ControlKeel.Repo.aggregate(ControlKeel.Benchmark.Run, :count, :id) == 0
    end

    test "owner sees the runner form and executing a run lands on the global run page" do
      {org, ws, _session} = org_bound_session_fixture()
      conn = cloud_member_conn(org, "owner")

      {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

      assert has_element?(view, "#benchmark-runner")

      render_submit(
        form(view, "#benchmark-runner",
          benchmark: %{
            "suite" => "vibe_failures_v1",
            "subjects" => ["controlkeel_validate"],
            "baseline_subject" => "controlkeel_validate"
          }
        )
      )

      {path, _flash} = assert_redirect(view)
      assert path =~ "/benchmarks/runs/"
    end
  end

  defp awaiting_import_run_fixture do
    tmp_dir = benchmark_tmp_dir()

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    write_benchmark_subjects!(tmp_dir, [
      %{"id" => "manual_subject", "label" => "Manual Subject", "type" => "manual_import"}
    ])

    original_cwd = File.cwd!()
    File.cd!(tmp_dir)
    on_exit(fn -> File.cd!(original_cwd) end)

    {:ok, run} =
      ControlKeel.Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "manual_subject",
          "baseline_subject" => "manual_subject",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    run
  end

  defp benchmark_tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-benchmarks-live-import-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
