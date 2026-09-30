#!/bin/bash
# Read-only: the app's LOCAL_MDNS event counts over the last N seconds (default 60).
. "$(dirname "$0")/beta_env.sh"
xcrun simctl spawn "$UDID" log show --last "${1:-60}s" --predicate 'process == "Runner"' --style compact > /tmp/r22_rate.txt 2>&1
echo "lines $(wc -l < /tmp/r22_rate.txt)"
grep -o '"event":"LOCAL_MDNS_[A-Z_]*"' /tmp/r22_rate.txt | sort | uniq -c | sort -rn
grep -o '"event":"LOCAL_MDNS_PEER_FOUND".*' /tmp/r22_rate.txt | grep -o '"port":[0-9]*' | sort | uniq -c | sort -k2 | tr '\n' ' '; echo
