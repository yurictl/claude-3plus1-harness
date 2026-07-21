---
name: start-work
description: Manage the working loop on a project's task tracking system — starting fresh tasks, resuming after a clean session, executing planned work, and capturing progress before context is lost. Detects the project's task management convention (WIP files, beads, ergo, GitHub Issues, Linear, plain Jira, ad-hoc) and adapts to it. Trigger phrases — "start work" / "kick off" (fresh task; gather context, plan, set up tracker), "continue" / "resume" (clean session; recall current task and propose next step), "let's go" / "proceed" (plan exists; execute autonomously until a fork or blocker), "checkpoint" / "snapshot" (persist current progress to the tracker so important context survives session end).
---

# Start-Work — Task Loop

This skill manages four phases of working on a tracked task. Branch by which trigger fired; do not run more than one phase per invocation.

## Phase selector

| Trigger phrases | Phase | Reference |
|---|---|---|
| start work, kick off, new task | Begin a new task | `references/start.md` |
| continue, resume, where did we leave off | Resume after a fresh session | `references/continue.md` |
| let's go, proceed, run | Execute an existing plan | `references/run.md` |
| checkpoint, snapshot, save state | Persist progress to the tracker | `references/checkpoint.md` |

If the user's wording is ambiguous (e.g. a bare "go" without object), ask which phase before proceeding.

## Step 1 — Detect the task-management system

Before any phase, identify what the project uses to track tasks. Full signals and per-system conventions live in `references/detect-system.md`. The short list:

- **WIP files** — a `docs/wip/` (or similar) directory with markdown tracking files; CLAUDE.md describes a graduation lifecycle
- **beads** — a `.beads/` directory or `bd` CLI in the project
- **ergo** — a `.ergo/` directory or ergo CLI
- **GitHub Issues** — `.github/ISSUE_TEMPLATE/`, repo notes that issues are the source of truth
- **Linear / Jira / Notion only** — no local tracking files; CLAUDE.md or README points at an external tracker key
- **Ad-hoc / none** — nothing detectable; ask the user before creating any tracking artifact

Project-specific conventions (file paths, ticket prefixes, scope rules, helper CLIs, frontmatter shape) live in the project's CLAUDE.md — read it first. Do not import conventions from another project from memory.

## Step 2 — Load the phase reference

Read the matching reference file from the table above and follow it. Do not improvise the workflow — the references encode the discipline.

## Cross-cutting principles (apply to every phase)

- **Verifiable success criteria.** Every plan and every checkpoint must name a concrete check — a test, a command, a Jira acceptance criterion, an observable behaviour. A goal without a check is a guess.
- **Match existing conventions exactly.** Before writing or updating a tracking artifact, read one or two existing ones to mirror filename, frontmatter, prefixes, and tone. Do not invent shapes.
- **Do not invent a tracker.** If no system is detectable, ask. Do not silently create `docs/wip/` or any equivalent.
- **Single source of truth for in-flight knowledge.** Anything important that lives only in this session's context must end up in the tracker before the session ends — that is what `checkpoint` is for.
- **No emojis** in any output (chat, files, commits).
