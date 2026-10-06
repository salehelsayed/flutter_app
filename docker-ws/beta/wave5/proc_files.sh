#!/bin/bash
# Read-only: cwd and lock/pipe-ish open files of the given pids.
for p in "$@"; do echo "== $p"; lsof -p "$p" 2>/dev/null | awk '$4=="cwd" || /lock|\.lock|hooks|FIFO|PIPE/' | cut -c1-200 | head -15; done
