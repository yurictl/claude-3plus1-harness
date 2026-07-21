# Pattern Interpretation Guide

How to read transcript-mine output. The script surfaces *candidates*; the human interpretation step distinguishes real recurring corrections from incidental matches.

## Default pattern categories

| Category | What it means | Yield rate |
|---|---|---|
| `explicit_instruction` | User states a rule (`always X`, `never Y`, `from now on`). | **Highest** — these are pre-formed rules ready to promote. |
| `stop_doing` | User explicitly tells the model to stop a behavior. | High — direct prohibition signal. |
| `still_wrong` | User signals the result is still incorrect. | Medium — needs context to know *what* is wrong. |
| `actually_correction` | User corrects an assumption. | Medium — often "model leaped to conclusion." |
| `wrong_target` | User says model operated on wrong file/scope. | Medium — points at target-selection heuristics. |
| `verification_request` | User asks if model checked something. | Medium — suggests missing default verification. |
| `additive_correction` | User asks for something that should have been included. | Low–medium — easiest to false-positive on (lots of normal "also" usage). |

The yield rate is **how often a hit in this category corresponds to a real promotable rule.** `explicit_instruction` is highest because the user did the work of stating a rule already.

## Reading the output

The JSON output has six top-level fields you should focus on:

1. **`counts_by_category`** — total hits per category, after the min-hits filter. Sort high → low; start with top.
2. **`sessions_per_category`** — distinct sessions (not just messages). 7 hits in 1 session = 1 frustrated thread; 7 hits in 7 sessions = a real recurring pattern.
3. **`counts_by_project`** — distribution. Concentration in one project = scope rule; spread across many = global rule.
4. **`examples`** — the truncated snippets. Read them. The whole point.
5. **`suppressed_low_hits`** — categories below `--min-hits`. Skim for patterns that might warrant lowering the threshold for a focused pass.
6. **`user_messages_seen`** — denominator. 5 hits in 50 messages is meaningful; 5 in 1000 is base rate.

## The discrimination question

For every example, ask:

> **"If I'd had a rule about this in CLAUDE.md a week ago, would the model have avoided this exchange?"**

If yes — promote.
If no — skip. Either it's not a recurring problem, the rule wouldn't be actionable, or it's a model-capability issue that no rule can fix.

This is the same shape as Hamel/Shreya's error-analysis discipline (open coding → axial coding → category): scan candidates, code the real ones, group into categories, design the fix.

## False-positive shapes to recognize

The regex patterns will match things that aren't corrections. Watch for:

- **The user pasted a list** containing words like "always" / "never" / "supported values" — matches `explicit_instruction` but isn't a rule for the model.
- **The user is describing a domain rule, not directing the model** — "the rule in finance is..." matches but is task content, not behavioral guidance.
- **The user used "actually" as a topic shift** — "actually let me think about Y instead" — not a correction.
- **`also` as natural connective** — "I also want to mention..." — not an additive correction.
- **`stop` as feature description** — "this is the stop button" — false positive.

For each match, **read the snippet, not just the count.** A high-count category populated with false positives is less actionable than a low-count category populated with real corrections.

## Cluster discipline

Two `still_wrong` hits about wildly different topics need wildly different fixes. Cluster before promoting.

Practical clustering:
1. Print all examples for the top 3 categories.
2. For each, write a one-phrase topic ("file paths", "tone", "test execution", "source URLs").
3. Group examples by topic.
4. Promote per-cluster, not per-category.

If a category has 12 hits across 7 distinct topics with no concentration, it's noise — skip the category as a whole and look at suppressed_low_hits with sharper patterns.

## Cross-referencing with existing config

Before proposing a fix:

1. **Read the target file** (`~/.claude/CLAUDE.md`, the project memory file, etc.).
2. **Grep it for the pattern.** Is there already a rule about this? If yes, the rule isn't being followed — the question is *why*. Bad wording, buried, or the model can't see the file in context.
3. **If a rule exists but isn't working:** rewrite for clarity, move it earlier in the file, or escalate (skill instead of CLAUDE.md line).

A transcript-mine pass that adds duplicate rules is worse than no pass at all — it grows the global config without fixing anything.

## Calibration over time

The script is calibrated when:
- Most surfaced categories contain ≥70% real corrections (not false positives) on inspection.
- Top patterns map to fixes the user agrees should have been in config already.
- Suppressed categories don't contain obvious recurring corrections that should have been counted.

If false-positive rate is high, edit `scripts/patterns.json` to tighten regexes for the offending category. Add domain-specific patterns (e.g., always-correcting tone in writing projects) for higher precision in your context.

## What "good" looks like

A well-calibrated pass produces output like:

> 4 categories above threshold. `explicit_instruction` (12, 6 sessions) — all in `~/notes/career-counsellor`, all about job-source URLs. → repo-specific CLAUDE.md rule.
> `verification_request` (7, 5 sessions) — spread across 3 projects, all about "did you run tests." → global CLAUDE.md.
> `stop_doing` (5, 3 sessions) — concentrated in writing projects, all about emoji and AI-tells. → augment the existing `linkedin-draft` skill.
> `still_wrong` (4, 4 sessions) — diffuse, no pattern. → defer; lower min-hits next pass to investigate.

Three concrete fixes proposed; one cluster deferred. That's a productive mining session.

A bad pass produces a wall of counts with no clear topic clustering. If you're getting that, the lookback window is too long, the patterns are too loose, or there genuinely isn't enough recurring correction signal in the period.
