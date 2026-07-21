---
title: Phase — execute the existing plan ("proceed")
---

# Phase: run ("let's go" / "proceed" / "run")

A plan exists — either in the tracking artifact, in a previous turn of the conversation, or both. The user wants you to execute it autonomously and only stop on a real fork or blocker.

## What "proceed" does and does not mean

**Does mean:**
- Execute the agreed plan end to end
- Make routine decisions yourself (formatter choices, obvious naming, which existing helper to reuse)
- Run validation as you go — you are not done until checks pass

**Does not mean:**
- Approval to take destructive or hard-to-reverse actions you didn't already discuss
- Approval to change scope mid-flight
- Approval to skip the plan if you "see something better" — propose, don't pivot silently

## Steps

### 1. Confirm the plan in one line

Before doing anything, re-state the plan in one or two sentences and the validation check you are working toward. This catches a stale interpretation cheaply. Example: "Running: add the SQS DLQ to module X, validate via `terraform plan` showing only the expected three resources."

If there is no plan (the user said "proceed" cold), stop and ask. "proceed" assumes a plan exists.

### 2. Track progress locally

Use the harness's task tracker (TaskCreate / TaskUpdate) for the in-session breakdown. This is for your own progress visibility — not a substitute for the project's tracking artifact, which gets updated separately at `checkpoint` time.

Set tasks to `in_progress` when you start them and `completed` immediately when done — do not batch.

### 3. Execute

Work through the plan. Run validation as soon as a step claims to be done — do not pile up unverified work.

For UI / frontend work, follow the workspace rule: actually start the dev server and use the feature; type-checks alone do not prove the feature works.

For infra / Terraform work, run `terraform plan` and compare the diff against your stated expectation before applying anything. Do not apply destructive changes without re-confirming with the user.

### 4. Stop conditions — when to break and ask

Stop the autonomous run and ask the user when any of these happen. Do not paper over them.

- **Real fork.** Two non-equivalent paths surface and you cannot pick from the plan or the project's conventions.
- **Blocker.** Something external is missing — credentials, an unreviewed MR, a decision the user owns.
- **Risky / destructive action surfaces.** Anything matching the workspace's risky-action list (force push, deleting data, modifying shared systems, sending external messages) — confirm explicitly even if a similar action was approved earlier in the session.
- **Plan no longer matches reality.** A core assumption from the plan turns out wrong. Surface, don't silently rewrite.
- **Validation fails twice in a row** with the same fix attempted. Stop and reason — there is a misunderstanding, not a typo.

### 5. Report at the end of the run

When the autonomous run reaches its natural end (validation passed, or you stopped on a condition above), report:

- **Done:** the concrete things that now exist or pass
- **Pending:** anything from the plan you intentionally did not do, with reason
- **Validation:** the exact command/check that confirms it (so the user can replay)
- **Next:** either "ready for `checkpoint`" or the open question that blocks progress

## Anti-patterns

- Treating "proceed" as a license to expand scope — stick to the plan
- Skipping validation because the change "looks right"
- Asking for permission on routine decisions — that defeats the point of this phase
- Waiting silently after a stop condition — surface it explicitly and propose the next step
