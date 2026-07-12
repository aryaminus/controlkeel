#!/usr/bin/env python3
"""Audit repository-local generated evidence for stale commits and references."""

import argparse
import json
import subprocess
import sys
from pathlib import Path


def head(repo):
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--evidence-dir", required=True)
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    evidence_dir = Path(args.evidence_dir).resolve()
    current_head = head(repo)
    issues = []
    checked = 0
    for path in sorted(evidence_dir.rglob("*.json")):
        try:
            artifact = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            issues.append(f"invalid JSON {path}: {error}")
            continue
        kind = artifact.get("evidence_kind")
        if kind == "test_inventory":
            checked += 1
            if artifact.get("commit_sha") != current_head:
                issues.append(f"stale test inventory: {path}")
            for entry in artifact.get("tests", []):
                relative = entry.get("file")
                if not relative or not (repo / relative).is_file():
                    issues.append(f"missing inventoried test: {relative}")
                status = entry.get("execution", {}).get("status")
                if status != "passed":
                    issues.append(f"inventoried test has no passing execution: {relative} ({status})")
        elif kind == "performance" and artifact.get("evidence_role") == "candidate":
            checked += 1
            if artifact.get("commit_sha") != current_head:
                issues.append(f"stale performance candidate: {path}")
            samples = artifact.get("samples_ms")
            if not isinstance(samples, list) or len(samples) < 5:
                issues.append(f"insufficient performance samples: {path}")
    result = {"status": "pass" if not issues else "stale", "checked": checked, "issues": issues}
    print(json.dumps(result, sort_keys=True))
    return 0 if not issues else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
