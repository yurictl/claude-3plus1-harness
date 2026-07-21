#!/usr/bin/env bash
# PreToolUse hook: gate `git push` behind a fresh /review grade when protected
# paths changed, and protect the harness itself from tampering.
# Paths come from scripts/harness.conf.
#
# Contract (Claude Code hooks):
#   stdin  — JSON: {"tool_name": "...", "tool_input": {"command": "..."}, ...}
#   exit 0 — allow the tool call
#   exit 2 — block it; stderr is shown to the agent as the reason
#
# Three gates, in order:
#   1. Marker integrity — hand-editing .claude/grade-ok is blocked outright;
#      the only writer is scripts/grade-marker.sh (invoked by /review).
#   2. Weakened-test gate — a push that changes protected paths AND the
#      calibration material (golden set, rubric) in one go is the classic
#      false-completion pattern; blocked, land them separately.
#   3. Grade freshness — the marker must exist and its fingerprint must match
#      the current protected-path state (content-based, not mtime: `touch`
#      can't forge it, reverts invalidate it).
set -uo pipefail

payload=$(cat)
command=$(printf '%s' "$payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
. scripts/harness.conf 2>/dev/null || exit 0

# --- Gate 1: marker integrity -------------------------------------------------
# Any Bash command touching the marker, other than the canonical script, is
# blocked. The marker is the harness's trust anchor; there is nothing legitimate
# to do to it by hand.
case "$command" in
  *grade-marker.sh*) ;; # canonical path — /review's stamp after a clean grade
  *grade-ok*)
    {
      echo "BLOCKED: .claude/grade-ok is the harness trust anchor and is never touched by hand."
      echo "It is written only by 'scripts/grade-marker.sh stamp', invoked by /review after a grade"
      echo "with zero [BLOCKER] findings. Run /review instead."
    } >&2
    exit 2
    ;;
esac

# Only gate pushes beyond this point.
case "$command" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# Everything in the outgoing set: committed ahead of origin/main, staged,
# unstaged, and untracked.
changed_in() {
  {
    git diff --name-only HEAD -- "$@" 2>/dev/null
    git diff --name-only --cached -- "$@" 2>/dev/null
    git log --name-only --pretty=format: origin/main..HEAD -- "$@" 2>/dev/null
    git ls-files --others --exclude-standard "$@" 2>/dev/null
  } | sed '/^$/d' | sort -u
}

# shellcheck disable=SC2086  # pathspecs are deliberately word-split
changed=$(changed_in $PROTECTED_PATHS)
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

# --- Gate 3: grade freshness ---------------------------------------------------
bash scripts/grade-marker.sh check
case $? in
  0) ;;
  1)
    {
      echo "PUSH BLOCKED: changes under the protected paths ($PROTECTED_PATHS) are not graded."
      echo "Changed: $(echo "$changed" | tr '\n' ' ')"
      echo "Run /review — it stamps the grade marker only on zero [BLOCKER] findings."
    } >&2
    exit 2
    ;;
  *)
    {
      echo "PUSH BLOCKED: the protected paths no longer match the state that was graded"
      echo "(the marker fingerprint is stale — files changed after the last /review)."
      echo "Re-run /review to grade the current state."
    } >&2
    exit 2
    ;;
esac

exit 0
