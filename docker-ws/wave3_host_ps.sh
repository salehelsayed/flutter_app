#!/bin/bash
# Lists Mac-side campaign, Maestro and Appium processes and device leases.
ps -axo pid,ppid,etime,command | grep -E "mknoon_checks|run_production_|maestro|appium|dart.*integration_test|run_wave3|beta/" | grep -v grep | cut -c1-220
echo "== leases"
ls -la /tmp/mknoon-device-leases-$(id -u) 2>&1
for f in /tmp/mknoon-device-leases-$(id -u)/*; do [ -f "$f" ] && { echo "-- $f"; cat "$f"; echo; lsof "$f" 2>/dev/null | tail -n +2 | cut -c1-120; }; done
