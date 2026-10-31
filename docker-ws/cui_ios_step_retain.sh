#!/bin/bash
# cui_ios_step.sh with MKNOON_IOS_RETAIN_PAYLOAD_TAP_XCRESULT=1 (keep the payload-tap xcresult for diagnosis).
#   host-run bash docker-ws/cui_ios_step_retain.sh <log-relative-to-worktree> -- <command...>
export MKNOON_IOS_RETAIN_PAYLOAD_TAP_XCRESULT=1
exec bash "$(dirname "$0")/cui_ios_step.sh" "$@"
