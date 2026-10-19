---
title: "ADR-001: Conventions docs are executed by the harness, not read by humans at review time"
summary: "Turn severity-tagged convention docs into machine-run graders (skill + hook + golden set) instead of relying on reviewers to apply them from memory. Amended 21-07 (anti-tamper, CAVEAT band), 25-07 (three fail-open paths closed; held-out/clean split; harness-health measurement; ablation as a decay detector) 27-07 (the model pin was a floating alias; telemetry split along the used/works seam) and 19-10 (state invariants: the deterministic half of the gate, for what the diff cannot show)."
status: accepted
updated: "19-10-2026"
---

# ADR-001: Conventions docs are executed by the harness, not read by humans at review time

## Context

Projects that document well end up in a specific failure mode: the verification knowledge is written down (conventions, severity rules, failure taxonomies), but the checks are executed by a human head at review time. The substrate exists; the executor is a person. Symptoms: a large share of human message traffic is "look at this / check that / can I merge?", agents read the docs as context but never grade their own output against them, and the same violations keep reaching review.

## Decision

Every convention doc that contains `[BLOCKER]`/`[WARNING]` rules is treated as **executable**:

1. A **grader skill** (`/review`) grades changes against the doc and reports findings in the severity format. Zero blockers → it stamps a grade marker.
2. A **PreToolUse hook** gates `git push` on a fresh marker when protected paths changed. Enforcement lives in the hook, not in prose — an instruction can be skipped, a hook cannot.
3. A **golden set** (`tests/golden/`) pins the grader's catch-rate: each historical violation is a replayable fixture. The replay runs on rubric edits and model upgrades.
4. A **write-back step** (`/checkpoint`) turns session failures into new rules or WIP entries, so the rubric compounds instead of rotting.

## Consequences

- Human review attention shifts to the semantic residue: business intent, stakeholder confirmation, irreversible operations.
- The rubric doc becomes load-bearing: editing it changes gate behavior, so edits get reviewed like code. The golden set is the regression suite for such edits.
- The grade marker is a soft artifact (a file); the harness trusts the skill to write it honestly. If that ever proves insufficient, the escalation path is running the replay script itself as the gate.
- LLM-as-judge is used without any judge infrastructure: a headless `claude -p` call with the rubric inline is the whole judge.

## Amendment (21-07-2026): anti-tamper and the CAVEAT band

Two refinements, prompted by pattern convergence with an outside reconstruction of the same harness shape ([fable-method](https://github.com/Sahir619/fable-method) — cited as convergence, not as measurement):

1. **The marker is content-bound, and the gate hunts false completion.** `.claude/grade-ok` holds a fingerprint of the protected paths at grade time (`scripts/grade-marker.sh`), so `touch` can't forge it and any post-grade edit invalidates it; the hook additionally blocks hand edits to the marker and blocks pushes that change the product and its calibration material (`tests/golden/`, the rubric) in the same outgoing set — the weakened-test pattern. Residual trust — "did the grade actually happen" — remains with the skill's hard rule; the escalation path above still stands.
2. **Three reporting bands instead of two.** Justified exceptions are not silently accepted: they surface as `[CAVEAT]` findings — structurally clean, resting on a semantic assumption — and route to a human by design. The caveat band *names* the handoff line between harness and human that this ADR's first consequence describes.

## Amendment (25-07-2026): three fail-open paths, and the measurement that was missing

A review of the gate against its own claims found that the enforcement layer this ADR relies on was reachable around, in three independent ways. All three were reproduced against the then-current code before being fixed, and each now has a case in `tests/harness/run.sh` marked `WAS-OPEN`.

1. **`stamp` opened the gate on request.** `pre-push-grade.sh` deliberately allowed any command matching `grade-marker.sh`, so `bash scripts/grade-marker.sh stamp` wrote a valid marker with no grade behind it — one command, gate open. The "residual trust" this ADR acknowledged was therefore not a residue but the primary path.
   **Now:** `stamp` requires a **grade record** (`.claude/last-grade.json`) written by `grade-marker.sh record` from `/review`'s findings, and refuses it unless `blocker == 0`, the fingerprint matches the current tree, the rubric hash matches the current rubric, and the record is younger than `GRADE_RECORD_TTL_MIN`. The fingerprint, rubric hash and timestamp are computed by the script, never supplied by the caller, so a record cannot be back-dated or pointed at another tree. Every stamp appends to `.claude/telemetry/grades.jsonl`.
2. **The file tools were a second door.** Gate 1 inspected Bash *command strings*; `Write`/`Edit` were not hooked at all (`PreToolUse` matched only `Bash` and `Skill`). Since the fingerprint is legitimately obtainable (`grade-marker.sh hash`), "hash, then Write it into the marker" forged a grade with no shell command to intercept.
   **Now:** `hooks/protect-anchors.sh` on `Write|Edit|MultiEdit|NotebookEdit` blocks both anchors, path-normalized so relative and absolute forms compare equal, with `permissions.deny` as the declarative echo. Enforcement stays in the hook because a permission entry is configuration a user can loosen.
3. **An undeterminable diff meant "nothing changed".** The outgoing set was computed against a hardcoded `origin/main`; the quickstart tells you to `rm -rf .git && git init`. With no such ref, the "committed but unpushed" term was empty, so *commit, then push* produced an empty changed-set and `exit 0` — the whole gate silently disabled on exactly the repo state the template ships you into.
   **Now:** the base ref resolves through `@{u}` → `origin/HEAD` → `origin/main` → `origin/master`, and when none resolves the hook **fails closed**, treating every tracked protected file as outgoing. An unfingerprintable protected tree also fails closed instead of passing.

**Consequence for the residual-trust claim.** It stands, but narrower and cheaper to audit: the record proves a grade was *reported*, not *performed*. What changed is the cost of faking one — from a single command to fabricating a findings record consistent with the diff — and that fabrications are now durable in the grade log rather than invisible. The escalation path (run the replay itself as the gate) is unchanged and still available.

**The measurement layer was pointed the wrong way.** Telemetry stored sessions, prompts, tokens and tool mix — evidence that the harness is *used*, none that it *works*. The two numbers that describe harness health were ephemeral: `make replay` printed a catch-rate to stdout and discarded it, and escapes (failures reaching runtime despite a clean grade) lived in prose in a WIP file meant to be deleted. Both are now durable — `replay.jsonl`, `escapes.jsonl` via `escape-log.sh` — and surfaced in a harness-health panel alongside loop-closure ratios that make a leaking loop visible (work started but never checkpointed; nothing graduated).

**The golden set was train and test at once.** Every fixture was written alongside the rule it checks, so the catch-rate was fitted by construction and nothing answered "does this rubric generalize?". And every fixture asserted a *catch*, so the suite measured recall only: a rubric edit that flags everything scored a perfect rate. `tests/golden/` now splits into `held-in/` (drives authoring), `held-out/` (never consulted while writing a rule; surfaces of the same rules that no rule was written against), and `clean/` (`expected.txt` = `NONE`, zero findings required — the precision half). An empty `expected.txt`, which used to match anything and pass silently, is now a hard failure. **Acceptance rule for a rubric change: held-in improves and held-out does not regress**, compared against a committed baseline (`tests/golden/baseline.json`).

**Grader ablation as a decay detector.** The grader model is now pinned (`GRADER_MODEL`), so a catch-rate change means a rubric change rather than a silent model swap. Two probes exploit the pin: `--tiers` grades on the cheap model as well, and `--ablate` grades with **no rubric at all**. A fixture still caught without the rubric is a rule redundant to model priors — dead weight with a decay curve, not earned signal — and this ADR's loop had no way to remove anything. `make replay-ablate` prints the classification (load-bearing / redundant / frontier-only / rubric miss), and `/checkpoint` now proposes retirements from it. This is the concrete answer to "generic best practice a frontier model already knows adds nothing", which until now was an instruction to the author rather than a check.

**New consequence (25-07).** The gate has its own regression suite (`tests/harness/run.sh`, `make test-harness`): zero LLM calls, a scratch git repo per case, 23 assertions covering the three bypasses plus the invariants that already existed. The golden set calibrates the grader; this calibrates the gate. Harness edits are now themselves gated by a test suite — which is the same argument this ADR makes about convention docs, applied one level up.

## Amendment (27-07-2026): the pin was not a pin, and the telemetry seam

Two corrections, both to claims this ADR already made rather than to new ground.

**The grader "pin" was a floating alias.** The 25-07 amendment above asserts that pinning `GRADER_MODEL` makes a catch-rate change mean a rubric change. The configured values were `sonnet` and `haiku` — aliases that resolve to whatever the current generation of each tier is. A model release would therefore move the catch-rate underneath an unchanged rubric, and `baseline.json` would still record `"model": "sonnet"`, so nothing in the output would say the comparison had become meaningless. The property the ablation and tier probes rest on — that the only moving part is the rubric — did not hold.

**Now:** `harness.conf` pins exact model IDs (`claude-sonnet-5`, `claude-haiku-4-5-20251001`), and `replay.sh` prints a warning when the committed baseline's `model` differs from the current pin, stating that the deltas mix a rubric change with a model change and attribute neither. Bumping the grader is now a deliberate two-step: edit the pin, then `make accept-rubric` to re-baseline on it. The warning is the enforcement half — without it the config fix would decay the next time someone edited the pin and forgot to re-accept.

**Telemetry is two products in one file.** The 25-07 amendment added the harness-health panel and named the distinction — activity says the harness is *used*, health says it *works* — but both halves lived in one 405-line `telemetry_report.py`, with the health panel's loop-closure ratios reading the activity collector's aggregate. The distinction was documented and not structural, so the half with a decay curve could not be removed without taking the durable half with it. Activity metrics are generic agent observability: session counts, prompts, tokens, tool mix are what an agent platform ships natively, and this one's version of them is a liability the day it does. Catch-rate trend, escapes past a clean grade, dead-weight candidates and loop closure are computed from this project's own rubric and golden set; no platform will ever produce them.

**Now:** three files along that seam — `telemetry_common.py` (store access), `harness_health.py` (the durable half, standalone: reads `replay.jsonl` / `escapes.jsonl` / `grades.jsonl`, and derives its per-session denominator from the event log when the harvester is absent), and `telemetry_report.py` (the activity half, which appends the health panel when present). `make health` runs the durable half alone. Deleting `telemetry_report.py`, `telemetry_harvest.py`, `seed_demo.py` and the `UserPromptSubmit` / `SessionEnd` hook entries leaves the health panel working, verified by running it against a tree with those files removed.

**Consequence.** The template now states its own decay curve in its file layout rather than only in prose: the components that measure whether the harness works are separable from the components that a better platform makes redundant. That is the same argument `--ablate` makes about rubric rules — a rule the model already knows is dead weight — applied to the harness's own code.

## Amendment (19-10-2026): state invariants — the half of the gate that does not read the diff

This ADR's premise is that a rubric executed against the change catches what a reviewer would. Measured in the deployment this template was distilled from, that premise held for what the rubric is *about* and failed for where it *looks*. Of the first ten escapes logged there, nine were a property of the state broken from outside the diff being graded: a fix landed in one of two twin files, a resource ported without the sibling config it needed, a value that existed only after rendering, a permission removed from something live. In the same period `--ablate` reported most of the matching fixtures **caught with no rubric at all** — the model knew those rules; given the twin file, it would have flagged it. It was never shown the twin file. More rubric could not fix that, and a grader told to read the whole tree on every push is a slower, costlier version of the same judgement on material that needs none.

**Decision.** The gate gets a deterministic fourth check. An *invariant* is a one-line property of the whole state, checked by code over the whole tree whenever a push touches `INVARIANT_PATHS`: registry `scripts/invariants/registry.tsv`, runner `scripts/check_invariants.py`, one executable check per row with a three-way exit (holds / violated / could not run — the last blocks). The diff decides *whether* to check; the whole tree decides the result — the deliberate inverse of "only judge what changed", because the violation in an untouched file is the case it exists for.

**What it is not.** Not a second grader: no model, so no anchor, no golden set and no catch-rate — a check either holds on its retro rows or it is wrong. Not a replacement for the rubric: the grader keeps everything that needs judgement (scope limits, the why, `[CAVEAT]`), and a mechanical rule may stay in both places until the invariant has a track record. Not a way around the weakened-test gate: the registry, the waivers and the retro set are calibration material, so a waiver cannot ride in the push that needs it.

**Proof, two kinds.** The gate's behaviour is pinned in `tests/harness/run.sh` (clean change passes; a violation blocks after a clean grade; a standing violation in a file the push did not touch blocks; a reasoned, separately landed waiver unblocks; a waiver in the same push, a reasonless one, a missing checker and a crashing check all block). Each invariant's *relevance* is pinned in `tests/invariants/retro.tsv`: on the commit that shipped its escape it must fire, on the fix it must not. In the source deployment that replay ran against 22 real states at landing, and a full-history sweep surfaced one failure shape nobody had logged — evidence the property-first framing finds things the incident-first one waits for.

**Write-back order.** `/checkpoint` now asks first which property of the state should have held, before proposing a rubric rule; `start work` asks the same question before the change — what must *stay* true, next to what must become true — which is the only point at which an invariant can be written before its incident instead of after.

**Consequence.** The template's honest limit moves: its one shipped invariant is a fixture-proven example over a placeholder product, and `make health` says so until a retro row points at a real commit. The harness now distinguishes two kinds of knowledge it curates — patterns a diff can show (rubric + golden set, judged, calibrated by rate) and properties a state must keep (invariants + retro set, executed, proven by history) — and routes each failure to the one whose shape it has.
