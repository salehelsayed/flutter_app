#!/bin/bash
# Read-only: flutter/xcodebuild/simctl processes whose cwd is the worktree, with ppid, cpu and elapsed time.
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
for p in $(pgrep -f "flutter_tools|xcodebuild|simctl|integration_test|flutter_tester|iproxy|idevice"); do
  cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in ("$WT"*) echo "$(ps -o pid=,ppid=,pcpu=,etime= -p $p) $(ps -o command= -p $p | grep -oE 'flutter_tools.snapshot [a-z]+[^/]{0,80}|xcodebuild [a-z-]+|simctl [a-z]+ [^ ]+' | head -1)";; esac
done | head -12
