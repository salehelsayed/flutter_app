#!/bin/bash
# Stop one Gradle or Kotlin compile daemon by exact PID, only if its command line is that daemon. No pattern kills.
#   host-run bash docker-ws/stop_gradle_daemon_pid.sh <pid>...
for P in "$@"; do
  [[ "$P" =~ ^[0-9]+$ ]] || { echo "refused $P: not a number"; continue; }
  A=$(ps -o args= -p "$P" 2>/dev/null)
  case "$A" in
    *GradleDaemon*|*gradle-launcher*|*KotlinCompileDaemon*|*kotlin-daemon*|*org.jetbrains.kotlin*) kill "$P" && echo "TERM $P: $(echo "$A" | cut -c1-90)";;
    "") echo "gone $P";;
    *) echo "refused $P: not a Gradle/Kotlin daemon";;
  esac
done
sleep 3; for P in "$@"; do ps -p "$P" >/dev/null 2>&1 && echo "still running $P" || echo "stopped $P"; done
