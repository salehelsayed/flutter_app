#!/bin/bash
# Read-only: does the UI-Update worktree (the build that showed "Media unavailable" for Pixel voice notes on the
# iPhone 13, 2026-10-08) differ from main in media receive code? Lists uncommitted and committed lib/ changes.
WT=/Volumes/CrucialX9/flutter_app-ui-update
cd "$WT" || { echo "no worktree"; exit 1; }
echo "branch: $(git rev-parse --abbrev-ref HEAD) head=$(git rev-parse --short HEAD)"
echo "merge-base with main: $(git merge-base HEAD main | cut -c1-9); main=$(git rev-parse --short main)"
echo "=== uncommitted lib/ ios/ changes"
git status --porcelain lib ios | head -60
echo "=== media/voice/download related files differing from main (committed + uncommitted)"
git diff --stat main -- lib | grep -iE 'media|voice|audio|download|attachment|blob|chat_message_listener' | head -40
echo "=== total lib diff vs main"
git diff --shortstat main -- lib
