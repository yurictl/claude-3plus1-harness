---
name: transcript-mine
description: Scan past Claude Code conversation transcripts for recurring user-correction patterns ("can you also…", "did you check…", "still wrong", "actually…", "stop doing X", "always/never X") and propose updates to ~/.claude/CLAUDE.md, project memory, or new skills based on hit counts. Use when the user runs /transcript-mine, asks "what am I correcting Claude on repeatedly", asks to find missing rules from past sessions, mentions Eugene Yan's transcript-mining or compounding-loop closing-the-loop step, or asks to review session history for patterns. Operates against ~/.claude/projects/*/*.jsonl transcript files locally; nothing leaves the machine.
---

# transcript-mine

Eugene Yan's *close the loop* practice for Claude Code (from *How to Work and Compound with AI*, 2026-05): instead of correcting the same mistake every session, scan past transcripts for recurring correction patterns, surface the top ones with hit counts, and propose config updates that prevent the corrections from recurring.

This is the **anti-decay** practice for the personal AI harness. Without it, every correction is forgotten by the next session. With it, every correction compounds into config.

## Workflow

### 1. Run the scanner

```bash
python3 ~/.claude/skills/transcript-mine/scripts/mine_transcripts.py --days 14
```

**Default scope: current project only.** The script auto-detects CWD and filters transcripts to the matching `~/.claude/projects/<encoded-cwd>/` directory (Claude Code encodes `/Users/yura/notes/research` → `-Users-yura-notes-research`). This is right for most invocations because fixes are usually project-scoped.

**Scope modes:**
| Flag | Scope |
|---|---|
| (no flag) | Current project, derived from CWD |
| `--all` | All projects under `~/.claude/projects/` — use for finding **global** rules that should land in `~/.claude/CLAUDE.md` |
| `--project <substr>` | Substring match on transcript path — use to scan a specific other project from anywhere |
| `--cwd <path>` | Override the auto-detected CWD (useful when running outside Claude Code) |

When to use which:
- **Default (current project):** the typical invocation. Surfaces patterns specific to this codebase/vault → fix lands in `<repo>/CLAUDE.md` or project memory.
- **`--all`:** quarterly cross-project review. Surfaces patterns that recur *across* projects → fix lands in `~/.claude/CLAUDE.md` (global). Don't run frequently — high volume, low signal-to-noise per individual fix.
- **`--project <substr>`:** debugging a specific other project's recurring corrections without changing directory.

Other common overrides:
- `--days N` — different lookback window. Use 7 for "what's been happening this week"; 30 for monthly review; 90 for quarterly cross-project pass.
- `--min-hits N` — lower to 1 for exploratory pass; default 3 for actionable signal.
- `--limit N` — max examples per category (default 20).
- `--patterns <path>` — point at custom patterns JSON.

The output's `"scope"` field reports which mode the script ran in. Always confirm before promoting fixes.

The script emits JSON. Pipe to a file for re-reading: `... > /tmp/mine.json`.

### Scope discipline — per-project vs `--all`

A fix discovered in a current-project pass goes to that project's config (`<repo>/CLAUDE.md` or project memory). A fix discovered in `--all` pass that's concentrated in one project goes to *that* project's config — even though `--all` was the lens. Scope of the *fix* is determined by the *concentration* of the pattern, not by the *scope of the scan*.

**Anti-pattern:** running `--all`, finding a pattern concentrated in one project, and promoting to global `~/.claude/CLAUDE.md`. That's tax on every other project's context for a project-specific issue. Always check `counts_by_project` before picking destination.

### 2. Read the output structure

Six top-level fields to focus on, in order:

1. **`counts_by_category`** — sorted hits per category. Start at the top.
2. **`sessions_per_category`** — same in distinct sessions. 7-hits-1-session ≠ 7-hits-7-sessions.
3. **`counts_by_project`** — distribution. Concentration vs spread determines fix scope.
4. **`examples`** — truncated snippets. Read them; the whole point.
5. **`suppressed_low_hits`** — categories below threshold. Skim for missed signal.
6. **`user_messages_seen`** — denominator for base-rate awareness.

For interpretation guidance and false-positive shapes to recognize, read [`references/pattern-interpretation.md`](references/pattern-interpretation.md).

### 3. Cluster patterns by topic

Two `still_wrong` hits on different topics need different fixes. Cluster before promoting:

1. Print all examples for the top 3 categories.
2. For each example, write a one-phrase topic ("file paths", "tone", "test execution").
3. Group by topic.
4. Promote per-cluster, never per-category.

A category with 12 hits across 7 unrelated topics is noise; ignore the category and inspect specific clusters with sharper queries instead.

### 4. Cross-reference existing config

For each cluster, before proposing a fix:

1. Read the candidate target file (`~/.claude/CLAUDE.md`, the project memory file).
2. Grep it for the pattern's keywords.
3. **If a rule exists** but the corrections still happen → the rule isn't working. Rewrite, relocate, or escalate (skill instead of CLAUDE.md line). Do **not** add a duplicate.
4. **If no rule exists** → propose adding one.

A transcript-mine pass that creates duplicate rules is worse than no pass: it grows the global config without fixing anything.

### 5. Pick the destination

For each cluster, pick where the rule lives. Quick form:

| Cluster shape | Destination |
|---|---|
| General behavior, applies everywhere | `~/.claude/CLAUDE.md` |
| Workspace-scoped behavior | `<workspace>/CLAUDE.md` |
| Repo/project-scoped behavior | `<repo>/CLAUDE.md` |
| Triggerable by task type, ≥1×/week, thick ruleset | new skill in `~/.claude/skills/<name>/` |
| Narrow, ≤2 rules, project-specific | `~/.claude/projects/<proj>/memory/<topic>.md` |

Read [`references/rule-placement.md`](references/rule-placement.md) for the full decision tree, the central tradeoff (every line in `~/.claude/CLAUDE.md` is paid on every prompt forever), worked examples, and anti-patterns.

### 6. Present proposals — do not auto-apply

For each cluster, output:

- **Pattern:** category + topic + hit count + session count + project distribution
- **Existing config check:** what was found at the target file when grep'd
- **Proposed fix:** target file path + concrete diff or new content
- **Confidence:**
  - **High** — ≥10 hits in single project (or ≥5 across projects) + clear actionable rule
  - **Medium** — 5–10 hits + topic-clear but rule-wording uncertain
  - **Low** — 3–5 hits or noisy cluster — flag for next pass, do not promote

Present proposals; let the user approve each individually. Do not edit files automatically.

### 7. Apply approved fixes precisely

For each approved fix:
- Read the target file.
- Edit precisely. Don't restructure unrelated content.
- Optionally add a trailing comment noting the source: `<!-- learned: 2026-05-09 from transcript-mine pass -->` if the file convention permits comments.
- For new skills: scaffold via `init_skill.py` if available, or write SKILL.md directly with `name` + `description` frontmatter.

### 8. Log the run

Append to `~/.claude/skills/transcript-mine/runs.log`:

```
2026-05-09 14:32 | days=14 | scanned=47 | patterns=6 | applied=4 | deferred=2
```

Format is informal but consistent. The log lets future passes notice when a previously-applied fix's pattern resurfaces (signal that the rule is being ignored or wasn't precise enough).

## Custom patterns

Default patterns at `scripts/patterns.json` cover RU+EN correction language across 7 categories. Edit the file to:
- Add domain-specific patterns (e.g., always-correcting tone in writing projects, always-correcting test-coverage in code projects).
- Tighten regexes to reduce false positives in your specific transcript history.
- Add new categories. Format: `{ "category_name": { "description": "...", "regexes": ["..."] } }`.

Keep regexes case-insensitive (the script applies `re.IGNORECASE | re.MULTILINE` automatically).

## Anti-patterns

- **Don't propose fixes for patterns with <3 hits.** Below the default threshold = noise. Wait.
- **Don't write generic rules** like *"be more careful"* or *"think harder"*. Not actionable, not testable, becomes vault rot.
- **Don't bundle unrelated patterns.** One cluster → one fix; preserves the audit trail of *which* correction motivated *which* rule.
- **Don't auto-edit `~/.claude/CLAUDE.md`.** Global file, blast radius high. Always confirm.
- **Don't include conversation content in commits, external messages, or shared documents.** Transcripts contain client names, internal projects, API keys, personal info. Output stays local.

## Privacy

The script reads `~/.claude/projects/*/*.jsonl` locally. Nothing leaves the machine. The output JSON contains transcript snippets — treat it as sensitive. If sharing findings (e.g., to discuss a pattern with a teammate), redact manually before sharing.

## How this skill composes with the user's vault

This skill is the operational implementation of the highest-leverage gap surfaced in the vault's 2026-05-09 Eugene Yan ingest:

- [[Compounding AI Workflow — Eugene Yan]] §"Closing the loop" — the practice this skill implements
- [[Agent Harness Decay]] §"compounding inverse" — the failure mode this skill prevents
- [[Claude Code — Rule Placement Hierarchy]] — the placement decision this skill operationalizes

These references live in the user's research vault at `~/notes/research/` if available; the skill works without them.
