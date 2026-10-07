#!/bin/bash
# Stop leftover Go test peers and benchmark suite processes started from the wave3-next worktree.
for p in $(pgrep -f "go-mknoon/bin/testpeer|run_benchmark_suite.dart"); do kill -9 "$p" 2>/dev/null && echo "killed $p"; done
