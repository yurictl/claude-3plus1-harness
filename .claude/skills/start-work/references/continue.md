---
title: Phase — resume after a clean session ("continue")
---

# Phase: continue ("continue" / "resume" / "where did we leave off")

The session is fresh. The user has a task in flight and wants to pick up where they left off. The goal of this phase is to **rebuild context cheaply** and propose the next step — not to start executing.

## The trap

The trap here is doing the work before remembering the work. Skim, then propose, then wait for the user to say "proceed".

## Steps

### 1. Identify the current task

Run detection from `detect-system.md` if not already done.

Then locate the task. In rough order of preference:

1. **User named it.** If the user mentions an ID or title — use that.
2. **Single in-flight artifact.** If only one tracking artifact has status `in-progress` / `open` / `bd ready`, use it. Confirm by name with the user before proceeding.
3. **Most recently updated.** If multiple, propose the most recently updated one and ask. List the top 3 with their last-updated dates.
4. **Branch name.** If the current git branch encodes a ticket (`feature/<ID>/...`), use that as a strong hint.

Never silently pick when ambiguous.

### 2. Read the tracking artifact in full

Read the artifact end to end — frontmatter, context, goal, hypotheses, evidence collected, current understanding, validation criteria, any progress table. This is the single most important step; do not skip it.

### 3. Read the surrounding state

Run these in parallel:

- `git status` and `git log --oneline -20` on the relevant branch — what code changes already exist, what was the last commit
- Any open MR / PR linked from the artifact — `glab mr view`, `gh pr view`, `bd show <id>` for linked attachments
- Any recent comments on the ticket if it lives externally — `jira issue view <ID>`, `gh issue view <N>`
- The 1–2 files most likely affected by the work (don't load the whole repo)

### 4. Reconcile artifact vs. reality

The artifact may be stale relative to what's actually been done. Check for:

- Checkboxes that look unchecked but the work is clearly done (e.g. an MR was merged)
- "Awaiting review" language for an MR that is now merged or closed
- Hypotheses that were confirmed or disproved but not noted

If you find drift, **note it** in the summary; do not fix it silently — that's what `checkpoint` is for, and the user may want to direct what to capture.

### 5. Summarise — short, structured

Output to the user:

- **Task:** title + tracker ID/path
- **Status:** done / in-progress / blocked / open
- **Where we left off:** 2–3 sentences naming the last concrete action and its result
- **Open items:** unchecked validation criteria or unanswered hypotheses, as a short list
- **Drift:** anything in the artifact that no longer matches reality (if any)
- **Proposed next step:** one concrete action — small, named, with the check it satisfies

### 6. Wait

Stop here. Do not execute. The user will say "proceed" / "let's go" to continue, or course-correct, or ask for a different next step. Resuming work without confirmation is the most common failure mode of this phase.

## Anti-patterns

- Reading the artifact and immediately editing code based on it — skips the user's input on the next step
- Picking the most recently updated artifact without confirming when several are in flight
- Fixing drift silently — surface it instead, let the user decide whether to checkpoint it now or later
- Producing a long retrospective; the summary is for re-orientation, not history
