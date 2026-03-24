defmodule ControlKeel.LocalProjectTest do
  use ControlKeel.DataCase

  alias ControlKeel.LocalProject
  alias ControlKeel.ProjectBinding

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-local-project-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    home_dir = Path.join(tmp_dir, "home")
    File.mkdir_p!(home_dir)

    previous_home = System.get_env("HOME")
    previous_ck_home = System.get_env("CONTROLKEEL_HOME")

    System.put_env("HOME", home_dir)
    System.put_env("CONTROLKEEL_HOME", home_dir)

    on_exit(fn ->
      restore_env("HOME", previous_home)
      restore_env("CONTROLKEEL_HOME", previous_ck_home)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir, home_dir: home_dir}
  end

  test "load_or_bootstrap creates a project binding in writable repos", %{tmp_dir: tmp_dir} do
    project_root = Path.join(tmp_dir, "project")
    File.mkdir_p!(project_root)

    assert {:ok, binding, session, :bootstrapped_project} =
             LocalProject.load_or_bootstrap(project_root, %{"agent" => "codex"},
               ephemeral_ok: true
             )

    assert binding["project_root"] ==
             ProjectBinding.bootstrap_summary(project_root)["project_root"]

    assert session.id == binding["session_id"]
    assert binding["bootstrap"]["mode"] == "project"
    assert File.exists?(Path.join(project_root, "controlkeel/project.json"))
    assert File.exists?(Path.join(project_root, "controlkeel/bin/controlkeel-mcp"))
    assert {:ok, _effective, :project} = ProjectBinding.read_effective(project_root)
  end

  test "load_or_bootstrap falls back to an ephemeral binding when the repo is not writable", %{
    tmp_dir: tmp_dir
  } do
    project_root = Path.join(tmp_dir, "readonly-project")
    File.mkdir_p!(project_root)
    File.chmod!(project_root, 0o555)

    on_exit(fn ->
      File.chmod(project_root, 0o755)
    end)

    assert {:ok, binding, session, :bootstrapped_ephemeral} =
             LocalProject.load_or_bootstrap(project_root, %{"agent" => "claude"},
               ephemeral_ok: true
             )

    assert binding["project_root"] ==
             ProjectBinding.bootstrap_summary(project_root)["project_root"]

    assert session.id == binding["session_id"]
    assert binding["bootstrap"]["mode"] == "ephemeral"
    refute File.exists?(Path.join(project_root, "controlkeel/project.json"))
    assert {:ok, _effective, :ephemeral} = ProjectBinding.read_effective(project_root)
    assert File.exists?(ProjectBinding.ephemeral_path(project_root))
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
