#!/bin/bash
# Read-only: open files (no sockets) of one pid, trimmed.
lsof -n -p "$1" 2>/dev/null | grep -v -E "\.dylib|\.so|/System/|txt " | tail -25 | cut -c1-200
