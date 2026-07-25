# Project Orientation

<!-- TODO: one paragraph — what this project is, its status, who it is for.
     This file is the template's Orientation layer; every TODO marks a slot
     grill-me will help you fill. -->

This project uses the 3+1 documentation framework with an executable verification harness: the conventions doc is a rubric the harness runs, not reference a human applies from memory.

## Map

| What | Where |
|---|---|
| The product | `src/` <!-- TODO: your real paths; keep in sync with scripts/harness.conf --> |
| The rubric | `docs/operations/conventions.md` — severity-tagged authoring rules |
| Why graders | `docs/decisions/ADR-001-docs-as-graders.md` |
| Open loops | `docs/wip/` |
| The grader | `/review` skill (`.claude/skills/review/`) |
| The write-back | `/checkpoint` skill (`.claude/skills/checkpoint/`) |
| The gate | `scripts/hooks/pre-push-grade.sh` (Bash) + `scripts/hooks/protect-anchors.sh` (Write/Edit) via PreToolUse |
| The trust anchors | `.claude/last-grade.json` (findings record) → `.claude/grade-ok` (fingerprint marker); sole writer `scripts/grade-marker.sh` |
| The gate's own tests | `tests/harness/run.sh` (`make test-harness`) — no LLM, seconds |
| Calibration | `tests/golden/{held-in,held-out,clean}/` + `scripts/replay.sh` (`make replay`) |
| Rule retirement | `make replay-ablate` — which rules the model already knows |
| Escape log | `scripts/escape-log.sh` → `.claude/telemetry/escapes.jsonl` |
| Harness config | `scripts/harness.conf` — protected paths, rubric, calibration paths, pinned models |
| Telemetry | `.claude/telemetry/` (local, gitignored) — `make report` / `make html` |

## Severity model

Findings are reported in exactly three bands:

- `[BLOCKER]` — must not merge in this state; fix before proceeding.
- `[WARNING]` — should be corrected; does not block if a justification is documented.
- `[CAVEAT]` — a violation carrying a documented justification (`# reason:`). It passed the structural check but rests on a semantic assumption the harness cannot verify, so it is **surfaced for human sign-off, never silently accepted**. Caveats are the designed handoff line between the harness and the human.

State the severity, the rule, the file/line, and the correct form (for caveats: the stated reason). Do not list passing rules.

Intentional exceptions are marked inline with `# reason: <short justification>` at the point of violation; a `[BLOCKER]` exception additionally requires the justification in the MR/commit description.

## Verifiable success criteria

Before a non-trivial change, name the check that will tell you it's done. For protected-path changes the check is always the same: `/review` reports zero `[BLOCKER]` findings. A goal without a check is a guess.

**Bounded retries:** three consecutive failed attempts at the same check → stop, report what was tried and what failed, and surface to the human. Do not grind the loop.

## Gate behavior

`git push` is gated by a PreToolUse hook with three checks:

1. **Anchor integrity** — the marker and the grade record are written only by `scripts/grade-marker.sh`, invoked by `/review`. Any other Bash command touching them is blocked, and so is any `Write`/`Edit`/`MultiEdit` on either path (`protect-anchors.sh`) — there is nothing legitimate to do to them by hand, on either route.
2. **Weakened-test gate** — a push that changes protected paths and the calibration material (`tests/golden/`, the rubric) in the same outgoing set is blocked: changing the product and weakening its tests in one go is the false-completion pattern this harness exists to catch. Land calibration changes separately, via `/checkpoint` + `make replay`.
3. **Grade freshness** — the marker holds a content fingerprint of the protected paths at grade time, not a timestamp. If the current state doesn't match, the grade is stale; re-run `/review`.

**Stamping requires a grade record.** `grade-marker.sh stamp` refuses unless `.claude/last-grade.json` — written by `grade-marker.sh record` from `/review`'s findings — reports zero blockers, matches the current fingerprint *and* the current rubric hash, and is younger than `GRADE_RECORD_TTL_MIN`. The fingerprint, rubric hash and timestamp are computed by the script, never supplied by the caller. Every stamp is appended to `.claude/telemetry/grades.jsonl`.

**Fail-closed.** When the outgoing set cannot be determined (no upstream, no `origin/HEAD`/`origin/main`, unreadable git state) or the protected tree cannot be fingerprinted, the hook demands a grade rather than allowing the push. An undeterminable diff is not an empty diff.

Residual trust: the record proves a grade was *reported*, not *performed* — that is `/review`'s hard rule. What it buys is that faking one now costs a fabricated findings record consistent with the diff, and that the fake is durable in the grade log instead of invisible. Escalation path if that proves insufficient: run the replay itself as the gate (see ADR-001).

**Editing the harness?** Run `make test-harness` — 23 assertions over the gate's own behaviour, including three bypasses that were once open (bare `stamp`, `Write` to the marker, commit-then-push with no baseline ref). The golden set calibrates the grader; this suite calibrates the gate.

## Adapter — evidence · authority · fraud-patterns

The three slots a verification harness needs, made explicit:

| Slot | Meaning | Here |
|---|---|---|
| **Evidence** | the source of truth each check reads | graded text via `git diff` / file content; calibration via per-set `make replay` rates against `tests/golden/baseline.json` <!-- TODO: name live probes if any rule needs one --> |
| **Authority** | who may sign off what the harness can't | `[CAVEAT]` findings and `[BLOCKER]` exceptions → human, via MR description; irreversible operations → human, always <!-- TODO: name the actual people/roles --> |
| **Fraud-patterns** | the failure modes checked for | the rubric rules + `tests/golden/` fixtures; the weakened-test gate; the three closed bypasses pinned in `tests/harness/run.sh` |

## Write-back rule

At session end (or when the user says "checkpoint"), run `/checkpoint`: if this session hit a failure the rubric would not have caught, log it (`scripts/escape-log.sh add`) and propose a new rule for `docs/operations/conventions.md` or a WIP entry in `docs/wip/`. Failures are curation signals, not noise — and an escape that is only described in prose cannot be counted.

A rubric change lands only if `held-in` improves and `held-out` does not regress (`docs/operations/conventions.md` §Calibration). Never write a `held-out/` fixture to make a rule pass.

## What the measurement is for

`make report` has two halves, and they answer different questions. Sessions, prompts, tokens and tool mix say the harness is being **used**. The harness-health panel — per-set catch-rate and its trend, escapes since the last rubric change, stamped grades, dead-weight candidates, loop-closure ratios — says whether it **works**. Activity is not progress; if only the first half moves, the loop is leaking.
