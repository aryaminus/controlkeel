defmodule ControlKeel.MCPLauncherTest do
  use ExUnit.Case, async: false

  test "bin/controlkeel-mcp keeps source-tree mix chatter off stdout" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-mcp-launcher-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    fake_mix = Path.join(bin_dir, "mix")
    arg_log = Path.join(tmp_dir, "mix-args.log")

    File.write!(
      fake_mix,
      """
      #!/bin/sh
      printf '%s\n' "$@" > "#{arg_log}"
      printf '\\033[0mWaiting for lock on the build directory (held by process 123)\\n'
      printf '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}\\n'
      exit 0
      """
    )

    File.chmod!(fake_mix, 0o755)

    wrapper = Path.join(File.cwd!(), "bin/controlkeel-mcp")
    env = [{"PATH", "#{bin_dir}:#{System.get_env("PATH")}"}, {"CK_PROJECT_ROOT", tmp_dir}]

    assert {output, 0} = System.cmd(wrapper, [], env: env)
    refute output =~ "Waiting for lock on the build directory"
    assert output == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}\n"

    assert File.read!(arg_log) =~ "ck.mcp\n--project-root\n#{tmp_dir}\n"
  end
end
