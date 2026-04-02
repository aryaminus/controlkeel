#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"


def extract_entry(version: str) -> str:
    content = CHANGELOG.read_text()
    pattern = re.compile(
        rf"^## v{re.escape(version)}.*?(?=^## v|\Z)",
        flags=re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(content)
    if not match:
        raise SystemExit(f"unable to locate changelog entry for v{version}")
    return match.group(0).strip()


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: render_release_notes.py <version>")

    version = sys.argv[1].removeprefix("v")
    changelog_entry = extract_entry(version)

    print(f"# ControlKeel v{version}\n")
    print("## Install\n")
    print("- Homebrew: `brew tap aryaminus/controlkeel && brew install controlkeel`")
    print("- npm bootstrap: `npm i -g @aryaminus/controlkeel`")
    print(
        "- Unix installer: `curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh`"
    )
    print(
        "- Raw GitHub shell installer: `curl -fsSL https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.sh | sh`"
    )
    print(
        "- PowerShell installer: `irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex`"
    )
    print(
        "- Raw GitHub PowerShell installer: `irm https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.ps1 | iex`"
    )
    print("\n## Adapter Artifacts\n")
    print("- Claude plugin bundle: `controlkeel-claude-plugin.tar.gz`")
    print("- Copilot plugin bundle: `controlkeel-copilot-plugin.tar.gz`")
    print("- OpenCode bundle: `controlkeel-opencode-native.tar.gz` and `controlkeel-opencode-native.tgz`")
    print("- Pi bundle: `controlkeel-pi-native.tar.gz` and `controlkeel-pi-native.tgz`")
    print("- VS Code companion: `controlkeel-vscode-companion.vsix`")
    print("\n## Direct Host Installs\n")
    print("- OpenCode npm plugin: add `\"plugin\": [\"@aryaminus/controlkeel-opencode\"]` to `opencode.json`")
    print("- Pi npm extension: `pi install npm:@aryaminus/controlkeel-pi-extension`")
    print("- Pi short form: `pi -e npm:@aryaminus/controlkeel-pi-extension`")
    print("- VS Code companion: `code --install-extension controlkeel-vscode-companion.vsix`")
    print("- Claude local plugin dir: `claude --plugin-dir ./controlkeel/dist/claude-plugin`")
    print("- Copilot local plugin bundle: `controlkeel plugin install copilot`")
    print("- Codex local plugin bundle: `controlkeel plugin install codex`")
    print("\n## Changelog\n")
    print(changelog_entry)


if __name__ == "__main__":
    main()
