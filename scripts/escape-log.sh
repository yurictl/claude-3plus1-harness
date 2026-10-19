#!/usr/bin/env bash
# Escape log — the one number that describes whether the harness works.
#
# An "escape" is a failure that reached runtime or review DESPITE a clean grade:
# the rubric had no rule for it, or the rule was there and did not fire. Escapes
# are what `docs/wip/harvest-failure-modes.md` collects in prose; this makes them
# countable, so the health panel can say "3 escapes since the last rubric change"
# instead of the telemetry only being able to say "you ran 40 sessions".
#
# Single writer by design (like grade-marker.sh): one shape, one place, greppable.
# Called by /checkpoint when it finds a verification-relevant event.
#
#   escape-log.sh add --what TEXT --missed RULE-OR-none --destination invariant|rule|fixture|wip|sharpen
#                     [--severity blocker|warning] [--fixture PATH] [--note TEXT]
#   escape-log.sh addressed --last|--ts TS --by TEXT [--test NAME]
#                               append a closure row: the countermeasure now exists
#   escape-log.sh list [N]      recent escapes, newest first
#   escape-log.sh count         total, addressed, and count since the last rubric change
#
# Destination `invariant` is asked first: if a property of the STATE should have
# held (not a pattern in a diff), it goes to scripts/invariants/registry.tsv with a
# hit/clear row in tests/invariants/retro.tsv — no rubric rule, no golden fixture.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}" || exit 1
. scripts/harness.conf

STORE_DIR="${TELEMETRY_DIR:-.claude/telemetry}"
STORE="$STORE_DIR/escapes.jsonl"

cmd="${1:-}"; shift || true

case "$cmd" in
  add)
    what=""; missed=""; dest=""; severity=""; fixture=""; note=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --what)        what="${2:?}"; shift 2 ;;
        --missed)      missed="${2:?}"; shift 2 ;;
        --destination) dest="${2:?}"; shift 2 ;;
        --severity)    severity="${2:?}"; shift 2 ;;
        --fixture)     fixture="${2:?}"; shift 2 ;;
        --note)        note="${2:?}"; shift 2 ;;
        *) echo "escape-log: unknown argument $1" >&2; exit 64 ;;
      esac
    done
    [ -n "$what" ] || { echo "escape-log add: --what is required (what actually failed)" >&2; exit 64; }
    [ -n "$dest" ] || { echo "escape-log add: --destination is required (invariant|rule|fixture|wip|sharpen)" >&2; exit 64; }
    case "$dest" in
      invariant|rule|fixture|wip|sharpen) ;;
      *) echo "escape-log add: --destination must be one of invariant|rule|fixture|wip|sharpen" >&2; exit 64 ;;
    esac

    mkdir -p "$STORE_DIR"
    rubric_sha=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:16])' "$RUBRIC" 2>/dev/null || echo "")
    WHAT="$what" MISSED="$missed" DEST="$dest" SEV="$severity" FIX="$fixture" NOTE="$note" \
    RSHA="$rubric_sha" STORE="$STORE" python3 - <<'EOF'
import json, os, datetime
row = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "what": os.environ["WHAT"],
    "missed_rule": os.environ["MISSED"] or None,
    "destination": os.environ["DEST"],
    "severity": os.environ["SEV"] or None,
    "fixture": os.environ["FIX"] or None,
    "note": os.environ["NOTE"] or None,
    "rubric_sha256": os.environ["RSHA"] or None,
}
with open(os.environ["STORE"], "a") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
print(f"logged escape -> {os.environ['STORE']} (destination: {row['destination']})")
EOF
    ;;

  addressed)
    # Append-only closure record: the escape's countermeasure now exists. The
    # original row is never edited; the panel subtracts addressed escapes so
    # "N open" means something. Needed because a countermeasure is not always a
    # rubric rule: an invariant has no rubric hash to file the escape against.
    target=""; by=""; test_name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --ts)   target="${2:?}"; shift 2 ;;
        --last) target="LAST"; shift ;;
        --by)   by="${2:?}"; shift 2 ;;
        --test) test_name="${2:?}"; shift 2 ;;
        *) echo "escape-log: unknown argument $1" >&2; exit 64 ;;
      esac
    done
    [ -n "$target" ] || { echo "escape-log addressed: pass --last or --ts TIMESTAMP" >&2; exit 64; }
    [ -n "$by" ]     || { echo "escape-log addressed: --by is required (what now catches it)" >&2; exit 64; }
    [ -f "$STORE" ]  || { echo "escape-log addressed: no escapes logged yet ($STORE)" >&2; exit 1; }
    TARGET="$target" BY="$by" TEST="$test_name" STORE="$STORE" python3 - <<'EOF'
import json, os, datetime, sys
store = os.environ["STORE"]
rows = [json.loads(l) for l in open(store) if l.strip()]
escapes = [r for r in rows if r.get("type") != "addressed"]
target = os.environ["TARGET"]
if target == "LAST":
    if not escapes:
        sys.exit("escape-log addressed: no escape rows to address")
    target = escapes[-1]["ts"]
elif not any(r["ts"] == target for r in escapes):
    sys.exit(f"escape-log addressed: no escape logged at {target}")
if any(r.get("type") == "addressed" and r.get("target_ts") == target for r in rows):
    sys.exit(f"escape-log addressed: {target} is already marked addressed")
row = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "type": "addressed", "target_ts": target, "by": os.environ["BY"], "test": os.environ["TEST"] or None}
with open(store, "a") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
print(f"escape {target} marked addressed by: {row['by']}")
EOF
    ;;

  list)
    n="${1:-10}"
    [ -f "$STORE" ] || { echo "no escapes logged yet ($STORE)"; exit 0; }
    N="$n" STORE="$STORE" python3 - <<'EOF'
import json, os
rows = [json.loads(l) for l in open(os.environ["STORE"]) if l.strip()]
closed = {r.get("target_ts"): r for r in rows if r.get("type") == "addressed"}
rows = [r for r in rows if r.get("type") != "addressed"]
for r in rows[-int(os.environ["N"]):][::-1]:
    sev = f"[{r['severity']}] " if r.get("severity") else ""
    print(f"{r['ts']}  {sev}{r['what']}")
    print(f"    missed: {r.get('missed_rule') or '(no rule existed)'}   -> {r['destination']}"
          + (f"   fixture: {r['fixture']}" if r.get("fixture") else ""))
    if r["ts"] in closed:
        print(f"    addressed by: {closed[r['ts']]['by']}")
EOF
    ;;

  count)
    [ -f "$STORE" ] || { echo "escapes: 0"; exit 0; }
    rubric_sha=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:16])' "$RUBRIC" 2>/dev/null || echo "")
    RSHA="$rubric_sha" STORE="$STORE" python3 - <<'EOF'
import json, os
rows = [json.loads(l) for l in open(os.environ["STORE"]) if l.strip()]
closed = {r.get("target_ts") for r in rows if r.get("type") == "addressed"}
rows = [r for r in rows if r.get("type") != "addressed"]
cur = os.environ["RSHA"]
since = sum(1 for r in rows if r.get("rubric_sha256") == cur and r["ts"] not in closed)
print(f"escapes: {len(rows)} total, {len(closed)} addressed, {since} open against the current rubric")
EOF
    ;;

  *)
    echo "usage: escape-log.sh add --what TEXT --destination invariant|rule|fixture|wip|sharpen [--missed RULE] [--severity S] [--fixture PATH] [--note TEXT]" >&2
    echo "       escape-log.sh addressed --last|--ts TS --by TEXT [--test NAME]" >&2
    echo "       escape-log.sh list [N]" >&2
    echo "       escape-log.sh count" >&2
    exit 64
    ;;
esac
