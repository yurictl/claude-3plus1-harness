#!/usr/bin/env python3
"""Shared store access for the two telemetry halves (stdlib only).

The split is deliberate and load-bearing:

  telemetry_report.py  — ACTIVITY. Sessions, prompts, tokens, tool mix. Says the
                         harness is being *used*. Generic agent observability;
                         the platform will eventually do this better, and this
                         half is meant to be deletable when it does.
  harness_health.py    — HEALTH. Catch-rate and its trend, escapes past a clean
                         grade, stamped grades, dead-weight candidates, loop
                         closure. Says the harness *works*. Nothing outside this
                         project can compute it — this half stays.

Everything both halves need lives here, so deleting the activity half leaves the
health half standalone.
"""

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

WORKSPACE = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path(__file__).resolve().parent.parent))
TDIR = WORKSPACE / ".claude" / "telemetry"


def load_jsonl(path):
    if not path.exists():
        return []
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def cutoff_for(days):
    """ISO cutoff string for --days N, or None for all time."""
    if not days:
        return None
    return (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def within(rec_ts, cutoff):
    return cutoff is None or (rec_ts or "") >= cutoff


def fmt_tokens(n):
    if n >= 1_000_000_000:
        return f"{n/1e9:.1f}B"
    if n >= 1_000_000:
        return f"{n/1e6:.1f}M"
    if n >= 1_000:
        return f"{n/1e3:.0f}k"
    return str(n)
