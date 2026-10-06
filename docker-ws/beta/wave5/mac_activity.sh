#!/bin/bash
# Read-only: build/test/device-automation processes running on the Mac, plus load.
ps -axo pid,etime,pcpu,command | grep -E "flutter_tools|xcodebuild|gradle|sims.dart|mknoon_checks|maestro|run_host_test|queue.sh|appium" \
  | grep -v grep | cut -c1-180 | head -25
uptime
