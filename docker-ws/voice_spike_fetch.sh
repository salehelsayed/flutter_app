#!/bin/bash
# Copy Codex's voice-spike handoff, APK and inputs into this repo's evidence folder (source only read).
S=/Users/I560101/.codex/worktrees/relay-thought-returners-20261027/.codex-test-logs/voice-spike-20261028
D=/Volumes/CrucialX9/flutter_app/.codex-test-logs/voice-spike-20261028; mkdir -p "$D"
cp "$S/HANDOFF.md" "$S/voice-spike-debug.apk" "$S/audio-fixtures.json" "$S/SOURCES.md" "$S/audio_report.py" "$D/" 2>&1
shasum -a 256 "$D/voice-spike-debug.apk"
