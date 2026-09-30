#!/bin/bash
# Read-only: newest iOS payload capture: files + failure lines in its logs.
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path/capture-* | head -1)
echo "dir=${d##*/}"
find "$d" -type f | sed "s|$d/||" | head -20
grep -rhE "automation mode|Failed to initialize|request_not_staged|handoff_deadline|failureCode|providerSetupComplete|auto_setup|error:" "$d" 2>/dev/null | cut -c1-220 | sort | uniq -c | head -12
