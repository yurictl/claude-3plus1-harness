#!/usr/bin/env python3
"""INV-ENV-KEY-PARITY: every key set in one src/env/*.conf is set in all of them.

Template example of a twin invariant: a setting added to the environment you are
working in, and never to the others, reads correct in the diff and fails in the
environment nobody touched. Usage: env-key-parity.py <tree-root>
"""
import configparser
import glob
import os
import sys

root = sys.argv[1]
keys = {}
for path in sorted(glob.glob(os.path.join(root, "src", "env", "*.conf"))):
    cp = configparser.ConfigParser()
    cp.read(path, encoding="utf-8")
    keys[os.path.relpath(path, root)] = {f"{s}.{k}" for s in cp.sections() for k in cp[s]}

union = set().union(*keys.values()) if keys else set()
violations = 0
for path, have in keys.items():
    for key in sorted(union - have):
        where = ", ".join(os.path.basename(p) for p, h in keys.items() if key in h)
        print(f"{path}\tmissing {key} (set in {where})")
        violations += 1
sys.exit(1 if violations else 0)
