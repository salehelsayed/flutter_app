#!/bin/bash
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios/ios-p269-* | head -1)
grep -n -A2 "Pressing Home button" "$d/xcodebuild-test.log" | cut -c1-200 | head -8
grep -oE "App state after Home: [0-9]+" "$d/xcodebuild-test.log" | head -2
