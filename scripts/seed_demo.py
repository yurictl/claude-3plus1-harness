#!/usr/bin/env python3
"""Seed deterministic demo data into .claude/telemetry/ so `make report` and
`make html` show a populated dashboard without any real sessions.

Purely synthetic and reproducible (no randomness, dates anchored to today).
`make reset` removes everything.
"""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

TDIR = Path(__file__).resolve().parent.parent / ".claude" / "telemetry"
TDIR.mkdir(parents=True, exist_ok=True)

today = datetime.now(timezone.utc).replace(hour=10, minute=0, second=0, microsecond=0)

# 14 days of sessions with a plausible weekly rhythm (quiet weekends).
PLAN = [  # (days_ago, prompts, active_min, out_tokens, tools)
    (13, 6, 41, 18_400, {"Bash": 22, "Edit": 9, "Read": 14}),
    (12, 11, 73, 35_200, {"Bash": 41, "Edit": 17, "Read": 20, "Write": 4}),
    (11, 4, 22, 9_100, {"Bash": 9, "Read": 11}),
    (10, 9, 58, 27_800, {"Bash": 30, "Edit": 12, "Read": 16, "Skill": 2}),
    (9, 13, 88, 44_600, {"Bash": 52, "Edit": 21, "Read": 24, "Write": 6}),
    (6, 7, 47, 21_300, {"Bash": 25, "Edit": 10, "Read": 12}),
    (5, 15, 96, 51_900, {"Bash": 58, "Edit": 26, "Read": 28, "Skill": 3}),
    (4, 8, 52, 24_700, {"Bash": 27, "Edit": 11, "Read": 15, "Agent": 2}),
    (3, 12, 79, 38_400, {"Bash": 44, "Edit": 19, "Read": 21, "Write": 5}),
    (2, 5, 31, 13_200, {"Bash": 14, "Read": 9, "Edit": 4}),
    (1, 10, 66, 31_500, {"Bash": 36, "Edit": 15, "Read": 18, "Skill": 2}),
    (0, 3, 19, 7_800, {"Bash": 8, "Read": 6}),
]

with open(TDIR / "sessions.jsonl", "w", encoding="utf-8") as f:
    for i, (ago, prompts, active, out_tok, tools) in enumerate(PLAN):
        start = today - timedelta(days=ago)
        asst = sum(tools.values()) + prompts * 2
        rec = {
            "session": f"demo-{i:04d}-0000-0000-0000-000000000000",
            "start": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "end": (start + timedelta(minutes=active * 2)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "duration_min": active * 2.0,
            "active_min": float(active),
            "user_prompts": prompts,
            "assistant_msgs": asst,
            "sidechain_msgs": 0,
            "tools": tools,
            "tokens": {"input": out_tok * 3, "output": out_tok,
                       "cache_read": out_tok * 40, "cache_creation": out_tok * 2},
            "models": ["claude-fable-5"],
            "git_branch": "main",
            "cc_version": "demo",
            "transcript_mtime": 0,
            "harvested": today.strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        f.write(json.dumps(rec) + "\n")

EVENTS = [
    (5, "start-work", {"prompt": "start work on the ingestion spike"}),
    (5, "run", {"prompt": "let's go"}),
    (5, "push", {"command": "git push origin feature/ingestion"}),
    (4, "checkpoint", {"prompt": "checkpoint"}),
    (3, "skill", {"skill": "review", "args": ""}),
    (3, "push", {"command": "git push origin feature/ingestion"}),
    (3, "mr-create", {"command": "gh pr create --fill"}),
    (1, "graduate", {"prompt": "graduate the ingestion WIP"}),
]

with open(TDIR / "events.jsonl", "w", encoding="utf-8") as f:
    for ago, event, detail in EVENTS:
        ts = today - timedelta(days=ago, hours=-1)
        f.write(json.dumps({
            "ts": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "event": event,
            "session": "demo-0000-0000-0000-0000-000000000000",
            "cwd": str(Path(__file__).resolve().parent.parent),
            "detail": detail,
        }) + "\n")

print(f"seeded {len(PLAN)} sessions + {len(EVENTS)} events -> {TDIR}")
