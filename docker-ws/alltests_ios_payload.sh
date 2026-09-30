#!/bin/bash
# Read-only: newest iOS payload proof json files (bounded) with failure fields.
d=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path
for f in $(find "$d" -type f -name '*.json' -newermt '2026-09-26 03:00' 2>/dev/null | head -8); do echo "== ${f#$d/}"; head -c 900 "$f" | tr '\n' ' '; echo; done
