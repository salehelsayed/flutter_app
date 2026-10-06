#!/bin/bash
# Copy git-excluded tool config the graph tests read (.claude/skills/graphify, .codex/hooks.json) into the worktree.
M=/Volumes/CrucialX9/flutter_app; W=$M/.claude/worktrees/wave3-next
mkdir -p "$W/.claude/skills" "$W/.codex"
cp -Rp "$M/.claude/skills/graphify" "$W/.claude/skills/" && echo "copied .claude/skills/graphify"
cp -p "$M/.claude/settings.json" "$W/.claude/settings.json" && echo "copied .claude/settings.json"
cp -p "$M/.codex/hooks.json" "$W/.codex/hooks.json" && echo "copied .codex/hooks.json"
cd "$W" && echo "status_lines=$(git status --short | wc -l | tr -d ' ')"
python3 -m unittest graphify-arch/tests/test_graphify_arch_tooling.py 2>&1 | tail -3
