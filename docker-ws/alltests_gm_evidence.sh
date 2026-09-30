#!/bin/bash
# Read-only: newest iOS group media run's saved xcodebuild log failure lines and fixture stderr stage lines.
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios/ios-p269-* | head -1)
echo "dir=${d##*/}"; ls "$d" | grep -E "xcodebuild-test.log|stderr.log"
grep -hE "error:|XCTAssert|MKNOON_269|Test Case .*(failed|passed)|Timed out|automation" "$d/xcodebuild-test.log" 2>/dev/null | cut -c1-260 | head -12
for f in "$d"/*.stderr.log; do [ -f "$f" ] && { echo "== ${f##*/}"; tail -c 600 "$f"; echo; }; done
