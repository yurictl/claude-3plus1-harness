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
#   escape-log.sh add --what TEXT --missed RULE-OR-none --destination rule|fixture|wip|sharpen
#                     [--severity blocker|warning] [--fixture PATH] [--note TEXT]
#   escape-log.sh list [N]      recent escapes, newest first
#   escape-log.sh count         total, and count since the last rubric change
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
    [ -n "$dest" ] || { echo "escape-log add: --destination is required (rule|fixture|wip|sharpen)" >&2; exit 64; }
    case "$dest" in
      rule|fixture|wip|sharpen) ;;
      *) echo "escape-log add: --destination must be one of rule|fixture|wip|sharpen" >&2; exit 64 ;;
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

  list)
    n="${1:-10}"
    [ -f "$STORE" ] || { echo "no escapes logged yet ($STORE)"; exit 0; }
    N="$n" STORE="$STORE" python3 - <<'EOF'
import json, os
rows = [json.loads(l) for l in open(os.environ["STORE"]) if l.strip()]
for r in rows[-int(os.environ["N"]):][::-1]:
    sev = f"[{r['severity']}] " if r.get("severity") else ""
    print(f"{r['ts']}  {sev}{r['what']}")
    print(f"    missed: {r.get('missed_rule') or '(no rule existed)'}   -> {r['destination']}"
          + (f"   fixture: {r['fixture']}" if r.get("fixture") else ""))
EOF
    ;;

  count)
    [ -f "$STORE" ] || { echo "escapes: 0"; exit 0; }
    rubric_sha=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:16])' "$RUBRIC" 2>/dev/null || echo "")
    RSHA="$rubric_sha" STORE="$STORE" python3 - <<'EOF'
import json, os
rows = [json.loads(l) for l in open(os.environ["STORE"]) if l.strip()]
cur = os.environ["RSHA"]
since = sum(1 for r in rows if r.get("rubric_sha256") == cur)
print(f"escapes: {len(rows)} total, {since} against the current rubric")
EOF
    ;;

  *)
    echo "usage: escape-log.sh add --what TEXT --destination rule|fixture|wip|sharpen [--missed RULE] [--severity S] [--fixture PATH] [--note TEXT]" >&2
    echo "       escape-log.sh list [N]" >&2
    echo "       escape-log.sh count" >&2
    exit 64
    ;;
esac
