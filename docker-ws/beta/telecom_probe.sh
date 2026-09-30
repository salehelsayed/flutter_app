#!/bin/bash
# Read-only: Android Telecom calls / audio sessions owned by the app.
. "$(dirname "$0")/beta_env.sh"
echo "now: $(date '+%H:%M:%S')  app pid: $($ADB shell pidof $PKG)"
$ADB shell dumpsys telecom 2>/dev/null | grep -nE "Call id=|state=|CommSess|mknoon|Active calls|numCalls|mCalls" | grep -iE "mknoon|CommSess|state=(ACTIVE|RINGING|DIALING|CONNECTING|ON_HOLD|DISCONNECT)|Call id" | head -20
echo "--- audio mode"; $ADB shell dumpsys audio 2>/dev/null | grep -E "^  ?mode|Audio mode|mMode|communication" | head -6
