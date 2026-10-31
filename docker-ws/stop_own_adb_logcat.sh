#!/bin/bash
# Stop one host 'adb ... logcat -v epoch' process by exact PID after an args check.
P="$1"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
A="$(ps -o args= -p "$P")"
case "$A" in "adb -s "*" logcat -v epoch") kill "$P" && echo "TERM $P";; *) echo "refused: $A";; esac
