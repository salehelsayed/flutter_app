#!/bin/bash
# Read-only: the full command line of each given pid (for finding a process's -destination / device).
for p in "$@"; do echo "== $p: $(ps -o command= -p "$p" 2>/dev/null)"; done
