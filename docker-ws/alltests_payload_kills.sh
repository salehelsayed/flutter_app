#!/bin/bash
# Read-only: receiver (emulator) app kill/start lines around the B13 failures, from the newest payload proof logcat.
f=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.android_payload_campaign/device-logcat.txt
ls -la "$f" | awk '{print $6,$7,$8}'
grep -E "^09-26 13:(19|2[0-2]):" "$f" | grep -E "Killing [0-9]+:com.mknoon.app|Start proc [0-9]+:com.mknoon.app" | cut -c1-170
