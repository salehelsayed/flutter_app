#!/bin/bash
# Read-only: print versionCode/versionName of an APK (aapt2 badging), or the signer SHA-256 of a jar-signed file such as an AAB (keytool -printcert -jarfile).
#   host-run bash docker-ws/apk_badging_and_jarcert.sh badging <apk>
#   host-run bash docker-ws/apk_badging_and_jarcert.sh jarcert <aab>
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
case "$1" in
  badging) "$BT/aapt2" dump badging "$2" 2>/dev/null | head -1 ;;
  jarcert) KT=$(/usr/libexec/java_home 2>/dev/null)/bin/keytool; [ -x "$KT" ] || KT=keytool; "$KT" -printcert -jarfile "$2" 2>&1 | grep -E "SHA256:" | head -1 ;;
esac
exit 0
