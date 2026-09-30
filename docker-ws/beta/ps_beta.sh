#!/bin/bash
# Read-only: beta runner / maestro processes and Mac load.
ps -axo pid,etime,pcpu,command | grep -E "maestro|dump_ui|pair.sh|run_flow|run_fixed3|gradle|flutter_tester|dartvm" | grep -v grep | cut -c1-150 | head -14
echo "load: $(sysctl -n vm.loadavg)"
