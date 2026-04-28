#!/usr/bin/env python3
"""Evaluate ControlKeel host-agent surfaces safely.

This read-only evaluator inventories what ControlKeel exposes to host agents:
CLI commands, MCP visibility, skills, attach-generated assets, hooks/plugins/extensions,
and benchmark harness event contracts. It writes redacted JSON and Markdown summaries
under an ignored evidence directory.
"""
import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path

SECRET_PATTERNS = [
    re.compile(r"(?i)(api[_-]?key|secret|token|password|authorization)\s*[:=]\s*[^\s,;}]+"),
    re.compile(r"sk_[A-Za-z0-9_\-]{12,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
]

SURFACE_PATHS = [
    ("opencode", ".opencode"),
    ("agents_skills", ".agents/skills"),
    ("agents_root", ".agents"),
    ("claude", ".claude"),
    ("codex", ".codex"),
    ("github_agents", ".github/agents"),
    ("github_skills", ".github/skills"),
    ("github_commands", ".github/commands"),
    ("github_mcp", ".github/mcp.json"),
    ("cursor_plugin", ".cursor-plugin"),
    ("vscode_mcp", ".vscode/mcp.json"),
    ("root_mcp", ".mcp.json"),
    ("hosted_mcp", ".mcp.hosted.json"),
    ("plugins", "plugins"),
    ("skills", "skills"),
    ("copilot_instructions", "copilot-instructions.md"),
    ("claude_md", "CLAUDE.md"),
    ("gemini_md", "GEMINI.md"),
    ("agent_guidance", "AGENTS.md"),
]

COMMANDS = [
    {"name": "controlkeel_version", "argv": ["controlkeel", "--version"], "surface": "cli"},
    {"name": "controlkeel_help", "argv": ["controlkeel", "help"], "surface": "cli"},
    {"name": "controlkeel_status", "argv": ["controlkeel", "status"], "surface": "cli"},
    {"name": "controlkeel_findings", "argv": ["controlkeel", "findings"], "surface": "cli"},
    {"name": "controlkeel_attach_doctor", "argv": ["controlkeel", "attach", "doctor"], "surface": "attach"},
    {"name": "controlkeel_skills_list", "argv": ["controlkeel", "skills", "list"], "surface": "skills"},
    {"name": "opencode_version", "argv": ["opencode", "--version"], "surface": "host_cli"},
    {"name": "opencode_mcp_list", "argv": ["opencode", "mcp", "list"], "surface": "mcp"},
]

EVENT_EXPORTS = [
    ("run_29_opencode", "tmp/benchmark-evidence/opencode-rerun/opencode/export.json"),
    ("run_30_opencode", "tmp/benchmark-evidence/opencode-rerun-after-scanner/opencode/export.json"),
    ("run_31_bounded", "tmp/benchmark-evidence/opencode-bounded-active/opencode/export.json"),
]


def redact(text):
    if text is None:
        return ""
    text = str(text)
    for pattern in SECRET_PATTERNS:
        text = pattern.sub(lambda m: m.group(0).split(":")[0].split("=")[0] + "=[redacted]", text)
    return text


def run_command(root, spec, timeout=20):
    started = time.time()
    try:
        proc = subprocess.run(spec["argv"], cwd=root, text=True, capture_output=True, timeout=timeout)
        status = "ok" if proc.returncode == 0 else "nonzero"
        stdout = redact(proc.stdout.strip())[:4000]
        stderr = redact(proc.stderr.strip())[:2000]
        return {
            "name": spec["name"],
            "surface": spec["surface"],
            "argv": spec["argv"],
            "status": status,
            "exit_status": proc.returncode,
            "elapsed_ms": int((time.time() - started) * 1000),
            "stdout_preview": stdout,
            "stderr_preview": stderr,
            "stdout_lines": len(proc.stdout.splitlines()),
            "stderr_lines": len(proc.stderr.splitlines()),
        }
    except FileNotFoundError as exc:
        return {"name": spec["name"], "surface": spec["surface"], "argv": spec["argv"], "status": "missing", "error": str(exc)}
    except subprocess.TimeoutExpired:
        return {"name": spec["name"], "surface": spec["surface"], "argv": spec["argv"], "status": "timeout", "elapsed_ms": int((time.time() - started) * 1000)}


def list_surface_path(root, label, rel):
    path = root / rel
    info = {"label": label, "path": rel, "exists": path.exists()}
    if not path.exists():
        return info
    if path.is_file():
        info.update({"type": "file", "size_bytes": path.stat().st_size})
        return info
    files = []
    dirs = []
    for child in sorted(path.rglob("*")):
        child_rel = str(child.relative_to(root))
        if child.is_dir():
            dirs.append(child_rel)
        else:
            files.append({"path": child_rel, "size_bytes": child.stat().st_size})
    info.update({
        "type": "directory",
        "file_count": len(files),
        "dir_count": len(dirs),
        "files_sample": files[:80],
        "dirs_sample": dirs[:40],
    })
    return info


def summarize_benchmark_events(root):
    summaries = []
    for label, rel in EVENT_EXPORTS:
        path = root / rel
        if not path.exists():
            summaries.append({"label": label, "path": rel, "exists": False})
            continue
        payload = json.loads(path.read_text())
        by_subject = {}
        for result in payload.get("results", []):
            subject = result.get("subject")
            bucket = by_subject.setdefault(subject, {
                "completed": 0,
                "caught": 0,
                "blocked": 0,
                "ck_event_scenarios": 0,
                "mcp_event_scenarios": 0,
                "skill_event_scenarios": 0,
                "plugin_event_scenarios": 0,
                "hook_event_scenarios": 0,
                "tool_names": set(),
                "tokens_total": 0,
            })
            if result.get("status") == "completed":
                bucket["completed"] += 1
            if (result.get("findings_count") or 0) > 0:
                bucket["caught"] += 1
            if result.get("decision") == "block":
                bucket["blocked"] += 1
            metadata = result.get("metadata", {}).get("import_metadata") or {}
            event = metadata.get("event_summary") or {}
            if event.get("ck_event_count", 0) > 0:
                bucket["ck_event_scenarios"] += 1
            if event.get("mcp_event_count", 0) > 0:
                bucket["mcp_event_scenarios"] += 1
            if event.get("skill_event_count", 0) > 0:
                bucket["skill_event_scenarios"] += 1
            if event.get("plugin_event_count", 0) > 0:
                bucket["plugin_event_scenarios"] += 1
            if event.get("hook_event_count", 0) > 0:
                bucket["hook_event_scenarios"] += 1
            for tool in event.get("tool_names") or []:
                bucket["tool_names"].add(tool)
            bucket["tokens_total"] += (metadata.get("tokens") or {}).get("total") or 0
        normalized = []
        for subject, bucket in sorted(by_subject.items()):
            bucket["tool_names"] = sorted(bucket["tool_names"])
            normalized.append({"subject": subject, **bucket})
        summaries.append({
            "label": label,
            "path": rel,
            "exists": True,
            "run_id": payload.get("run", {}).get("id"),
            "status": payload.get("run", {}).get("status"),
            "subjects": normalized,
        })
    return summaries


def write_markdown(report, output_dir):
    lines = [
        "# ControlKeel Surface Evaluation",
        "",
        f"Generated at: `{report['generated_at']}`",
        "",
        "## Command surfaces",
        "",
        "| Surface | Command | Status | Exit | Time | Output lines |",
        "| --- | --- | --- | ---: | ---: | ---: |",
    ]
    for item in report["commands"]:
        lines.append(f"| {item.get('surface')} | `{' '.join(item.get('argv', []))}` | {item.get('status')} | {item.get('exit_status', '')} | {item.get('elapsed_ms', '')} ms | {item.get('stdout_lines', 0)} |")
    lines.extend(["", "## Attach/generated asset surfaces", "", "| Label | Path | Exists | Type/count |", "| --- | --- | --- | --- |"])
    for item in report["paths"]:
        count = item.get("type", "")
        if item.get("type") == "directory":
            count = f"{item.get('file_count', 0)} files, {item.get('dir_count', 0)} dirs"
        elif item.get("type") == "file":
            count = f"file, {item.get('size_bytes', 0)} bytes"
        lines.append(f"| {item['label']} | `{item['path']}` | {item['exists']} | {count} |")
    lines.extend(["", "## Benchmark event evidence", "", "| Run | Subject | Completed | Caught | Blocked | CK | MCP | Skills | Plugins | Hooks | Tools | Tokens |", "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |"])
    for run in report["benchmark_events"]:
        for subject in run.get("subjects", []):
            tools = ", ".join(subject.get("tool_names") or [])
            lines.append(f"| {run.get('run_id')} | {subject['subject']} | {subject['completed']} | {subject['caught']} | {subject['blocked']} | {subject['ck_event_scenarios']} | {subject['mcp_event_scenarios']} | {subject['skill_event_scenarios']} | {subject['plugin_event_scenarios']} | {subject['hook_event_scenarios']} | {tools} | {subject['tokens_total']} |")
    lines.append("")
    (output_dir / "surface-summary.md").write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="tmp/benchmark-evidence/full-suite/surfaces")
    parser.add_argument("--command-timeout", type=int, default=20)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = root / args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project_root": str(root),
        "commands": [run_command(root, spec, timeout=args.command_timeout) for spec in COMMANDS],
        "paths": [list_surface_path(root, label, rel) for label, rel in SURFACE_PATHS],
        "benchmark_events": summarize_benchmark_events(root),
    }
    (out / "surface-report.json").write_text(json.dumps(report, indent=2))
    write_markdown(report, out)
    print(json.dumps({"output_dir": str(out), "commands": len(report["commands"]), "paths": len(report["paths"]), "event_exports": len(report["benchmark_events"])}))

if __name__ == "__main__":
    main()
