---
title: Detect the project's task-management system
---

# Detect the task-management system

Run this detection before any phase. Output: a single chosen system + the conventions you will follow. If signals conflict, ask the user.

## Signals (check in order)

### 1. WIP files convention

Signals (any one is sufficient):
- A directory `docs/wip/`, `wip/`, or `notes/wip/` containing markdown files
- CLAUDE.md mentions WIP files, "graduation", `make docs-check`, `make docs-index`
- A `scripts/*_docs.py`, `scripts/docs.py`, or similar docs CLI

What to learn before acting:
- Filename pattern (prefix, slug rules) — read 2–3 existing WIP filenames
- Frontmatter shape — open one WIP and copy its `title/summary/status/updated/scope` exactly
- Status lifecycle — read CLAUDE.md or `docs/INDEX.md`
- Where graduated content goes — usually `docs/operations/`, `docs/decisions/`, `docs/investigations/`
- Whether there is a CLI to scaffold new WIPs — prefer it over manual file writes when present

### 2. beads

Signals:
- `.beads/` directory at repo root
- `bd` CLI available (`which bd`)
- CLAUDE.md mentions beads / `bd ready` / `bd list`

What to learn:
- `bd ready` — what's actionable now
- `bd list` — full task index
- `bd show <id>` — task body, acceptance, blockers
- `bd create` and `bd update` — for new tasks and progress
- Issue identifiers (e.g. `bd-1234`) and how the project links them to commits

### 3. ergo

Signals:
- `.ergo/` directory or ergo config in the project
- An ergo CLI in PATH
- CLAUDE.md references ergo

What to learn from the project's own docs and existing artifacts; do not assume conventions from training data.

### 4. GitHub Issues / GitLab Issues as primary tracker

Signals:
- `.github/ISSUE_TEMPLATE/` or `.gitlab/issue_templates/`
- README or CLAUDE.md states issues are the source of truth
- No local tracking files

What to learn:
- Default labels / milestones / projects used
- Linking convention between branches/MRs and issues (e.g. `Closes #123`)
- Whether comments on the issue are expected as the running log (yes for many teams)

CLI: `gh issue ...` or `glab issue ...`.

### 5. Linear / Jira / Notion only (no local tracking)

Signals:
- CLAUDE.md or README points at a Linear team / Jira project key / Notion database
- Local CLIs configured: `linear`, `jira`, etc.
- No local `wip/` or `.beads/` style directories

What to learn:
- The project key or team
- The expected status flow (e.g. To Do → In Progress → In Review → Done)
- Whether comments on the ticket are the running log, or notes live elsewhere

### 6. Ad-hoc / none

If nothing above matches:
- Do not silently create `docs/wip/` or any tracking directory.
- Ask the user one question: "I don't see a task-management convention in this project. Should I (a) use a lightweight local notes file you point me at, (b) set up `docs/wip/` files, or (c) just track in conversation for now?"
- Honour the answer for the rest of the loop.

## Output of detection

State the chosen system in one sentence to the user before proceeding, e.g. "Working with WIP files in `docs/wip/`, ticket prefixes per CLAUDE.md, scope rules per CLAUDE.md."

If multiple systems coexist (rare — e.g. WIP files plus Jira), confirm which is the running log and which is the formal ticket.
