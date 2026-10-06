#!/bin/bash
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PROJECT_MEMORY_TEST_MEMORY_DIR="$HOME/.claude-docker-home/.claude/projects/-workspace/memory"
python3 -m unittest -v project-memory/tests/test_project_memory.py 2>&1 | sed -n '/^FAIL:/,/^Ran /p' | head -40
