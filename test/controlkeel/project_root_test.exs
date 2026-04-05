defmodule ControlKeel.ProjectRootTest do
  use ExUnit.Case, async: true

  alias ControlKeel.ProjectRoot

  test "resolve walks up to the nearest project marker" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-project-root-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib/demo"))
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Demo.MixProject do\nend\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert ProjectRoot.resolve(Path.join(tmp_dir, "lib/demo")) == ProjectRoot.resolve(tmp_dir)
  end

  test "resolve falls back to the provided directory when no marker exists" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-project-root-none-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert ProjectRoot.resolve(tmp_dir) == ProjectRoot.resolve(Path.expand(tmp_dir))
  end
end
