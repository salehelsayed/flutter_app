#!/bin/bash
# Kill stray idevicesyslog / devicectl --console capture processes on the Mac.
# Orphaned captures hold the libimobiledevice syslog relay, so a later capture
# connects but receives nothing (observed 2026-08-21).
echo "before:"; pgrep -fl 'idevicesyslog' || echo "  (none)"
pkill -f 'idevicesyslog' 2>/dev/null
sleep 2
echo "after:"; pgrep -fl 'idevicesyslog' || echo "  (none)"
