#!/bin/bash
# Read-only: is a given PID alive, and its command name.
ps -o pid=,pcpu=,comm= -p "${1:?pid}" 2>/dev/null || echo "pid ${1} gone"
