#!/bin/bash
# Read-only: what run_b8.sh is doing right now, and the top CPU users.
ps -axo pid,ppid,etime,pcpu,command | grep -E "run_b8|adb .*(install|shell)|maestro|gradle|GradleDaemon|kotlin-daemon|java .*gradle" | grep -v grep | cut -c1-170 | head -14
echo "--- top CPU"
ps -Aceo pcpu,pid,etime,comm -r | head -10
