#!/bin/bash
# Read-only: signing authority and entitlement keys of a built simulator app.
#   host-run bash docker-ws/sim_app_entitlements.sh <path to Runner.app>
codesign -dv "${1:?app}" 2>&1 | grep -E 'Signature|Authority|TeamIdentifier' | head -4
codesign -d --entitlements :- "$1" 2>/dev/null | grep -oE '<key>[^<]+</key>' | head -12
