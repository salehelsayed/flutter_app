#!/bin/bash
# Read-only probe before creating the "fixes" worktree.
echo "=== mac git ==="; git --version
echo "=== zshrc claude-docker ==="; grep -n -A7 'claude-docker' "$HOME/.zshrc"
echo "=== target path ==="; ls -ld /Volumes/CrucialX9/flutter_app-fixes 2>&1
echo "=== branches ==="; git -C /Volumes/CrucialX9/flutter_app branch --list 'fixes*'
echo "=== docker home ==="; ls -la "$HOME/.claude-docker-home" | head -30
echo PROBE DONE
