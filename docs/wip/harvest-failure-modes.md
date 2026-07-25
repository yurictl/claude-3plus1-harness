---
title: "Harvest real failure modes into the rubric"
summary: "Open loop: collect failures the rubric would not have caught and graduate each into conventions.md plus a golden-set fixture. Delete this file when the first month of harvesting is done."
status: open
updated: "25-07-2026"
---

# WIP — Harvest real failure modes into the rubric

## Context

The rubric ships with generic starter rules. Its long-term value comes from rules **earned from incidents** — those are the ones a frontier model does not already know. This WIP tracks the harvesting loop until it becomes habit.

## Protocol

On every failure that reaches runtime or review despite a clean grade:

1. **Log it as an escape** — `bash scripts/escape-log.sh add --what "…" --missed "…" --destination rule|fixture|wip|sharpen`. Do this first and always: prose in this file is for the thinking, the log is what makes escapes countable in `make report`. A failure described only here cannot be trended.
2. Write the failure down here if it needs working out (what happened, why the rubric missed it).
3. Draft the rule for `docs/operations/conventions.md` with severity.
4. Add a fixture to `tests/golden/held-in/<case>/` reproducing the violation (`case.<ext>` + `expected.txt`).
5. If the failure is a *different surface* of a rule that already exists, the fixture belongs in `tests/golden/held-out/` — and then don't touch the rule to make it pass. If it was a false positive, add a `tests/golden/clean/` fixture (`expected.txt` = `NONE`).
6. Run `make replay` — held-in must improve, held-out must not regress. Then `make accept-rubric` to move the baseline.
7. Remove the entry from this file.

## Collected failures

_(none yet — seed with your first real incident)_

## First ablation read (25-07-2026) — the starter rules are mostly dead weight

`make replay-ablate`, pinned `sonnet` + cheap `haiku`, against the two shipped starter rules:

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
