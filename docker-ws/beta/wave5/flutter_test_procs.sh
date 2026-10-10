#!/bin/bash
# Read-only: running flutter test / flutter_tester processes and the SDK lock holder.
ps -axo pid,ppid,etime,command | grep -E 'flutter_tools.snapshot test|flutter_tester|flutter_sdk.sh' | grep -v grep | cut -c1-200
lsof $HOME/development/flutter-3.47.2/bin/cache/lockfile 2>/dev/null | tail -n +2 | cut -c1-120
