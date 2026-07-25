#!/usr/bin/env bash
# Grade marker management — the harness trust anchor.
#
# Two artifacts, one writer (this script):
#   GRADE_RECORD (.claude/last-grade.json) — the findings record /review produces
#   GRADE_MARKER (.claude/grade-ok)        — the content fingerprint the gate checks
#
# The marker is not a timestamp: it holds a fingerprint of the protected paths at
# grade time, so `touch` can't forge it and any edit (or revert) after grading
# invalidates it. And it cannot be stamped bare: `stamp` requires a fresh record
# whose fingerprint and rubric hash — both computed HERE, never supplied by the
# caller — match the current tree. Stamping is therefore no longer one command
# away from an ungraded push; it requires having produced a findings artifact,
# and that artifact is appended to the grade log for after-the-fact audit.
#
# Residual trust (unchanged, and now bounded): the record proves a grade was
# *reported*, not that it was *performed*. What changed is the cost of faking it —
# from `stamp` to fabricating a findings record consistent with the diff — and
# that fakes are now durable and auditable instead of invisible.
#
#   hash    — print the current fingerprint of the protected paths
#   rubric  — print the current rubric hash
#   record  — read findings JSON on stdin, write GRADE_RECORD (adds fingerprint,
#             rubric hash and timestamp itself). Called by /review.
#   stamp   — validate GRADE_RECORD, then write GRADE_MARKER + append grade log
#   check   — exit 0 if the marker matches the current state;
#             1 if missing, 2 if stale (fingerprint mismatch)
#   show    — print the current record, human-readable (no side effects)
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}" || exit 1
. scripts/harness.conf

MARKER="${GRADE_MARKER:-.claude/grade-ok}"
RECORD="${GRADE_RECORD:-.claude/last-grade.json}"
TTL_MIN="${GRADE_RECORD_TTL_MIN:-45}"
STORE_DIR="${TELEMETRY_DIR:-.claude/telemetry}"

fingerprint() {
  HARNESS_PROTECTED="$PROTECTED_PATHS" python3 - <<'EOF'
import hashlib, os, sys
h = hashlib.sha256()
seen = False
for root in os.environ["HARNESS_PROTECTED"].split():
    if os.path.isfile(root):
        entries = [root]
    elif os.path.isdir(root):
        entries = []
        for dirpath, dirs, files in os.walk(root):
            dirs.sort()
            entries.extend(os.path.join(dirpath, f) for f in sorted(files))
    else:
        # A protected path that does not exist is a configuration error, not an
        # empty set: fail loudly rather than fingerprinting nothing.
        print(f"grade-marker: protected path not found: {root}", file=sys.stderr)
        raise SystemExit(3)
    for p in entries:
        seen = True
        h.update(p.encode())
        with open(p, "rb") as fh:
            h.update(fh.read())
if not seen:
    print("grade-marker: protected paths contain no files", file=sys.stderr)
    raise SystemExit(3)
print(h.hexdigest())
EOF
}

rubric_hash() {
  [ -f "$RUBRIC" ] || { echo "grade-marker: missing rubric $RUBRIC" >&2; return 3; }
  python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$RUBRIC"
}

case "${1:-}" in
  hash)
    fingerprint
    ;;

  rubric)
    rubric_hash
    ;;

  record)
    # /review pipes its findings here. The caller supplies only what it observed;
    # the fingerprint, the rubric hash and the timestamp are computed here so they
    # cannot be back-dated or pointed at a different tree.
    #
    # stdin is consumed here, in bash: `python3 -` takes its *program* from stdin,
    # so the interpreter and the payload cannot share that channel.
    payload=$(cat)
    fp=$(fingerprint) || exit 3
    rh=$(rubric_hash) || exit 3
    mkdir -p "$(dirname "$RECORD")"
    PAYLOAD="$payload" FP="$fp" RH="$rh" RECORD_PATH="$RECORD" python3 - <<'EOF' || exit 1
import json, os, sys, datetime

raw = os.environ.get("PAYLOAD", "").strip()
if not raw:
    print("grade-marker record: no findings JSON on stdin", file=sys.stderr)
    raise SystemExit(1)
try:
    d = json.loads(raw)
except Exception as e:
    print(f"grade-marker record: stdin is not valid JSON ({e})", file=sys.stderr)
    raise SystemExit(1)

# Required shape. Counts are integers; `graded` names what was actually read.
missing = [k for k in ("blocker", "warning", "caveat", "graded") if k not in d]
if missing:
    print(f"grade-marker record: missing required keys: {', '.join(missing)}", file=sys.stderr)
    print('expected: {"blocker":0,"warning":0,"caveat":0,"graded":["path",...],"findings":["[SEVERITY] ..."]}', file=sys.stderr)
    raise SystemExit(1)
for k in ("blocker", "warning", "caveat"):
    if not isinstance(d[k], int) or d[k] < 0:
        print(f"grade-marker record: {k} must be a non-negative integer", file=sys.stderr)
        raise SystemExit(1)
graded = d["graded"]
if not isinstance(graded, list) or not graded or not all(isinstance(x, str) and x.strip() for x in graded):
    print("grade-marker record: `graded` must be a non-empty list of paths actually read", file=sys.stderr)
    raise SystemExit(1)

findings = d.get("findings", [])
if not isinstance(findings, list):
    print("grade-marker record: `findings` must be a list of report lines", file=sys.stderr)
    raise SystemExit(1)
declared = d["blocker"] + d["warning"] + d["caveat"]
if declared and len(findings) < declared:
    print(f"grade-marker record: {declared} findings counted but only {len(findings)} reported — "
          "the record must carry the lines it counts", file=sys.stderr)
    raise SystemExit(1)

rec = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "fingerprint": os.environ["FP"],
    "rubric_sha256": os.environ["RH"],
    "blocker": d["blocker"],
    "warning": d["warning"],
    "caveat": d["caveat"],
    "graded": graded,
    "findings": findings,
    "session": d.get("session", ""),
}
with open(os.environ["RECORD_PATH"], "w") as fh:
    json.dump(rec, fh, ensure_ascii=False, indent=1)
    fh.write("\n")
print(f"recorded {os.environ['RECORD_PATH']}: "
      f"{rec['blocker']} blocker / {rec['warning']} warning / {rec['caveat']} caveat "
      f"over {len(graded)} file(s)")
EOF
    ;;

  stamp)
    # Validate the record against the current tree, then stamp. Every refusal
    # names the reason: a silent refusal would be indistinguishable from a pass.
    [ -f "$RECORD" ] || {
      echo "REFUSED: no grade record at $RECORD." >&2
      echo "The marker is stamped from a findings record, not on request. Run /review:" >&2
      echo "  it grades, pipes findings into 'grade-marker.sh record', then stamps." >&2
      exit 1
    }
    fp=$(fingerprint) || exit 3
    rh=$(rubric_hash) || exit 3
    FP="$fp" RH="$rh" RECORD_PATH="$RECORD" TTL="$TTL_MIN" python3 - <<'EOF' || exit 1
import json, os, sys, datetime

try:
    rec = json.load(open(os.environ["RECORD_PATH"]))
except Exception as e:
    print(f"REFUSED: grade record is unreadable ({e}). Re-run /review.", file=sys.stderr)
    raise SystemExit(1)

def refuse(msg):
    print(f"REFUSED: {msg}", file=sys.stderr)
    raise SystemExit(1)

if rec.get("blocker", 1) != 0:
    refuse(f"the recorded grade has {rec.get('blocker')} [BLOCKER] finding(s). "
           "Fix them and re-grade; the gate opens on zero blockers only.")

if rec.get("fingerprint") != os.environ["FP"]:
    refuse("the protected paths changed after the grade was recorded "
           "(record fingerprint != current). Re-run /review on the current state.")

if rec.get("rubric_sha256") != os.environ["RH"]:
    refuse("the rubric changed after the grade was recorded. A grade against an "
           "old rubric is not a grade. Re-run /review.")

try:
    ts = datetime.datetime.strptime(rec["ts"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc)
except Exception:
    refuse("the grade record has no usable timestamp. Re-run /review.")

age_min = (datetime.datetime.now(datetime.timezone.utc) - ts).total_seconds() / 60
ttl = float(os.environ["TTL"])
if age_min > ttl:
    refuse(f"the grade record is {age_min:.0f} min old (TTL {ttl:.0f} min) — it belongs "
           "to a past session. Re-run /review.")
if age_min < -5:
    refuse("the grade record is timestamped in the future. Re-run /review.")
EOF
    mkdir -p "$(dirname "$MARKER")" "$STORE_DIR"
    printf '%s\n' "$fp" > "$MARKER"
    # Append to the durable grade log — this is what makes a fabricated grade
    # auditable after the fact, and what feeds the harness-health panel.
    FP="$fp" RECORD_PATH="$RECORD" LOG="$STORE_DIR/grades.jsonl" python3 - <<'EOF'
import json, os, datetime
rec = json.load(open(os.environ["RECORD_PATH"]))
row = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "graded_at": rec.get("ts"),
    "fingerprint": os.environ["FP"][:16],
    "rubric_sha256": rec.get("rubric_sha256", "")[:16],
    "blocker": rec.get("blocker"),
    "warning": rec.get("warning"),
    "caveat": rec.get("caveat"),
    "files": len(rec.get("graded", [])),
}
with open(os.environ["LOG"], "a") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
EOF
    echo "stamped $MARKER ($(cut -c1-12 "$MARKER")…) from $RECORD"
    ;;

  check)
    [ -f "$MARKER" ] || exit 1
    cur=$(fingerprint) || exit 3
    [ "$cur" = "$(cat "$MARKER")" ] || exit 2
    ;;

  show)
    [ -f "$RECORD" ] || { echo "no grade record at $RECORD"; exit 1; }
    python3 -c '
import json,sys
r=json.load(open(sys.argv[1]))
print(f"graded {r.get(\"ts\")} — {r.get(\"blocker\")} blocker / {r.get(\"warning\")} warning / {r.get(\"caveat\")} caveat")
print("files: " + ", ".join(r.get("graded", [])))
for line in r.get("findings", []):
    print("  " + line)
' "$RECORD"
    ;;

  *)
    echo "usage: grade-marker.sh hash|rubric|record|stamp|check|show" >&2
    exit 64
    ;;
esac
