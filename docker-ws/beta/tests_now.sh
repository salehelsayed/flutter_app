#!/bin/bash
# Read-only: which test processes are running right now, their working directories,
# and how long they have run. Used before changing the live checkout.
ps -axo pid,ppid,etime,command | grep -E "flutter_tester|dartvm .*(test|flutter_tools.snapshot test)|xcodebuild .*test|GradleWorkerMain|Gradle Test Executor|run_[a-z_0-9]+\.sh|gradlew" | grep -v grep | cut -c1-210
for p in $(ps -axo pid,command | grep -E "flutter_tester|dartvm .*test|GradleWorkerMain" | grep -v grep | awk '{print $1}'); do
  echo "cwd $p: $(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
done
