#!/usr/bin/env bash
# Replay scripts/check_invariants.py over the trees listed in tests/invariants/retro.tsv.
# Each invariant must report a finding on the state that shipped its escape (hit) and
# none on the fix (clear). Zero LLM calls; commits are extracted with `git archive`.
#
#   bash tests/invariants/retro.sh [retro.tsv]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TSV="${1:-$ROOT/tests/invariants/retro.tsv}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/invariant-retro.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0; rows=0
while IFS=$'\t' read -r ref inv match expect note; do
  [[ -z "${ref// }" || "$ref" == \#* ]] && continue
  rows=$((rows+1))
  case "$ref" in
    fixture:*) tree="$ROOT/tests/invariants/fixtures/${ref#fixture:}" ;;
    *)         tree="$WORK/$ref"
               if [ ! -d "$tree" ]; then
                 mkdir -p "$tree"
                 git -C "$ROOT" archive "$ref" | tar -x -C "$tree" 2>/dev/null \
                   || { fail=$((fail+1)); printf 'FAIL %-26s %s: cannot extract this ref\n' "$ref" "$inv"; continue; }
               fi ;;
  esac
  out=$(python3 "$ROOT/scripts/check_invariants.py" --root "$tree" --only "$inv" --json 2>&1); rc=$?
  if [ "$rc" -ge 2 ]; then
    fail=$((fail+1)); printf 'FAIL %-26s %-20s could not run: %s\n' "$ref" "$inv" "$out"; continue
  fi
  hits=$(MATCH="$match" python3 -c 'import json,os,sys; print(sum(os.environ["MATCH"] in f["subject"] for f in json.load(sys.stdin)["findings"]))' <<<"$out")
  got=clear; [ "$hits" -gt 0 ] && got=hit
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); mark=ok; else fail=$((fail+1)); mark=FAIL; fi
  printf '%-4s %-26s %-20s %-5s (want %s)  %s\n' "$mark" "$ref" "$inv" "$got" "$expect" "$note"
done < "$TSV"
[ "$rows" -eq 0 ] && { echo "retro: no rows — an invariant without a retro row is not landed"; exit 1; }
echo "retro: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
