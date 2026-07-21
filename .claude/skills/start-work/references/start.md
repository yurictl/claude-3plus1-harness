---
title: Phase — start a fresh task ("start work")
---

# Phase: start ("start work" / "kick off" / "new task")

A new task is being kicked off. The goal is **not** to start coding — it is to load enough context that the plan is real, then create the tracking artifact and a verifiable plan.

## Pre-flight discipline

This phase is about thinking, not typing. Resist the urge to jump into the work. The output of this phase is a written plan with a check.

## Steps

### 1. Parse what the user gave you

From the user's message, extract:
- **Topic / one-line description** of what the work is about
- **Ticket** if any (`bd-1234`, `#456`, `LIN-7`, or any project-specific prefix) — match against the project's known prefixes from CLAUDE.md
- **Scope hints** — which part of the system, which repo, which AWS account, etc.

If any of these are missing and the work is non-trivial, ask once before going further. Do not invent a topic.

### 2. Confirm the task-management system

Run the detection from `detect-system.md` if not already done. State your conclusion in one sentence to the user. If the user already named a tracker, follow that.

### 3. Gather context — in parallel

The point is to know what already exists so the plan respects it. Run these in parallel where possible.

**A. Existing tracking artifacts — overlap check.** Read the tracker's index of in-flight items (e.g. all files in `docs/wip/`, `bd ready`, open issues with the right label). For each, note topic / scope / status. List anything that overlaps with the new topic.

**B. Relevant operational docs.** Look for the project's docs index (e.g. `docs/INDEX.md`, README sections, an architecture page). Read the 1–2 docs whose purpose overlaps with the topic. Note constraints, runbook steps, or invariants that apply.

**C. Relevant decisions / investigations.** List `docs/decisions/`, `docs/adr/`, `docs/investigations/` (whichever exists). Read any whose title suggests architectural relevance. Note the decision or finding in one sentence each.

**D. Ticket details** (only if a ticket ID was provided). Use the project's CLI: `jira issue view <ID>`, `gh issue view <N>`, `glab issue view <N>`, `bd show <id>`, `linear ...`. Extract: summary, description, acceptance criteria, assignee, status. If the call fails, say so and continue.

**E. Code touchpoints.** If the topic clearly maps to code, locate the relevant files (one or two — don't read the whole repo). The point is to know where edits will land, not to start editing.

### 4. Synthesise — think before writing

Reason through, in writing:

1. **Overlap.** Does this duplicate an existing tracking artifact? If yes, propose updating that artifact instead and stop here.
2. **Constraints.** What do operational docs and decisions tell us we must not break or must follow?
3. **Validation strategy.** How will we know it's done? Be concrete — a test, a CI check, a `terraform plan` delta, a curl command, a Jira acceptance criterion. If you cannot name a check, escalate to the user before continuing.
4. **Risk and blast radius.** Anything destructive, hard to reverse, or visible to others? Flag now, not later.

Output a short pre-flight summary to the user (3–5 bullets) covering: chosen tracker, overlap result, key constraints, validation strategy, any risks.

### 5. Create the tracking artifact

Match the project's conventions exactly. Read one or two existing artifacts of the same kind first to mirror filename, frontmatter, prefixes, and section structure.

If the project provides a scaffolding CLI (e.g. `bd create`, `gh issue create`, `ergo plan add`, or a project-local script under `scripts/`), prefer it over hand-writing the file — it sets fields the linter will check.

Pre-load the artifact with what you gathered:
- Context section: why this exists; links to relevant docs and decisions; cross-refs to overlapping in-flight work
- Goal: derived from the ticket / acceptance criteria, not invented
- Hypotheses (if the artifact format has them): explicit, checkable
- Validation criteria: the concrete checks from step 4

Do not pre-fill data sections with speculation. Leave "evidence collected" empty for the work to fill.

### 6. Report

Tell the user:
- Which tracker and artifact you created (path or ID)
- Key context that informed the plan (with pointers, not paragraphs)
- The validation criteria you chose, and why
- The next concrete action (so the user can say "proceed" or course-correct)

## Anti-patterns

- Creating the tracking file before reading existing ones — leads to filename and frontmatter mismatch
- Naming a goal without a check — "improve X" with no observable
- Importing conventions from another project from memory — read CLAUDE.md instead
- Starting code edits in this phase — that's the next phase
