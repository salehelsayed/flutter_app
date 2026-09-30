#!/bin/bash
# Read-only: what the app's open files look like (types, DNS-SD sockets), to pick a leak counter.
. "$(dirname "$0")/beta_env.sh"
p=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk '/UIKitApplication:com.mknoon.app/ {print $1; exit}')
echo "pid $p"; lsof -p "$p" > /tmp/r22_lsof.txt 2>/dev/null
echo "total $(wc -l < /tmp/r22_lsof.txt)"; awk 'NR>1 {print $5}' /tmp/r22_lsof.txt | sort | uniq -c | sort -rn | head
echo "mdns lines: $(grep -ic mdns /tmp/r22_lsof.txt)"; grep -i unix /tmp/r22_lsof.txt | head -8
