#!/bin/bash
# Read-only: processes holding the main checkout index.lock open, and running git processes for that repo (pid, start, command head).
L=/Volumes/CrucialX9/flutter_app/.git/index.lock
echo "holders:"; lsof "$L" 2>/dev/null | tail -n +2 | cut -c1-80
echo "git processes:"; pgrep -lf "^git |/git " 2>/dev/null | cut -c1-120 | head -10
