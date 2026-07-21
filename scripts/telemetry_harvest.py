#!/usr/bin/env python3
"""Harvest per-session aggregates from Claude Code transcripts into the durable
telemetry store (.claude/telemetry/sessions.jsonl).

Transcripts under ~/.claude/projects/<slug>/ expire after ~30 days; this script
distills each into one JSON line (tokens, tools, message counts, duration) that
survives. Zero LLM involvement; stdlib only.

Modes:
  telemetry_harvest.py               SessionEnd hook mode: reads hook JSON from
                                     stdin, harvests that session. Always exit 0.
  telemetry_harvest.py --all         Backfill: harvest every transcript in the
                                     project dir (skips unchanged ones by mtime).
  telemetry_harvest.py --transcript P  Harvest one file explicitly.

Design notes: README.md in this example.
Schema: README.md § Layer 2.
"""

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

WORKSPACE = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path(__file__).resolve().parent.parent))
STORE = WORKSPACE / ".claude" / "telemetry" / "sessions.jsonl"


def project_transcript_dir() -> Path:
    slug = str(WORKSPACE).replace("/", "-")
    return Path.home() / ".claude" / "projects" / slug


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def is_real_prompt(d):
    """A human-typed prompt: user line, not meta, not a tool_result carrier."""
    if d.get("isMeta") or d.get("isSidechain"):
        return False
    content = (d.get("message") or {}).get("content")
    if isinstance(content, str):
        return not content.lstrip().startswith(("<local-command", "<command-name>", "<task-notification>"))
    if isinstance(content, list):
        return any(isinstance(c, dict) and c.get("type") == "text" for c in content)
    return False


ACTIVE_GAP_CAP = 300  # seconds; inter-message gaps above this count as idle


def harvest_file(path: Path):
    first_ts = last_ts = prev_ts = None
    active_sec = 0.0
    user_prompts = 0
    assistant_ids = set()
    sidechain_ids = set()
    tools = {}
    tokens = {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
    models = set()
    git_branch = version = None
    session_id = path.stem

    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = parse_ts(d.get("timestamp", ""))
            if ts:
                first_ts = first_ts or ts
                if prev_ts is not None:
                    gap = (ts - prev_ts).total_seconds()
                    if 0 <= gap:
                        active_sec += min(gap, ACTIVE_GAP_CAP)
                prev_ts = ts
                last_ts = ts
            t = d.get("type")
            if t == "user":
                if is_real_prompt(d):
                    user_prompts += 1
                git_branch = d.get("gitBranch") or git_branch
                version = d.get("version") or version
            elif t == "assistant":
                m = d.get("message") or {}
                mid = m.get("id")
                bucket = sidechain_ids if d.get("isSidechain") else assistant_ids
                # streamed chunks repeat the same message id + usage; count once
                if mid and mid not in assistant_ids and mid not in sidechain_ids:
                    u = m.get("usage") or {}
                    tokens["input"] += u.get("input_tokens", 0) or 0
                    tokens["output"] += u.get("output_tokens", 0) or 0
                    tokens["cache_read"] += u.get("cache_read_input_tokens", 0) or 0
                    tokens["cache_creation"] += u.get("cache_creation_input_tokens", 0) or 0
                    if m.get("model") and m["model"] != "<synthetic>":
                        models.add(m["model"])
                if mid:
                    bucket.add(mid)
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        name = c.get("name", "?")
                        tools[name] = tools.get(name, 0) + 1

    if first_ts is None:
        return None
    duration_min = round((last_ts - first_ts).total_seconds() / 60, 1) if last_ts else 0
    return {
        "session": session_id,
        "start": first_ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "end": last_ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if last_ts else None,
        "duration_min": duration_min,
        "active_min": round(active_sec / 60, 1),
        "user_prompts": user_prompts,
        "assistant_msgs": len(assistant_ids),
        "sidechain_msgs": len(sidechain_ids),
        "tools": dict(sorted(tools.items(), key=lambda kv: -kv[1])),
        "tokens": tokens,
        "models": sorted(models),
        "git_branch": git_branch,
        "cc_version": version,
        "transcript_mtime": int(path.stat().st_mtime),
        "harvested": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def load_store():
    records = {}
    if STORE.exists():
        with open(STORE, encoding="utf-8") as f:
            for line in f:
                try:
                    r = json.loads(line)
                    records[r["session"]] = r
                except (json.JSONDecodeError, KeyError):
                    continue
    return records


def save_store(records):
    STORE.parent.mkdir(parents=True, exist_ok=True)
    rows = sorted(records.values(), key=lambda r: r.get("start") or "")
    fd, tmp = tempfile.mkstemp(dir=STORE.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp, STORE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="backfill every transcript in the project dir")
    ap.add_argument("--transcript", help="harvest one transcript file")
    args = ap.parse_args()

    targets = []
    if args.all:
        d = project_transcript_dir()
        if not d.is_dir():
            print(f"no transcript dir: {d}", file=sys.stderr)
            return
        existing = load_store()
        for p in sorted(d.glob("*.jsonl")):
            rec = existing.get(p.stem)
            if rec and rec.get("transcript_mtime") == int(p.stat().st_mtime) and "active_min" in rec:
                continue  # unchanged since last harvest (and schema is current)
            targets.append(p)
    elif args.transcript:
        targets = [Path(args.transcript)]
    else:
        # SessionEnd hook mode: payload on stdin
        try:
            payload = json.load(sys.stdin)
            tp = payload.get("transcript_path")
            if tp and Path(tp).is_file():
                targets = [Path(tp)]
        except (json.JSONDecodeError, OSError):
            pass
        if not targets:
            return  # nothing to do; never fail the hook

    records = load_store()
    harvested = 0
    for p in targets:
        try:
            rec = harvest_file(p)
        except OSError:
            continue
        if rec:
            records[rec["session"]] = rec
            harvested += 1
    if harvested:
        save_store(records)
    print(f"harvested {harvested} session(s) -> {STORE}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # hook safety: telemetry must never block the agent
        print(f"telemetry_harvest: {e}", file=sys.stderr)
        sys.exit(0)
