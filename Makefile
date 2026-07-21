.PHONY: replay seed-violation reset report html backfill seed-telemetry reset-telemetry

# --- verification harness ----------------------------------------------------

replay:            ## replay the golden set through a headless grader; prints catch-rate
	bash scripts/replay.sh

seed-violation:    ## drop a violating file into src/ to demo the /review + hook loop
	cp tests/golden/plaintext-secret/case.txt src/demo-violation.txt
	@echo "Seeded src/demo-violation.txt (plaintext password)."
	@echo "Now ask Claude to commit & push it -> the hook blocks; run /review -> [BLOCKER]."

reset:             ## remove the demo violation and the grade marker
	rm -f src/demo-violation.txt .claude/grade-ok
	@echo "Clean."

# --- telemetry -----------------------------------------------------------------

report:            ## console summary over the telemetry stores
	@python3 scripts/telemetry_report.py

html:              ## static dashboard -> .claude/telemetry/report.html
	@python3 scripts/telemetry_report.py --html .claude/telemetry/report.html

backfill:          ## harvest every transcript of this project (idempotent)
	@python3 scripts/telemetry_harvest.py --all

seed-telemetry:    ## deterministic telemetry demo data (no real sessions needed)
	@python3 scripts/seed_demo.py

reset-telemetry:   ## wipe the telemetry stores
	@rm -rf .claude/telemetry
	@echo "telemetry stores removed"
