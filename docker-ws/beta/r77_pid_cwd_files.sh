#!/bin/bash
# Read-only: cwd and open regular files of one pid.
lsof -p "$1" 2>/dev/null | awk '$4=="cwd" || $5=="REG"' | awk '{print $4, $NF}' | grep -v -E "dyld|icudt|\.snapshot$" | head -8
