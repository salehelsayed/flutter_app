#!/bin/bash
# Read-only: flutter processes running the benchmark harness, with ppid, cpu, elapsed and state.
for p in $(pgrep -f "integration_test/benchmark_harness.dart"); do
  echo "$(ps -o pid=,ppid=,%cpu=,etime=,state= -p "$p") $(ps -o command= -p "$p" | grep -o 'flutter_tools.snapshot [a-z]*' )"
done
echo "-- flutter lock holders:"; lsof "$HOME/development/flutter-3.47.2/bin/cache/lockfile" 2>/dev/null | tail -5
