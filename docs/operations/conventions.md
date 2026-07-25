---
title: "Project Conventions — the rubric"
summary: "Severity-tagged authoring rules for the protected paths — the rubric the /review grader executes and the three-set golden suite calibrates. Ships with two starter rules; replace them with rules earned from your incidents. Carries the acceptance rule for its own edits and the retirement probe."
status: active
updated: "25-07-2026"
---

# Project Conventions — the rubric

Prescriptive rules for everything under the protected paths (`scripts/harness.conf`). Apply this checklist before merging any change to those paths. This document is **executable**: the `/review` skill grades diffs against it, the pre-push hook enforces a fresh grade, and `tests/golden/` pins its catch-rate.

Severity: `[BLOCKER]` must be fixed before merge; `[WARNING]` should be fixed unless justified with an inline `# reason:` comment. A justified exception is not silently accepted — the grader reports it as `[CAVEAT]` with the stated reason, routing it to a human for sign-off.

Evidence: every rule in this file is checked against the **text being graded** (the diff or file content) — no live probe is needed. The rubric's own health is checked by `make replay` (per-set catch-rate; see Calibration below). When you add a rule whose source of truth is anything other than the graded text (a live system, an API, a registry), name that probe next to the rule.

## Starter rules (replace with your own)

<!-- TODO: these two exist so the harness is runnable out of the box.
     Replace them with rules earned from YOUR incidents — see Provenance below. -->

- `[BLOCKER]` **No plaintext secrets.** Committed material never contains literal passwords, tokens, API keys, or connection strings with embedded credentials. Secrets come from the environment or a secret store; the committed form is a reference, not a value.
- `[WARNING]` **TODO carries a tracker reference.** Every `TODO`/`FIXME` names an issue (or carries an inline `# reason:` explaining why none exists yet). An unanchored TODO is a decision nobody owns.

## Exceptions

An intentional violation is marked at the point of violation:

```
timeout = 900  # reason: vendor API cold-start, see incident 2026-05-12
```

`[WARNING]` exceptions need only the inline comment. `[BLOCKER]` exceptions additionally require the justification in the MR/commit description — inline alone is not sufficient.

Either way the exception surfaces in the grade as `[CAVEAT] <rule> — <file>:<line> — <stated reason>`: the harness verified the structure, a human owns the assumption.

## Provenance

The starter rules are deliberately generic. The pattern only pays off when the rules are **earned from incidents** — each rule traceable to a failure that actually happened, because those are the rules a frontier model does not already know. See `docs/wip/harvest-failure-modes.md` for the open loop that grows this file, and add a golden fixture with every rule you land.

## Calibration — how a change to this file is accepted

This file's own health is measured by `make replay`, over three fixture sets that do three different jobs:

| Set | Job | Written when |
|---|---|---|
| `tests/golden/held-in/` | drives rule authoring — the fixture that proves the new rule fires | alongside the rule |
| `tests/golden/held-out/` | answers "does this rubric generalize?" — surfaces of the same rules that **no rule was written against** | never while authoring a rule |
| `tests/golden/clean/` | pins precision — material that must produce **zero** findings (`expected.txt` = `NONE`) | when a rule misfires, or with any rule that could over-fire |

**Acceptance rule: a change to this file lands only if `held-in` improves and `held-out` does not regress.** `replay.sh` compares per-set rates against the committed baseline (`tests/golden/baseline.json`) and names any regression. A held-out regression means the edit fitted the fixtures rather than the failure.

Two properties worth stating, because their absence is the usual way a rubric rots:

- **Held-out is never consulted while writing a rule.** A rule authored against a held-out fixture measures nothing; at that moment the fixture has become held-in. If you need a new surface to author against, add it to `held-in/`.
- **Recall without precision is not a catch-rate.** Every fixture asserting a *catch* means a rubric that flags everything scores perfectly. The `clean/` set is the other half; an empty `expected.txt` is a hard failure, not a skip.

## Retirement — a rule can also leave

The loop that only ever adds rules eventually grades slower, flags more, and reads no better. `make replay-ablate` grades every fixture **with no rubric at all**: anything still caught is redundant to what the model already knows, and is a retirement candidate rather than earned signal. `--tiers` adds the cheap-model read — a rule the cheap tier misses is calibrated to the top tier and will not survive a model change. Retire from the table, not from taste.

## Grading model

The grader model is pinned in `scripts/harness.conf` (`GRADER_MODEL`), so a change in catch-rate means a change in this file — not a silent model swap underneath it. Re-run `make replay` after a deliberate model change and record a new baseline if the rates move.
