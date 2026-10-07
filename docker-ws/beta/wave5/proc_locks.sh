#!/bin/bash
# Read-only: lock/lease/socket files a pid holds or waits on.
lsof -p "$1" 2>/dev/null | grep -iE "lock|lease|\.sock|FIFO|PIPE|TCP" | cut -c1-200 | head -15
