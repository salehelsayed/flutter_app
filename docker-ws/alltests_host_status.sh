#!/bin/bash
# Read-only: live test/build/device processes and device lists for the all-tests run.
echo "== processes =="
ps ax -o pid=,ppid=,etime=,command= 2>/dev/null | grep -E "mknoon_checks|restart-checkpoint|source0[0-9][0-9]|sims|xcodebuild|flutter_tools|gradle|appium|emulator|mknoon-all-tests|run_test_gates|idevicesyslog|logcat" | grep -v -E "grep|alltests_host_status" | cut -c1-260 | head -60
echo "== adb =="; adb devices -l 2>&1 | head
echo "== simctl booted =="; xcrun simctl list devices booted 2>&1 | head -20
echo "== devicectl =="; xcrun devicectl list devices 2>&1 | head -10
echo "== docker =="; docker ps --format '{{.Names}} {{.Status}}' 2>&1 | head
echo "== worktree =="; git -C /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree status --short 2>&1 | wc -l; git -C /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree log -1 --format='%H %cd' 2>&1
echo "== disk =="; df -h /Volumes/CrucialX9 / 2>&1
