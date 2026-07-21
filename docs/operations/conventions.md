---
title: "Project Conventions — the rubric"
summary: "Severity-tagged authoring rules for the protected paths — the rubric the /review grader executes and the golden set calibrates. Ships with two starter rules; replace them with rules earned from your incidents."
status: active
updated: "21-07-2026"
---

# Project Conventions — the rubric

Prescriptive rules for everything under the protected paths (`scripts/harness.conf`). Apply this checklist before merging any change to those paths. This document is **executable**: the `/review` skill grades diffs against it, the pre-push hook enforces a fresh grade, and `tests/golden/` pins its catch-rate.

Severity: `[BLOCKER]` must be fixed before merge; `[WARNING]` should be fixed unless justified with an inline `# reason:` comment. A justified exception is not silently accepted — the grader reports it as `[CAVEAT]` with the stated reason, routing it to a human for sign-off.

Evidence: every rule in this file is checked against the **text being graded** (the diff or file content) — no live probe is needed. The rubric's own health is checked by `make replay` (golden-set catch-rate). When you add a rule whose source of truth is anything other than the graded text (a live system, an API, a registry), name that probe next to the rule.

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

The starter rules are deliberately generic. The pattern only pays off when the rules are **earned from incidents** — each rule traceable to a failure that actually happened, because those are the rules a frontier model does not already know. See `docs/wip/harvest-failure-modes.md` for the open loop that grows this file, and add a golden fixture under `tests/golden/` with every rule you land.
