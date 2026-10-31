#!/bin/bash
# Read-only: java/gradle/kotlin/dart/flutter/simulator processes with pid, start, rss MB, cwd and command head.
ps -axo pid=,lstart=,rss=,command= | grep -E "GradleDaemon|KotlinCompileDaemon|kotlin-daemon|dart(aotruntime|vm)? .*(analysis_server|language-server)|flutter_tools|CoreSimulator|launchd_sim|qemu-system" | grep -v grep | while read pid d1 d2 d3 d4 d5 rss rest; do c=$(lsof -a -p $pid -d cwd -Fn 2>/dev/null | sed -n "s/^n//p"); echo "$pid $d2 $d3 $d4 $((rss/1024))MB cwd=${c#/Volumes/CrucialX9/} :: $(echo $rest | cut -c1-90)"; done
