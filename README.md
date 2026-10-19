# claude-3plus1-harness

A [Claude Code](https://claude.com/claude-code) **project template**: the 3+1 documentation framework with an executable verification harness and local telemetry, pre-wired. Clone it (or "Use this template"), point one config file at your paths, and a new project starts with docs that grade, a gate that enforces, and a loop that compounds.

Three layers, one premise:

1. **Substrate — the 3+1 docs.** Most engineering knowledge is never published because writing it up is too expensive. If documentation lives in a shape both humans and agents can read, write, and keep current, that cost collapses.
2. **Executor — the verification harness.** In a mature 3+1 project the verification knowledge is already written down; what's missing is the executor. Here the conventions doc is a rubric a grader skill runs, a PreToolUse hook enforces, and a golden set calibrates.
3. **Measurement — local telemetry.** Zero-LLM hooks log the work loop; a SessionEnd harvester preserves session aggregates past transcript rotation; a stdlib script renders the dashboard. Two halves, deliberately: activity metrics show the harness is being *used*, and a harness-health panel — catch-rate trend, escapes past a clean grade, dead-weight rules, loop-closure ratios — shows whether it *works*.

Framework reference: [LinkedIn — "Most engineering knowledge is never published"](https://www.linkedin.com/feed/update/urn:li:share:7431585543827668992). Predecessor repo (skills collection + worked examples this template grew out of): [`claude-skills-3plus1`](https://github.com/yurictl/claude-skills-3plus1).

---

## The 3+1 framework, in one screen

| Bucket | Lives in | Holds |
|---|---|---|
| **Orientation** (persistent) | `CLAUDE.md` + optional `LEXICON.md` + optional `CONTRACT.md` at project root | Scope, status, project map; canonical vocabulary; behavioural agreement with the agent |
| **Operations** (persistent) | `docs/operations/` | Runnable procedures with the reference data they need, one topic per file |
| **Decisions** (persistent) | `docs/decisions/` | ADRs / design docs / post-mortems; why a choice was made; append-only or supersede |
| **WIP** (transient) | task tracker (ergo / bd / GitHub Issues / `docs/wip/`) | Hypotheses, investigations, deferred questions — graduate or drop when resolved |

`LEXICON.md` and `CONTRACT.md` are **lazy** — they appear when there is something to write, not before.

---

## What you get

```
CLAUDE.md                          Orientation template — map, severity model, adapter table (TODO slots)
docs/
  operations/conventions.md        the rubric — [BLOCKER]/[WARNING] rules + how its own edits are accepted
  decisions/ADR-001-*.md           why docs-as-graders (+ anti-tamper, CAVEAT, fail-open amendments)
  wip/harvest-failure-modes.md     open loop: real failures graduate into the rubric
src/                               placeholder for your product (see scripts/harness.conf); src/env/ = the twin-config demo
.claude/
  settings.json                    all hook wiring + anchor deny-list (the on/off switch)
  skills/
    review/                        the grader — three bands: [BLOCKER]/[WARNING]/[CAVEAT]
    checkpoint/                    the write-back step — failures become rules, fixtures, escapes
    grill-me/                      interview -> route resolutions into the 3+1 buckets
    start-work/                    drive the WIP layer (start / resume / proceed / checkpoint)
    graduate/                      promote finished WIP into Operations / Decisions
    transcript-mine/               close the correction loop from past sessions
scripts/
  harness.conf                     THE file to edit: protected paths, rubric, calibration, pinned models
  grade-marker.sh                  trust anchors: findings record + fingerprint marker (record/stamp/check)
  hooks/pre-push-grade.sh          the gate: anchor integrity + weakened-test + state invariants + freshness, fail-closed
  hooks/protect-anchors.sh         the second door: Write/Edit on either anchor is blocked
  replay.sh                        three-set replay + tier/ablation probes via headless `claude -p`
  check_invariants.py              runs the state invariants over the whole tree (stdlib, no LLM)
  invariants/registry.tsv          one row per invariant: id, statement, check, provenance
  invariants/exceptions.tsv        reasoned waivers (a whole-state check has no diff line for `# reason:`)
  escape-log.sh                    failures that got past a clean grade, made countable — and closable
  hooks/telemetry-log.sh           zero-LLM work-loop event collector
  harness_health.py                the durable half: catch-rate trend, escapes, dead weight
  telemetry_common.py              store access shared by both halves
  telemetry_harvest.py             activity: SessionEnd transcript -> session aggregate
  telemetry_report.py              activity: console summary / HTML dashboard (deletable)
tests/
  golden/held-in/<case>/           fixtures written alongside the rule they check
  golden/held-out/<case>/          never consulted while authoring a rule — the generalization check
  golden/clean/<case>/             expected.txt = NONE — the precision half
  golden/baseline.json             committed per-set rates the replay compares against
  harness/run.sh                   the gate's own regression suite (no LLM, seconds)
  invariants/retro.tsv             each invariant vs the state that shipped its escape (hit) and the fix (clear)
Makefile                           test-harness / invariants / test-invariants / replay / replay-ablate / accept-rubric + telemetry
```

---

## Quickstart

Requirements: `claude` CLI, `git`, `python3`, `bash`.

```bash
git clone <this repo> my-project && cd my-project
rm -rf .git && git init          # or use GitHub's "Use this template"
claude                           # start a session with this dir as project root
```

Then, inside the session:

1. **Seed the docs**: say `grill me` — the interview routes your project's vocabulary, agent contract, procedures, and open questions into the 3+1 buckets, and fills the `TODO` slots in `CLAUDE.md`.
2. **Point the harness**: edit `scripts/harness.conf` (protected paths) and replace the starter rules in `docs/operations/conventions.md` with rules earned from *your* incidents.
3. **Calibrate**: `make replay` — the three sets replay through the pinned grader and print per-set rates (6/6 out of the box); `make accept-rubric` records them as your baseline.
4. **See the gate work**: `make seed-violation`, ask Claude to commit and push — the hook blocks; `/review` finds the `[BLOCKER]`; fix, re-review, push. Try `touch .claude/grade-ok`, a `Write` to it, or a bare `grade-marker.sh stamp` — all three refused, and `make test-harness` proves it stays that way. Then `make reset && make seed-twin-violation`: a new environment config that `/review` grades clean — nothing in the file is wrong on its own — and the invariant gate still blocks the push, because its twins set a key it does not.
5. **Work the loop**: `start work` → … → `checkpoint`. Failures the rubric missed get logged as escapes and become proposed rules + fixtures; finished WIP graduates into permanent docs; `transcript-mine` feeds recurring corrections back into `CLAUDE.md`/`CONTRACT.md`.
6. **Read the health panel**: `make health` — the harness measuring itself (catch-rate trend, escapes since the last rubric change, dead-weight candidates, loop-closure ratios), not measuring your activity. `make report` prints your activity first and appends the same panel.

---

## The verification harness

The rubric is graded in three bands — `[BLOCKER]`, `[WARNING]`, and `[CAVEAT]`: a justified exception (`# reason:`) that passed the structural check but rests on a semantic assumption, surfaced for human sign-off instead of silently accepted. Caveats are the designed handoff line between harness and human.

The gate is **tamper-aware**, aimed at false completion:

- the grade marker is a **content fingerprint** of the protected paths, not a timestamp — `touch` can't forge it, any post-grade edit (or revert) invalidates it;
- **stamping requires a findings record.** `/review` pipes what it found into `grade-marker.sh record`; `stamp` refuses unless that record reports zero blockers and matches the current fingerprint, the current rubric hash, and a freshness TTL. Fingerprint, rubric hash and timestamp are computed by the script, never supplied by the caller, and every stamp lands in a durable grade log;
- both anchors are **unwritable by hand on both routes** — Bash commands and the file tools (`Write`/`Edit`/`MultiEdit`) are each blocked by their own hook;
- an **undeterminable diff fails closed.** The outgoing set resolves through `@{u}` → `origin/HEAD` → `origin/main` → `origin/master`; with no baseline the whole branch counts as outgoing and a grade is demanded. (Not academic: `rm -rf .git && git init` is step one of the quickstart.)
- a push that changes the product *and* its calibration material (golden set, rubric) in one outgoing set is refused as the **weakened-test pattern** — land calibration changes separately, via `/checkpoint` + `make replay`;
- the replay **discloses uncommitted calibration changes** next to the catch-rate, so a claimed "N/N" always names its baseline.

- a change can be right in its own diff and still break the system somewhere it did not look — the **state invariants** (below) check the whole tree, not the diff.

The gate has its own regression suite: `make test-harness` — 31 assertions, no LLM calls, a scratch git repo per case, three of them pinning bypasses that were open in an earlier revision. The golden set calibrates the *grader*; this calibrates the *gate*.

What stays human by design: `[CAVEAT]` sign-off, stakeholder confirmations, business intent, irreversible operations. The gate frees that attention from re-checking what's already written down.

### State invariants — what the diff cannot show

The grader reads the diff. The failures that get past a clean grade mostly do not live in it: the setting added to the environment you were working in and never to its twin, the consumer of the thing you renamed, the value that only exists after rendering, the permission something live still relied on. In the deployment this template was distilled from, 9 of the first 10 logged escapes had that shape — and the ablation probe said the grader *knew* most of those rules with no rubric at all. The failure was where it looked, not what it knew.

An invariant is a one-line property of the whole state, checked by code over the whole tree on every push that touches `INVARIANT_PATHS`, whichever file the push touched:

| Piece | Job |
|---|---|
| `scripts/invariants/registry.tsv` | id, statement, check, provenance — the escape it encodes |
| a check (any executable) | gets the tree root; prints `subject<TAB>detail` per violation; exits 0 holds / 1 violated / anything else = could not run, which blocks |
| `scripts/invariants/exceptions.tsv` | a waiver is a row with a reason — a whole-state check has no diff line to hang `# reason:` on |
| `tests/invariants/retro.tsv` | the invariant's proof: a commit that shipped its escape must report it (`hit`), the fix must not (`clear`) |

No model in the path, so no anchor, no golden set and no catch-*rate*: a retro row holds or the check is wrong. The registry, its waivers and the retro set are calibration material — adding a waiver in the same push as the violation it waives is the weakened-test pattern, and blocked as such. Ships with one example (`INV-ENV-KEY-PARITY` over `src/env/`, proven by two fixture trees); `make health` says so until a retro row points at a real commit.

The write-back order changes with it: at `/checkpoint` the first question about an escape is *which property of the state should have held?* — and `start work` asks it before the change, when it is still cheap: what must **stay** true, next to what must become true.

### Calibration that can fail

A grader whose fixtures were all written next to the rules they check has a catch-rate fitted by construction. Three sets, three jobs:

| Set | Answers |
|---|---|
| `held-in/` | does the new rule fire? (written alongside the rule) |
| `held-out/` | does the rubric **generalize**? (surfaces no rule was authored against, never consulted while writing one) |
| `clean/` | does it stay **precise**? (`expected.txt` = `NONE` — zero findings required) |

**A rubric change lands only if `held-in` improves and `held-out` does not regress**, compared against a committed baseline. Without `clean/` the suite measures recall alone, and a rubric that flags everything scores perfectly.

### Rules can also leave

The grader model is pinned to an exact model ID — not a floating alias like `sonnet`, which would move under you at the next release — so a catch-rate change means a rubric change rather than a silent model swap. If the committed baseline was graded by a different model than the current pin, the replay says so instead of printing deltas that attribute neither. Two probes exploit the pin:

- `make replay-tiers` — grade on the cheap model too. A rule only the cheap tier needs is one the frontier model already knows; a rule only the frontier catches is not portable.
- `make replay-ablate` — grade with **no rubric at all**. Anything still caught is redundant to model priors: dead weight with a decay curve, not earned signal.

The output classifies every fixture as load-bearing / redundant / frontier-only / rubric-miss, and `/checkpoint` proposes retirements from it. A loop that only adds rules eventually grades slower and flags more for nothing — "generic best practice a frontier model already knows adds nothing" becomes a check instead of an instruction.

**Pattern convergence.** [fable-method](https://github.com/Sahir619/fable-method) — a community reconstruction of an agent-verification workflow — independently arrives at the same harness shape, and its domain-adapter triple maps one-to-one onto 3+1: **fraud-patterns** → the rubric + golden set, **evidence** (the source-of-truth probe per check) → Operations, **authority** (who signs off what the harness can't) → `CONTRACT.md`. Cited as convergence, not as measurement.

---

## The four loop skills

<p align="center">
  <img src="docs/skills-loop.svg" alt="Four skills — grill-me, start-work, graduate, transcript-mine — composing clockwise around a central 3+1 docs stack (Orientation, Operations, Decisions, WIP)." width="640">
</p>

Shipped project-scoped under `.claude/skills/` so a templated project is self-contained; symlink them into `~/.claude/skills/` instead if you want them across all projects.

- **`grill-me`** — interviews you one question at a time and routes every resolution into the right bucket: glossary → `LEXICON.md`, agent-behaviour rules → `CONTRACT.md`, procedures → Operations, costly-to-reverse choices → Decisions, deferred questions → WIP. Adapted from Matt Pocock's `grill-with-docs`.
- **`start-work`** — four phases on whichever tracker the project uses: kick off / resume / proceed autonomously / checkpoint before context is lost. Detects the tracker convention from `CLAUDE.md`; does not invent one.
- **`graduate`** — when a tracked task is verifiably done, move the durable knowledge into Operations / Decisions and close the tracking artifact cleanly. Without it, the WIP layer accretes and the docs surface stays empty.
- **`transcript-mine`** — Eugene Yan's *compounding-loop* practice: scan recent transcripts for recurring corrections, propose config updates. Local only; nothing leaves the machine.

Each skill writes to a layer the next one reads. Skip any of them and the loop leaks: skip `grill-me` and docs stay tacit; skip `graduate` and WIP rots; skip `transcript-mine` and the same correction repeats every session.

---

## Telemetry (optional)

Local observability at 1% of the weight of a real stack — no server, no database, no dependencies. Event log (`.claude/telemetry/events.jsonl`) + session aggregates (`sessions.jsonl`) + `make report` / `make html` for a self-contained dashboard. Collectors always exit 0 (telemetry can never block the agent); stores are local, gitignored, disposable.

**Two halves, split at the file level — the seam is the point.**

| | Says | Files | Command | Outlook |
|---|---|---|---|---|
| **Activity** | the harness is *used* | `telemetry_report.py`, `telemetry_harvest.py`, `seed_demo.py` | `make report` / `make html` | generic agent observability — designed to be deleted the day the platform does it better |
| **Health** | the harness *works* | `harness_health.py` | `make health` | computed from *your* rubric and golden set; nothing else can produce it |

`harness_health.py` is standalone: it reads `replay.jsonl` / `escapes.jsonl` / `grades.jsonl` and falls back to the event log for its per-session denominator, so the durable half survives the activity half being removed. `telemetry_report.py` appends the health panel when it is present (`--no-health` to skip).

Don't want the activity half? Delete `scripts/telemetry_report.py`, `scripts/telemetry_harvest.py`, `scripts/seed_demo.py` and the `UserPromptSubmit` / `SessionEnd` entries in `.claude/settings.json`. `make health` keeps working. Don't want telemetry at all? Also drop `harness_health.py`, `telemetry_common.py` and the remaining `telemetry-log.sh` hook entries — the verification harness is independent of all of it.

---

## Adapting the template — checklist

- [ ] `scripts/harness.conf` — point `PROTECTED_PATHS` at your product; delete `src/app.conf`; check the pinned `GRADER_MODEL` / `GRADER_MODEL_CHEAP` are available to you. Keep them **exact model IDs, never aliases** — `sonnet` and `haiku` float to the current generation, which is the silent model swap the pin exists to rule out.
- [ ] `docs/operations/conventions.md` — replace the starter rules with **incident-earned** rules; verify with `make replay-ablate` rather than by judgement.
- [ ] `tests/golden/held-in/` — seed from **historical incidents**, one fixture per landed rule.
- [ ] `tests/golden/held-out/` — seed with *different surfaces* of those same incidents, and then don't look at them while writing rules. This is the set that can actually fail.
- [ ] `tests/golden/clean/` — seed with compliant material, including anything a rule might over-fire on.
- [ ] `make accept-rubric` — record your own baseline; the shipped one describes the starter rules.
- [ ] `scripts/invariants/` — replace `INV-ENV-KEY-PARITY` (and delete `src/env/` with `src/app.conf`) with invariants earned from your escapes; set `INVARIANT_PATHS` in `harness.conf`. Each lands with a `hit`/`clear` pair in `tests/invariants/retro.tsv` on real commits, then `make test-invariants && make invariants`. A gate that is red on arrival gets disabled — add an invariant once the tree satisfies it (or the deviation is a reasoned waiver).
- [ ] `make test-harness` — should stay green after any edit to the hooks, `grade-marker.sh` or `check_invariants.py`.
- [ ] `CLAUDE.md` — fill the `TODO` slots (map, adapter authority/evidence); `grill-me` will walk you through it.
- [ ] Review skills' trigger vocabulary (`telemetry-log.sh` triggers, `start-work` phrases) against your own work-loop language.
- [ ] Check your org's AI-tool policy before moving `scripts/replay.sh` into CI.

## Status

Personal. Lightly polished for sharing, not productised. Successor to [`claude-skills-3plus1`](https://github.com/yurictl/claude-skills-3plus1), where the harness and telemetry first appeared as worked examples.

Origin credits: `grill-me` — adapted from Matt Pocock's `grill-with-docs`; `transcript-mine` — implements Eugene Yan's *closing-the-loop* step from *How to Work and Compound with AI* (2026-05); telemetry — inspired by [agentsview](https://github.com/kenn-io/agentsview); 3+1 framework — mine, written up at the LinkedIn link above.
