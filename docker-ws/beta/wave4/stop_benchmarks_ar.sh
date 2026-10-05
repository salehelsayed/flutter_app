#!/bin/bash
# Stop this session's A/R benchmark run: the suite, its test peer, and every flutter_tools process running
# integration_test/benchmark_harness.dart (including orphans with ppid 1), then shut the simulator down.
kill_tree() { for c in $(pgrep -P "$1"); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
for p in $(pgrep -f "run_benchmark_suite.dart -d 674DFFF6"); do kill_tree "$p"; done
for p in $(pgrep -f "run_benchmarks_ar.sh"); do kill_tree "$p"; done
for p in $(pgrep -f "flutter_tools.*integration_test/benchmark_harness.dart"); do kill_tree "$p"; done
pkill -f "go-mknoon/bin/testpeer" 2>/dev/null
sleep 2
for p in $(pgrep -f "flutter_tools.*integration_test/benchmark_harness.dart"); do kill -9 "$p" 2>/dev/null; done
xcrun simctl shutdown 674DFFF6-5F38-4235-93F6-AF7FBF86AE65 2>/dev/null
sleep 1; pgrep -fl "run_benchmark_suite|bin/testpeer|benchmark_harness.dart" | cut -c1-120 || true
echo "stopped"
