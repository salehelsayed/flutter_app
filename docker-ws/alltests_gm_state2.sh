#!/bin/bash
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios/ios-p269-* | head -1)
grep -hoE "App state after Home: [0-9]+|Wait for com.apple.springboard[^\n]{0,80}|t = +[0-9.]+s +(Checking|Wait|Pressing|Tear)[^\n]{0,80}" "$d/xcodebuild-test.log" | sed -n '1,14p'
