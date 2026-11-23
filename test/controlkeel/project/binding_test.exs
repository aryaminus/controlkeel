defmodule ControlKeel.Project.BindingTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Project.Binding

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

    assert :ok = Binding.ensure_mcp_wrapper(tmp)

    body = File.read!(Binding.mcp_wrapper_path(tmp))

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

    assert :ok = Binding.ensure_mcp_wrapper(tmp)

    body = File.read!(Binding.mcp_wrapper_path(tmp))

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

    assert :ok = Binding.ensure_mcp_wrapper(tmp)

    body = File.read!(Binding.mcp_wrapper_path(tmp))

    case :os.type() do
      {:win32, _} ->
        assert body =~ "CONTROLKEEL_BIN"
        assert body =~ "mcp"

      _ ->
        compile_root = Path.expand("../../..", __DIR__)
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

    assert :ok = Binding.ensure_mcp_wrapper(tmp)

    body = File.read!(Binding.mcp_wrapper_path(tmp))

    case :os.type() do
      {:win32, _} ->
        assert body =~ "CK_PROJECT_ROOT"
        assert body =~ "CONTROLKEEL_BIN"
        assert body =~ "mcp"

      _ ->
        executable = Binding.cli_executable_command()
        assert body =~ "export CK_PROJECT_ROOT="
        assert body =~ executable
        assert body =~ "mcp --project-root"
        refute Binding.burrito_erts_shim?(executable)
    end
  end

  test "cli_executable_command avoids Burrito ERTS shim when PATH has native wrapper" do
    executable = Binding.cli_executable_command()
    assert is_binary(executable)
    refute Binding.burrito_erts_shim?(executable)
  end

  test "resolve_cli_executable scans PATH when given Burrito ERTS shim", %{tmp: tmp} do
    native_dir = Path.join(tmp, "bin")
    File.mkdir_p!(native_dir)
    native = Path.join(native_dir, "controlkeel")
    File.write!(native, "#!/usr/bin/env sh\nexit 0\n")
    File.chmod!(native, 0o755)

    old_path = System.get_env("PATH") || ""
    System.put_env("PATH", native_dir <> ":" <> old_path)
    on_exit(fn -> System.put_env("PATH", old_path) end)

    shim =
      Path.join(tmp, ".burrito/controlkeel_erts-15.2.7.2_0.3.47/bin/controlkeel")

    File.mkdir_p!(Path.dirname(shim))
    File.write!(shim, "#!/usr/bin/env sh\nexit 0\n")
    File.chmod!(shim, 0o755)

    resolved = Binding.resolve_cli_executable(shim)

    assert resolved == native
    refute Binding.burrito_erts_shim?(resolved)
  end

  test "mcp_wrapper_cli_runnable? flags Burrito ERTS shim default target", %{tmp: tmp} do
    File.write!(Path.join(tmp, "README.md"), "not a controlkeel app")
    assert :ok = Binding.ensure_mcp_wrapper(tmp)

    shim =
      "/tmp/.burrito/controlkeel_erts-15.2.7.2_0.3.47/bin/controlkeel"

    broken =
      File.read!(Binding.mcp_wrapper_path(tmp))
      |> String.replace(Binding.cli_executable_command(), shim)

    File.write!(Binding.mcp_wrapper_path(tmp), broken)

    refute Binding.mcp_wrapper_cli_runnable?(tmp)
  end

  test "dev_or_build_path? flags dev/build artifacts but not installed binaries" do
    # Empty/nil resolve to a dev fallback (bare command name on PATH).
    assert Binding.dev_or_build_path?("")
    assert Binding.dev_or_build_path?(nil)

    # Dev/build artifact paths that must not be baked into a shipped wrapper.
    assert Binding.dev_or_build_path?("/repo/_build/prod/rel/controlkeel/bin/controlkeel")

    assert Binding.dev_or_build_path?("/home/u/.burrito/controlkeel_erts-15/bin/controlkeel")

    assert Binding.dev_or_build_path?("/opt/app/erts-15.2/bin/controlkeel")
    assert Binding.dev_or_build_path?("/repo/deps/controlkeel/controlkeel")
    assert Binding.dev_or_build_path?("/usr/local/bin/mix")

    # Installed/native locations and bare names stay as-is.
    refute Binding.dev_or_build_path?("controlkeel")
    refute Binding.dev_or_build_path?("/usr/local/bin/controlkeel")
    refute Binding.dev_or_build_path?("/opt/homebrew/bin/controlkeel")
  end

  describe "mcp_command_spec/2 portable mode" do
    # Regression: a project-specific absolute wrapper path must never be written
    # into a global/shared host config. The wrapper can live in a temp or moved
    # folder and break MCP for every project sharing the global config.
    test "portable: true never returns the project wrapper path", %{tmp: tmp} do
      # Install a wrapper so the non-portable branch would pick it up.
      assert :ok = Binding.ensure_mcp_wrapper(tmp)

      spec = Binding.mcp_command_spec(tmp, portable: true)

      wrapper = Binding.mcp_wrapper_path(tmp)

      refute spec[:command] == wrapper
      assert spec[:args] == ["mcp"]
      assert String.ends_with?(spec[:command], "controlkeel")
      refute Binding.burrito_erts_shim?(spec[:command])
    end

    test "portable: false (default) still uses the wrapper when present", %{tmp: tmp} do
      assert :ok = Binding.ensure_mcp_wrapper(tmp)

      spec = Binding.mcp_command_spec(tmp)
      wrapper = Binding.mcp_wrapper_path(tmp)

      assert spec[:command] == wrapper
      assert spec[:args] == []
    end

    test "default falls back to installed CLI when no wrapper exists", %{tmp: tmp} do
      spec = Binding.mcp_command_spec(tmp)

      refute spec[:command] == Binding.mcp_wrapper_path(tmp)
      # macOS may canonicalize /var -> /private/var, so compare by basename.
      [mcp_flag, root_flag, resolved_root] = spec[:args]
      assert mcp_flag == "mcp"
      assert root_flag == "--project-root"
      assert Path.basename(resolved_root) == Path.basename(tmp)
      assert String.ends_with?(spec[:command], "controlkeel")
    end
  end

  describe "ensure_gitignore/3" do
    test "creates a managed block covering controlkeel/ and .controlkeel/", %{tmp: tmp} do
      assert :ok = Binding.ensure_gitignore(tmp)

      contents = File.read!(Path.join(tmp, ".gitignore"))
      assert contents =~ "# ControlKeel managed"
      assert contents =~ "/controlkeel/"
      # The verified bug: .controlkeel/tool_usage.json must now be ignored.
      assert contents =~ "/.controlkeel/"
    end

    test "preserves existing user content and is idempotent", %{tmp: tmp} do
      path = Path.join(tmp, ".gitignore")
      File.write!(path, "node_modules/\n/_build/\n")

      assert :ok = Binding.ensure_gitignore(tmp)
      first = File.read!(path)
      assert first =~ "node_modules/"
      assert first =~ "/_build/"
      assert first =~ "/.controlkeel/"

      # Running again must not change the file or duplicate the block.
      assert :ok = Binding.ensure_gitignore(tmp)
      assert File.read!(path) == first

      [_, _] = String.split(first, "# ControlKeel managed", parts: 2)
    end

    test "merges extra entries (e.g. project-scope agent dirs) into the block", %{tmp: tmp} do
      assert :ok = Binding.ensure_gitignore(tmp, ["/.windsurf/", "/.cline/"])

      contents = File.read!(Path.join(tmp, ".gitignore"))
      assert contents =~ "/.windsurf/"
      assert contents =~ "/.cline/"
      assert contents =~ "/.controlkeel/"

      # A later call without the extras accumulates: previously-managed dirs
      # persist (so attaching agent B doesn't drop agent A's entry) and no
      # duplicate managed block is left behind.
      assert :ok = Binding.ensure_gitignore(tmp)
      refreshed = File.read!(Path.join(tmp, ".gitignore"))
      assert refreshed =~ "/.windsurf/"
      assert refreshed =~ "/.cline/"
      assert [_, _] = String.split(refreshed, "# ControlKeel managed", parts: 2)
    end

    test "skips entries already covered by an ignored parent directory", %{tmp: tmp} do
      File.write!(Path.join(tmp, ".gitignore"), "/.claude/\n")

      assert :ok =
               Binding.ensure_gitignore(tmp, [
                 "/.claude/settings.json",
                 "/.claude/agents/",
                 "/.cline/"
               ])

      contents = File.read!(Path.join(tmp, ".gitignore"))
      refute contents =~ "/.claude/settings.json"
      refute contents =~ "/.claude/agents/"
      assert contents =~ "/.cline/"
      assert contents =~ "/.claude/\n"
    end
  end
end
