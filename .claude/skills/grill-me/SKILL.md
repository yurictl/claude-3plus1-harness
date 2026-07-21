---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree, and channelling resolutions into the project's 3+1 docs (Orientation = CLAUDE.md / LEXICON / CONTRACT, Operations, Decisions, WIP). Use when user wants to stress-test a plan, get grilled on their design, agree on naming, clarify how the agent should behave in this project, or mentions "grill me".
---

> **Origin.** This skill is Yuri Timerkhanov's adaptation of Matt Pocock's `grill-with-docs` interview pattern (`@mattpocockuk`, founder of AI Hero). The change: every resolution is routed into the **3+1 documentation framework**, and a new **CONTRACT.md** layer captures the behavioural agreement with the agent. The framework itself is described in [this LinkedIn post](https://www.linkedin.com/feed/update/urn:li:share:7431585543827668992).

Interview the user relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask one question at a time. If a question can be answered by exploring the codebase, explore the codebase instead of asking.

## What the session produces

Every grilling session resolves things. Route each resolution into the project's **3+1 documentation framework** — 3 persistent buckets (Orientation, Operations, Decisions) plus 1 transient (WIP). Within Orientation there are up to three slots: `CLAUDE.md`, `LEXICON.md`, `CONTRACT.md`.

| Resolution type | Destination | When to write |
|---|---|---|
| Canonical name for a domain object / term | `LEXICON.md` at project root (Orientation) | Inline, the moment the term crystallizes |
| Rule about how the **agent** behaves (permissions, proactivity scope, batch protocol, what to ask vs do silently) | `CONTRACT.md` at project root (Orientation) | Inline after the user confirms the rule — stop, ask, fix |
| Repeatable procedure with concrete steps | `docs/operations/<slug>.md` (Operations) | When ≥3 steps + clear trigger/precondition emerge |
| Trade-off resolved with a non-obvious choice | `docs/decisions/NNNN-<slug>.md` (Decisions, ADR) | When the **three-test** below passes |
| Open question, punted on purpose | `docs/wip/<slug>.md` **or** project's task tracker (ergo / bd / etc.) | When the user explicitly defers |

Detect the project's existing layout before writing. If `docs/operations/` or `docs/decisions/` don't exist yet, create them only when there's actual content to put in. For multi-module projects, a local `LEXICON.md` / `CONTRACT.md` per module is fine — same convention as `CLAUDE.md`.

## LEXICON.md — the glossary

A flat list of canonical terms, one short paragraph each. Pure glossary, **stripped of implementation detail**. The point is shared vocabulary.

- **Challenge conflicts.** When the user's wording contradicts an existing LEXICON entry, surface it immediately and ask which one is canonical.
- **Sharpen fuzzy terms.** When a word is overloaded (e.g. "account" — Customer or User?), propose a precise term and recommend one.
- **Cross-reference code.** When the user's claim conflicts with the actual implementation, surface the discrepancy and resolve before writing.
- **Write inline.** Don't batch — capture each resolved term as it lands.

## CONTRACT.md — working agreement with the agent

The behavioral contract between the user and the agent in this project. **Not a code/API contract** — it answers "how does the agent operate here?", not "what does the module promise?". Lives at project root alongside `LEXICON.md` and `CLAUDE.md`.

Typical clauses: decision authority (read-anywhere / safe-write / ask-first), batch-operation protocol, proactivity radius, frontmatter / metadata policy, marking of agent-authored content, memory policy, skill auto-trigger policy.

**Boundary test.** Apply both:
1. "Does this rule change what the *agent* does in future sessions?" — yes → CONTRACT.
2. "Is this about code or about behavior?" — behavior → CONTRACT; code → Decisions / Operations.

If a resolution describes a code/system promise (invariant, error mode, idempotency, ordering) — that's not CONTRACT in this framework; it belongs in Decisions or in code itself.

**Triggers during grilling.** Watch for:
- "Don't / do X" — permission rule.
- "Ask first before Y" — gate rule.
- "Be proactive about Z but not W" — scope rule.
- "When you say 'batch', what does that mean?" — protocol rule.
- "Auto-trigger skill X here, or always ask?" — skill policy.
- "Mark your own writing as …" — authorship rule.

**How to write.** Stop, ask the user to confirm the rule verbatim, write it inline as a numbered clause. The protocol mirrors the user's own evolution rule: *encounter ambiguity → stop → ask → fix here*. Don't batch; don't paraphrase; don't infer "obvious" rules. When a new clause contradicts an old one, the new one wins — note the supersession in the old clause rather than silently editing.

## docs/decisions/ — ADRs

Only create an ADR when **all three** are true:
1. The decision is costly to reverse.
2. It would be non-obvious to a future reader without context.
3. It results from a genuine trade-off, not a default.

If any of the three is missing, the resolution belongs in LEXICON, Operations, or just the code. Don't pad the decisions/ folder with low-stakes choices.

Naming: `NNNN-<kebab-slug>.md`, where NNNN is the next free number. Minimal template — Context / Decision / Consequences. Append-only; supersede with a new ADR rather than editing.

## docs/operations/ — runnable procedures

Create when grilling produces a concrete procedure someone (or future-you) would actually re-run. Signal: the user just walked you through "how we do X" with steps, a trigger, and a precondition. Tell-tales: "every time", "before deploy", "when key rotates", "to onboard a new …".

- Lead with the trigger and prerequisites.
- Numbered steps, each runnable (command, click, decision rule).
- Reference data right next to the step that needs it — don't split how-to from reference unless the reference is genuinely shared.
- One procedure per file. Slug from the trigger, not the topic.

## docs/wip/ or tracker — open questions

When the user defers a question ("not now", "park it", "I don't know yet"), don't lose it. If the project has a task tracker (per `CLAUDE.md`), create a tracker entry. Otherwise drop a short note in `docs/wip/<slug>.md` with the question, what's known, and what would unblock it.

Don't write WIP for questions the grilling itself just answered — only for genuinely deferred ones.

## Writing rules

- **Lazy creation.** Don't pre-create empty files. A folder appears the first time it has real content.
- **One destination per resolution.** If a resolution feels like it belongs in two places, it usually means it's still fuzzy — grill harder.
- **Confirm before writing decisions and operations.** LEXICON entries can be written inline; ADRs and Operations docs are bigger commitments — propose the draft, get a nod, then write.
- **Match the project's language.** If existing docs are in Russian, write in Russian. If English, English. Don't mix within a file.
- **Respect local CLAUDE.md.** A subproject's CLAUDE.md may override paths or conventions (e.g. legacy beads tracker, Obsidian vault rules). Read it first.

## End of session

When the user signals "done" / "enough", give a one-screen summary:
- Terms added/changed in LEXICON.
- CONTRACT clauses added/changed.
- ADRs drafted.
- Operations docs drafted.
- WIP/tracker items opened.
- Anything still genuinely unresolved.

No retrospective on the interview itself. Just the artifacts.
