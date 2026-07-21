---
name: graduate
description: Graduate a finished tracking artifact into permanent project documentation. Use when the work is done — the tracking notes (WIP file, beads task, ergo entry, GitHub Issue, Linear ticket) are no longer needed, but the durable knowledge they hold (operational steps, architectural decisions, troubleshooting recipes) should be promoted into the project's permanent docs and the tracking artifact should be closed or removed cleanly. Detects the project's task-management convention and graduation lifecycle from CLAUDE.md and existing docs. Trigger phrases — "graduate", "graduate this", "wrap this up", "promote to permanent docs", or invoking after a task is verifiably complete and the user asks to wrap up.
---

# Graduate — finish a tracked task into permanent docs

Graduation is a **clean move**. Durable knowledge goes into the project's permanent documentation; the tracking artifact is closed or deleted with no stub left behind. If knowledge is not durable, it is dropped, not preserved as history.

## Step 1 — Detect the task-management system

Identify the tracker used in this project (usually obvious from session context; confirm if not). Signals:

- **WIP files** — `docs/wip/` or similar markdown directory; CLAUDE.md mentions graduation; a docs CLI may exist (e.g. `make docs-index` or a project-local script under `scripts/`)
- **beads** — `.beads/` or `bd` CLI
- **ergo** — `.ergo/` or ergo CLI
- **GitHub / GitLab Issues** — issues are the source of truth
- **External-only** — Linear / Jira / Notion as the system of record, with no local tracking files

Read the project's CLAUDE.md for the graduation lifecycle (where graduated content lives, frontmatter shape, status values, naming, whether a docs index needs rebuilding). If unclear, ask the user before moving content.

## Step 2 — Identify the artifact and confirm completion

Locate the artifact (path, ticket ID, or issue number). Confirm with the user that the work is actually done:

- All validation criteria passing
- Linked MRs / PRs merged or closed appropriately
- No open hypotheses or unanswered checkboxes that matter

If anything is still in flight, **stop** and propose a `checkpoint` instead. Do not graduate work-in-progress.

## Step 3 — Classify the durable knowledge

Read the artifact and decide what kind of knowledge it represents (it can be more than one):

- **Operational** — runbooks, configs, procedures, troubleshooting → operations docs (e.g. `docs/operations/`)
- **Architectural decision** — why a choice was made, what was rejected → ADR / decision docs (e.g. `docs/decisions/`)
- **Investigation / research** — landscape survey, comparative analysis that informs future decisions → investigation docs (e.g. `docs/investigations/`) — only if the project distinguishes them
- **Nothing durable** — sometimes the artifact existed only to coordinate and produces no new knowledge. Skip to step 6 and just close it.

Match the project's existing categories. Do not invent a new category to fit your content.

## Step 4 — Prefer updating existing docs over creating new ones

Before creating any new file, search for an existing doc where this knowledge fits. Updating an existing file in place is almost always better than creating a new standalone file — it keeps the docs surface area small and discoverable.

Creating a new file in `docs/operations/` or `docs/decisions/` is a significant choice. Confirm with the user before doing it. If creating new:

- Match the project's frontmatter shape exactly (read 1–2 existing docs of the same kind)
- Use the project's scaffolding CLI if one exists
- Inherit the artifact's scope unless the graduated content materially shifts it
- Use the project's date format for the `updated:` field

## Step 5 — Move content cleanly

When updating an existing doc:
- Add the new content in the appropriate section (avoid creating new top-level sections unless warranted)
- Update the `updated:` field to today
- Strip WIP-specific language (hypotheses, "investigating", "we think") — graduated content speaks in present-tense fact
- Keep all factual content, tables, code blocks, links

When creating a new doc:
- Same cleanup of WIP language
- Cross-link from related docs if the new doc fills an obvious gap
- Do not include the artifact's session-specific narrative ("on 2026-04-12 we discovered") — keep durable facts only

## Step 6 — Close the tracking artifact

The graduation is a clean move — no stub, no cross-reference left behind.

- **WIP files** — delete the file
- **beads** — `bd close <id>` with a one-line summary
- **ergo** — close per ergo's CLI
- **GitHub / GitLab Issues** — close the issue with a comment linking to the new/updated doc
- **External-only (Jira / Linear)** — transition to Done; comment with the doc link if comments-as-log is the convention

## Step 7 — Rebuild any docs index

If the project has an auto-generated docs index, rebuild it. Examples:

- `make docs-index` (regenerates `docs/INDEX.md`)
- `make docs-check` to verify links and frontmatter
- A `scripts/build_docs.py` or similar

Do this even if you only updated an existing doc — `updated:` dates often feed into the index ordering.

## Step 8 — Report

Tell the user:

- **Destination** — path of the new or updated doc
- **What was added** — one or two bullets of the durable content moved
- **What was dropped** — any WIP content intentionally left behind (hypotheses that didn't pan out, session narrative)
- **Tracker state** — artifact deleted / issue closed / ticket transitioned
- **Index** — rebuilt, or note it's not applicable

## Anti-patterns

- Creating a new doc when an existing one fits — adds clutter, fragments knowledge
- Leaving a stub in the tracker ("see `docs/operations/foo.md`") — graduation is a clean move
- Graduating work that isn't actually done because the user said "graduate" — confirm completion first
- Importing graduation conventions from another project — every project has its own destinations and lifecycle; read CLAUDE.md
- Carrying over WIP language ("we investigated whether X") into the graduated doc — rewrite in fact mode
