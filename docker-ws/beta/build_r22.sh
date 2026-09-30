#!/bin/bash
# R2-2 validation build (2026-09-28): iOS simulator app only. Syncs the live working tree (main + uncommitted
# work, incl. the bonsoir_darwin resolve fix) into the isolated copy and builds it with the same settings as
# the earlier beta builds (debug + E2E_TEST_MODE, release voice-call defines with the in-app call UI).
# The live checkout is only read. Output: artifacts/beta-20260928/build-r2-2/{result.txt,Runner-nock.app,...}
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/build-r2-2"
OLD_APP="$SRC/artifacts/beta-20260928/build/Runner-nock.app"   # the build installed now (before the fix)
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
NEW_GO=closeUnresponsiveRelayConn                  # Go symbol: proves the Go binding is current
FIX_MARK=fr.skyost.bonsoir.discovery.resolve       # queue label added by the R2-2 fix; lands in the plugin binary
SW=third_party/bonsoir_darwin/darwin/Classes/Discovery/BonsoirServiceDiscovery.swift
mkdir -p "$OUT"
RESULT="$OUT/result.txt"; : > "$RESULT"
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$RESULT"; }
marker_count() { # marker_count <app dir> : files in the app that contain FIX_MARK
  LC_ALL=C grep -r -a -l "$FIX_MARK" "$1" 2>/dev/null | sed "s#^$1/##" | tr '\n' ' '
}

note "old installed build carries the fix marker in: [$(marker_count "$OLD_APP")] (expect empty)"
note "sync start"
PROOF_DST="$DST" PROOF_MAX_GB=8 bash "$SRC/docker-ws/prepare_proof_checkout_5556.sh" > "$OUT/prepare.log" 2>&1 \
  || { note "PREPARE FAILED (see prepare.log)"; exit 1; }
cd "$DST" || { note "NO COPY"; exit 2; }
cp .proof-checkout-provenance.txt "$OUT/provenance.txt"
note "synced: $(tr '\n' ' ' < .proof-checkout-provenance.txt)"
for m in "$SW:$FIX_MARK" "$SW:PendingResolution" "$SW:setCancelHandler" \
         "lib/features/groups/application/group_message_listener_system_transition_processor.dart:relaxTerminalPreTransitionHash"; do
  grep -q "${m##*:}" "${m%%:*}" || { note "FIX MARKER MISSING ${m##*:}"; exit 1; }
done
cmp -s "$SRC/$SW" "$DST/$SW" && note "fix file identical to the live tree (md5 $(md5 -q "$DST/$SW"))" \
  || { note "FIX FILE DIFFERS FROM THE LIVE TREE"; exit 1; }
grep -n "bonsoir_darwin" pubspec.yaml | head -3 >> "$RESULT"

STAMP=$(date +%y%m%d%H%M%S)
SHA=$(sed -n 's/^source_head_short=//p' .proof-checkout-provenance.txt)
DIRTY=$(sed -n 's/^source_dirty_files=//p' .proof-checkout-provenance.txt)
BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"
defines() {
  echo --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true
  /usr/bin/python3 -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items():
    if k=="VOICE_CALL_IOS_NATIVE_ENABLED": v="false"
    print(f"--dart-define={k}={v}")' "$SRC/tool/build/voice_call_release_defines.json"
}
defines > "$OUT/defines_ios.txt"

note "ios go bindings"
if ! bash scripts/ensure_go_ios_bindings.sh > "$OUT/ios_go_bindings.log" 2>&1; then
  note "IOS FAILED (go bindings, see ios_go_bindings.log)"
else
  note "ios build $BUILD_NAME (in-app call UI)"
  M=$(mktemp)
  if "$FLUTTER" build ios --simulator --debug -t lib/main.dart $(defines) \
      --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_build.log" 2>&1 \
     && [ build/ios/iphonesimulator/Runner.app/Info.plist -nt "$M" ]; then
    rm -rf "$OUT/Runner-nock.app"; cp -R build/ios/iphonesimulator/Runner.app "$OUT/Runner-nock.app"
    g=0; s=0
    for f in $(find "$OUT/Runner-nock.app" -type f \( -name Runner -o -name Runner.debug.dylib -o -name GoMknoon \)); do
      g=$(( g + $(LC_ALL=C grep -a -c runtime.goexit "$f") )); s=$(( s + $(LC_ALL=C grep -a -c "$NEW_GO" "$f") ))
    done
    note "IOS OK go_marker=$g go_new_symbol=$s bonsoir_fix_marker_in=[$(marker_count "$OUT/Runner-nock.app")]"
  else
    note "IOS FAILED (see ios_build.log)"
  fi
fi
note "$BUILD_NAME"
note "R22 BUILD DONE"
