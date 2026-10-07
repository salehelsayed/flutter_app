#!/bin/bash
# Read-only: parentless (ppid 1) dart/flutter/gradle processes whose cwd is the wave3-next worktree.
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
for p in $(ps -axo pid=,ppid=,command= | awk '$2==1 && /dartvm|flutter|gradle|java/ {print $1}'); do
  cwd=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in ("$WT"*) echo "$p $(ps -o etime=,pcpu= -p $p) $(ps -o command= -p $p | grep -oE 'build (apk|ios|ipa)[^-]*|test |daemon|GradleDaemon|KotlinCompileDaemon' | head -1)";; esac
done
