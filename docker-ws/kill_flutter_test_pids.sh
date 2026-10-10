#!/bin/bash
# Kills only the given PIDs, and only if they are flutter test processes.
for pid in "$@"; do
  if ps -o command= -p "$pid" | grep -qE 'flutter_tools.snapshot test|flutter_tester|dart-sdk/bin/dart'; then
    kill "$pid" && echo "killed $pid"
  else
    echo "skip $pid (not a flutter test process)"
  fi
done
