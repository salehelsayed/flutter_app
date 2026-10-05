#!/bin/bash
# Probe: run a trivial Maestro flow on one simulator (detached, 400 s), log to r81.out; also list XCTest/driver
# processes and listeners on Maestro's iOS driver ports for that simulator.
if [ -z "${R81_DETACHED:-}" ]; then R81_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 & echo "started"; exit 0; fi
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:$PATH"; export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000 MAESTRO_CLI_NO_ANALYTICS=1
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r81.out
{ echo "start $(date -u +%T) device $1"
  echo "--- xctest/driver processes before:"; ps -axo pid=,etime=,command= | grep -i -E "xctrunner|maestro-driver|WebDriverAgent|XCTRunner|devicehub" | grep -v grep | cut -c1-160
  echo "--- listeners 22087-22100:"; lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '$9 ~ /:220[89][0-9]$|:2210[0-9]$/' | head
  s=$(date +%s); timeout 400 maestro --device "$1" test /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave3/flows/hello_ios.yaml 2>&1 | tail -12
  echo "maestro rc=${PIPESTATUS[0]} seconds=$(( $(date +%s)-s ))"
} > "$OUT" 2>&1
