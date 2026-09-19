defmodule ControlKeelWeb.DeployReviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-deploy-review-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "config"))

    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      defp deps, do: [{:phoenix, "~> 1.7"}]
    end
    """)

    File.write!(Path.join(tmp_dir, "config/config.exs"), "import Config")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  defp deploy_session(tmp_dir) do
    {org, ws, session} = org_bound_session_fixture()
    {:ok, session} = Mission.attach_session_runtime_context(session, %{"project_root" => tmp_dir})
    {org, ws, session}
  end

  defp session_with_no_local_project_binding do
    _binding_id_guard = session_fixture()
    org_bound_session_fixture()
  end

  test "redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/acme/workspaces/core/sessions/999999/deploy-review")
  end

  test "shows unavailable notice when the project root cannot be resolved", %{conn: conn} do
    {org, ws, session} = session_with_no_local_project_binding()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    assert html =~ "not available on this machine"
    assert html =~ "controlkeel deploy analyze"
  end

  test "renders stack overview for a resolvable project", %{conn: conn, tmp_dir: tmp_dir} do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    assert html =~ "Detected stack"
    assert html =~ "Phoenix"
    assert html =~ "Recommended platforms"
    assert html =~ "Fly.io"
  end

  test "computes tier options from HostingCost, including tiers the old UI missed", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    costs_html =
      render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"costs\"]"))

    assert costs_html =~ "Standard 2X"
    assert costs_html =~ "Dedicated"
    assert costs_html =~ "Managed XL"
  end

  test "estimate costs renders per-platform monthly totals", %{conn: conn, tmp_dir: tmp_dir} do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"costs\"]"))

    render_change(element(view, "select[phx-change=\"select_tier\"]"), %{"tier" => "standard_2x"})

    estimates_html = render_click(element(view, "button[phx-click=\"estimate_costs\"]"))

    assert estimates_html =~ "Best fit"
    assert estimates_html =~ "/mo"
  end

  test "rejects unknown tier and db tier values", %{conn: conn, tmp_dir: tmp_dir} do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"costs\"]"))

    html =
      render_change(element(view, "select[phx-change=\"select_tier\"]"), %{"tier" => "bogus"})

    assert html =~ "Unknown compute tier."

    html =
      render_change(element(view, "select[phx-change=\"select_db_tier\"]"), %{
        "db_tier" => "bogus"
      })

    assert html =~ "Unknown database tier."
  end

  test "preview, arm, and confirm write files to the project root", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"files\"]"))

    preview_html = render_click(element(view, "button[phx-click=\"preview_files\"]"))

    assert preview_html =~ "Skipped (dry run)"
    refute File.exists?(Path.join(tmp_dir, "Dockerfile"))

    armed_html = render_click(element(view, "button[phx-click=\"arm_write\"]"))
    assert armed_html =~ "Confirm write"

    written_html = render_click(element(view, "button[phx-click=\"confirm_write_files\"]"))

    assert written_html =~ "Wrote 4 files"
    assert written_html =~ "Written"
    assert File.exists?(Path.join(tmp_dir, "Dockerfile"))
    assert File.exists?(Path.join(tmp_dir, ".github/workflows/ci.yml"))
  end

  test "second write skips existing files with an accurate label", %{conn: conn, tmp_dir: tmp_dir} do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"files\"]"))
    render_click(element(view, "button[phx-click=\"preview_files\"]"))
    render_click(element(view, "button[phx-click=\"arm_write\"]"))
    render_click(element(view, "button[phx-click=\"confirm_write_files\"]"))

    render_click(element(view, "button[phx-click=\"preview_files\"]"))
    render_click(element(view, "button[phx-click=\"arm_write\"]"))
    rewritten_html = render_click(element(view, "button[phx-click=\"confirm_write_files\"]"))

    assert rewritten_html =~ "skipped 4 (already existed)"
    assert rewritten_html =~ "Skipped (already exists)"
    refute rewritten_html =~ "Skipped (dry run)"
  end

  test "write failures surface per-file errors instead of claiming success", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    {org, ws, session} = deploy_session(tmp_dir)
    File.write!(Path.join(tmp_dir, ".github"), "not a directory")

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"files\"]"))
    render_click(element(view, "button[phx-click=\"preview_files\"]"))
    render_click(element(view, "button[phx-click=\"arm_write\"]"))

    failed_html = render_click(element(view, "button[phx-click=\"confirm_write_files\"]"))

    assert failed_html =~ "failed 1"
    assert failed_html =~ "Write failed"
    assert failed_html =~ "Wrote 3"
    refute File.exists?(Path.join(tmp_dir, ".github/workflows/ci.yml"))
  end

  test "guides tab renders DNS, migration, and scaling guides", %{conn: conn, tmp_dir: tmp_dir} do
    {org, ws, session} = deploy_session(tmp_dir)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/deploy-review"))

    guides_html =
      render_click(element(view, "button[phx-click=\"set_tab\"][phx-value-tab=\"guides\"]"))

    assert guides_html =~ "DNS &amp; SSL setup"
    assert guides_html =~ "Database migrations"
    assert guides_html =~ "Scaling"
  end
end
