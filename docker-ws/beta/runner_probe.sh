#!/bin/bash
# Read-only: is the release test driver still alive, and what are its children?
ps -axo pid,ppid,etime,pcpu,command | grep -E "legacy_target_contracts|run_[a-z0-9_]+\.sh|flutter test|xcodebuild" | grep -v grep | cut -c1-170 | head -12
sysctl -n vm.swapusage
