#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit) hook: block file-tool writes to the
# harness trust anchors.
#
# Why this exists: pre-push-grade.sh Gate 1 inspects Bash command strings, so it
# only ever saw the shell path. The file tools are a second, entirely separate
# route to the same file — and the fingerprint is legitimately obtainable
# (`grade-marker.sh hash`), so "hash, then Write it into the marker" opened the
# gate with no grade and no Bash command to intercept. Same anchor, second door.
#
# Enforcement lives here rather than only in settings.json `permissions.deny`
# because a permission entry is configuration a user can loosen, while a hook is
# the layer ADR-001 relies on ("an instruction can be skipped, a hook cannot").
# Both are wired; this is the load-bearing one.
#
# Contract: exit 0 allows, exit 2 blocks with stderr shown to the agent.
set -uo pipefail

payload=$(cat)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
. scripts/harness.conf 2>/dev/null || exit 0

MARKER="${GRADE_MARKER:-.claude/grade-ok}"
RECORD="${GRADE_RECORD:-.claude/last-grade.json}"

# Any file_path-shaped field the file tools use, normalized to a project-relative
# path so /abs/path/.claude/grade-ok and .claude/grade-ok compare equal.
target=$(printf '%s' "$payload" | MARKER="$MARKER" RECORD="$RECORD" python3 -c '
import json, os, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = d.get("tool_input", {}) or {}
paths = []
for key in ("file_path", "path", "notebook_path"):
    v = ti.get(key)
    if isinstance(v, str) and v:
        paths.append(v)
# MultiEdit-style batches
for edit in (ti.get("edits") or []):
    if isinstance(edit, dict):
        v = edit.get("file_path")
        if isinstance(v, str) and v:
            paths.append(v)

root = os.path.realpath(os.getcwd())
anchors = {os.path.realpath(os.path.join(root, os.environ[k])) for k in ("MARKER", "RECORD")}

for p in paths:
    rp = os.path.realpath(p if os.path.isabs(p) else os.path.join(root, p))
    if rp in anchors:
        print(os.path.relpath(rp, root))
        break
' 2>/dev/null || true)

[ -n "$target" ] || exit 0

{
  echo "BLOCKED: $target is a harness trust anchor — it is never written by a file tool."
  echo
  echo "The marker is a content fingerprint of the protected paths, and the record is the"
  echo "findings artifact it is stamped from. Writing either by hand fakes a grade that"
  echo "did not happen — the exact failure this harness exists to catch."
  echo
  echo "The only writer is scripts/grade-marker.sh:"
  echo "  bash scripts/grade-marker.sh record  <<< '{\"blocker\":0,...}'   # /review's findings"
  echo "  bash scripts/grade-marker.sh stamp                              # validates, then stamps"
  echo "Run /review."
} >&2
exit 2
