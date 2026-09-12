defmodule ControlKeel.CLI.ResolveProjectRootTest do
  use ExUnit.Case, async: true

  alias ControlKeel.CLI

  @tag :tmp_dir
  test "explicit --project-root option is resolved, not used raw", %{tmp_dir: tmp_dir} do
    # A trailing-slash explicit root must be normalized via Root.resolve/1,
    # not returned verbatim.
    raw = tmp_dir <> "/"

    resolved =
      CLI.resolve_project_root([project_root: raw], "/Users/aryaminus/Developer/idea")

    assert resolved == ControlKeel.Project.Root.resolve(raw)
    refute String.ends_with?(resolved, "/")
  end

  @tag :tmp_dir
  test "falls back to resolving the positional project root", %{tmp_dir: tmp_dir} do
    assert CLI.resolve_project_root([], tmp_dir) ==
             ControlKeel.Project.Root.resolve(tmp_dir)
  end
end
