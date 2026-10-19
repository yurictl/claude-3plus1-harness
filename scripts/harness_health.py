#!/usr/bin/env python3
"""Harness health — the half of the telemetry that measures the HARNESS.

Activity metrics (sessions, prompts, tokens — see telemetry_report.py) say the
harness is being used. These say whether it works: does the grader still catch
what it used to (replay), did anything get past it (escapes), is the loop
actually closing (checkpoint / graduate ratios), which rules are dead weight.
Without this section a dashboard reports effort and calls it progress.

Standalone by construction. It reads the harness's own stores — replay.jsonl,
escapes.jsonl, grades.jsonl, written by replay.sh / escape-log.sh /
grade-marker.sh — and needs neither the transcript harvester nor the activity
report. Deleting the activity half does not touch this.

  harness_health.py              the health panel
  harness_health.py --days 30    restrict to the last N days
"""

import argparse
import hashlib
import re
from collections import Counter
from datetime import datetime, timezone

from telemetry_common import TDIR, WORKSPACE, cutoff_for, load_jsonl, within


def rubric_sha():
    """Short hash of the current rubric — the key escapes and replays are filed under."""
    conf = WORKSPACE / "scripts" / "harness.conf"
    rubric = "docs/operations/conventions.md"
    if conf.exists():
        m = re.search(r'^RUBRIC="?([^"\n]+)"?', conf.read_text(encoding="utf-8"), re.M)
        if m:
            rubric = m.group(1)
    p = WORKSPACE / rubric
    if not p.exists():
        return None
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16]


def golden_sets():
    """The set names a *full* replay covers, per harness.conf."""
    conf = WORKSPACE / "scripts" / "harness.conf"
    if conf.exists():
        m = re.search(r'^GOLDEN_SETS="?([^"\n]+)"?', conf.read_text(encoding="utf-8"), re.M)
        if m:
            return set(m.group(1).split())
    return {"held-in", "held-out", "clean"}


def days_since(ts):
    if not ts:
        return None
    try:
        t = datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    return (datetime.now(timezone.utc) - t).days


def harness_health(days=None):
    cutoff = cutoff_for(days)
    replays = [r for r in load_jsonl(TDIR / "replay.jsonl") if within(r.get("ts"), cutoff)]
    escapes = [e for e in load_jsonl(TDIR / "escapes.jsonl") if within(e.get("ts"), cutoff)]
    grades = [g for g in load_jsonl(TDIR / "grades.jsonl") if within(g.get("ts"), cutoff)]
    cur_rubric = rubric_sha()

    # A `--set` replay covers one set. Its rate is not comparable to a full run's,
    # so partial runs never define the headline or enter the trend — otherwise a
    # single diagnostic re-run silently redefines the catch-rate.
    expected = golden_sets()
    full = [r for r in replays if set(r.get("sets") or {}) == expected]
    latest = full[-1] if full else None
    newest = replays[-1] if replays else None
    partial_since = len(replays) - (replays.index(latest) + 1) if latest else len(replays)

    trend = []
    for r in full[-6:]:
        sets = r.get("sets") or {}
        tp = sum(v.get("pass", 0) for v in sets.values())
        tt = sum(v.get("total", 0) for v in sets.values())
        trend.append((r.get("ts", "")[:10], tp, tt))

    # Rules that keep letting things through, and rules never exercised.
    escapes_by_rule = Counter((e.get("missed_rule") or "(no rule existed)") for e in escapes)
    escapes_current = [e for e in escapes if cur_rubric and e.get("rubric_sha256") == cur_rubric]

    # Decay read: fixtures the model catches with no rubric at all.
    redundant, frontier_only = [], []
    for r in reversed(replays):           # newest run that carries the probes
        fx = r.get("fixtures") or []
        if any(f.get("caught_without_rubric") is not None for f in fx):
            redundant = [f"{f['set']}/{f['fixture']}" for f in fx if f.get("caught_without_rubric") is True]
            break
    for r in reversed(replays):
        fx = r.get("fixtures") or []
        if any(f.get("cheap_caught") is not None for f in fx):
            frontier_only = [f"{f['set']}/{f['fixture']}" for f in fx
                             if f.get("cheap_caught") is False and f.get("verdict") == "pass"]
            break

    return {
        "replays": replays, "escapes": escapes, "grades": grades,
        "latest": latest, "trend": trend,
        "newest": newest, "partial_since": partial_since,
        "days_since_replay": days_since(latest.get("ts")) if latest else None,
        "rubric_sha": cur_rubric,
        "rubric_changed": bool(latest and cur_rubric and latest.get("rubric_sha256") != cur_rubric),
        "escapes_by_rule": escapes_by_rule,
        "escapes_current_rubric": len(escapes_current),
        "blocker_grades": sum(1 for g in grades if g.get("blocker")),
        "caveats": sum(g.get("caveat") or 0 for g in grades),
        "redundant": redundant,
        "frontier_only": frontier_only,
    }


def loop_closure(days=None):
    """Ratios that show whether the four-skill loop leaks.

    Each skill writes to the layer the next one reads, so a lopsided mix is a
    diagnosis: start-work without checkpoint = the rubric never compounds;
    start-work without graduate = the WIP layer rots.

    Reads events.jsonl directly rather than taking the activity report's
    aggregate, so the panel survives the activity half being deleted. The
    per-session denominator prefers sessions.jsonl and falls back to distinct
    session ids in the event log when the harvester is gone.
    """
    cutoff = cutoff_for(days)
    events = [e for e in load_jsonl(TDIR / "events.jsonl") if within(e.get("ts"), cutoff)]
    ev = Counter(e.get("event", "?") for e in events)
    sk = Counter(e["detail"].get("skill", "?") for e in events
                 if e.get("event") == "skill" and isinstance(e.get("detail"), dict))

    harvested = [s for s in load_jsonl(TDIR / "sessions.jsonl") if within(s.get("start"), cutoff)]
    sessions = len(harvested) or len({e.get("session") for e in events if e.get("session")})

    starts = ev.get("start-work", 0) + sk.get("start-work", 0)
    checks = ev.get("checkpoint", 0) + sk.get("checkpoint", 0)
    grads = ev.get("graduate", 0) + sk.get("graduate", 0)
    return {
        "checkpoint_per_session": round(checks / max(sessions, 1), 2),
        "graduate_per_start": (round(grads / starts, 2) if starts else None),
        "starts": starts, "checkpoints": checks, "graduates": grads,
        "pushes": ev.get("push", 0),
    }


def health_report(h, lc):
    print()
    print("── harness health " + "─" * 44)
    if h["latest"]:
        sets = h["latest"].get("sets") or {}
        per = "  ".join(f"{k} {v.get('pass',0)}/{v.get('total',0)}" for k, v in sets.items())
        stale = f", {h['days_since_replay']}d ago" if h["days_since_replay"] is not None else ""
        print(f"catch-rate: {per}   (model {h['latest'].get('model','?')}{stale})")
        if h["latest"].get("dirty_calibration"):
            print("  ! that run was against uncommitted calibration material — provisional")
        if h["rubric_changed"]:
            print("  ! the rubric changed since that run — re-run 'make replay' before trusting it")
        if h["days_since_replay"] is not None and h["days_since_replay"] > 30:
            print("  ! no replay in over a month; a grader without a fresh golden set is decorative")
        if h["partial_since"]:
            sets = ", ".join(h["newest"].get("sets") or {})
            print(f"  ! {h['partial_since']} partial replay(s) since (newest: {sets}) — not comparable,")
            print("    excluded from the headline and the trend; 'make replay' for a full run")
        if len(h["trend"]) > 1:
            print("  trend: " + "  ".join(f"{d} {p}/{t}" for d, p, t in h["trend"]))
    elif h["newest"]:
        sets = ", ".join(h["newest"].get("sets") or {})
        print(f"catch-rate: no full replay on record — only partial runs ({sets}). Run 'make replay'.")
    else:
        print("catch-rate: never replayed — run 'make replay'")

    n_esc = len(h["escapes"])
    if n_esc:
        print(f"escapes: {n_esc} total, {h['escapes_current_rubric']} against the current rubric")
        for rule, cnt in h["escapes_by_rule"].most_common(5):
            print(f"  {cnt}×  {rule}")
    else:
        print("escapes: 0 logged — either the rubric is holding, or /checkpoint is not logging them")

    if h["grades"]:
        print(f"grades stamped: {len(h['grades'])}   with-blockers-refused: {h['blocker_grades']}   "
              f"caveats surfaced: {h['caveats']}")

    if h["redundant"]:
        print("dead-weight candidates (caught with NO rubric — the model already knows):")
        for f in h["redundant"]:
            print(f"  {f}")
    if h["frontier_only"]:
        print("frontier-only rules (the cheap tier misses them — not portable):")
        for f in h["frontier_only"]:
            print(f"  {f}")
    if not h["redundant"] and not h["frontier_only"] and h["latest"]:
        print("decay probes: not run — 'make replay-tiers' classifies each rule")

    gps = lc["graduate_per_start"]
    print(f"loop: start-work {lc['starts']}  checkpoint {lc['checkpoints']} "
          f"({lc['checkpoint_per_session']}/session)  graduate {lc['graduates']}"
          + (f" ({gps}/start)" if gps is not None else "") + f"  pushes {lc['pushes']}")
    if lc["starts"] and lc["checkpoints"] == 0:
        print("  ! work started, never checkpointed — failures are not reaching the rubric")
    if lc["starts"] and lc["graduates"] == 0:
        print("  ! nothing graduated — the WIP layer is accreting")


def main():
    ap = argparse.ArgumentParser(description="harness-health panel")
    ap.add_argument("--days", type=int, help="restrict to the last N days")
    args = ap.parse_args()
    health_report(harness_health(args.days), loop_closure(args.days))


if __name__ == "__main__":
    main()
