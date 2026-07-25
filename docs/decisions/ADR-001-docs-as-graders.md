---
title: "ADR-001: Conventions docs are executed by the harness, not read by humans at review time"
summary: "Turn severity-tagged convention docs into machine-run graders (skill + hook + golden set) instead of relying on reviewers to apply them from memory. Amended 21-07 (anti-tamper, CAVEAT band) and 25-07 (three fail-open paths closed; held-out/clean split; harness-health measurement; ablation as a decay detector)."
status: accepted
updated: "25-07-2026"
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

**New consequence.** The gate has its own regression suite (`tests/harness/run.sh`, `make test-harness`): zero LLM calls, a scratch git repo per case, 23 assertions covering the three bypasses plus the invariants that already existed. The golden set calibrates the grader; this calibrates the gate. Harness edits are now themselves gated by a test suite — which is the same argument this ADR makes about convention docs, applied one level up.
