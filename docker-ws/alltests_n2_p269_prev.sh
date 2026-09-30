#!/bin/bash
# Read-only: show key lines of each p269 capture's xcodebuild-test.log and stderr stage.
B=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios
for d in "$B"/ios-p269-*; do
  echo "=== $d"; cat "$d/phase-a-receipt.json.stderr.log" 2>/dev/null; echo
  ls "$d" | tr '\n' ' '; echo
  grep -nE "MKNOON_269|Pressing Home|error:|failed \(|Timed out" "$d/xcodebuild-test.log" 2>/dev/null | cut -c1-260 | head -20
done
