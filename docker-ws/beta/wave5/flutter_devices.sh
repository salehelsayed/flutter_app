#!/bin/bash
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:$PATH"
which flutter; timeout 90 flutter devices --machine 2>&1 | tail -20 | cut -c1-200; echo "rc=$?"
