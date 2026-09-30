#!/bin/bash
# Read-only: all open files/sockets (non-library) of a pid.
lsof -p "$1" 2>/dev/null | awk 'NR>1 && $5 !~ /^(DIR)$/ && $9 !~ /\.(dylib|so|dill|snapshot)$/ {print $4, $5, $9}' | grep -v "/System/\|/usr/lib" | head -30
