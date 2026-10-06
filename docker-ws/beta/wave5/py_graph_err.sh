#!/bin/bash
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
python3 -m unittest graphify-arch/tests/test_graphify_arch_tooling.py 2>&1 | sed -n '/^FAIL:/,/^Ran/p' | grep -vE "^\s+~|^\s+\^" | tail -14
