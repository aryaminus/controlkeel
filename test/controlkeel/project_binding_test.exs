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

  test "ensure_mcp_wrapper launcher falls back to source launcher when binary missing", %{
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
        compile_root = Path.expand("../..", __DIR__)
        launcher_path = Path.join(compile_root, "bin/controlkeel-mcp")

        assert body =~ "SOURCE_LAUNCHER"
        assert body =~ launcher_path
        assert body =~ "CK_PROJECT_ROOT"
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
        assert body =~ "CK_PROJECT_ROOT"
        assert body =~ "CONTROLKEEL_BIN"
        assert body =~ "mcp"

      _ ->
        executable = System.find_executable("controlkeel") || "controlkeel"
        assert body =~ "export CK_PROJECT_ROOT="
        assert body =~ executable
        assert body =~ "mcp --project-root"
    end
  end
end
