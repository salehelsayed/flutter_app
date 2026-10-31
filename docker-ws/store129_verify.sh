#!/bin/bash
# Verify the 129 store artifacts in build/wt-translate-129: version, sha256, size, defines, URLs, relay, signer, entitlements.
# Prints counts and booleans only, never key values.
set -uo pipefail
N=${1:?build number}; W=/Volumes/CrucialX9/flutter_app/build/wt-translate-129
T=$(mktemp -d); E=/Volumes/CrucialX9/flutter_app/${2:?evidence dir under repo}; mkdir -p "$E"
cd "$W"
K1=$(sed -n "/updateCheckK1PublicKeyBase64 =/{n;s/.*'\(.*\)'.*/\1/p;}" lib/features/update_check/domain/update_check_keys.dart)
count() { LC_ALL=C grep -a -c -F -- "$1" "$2" 2>/dev/null || true; }
{
echo "== k1 length ${#K1}"
AAB=build/app/outputs/bundle/release/app-release.aab
if [ -f "$AAB" ]; then
  echo "== AAB $AAB size_bytes=$(stat -f %z "$AAB") sha256=$(shasum -a 256 "$AAB" | cut -d' ' -f1) mtime=$(stat -f %Sm -t %Y-%m-%dT%H:%M:%S "$AAB")"
  mkdir -p "$T/aab"; unzip -q -o "$AAB" 'base/lib/arm64-v8a/libapp.so' 'base/manifest/AndroidManifest.xml' 'base/dex/*' -d "$T/aab"
  MM=$(find build/app/intermediates -path '*release*' -name AndroidManifest.xml -path '*merged_manifest*' | head -1)
  echo "merged_manifest=$MM"; grep -o 'android:versionCode="[0-9]*"\|android:versionName="[^"]*"' "$MM" | sort -u
  echo "aab_manifest_has_1.0.1=$(count '1.0.1' "$T/aab/base/manifest/AndroidManifest.xml")"
  S=$T/aab/base/lib/arm64-v8a/libapp.so; strings -a "$S" > "$T/libapp.txt"
  echo "libapp update_url=$(count 'https://updates.mknoon.xyz/mknoon/version.json' "$T/libapp.txt")"
  echo "libapp play_url=$(count 'https://play.google.com/store/apps/details?id=com.mknoon.app' "$T/libapp.txt")"
  echo "libapp testflight_url=$(count 'https://testflight.apple.com/join/nUVjrEYS' "$T/libapp.txt")"
  echo "libapp k1=$(count "$K1" "$T/libapp.txt")"
  echo "libapp hetzner_relay=$(count '2-29-62-121.sslip.io' "$T/libapp.txt") aws_relay_host=$(count 'mknoun.xyz' "$T/libapp.txt") gemma_manifest=$(count 'models/gemma-translate.json' "$T/libapp.txt")"
  echo "libapp E2E_TEST_MODE=$(count 'E2E_TEST_MODE' "$T/libapp.txt") SE41_PREVIEW=$(count 'SE41_PREVIEW' "$T/libapp.txt")"
  echo "dex play_url=$(cat "$T"/aab/base/dex/*.dex | LC_ALL=C grep -a -c -F 'https://play.google.com/store/apps/details?id=com.mknoon.app')"
  echo "aab_signer=$(keytool -printcert -jarfile "$AAB" 2>/dev/null | sed -n 's/^Owner: //p' | head -1 | cut -c1-60)"
fi
IPA=$(find build/ios/ipa -maxdepth 1 -name '*.ipa' | head -1)
if [ -n "$IPA" ]; then
  echo "== IPA $IPA size_bytes=$(stat -f %z "$IPA") sha256=$(shasum -a 256 "$IPA" | cut -d' ' -f1) mtime=$(stat -f %Sm -t %Y-%m-%dT%H:%M:%S "$IPA")"
  mkdir -p "$T/ipa"; unzip -q -o "$IPA" -d "$T/ipa"; APP=$(find "$T/ipa/Payload" -maxdepth 1 -name '*.app' | head -1)
  for k in CFBundleShortVersionString CFBundleVersion CFBundleIdentifier; do echo "$k=$(/usr/libexec/PlistBuddy -c "Print :$k" "$APP/Info.plist")"; done
  A=$APP/Frameworks/App.framework/App; strings -a "$A" > "$T/app.txt"
  echo "App update_url=$(count 'https://updates.mknoon.xyz/mknoon/version.json' "$T/app.txt")"
  echo "App testflight_url=$(count 'https://testflight.apple.com/join/nUVjrEYS' "$T/app.txt")"
  echo "App apps.apple.com=$(count 'apps.apple.com' "$T/app.txt")"
  echo "Runner apps.apple.com=$(count 'apps.apple.com' "$APP/Runner")"
  echo "App k1=$(count "$K1" "$T/app.txt")"
  echo "App E2E_TEST_MODE=$(count 'E2E_TEST_MODE' "$T/app.txt") SE41_PREVIEW=$(count 'SE41_PREVIEW' "$T/app.txt")"
  echo "Runner go_runtime=$(count 'runtime.main' "$APP/Runner") go1=$(count 'go1.' "$APP/Runner") runner_bytes=$(stat -f %z "$APP/Runner")"
  codesign -d --entitlements :- "$APP" 2>/dev/null > "$T/ent.plist"
  for k in aps-environment com.apple.developer.kernel.increased-memory-limit get-task-allow beta-reports-active; do echo "ent $k=$(plutil -extract "$k" raw -o - "$T/ent.plist" 2>/dev/null)"; done
  echo "App hetzner_relay=$(count '2-29-62-121.sslip.io' "$T/app.txt") aws_relay_host=$(count 'mknoun.xyz' "$T/app.txt") gemma_manifest=$(count 'models/gemma-translate.json' "$T/app.txt")"
  echo "team=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p') authority=$(codesign -dv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  ls build/ios/archive/ 2>/dev/null
fi
} > "$E/verify.txt" 2>&1
rm -rf "$T"
cat "$E/verify.txt"
