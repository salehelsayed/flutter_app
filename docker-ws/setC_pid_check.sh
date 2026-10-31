#!/bin/bash
# Show whether the given Mac PIDs are still alive (ps only, kills nothing).
for p in "$@"; do ps -o pid=,etime=,args= -p "$p" | cut -c1-120 || echo "$p gone"; done
