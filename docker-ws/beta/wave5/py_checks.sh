#!/bin/bash
# Run the three Python test groups that blocked the full run, in the worktree, with the Wave 5 environment.
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PROJECT_MEMORY_TEST_MEMORY_DIR="$HOME/.claude-docker-home/.claude/projects/-workspace/memory"
for t in graphify-arch/tests/test_graphify_arch_tooling.py project/tests/test_build_project_index.py project-memory/tests/test_project_memory.py; do
  echo "== $t"; python3 -m unittest -v "$t" 2>&1 | grep -E "skipped|^Ran |^OK|FAILED|Error" | head -8
done
