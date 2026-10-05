#!/bin/bash
# Probe: which kill command works for an app process on an iOS simulator.  r88_sim_kill_probe.sh <udid>
U=$1
xcrun simctl launch "$U" com.apple.Preferences >/dev/null 2>&1; sleep 3
pid=$(xcrun simctl spawn "$U" launchctl list | awk '$3 ~ /^UIKitApplication:com.apple.Preferences\[/ {print $1}')
echo "pid=$pid"
xcrun simctl spawn "$U" kill -9 "$pid"; echo "spawn kill rc=$?"
xcrun simctl spawn "$U" /bin/kill -9 "$pid"; echo "spawn /bin/kill rc=$?"
ls "$(xcrun simctl getenv "$U" SIMULATOR_ROOT 2>/dev/null)/bin" 2>/dev/null | head; 
ps -p "$pid" -o pid,comm | tail -1; echo "host ps rc=$?"
kill -9 "$pid"; echo "host kill rc=$?"; sleep 1
xcrun simctl spawn "$U" launchctl list | awk '$3 ~ /Preferences/'; echo end
