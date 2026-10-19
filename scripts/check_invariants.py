#!/usr/bin/env python3
"""Check the project's state invariants over a tree (stdlib only, no LLM).

The rubric is graded against a DIFF; an invariant is a property of the whole
STATE that must hold after any change, whichever file the change touched. The
escapes it exists for live outside the diff: a twin file that never got the
fix, a consumer of something renamed, a value that only exists once derived.

Registry: scripts/invariants/registry.tsv   (id, statement, check, provenance)
Waivers:  scripts/invariants/exceptions.tsv (id, subject, reason)

Check contract — each `check` is an executable (.py → python3, .sh → bash,
else run directly) called with the tree root as its only argument:
  stdout  one violation per line: <subject><TAB><detail>
  exit 0  the invariant holds (and stdout is empty)
  exit 1  violated
  other   could not run — never read as a pass

  check_invariants.py [--root DIR] [--only ID,ID] [--json]

Exit 0 = all hold, 1 = violation(s), 2 = could not run (bad registry, a check
that crashed, a waiver without a reason). 2 is never folded into 0 or 1.
"""
import argparse
import json
import os
import subprocess
import sys

HARNESS_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_tsv(path, columns):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            if not line.strip() or line.startswith("#"):
                continue
            cells = line.rstrip("\n").split("\t")
            if len(cells) < columns:
                raise ValueError(f"{path}:{n}: expected {columns} tab-separated columns, got {len(cells)}")
            rows.append([c.strip() for c in cells])
    return rows


def run_check(check, root):
    path = os.path.join(HARNESS_ROOT, check)
    if not os.path.exists(path):
        raise ValueError(f"check not found: {check}")
    argv = [sys.executable, path] if path.endswith(".py") else ["bash", path] if path.endswith(".sh") else [path]
    proc = subprocess.run(argv + [root], capture_output=True, text=True, timeout=120)
    if proc.returncode not in (0, 1):
        raise ValueError(f"{check} could not run (exit {proc.returncode}): {proc.stderr.strip()[:300]}")
    lines = [l for l in proc.stdout.splitlines() if l.strip()]
    if proc.returncode == 0 and lines:
        raise ValueError(f"{check} exited 0 but reported violations — contract broken")
    if proc.returncode == 1 and not lines:
        raise ValueError(f"{check} exited 1 without naming a violation — contract broken")
    return [tuple((l.split("\t", 1) + [""])[:2]) for l in lines]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=HARNESS_ROOT, help="tree to check (default: the project root)")
    ap.add_argument("--registry", default=os.path.join(HARNESS_ROOT, "scripts", "invariants", "registry.tsv"))
    ap.add_argument("--exceptions", default=os.path.join(HARNESS_ROOT, "scripts", "invariants", "exceptions.tsv"))
    ap.add_argument("--only", help="comma-separated invariant ids")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    only = set(a.only.split(",")) if a.only else None
    findings, notes, used = [], [], set()
    try:
        registry = read_tsv(a.registry, 4)
        ids = {r[0] for r in registry}
        waivers = {}
        for inv, subject, reason in (r[:3] for r in read_tsv(a.exceptions, 3)):
            if inv not in ids or not reason:
                raise ValueError(f"exception needs a known invariant and a reason: {inv} {subject}")
            waivers[(inv, subject)] = reason
        root = os.path.abspath(a.root)
        for inv, _statement, check, _provenance in registry:
            if only and inv not in only:
                continue
            for subject, detail in run_check(check, root):
                if (inv, subject) in waivers:
                    used.add((inv, subject))
                    continue
                findings.append({"invariant": inv, "subject": subject, "detail": detail})
    except (ValueError, OSError, subprocess.SubprocessError) as e:
        print(f"check_invariants: {e}", file=sys.stderr)
        return 2

    for key in waivers:
        if key not in used and (not only or key[0] in only):
            notes.append(f"exception {key[0]} {key[1]} no longer matches anything — drop it")

    if a.json:
        print(json.dumps({"findings": findings, "notes": notes}, indent=1))
    else:
        for f in findings:
            print(f"{f['invariant']}  {f['subject']}: {f['detail']}")
        for n in notes:
            print(f"note: {n}")
        print(f"{len(findings)} violation(s), {len(registry)} invariant(s) checked")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
