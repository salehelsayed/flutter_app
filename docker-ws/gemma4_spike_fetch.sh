#!/bin/bash
# Copy Codex's Gemma 4 spike handoff, artifact.json and APK into this repo's evidence folder (source only read).
S=/Users/I560101/.codex/worktrees/relay-thought-returners-20261027/.codex-test-logs/gemma4-spike-20261028
D=/Volumes/CrucialX9/flutter_app/.codex-test-logs/gemma4-spike-20261028; mkdir -p "$D"
ls -la "$S"
cp "$S/HANDOFF.md" "$S/artifact.json" "$S/gemma4-spike-debug.apk" "$D/" 2>&1; echo "cp exit=$?"
stat -f '%z %N' "$D/gemma4-spike-debug.apk"; shasum -a 256 "$D/gemma4-spike-debug.apk"
