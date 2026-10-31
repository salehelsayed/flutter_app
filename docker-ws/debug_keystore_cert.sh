#!/bin/bash
# Print SHA-256 cert fingerprint of the standard Android debug keystore (read-only).
KS="$HOME/.android/debug.keystore"
[ -f "$KS" ] || { echo "no debug keystore"; exit 1; }
keytool -list -v -keystore "$KS" -storepass android -alias androiddebugkey 2>/dev/null | grep -E 'SHA256:' | head -1
