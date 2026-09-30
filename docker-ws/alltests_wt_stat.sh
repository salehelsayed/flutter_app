#!/bin/bash
# Read-only: mtimes of worktree build outputs and current process children of a pid (twice, 5 s apart).
wt=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree; date
ls -ld "$wt/build/ios/iphoneos/Runner.app" "$wt/build/app/outputs/flutter-apk" 2>&1 | awk '{print $6,$7,$8,$9}'
for i in 1 2 3; do pgrep -P "$1" | while read c; do ps -o pid=,etime=,command= -p $c | cut -c1-160; done; sleep 5; done
