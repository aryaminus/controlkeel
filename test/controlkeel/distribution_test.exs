defmodule ControlKeel.DistributionTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Distribution

  test "exposes public install channels" do
    ids = Enum.map(Distribution.install_channels(), & &1.id)

    assert "homebrew" in ids
    assert "npm" in ids
    assert "shell-installer" in ids
    assert "powershell-installer" in ids
    assert "github-releases" in ids
  end

  test "maps raw binaries and archives by platform" do
    assert Distribution.raw_binary_asset_name("linux", "x86_64") == "controlkeel-linux-x86_64"
    assert Distribution.raw_binary_asset_name("macos", "arm64") == "controlkeel-macos-arm64"

    assert Distribution.binary_archive_name("linux", "x86_64") ==
             "controlkeel-linux-x86_64.tar.gz"

    assert Distribution.binary_archive_name("windows", "x86_64") ==
             "controlkeel-windows-x86_64.zip"
  end
end
