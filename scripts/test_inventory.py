#!/usr/bin/env python3
"""Generate and audit a machine-readable Elixir test inventory."""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path


MODULE_RE = re.compile(r"^defmodule\s+([A-Za-z0-9_.]+)", re.MULTILINE)
META_RE = re.compile(r"^#\s*ck:test\s+(.*)$", re.MULTILINE)


def head(repo):
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()


def generated_at():
    if "SOURCE_DATE_EPOCH" in os.environ:
        generated = datetime.datetime.fromtimestamp(int(os.environ["SOURCE_DATE_EPOCH"]), datetime.timezone.utc)
    else:
        generated = datetime.datetime.now(datetime.timezone.utc)
    return generated.isoformat().replace("+00:00", "Z")


def metadata(content):
    match = META_RE.search(content)
    values = {}
    if match:
        for token in match.group(1).split():
            if "=" in token:
                key, value = token.split("=", 1)
                values[key] = value
    return values


def generate(args):
    repo = Path(args.repo).resolve()
    results = json.loads(Path(args.results).read_text(encoding="utf-8")) if args.results else {}
    entries = []
    for path in sorted(repo.glob("test/**/*_test.exs")):
        relative = path.relative_to(repo).as_posix()
        content = path.read_text(encoding="utf-8", errors="replace")
        meta = metadata(content)
        entries.append({
            "file": relative,
            "module": (MODULE_RE.search(content).group(1) if MODULE_RE.search(content) else None),
            "category": meta.get("category", "performance" if "/performance/" in f"/{relative}" else "test"),
            "invariant": meta.get("invariant"),
            "related_modules": [value for value in meta.get("relates", "").split(",") if value],
            "execution": results.get(relative, {"status": "unexecuted", "runtime_ms": None}),
        })
    output = {"schema_version": 1, "evidence_kind": "test_inventory", "commit_sha": head(repo), "generated_at": generated_at(), "tests": entries}
    Path(args.output).write_text(
        json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


def audit(args):
    repo = Path(args.repo).resolve()
    inventory = json.loads(Path(args.inventory).read_text(encoding="utf-8"))
    issues = []
    if inventory.get("schema_version") != 1 or inventory.get("evidence_kind") != "test_inventory":
        issues.append("inventory schema is invalid")
    if inventory.get("commit_sha") != head(repo):
        issues.append("inventory commit_sha is stale")
    current = {path.relative_to(repo).as_posix() for path in repo.glob("test/**/*_test.exs")}
    recorded = {entry.get("file") for entry in inventory.get("tests", [])}
    for path in sorted(recorded - current):
        issues.append(f"missing test: {path}")
    for path in sorted(current - recorded):
        issues.append(f"untracked test: {path}")
    for entry in inventory.get("tests", []):
        status = entry.get("execution", {}).get("status")
        if status != "passed":
            issues.append(f"test has no passing execution: {entry.get('file')} ({status})")
    print(json.dumps({"status": "pass" if not issues else "stale", "issues": issues}, sort_keys=True))
    return 0 if not issues else 2


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    generate_parser = sub.add_parser("generate")
    generate_parser.add_argument("--repo", required=True)
    generate_parser.add_argument("--output", required=True)
    generate_parser.add_argument("--results")
    generate_parser.set_defaults(func=generate)
    audit_parser = sub.add_parser("audit")
    audit_parser.add_argument("--repo", required=True)
    audit_parser.add_argument("--inventory", required=True)
    audit_parser.set_defaults(func=audit)
    args = parser.parse_args()
    try:
        return args.func(args)
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
