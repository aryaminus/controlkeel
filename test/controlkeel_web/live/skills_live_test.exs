defmodule ControlKeelWeb.SkillsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "skills studio renders the catalog and can export and install bundles", %{conn: conn} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-skills-live-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, view, html} = live(conn, ~p"/skills")

    assert html =~ "Skills Studio"
    assert has_element?(view, "#skills-project-form")
    assert has_element?(view, "#skills-action-form")
    assert has_element?(view, "#skills-export-button")
    assert has_element?(view, "#skills-install-button")
    assert has_element?(view, "#skills-target-matrix")
    assert has_element?(view, "#skills-list")
    assert has_element?(view, "#targets-list")
    assert has_element?(view, "#skill-controlkeel-governance")

    assert html =~ "Bootstrap"
    assert html =~ "Duplicate copies"

    render_click(element(view, "#skill-controlkeel-governance"))
    assert render(view) =~ "Required CK MCP tools"

    assert has_element?(view, "#skills-list article")
    assert has_element?(view, "#skills-target-matrix tbody tr")

    render_change(view, "search_skills", %{"skill_search" => "governance"})
    assert render(view) =~ "controlkeel-governance"

    render_change(view, "search_targets", %{"target_search" => "claude"})
    assert render(view) =~ "Claude Code"

    render_change(view, "search_skills", %{"skill_search" => "zzzznotexist"})
    refute has_element?(view, "#skills-list article")

    render_change(view, "search_targets", %{"target_search" => ""})
    assert has_element?(view, "#skills-target-matrix tbody tr")

    render_submit(form(view, "#skills-project-form", project: %{"project_root" => tmp_dir}))

    export_html = render_click(element(view, "#skills-export-button"))
    assert export_html =~ "Exported open-standard bundle"

    assert File.exists?(
             Path.join(
               tmp_dir,
               "controlkeel/dist/open-standard/skills/controlkeel-governance/SKILL.md"
             )
           )

    render_change(
      form(view, "#skills-action-form",
        skill_action: %{"target" => "claude-standalone", "scope" => "project"}
      )
    )

    install_html = render_click(element(view, "#skills-install-button"))
    assert install_html =~ "Installed claude-standalone skills"
    assert File.exists?(Path.join(tmp_dir, ".claude/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".claude/agents/controlkeel-operator.md"))
  end

  test "prune flow previews and removes only user-level duplicates", %{conn: conn} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-skills-prune-live-#{System.unique_integer([:positive])}"
      )

    home_dir = Path.join(tmp_dir, "home")
    project_root = Path.join(tmp_dir, "project")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(home_dir)
    File.mkdir_p!(project_root)

    previous_home = System.get_env("HOME")
    previous_ck_home = System.get_env("CONTROLKEEL_HOME")
    previous_trust = System.get_env("CONTROLKEEL_TRUST_PROJECT_SKILLS")

    System.put_env("HOME", home_dir)
    System.put_env("CONTROLKEEL_HOME", home_dir)
    System.put_env("CONTROLKEEL_TRUST_PROJECT_SKILLS", "1")

    on_exit(fn ->
      restore_env("HOME", previous_home)
      restore_env("CONTROLKEEL_HOME", previous_ck_home)
      restore_env("CONTROLKEEL_TRUST_PROJECT_SKILLS", previous_trust)
      File.rm_rf!(tmp_dir)
    end)

    source =
      :code.priv_dir(:controlkeel)
      |> to_string()
      |> Path.join("skills/controlkeel-governance/SKILL.md")
      |> File.read!()

    user_skill = Path.join(home_dir, ".agents/skills/controlkeel-governance/SKILL.md")
    File.mkdir_p!(Path.dirname(user_skill))
    File.write!(user_skill, source)

    project_skill = Path.join(project_root, ".claude/skills/controlkeel-governance/SKILL.md")
    File.mkdir_p!(Path.dirname(project_skill))
    File.write!(project_skill, source)

    {:ok, view, _html} = live(conn, ~p"/skills")

    render_submit(form(view, "#skills-project-form", project: %{"project_root" => project_root}))

    assert has_element?(view, "#skills-prune-button")

    render_click(element(view, "#skills-prune-button"))

    assert has_element?(view, "#prune-duplicates-modal")
    modal_html = element(view, "#prune-duplicates-modal") |> render()
    assert modal_html =~ "Will be removed"
    assert modal_html =~ ".claude/skills/"
    assert File.exists?(user_skill)

    result_html = render_click(element(view, "#skills-prune-confirm"))

    assert result_html =~ "Pruned 1 user-level duplicate skill copy"
    refute File.exists?(Path.dirname(user_skill))
    assert File.exists?(project_skill)
    refute has_element?(view, "#prune-duplicates-modal")
  end

  test "token audit renders sortable per-mode tables", %{conn: conn} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-skills-audit-live-#{System.unique_integer([:positive])}"
      )

    home_dir = Path.join(tmp_dir, "home")
    project_root = Path.join(tmp_dir, "project")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(home_dir)
    File.mkdir_p!(Path.join(project_root, ".agents/skills/aaa-skill"))
    File.mkdir_p!(Path.join(project_root, ".agents/skills/zzz-skill"))

    previous_home = System.get_env("HOME")
    previous_ck_home = System.get_env("CONTROLKEEL_HOME")

    System.put_env("HOME", home_dir)
    System.put_env("CONTROLKEEL_HOME", home_dir)

    on_exit(fn ->
      restore_env("HOME", previous_home)
      restore_env("CONTROLKEEL_HOME", previous_ck_home)
      File.rm_rf!(tmp_dir)
    end)

    File.write!(Path.join(project_root, "AGENTS.md"), String.duplicate("word ", 60))

    File.write!(
      Path.join(project_root, ".agents/skills/aaa-skill/SKILL.md"),
      "---\nname: aaa-skill\ndescription: Small audit fixture skill.\n---\n# A\nbody\n"
    )

    File.write!(
      Path.join(project_root, ".agents/skills/zzz-skill/SKILL.md"),
      "---\nname: zzz-skill\ndescription: Larger audit fixture skill.\n---\n# Z\n" <>
        String.duplicate("padding word ", 120)
    )

    {:ok, view, _html} = live(conn, ~p"/skills")

    render_submit(form(view, "#skills-project-form", project: %{"project_root" => project_root}))

    rules_html = render_click(element(view, "#audit-mode-rules"))
    assert has_element?(view, "#audit-rules-table tbody tr")
    assert rules_html =~ "AGENTS.md"
    assert rules_html =~ "Rule files"

    render_click(element(view, "#audit-mode-skills"))
    assert has_element?(view, "#audit-skills-table tbody tr")
    skills_html = render(view)
    assert skills_html =~ "aaa-skill"
    assert skills_html =~ "zzz-skill"

    default_sorted = element(view, "#audit-skills-table") |> render()
    assert Regex.match?(~r/zzz-skill.*aaa-skill/s, default_sorted)

    name_desc = render_click(element(view, "#audit-skills-sort-name"))
    assert Regex.match?(~r/zzz-skill.*aaa-skill/s, name_desc)

    name_asc = render_click(element(view, "#audit-skills-sort-name"))
    assert Regex.match?(~r/aaa-skill.*zzz-skill/s, name_asc)

    tools_html = render_click(element(view, "#audit-mode-tools"))
    assert has_element?(view, "#audit-tools-table tbody tr")
    assert has_element?(view, "#audit-groups-table tbody tr")
    assert tools_html =~ "CK_TOOL_GROUPS"
    assert tools_html =~ "Group savings"

    full_html = render_click(element(view, "#audit-mode-full"))
    assert has_element?(view, "#audit-rules-table tbody tr")
    assert has_element?(view, "#audit-skills-table tbody tr")
    assert has_element?(view, "#audit-download-link")
    assert full_html =~ "Download JSON"

    link_html = element(view, "#audit-download-link") |> render()
    assert link_html =~ "download=1"
    assert link_html =~ "mode=full"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
