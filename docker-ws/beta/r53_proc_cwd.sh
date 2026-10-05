#!/bin/bash
# Read-only: working directory and start time of the given PIDs.
for p in "$@"; do echo "$p cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p') start=$(ps -o lstart= -p $p)"; done
