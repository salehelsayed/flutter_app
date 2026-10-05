#!/bin/bash
# Run one repo script (path relative to the repo root) inside the wave3-next worktree.
#   wt_script.sh scripts/test/x.sh [args...]
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
s=$1; shift; case "$s" in *.py) exec python3 "$s" "$@";; *) exec bash "$s" "$@";; esac
