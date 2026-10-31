#!/bin/bash
# Re-sign an APK with the standard Android debug key so it installs over a debug-signed build (keeps app data).
#   host-run bash docker-ws/resign_apk_debug_key.sh <in.apk> <out.apk>
set -uo pipefail
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
"$BT/zipalign" -f -p 4 "$1" "$2.aligned" || exit 3
"$BT/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android --ks-key-alias androiddebugkey \
  --key-pass pass:android --out "$2" "$2.aligned" || exit 4
rm -f "$2.aligned" "$2.idsig"
"$BT/apksigner" verify "$2" && echo "VERIFIED $(shasum -a 256 "$2" | cut -d' ' -f1)"
