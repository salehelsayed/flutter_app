#!/bin/bash
# Read-only: key lines from the newest iOS payload capture's xcode logs.
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path/capture-* | head -1)/fast-path
for f in prepare.xcode.log cleanup-1.xcode.log; do
  echo "== $f"
  grep -E "error:|Test Case .*(passed|failed)|MKNOON_|Executed|TEST (EXECUTE|SUCCEEDED|FAILED)|automation" "$d/$f" | cut -c1-330 | head -12
done
head -c 1500 "$d/direct-notification-diagnostic.redacted.json"; echo
