defmodule ControlKeel.DistributionIntegrityTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "npm bootstrap manifest and lock versions match" do
    package = json!("packages/npm/controlkeel/package.json")
    lock = json!("packages/npm/controlkeel/package-lock.json")

    assert lock["version"] == package["version"]
    assert lock["packages"][""]["version"] == package["version"]
  end

  test "version bump workflow is bound to the successful CI commit" do
    workflow = File.read!(Path.join(@root, ".github/workflows/bump-version.yml"))

    assert workflow =~ "ref: ${{ github.event.workflow_run.head_sha }}"
    assert workflow =~ ~S|test "$(git rev-parse origin/main)" = "${VERIFIED_SHA}"|
    assert workflow =~ ~S|--force-with-lease="refs/heads/main:${VERIFIED_SHA}"|
    refute workflow =~ "git pull --rebase"
    refute workflow =~ "git push origin \"refs/tags/v${VERSION}\" --force"
    refute workflow =~ "release-verification.md"
  end

  test "installers require the canonical checksum manifest before installation" do
    shell = File.read!(Path.join(@root, "scripts/install.sh"))
    powershell = File.read!(Path.join(@root, "scripts/install.ps1"))

    for installer <- [shell, powershell] do
      assert installer =~ "controlkeel-checksums.txt"
      assert installer =~ "checksum mismatch" or installer =~ "Checksum mismatch"
    end

    assert shell =~ "verify_checksum \"${TMP_DIR}/controlkeel\""
    assert powershell =~ "Confirm-Checksum -FilePath $TempFile"
  end

  test "installers print the complete repo-local verification path" do
    shell = File.read!(Path.join(@root, "scripts/install.sh"))
    powershell = File.read!(Path.join(@root, "scripts/install.ps1"))

    for installer <- [shell, powershell],
        command <- [
          "controlkeel setup",
          "controlkeel attach doctor",
          "controlkeel provider doctor",
          "controlkeel status",
          "controlkeel findings"
        ] do
      assert installer =~ command
    end
  end

  defp json!(relative_path) do
    @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()
  end
end
