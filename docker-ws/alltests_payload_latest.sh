#!/bin/bash
# Read-only: newest android payload proof files (names, and small json bodies).
d=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.android_payload_campaign
ls -t "$d" | head -8
for f in $(find "$d" -maxdepth 1 -name '*.json' -newermt '2026-09-26 13:40' | head -5); do echo "== ${f#$d/}"; head -c 1200 "$f"; echo; done
