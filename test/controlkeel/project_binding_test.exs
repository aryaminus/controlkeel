defmodule ControlKeel.ProjectBindingTest do
  use ExUnit.Case, async: true

  alias ControlKeel.ProjectBinding

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "ck-proj-binding-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  test "ensure_mcp_wrapper installs stdio launcher inside ControlKeel source checkout", %{
    tmp: tmp
  } do
    File.mkdir_p!(Path.join(tmp, "lib/controlkeel"))
    File.write!(Path.join(tmp, "mix.exs"), "%{}, []")

    File.write!(
      Path.join(tmp, "lib/controlkeel/application.ex"),
      "defmodule CK.Application, do: :ok"
    )

    assert :ok = ProjectBinding.ensure_mcp_wrapper(tmp)

    body = File.read!(ProjectBinding.mcp_wrapper_path(tmp))

    case :os.type() do
      {:win32, _} ->
        assert body =~ "CONTROLKEEL_BIN"
        assert body =~ "mcp"
        assert body =~ "--project-root"

      _ ->
        assert body =~ "exec_mix_ck_mcp_filtered"
        assert body =~ "<&0"
        assert body =~ "awk"
    end
  end

  test "ensure_mcp_wrapper installs minimal controlkeel launcher for other repos", %{tmp: tmp} do
    File.write!(Path.join(tmp, "README.md"), "not a controlkeel app")

    assert :ok = ProjectBinding.ensure_mcp_wrapper(tmp)

    body = File.read!(ProjectBinding.mcp_wrapper_path(tmp))

    case :os.type() do
      {:win32, _} ->
        assert body =~ "mcp"
        assert body =~ "--project-root"

      _ ->
        refute body =~ "exec_mix_ck_mcp_filtered"
        assert body =~ "controlkeel"
        assert body =~ "mcp"
        assert body =~ "--project-root"
    end
  end

  test "ensure_mcp_wrapper launcher uses resolved controlkeel path outside source tree", %{
    tmp: tmp
  } do
    File.write!(Path.join(tmp, "README.md"), "not a controlkeel app")

    assert :ok = ProjectBinding.ensure_mcp_wrapper(tmp)

    body = File.read!(ProjectBinding.mcp_wrapper_path(tmp))

    case :os.type() do
      {:win32, _} ->
        assert body =~ "CONTROLKEEL_BIN"
        assert body =~ "mcp"

      _ ->
        executable = System.find_executable("controlkeel") || "controlkeel"
        assert body =~ executable
        assert body =~ "mcp --project-root"
    end
  end
end
