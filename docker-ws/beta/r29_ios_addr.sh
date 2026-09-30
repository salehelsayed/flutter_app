#!/bin/bash
# Read-only: the iPhone app's relay address lists ([ADDR] circuit addresses) logged between two local times.
. "$(dirname "$0")/beta_env.sh"
xcrun simctl spawn "$UDID" log show --style compact --start "$1" --end "$2" --predicate 'process == "Runner"' 2>/dev/null \
  | grep 'circuit addresses' | sed -E 's#/p2p/12D3KooW[A-Za-z0-9]+#/p2p/<relay>#g' | cut -c1-420 | tail -3
