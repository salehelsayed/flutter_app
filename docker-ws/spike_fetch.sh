#!/bin/bash
# Copy Codex's translation-spike handoff and APK into this repo's evidence folder (read-only on the source).
S=/Users/I560101/.codex/worktrees/relay-thought-returners-20261027/.codex-test-logs/translation-spike-20261028
D=/Volumes/CrucialX9/flutter_app/.codex-test-logs/translation-spike-20261028; mkdir -p "$D"
cp "$S/HANDOFF.md" "$S/translation-spike-debug.apk" "$D/" && ls -la "$S" && shasum -a 256 "$D/translation-spike-debug.apk"
