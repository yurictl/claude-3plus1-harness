# Rule Placement — Decision Tree

When a transcript-mine pass surfaces a recurring correction pattern, the fix has to live somewhere. This file is the decision tree for picking that location.

The five candidate locations, by activation profile:

| Level | File | Activation | Cost | When to use |
|---|---|---|---|---|
| **Global** | `~/.claude/CLAUDE.md` | Always, every prompt, every repo | High — burns context on every call | Universal behavior; rule must apply everywhere |
| **Workspace** | `<workspace>/CLAUDE.md` | Always, but only inside that workspace | Medium — burns context inside workspace | Workspace-specific but universal within it |
| **Repo / project** | `<repo>/CLAUDE.md` | Always, but only inside that repo | Medium — pays inside one repo | Per-repo style that differs from siblings |
| **Skill** | `~/.claude/skills/<name>/SKILL.md` | On-demand — loaded when description matches | Low — pays only when triggered | Thick ruleset tied to a specific kind of task |
| **Feedback memory** | `~/.claude/projects/<proj>/memory/` | Always, within the project | Low — narrow, always-on within a project | 1–2 surgical rules; too narrow for a full skill |

## Decision tree

```
Is the rule universal AND always needed (would I want it active in every project)?
├── YES → ~/.claude/CLAUDE.md (global)
│
└── NO → Is it scoped to a single workspace/repo/project?
        ├── YES, scoped to <workspace> → <workspace>/CLAUDE.md
        ├── YES, scoped to one repo    → <repo>/CLAUDE.md
        │
        └── NO, it triggers by task type
                Is it a thick ruleset (>5 rules, multi-step procedure, dedicated workflow)?
                ├── YES → new skill in ~/.claude/skills/<name>/
                │
                └── NO (1-2 rules, narrow project context)
                        → ~/.claude/projects/<proj>/memory/<topic>.md
```

## Key tradeoff

Every line in `~/.claude/CLAUDE.md` is paid **on every prompt**, in every repo, forever. So:

- **Universal rule that fires often** → global is fine; the cost is justified.
- **Universal rule that fires rarely** → still global if there's no skill-shape, but stay terse. One line beats a paragraph.
- **Task-specific rule** → skill (description-gated, pays only on match).
- **Project-specific narrow rule** → feedback memory (paid only inside the project).

Don't put rules in global that only apply to one repo. That's tax on every other repo's context for no benefit.

## Worked examples (from transcript-mine output)

### Example 1 — additive_correction in single project

> 5 hits of "can you also add..." in `~/notes/career-counsellor`, all about including job-source URL when drafting outreach. Other projects: 0 hits.

**Diagnosis:** project-specific, narrow, recurring.
**Fix location:** `~/notes/career-counsellor/CLAUDE.md` — add: *"When drafting outreach, always include the source URL of the job posting in the message."*

### Example 2 — verification_request across many projects

> 12 hits of "did you check..." across 4 projects. Pattern: model writes code without running existing tests first.

**Diagnosis:** universal behavior, fires often.
**Fix location:** `~/.claude/CLAUDE.md` — add: *"Before editing test-adjacent code, run the relevant test suite first to capture baseline state."*

### Example 3 — still_wrong concentrated in one task type

> 8 hits of "still wrong" in one project, all when generating LinkedIn post drafts. Pattern: drafts have AI-tells the user has explicitly banned.

**Diagnosis:** task-specific, thick ruleset (the user has documented content discipline elsewhere).
**Fix location:** existing or new skill (`~/.claude/skills/linkedin-draft/SKILL.md`). If skill exists, augment its anti-pattern section. If not, this is the trigger to create one.

### Example 4 — stop_doing single occurrence

> 1 hit of "stop adding emojis." 

**Diagnosis:** below the min-hits threshold; likely already covered by global "don't use emojis" rule. Verify against current `~/.claude/CLAUDE.md` and skip if duplicate.

### Example 5 — explicit_instruction with high specificity

> 4 hits across 2 projects: "always run `bun test` before reporting work as complete in this repo."

**Diagnosis:** repo-specific, recurring.
**Fix location:** the relevant repo's `CLAUDE.md`. NOT global (other repos use `pytest` / `jest` / etc.; would be wrong elsewhere).

## Anti-patterns

- **Don't promote rules globally just because they sound general.** A rule like "always cite your sources" sounds universal but is project-specific — it makes sense in research-vault contexts but is noise in coding repos.
- **Don't write rules that aren't actionable.** *"Be more careful about file paths"* is not a rule; it's a wish. *"When asked to edit a file, read it before guessing the path"* is a rule.
- **Don't duplicate the existing config.** Before adding a new rule, grep the target file for the pattern. If the rule is already there and not being followed, the problem is the rule's wording or placement, not its existence.
- **Don't bundle multiple unrelated patterns into one fix.** One pattern → one fix. Preserves the audit trail of *which* correction pattern motivated *which* rule.

## When the fix isn't a rule

Some patterns surfaced by transcript-mine aren't rule-fixable:
- **The model is doing the right thing; the user changed their mind.** The "correction" is a normal task evolution, not a rule violation. Skip.
- **The pattern is one user, one session, never recurring.** Below threshold. Wait for next pass.
- **The pattern reflects a model capability gap.** No rule can fix "the model can't reason about X." File for awareness; don't write a rule.
- **The pattern requires a tool, not a rule.** "Did you run the tests" recurring → maybe a stop-hook that runs tests automatically beats a CLAUDE.md rule.
