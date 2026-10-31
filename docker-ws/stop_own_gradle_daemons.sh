#!/bin/bash
# Stop a Gradle daemon and its Kotlin daemon by exact PIDs after a name and args check.
#   host-run bash docker-ws/stop_own_gradle_daemons.sh <gradle-pid> <kotlin-pid>
for PID in "$@"; do
  [[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused $PID"; continue; }
  ARGS="$(ps -o args= -p "$PID")"
  case "$ARGS" in *java*GradleDaemon*|*java*KotlinCompileDaemon*) kill "$PID" && echo "TERM $PID";; *) echo "refused $PID: not a gradle/kotlin daemon";; esac
done
