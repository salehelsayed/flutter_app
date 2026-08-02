#!/usr/bin/env bash
# Plan 321: register an iPhone UDID into the team's automatic dev provisioning
# profile (fixes install error 0xe8008012 "profile cannot be installed on this
# device") by building against that destination with provisioning updates
# allowed. Requires the Mac's Xcode Apple-ID session (already dev-signing).
set -uo pipefail
cd "$(dirname "$0")/../.."
UDID="${1:?usage: register_ios_device_321.sh <udid>}"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "id=$UDID" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build 2>&1 | tail -12
exit "${PIPESTATUS[0]}"
