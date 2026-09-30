#!/bin/bash
# Read-only: Staging diagnostics, test summary strings, prior xcresult summary, sims run logs. Bounded.
W=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
P=$W/build/sims/proofs/groups.media_send_reliability_ios
d=$(ls -td "$P"/ios-p269-* | head -1); X=$d/p269-ios.xcresult
echo "=== Staging files"; find "$X/Staging" -type f -print0 | while IFS= read -r -d '' f; do echo "$(stat -f '%z %Sm' "$f") ${f#$X/Staging/1_Test/Diagnostics/}"; done
find "$X/Staging" -type f \( -name '*.txt' -o -name '*.log' \) -print0 | while IFS= read -r -d '' f; do echo "--- tail ${f##*/}"; LC_ALL=C grep -a -v -i -E 'token|secret|password' "$f" | LC_ALL=C grep -a -i -E 'fail|error|assert|timed out|wait|crash|terminat|P269|MKNOON_269|Test Case|Executed' | tail -n 25 | LC_ALL=C cut -c1-220; done
echo "=== summary strings"; for b in "$X"/Data/data.*; do s=$(stat -f %z "$b"); [ "$s" -ne 19850 ] && continue; /opt/homebrew/bin/zstd -dc "$b" | LC_ALL=C strings -n 8 | LC_ALL=C grep -a -v -E '^K[0-9]|^\[T' | awk '!seen[$0]++' | head -70 | LC_ALL=C cut -c1-200; done
