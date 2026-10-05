#!/bin/bash
# Read-only: pid, ppid, cpu, elapsed and the tail of the command for the given pids.
for p in "$@"; do ps -o pid=,ppid=,%cpu=,etime= -p "$p" | tr '\n' ' '; ps -o command= -p "$p" | rev | cut -c1-160 | rev; done
