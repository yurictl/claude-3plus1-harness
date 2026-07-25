#!/usr/bin/env bash
# Golden-set replay — the calibration layer. Feeds each fixture to a headless
# grader (`claude -p`) and checks the expected finding is still produced.
#
# Three sets, three different jobs (scripts/harness.conf: GOLDEN_SETS):
#   held-in   — written alongside the rule it checks; drives rule authoring
#   held-out   — a surface NEVER consulted while writing a rule; the only honest
#                answer to "does this rubric generalize?". Accept a rubric change
#                only if held-in improves and held-out does not regress.
#   clean      — must produce ZERO findings. Without it the run measures recall
#                only, and a rubric that flags everything scores a perfect
#                catch-rate. This is the precision half.
#
# Two instruments beyond pass/fail:
#   --tiers    grade with the pinned model AND the cheap one. A rule only the
#              cheap tier needs is a rule the frontier model already knows.
#   --ablate   grade with NO rubric at all. Anything still caught is redundant to
#              model priors — dead weight with a decay curve, not earned signal.
#
# Runs are appended to $TELEMETRY_DIR/replay.jsonl; per-set rates are compared
# against the committed baseline ($GOLDEN_BASELINE) so a regression is loud.
#
#   bash scripts/replay.sh [--set held-in|held-out|clean|all] [--model ALIAS]
#                          [--tiers] [--ablate] [--update-baseline] [-q]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/harness.conf

SET_ARG="all"; MODEL="${GRADER_MODEL:-}"; TIERS=0; ABLATE=0; UPDATE_BASELINE=0; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --set)              SET_ARG="${2:?--set needs a value}"; shift 2 ;;
    --model)            MODEL="${2:?--model needs a value}"; shift 2 ;;
    --tiers)            TIERS=1; shift ;;
    --ablate)           ABLATE=1; shift ;;
    --update-baseline)  UPDATE_BASELINE=1; shift ;;
    -q|--quiet)         QUIET=1; shift ;;
    -h|--help)          sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

[ -f "$RUBRIC" ] || { echo "missing $RUBRIC" >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "the 'claude' CLI is not on PATH" >&2; exit 1; }

GOLDEN_ROOT="${GOLDEN_ROOT:-tests/golden}"
GOLDEN_SETS="${GOLDEN_SETS:-held-in held-out clean}"
BASELINE="${GOLDEN_BASELINE:-tests/golden/baseline.json}"
STORE_DIR="${TELEMETRY_DIR:-.claude/telemetry}"

case "$SET_ARG" in
  all) SETS="$GOLDEN_SETS" ;;
  *)   SETS="$SET_ARG" ;;
esac

# Tamper disclosure: a catch-rate computed against uncommitted fixtures or an
# uncommitted rubric is not comparable to the committed baseline — say so up
# front, so a claimed "N/N" always carries the caveat.
# shellcheck disable=SC2086
dirty=$(git status --porcelain -- $CALIBRATION_PATHS 2>/dev/null)
if [ -n "$dirty" ]; then
  echo "NOTE: uncommitted changes to calibration material — this catch-rate is"
  echo "provisional, not the committed baseline:"
  echo "$dirty" | sed 's/^/  /'
  echo
fi

RUBRIC_SHA=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:16])' "$RUBRIC")

# grade <case_file> <label> <model> <use_rubric:0|1> — echo the grader's output.
grade() {
  local case_file="$1" label="$2" model="$3" use_rubric="$4" prompt
  if [ "$use_rubric" = "1" ]; then
    prompt="You are a reviewer. Grade the material below against the following conventions. Report findings only, one per line, in the format: [SEVERITY] rule — detail. A violation carrying an inline '# reason:' justification is not silently accepted: report it as [CAVEAT] rule — detail — stated reason. If the material violates nothing, reply exactly: NO FINDINGS. Do not list passing rules.

=== CONVENTIONS ===
$(cat "$RUBRIC")

=== MATERIAL (${label}) ===
$(cat "$case_file")"
  else
    # Ablation: no rubric, only the reporting format. Whatever comes back is what
    # the model knows on its own — i.e. what the rubric does not need to say.
    prompt="You are a reviewer. Report any problems you find in the material below, one per line, in the format: [SEVERITY] rule — detail. If you find nothing worth reporting, reply exactly: NO FINDINGS. Do not list things that are fine.

=== MATERIAL (${label}) ===
$(cat "$case_file")"
  fi
  claude -p --model "$model" "$prompt" 2>/dev/null
}

# matched <output> <expected_pattern_or_NONE> — 0 if the fixture's expectation holds.
matched() {
  local out="$1" want="$2"
  if [ "$want" = "NONE" ]; then
    # Precision fixture: no severity-tagged finding may appear.
    ! printf '%s' "$out" | grep -qE '\[(BLOCKER|WARNING|CAVEAT)\]'
  else
    printf '%s' "$out" | grep -qE "$want"
  fi
}

# has_finding <output> — 0 if any severity-tagged finding is present.
has_finding() { printf '%s' "$1" | grep -qE '\[(BLOCKER|WARNING|CAVEAT)\]'; }

results_json="["
first_row=1
overall_miss=0
declare -a set_names=() set_pass=() set_total=()

for gset in $SETS; do
  dir_set="$GOLDEN_ROOT/$gset"
  [ -d "$dir_set" ] || { echo "SKIP set '$gset' (no $dir_set)"; continue; }

  echo "── $gset"
  s_pass=0; s_total=0

  for dir in "$dir_set"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    label="$gset/$name"
    case_file=$(find "$dir" -maxdepth 1 -name 'case.*' | head -1)

    if [ -z "$case_file" ] || [ ! -f "$dir/expected.txt" ]; then
      echo "MISS  $label — incomplete fixture (need case.<ext> + expected.txt)"
      s_total=$((s_total+1)); overall_miss=$((overall_miss+1)); continue
    fi
    want=$(tr -d '\r' < "$dir/expected.txt" | sed '/^[[:space:]]*$/d' | head -1)
    if [ -z "$want" ]; then
      # An empty expectation used to match everything and PASS silently.
      echo "MISS  $label — empty expected.txt (use a regex, or the literal NONE)"
      s_total=$((s_total+1)); overall_miss=$((overall_miss+1)); continue
    fi

    out=$(grade "$case_file" "$label" "$MODEL" 1)
    s_total=$((s_total+1))
    if matched "$out" "$want"; then
      verdict=pass; s_pass=$((s_pass+1)); echo "PASS  $label"
    else
      verdict=miss; overall_miss=$((overall_miss+1))
      echo "MISS  $label — expected /$want/, got:"
      printf '%s\n' "$out" | sed 's/^/      /' | head -8
    fi

    # --- optional probes ------------------------------------------------------
    cheap_caught="null"; ablate_caught="null"
    if [ "$TIERS" = "1" ] && [ -n "${GRADER_MODEL_CHEAP:-}" ]; then
      out_probe=$(grade "$case_file" "$label" "$GRADER_MODEL_CHEAP" 1)
      if matched "$out_probe" "$want"; then cheap_caught=true; else cheap_caught=false; fi
    fi
    if [ "$ABLATE" = "1" ] && [ "$gset" != "clean" ]; then
      # Ablation is meaningless for clean fixtures: with no rubric a model has
      # nothing to be silent about, so "findings" there measure nothing.
      out_probe=$(grade "$case_file" "$label" "$MODEL" 0)
      if has_finding "$out_probe"; then ablate_caught=true; else ablate_caught=false; fi
    fi

    [ "$first_row" = "1" ] || results_json+=","
    first_row=0
    results_json+=$(python3 -c '
import json,sys
print(json.dumps({"set":sys.argv[1],"fixture":sys.argv[2],"verdict":sys.argv[3],
                  "cheap_caught":json.loads(sys.argv[4]),
                  "caught_without_rubric":json.loads(sys.argv[5])}))' \
      "$gset" "$name" "$verdict" "$cheap_caught" "$ablate_caught")
  done

  echo "      $gset: ${s_pass}/${s_total}"
  echo
  set_names+=("$gset"); set_pass+=("$s_pass"); set_total+=("$s_total")
done
results_json+="]"

# --- report, baseline comparison, run log --------------------------------------
sets_json=$(python3 - "${set_names[@]:-}" <<'EOF'
import json, sys
names = sys.argv[1:]
print(json.dumps(names))
EOF
)
pass_json=$(printf '%s\n' "${set_pass[@]:-}" | python3 -c 'import json,sys;print(json.dumps([int(x) for x in sys.stdin.read().split()]))')
total_json=$(printf '%s\n' "${set_total[@]:-}" | python3 -c 'import json,sys;print(json.dumps([int(x) for x in sys.stdin.read().split()]))')

RESULTS="$results_json" SETS_J="$sets_json" PASS_J="$pass_json" TOTAL_J="$total_json" \
MODEL="$MODEL" CHEAP="${GRADER_MODEL_CHEAP:-}" RUBRIC_SHA="$RUBRIC_SHA" \
BASELINE="$BASELINE" STORE_DIR="$STORE_DIR" DIRTY="$dirty" \
TIERS="$TIERS" ABLATE="$ABLATE" UPDATE="$UPDATE_BASELINE" QUIET="$QUIET" python3 - <<'EOF'
import json, os, datetime, pathlib

res    = json.loads(os.environ["RESULTS"])
names  = json.loads(os.environ["SETS_J"])
passes = json.loads(os.environ["PASS_J"])
totals = json.loads(os.environ["TOTAL_J"])
rates  = {n: {"pass": p, "total": t} for n, p, t in zip(names, passes, totals)}

tp, tt = sum(passes), sum(totals)
print(f"catch-rate: {tp}/{tt}" + ("" if tt else " (no fixtures)"))
for n in names:
    print(f"  {n:<9} {rates[n]['pass']}/{rates[n]['total']}")

# --- decay classification (only meaningful with the probes on) ----------------
if os.environ["TIERS"] == "1" or os.environ["ABLATE"] == "1":
    print("\nrule standing per fixture:")
    print(f"  {'fixture':<28} {'pinned':<7} {'cheap':<7} {'no-rubric':<10} verdict")
    for r in res:
        if r["set"] == "clean":
            continue
        pinned = "yes" if r["verdict"] == "pass" else "NO"
        cheap  = {True: "yes", False: "no", None: "–"}[r["cheap_caught"]]
        abl    = {True: "yes", False: "no", None: "–"}[r["caught_without_rubric"]]
        if r["verdict"] != "pass":
            verdict = "RUBRIC MISS — the rule does not fire"
        elif r["caught_without_rubric"] is True:
            verdict = "REDUNDANT — the model catches it unaided; decay candidate"
        elif r["cheap_caught"] is False:
            verdict = "FRONTIER-ONLY — calibrated to the top tier, not portable"
        elif r["cheap_caught"] is True:
            verdict = "LOAD-BEARING — needed and portable across tiers"
        else:
            verdict = "load-bearing (run --ablate/--tiers for the full read)"
        print(f"  {r['set']+'/'+r['fixture']:<28} {pinned:<7} {cheap:<7} {abl:<10} {verdict}")

# --- baseline ------------------------------------------------------------------
bpath = pathlib.Path(os.environ["BASELINE"])
regressions = []
if os.environ["UPDATE"] == "1":
    bpath.parent.mkdir(parents=True, exist_ok=True)
    bpath.write_text(json.dumps({
        "updated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
        "model": os.environ["MODEL"],
        "rubric_sha256": os.environ["RUBRIC_SHA"],
        "sets": rates,
    }, indent=1) + "\n")
    print(f"\nbaseline updated -> {bpath}")
elif bpath.exists():
    try:
        base = json.loads(bpath.read_text())
        print(f"\nbaseline ({base.get('updated','?')}, model {base.get('model','?')}):")
        for n in names:
            b = base.get("sets", {}).get(n)
            if not b:
                print(f"  {n:<9} no baseline entry")
                continue
            now_rate  = rates[n]["pass"]  / rates[n]["total"]  if rates[n]["total"]  else 0
            base_rate = b["pass"] / b["total"] if b["total"] else 0
            delta = "same" if now_rate == base_rate else ("BETTER" if now_rate > base_rate else "REGRESSED")
            print(f"  {n:<9} {rates[n]['pass']}/{rates[n]['total']} vs {b['pass']}/{b['total']}  {delta}")
            if now_rate < base_rate:
                regressions.append(n)
    except Exception as e:
        print(f"\nbaseline unreadable ({e})")
else:
    print(f"\nno baseline yet — run with --update-baseline to record one at {bpath}")

if regressions:
    print("\nACCEPTANCE RULE: a rubric change is accepted only if held-in improves and "
          "held-out does not regress.")
    print("Regressed set(s): " + ", ".join(regressions) + " -> do not land this rubric change.")

# --- durable run log -----------------------------------------------------------
store = pathlib.Path(os.environ["STORE_DIR"])
store.mkdir(parents=True, exist_ok=True)
with (store / "replay.jsonl").open("a") as fh:
    fh.write(json.dumps({
        "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "model": os.environ["MODEL"],
        "cheap_model": os.environ["CHEAP"] if os.environ["TIERS"] == "1" else None,
        "ablation": os.environ["ABLATE"] == "1",
        "rubric_sha256": os.environ["RUBRIC_SHA"],
        "dirty_calibration": bool(os.environ["DIRTY"].strip()),
        "sets": rates,
        "fixtures": res,
    }, ensure_ascii=False) + "\n")

raise SystemExit(1 if regressions else 0)
EOF
baseline_rc=$?

[ "$overall_miss" -eq 0 ] || exit 1
exit $baseline_rc
