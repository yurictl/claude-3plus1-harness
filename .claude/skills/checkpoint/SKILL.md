---
name: checkpoint
description: Session-end write-back step. Use when the user says "checkpoint", "фиксируемся", or is wrapping up — harvest failures seen this session into the rubric or a WIP entry so the verification substrate compounds.
---

# checkpoint — the write-back step

Failures are curation signals. This skill closes the loop that keeps the rubric alive.

## Steps

1. Scan this session for verification-relevant events:
   - a `[BLOCKER]`/`[WARNING]` class problem that the rubric **did not** have a rule for;
   - a failed command / rejected review / runtime surprise on protected-path material;
   - a rule that misfired (false positive the user overrode).
2. For each event, propose exactly one destination:
   - **new or sharpened rule** → draft the edit to `docs/operations/conventions.md` (with severity) **plus** a golden fixture under `tests/golden/<case>/` (`case.<ext>` + `expected.txt`);
   - **not rubric-shaped yet** → an entry in `docs/wip/harvest-failure-modes.md` following its protocol;
   - **false positive** → a rule sharpening or an explicit exception note in the rubric.
3. Show the proposals and wait for approval before writing. Rubric edits change gate behavior — treat them like code.
4. After a rubric edit lands, run `make replay` and report the catch-rate. A new rule without a passing fixture is not landed.
5. If nothing verification-relevant happened, say so in one line and stop. Do not manufacture findings.
