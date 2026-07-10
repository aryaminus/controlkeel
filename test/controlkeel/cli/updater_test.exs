defmodule ControlKeel.CLI.UpdaterTest do
  use ExUnit.Case, async: true

  alias ControlKeel.CLI.Updater

  test "production binary downloads are pinned to the official repository" do
    assert Updater.official_release_base_url("1.2.3") ==
             "https://github.com/aryaminus/controlkeel/releases/download/v1.2.3"
  end

  test "accepts a matching release checksum" do
    path = tmp_file!("trusted binary")
    hash = :crypto.hash(:sha256, "trusted binary") |> Base.encode16(case: :lower)

    assert :ok =
             Updater.verify_download_checksum(
               path,
               "controlkeel-macos-arm64",
               "#{hash}  ./controlkeel-macos-arm64\n"
             )
  end

  test "rejects missing and mismatched release checksums" do
    path = tmp_file!("untrusted binary")

    assert {:error, "no checksum entry for controlkeel-macos-arm64"} =
             Updater.verify_download_checksum(path, "controlkeel-macos-arm64", "abc  other\n")

    assert {:error, "checksum mismatch for controlkeel-macos-arm64"} =
             Updater.verify_download_checksum(
               path,
               "controlkeel-macos-arm64",
               "#{String.duplicate("0", 64)}  controlkeel-macos-arm64\n"
             )
  end

  test "atomically installs an executable replacement from the destination directory" do
    dir = tmp_dir!()
    path = Path.join(dir, "controlkeel")
    File.write!(path, "old binary")

    downloader = fn _version, temp_path, _opts ->
      assert Path.dirname(temp_path) == dir
      assert Path.basename(temp_path) =~ ".controlkeel-update-"
      File.write(temp_path, "verified binary")
    end

    assert :ok = Updater.install_direct_binary(path, "1.2.3", download_binary: downloader)
    assert File.read!(path) == "verified binary"
    assert match?({:ok, %{mode: mode}} when Bitwise.band(mode, 0o111) != 0, File.stat(path))
    assert update_temps(dir) == []
  end

  test "keeps the existing binary and cleans temporary files when preparation fails" do
    dir = tmp_dir!()
    path = Path.join(dir, "controlkeel")
    File.write!(path, "old binary")

    downloader = fn _version, temp_path, _opts -> File.write(temp_path, "new binary") end

    assert {:error, :chmod_failed} =
             Updater.install_direct_binary(path, "1.2.3",
               download_binary: downloader,
               chmod: fn _path, _mode -> {:error, :chmod_failed} end
             )

    assert File.read!(path) == "old binary"
    assert update_temps(dir) == []
  end

  test "keeps the existing binary and cleans temporary files when atomic rename fails" do
    dir = tmp_dir!()
    path = Path.join(dir, "controlkeel")
    File.write!(path, "old binary")

    downloader = fn _version, temp_path, _opts -> File.write(temp_path, "new binary") end

    assert {:error, :rename_failed} =
             Updater.install_direct_binary(path, "1.2.3",
               download_binary: downloader,
               rename: fn _source, _destination -> {:error, :rename_failed} end
             )

    assert File.read!(path) == "old binary"
    assert update_temps(dir) == []
  end

  test "cleans temporary files when preparation raises" do
    dir = tmp_dir!()
    path = Path.join(dir, "controlkeel")
    File.write!(path, "old binary")

    assert_raise RuntimeError, "download crashed", fn ->
      Updater.install_direct_binary(path, "1.2.3",
        download_binary: fn _version, temp_path, _opts ->
          File.write!(temp_path, "partial binary")
          raise "download crashed"
        end
      )
    end

    assert File.read!(path) == "old binary"
    assert update_temps(dir) == []
  end

  defp tmp_file!(contents) do
    path = Path.join(System.tmp_dir!(), "updater-test-#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp tmp_dir! do
    path = Path.join(System.tmp_dir!(), "updater-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp update_temps(dir), do: Path.wildcard(Path.join(dir, ".controlkeel-update-*"))
end
