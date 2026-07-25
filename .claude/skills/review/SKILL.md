---
name: review
description: Grade changes under the protected paths (scripts/harness.conf) against the rubric docs/operations/conventions.md and report [BLOCKER]/[WARNING]/[CAVEAT] findings. Use when the user asks to review or grade changes, before any push or MR touching protected paths, or when the pre-push hook reports an ungraded change.
---

# review — the rubric grader

Grade changes to the protected paths against the conventions doc. The doc is the single source of rules — do not invent rules that are not in it, and do not skip rules that are.

## Steps

1. Read `scripts/harness.conf` for `PROTECTED_PATHS` and `RUBRIC`, then read the rubric in full.
2. Collect the material to grade, in this order of preference:
   - changed files: `git diff --name-only HEAD -- <protected paths>` plus `git diff --name-only --cached -- <protected paths>` plus commits ahead of the branch's upstream (or `origin/main`) if one exists, plus untracked files under the protected paths;
   - if nothing changed, grade **all** files under the protected paths (full audit).
3. Grade every rule in the doc against every collected file. Findings come in three bands:
   - **violation** → `[SEVERITY] <rule name> — <file>:<line> — <what is wrong> — <the correct form>`
   - **justified exception** (violation carrying an inline `# reason:`) → `[CAVEAT] <rule name> — <file>:<line> — <the stated reason>`. A caveat passed the structural check but rests on a semantic assumption the machine cannot verify — it is surfaced for human sign-off, never silently accepted. A `[BLOCKER]`-level exception additionally requires the justification in the MR/commit description; if that is missing, say so in the caveat line.
   - **pass** → not listed.
4. Summarize: count of blockers / warnings / caveats. If there are caveats, state explicitly that they route to a human for sign-off.
5. **Record the grade.** Pipe the findings into the canonical writer — this is the artifact `stamp` validates, so it must reflect what you actually read:

   ```bash
   bash scripts/grade-marker.sh record <<'JSON'
   {"blocker": 0, "warning": 1, "caveat": 1,
    "graded": ["src/app.conf", "src/other.conf"],
    "findings": ["[WARNING] TODO carries a tracker reference — src/app.conf:12 — …",
                 "[CAVEAT] TODO carries a tracker reference — src/other.conf:4 — vendor driver leaks above 50"]}
   JSON
   ```

   `graded` must name the files you actually read, and `findings` must carry the lines the counts refer to — the script refuses a record that counts findings it does not contain. The fingerprint, the rubric hash and the timestamp are added by the script; you cannot supply them.
6. **Open or hold the gate:**
   - zero `[BLOCKER]` findings → `bash scripts/grade-marker.sh stamp`, then state that the push gate is open (caveats do not block the gate — they block silent acceptance);
   - any `[BLOCKER]` → do NOT stamp; propose concrete fixes and offer to apply them. (`stamp` would refuse the record anyway, and say why.)

## Hard rule

Never record a grade you did not perform. The record and the marker cannot be written any other way — the file tools are blocked on both paths and `stamp` refuses a record whose fingerprint, rubric hash or age does not match — but no mechanism can prove the *grading* happened. That last step is this rule, and every stamped grade is appended to `.claude/telemetry/grades.jsonl`, so a fabricated one is durable and auditable rather than invisible.

## Notes

- Never edit the rubric to make the material pass. If a rule is wrong, that is a `/checkpoint` proposal with a golden fixture, landed separately — the push gate blocks product and calibration changes travelling together.
- If `stamp` refuses, read the reason and act on it; do not retry the command. Three consecutive failed attempts at the same check → stop and surface to the human (`CLAUDE.md`, bounded retries).
