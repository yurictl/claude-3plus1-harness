#!/usr/bin/env bash
# Harness self-tests — the gate's own regression suite.
#
# The golden set (tests/golden/) calibrates the GRADER: does the rubric still
# catch a known violation? This suite calibrates the GATE: can the push gate be
# opened without a grade? Different failure, different fixture, same discipline.
#
# Every test below is either a bypass that once worked (marked WAS-OPEN) or an
# invariant the gate already had and must not lose. Zero LLM calls, zero network,
# runs in a scratch git repo per case — safe to run anywhere, fast enough to run
# on every harness edit.
#
#   bash tests/harness/run.sh          # all cases
#   bash tests/harness/run.sh -v       # show stderr of each blocked call
set -uo pipefail

SRC_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

pass=0
fail=0
SCRATCHES=()

cleanup() {
  for s in "${SCRATCHES[@]:-}"; do
    [ -n "$s" ] && [ -d "$s" ] && chmod -R u+rwX "$s" 2>/dev/null; rm -rf "$s" 2>/dev/null
  done
}
trap cleanup EXIT

# --- harness -------------------------------------------------------------------

ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; }

# mkscratch <with_baseline:0|1> — a minimal copy of the harness in a temp git repo.
mkscratch() {
  local with_baseline="$1"
  local s
  s=$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX") || return 1
  SCRATCHES+=("$s")

  mkdir -p "$s/scripts/hooks" "$s/docs/operations" "$s/src" "$s/tests/golden/held-in/demo" "$s/.claude"
  cp "$SRC_ROOT/scripts/harness.conf" "$s/scripts/"
  cp "$SRC_ROOT/scripts/grade-marker.sh" "$s/scripts/"
  cp "$SRC_ROOT/scripts/hooks/pre-push-grade.sh" "$s/scripts/hooks/"
  cp "$SRC_ROOT/scripts/hooks/protect-anchors.sh" "$s/scripts/hooks/"
  cp "$SRC_ROOT/docs/operations/conventions.md" "$s/docs/operations/"
  mkdir -p "$s/scripts/invariants" "$s/src/env"
  cp "$SRC_ROOT/scripts/check_invariants.py" "$s/scripts/"
  find "$SRC_ROOT/scripts/invariants" -maxdepth 1 -type f -exec cp {} "$s/scripts/invariants/" \;
  printf '[server]\nport = 8080\n' > "$s/src/env/dev.conf"
  printf '[server]\nport = 80\n'   > "$s/src/env/prod.conf"
  printf '[server]\nport = 8080\n' > "$s/src/app.conf"
  printf 'case\n' > "$s/tests/golden/held-in/demo/case.txt"
  printf 'x\n'    > "$s/tests/golden/held-in/demo/expected.txt"

  git -C "$s" init -q
  git -C "$s" config user.email harness@test.local
  git -C "$s" config user.name  "Harness Test"
  git -C "$s" add -A
  git -C "$s" commit -qm init

  # A baseline ref makes "committed but unpushed" computable. Without it the hook
  # must fail closed — that is the WAS-OPEN case below.
  [ "$with_baseline" = "1" ] && git -C "$s" update-ref refs/remotes/origin/main HEAD

  printf '%s' "$s"
}

# push_hook <scratch> — run the push gate; echoes stderr, returns its exit code.
push_hook() {
  local s="$1" out rc
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
        | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/hooks/pre-push-grade.sh" 2>&1)
  rc=$?
  [ "$VERBOSE" = "1" ] && [ -n "$out" ] && printf '      | %s\n' "$out" | head -6
  return $rc
}

# bash_hook <scratch> <command> — run the push gate against an arbitrary command.
bash_hook() {
  local s="$1" cmd="$2" out rc
  out=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd" \
        | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/hooks/pre-push-grade.sh" 2>&1)
  rc=$?
  [ "$VERBOSE" = "1" ] && [ -n "$out" ] && printf '      | %s\n' "$out" | head -4
  return $rc
}

# file_hook <scratch> <tool> <path> — run the anchor guard for a file tool.
file_hook() {
  local s="$1" tool="$2" path="$3" out rc
  out=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]}}))' "$tool" "$path" \
        | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/hooks/protect-anchors.sh" 2>&1)
  rc=$?
  [ "$VERBOSE" = "1" ] && [ -n "$out" ] && printf '      | %s\n' "$out" | head -4
  return $rc
}

marker() { bash -c "cd '$1' && . scripts/harness.conf && printf '%s' \"\$GRADE_MARKER\""; }

record() { # record <scratch> <blocker> [findings-count]
  local s="$1" b="$2" n="${3:-0}" json
  json=$(python3 -c '
import json,sys
b=int(sys.argv[1]); n=int(sys.argv[2])
print(json.dumps({"blocker":b,"warning":0,"caveat":0,
                  "graded":["src/app.conf"],
                  "findings":[f"[BLOCKER] rule — src/app.conf:{i+1} — detail" for i in range(n)]}))' "$b" "$n")
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/grade-marker.sh" record >/dev/null 2>&1
}

stamp() { CLAUDE_PROJECT_DIR="$1" bash "$1/scripts/grade-marker.sh" stamp >/dev/null 2>&1; }

echo "harness self-tests"
echo

# --- 1. WAS-OPEN: bare stamp opened the gate with no grade ---------------------
s=$(mkscratch 1)
if stamp "$s"; then
  bad "stamp-without-record is refused" "stamp succeeded with no grade record"
elif [ -f "$s/$(marker "$s")" ]; then
  bad "stamp-without-record is refused" "marker was written despite the refusal"
else
  ok "stamp-without-record is refused          [WAS-OPEN: one command opened the gate]"
fi

# --- 2. a grade record with blockers cannot be stamped -------------------------
s=$(mkscratch 1)
record "$s" 1 1
if stamp "$s"; then
  bad "stamp-refuses-blockers" "stamped a record carrying a [BLOCKER]"
else
  ok "stamp-refuses-blockers"
fi

# --- 3. record shape is validated (counts must carry their lines) --------------
s=$(mkscratch 1)
if printf '' | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/grade-marker.sh" record >/dev/null 2>&1; then
  bad "record-rejects-empty-stdin" "empty stdin accepted"
else ok "record-rejects-empty-stdin"; fi

if printf '{"blocker":0}' | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/grade-marker.sh" record >/dev/null 2>&1; then
  bad "record-rejects-missing-keys" "partial record accepted"
else ok "record-rejects-missing-keys"; fi

if printf '{"blocker":0,"warning":0,"caveat":0,"graded":[]}' | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/grade-marker.sh" record >/dev/null 2>&1; then
  bad "record-rejects-empty-graded" "record with nothing graded accepted"
else ok "record-rejects-empty-graded"; fi

if printf '{"blocker":0,"warning":2,"caveat":0,"graded":["src/app.conf"],"findings":[]}' | CLAUDE_PROJECT_DIR="$s" bash "$s/scripts/grade-marker.sh" record >/dev/null 2>&1; then
  bad "record-rejects-uncounted-findings" "2 findings counted, 0 reported — accepted"
else ok "record-rejects-uncounted-findings"; fi

# --- 4. ungraded change is blocked, graded change passes, later edit goes stale -
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
if push_hook "$s"; then
  bad "ungraded-change-blocked" "push allowed with an ungraded change"
else ok "ungraded-change-blocked"; fi

record "$s" 0 0
if ! stamp "$s"; then
  bad "graded-change-allowed" "stamp refused a clean record"
elif push_hook "$s"; then
  ok "graded-change-allowed"
else
  bad "graded-change-allowed" "push blocked after a clean grade"
fi

printf '[server]\nport = 7070\n' > "$s/src/app.conf"
if push_hook "$s"; then
  bad "stale-fingerprint-blocked" "push allowed after editing graded files"
else ok "stale-fingerprint-blocked"; fi

# --- 5. rubric change after the grade invalidates it --------------------------
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
record "$s" 0 0
printf '\n- `[BLOCKER]` **Loosened.**\n' >> "$s/docs/operations/conventions.md"
if stamp "$s"; then
  bad "stamp-refuses-changed-rubric" "stamped a grade recorded against a different rubric"
else ok "stamp-refuses-changed-rubric"; fi

# --- 6. a record from a past session is not stampable -------------------------
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
record "$s" 0 0
python3 - "$s" <<'EOF'
import json, sys, datetime, os
root = sys.argv[1]
p = os.path.join(root, ".claude", "last-grade.json")
rec = json.load(open(p))
old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=3)
rec["ts"] = old.strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(rec, open(p, "w"))
EOF
if stamp "$s"; then
  bad "stamp-refuses-stale-record" "stamped a 3h-old grade record"
else ok "stamp-refuses-stale-record"; fi

# --- 7. WAS-OPEN: the file tools were a second door to the anchors ------------
s=$(mkscratch 1)
if file_hook "$s" Write ".claude/grade-ok"; then
  bad "write-tool-marker-blocked" "Write to the marker allowed"
else ok "write-tool-marker-blocked                [WAS-OPEN: hash + Write forged a grade]"; fi

if file_hook "$s" Edit "$s/.claude/grade-ok"; then
  bad "write-tool-marker-blocked-abspath" "Edit of the marker via absolute path allowed"
else ok "write-tool-marker-blocked-abspath"; fi

if file_hook "$s" Write ".claude/last-grade.json"; then
  bad "write-tool-record-blocked" "Write to the grade record allowed"
else ok "write-tool-record-blocked"; fi

if file_hook "$s" Write "src/app.conf"; then
  ok "write-tool-other-paths-allowed"
else
  bad "write-tool-other-paths-allowed" "the anchor guard blocked an ordinary file"
fi

# --- 8. the Bash door stays shut ---------------------------------------------
s=$(mkscratch 1)
if bash_hook "$s" "touch .claude/grade-ok"; then
  bad "bash-touch-marker-blocked" "touch on the marker allowed"
else ok "bash-touch-marker-blocked"; fi

if bash_hook "$s" "python3 -c 'open(\".claude/last-grade.json\",\"w\")'"; then
  bad "bash-write-record-blocked" "shell write to the grade record allowed"
else ok "bash-write-record-blocked"; fi

if bash_hook "$s" "bash scripts/grade-marker.sh hash"; then
  ok "canonical-script-allowed"
else
  bad "canonical-script-allowed" "the canonical writer was blocked"
fi

# --- 9. WAS-OPEN: committed change + no baseline ref = unguarded push ---------
s=$(mkscratch 0)   # no origin/main, as after `rm -rf .git && git init`
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
git -C "$s" add -A
git -C "$s" commit -qm "change the product"
if push_hook "$s"; then
  bad "no-baseline-committed-change-blocked" "push allowed: committed change invisible without origin/main"
else
  ok "no-baseline-committed-change-blocked    [WAS-OPEN: commit-then-push skipped the gate]"
fi

# and with a baseline present the same shape is still caught
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
git -C "$s" add -A
git -C "$s" commit -qm "change the product"
if push_hook "$s"; then
  bad "baseline-committed-change-blocked" "push allowed for a committed ungraded change"
else ok "baseline-committed-change-blocked"; fi

# --- 10. weakened-test gate ---------------------------------------------------
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
printf 'weakened\n' > "$s/tests/golden/held-in/demo/expected.txt"
record "$s" 0 0
stamp "$s"
if push_hook "$s"; then
  bad "weakened-test-gate" "product + calibration in one push allowed"
else ok "weakened-test-gate"; fi

# --- 11. unfingerprintable protected paths fail closed -----------------------
s=$(mkscratch 1)
printf 'secret\n' > "$s/src/unreadable.conf"
chmod 000 "$s/src/unreadable.conf" 2>/dev/null
if [ -r "$s/src/unreadable.conf" ]; then
  printf 'SKIP  fingerprint-failure-fails-closed (file still readable — running as root?)\n'
else
  if push_hook "$s"; then
    bad "fingerprint-failure-fails-closed" "push allowed while the protected tree could not be hashed"
  else ok "fingerprint-failure-fails-closed"; fi
fi
chmod u+rw "$s/src/unreadable.conf" 2>/dev/null

# --- 12. clean tree, nothing outgoing: the gate stays out of the way ---------
s=$(mkscratch 1)
if push_hook "$s"; then
  ok "clean-tree-not-gated"
else
  bad "clean-tree-not-gated" "push blocked with nothing outgoing"
fi

# --- 13. state invariants: the whole tree, not the diff ----------------------
# Every case grades first, so a block here can only be the invariant gate.
graded_push() { record "$1" 0 0 && stamp "$1" && push_hook "$1"; }

# 13a. a change that keeps the twins in step passes
s=$(mkscratch 1)
printf 'timeout = 30\n' >> "$s/src/env/dev.conf"; printf 'timeout = 60\n' >> "$s/src/env/prod.conf"
if graded_push "$s"; then ok "invariant-clean-change-allowed"
else bad "invariant-clean-change-allowed" "a change keeping both environments in step was blocked"; fi

# 13b. a key added to one twin only blocks, even with a clean grade
s=$(mkscratch 1)
printf 'timeout = 30\n' >> "$s/src/env/dev.conf"
if graded_push "$s"; then bad "invariant-violation-blocks-graded-push" "twin drift pushed after a clean grade"
else ok "invariant-violation-blocks-graded-push   [the diff reads correct; the untouched twin is wrong]"; fi

# 13c. the violation already sits in the tree; this push touches something else under src
s=$(mkscratch 1)
printf 'timeout = 30\n' >> "$s/src/env/dev.conf"
git -C "$s" commit -qam "drift, already on origin"; git -C "$s" update-ref refs/remotes/origin/main HEAD
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
if graded_push "$s"; then bad "invariant-whole-tree-checked" "a standing violation outside the push was waved through"
else ok "invariant-whole-tree-checked"; fi

# 13d. ...a waiver with a reason unblocks it — but only when it was landed on its own
printf 'INV-ENV-KEY-PARITY\tsrc/env/prod.conf\tprod reads timeout from the platform default\n' >> "$s/scripts/invariants/exceptions.tsv"
git -C "$s" add -A scripts/invariants; git -C "$s" commit -qm "declare the waiver" -- scripts/invariants
git -C "$s" update-ref refs/remotes/origin/main HEAD
if graded_push "$s"; then ok "invariant-declared-exception-honoured"
else bad "invariant-declared-exception-honoured" "a landed, reasoned waiver did not unblock"; fi

# 13e. a waiver in the SAME push as the product change is the weakened-test pattern
s=$(mkscratch 1)
printf 'timeout = 30\n' >> "$s/src/env/dev.conf"
printf 'INV-ENV-KEY-PARITY\tsrc/env/prod.conf\tlater\n' >> "$s/scripts/invariants/exceptions.tsv"
if graded_push "$s"; then bad "invariant-waiver-with-product-blocked" "violation + its waiver pushed together"
else ok "invariant-waiver-with-product-blocked    [weakening the check in the same push]"; fi

# 13f. a waiver without a reason is not a waiver
s=$(mkscratch 1)
printf 'INV-ENV-KEY-PARITY\tsrc/env/prod.conf\t\n' >> "$s/scripts/invariants/exceptions.tsv"
git -C "$s" commit -qam "reasonless waiver"; git -C "$s" update-ref refs/remotes/origin/main HEAD
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
if graded_push "$s"; then bad "invariant-waiver-needs-reason" "a reasonless waiver was accepted"
else ok "invariant-waiver-needs-reason"; fi

# 13g. the checker gone -> blocked, not skipped
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
rm -f "$s/scripts/check_invariants.py"
if graded_push "$s"; then bad "invariant-missing-checker-fails-closed" "push allowed with the checker removed"
else ok "invariant-missing-checker-fails-closed"; fi

# 13h. a check that crashes is "could not run", never a pass
s=$(mkscratch 1)
printf 'import sys\nsys.exit(3)\n' > "$s/scripts/invariants/env-key-parity.py"
git -C "$s" commit -qam "a check that cannot run"; git -C "$s" update-ref refs/remotes/origin/main HEAD
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
if graded_push "$s"; then bad "invariant-crashing-check-fails-closed" "a crashing check let the push through"
else ok "invariant-crashing-check-fails-closed"; fi

# --- 14. WAS-OPEN: the gate could be switched off by deleting its config -------
# scripts/harness.conf is not a trust anchor, so nothing stops a session from
# removing it. Both hooks sourced it with `|| exit 0`: one `rm` and every gate —
# grade, weakened-test, invariants, and the Write/Edit anchor guard — let
# everything through, silently. Loading failures now block pushes, leave
# unrelated commands alone, and the anchor guards fall back to default paths.

# 14a. config gone -> a push with a change is blocked
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
anchor_path=$(marker "$s")
rm -f "$s/scripts/harness.conf"
if push_hook "$s"; then bad "missing-harness-conf-fails-closed" "push allowed with harness.conf removed"
else ok "missing-harness-conf-fails-closed       [WAS-OPEN: rm one file disabled the gate]"; fi

# 14b. ...while a non-push command is still allowed
if bash_hook "$s" "ls -la"; then ok "missing-config-still-allows-reads"
else bad "missing-config-still-allows-reads" "an unrelated command was blocked"; fi

# 14c. ...and the Bash anchor guard still holds without it
if bash_hook "$s" "touch $anchor_path"; then bad "bash-anchor-guard-survives-missing-config" "anchor write via Bash allowed"
else ok "bash-anchor-guard-survives-missing-config"; fi

# 14d. ...and so does the Write/Edit anchor guard (the second door)
if file_hook "$s" Write "$s/$anchor_path"; then bad "file-anchor-guard-survives-missing-config" "Write to the marker allowed without harness.conf"
else ok "file-anchor-guard-survives-missing-config [WAS-OPEN: same rm opened the file-tool door]"; fi

# 14e. a half-broken config (sources with an error, defines nothing the gate needs) blocks
s=$(mkscratch 1)
printf '[server]\nport = 9090\n' > "$s/src/app.conf"
printf 'PROTECTED_PATHS=(\n' > "$s/scripts/harness.conf"   # unterminated array
if push_hook "$s"; then bad "broken-harness-conf-fails-closed" "push allowed with a syntactically broken config"
else ok "broken-harness-conf-fails-closed"; fi

echo
echo "harness self-tests: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
