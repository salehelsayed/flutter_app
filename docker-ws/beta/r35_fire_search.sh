#!/bin/bash
# Read-only: which pod/plugin code touches FIRApp/Messaging at load time (before didFinishLaunching).
P=/Volumes/CrucialX9/flutter_app-r2val/ios/Pods
PC=$HOME/.pub-cache/hosted/pub.dev
echo "== pods with +load / __attribute__((constructor)):"
grep -rlE '\+ ?\(void\)load|__attribute__\(\(constructor' "$P/FirebaseMessaging" "$P/FirebaseCore" "$P/FirebaseInstallations" "$P/GoogleUtilities" "$P/FirebaseCoreInternal" 2>/dev/null | head -20
echo "== FlutterFire plugin versions in the lockfile:"
grep -A2 -E '^  firebase_(core|messaging)' /Volumes/CrucialX9/flutter_app/pubspec.lock | grep -E 'firebase_|version' | head
for d in $(ls -d $PC/firebase_messaging-* $PC/firebase_core-* 2>/dev/null); do
  hits=$(grep -rnE '\+ ?\(void\)load|defaultApp|\[FIRApp |FIRMessaging messaging|Messaging\.messaging|__attribute__\(\(constructor' "$d/ios" 2>/dev/null | head -12)
  [ -n "$hits" ] && { echo "== $d"; echo "$hits" | cut -c1-220; }
done
echo "== Messaging +load:"; grep -rnE -A12 '\+ ?\(void\)load' "$P/FirebaseMessaging" 2>/dev/null | head -40 | cut -c1-200
