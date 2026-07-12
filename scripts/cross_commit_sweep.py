#!/usr/bin/env python3
"""Produce a read-only evidence-gap report for a bounded commit range."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def build_report(repo: Path, base: str, head: str) -> str:
    files = [line for line in git(repo, "diff", "--name-only", f"{base}...{head}").splitlines() if line]
    commits = git(repo, "log", "--format=- `%h` %s", f"{base}..{head}") or "- No commits in range"

    source_changed = any(path.startswith(("lib/", "config/", "priv/")) for path in files)
    tests_changed = any(path.startswith("test/") for path in files)
    docs_changed = any(path.startswith("docs/") or path.endswith(".md") for path in files)
    skills_changed = any(path.startswith("priv/skills/") for path in files)
    skill_tests_changed = any("skills" in path and path.startswith("test/") for path in files)

    warnings: list[str] = []
    if source_changed and not tests_changed:
        warnings.append("Production or configuration files changed without test changes.")
    if source_changed and not docs_changed:
        warnings.append("Production or configuration files changed without documentation changes; confirm docs are unaffected.")
    if skills_changed and not skill_tests_changed:
        warnings.append("Built-in skills changed without skill-focused test changes.")

    file_lines = "\n".join(f"- `{path}`" for path in files) or "- No files changed"
    warning_lines = "\n".join(f"- {warning}" for warning in warnings) or "- No heuristic evidence gaps detected"

    return f"""# Cross-commit sweep

Range: `{base}...{head}`

## Commits

{commits}

## Changed files

{file_lines}

## Evidence review

{warning_lines}

These are review prompts, not policy findings. Confirm each item against the diff before recording a CK finding.
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    report = build_report(args.repo.resolve(), args.base, args.head)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(report, encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
