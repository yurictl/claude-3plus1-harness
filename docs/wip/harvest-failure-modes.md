---
title: "Harvest real failure modes into the rubric"
summary: "Open loop: collect failures the rubric would not have caught and graduate each into conventions.md plus a golden-set fixture. Delete this file when the first month of harvesting is done."
status: open
updated: "19-10-2026"
---

# WIP — Harvest real failure modes into the rubric

## Context

The rubric ships with generic starter rules. Its long-term value comes from rules **earned from incidents** — those are the ones a frontier model does not already know. This WIP tracks the harvesting loop until it becomes habit.

## Protocol

On every failure that reaches runtime or review despite a clean grade:

1. **Log it as an escape** — `bash scripts/escape-log.sh add --what "…" --missed "…" --destination invariant|rule|fixture|wip|sharpen`. Do this first and always: prose in this file is for the thinking, the log is what makes escapes countable in `make report`. A failure described only here cannot be trended.
2. Write the failure down here if it needs working out (what happened, why the rubric missed it).
   **First ask: which property of the whole state should have held?** If the failure sat outside the diff that was graded — a twin left without the change, a consumer of something renamed or removed, a value that exists only once derived — it is an invariant, not a rubric rule: add a row to `scripts/invariants/registry.tsv` with its check, a `hit` row (the commit that shipped it) and a `clear` row (the fix) to `tests/invariants/retro.tsv`, run `make test-invariants && make invariants`, then `escape-log.sh addressed`. Steps 3–6 are for the diff-shaped rest.
3. Draft the rule for `docs/operations/conventions.md` with severity.
4. Add a fixture to `tests/golden/held-in/<case>/` reproducing the violation (`case.<ext>` + `expected.txt`).
5. If the failure is a *different surface* of a rule that already exists, the fixture belongs in `tests/golden/held-out/` — and then don't touch the rule to make it pass. If it was a false positive, add a `tests/golden/clean/` fixture (`expected.txt` = `NONE`).
6. Run `make replay` — held-in must improve, held-out must not regress. Then `make accept-rubric` to move the baseline.
7. Remove the entry from this file.

## Collected failures

_(none yet — seed with your first real incident)_

## First ablation read (25-07-2026) — the starter rules are mostly dead weight

`make replay-ablate`, pinned `sonnet` + cheap `haiku` (aliases at the time; the pin is exact model IDs as of 27-07 — re-run before comparing), against the two shipped starter rules:

| Fixture | pinned | cheap | no rubric | standing |
|---|---|---|---|---|
| `held-in/plaintext-secret` | yes | yes | **yes** | redundant — the model flags a literal password unaided |
| `held-in/justified-exception` | yes | yes | **yes** | redundant |
| `held-out/connection-string` | yes | yes | **yes** | redundant |
| `held-out/bare-todo` | yes | yes | **no** | **load-bearing** |

Three of four fixtures cover material a frontier model reports with no rubric at all. This is the README's own warning, measured rather than asserted: generic best practice adds nothing to the grade.

The one survivor is instructive. Unaided, a bare `TODO` is not something a model reports — it's ordinary code. With the rubric it becomes a `[WARNING]`. So what is load-bearing is not "notice the TODO" but the **project convention** ("every TODO names an issue") — a local policy the model cannot guess. That is the shape an earned rule has, and the test for a candidate rule: *would a model with no rubric already say this?* If yes, it is not a rule, it is a reminder.

No retirement action taken — the starter rules exist to make the template runnable and are meant to be replaced wholesale, not pruned. Re-run this table after the first three incident-earned rules land; at that point the redundant ones should be retired for real.

## Exit criteria

- [ ] At least three incident-earned rules landed with fixtures.
- [ ] `/checkpoint` logs escapes and proposes entries here without being reminded.
- [ ] `make replay-ablate` has been run once and at least one shipped rule has been classified (kept or retired) from its table rather than from taste.
- [ ] This file is deleted; the protocol lives on as habit (or graduates into CLAUDE.md if it keeps being forgotten). The escape log survives it — that is the durable half.

## Open: `held-out/bare-todo` is flaky, so the acceptance rule fires on noise (27-07-2026)

Found while re-baselining after the grader pin was changed from the `sonnet` alias to `claude-sonnet-5`. The full replay came back 5/6 with `held-out/bare-todo` missed, which reads as a held-out regression and blocks the change under the acceptance rule. It is not a regression:

| Run | `held-out/bare-todo` |
|---|---|
| full replay | MISS |
| `--set held-out` ×3 | MISS, MISS, PASS |

Same model, same rubric, same fixture — the grader reports the bare `TODO` as a `[WARNING]` maybe one time in three. Consistent with the 25-07 ablation read: this is the one fixture whose catch depends on the rubric rather than model priors, so it sits closest to the decision boundary and is the one most exposed to sampling variance.

**Why it matters beyond one fixture.** Calibration is single-sample: one `claude -p` per fixture, six fixtures, and a pass/fail regex. A fixture that passes p≈0.4 of the time makes `make replay` a coin flip on whether a legitimate rubric change lands, and makes a recorded baseline a snapshot of one draw rather than a rate. The acceptance rule ("held-in improves, held-out does not regress") assumes the measurement is stable; it isn't, and nothing in the output says so. A run that reports `2/2` and a run that reports `1/2` are currently indistinguishable from a real rubric change.

**Not fixed here — deliberately.** Re-baselining now would bless one draw as the new truth, which is the false-completion pattern the harness exists to catch. `baseline.json` is therefore left recording `model: sonnet`; every replay warns that the baseline and the pin disagree until this is resolved.

Options, cheapest first:
1. **N-of-M sampling** — grade each fixture k times, record pass-fraction instead of pass/fail, and make the acceptance rule compare fractions with a margin. Multiplies replay cost by k.
2. **Tighten the fixture** — the expectation regex (`[WARNING].*(TODO|tracker|issue)`) may be narrower than the finding the grader actually writes. Check the raw output before assuming a capability gap; a wording mismatch is a cheaper cause than variance.
3. **Report flakiness rather than remove it** — keep the fixture, track per-fixture pass-rate across runs in `replay.jsonl` (the data is already there), and surface unstable fixtures in the health panel. A flaky fixture is itself a finding about the rule.

Whichever lands, the durable lesson is the one this file exists for: a single-sample LLM grader is a *measurement*, and a measurement without a variance estimate cannot support an accept/reject rule.
