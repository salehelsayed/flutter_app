#!/bin/bash
# List (or stop with "stop") the Mac processes this beta session may have left: log captures,
# the private Appium server on 4725, and detached docker-ws/beta jobs.
PAT='idevicesyslog|appium.*4725|docker-ws/beta/r[0-9]+_|docker-ws/beta/run_r[0-9]+'
ps -axo pid,etime,command | grep -E "$PAT" | grep -v -e grep -e r48_my_mac_procs | cut -c1-180
if [ "$1" = stop ]; then
  ps -axo pid,command | grep -E "$PAT" | grep -v -e grep -e r48_my_mac_procs | awk '{print $1}' | xargs -r kill 2>/dev/null
  sleep 2; echo "after:"; ps -axo pid,command | grep -E "$PAT" | grep -v -e grep -e r48_my_mac_procs | cut -c1-180
fi
echo "R48 DONE"
