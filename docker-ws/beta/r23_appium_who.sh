#!/bin/bash
# Read-only: active Appium sessions on this Mac (who else drives the beta devices).
for port in 4723 4724 18932; do
  echo "=== port $port"
  curl -s -m 5 "http://127.0.0.1:$port/status" | head -c 300; echo
  curl -s -m 5 "http://127.0.0.1:$port/appium/sessions" | head -c 1500; echo
done
echo "=== appium processes"
ps -axo pid,ppid,etime,command | grep -i appium | grep -v grep | cut -c1-220
