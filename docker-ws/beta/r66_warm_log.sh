#!/bin/bash
# Read the warm-build verbose log on the Mac (the container view of growing files lags).
L=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_warm_ios_sim.verbose.log
echo "lines: $(wc -l < $L 2>/dev/null)"; tail -${1:-12} "$L" 2>/dev/null | cut -c1-220
