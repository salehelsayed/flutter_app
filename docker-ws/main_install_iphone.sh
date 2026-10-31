#!/bin/bash
# Install the built Runner.app from a worktree on ONE iPhone (11 or 13) WITHOUT uninstalling (data kept), then launch and verify bundleVersion.
#   host-run bash docker-ws/main_install_iphone.sh <worktree> <11|13>
W="${1:?worktree}"
case "${2:?phone}" in 11) U=00008030-001A6D2801BB802E ;; 13) U=00008110-00184D622289801E ;; *) echo "refused phone"; exit 2 ;; esac
cd "$W" || exit 2
IPHONE_UDIDS=$U bash docker-ws/install_iphones_keep_identity.sh
