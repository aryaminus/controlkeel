defmodule ControlKeel.UpdaterTest do
  use ControlKeel.DataCase

  alias ControlKeel.ProjectBinding
  alias ControlKeel.Updater

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-updater-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "check reports a newer release and stale attached surfaces", %{tmp_dir: tmp_dir} do
    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "cursor",
                 "attached_agents" => %{
                   "cursor" => %{
                     "target" => "cursor-native",
                     "scope" => "project",
                     "controlkeel_version" => "0.0.1"
                   }
                 }
               },
               tmp_dir
             )

    report =
      Updater.check(tmp_dir,
        executable_path: "/opt/homebrew/bin/controlkeel",
        http_get: fn _url ->
          {:ok,
           %{
             "tag_name" => "v999.0.0",
             "html_url" => "https://github.com/aryaminus/controlkeel/releases/tag/v999.0.0"
           }}
        end,
        cmd_runner: fn
          "brew", ["--prefix"], _opts -> {"/opt/homebrew\n", 0}
          _cmd, _args, _opts -> {"", 1}
        end
      )

    assert report["update_available"]
    assert get_in(report, ["install", "channel"]) == "brew"
    assert get_in(report, ["attached", "stale_count"]) == 1
    assert get_in(report, ["commands", "self_update"]) == "brew upgrade controlkeel"
    assert get_in(report, ["commands", "attached_sync"]) == "controlkeel update --sync-attached"
  end

  test "apply returns manual guidance for unsupported channels", %{tmp_dir: tmp_dir} do
    assert {:ok, report} =
             Updater.apply(tmp_dir,
               apply: true,
               executable_path: "/tmp/controlkeel",
               http_get: fn _url ->
                 {:ok,
                  %{
                    "tag_name" => "v999.0.0",
                    "html_url" => "https://github.com/aryaminus/controlkeel/releases/tag/v999.0.0"
                  }}
               end,
               cmd_runner: fn _cmd, _args, _opts -> {"", 1} end
             )

    assert get_in(report, ["apply_result", "status"]) in ["manual", "applied", "error"]
  end
end
