---
name: review
description: Grade changes under the protected paths (scripts/harness.conf) against the rubric docs/operations/conventions.md and report [BLOCKER]/[WARNING]/[CAVEAT] findings. Use when the user asks to review or grade changes, before any push or MR touching protected paths, or when the pre-push hook reports an ungraded change.
---

# review — the rubric grader

Grade changes to the protected paths against the conventions doc. The doc is the single source of rules — do not invent rules that are not in it, and do not skip rules that are.

## Steps

1. Read `scripts/harness.conf` for `PROTECTED_PATHS` and `RUBRIC`, then read the rubric in full.
2. Collect the material to grade, in this order of preference:
   - changed files: `git diff --name-only HEAD -- <protected paths>` plus `git diff --name-only --cached -- <protected paths>` plus commits ahead of `origin/main` if it exists, plus untracked files under the protected paths;
   - if nothing changed, grade **all** files under the protected paths (full audit).
3. Grade every rule in the doc against every collected file. Findings come in three bands:
   - **violation** → `[SEVERITY] <rule name> — <file>:<line> — <what is wrong> — <the correct form>`
   - **justified exception** (violation carrying an inline `# reason:`) → `[CAVEAT] <rule name> — <file>:<line> — <the stated reason>`. A caveat passed the structural check but rests on a semantic assumption the machine cannot verify — it is surfaced for human sign-off, never silently accepted. A `[BLOCKER]`-level exception additionally requires the justification in the MR/commit description; if that is missing, say so in the caveat line.
   - **pass** → not listed.
4. Summarize: count of blockers / warnings / caveats. If there are caveats, state explicitly that they route to a human for sign-off.
5. **Gate marker:**
   - zero `[BLOCKER]` findings → run `bash scripts/grade-marker.sh stamp` and state that the push gate is open (caveats do not block the gate — they block silent acceptance);
   - any `[BLOCKER]` → do NOT stamp; propose concrete fixes and offer to apply them.

## Hard rule

Never stamp the marker without having actually executed steps 1–4 in this session. The marker holds a fingerprint of the protected paths (see `scripts/grade-marker.sh`), so a stale or hand-touched marker fails the hook deterministically — but the fingerprint cannot prove the grade *happened*. That last step is this rule.
