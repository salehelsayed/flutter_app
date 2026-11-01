#!/bin/bash
# One leased run for a Codex-UI iOS RED: config-only setup in the worktree (Go bindings + pod install), then the given
# IosNotificationRecoveryTests methods on a simulator (codexui_notif_red_test.sh). Plist must already be staged by path.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/codexui_red_full.sh <worktree> <sim name> <evidence dir under repo> <method>...
set -uo pipefail
W=${1:?worktree}; NAME=${2:?sim}; EV=${3:?evidence}; shift 3
REPO=/Volumes/CrucialX9/flutter_app
bash "$REPO/docker-ws/codexui_ios_setup.sh" "$W" "$EV/setup.log"
bash "$REPO/docker-ws/codexui_notif_red_test.sh" "$W" "$NAME" "$EV/xcodebuild_test.log" "$@"
