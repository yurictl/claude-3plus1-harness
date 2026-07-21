#!/usr/bin/env bash
# Telemetry collector: append one JSONL event per harness signal to
# .claude/telemetry/events.jsonl. Zero-LLM, write-and-forget, ALWAYS exit 0 —
# telemetry must never block or slow the agent.
#
# Wired in .claude/settings.json for three hook events:
#   UserPromptSubmit — logs work-loop trigger phrases (start-work / checkpoint /
#                      run / resume / graduate); non-trigger prompts are NOT logged
#   PreToolUse Bash  — logs `git push` and MR-creation commands
#   PreToolUse Skill — logs every skill invocation (harness-usage metric)
#
# The trigger vocabulary is the `triggers` list below — edit it to match your
# own work-loop phrases. See README.md for the full design.

STORE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/telemetry"
STORE="$STORE_DIR/events.jsonl"

payload=$(cat 2>/dev/null) || exit 0
mkdir -p "$STORE_DIR" 2>/dev/null || exit 0

printf '%s' "$payload" | python3 -c '
import json, re, sys, datetime

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

hook = d.get("hook_event_name", "")
event = None
detail = {}

if hook == "UserPromptSubmit":
    prompt = d.get("prompt", "") or ""
    low = prompt.lower()
    # Work-loop vocabulary — English + Russian examples; adapt to your own.
    triggers = [
        ("start-work",  r"начинаем|start work|kick off"),
        ("checkpoint",  r"фиксируемся|зафиксир|checkpoint|snapshot"),
        ("run",         r"погнали|поехали|let.s go|proceed"),
        ("resume",      r"продолжим|продолжаем|continue|resume"),
        ("graduate",    r"graduate|выпускаем"),
    ]
    for name, pat in triggers:
        if re.search(pat, low):
            event = name
            detail = {"prompt": prompt[:200]}
            break
elif hook == "PreToolUse":
    tool = d.get("tool_name", "")
    ti = d.get("tool_input", {}) or {}
    if tool == "Bash":
        cmd = (ti.get("command", "") or "").replace("\n", " ")
        if re.search(r"git(\s+-C\s+(\"[^\"]+\"|\S+))?\s+push(\s|$)", cmd):
            event = "push"
        elif "glab mr create" in cmd or "gh pr create" in cmd:
            event = "mr-create"
        if event:
            detail = {"command": cmd[:300]}
    elif tool == "Skill":
        event = "skill"
        detail = {"skill": ti.get("skill", ""), "args": (ti.get("args", "") or "")[:200]}

if event is None:
    sys.exit(0)

rec = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "event": event,
    "session": d.get("session_id", ""),
    "cwd": d.get("cwd", ""),
    "detail": detail,
}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
' "$STORE" 2>/dev/null

exit 0
