#!/bin/bash
# Read-only: list host processes for xcodebuild, devicectl, idevicesyslog, mknoon_checks or sims.dart (pid, etime, args cut).
#   host-run bash docker-ws/host_find_test_procs.sh
ps -axo pid=,etime=,args= | grep -E 'xcodebuild|devicectl|idevicesyslog|mknoon_checks|sims\.dart' | grep -v grep | cut -c1-180
exit 0
