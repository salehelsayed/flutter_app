#!/bin/bash
# Read-only: newest android payload campaign proof files mentioning sender failure.
d=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.android_payload_campaign
n=$(ls -td "$d"/*/ 2>/dev/null | head -1); echo "dir=$n"; ls -t "$n" | head -12
grep -rhoE '"(errorCode|senderFailure|cleanupCode|failureCode|stage)":"?[^,}]{0,80}' "$n" 2>/dev/null | sort | uniq -c | head -15
