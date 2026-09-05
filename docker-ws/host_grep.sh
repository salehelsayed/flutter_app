#!/bin/bash
# Grep any file ON THE MAC (the container's view of the shared checkout lags).
# Usage: docker-ws/host_grep.sh <file> <extended-regex> [<max lines>] [<width>]
FILE="${1:?file}"; PATTERN="${2:?pattern}"; MAX="${3:-40}"; WIDTH="${4:-240}"
echo "now: $(date -u +%H:%M:%SZ) file: $FILE ($(wc -l < "$FILE" | tr -d ' ') lines)"
grep -E "$PATTERN" "$FILE" | head -n "$MAX" | cut -c1-"$WIDTH"
