#!/bin/bash
# Print the introduction FLOW events (event name + status fields) for one introduction id prefix from a device's logcat.
#   setA_intro_events.sh <serial> <intro-id-prefix>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
{ if [ -f "$1" ]; then cat "$1"; else adb -s "$1" logcat -d; fi; } | grep -F "$2" | grep -oE '"ts":"[^"]*"|"event":"[A-Z_]*"|"(action|overallStatus|newOverall|status|recipientStatus|introducedStatus)":"[a-z_]*"' \
  | paste -sd' ' | sed 's/"ts":/\n/g' | sed 's/"event"://; s/"//g' | grep -vE 'DB_(LOAD|INSERT|UPDATE)_.*START|REPO_.*START' | cut -c12-200
