#!/bin/bash
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next && git fetch -q origin fix/conversation-photo-keyboard-overflow && git checkout -q -B pr9-docfix origin/fix/conversation-photo-keyboard-overflow && git log --oneline -1 && git status --porcelain --untracked-files=no | wc -l
