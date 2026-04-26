#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
from datetime import date


ROOT = pathlib.Path(__file__).resolve().parents[1]
MIX_EXS = ROOT / "mix.exs"
CHANGELOG = ROOT / "CHANGELOG.md"
NPM_PACKAGE = ROOT / "packages" / "npm" / "controlkeel" / "package.json"
NPM_SERVER = ROOT / "packages" / "npm" / "controlkeel" / "server.json"
PLUGIN_MANIFESTS = [ROOT / "plugin.json", ROOT / ".cursor-plugin" / "plugin.json"]


def read_version() -> tuple[str, str]:
    content = MIX_EXS.read_text()
    match = re.search(r'version:\s*"(\d+)\.(\d+)\.(\d+)"', content)
    if not match:
        raise SystemExit("unable to locate version in mix.exs")

    major, minor, patch = map(int, match.groups())
    current = f"{major}.{minor}.{patch}"
    bumped = f"{major}.{minor}.{patch + 1}"
    updated = re.sub(
        r'version:\s*"\d+\.\d+\.\d+"',
        f'version: "{bumped}"',
        content,
        count=1,
    )
    MIX_EXS.write_text(updated)
    update_npm_package_version(bumped)
    return current, bumped


def update_npm_package_version(version: str) -> None:
    if not NPM_PACKAGE.exists():
        return

    content = NPM_PACKAGE.read_text()
    updated = re.sub(
        r'"version":\s*"\d+\.\d+\.\d+"',
        f'"version": "{version}"',
        content,
        count=1,
    )
    NPM_PACKAGE.write_text(updated)

    update_npm_server_version(version)
    update_plugin_manifest_versions(version)


def update_npm_server_version(version: str) -> None:
    if not NPM_SERVER.exists():
        return

    data = json.loads(NPM_SERVER.read_text())
    data["version"] = version
    for package in data.get("packages", []):
        package["version"] = version
    NPM_SERVER.write_text(json.dumps(data, indent=2) + "\n")


def update_plugin_manifest_versions(version: str) -> None:
    for manifest in PLUGIN_MANIFESTS:
        if not manifest.exists():
            continue

        data = json.loads(manifest.read_text())
        data["version"] = version
        manifest.write_text(json.dumps(data, indent=2) + "\n")


def previous_tag() -> str | None:
    result = subprocess.run(
        ["git", "describe", "--tags", "--abbrev=0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        return result.stdout.strip()
    return None


def commit_lines(prev_tag: str | None) -> list[str]:
    revision = f"{prev_tag}..HEAD" if prev_tag else "HEAD"
    result = subprocess.run(
        ["git", "log", revision, "--pretty=format:%s"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    filtered = [
        line
        for line in lines
        if not line.startswith("chore(release):")
    ]
    return filtered[:25]


def update_changelog(version: str, changes: list[str]) -> None:
    today = date.today().isoformat()
    existing = CHANGELOG.read_text() if CHANGELOG.exists() else "# Changelog\n\n"

    if f"## v{version}" in existing:
      return

    bullets = "\n".join(f"- {line}" for line in (changes or ["Internal maintenance release."]))
    entry = f"## v{version} — {today}\n\n### What's changed\n\n{bullets}\n\n"

    if existing.startswith("# Changelog"):
        header, _, rest = existing.partition("\n\n")
        content = f"{header}\n\n{entry}{rest}"
    else:
        content = f"# Changelog\n\n{entry}{existing}"

    CHANGELOG.write_text(content)


def main() -> None:
    _current, bumped = read_version()
    changes = commit_lines(previous_tag())
    update_changelog(bumped, changes)
    print(bumped)


if __name__ == "__main__":
    main()
