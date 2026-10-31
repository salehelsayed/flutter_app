#!/bin/bash
# Read-only: deeper frames of the worker threads of a sleeping process.
sample "${1:?pid}" 1 2>/dev/null | sed -n "/ThreadPoolExecutor/,/Thread_/p" | grep -vE "^\s*$" | sed -E "s/ +\[0x[0-9a-f]+\]//" | head -40
