#!/bin/bash
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios/ios-p269-* | head -1)
grep -hE "App state after Home|error:|phase_a_ready|Pressing Home|springboard|Wait for com.apple.springboard" "$d/xcodebuild-test.log" | cut -c1-240 | head -10
