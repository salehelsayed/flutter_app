#!/bin/bash
# Read-only: stack-ish view of what a sleeping Python process waits on (sample 1s, top frames).
sample "${1:?pid}" 1 2>/dev/null | grep -E "flock|sleep|select|wait|lock|poll|read" | head -8
