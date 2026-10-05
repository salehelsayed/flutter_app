#!/bin/bash
# Build the architecture graph inside the UI-Update worktree (graphs are not in git).
cd /Volumes/CrucialX9/flutter_app-ui-update || exit 1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
./graphify-arch/refresh_arch_graph.sh 2>&1 | tail -15
ls -la graphify-arch/graphify-out/ 2>&1 | head -8
python3 graphify-arch/tdd_context.py query "drain group offline inbox" --profile general --budget 200 2>&1 | head -5
echo "R47 DONE"
