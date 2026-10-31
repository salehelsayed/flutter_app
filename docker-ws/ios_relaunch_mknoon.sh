#!/bin/bash
# Relaunch Mknoon on ONE iPhone (11 or 13) with --terminate-existing. No install, no uninstall.
#   host-run bash docker-ws/ios_relaunch_mknoon.sh <11|13>
case "${1:?phone}" in 11) U=00008030-001A6D2801BB802E ;; 13) U=00008110-00184D622289801E ;; *) echo "refused phone"; exit 2 ;; esac
xcrun devicectl device process launch --device "$U" --terminate-existing com.mknoon.app 2>&1 | tail -2
