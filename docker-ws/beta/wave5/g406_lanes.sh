#!/bin/bash
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406 || exit 1
bash scripts/run_host_test_gates.sh --list 2>&1 | head -60
