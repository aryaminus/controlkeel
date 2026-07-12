#!/usr/bin/env python3
"""Validate and compare commit-linked performance evidence without updating baselines."""

import argparse
import json
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path


def fail(message):
    raise ValueError(message)


def load(path):
    with Path(path).open(encoding="utf-8") as handle:
        data = json.load(handle)
    required = {"schema_version", "evidence_kind", "evidence_role", "benchmark", "commit_sha", "environment", "samples_ms"}
    missing = sorted(required - data.keys())
    if missing:
        fail(f"missing fields: {', '.join(missing)}")
    if data["schema_version"] != 1:
        fail("schema_version must be 1")
    if data["evidence_kind"] != "performance" or data["evidence_role"] not in {"baseline", "candidate"}:
        fail("performance evidence kind or role is invalid")
    samples = data["samples_ms"]
    if not isinstance(samples, list) or len(samples) < 5 or not all(isinstance(x, (int, float)) and x > 0 for x in samples):
        fail("samples_ms must contain at least five positive numbers")
    if not isinstance(data["environment"], dict) or not data["environment"]:
        fail("environment must be a non-empty object")
    return data


def percentile(values, percentile_value):
    ordered = sorted(values)
    index = max(0, (len(ordered) * percentile_value + 99) // 100 - 1)
    return ordered[index]


def stats(data):
    samples = data["samples_ms"]
    return {"median_ms": statistics.median(samples), "p95_ms": percentile(samples, 95), "sample_count": len(samples)}


def git_head(repo):
    result = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def compare(args):
    baseline = load(args.baseline)
    candidate = load(args.candidate)
    if baseline["evidence_role"] != "baseline" or candidate["evidence_role"] != "candidate":
        fail("compare requires baseline and candidate evidence roles")
    if baseline["benchmark"] != candidate["benchmark"]:
        fail("benchmark names differ")
    if baseline["environment"] != candidate["environment"]:
        fail("environment fingerprints differ")
    if args.repo and candidate["commit_sha"] != git_head(args.repo):
        fail("candidate commit_sha is stale")
    baseline_stats = stats(baseline)
    candidate_stats = stats(candidate)
    threshold = float(candidate.get("allowed_regression_percent", baseline.get("allowed_regression_percent", 0)))
    if threshold < 0:
        fail("allowed_regression_percent must be non-negative")
    base = baseline_stats["median_ms"]
    regression = ((candidate_stats["median_ms"] / base) - 1) * 100
    review = candidate.get("regression_review", {})
    approved = review.get("status") == "approved" and isinstance(review.get("review_id"), int) and review["review_id"] > 0 and isinstance(review.get("reviewed_by"), str) and bool(review["reviewed_by"].strip())
    result = {
        "benchmark": candidate["benchmark"],
        "baseline": baseline_stats,
        "candidate": candidate_stats,
        "regression_percent": regression,
        "allowed_regression_percent": threshold,
        "regression_review_approved": approved,
        "status": "pass" if regression <= threshold or approved else "regression_requires_review",
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "pass" else 2


def fingerprint(_args):
    runtime = subprocess.run(["elixir", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    print(json.dumps({"os": platform.system(), "os_release": platform.release(), "arch": platform.machine(), "python": platform.python_version(), "beam_runtime": runtime, "ci": os.environ.get("CI", "false")}, sort_keys=True))
    return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    compare_parser = sub.add_parser("compare")
    compare_parser.add_argument("--baseline", required=True)
    compare_parser.add_argument("--candidate", required=True)
    compare_parser.add_argument("--repo")
    compare_parser.set_defaults(func=compare)
    fingerprint_parser = sub.add_parser("fingerprint")
    fingerprint_parser.set_defaults(func=fingerprint)
    args = parser.parse_args()
    try:
        return args.func(args)
    except (ValueError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
