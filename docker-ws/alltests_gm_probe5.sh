#!/bin/bash
# Read-only. Mode "log": print the sims row log. Mode "x": earlier xcresult summaries + newest stdout middle.
W=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
P=$W/build/sims/proofs/groups.media_send_reliability_ios
if [ "$1" = log ]; then LC_ALL=C grep -a -v -i -E 'token|secret|password' "$W/build/sims/logs/groups.media_send_reliability_ios.log"; exit 0; fi
for d in $(ls -td "$P"/ios-p269-* | sed -n 2,3p); do echo "##### ${d##*/}"
  xcrun xcresulttool get test-results tests --path "$d/p269-ios.xcresult" 2>&1 | LC_ALL=C grep -a -E '"(name|result|failureMessage|durationInSeconds)"|failure|Failure' | head -12 | cut -c1-240
  xcrun xcresulttool get log --type console --path "$d/p269-ios.xcresult" 2>/dev/null | LC_ALL=C grep -a -E 'MKNOON_269|Waiting|error:|failed \(' | head -8 | cut -c1-240
done
d=$(ls -td "$P"/ios-p269-* | head -1)
echo "##### newest stdout t>=6s (non-Checking)"
find "$d/p269-ios.xcresult" -name 'StandardOutputAndStandardError*.txt' -print0 | while IFS= read -r -d '' f; do LC_ALL=C grep -a -v 'Checking existence' "$f" | LC_ALL=C grep -a -E ' t = |MKNOON|error' | head -30 | LC_ALL=C cut -c1-300; done
echo "##### sims log size"; ls -lT "$W/build/sims/logs/groups.media_send_reliability_ios.log" | awk '{print $5,$6,$7,$8}'
