#!/bin/bash
# Read-only one-line Mac status: is the release test run still going?
# Prints: BUSY|IDLE load1 load5 memfree% tests=<n> sims=<n> lanes=<script names>
read -r _ l1 l5 _ < <(sysctl -n vm.loadavg | tr -d '{}')
free=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {print $2}' | tr -d '%')
tests=$(ps -axo command | grep -cE "flutter_tester|dartvm .*(test|flutter_tools.snapshot test)|xcodebuild .*test|GradleWorkerMain|Gradle Test Executor" )
sims=$(xcrun simctl list devices booted 2>/dev/null | grep -c Booted)
lanes=$(ps -axo command | grep -oE "(run_[a-z_0-9]+|[a-z_]*lane[a-z_]*|release[a-z_]*)\.(sh|py)" | grep -vE "run_fixed|run_flow|beta|release_busy|run_claude_docker" | sort -u | tr '\n' ',' )
state=BUSY
if [ "${l1%.*}" -lt 20 ] && [ "${tests:-0}" -le 2 ] && [ -z "$lanes" ]; then state=IDLE; fi
echo "$state load1=$l1 load5=$l5 memfree=${free}% tests=$tests sims=$sims lanes=${lanes:-none}"
