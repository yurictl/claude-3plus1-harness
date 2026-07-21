#!/usr/bin/env bash
# Golden-set replay: feed each fixture to a headless grader (claude -p) and
# check the expected finding is still caught. Exit non-zero on any miss.
#
# This is the calibration layer: run it after editing the rubric and after
# model upgrades. A grader without a golden set is decorative.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/harness.conf

[ -f "$RUBRIC" ] || { echo "missing $RUBRIC" >&2; exit 1; }

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

pass=0
miss=0

for dir in tests/golden/*/; do
  name=$(basename "$dir")
  case_file=$(find "$dir" -maxdepth 1 -name 'case.*' | head -1)
  [ -n "$case_file" ] && [ -f "$dir/expected.txt" ] || { echo "SKIP  $name (incomplete fixture)"; continue; }

  prompt="You are a reviewer. Grade the material below against the following conventions. Report findings only, one per line, in the format: [SEVERITY] rule — detail. A violation carrying an inline '# reason:' justification is not silently accepted: report it as [CAVEAT] rule — detail — stated reason. Do not list passing rules.

=== CONVENTIONS ===
$(cat "$RUBRIC")

=== MATERIAL (${name}/$(basename "$case_file")) ===
$(cat "$case_file")"

  out=$(claude -p "$prompt" 2>/dev/null)

  if printf '%s' "$out" | grep -qE "$(cat "$dir/expected.txt")"; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "MISS  $name — expected /$(cat "$dir/expected.txt")/, got:"
    printf '%s\n' "$out" | sed 's/^/      /'
    miss=$((miss + 1))
  fi
done

total=$((pass + miss))
echo
echo "catch-rate: ${pass}/${total}"
[ "$miss" -eq 0 ]
