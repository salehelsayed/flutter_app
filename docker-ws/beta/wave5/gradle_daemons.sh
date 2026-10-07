#!/bin/bash
# Read-only: Gradle and Kotlin daemons with cpu, cpu time, elapsed, and cwd.
for p in $(pgrep -f "GradleDaemon|KotlinCompileDaemon|GradleWorkerMain"); do
  echo "$(ps -o pid=,pcpu=,time=,etime= -p $p) $(ps -o command= -p $p | grep -oE 'GradleDaemon [0-9.]+|KotlinCompileDaemon|GradleWorkerMain' | head -1) cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | cut -c1-80)"
done
