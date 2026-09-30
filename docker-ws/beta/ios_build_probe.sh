#!/bin/bash
# Read-only: is the isolated copy still the exact source of the installed Android APK
# (sync 00:05Z + patch 362d930e2), and does it have what an iOS simulator build needs?
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
cd "$DST" || { echo "no copy"; exit 2; }
echo "--- provenance"; cat .proof-checkout-provenance.txt
echo "--- patch markers (want 1+ each)"
grep -c CALL_INCOMING_SIGNAL_NOT_ACCEPTED lib/features/call/application/handle_incoming_call_signal.dart
grep -c MAX_CALLER_EXPIRY_AHEAD_MS android/app/src/main/kotlin/com/mknoon/app/call/CallPayloadParser.kt
grep -c foregroundOwnsRuntime android/app/src/main/kotlin/com/mknoon/app/call/HeadlessCallAdmissionWorker.kt
echo "--- files in the copy newer than the Android APK (want none outside build dirs)"
find lib android/app/src ios/Runner -newer "$SRC/artifacts/beta-20260925/build/beta-android.apk" -type f 2>/dev/null | head -10
echo "--- iOS Go framework"
find ios -maxdepth 3 \( -name "*.xcframework" -o -name "GoMknoon*" \) 2>/dev/null | head -10
echo "--- defines file same as live checkout?"
cmp tool/build/voice_call_release_defines.json "$SRC/tool/build/voice_call_release_defines.json" && echo "same"
echo "--- frameworks in the working c8be267bd nock app"
ls "$SRC/artifacts/beta-20260925/build/Runner-nock.app/Frameworks" | head -40
echo "--- last iOS build log tail"
tail -5 "$SRC/artifacts/beta-20260925/build/ios_nock_build.log"
