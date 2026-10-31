#!/bin/bash
# Read-only: list processes whose command line mentions appium (pid, etime, args cut).
#   host-run bash docker-ws/host_find_appium.sh
ps -axo pid=,etime=,args= | grep -i appium | grep -v grep | cut -c1-200
exit 0
