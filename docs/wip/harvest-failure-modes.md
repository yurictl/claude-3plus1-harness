---
title: "Harvest real failure modes into the rubric"
summary: "Open loop: collect failures the rubric would not have caught and graduate each into conventions.md plus a golden-set fixture. Delete this file when the first month of harvesting is done."
status: open
updated: "21-07-2026"
---

# WIP — Harvest real failure modes into the rubric

## Context

The rubric ships with generic starter rules. Its long-term value comes from rules **earned from incidents** — those are the ones a frontier model does not already know. This WIP tracks the harvesting loop until it becomes habit.

## Protocol

On every failure that reaches runtime or review despite a clean grade:

1. Write the failure down here (what happened, why the rubric missed it).
2. Draft the rule for `docs/operations/conventions.md` with severity.
3. Add a fixture to `tests/golden/<case>/` reproducing the violation (`case.<ext>` + `expected.txt`).
4. Run `make replay` — the new fixture must pass before the rule counts as landed.
5. Remove the entry from this file.

## Collected failures

_(none yet — seed with your first real incident)_

## Exit criteria

- [ ] At least three incident-earned rules landed with fixtures.
- [ ] `/checkpoint` proposes entries here without being reminded.
- [ ] This file is deleted; the protocol lives on as habit (or graduates into CLAUDE.md if it keeps being forgotten).
