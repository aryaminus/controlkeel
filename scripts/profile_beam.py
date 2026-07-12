#!/usr/bin/env python3
"""Build or execute bounded BEAM profiler commands and emit structured evidence."""

import argparse
import json
import subprocess
import sys
import time


PROFILERS = {"cprof": "profile.cprof", "eprof": "profile.eprof", "fprof": "profile.fprof"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profiler", choices=sorted(PROFILERS), required=True)
    parser.add_argument("--expression", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=30)
    parser.add_argument("--max-output-bytes", type=int, default=100_000)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.timeout_seconds <= 300:
        parser.error("timeout-seconds must be between 1 and 300")
    if not 1_000 <= args.max_output_bytes <= 1_000_000:
        parser.error("max-output-bytes must be between 1000 and 1000000")
    command = ["mix", PROFILERS[args.profiler], "-e", args.expression]
    evidence = {"profiler": args.profiler, "command": command, "timeout_seconds": args.timeout_seconds, "max_output_bytes": args.max_output_bytes, "executed": args.execute}
    if not args.execute:
        print(json.dumps(evidence, sort_keys=True))
        return 0
    started = time.monotonic()
    try:
        result = subprocess.run(command, capture_output=True, timeout=args.timeout_seconds)
    except subprocess.TimeoutExpired:
        evidence.update({"status": "timeout", "duration_ms": int((time.monotonic() - started) * 1000)})
        print(json.dumps(evidence, sort_keys=True))
        return 2
    output = (result.stdout + result.stderr)[: args.max_output_bytes]
    evidence.update({"status": "pass" if result.returncode == 0 else "failed", "exit_code": result.returncode, "duration_ms": int((time.monotonic() - started) * 1000), "output": output.decode(errors="replace"), "output_truncated": len(result.stdout) + len(result.stderr) > len(output)})
    print(json.dumps(evidence, sort_keys=True))
    return result.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
