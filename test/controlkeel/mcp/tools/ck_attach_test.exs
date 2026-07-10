defmodule ControlKeel.MCP.Tools.CkAttachTest do
  use ExUnit.Case, async: false

  alias ControlKeel.MCP.Tools.CkAttach

  describe "argument validation" do
    test "rejects missing host" do
      assert {:error, {:invalid_arguments, message}} = CkAttach.call(%{})
      assert message =~ "host is required"
    end

    test "rejects non-object arguments" do
      assert {:error, {:invalid_arguments, _}} = CkAttach.call("not a map")
    end

    test "rejects unknown host with helpful message" do
      assert {:error, {:invalid_arguments, message}} = CkAttach.call(%{"host" => "vim"})
      assert message =~ "unknown host: vim"
      assert message =~ "claude-code"
    end

    test "rejects empty host string" do
      assert {:error, {:invalid_arguments, _}} = CkAttach.call(%{"host" => ""})
    end

    test "rejects invalid scopes" do
      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{"host" => "opencode", "scope" => "workspace"})

      assert message =~ "invalid scope"
    end

    test "rejects project roots outside the MCP project boundary" do
      boundary = Path.join(System.tmp_dir!(), "ck-attach-boundary")
      outside = Path.join(System.tmp_dir!(), "ck-attach-outside")
      File.mkdir_p!(boundary)
      File.mkdir_p!(outside)
      previous = System.get_env("CK_PROJECT_ROOT")
      System.put_env("CK_PROJECT_ROOT", boundary)

      on_exit(fn ->
        if previous,
          do: System.put_env("CK_PROJECT_ROOT", previous),
          else: System.delete_env("CK_PROJECT_ROOT")

        File.rm_rf!(boundary)
        File.rm_rf!(outside)
      end)

      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{"host" => "opencode", "project_root" => outside})

      assert message =~ "must stay within"
    end

    test "rejects a project root symlink that escapes the boundary" do
      boundary =
        Path.join(System.tmp_dir!(), "ck-attach-boundary-#{System.unique_integer([:positive])}")

      outside =
        Path.join(System.tmp_dir!(), "ck-attach-outside-#{System.unique_integer([:positive])}")

      link = Path.join(boundary, "linked-project")
      File.mkdir_p!(boundary)
      File.mkdir_p!(outside)
      File.ln_s!(outside, link)
      previous = System.get_env("CK_PROJECT_ROOT")
      System.put_env("CK_PROJECT_ROOT", boundary)

      on_exit(fn ->
        if previous,
          do: System.put_env("CK_PROJECT_ROOT", previous),
          else: System.delete_env("CK_PROJECT_ROOT")

        File.rm_rf!(boundary)
        File.rm_rf!(outside)
      end)

      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{"host" => "opencode", "project_root" => link})

      assert message =~ "must stay within"
    end

    test "rejects an intermediate symlink that escapes the boundary" do
      boundary =
        Path.join(System.tmp_dir!(), "ck-attach-boundary-#{System.unique_integer([:positive])}")

      outside =
        Path.join(System.tmp_dir!(), "ck-attach-outside-#{System.unique_integer([:positive])}")

      File.mkdir_p!(boundary)
      File.mkdir_p!(outside)

      # Create an intermediate symlink: boundary/linkdir -> outside
      # Then request boundary/linkdir/sub, which resolves to outside/sub
      File.ln_s!(outside, Path.join(boundary, "linkdir"))
      target = Path.join([boundary, "linkdir", "sub"])
      File.mkdir_p!(target)

      previous = System.get_env("CK_PROJECT_ROOT")
      System.put_env("CK_PROJECT_ROOT", boundary)

      on_exit(fn ->
        if previous,
          do: System.put_env("CK_PROJECT_ROOT", previous),
          else: System.delete_env("CK_PROJECT_ROOT")

        File.rm_rf!(boundary)
        File.rm_rf!(outside)
      end)

      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{"host" => "opencode", "project_root" => target})

      assert message =~ "must stay within"
    end

    test "rejects relative project roots" do
      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{"host" => "opencode", "project_root" => "../escape"})

      assert message =~ "absolute path"
    end

    test "rejects a nonexistent project root for user scope" do
      boundary = temp_path("user-boundary")
      File.mkdir_p!(boundary)
      previous = System.get_env("CK_PROJECT_ROOT")
      System.put_env("CK_PROJECT_ROOT", boundary)

      on_exit(fn -> restore_project_root(previous, [boundary]) end)

      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{
                 "host" => "claude-code",
                 "scope" => "user",
                 "project_root" => Path.join(boundary, "missing")
               })

      assert message =~ "existing directory"
    end

    test "rejects a user-scope project outside the boundary" do
      boundary = temp_path("user-boundary")
      outside = temp_path("user-outside")
      File.mkdir_p!(boundary)
      File.mkdir_p!(outside)
      previous = System.get_env("CK_PROJECT_ROOT")
      System.put_env("CK_PROJECT_ROOT", boundary)

      on_exit(fn -> restore_project_root(previous, [boundary, outside]) end)

      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{
                 "host" => "claude-code",
                 "scope" => "user",
                 "project_root" => outside
               })

      assert message =~ "must stay within"
    end

    test "rejects a user-scope project symlink that escapes the boundary" do
      boundary = temp_path("user-boundary")
      outside = temp_path("user-outside")
      link = Path.join(boundary, "linked-project")
      File.mkdir_p!(boundary)
      File.mkdir_p!(outside)
      File.ln_s!(outside, link)
      previous = System.get_env("CK_PROJECT_ROOT")
      System.put_env("CK_PROJECT_ROOT", boundary)

      on_exit(fn -> restore_project_root(previous, [boundary, outside]) end)

      assert {:error, {:invalid_arguments, message}} =
               CkAttach.call(%{
                 "host" => "claude-code",
                 "scope" => "user",
                 "project_root" => link
               })

      assert message =~ "must stay within"
    end
  end

  defp temp_path(label) do
    Path.join(System.tmp_dir!(), "ck-attach-#{label}-#{System.unique_integer([:positive])}")
  end

  defp restore_project_root(previous, paths) do
    if previous,
      do: System.put_env("CK_PROJECT_ROOT", previous),
      else: System.delete_env("CK_PROJECT_ROOT")

    Enum.each(paths, &File.rm_rf!/1)
  end
end
