defmodule ControlKeelWeb.BenchmarksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  defp benchmarks_path(org, ws), do: "/#{org.slug}/workspaces/#{ws.slug}/benchmarks"

  defp benchmark_run_path(org, ws, run_id),
    do: "/#{org.slug}/workspaces/#{ws.slug}/benchmarks/runs/#{run_id}"

  test "workspace benchmarks renders the runner and launches a benchmark run", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    _existing_run = benchmark_run_fixture()

    {:ok, view, _html} = live(conn, benchmarks_path(org, ws))

    assert has_element?(view, "#workspace-benchmarks-page")
    assert has_element?(view, "#benchmark-runner button[type='submit']")
    assert has_element?(view, "#benchmark-preset-opencode")
    assert has_element?(view, "#benchmark-subjects-input")
    assert has_element?(view, "#benchmark-baseline-input")
    assert has_element?(view, "a[href='/docs/benchmarks']")

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

  test "preset buttons fill subject fields", %{conn: conn} do
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

  test "runner surfaces configured external subjects", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

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

    {:ok, _view, html} = live(conn, benchmarks_path(org, ws))

    assert html =~ "OpenCode Manual Import (external)"
  end

  test "run detail renders the persisted scenario matrix", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    run =
      benchmark_run_fixture(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hr_discriminatory_candidate_filter,legal_privileged_memo_logging"
      })

    {:ok, view, html} = live(conn, benchmark_run_path(org, ws, run.id))

    assert html =~ "Scenario matrix"
    assert html =~ "Catch rate"
    assert html =~ "Promotion integrity"
    assert has_element?(view, "#scenario-hr_discriminatory_candidate_filter")

    assert has_element?(
             view,
             "a[href=\"/api/v1/benchmarks/runs/#{run.id}/export?format=csv\"]"
           )

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

  test "run detail renders the comparison panel for a multi-subject run", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    run =
      benchmark_run_fixture(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hr_discriminatory_candidate_filter,legal_privileged_memo_logging"
      })

    {:ok, view, html} = live(conn, benchmark_run_path(org, ws, run.id))

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

  test "run detail renders an empty comparison state for a single-subject run", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    run = benchmark_run_fixture()

    {:ok, view, html} = live(conn, benchmark_run_path(org, ws, run.id))

    assert has_element?(view, "#comparison-panel")
    assert html =~ "No comparable subjects"
    refute has_element?(view, "#comparison-subject-controlkeel_validate")
    refute has_element?(view, "#comparison-chart")
  end

  test "run detail renders the import panel for an awaiting-import run", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    run = awaiting_import_run_fixture()

    {:ok, view, html} = live(conn, benchmark_run_path(org, ws, run.id))

    assert has_element?(view, "#import-panel")
    assert has_element?(view, "#import-slots")
    assert has_element?(view, "#import-slot-manual_subject-hardcoded_api_key_python_webhook")
    assert has_element?(view, "#benchmark-import-form")
    assert html =~ "Manual Subject"
  end

  test "import completes a run through the import panel", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    run = awaiting_import_run_fixture()

    {:ok, view, _html} = live(conn, benchmark_run_path(org, ws, run.id))

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

  test "import panel flashes an error for invalid JSON without navigating", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    run = awaiting_import_run_fixture()

    {:ok, view, _html} = live(conn, benchmark_run_path(org, ws, run.id))

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

  test "run detail redirects to the workspace benchmarks index when the run is not found", %{
    conn: conn
  } do
    {org, ws, _session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             live(conn, benchmark_run_path(org, ws, 999_999))

    assert to == benchmarks_path(org, ws)
    assert flash["error"] == "Benchmark run not found."
  end

  describe "benchmark run access (cloud mode)" do
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

    setup %{conn: conn} do
      suffix = System.unique_integer([:positive])

      {:ok, org} =
        Accounts.create_org(%{name: "BenchCo #{suffix}", slug: "benchco-#{suffix}"})

      {:ok, admin} =
        Accounts.create_user(%{email: "bench-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} =
        Accounts.create_user(%{email: "bench-viewer-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: viewer.id,
        org_id: org.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})

      {:ok, conn: conn, org: org, workspace: workspace, admin: admin, viewer: viewer}
    end

    test "viewers see a role notice instead of the runner and are denied run events", %{
      conn: conn,
      org: org,
      workspace: workspace,
      viewer: viewer
    } do
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})

      {:ok, view, _html} = live(conn, benchmarks_path(org, workspace))

      refute has_element?(view, "#benchmark-runner-panel")
      refute has_element?(view, "#benchmark-runner")
      assert has_element?(view, "#benchmarks-viewer-notice")

      denied_html = render_click(view, "run", %{"benchmark" => %{}})
      assert denied_html =~ "Admin or owner role required."
    end

    test "viewers see awaiting-import slots but no import form on a run page", %{
      conn: conn,
      org: org,
      workspace: workspace,
      viewer: viewer
    } do
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})
      run = awaiting_import_run_fixture()

      {:ok, view, _html} = live(conn, benchmark_run_path(org, workspace, run.id))

      assert has_element?(view, "#import-panel")
      assert has_element?(view, "#import-slots")
      refute has_element?(view, "#benchmark-import-form")
      assert render(view) =~ "Admin or owner role required to import results."
    end

    test "admins see the runner", %{
      conn: conn,
      org: org,
      workspace: workspace,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})

      {:ok, view, _html} = live(conn, benchmarks_path(org, workspace))

      assert has_element?(view, "#benchmark-runner-panel")
      assert has_element?(view, "#benchmark-runner")
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
