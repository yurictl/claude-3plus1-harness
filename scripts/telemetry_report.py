#!/usr/bin/env python3
"""Lightweight telemetry report over the durable stores (agentsview-inspired,
no server / no DB / no deps — stdlib only).

Reads .claude/telemetry/sessions.jsonl (per-session aggregates harvested from
transcripts by telemetry_harvest.py) and .claude/telemetry/events.jsonl
(work-loop events from the hook collector).

  telemetry_report.py                console summary
  telemetry_report.py --days 30      restrict to the last N days
  telemetry_report.py --html PATH    also write a self-contained static
                                     dashboard (light+dark, no JS libraries)

Design notes: README.md in this example.
"""

import argparse
import html
import json
import os
from collections import Counter, defaultdict
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


def collect(days=None):
    cutoff = None
    if days:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    sessions = [s for s in load_jsonl(TDIR / "sessions.jsonl") if within(s.get("start"), cutoff)]
    events = [e for e in load_jsonl(TDIR / "events.jsonl") if within(e.get("ts"), cutoff)]

    tools, models, daily_prompts = Counter(), Counter(), defaultdict(int)
    tok = Counter()
    for s in sessions:
        tools.update(s.get("tools") or {})
        models.update({m: s.get("assistant_msgs", 0) for m in s.get("models") or []})
        for k, v in (s.get("tokens") or {}).items():
            tok[k] += v
        daily_prompts[(s.get("start") or "")[:10]] += s.get("user_prompts", 0)
    event_mix = Counter(e.get("event", "?") for e in events)
    skill_mix = Counter(e["detail"].get("skill", "?") for e in events if e.get("event") == "skill")
    return {
        "sessions": sessions, "events": events, "tools": tools, "models": models,
        "daily_prompts": dict(sorted(daily_prompts.items())), "tokens": tok,
        "event_mix": event_mix, "skill_mix": skill_mix,
        "prompts": sum(s.get("user_prompts", 0) for s in sessions),
        "hours": round(sum(s.get("active_min", s.get("duration_min", 0)) for s in sessions) / 60, 1),
    }


def console_report(d):
    print(f"sessions: {len(d['sessions'])}   prompts: {d['prompts']}   active time: {d['hours']}h (gaps >5m excluded)")
    t = d["tokens"]
    print(f"tokens: out {fmt_tokens(t['output'])} · in {fmt_tokens(t['input'])} · "
          f"cache read {fmt_tokens(t['cache_read'])} · cache write {fmt_tokens(t['cache_creation'])}")
    if d["event_mix"]:
        print("work-loop events: " + "  ".join(f"{k}:{v}" for k, v in d["event_mix"].most_common()))
    if d["skill_mix"]:
        print("skills: " + "  ".join(f"{k}:{v}" for k, v in d["skill_mix"].most_common()))
    print("top tools: " + "  ".join(f"{k}:{v}" for k, v in d["tools"].most_common(10)))
    print("models: " + "  ".join(f"{k}:{v}" for k, v in d["models"].most_common()))
    weekly = defaultdict(int)
    for day, n in d["daily_prompts"].items():
        try:
            wk = datetime.strptime(day, "%Y-%m-%d").strftime("%G-W%V")
        except ValueError:
            continue
        weekly[wk] += n
    print("prompts by week: " + "  ".join(f"{k}:{v}" for k, v in sorted(weekly.items())))


def hbar_rows(counter, top=10):
    items = counter.most_common(top)
    other = sum(counter.values()) - sum(v for _, v in items)
    if other > 0:
        items.append(("Other", other))
    mx = max((v for _, v in items), default=1)
    rows = []
    for name, v in items:
        pct = max(1.5, 100 * v / mx)
        rows.append(
            f'<div class="hrow"><div class="hlabel" title="{html.escape(str(name))}">{html.escape(str(name))}</div>'
            f'<div class="htrack"><div class="hbar" style="width:{pct:.1f}%"></div></div>'
            f'<div class="hval">{v:,}</div></div>')
    return "\n".join(rows) or '<div class="empty">no data</div>'


def daily_chart(daily, days=45):
    if not daily:
        return '<div class="empty">no data</div>'
    end = datetime.now(timezone.utc).date()
    seq = [(end - timedelta(days=i)).isoformat() for i in range(days - 1, -1, -1)]
    mx = max((daily.get(day, 0) for day in seq), default=1) or 1
    bars = []
    for day in seq:
        v = daily.get(day, 0)
        h = max(2, round(92 * v / mx)) if v else 2
        cls = "vbar" if v else "vbar zero"
        bars.append(f'<div class="vslot"><div class="{cls}" style="height:{h}px"></div>'
                    f'<div class="tip">{day} · {v} prompts</div></div>')
    return '<div class="vchart">' + "".join(bars) + "</div>" + \
           f'<div class="axisnote">{seq[0]} — {seq[-1]}, prompts per day, max {mx}</div>'


def sessions_table(sessions, last=20):
    rows = []
    for s in sorted(sessions, key=lambda r: r.get("start") or "", reverse=True)[:last]:
        top_tools = ", ".join(list((s.get("tools") or {}))[:3])
        rows.append(
            "<tr>"
            f'<td class="num">{html.escape((s.get("start") or "")[:16].replace("T", " "))}</td>'
            f'<td class="num">{s.get("active_min", s.get("duration_min", 0)):g}m</td>'
            f'<td class="num">{s.get("user_prompts", 0)}</td>'
            f'<td class="num">{s.get("assistant_msgs", 0)}</td>'
            f'<td class="num">{fmt_tokens((s.get("tokens") or {}).get("output", 0))}</td>'
            f'<td>{html.escape(top_tools)}</td>'
            f'<td class="mono">{html.escape((s.get("session") or "")[:8])}</td>'
            "</tr>")
    return "\n".join(rows) or '<tr><td colspan="7" class="empty">no sessions</td></tr>'


def html_report(d, days_label):
    t = d["tokens"]
    gen = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    tiles = [
        ("Sessions", f"{len(d['sessions']):,}"),
        ("User prompts", f"{d['prompts']:,}"),
        ("Active time", f"{d['hours']:g}h"),
        ("Output tokens", fmt_tokens(t["output"])),
        ("Cache read", fmt_tokens(t["cache_read"])),
    ]
    tiles_html = "".join(
        f'<div class="tile"><div class="tlabel">{html.escape(k)}</div><div class="tval">{html.escape(v)}</div></div>'
        for k, v in tiles)
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Agent Telemetry</title>
<style>
.viz-root {{
  --surface-1:#fcfcfb; --page:#f9f9f7; --ink:#0b0b0b; --ink-2:#52514e; --muted:#898781;
  --grid:#e1e0d9; --baseline:#c3c2b7; --series-1:#2a78d6; --border:rgba(11,11,11,0.10);
}}
@media (prefers-color-scheme: dark) {{ .viz-root {{
  --surface-1:#1a1a19; --page:#0d0d0d; --ink:#ffffff; --ink-2:#c3c2b7; --muted:#898781;
  --grid:#2c2c2a; --baseline:#383835; --series-1:#3987e5; --border:rgba(255,255,255,0.10);
}} }}
* {{ box-sizing:border-box; margin:0; }}
body {{ font-family:system-ui,-apple-system,"Segoe UI",sans-serif; }}
.viz-root {{ background:var(--page); color:var(--ink); min-height:100vh; padding:24px; }}
h1 {{ font-size:18px; margin-bottom:2px; }}
.sub {{ color:var(--muted); font-size:12px; margin-bottom:20px; }}
.tiles {{ display:flex; flex-wrap:wrap; gap:12px; margin-bottom:20px; }}
.tile {{ background:var(--surface-1); border:1px solid var(--border); border-radius:8px; padding:12px 16px; min-width:130px; }}
.tlabel {{ color:var(--ink-2); font-size:12px; }}
.tval {{ font-size:26px; font-weight:600; margin-top:2px; }}
.grid2 {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:12px; margin-bottom:12px; }}
.card {{ background:var(--surface-1); border:1px solid var(--border); border-radius:8px; padding:16px; }}
.card h2 {{ font-size:13px; font-weight:600; color:var(--ink-2); margin-bottom:12px; }}
.vchart {{ display:flex; align-items:flex-end; gap:2px; height:96px; border-bottom:1px solid var(--baseline); }}
.vslot {{ position:relative; flex:1 1 0; display:flex; align-items:flex-end; min-width:4px; }}
.vbar {{ width:100%; background:var(--series-1); border-radius:4px 4px 0 0; }}
.vbar.zero {{ background:var(--grid); }}
.vslot .tip {{ display:none; position:absolute; bottom:100%; left:50%; transform:translateX(-50%);
  background:var(--ink); color:var(--page); font-size:11px; padding:3px 7px; border-radius:4px; white-space:nowrap; z-index:2; }}
.vslot:hover .tip {{ display:block; }}
.axisnote {{ color:var(--muted); font-size:11px; margin-top:6px; }}
.hrow {{ display:flex; align-items:center; gap:8px; margin-bottom:6px; }}
.hlabel {{ width:130px; font-size:12px; color:var(--ink-2); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.htrack {{ flex:1; }}
.hbar {{ height:14px; background:var(--series-1); border-radius:0 4px 4px 0; }}
.hval {{ width:56px; text-align:right; font-size:12px; font-variant-numeric:tabular-nums; }}
table {{ width:100%; border-collapse:collapse; font-size:12px; }}
th {{ text-align:left; color:var(--muted); font-weight:500; padding:4px 8px; border-bottom:1px solid var(--grid); }}
td {{ padding:4px 8px; border-bottom:1px solid var(--grid); }}
td.num {{ font-variant-numeric:tabular-nums; }}
td.mono {{ font-family:ui-monospace,monospace; color:var(--muted); }}
.empty {{ color:var(--muted); font-size:12px; }}
.tablewrap {{ overflow-x:auto; }}
</style></head>
<body class="viz-root">
<h1>Agent Telemetry</h1>
<div class="sub">{html.escape(days_label)} · generated {gen} · sessions.jsonl + events.jsonl</div>
<div class="tiles">{tiles_html}</div>
<div class="card" style="margin-bottom:12px"><h2>Daily activity — user prompts</h2>{daily_chart(d["daily_prompts"])}</div>
<div class="grid2">
  <div class="card"><h2>Tool calls</h2>{hbar_rows(d["tools"])}</div>
  <div class="card"><h2>Work-loop events</h2>{hbar_rows(d["event_mix"])}</div>
  <div class="card"><h2>Skill invocations</h2>{hbar_rows(d["skill_mix"])}</div>
  <div class="card"><h2>Models (assistant msgs)</h2>{hbar_rows(d["models"])}</div>
</div>
<div class="card tablewrap"><h2>Recent sessions</h2>
<table><thead><tr><th>start (UTC)</th><th>active</th><th>prompts</th><th>asst msgs</th><th>out tok</th><th>top tools</th><th>id</th></tr></thead>
<tbody>{sessions_table(d["sessions"])}</tbody></table></div>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, help="restrict to the last N days")
    ap.add_argument("--html", metavar="PATH", help="write a static HTML dashboard")
    args = ap.parse_args()

    d = collect(args.days)
    console_report(d)
    if args.html:
        label = f"last {args.days} days" if args.days else "all time"
        out = Path(args.html)
        out.write_text(html_report(d, label), encoding="utf-8")
        print(f"\nhtml dashboard -> {out}")


if __name__ == "__main__":
    main()
