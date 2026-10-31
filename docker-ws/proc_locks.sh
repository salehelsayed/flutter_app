#!/bin/bash
# Read-only: open files of one process that look like locks, leases or fifos.
lsof -p "${1:?pid}" 2>/dev/null | grep -iE "lock|lease|fifo|PIPE|\.json" | awk "{print \$4, \$5, \$9}" | head -20
