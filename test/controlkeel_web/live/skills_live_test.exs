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
    assert has_element?(view, "#install-channel-homebrew")
    assert has_element?(view, "#copy-install-npm")
    assert has_element?(view, "#skills-target-matrix")
    assert has_element?(view, "#skills-agent-matrix")
    assert has_element?(view, "#skill-controlkeel-governance")
    assert has_element?(view, "#agent-claude-code")
    assert has_element?(view, "#agent-cline")
    assert has_element?(view, "#copy-agent-claude-code")
    assert has_element?(view, "#agent-open-swe")
    assert has_element?(view, "#agent-devin")
    assert has_element?(view, "#agent-vllm")

    render_click(element(view, "#skill-controlkeel-governance"))
    assert render(view) =~ "Required CK MCP tools"
    assert render(view) =~ "controlkeel attach claude-code"
    assert render(view) =~ "Attachable client"
    assert render(view) =~ "Headless runtime"

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
end
