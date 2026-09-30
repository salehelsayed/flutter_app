#!/bin/bash
# Read-only: list variable NAMES (never values) the run env scripts define.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
for f in run-env-after-source039.sh run-env-next.sh; do echo "== $f =="; grep -oE '^(export +)?[A-Z_][A-Z0-9_]*=' "$run/$f" | sed -E 's/^export +//; s/=$//' | sort -u | tr '\n' ' '; echo; grep -E '^\s*(source|\.) ' "$run/$f" | sed -E 's/=.*//' ; done
echo "== worktree mknoon_checks =="; ls -la /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/scripts/mknoon_checks.py
