.PHONY: replay replay-tiers replay-ablate accept-rubric test-harness invariants test-invariants test seed-violation seed-twin-violation reset health report html backfill seed-telemetry reset-telemetry escapes

# --- verification harness ----------------------------------------------------

test-harness:      ## the gate's own regression suite (no LLM, no network, seconds)
	bash tests/harness/run.sh

invariants:        ## state invariants over the whole tree (what the push gate runs; no LLM)
	@python3 scripts/check_invariants.py

test-invariants:   ## each invariant vs the state that shipped its escape (hit) and the fix (clear)
	bash tests/invariants/retro.sh

replay:            ## replay the golden set through the pinned grader; per-set catch-rate
	bash scripts/replay.sh

replay-tiers:      ## replay on the pinned AND the cheap model — which rules are portable
	bash scripts/replay.sh --tiers

replay-ablate:     ## replay with and WITHOUT the rubric — which rules the model already knows
	bash scripts/replay.sh --tiers --ablate

accept-rubric:     ## record the current per-set rates as the committed baseline
	bash scripts/replay.sh --update-baseline

test: test-harness test-invariants replay   ## gate suite + invariant retro + grader calibration

seed-violation:    ## drop a violating file into src/ to demo the /review + hook loop
	cp tests/golden/held-in/plaintext-secret/case.txt src/demo-violation.txt
	@echo "Seeded src/demo-violation.txt (plaintext password)."
	@echo "Now ask Claude to commit & push it -> the hook blocks; run /review -> [BLOCKER]."

seed-twin-violation: ## add a third environment without the twins' keys — the invariant gate's demo
	printf '[server]\n' > src/env/staging.conf
	@echo "Seeded src/env/staging.conf (no server.port, which dev and prod both set)."
	@echo "/review grades the new file clean — nothing in it is wrong on its own. Push -> the"
	@echo "invariant gate blocks: INV-ENV-KEY-PARITY. 'make invariants' shows the same."

reset:             ## remove the demo violations, the grade marker and the grade record
	rm -f src/demo-violation.txt src/env/staging.conf .claude/grade-ok .claude/last-grade.json
	@echo "Clean."

# --- harness health: does the harness WORK -------------------------------------
# Independent of the activity half below — reads only replay/escape/grade logs.

health:            ## catch-rate + trend, escapes, dead weight, loop closure
	@python3 scripts/harness_health.py

# --- activity telemetry: is the harness USED -----------------------------------
# Generic agent observability; the half to drop when the platform ships its own.

report:            ## activity summary + the harness-health panel
	@python3 scripts/telemetry_report.py

html:              ## static dashboard -> .claude/telemetry/report.html
	@python3 scripts/telemetry_report.py --html .claude/telemetry/report.html

escapes:           ## failures that got past a clean grade, newest first
	@bash scripts/escape-log.sh list 20

backfill:          ## harvest every transcript of this project (idempotent)
	@python3 scripts/telemetry_harvest.py --all

seed-telemetry:    ## deterministic telemetry demo data (no real sessions needed)
	@python3 scripts/seed_demo.py

reset-telemetry:   ## wipe the telemetry stores
	@rm -rf .claude/telemetry
	@echo "telemetry stores removed"
