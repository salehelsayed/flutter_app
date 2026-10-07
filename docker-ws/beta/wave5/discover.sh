#!/bin/bash
# Run the checks tool's device discovery against the Wave 5 config in the worktree.
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk" PATH="$HOME/development/flutter-3.47.2/bin:$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:$PATH"
time python3 scripts/mknoon_checks.py devices --device-config .codex-test-logs/production-bootstrap-migration-20260930/wave5-full-device-config.json 2>&1 | tail -15 | cut -c1-200
