#!/bin/bash
# Print the SIMS dry-run plan for one capability in the worktree (no devices touched).
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
timeout 300 dart tool/sims/sims.dart major --only "$1" --dry-run --format json 2>&1 | head -c 6000
