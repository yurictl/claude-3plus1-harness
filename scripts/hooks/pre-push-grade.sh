#!/usr/bin/env bash
# PreToolUse(Bash) hook: gate `git push` behind a fresh /review grade when
# protected paths changed, and protect the harness itself from tampering.
# Paths come from scripts/harness.conf.
#
# Contract (Claude Code hooks):
#   stdin  — JSON: {"tool_name": "...", "tool_input": {"command": "..."}, ...}
#   exit 0 — allow the tool call
#   exit 2 — block it; stderr is shown to the agent as the reason
#
# Four gates, in order:
#   1. Anchor integrity — hand-editing .claude/grade-ok or .claude/last-grade.json
#      via Bash is blocked; the only writer is scripts/grade-marker.sh. The
#      Write/Edit path is covered by hooks/protect-anchors.sh.
#   2. Weakened-test gate — a push that changes protected paths AND the
#      calibration material (golden set, rubric) in one go is the classic
#      false-completion pattern; blocked, land them separately. The invariant
#      registry and its exceptions are calibration material too.
#   3. State invariants — when the push touches INVARIANT_PATHS, every invariant
#      in scripts/invariants/registry.tsv must hold over the WHOLE tree (code, no
#      LLM, no anchor); a check that cannot run blocks.
#   4. Grade freshness — the marker must exist and its fingerprint must match
#      the current protected-path state (content-based, not mtime: `touch`
#      can't forge it, reverts invalidate it).
#
# Fail-closed principle: whenever the outgoing set cannot be determined (no
# upstream, no origin/HEAD, unreadable git state), the hook treats EVERY tracked
# protected file as outgoing and demands a grade. An undeterminable diff used to
# mean "nothing changed" — which silently disabled the whole gate on any repo
# freshly `git init`ed from this template.
set -uo pipefail

payload=$(cat)
command=$(printf '%s' "$payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
. scripts/harness.conf 2>/dev/null || exit 0

MARKER="${GRADE_MARKER:-.claude/grade-ok}"
RECORD="${GRADE_RECORD:-.claude/last-grade.json}"

# --- Gate 1: anchor integrity -------------------------------------------------
# Any Bash command touching an anchor, other than the canonical script, is
# blocked. The anchors are the harness's trust roots; there is nothing
# legitimate to do to them by hand.
case "$command" in
  *grade-marker.sh*) ;; # canonical path — /review's record + stamp
  *grade-ok*|*last-grade.json*)
    {
      echo "BLOCKED: $MARKER / $RECORD are the harness trust anchors and are never touched by hand."
      echo "They are written only by 'scripts/grade-marker.sh' (record → stamp), invoked by /review"
      echo "after a grade with zero [BLOCKER] findings. Run /review instead."
    } >&2
    exit 2
    ;;
esac

# Only gate pushes beyond this point.
case "$command" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# --- outgoing-set resolution ---------------------------------------------------
# Base ref for "committed but not yet pushed", in order of trustworthiness:
#   1. the branch's own upstream          (@{u})
#   2. the remote's default branch        (origin/HEAD)
#   3. conventional fallbacks             (origin/main, origin/master)
# If none resolves, there is no baseline — fail closed.
base=""
if b=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) && [ -n "$b" ]; then
  base="$b"
else
  for cand in origin/HEAD origin/main origin/master; do
    if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then base="$cand"; break; fi
  done
fi

# Everything in the outgoing set: committed ahead of base, staged, unstaged,
# and untracked. With no base, `git ls-files` stands in for "the whole branch is
# outgoing", which is exactly true for a repo that has never pushed.
changed_in() {
  {
    git diff --name-only HEAD -- "$@" 2>/dev/null
    git diff --name-only --cached -- "$@" 2>/dev/null
    if [ -n "$base" ]; then
      git log --name-only --pretty=format: "$base..HEAD" -- "$@" 2>/dev/null
    else
      git ls-files -- "$@" 2>/dev/null
    fi
    git ls-files --others --exclude-standard -- "$@" 2>/dev/null
  } | sed '/^$/d' | sort -u
}

# shellcheck disable=SC2086  # pathspecs are deliberately word-split
changed=$(changed_in $PROTECTED_PATHS)

if [ -z "$changed" ] && [ -z "$base" ]; then
  # Belt for the pathological case: no base AND ls-files empty (e.g. protected
  # paths untracked). Anything under the protected roots still demands a grade.
  # shellcheck disable=SC2086
  changed=$(find $PROTECTED_PATHS -type f 2>/dev/null | sed '/^$/d' | sort -u)
fi

[ -z "$changed" ] && exit 0

# --- Gate 2: weakened-test gate ------------------------------------------------
# shellcheck disable=SC2086
calibration=$(changed_in $CALIBRATION_PATHS)
if [ -n "$calibration" ]; then
  {
    echo "PUSH BLOCKED: calibration material modified alongside protected paths in the same push:"
    echo "$calibration" | sed 's/^/  /'
    echo "Changing the product and weakening its tests/rubric in one change is the"
    echo "false-completion pattern this harness exists to catch. Land the calibration"
    echo "change separately (via /checkpoint + 'make replay'), then push the product change."
  } >&2
  exit 2
fi

# --- Gate 3: state invariants ------------------------------------------------
# Deterministic, cheap, and runs before the grade check (a violation makes a
# re-grade wasted). Triggered by a change under INVARIANT_PATHS, then checks the
# WHOLE tree, not the outgoing files: an invariant is a property of the state, and
# "the violation sits in a file this push did not touch" is the twin shape it
# exists for. Fail-closed: a missing checker or a check that cannot run blocks.
# shellcheck disable=SC2086
if [ -n "${INVARIANT_CHECK:-}" ] && [ -n "$(changed_in ${INVARIANT_PATHS:-$PROTECTED_PATHS})" ]; then
  inv_rc=0
  if [ ! -r "$INVARIANT_CHECK" ]; then
    inv_out="the checker ($INVARIANT_CHECK) is missing or unreadable"; inv_rc=2
  else
    inv_out=$(python3 "$INVARIANT_CHECK" 2>&1) || inv_rc=$?
  fi
  if [ "$inv_rc" -ne 0 ]; then
    {
      if [ "$inv_rc" -eq 1 ]; then
        echo "PUSH BLOCKED: a state invariant does not hold (scripts/invariants/registry.tsv):"
      else
        echo "PUSH BLOCKED: the invariant check could not run — failing closed:"
      fi
      echo "$inv_out" | sed 's/^/  /'
      echo "The check covers the whole tree, not only this push: a violation in a file you did"
      echo "not touch is the twin/consumer shape this gate exists for. Fix the state, or — if the"
      echo "deviation is intentional — declare it in scripts/invariants/exceptions.tsv with a"
      echo "reason, in its own push (the registry is calibration material)."
    } >&2
    exit 2
  fi
fi

# --- Gate 4: grade freshness ---------------------------------------------------
bash scripts/grade-marker.sh check
case $? in
  0) ;;
  1)
    {
      echo "PUSH BLOCKED: changes under the protected paths ($PROTECTED_PATHS) are not graded."
      echo "Changed: $(echo "$changed" | tr '\n' ' ')"
      [ -n "$base" ] || echo "(no upstream/origin baseline — the whole branch is treated as outgoing)"
      echo "Run /review — it records findings, then stamps the marker on zero [BLOCKER]s."
    } >&2
    exit 2
    ;;
  2)
    {
      echo "PUSH BLOCKED: the protected paths no longer match the state that was graded"
      echo "(the marker fingerprint is stale — files changed after the last /review)."
      echo "Re-run /review to grade the current state."
    } >&2
    exit 2
    ;;
  *)
    {
      echo "PUSH BLOCKED: the harness could not fingerprint the protected paths"
      echo "($PROTECTED_PATHS — missing path or unreadable file? see scripts/harness.conf)."
      echo "Failing closed: fix the configuration, then re-run /review."
    } >&2
    exit 2
    ;;
esac

exit 0
