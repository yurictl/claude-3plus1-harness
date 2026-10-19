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
2. **Log every escape.** An escape is a failure that got past a clean grade — the one number that says whether the harness works, and worthless if it lives only in prose:

   ```bash
   bash scripts/escape-log.sh add \
     --what "staging port hardcoded in a committed config" \
     --missed "(no rule existed)" \
     --destination rule --severity warning
   ```

   `--destination` is `invariant` (a property of the state should have held) / `rule` (becomes a rubric rule) / `fixture` (rule exists, did not fire) / `wip` (not rubric-shaped yet) / `sharpen` (false positive).
3. For each event, propose exactly one destination. **Ask the invariant question first:** was there a property of the whole state that should have held — a twin left without the fix, a consumer of something renamed or removed, a value that only exists once derived? Those fail outside the diff the grader reads, so a rubric rule about the diff pattern is the wrong shape for them:
   - **invariant** → a row in `scripts/invariants/registry.tsv` + an executable check (contract in `scripts/check_invariants.py`) + a `hit`/`clear` pair in `tests/invariants/retro.tsv` — the commit that shipped the escape and the commit that fixed it. `make test-invariants` and `make invariants` must both pass (the second: the current tree holds, or the deviation is a reasoned row in `scripts/invariants/exceptions.tsv`);
   - **new or sharpened rule** → draft the edit to `docs/operations/conventions.md` (with severity) **plus** a fixture under `tests/golden/held-in/<case>/` (`case.<ext>` + `expected.txt`);
   - **not rubric-shaped yet** → an entry in `docs/wip/harvest-failure-modes.md` following its protocol;
   - **false positive** → a rule sharpening, plus a `tests/golden/clean/<case>/` fixture (`expected.txt` = `NONE`) so the precision loss cannot come back.
4. Show the proposals and wait for approval before writing. Rubric edits change gate behavior — treat them like code.
5. **Land the calibration change under the acceptance rule.** After a rubric edit:
   - `make replay` — report the per-set rates;
   - accept **only if `held-in` improved and `held-out` did not regress**. `replay.sh` compares against the committed baseline and says so; a held-out regression means the edit fitted the fixtures rather than the failure — revise it;
   - once accepted, `make accept-rubric` records the new baseline;
   - never write a `held-out/` fixture to make a rule pass. Held-out exists precisely because it was not consulted while the rule was written; a rule authored against it measures nothing.
6. A new rule without a passing fixture is not landed; a new invariant without its retro pair is not landed either. A rubric, registry or waiver edit pushed together with a product change is blocked by the gate — land it on its own.
   When the countermeasure exists, close the escape: `bash scripts/escape-log.sh addressed --ts <ts> --by "<what now catches it>" --test <assertion or retro row>`.
7. Periodically (or when the rubric passes ~10 rules) run `make replay-ablate` and read the dead-weight table: a fixture caught with **no rubric at all** is a rule the model already knows — propose retiring it. The loop that only adds rules eventually grades slower and flags more, for nothing.
8. If nothing verification-relevant happened, say so in one line and stop. Do not manufacture findings.
