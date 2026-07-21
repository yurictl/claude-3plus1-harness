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
| The gate | `scripts/hooks/pre-push-grade.sh` via PreToolUse hook |
| The trust anchor | `.claude/grade-ok` fingerprint marker, managed by `scripts/grade-marker.sh` |
| Calibration | `tests/golden/` + `scripts/replay.sh` (`make replay`) |
| Harness config | `scripts/harness.conf` — protected paths, rubric, calibration paths |
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

1. **Marker integrity** — `.claude/grade-ok` is written only by `scripts/grade-marker.sh stamp`, invoked by `/review` after a clean grade. Any other Bash command touching the marker is blocked by the hook — there is nothing legitimate to do to it by hand.
2. **Weakened-test gate** — a push that changes protected paths and the calibration material (`tests/golden/`, the rubric) in the same outgoing set is blocked: changing the product and weakening its tests in one go is the false-completion pattern this harness exists to catch. Land calibration changes separately, via `/checkpoint` + `make replay`.
3. **Grade freshness** — the marker holds a content fingerprint of the protected paths at grade time, not a timestamp. If the current state doesn't match, the grade is stale; re-run `/review`.

Residual trust: the fingerprint proves the graded state is the pushed state, but cannot prove the grade *happened* — that is `/review`'s hard rule, and the escalation path if it ever proves insufficient is running the replay itself as the gate (see ADR-001).

## Adapter — evidence · authority · fraud-patterns

The three slots a verification harness needs, made explicit:

| Slot | Meaning | Here |
|---|---|---|
| **Evidence** | the source of truth each check reads | graded text via `git diff` / file content; calibration via `make replay` catch-rate <!-- TODO: name live probes if any rule needs one --> |
| **Authority** | who may sign off what the harness can't | `[CAVEAT]` findings and `[BLOCKER]` exceptions → human, via MR description; irreversible operations → human, always <!-- TODO: name the actual people/roles --> |
| **Fraud-patterns** | the failure modes checked for | the rubric rules + `tests/golden/` fixtures; the weakened-test gate in the hook |

## Write-back rule

At session end (or when the user says "checkpoint"), run `/checkpoint`: if this session hit a failure the rubric would not have caught, propose a new rule for `docs/operations/conventions.md` or a WIP entry in `docs/wip/`. Failures are curation signals, not noise.
