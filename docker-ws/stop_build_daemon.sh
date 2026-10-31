#!/bin/bash
# Stop one idle Gradle or Kotlin daemon by exact PID after checking its command line.
P="${1:?pid}"; A="$(ps -o command= -p "$P" 2>/dev/null)"
case "$A" in *GradleDaemon*|*KotlinCompileDaemon*|*kotlin-daemon*|*org.gradle.launcher.daemon*) kill "$P" && echo "stopped $P";; *) echo "refused $P: not a gradle/kotlin daemon";; esac
