#!/bin/bash
# Read-only: list Astra's P0 evidence folder and print small summary files (no app data).
#   host-run bash docker-ws/astra_p0_evidence_peek.sh
W=/Volumes/CrucialX9/flutter_app-astra-p0-tests-post129-20261030
ls -1 "$W/.codex-test-logs/" 2>/dev/null | tail -20
D=$(ls -d "$W"/.codex-test-logs/p0-* 2>/dev/null | tail -3)
for d in $D; do echo "== $d"; ls -1 "$d" | head -30; done
for f in $(ls "$W"/.codex-test-logs/p0-*/*summary* "$W"/.codex-test-logs/p0-*/*SUMMARY* "$W"/.codex-test-logs/p0-*/*result*.md 2>/dev/null | head -5); do echo "=== $f"; head -60 "$f"; done
