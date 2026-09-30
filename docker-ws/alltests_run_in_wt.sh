#!/bin/bash
# Run a command in the all-tests worktree with the 3.47.2 SDK first on PATH: alltests_run_in_wt.sh <cmd> args...
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree || exit 4
export PATH="$HOME/development/flutter-3.47.2/bin:$PATH"
"$@"
