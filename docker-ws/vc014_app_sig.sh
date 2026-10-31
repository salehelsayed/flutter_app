#!/bin/bash
# VC-014 read-only: signing identity, profile name and aps-environment of a Runner.app.   vc014_app_sig.sh <Runner.app>
A="$1"; codesign -dv "$A" 2>&1 | grep -E 'Authority=Apple|TeamIdentifier|Timestamp|Signed Time' | head -3
security cms -D -i "$A/embedded.mobileprovision" 2>/dev/null | plutil -extract Name raw - 2>/dev/null
codesign -d --entitlements - --xml "$A" 2>/dev/null | plutil -extract aps-environment raw - 2>/dev/null
ls "$A/Frameworks" | grep -i -E 'mknoon|gomk' ; codesign --verify --deep --strict "$A" && echo verify-ok
