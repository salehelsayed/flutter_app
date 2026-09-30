#!/bin/bash
# Read-only: grep a worktree sims capability log. Usage: <cap id> <pattern> [context]
grep -n -A"${3:-0}" -E "$2" "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/logs/$1.log" | cut -c1-260 | head -40
