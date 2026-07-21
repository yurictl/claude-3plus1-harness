---
title: Phase — persist progress to the tracker ("checkpoint")
---

# Phase: checkpoint ("checkpoint" / "snapshot" / "save state")

Important context lives only in the session. The goal of this phase is to move it into the tracker so the next clean session can rebuild it. This is **not** graduation — the work is not finished; it is being saved.

## What gets captured

A good checkpoint answers, for the next reader: "what did this session find out, and what changes about the next step because of it?"

Specifically:
- **New evidence** — commands run, their results, screenshots, log excerpts that clarify the problem
- **Confirmed / disproved hypotheses** — tick boxes, or note "disproved because X"
- **Decisions taken in conversation** — what we chose, why, what we rejected
- **Stale items corrected** — MRs that merged, blockers that lifted, statuses that changed
- **Updated next step** — if it shifted from the previous plan
- **Open questions** — anything the user said "we'll figure out later" about

## What does not go in

- Speculative content not grounded in this session
- Step-by-step replay of every tool call ("then I read X, then I read Y") — capture the conclusions, not the trace
- Anything sensitive that should not be checked in (credentials, internal URLs that don't belong in repo)

## Steps

### 1. Identify the artifact

Use the same task identification logic as `continue.md` — usually obvious from session context, but confirm if the session has touched more than one task.

### 2. Read the artifact's current state

Open it. Note its existing structure and section headings — match them. If the artifact has a fixed shape (e.g. WIP frontmatter with `title / summary / status / updated / scope`), update fields, do not restructure the file.

### 3. Diff: what changed since the last update

Walk session memory and identify the deltas. List them mentally before writing — this is where most checkpoints leak. Cross-reference against:
- The artifact's `updated:` date — what's happened since
- The artifact's hypotheses — any newly answered
- The artifact's validation criteria — any newly passing
- Any progress table or status block

### 4. Write the update

In the artifact:
- Append new evidence to the appropriate section ("Findings", "Notes", "Evidence" — whatever the artifact uses)
- Tick off boxes that are now done
- Refine "current understanding" or equivalent — make it reflect what we now think, not the history of what we thought
- Update factual status (MR merged, deploy applied) — concise, dated
- Update the `updated:` field to today's date in the artifact's format (commonly `DD-MM-YYYY` — match what's already there)
- If the project tracks status in frontmatter, update it (`open` → `in-progress`, etc.) — but do **not** flip to `done` / graduate-ready unless the user said so

### 5. Mirror to the external ticket if applicable

If the project also tracks the work in Jira / Linear / GitHub Issues and the team uses comments as the running log, post a short comment summarising the checkpoint (link to MRs, key finding, current status). Do this only if comments-as-log is the project's convention — otherwise skip.

### 6. Confirm and stop

Tell the user:
- Which artifact was updated and what changed (diff in 3–5 bullets)
- Whether anything significant is **not** captured because it didn't fit (so they can flag it)
- That the work is **not** graduated — explicitly, so the user knows nothing is being closed

Do not continue executing. Checkpointing is a deliberate pause.

## Anti-patterns

- Restructuring the artifact's sections to match what feels logical now — keep the existing structure; future readers compare versions
- Writing a session log instead of distilled findings
- Marking the task `done` or moving content out of WIP — that's `graduate`, not `checkpoint`
- Forgetting the `updated:` date — breaks any tooling that sorts by it
- Letting the artifact contradict itself (old paragraph says "investigating", new paragraph says "confirmed") — refine, don't append blindly
