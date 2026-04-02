defmodule ControlKeel.Distribution do
  @moduledoc false

  @github_owner "aryaminus"
  @github_repo "controlkeel"
  @homebrew_tap "aryaminus/controlkeel"
  @homebrew_repo "aryaminus/homebrew-controlkeel"
  @npm_package "@aryaminus/controlkeel"
  @core_mcp_tools ~w(
    ck_context
    ck_validate
    ck_finding
    ck_budget
    ck_route
    ck_delegate
    ck_skill_list
    ck_skill_load
  )

  @install_channels [
    %{
      id: "homebrew",
      label: "Homebrew",
      command: "brew tap aryaminus/controlkeel && brew install controlkeel",
      platforms: ["macos", "linux"],
      description: "Recommended native install path on macOS and Linux."
    },
    %{
      id: "npm",
      label: "npm bootstrap",
      command: "npm i -g @aryaminus/controlkeel",
      platforms: ["macos", "linux", "windows"],
      description:
        "Cross-platform bootstrapper that downloads the matching GitHub release binary."
    },
    %{
      id: "shell-installer",
      label: "Unix installer",
      command:
        "curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh",
      platforms: ["macos", "linux"],
      description: "Direct latest-release installer for shell environments."
    },
    %{
      id: "raw-shell-installer",
      label: "Raw GitHub shell installer",
      command:
        "curl -fsSL https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.sh | sh",
      platforms: ["macos", "linux"],
      description: "Stable bootstrap script from the repository that installs the latest release."
    },
    %{
      id: "powershell-installer",
      label: "PowerShell installer",
      command:
        "irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex",
      platforms: ["windows"],
      description: "Direct latest-release installer for Windows PowerShell."
    },
    %{
      id: "raw-powershell-installer",
      label: "Raw GitHub PowerShell installer",
      command:
        "irm https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.ps1 | iex",
      platforms: ["windows"],
      description: "Stable bootstrap script from the repository that installs the latest release."
    },
    %{
      id: "github-releases",
      label: "GitHub Releases",
      command: "https://github.com/aryaminus/controlkeel/releases",
      platforms: ["macos", "linux", "windows"],
      description: "Canonical source for packaged binaries, checksums, and plugin bundles."
    }
  ]

  def github_repo_slug, do: "#{@github_owner}/#{@github_repo}"
  def github_releases_url, do: "https://github.com/#{github_repo_slug()}/releases"
  def latest_download_base_url, do: github_releases_url() <> "/latest/download"
  def homebrew_tap, do: @homebrew_tap
  def homebrew_repo, do: @homebrew_repo
  def npm_package, do: @npm_package
  def checksum_filename, do: "controlkeel-checksums.txt"
  def required_mcp_tools, do: @core_mcp_tools
  def install_channels, do: @install_channels

  def install_channels(ids) when is_list(ids) do
    Enum.filter(@install_channels, &(&1.id in ids))
  end

  def install_channel(id), do: Enum.find(@install_channels, &(&1.id == id))

  def current_install_channels do
    current_platform = current_platform()

    @install_channels
    |> Enum.filter(fn channel ->
      "github-releases" == channel.id or current_platform in channel.platforms
    end)
  end

  def current_install_lines do
    current_install_channels()
    |> Enum.map(fn channel -> "#{channel.label}: #{channel.command}" end)
  end

  def install_markdown do
    Enum.map_join(current_install_channels(), "\n", fn channel ->
      "- #{channel.label}: `#{channel.command}`"
    end)
  end

  def install_markdown_all do
    Enum.map_join(@install_channels, "\n", fn channel ->
      "- #{channel.label}: `#{channel.command}`"
    end)
  end

  def install_summary do
    "Install or upgrade ControlKeel via Homebrew, the npm bootstrapper, direct install scripts, or GitHub Releases."
  end

  def raw_binary_asset_name("linux", "x86_64"), do: "controlkeel-linux-x86_64"
  def raw_binary_asset_name("linux", "arm64"), do: "controlkeel-linux-arm64"
  def raw_binary_asset_name("macos", "x86_64"), do: "controlkeel-macos-x86_64"
  def raw_binary_asset_name("macos", "arm64"), do: "controlkeel-macos-arm64"
  def raw_binary_asset_name("windows", "x86_64"), do: "controlkeel-windows-x86_64.exe"
  def raw_binary_asset_name(_, _), do: nil

  def binary_archive_name("linux", "x86_64"), do: "controlkeel-linux-x86_64.tar.gz"
  def binary_archive_name("linux", "arm64"), do: "controlkeel-linux-arm64.tar.gz"
  def binary_archive_name("macos", "x86_64"), do: "controlkeel-macos-x86_64.tar.gz"
  def binary_archive_name("macos", "arm64"), do: "controlkeel-macos-arm64.tar.gz"
  def binary_archive_name("windows", "x86_64"), do: "controlkeel-windows-x86_64.zip"
  def binary_archive_name(_, _), do: nil

  def bundle_archive_name(target) when is_binary(target) do
    "controlkeel-#{target}.tar.gz"
  end

  def latest_binary_download_url(os, arch) do
    case raw_binary_asset_name(os, arch) do
      nil -> nil
      filename -> latest_download_base_url() <> "/" <> filename
    end
  end

  def latest_binary_archive_download_url(os, arch) do
    case binary_archive_name(os, arch) do
      nil -> nil
      filename -> latest_download_base_url() <> "/" <> filename
    end
  end

  def latest_bundle_download_url(target) when is_binary(target) do
    latest_download_base_url() <> "/" <> bundle_archive_name(target)
  end

  def latest_installer_url("sh"), do: latest_download_base_url() <> "/install.sh"
  def latest_installer_url("ps1"), do: latest_download_base_url() <> "/install.ps1"
  def latest_installer_url(_), do: nil

  def raw_installer_url("sh"),
    do: "https://raw.githubusercontent.com/#{github_repo_slug()}/main/scripts/install.sh"

  def raw_installer_url("ps1"),
    do: "https://raw.githubusercontent.com/#{github_repo_slug()}/main/scripts/install.ps1"

  def raw_installer_url(_), do: nil

  def portable_project_root, do: "."

  def current_platform do
    case :os.type() do
      {:win32, _} -> "windows"
      {:unix, :darwin} -> "macos"
      _ -> "linux"
    end
  end
end
