#!/bin/bash
# Print lines after line <n> of a capture file that match <ERE> (Mac side).   host-run bash docker-ws/calls28_tail_from.sh <file-in-repo> <n> <ERE>
REPO="$(cd "$(dirname "$0")/.." && pwd)"
tail -n +"$(( ${2:-0} + 1 ))" "$REPO/$1" | grep -E "$3" | cut -c1-300
