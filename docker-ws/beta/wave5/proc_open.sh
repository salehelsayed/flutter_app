#!/bin/bash
# Read-only: regular files open by a pid, and its wait channel via sample of stack (short).
lsof -p "$1" 2>/dev/null | awk '$5=="REG"' | tail -8 | cut -c1-220
