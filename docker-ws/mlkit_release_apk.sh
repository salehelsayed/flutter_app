#!/bin/bash
# Production release APK (shrunk) from a worktree with an overridden build number; stages and removes the release keystore.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/mlkit_release_apk.sh <worktree> <build-number>
set -uo pipefail
W="$1"; BN="$2"; EXTRA="${3:-}"  # optional extra --dart-define, e.g. FDC_FLOW_LOG=1
SRC=/Volumes/CrucialX9/flutter_app/android/app/upload-keystore.jks
DST="$W/android/app/upload-keystore.jks"
cd "$W" || exit 2
KSRC=/Volumes/CrucialX9/flutter_app/android/key.properties
KDST="$W/android/key.properties"
STAGED=0; KSTAGED=0
if [ ! -e "$DST" ]; then cp "$SRC" "$DST" && STAGED=1; fi
if [ ! -e "$KDST" ]; then cp "$KSRC" "$KDST" && KSTAGED=1; fi
cleanup() {
  [ "$STAGED" = 1 ] && cmp -s "$SRC" "$DST" && rm -f "$DST" && echo "keystore removed"
  [ "$KSTAGED" = 1 ] && cmp -s "$KSRC" "$KDST" && rm -f "$KDST" && echo "key.properties removed"
}
trap cleanup EXIT
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
echo "== provenance $(date -u +%H:%M:%SZ) head=$(git rev-parse HEAD) pubspec=$VERSION build_number=$BN extra=$EXTRA"
python3 scripts/check_update_check_release_defines.py \
  --dart-define-from-file=tool/build/voice_call_release_defines.json || { echo "RELEASE_GUARD FAILED"; exit 3; }
echo "== ensure_go_android_bindings $(date -u +%H:%M:%SZ)"
bash scripts/ensure_go_android_bindings.sh || { echo "GO_ANDROID_BINDINGS FAILED"; exit 4; }
MARK=$(mktemp)
APK=build/app/outputs/flutter-apk/app-release.apk
echo "== flutter build apk $(date -u +%H:%M:%SZ)"
flutter build apk --release --target=lib/main.dart \
  --build-name="${VERSION%%+*}" --build-number="$BN" \
  --dart-define-from-file=tool/build/voice_call_release_defines.json ${EXTRA:+--dart-define=$EXTRA} \
  --android-project-arg=enableAndroidNativeCalls=true
rc=$?
if [ $rc -ne 0 ]; then echo "BUILD FAILED rc=$rc"; exit $rc; fi
if [ ! "$APK" -nt "$MARK" ]; then echo "STALE APK"; exit 5; fi
echo "APK $W/$APK sha256=$(shasum -a 256 "$APK" | cut -d' ' -f1) size=$(du -m "$APK" | cut -f1)MB"
ls -la build/app/outputs/mapping/release/mapping.txt | awk '{print "MAPPING", $5, $NF}'
echo "== done $(date -u +%H:%M:%SZ)"
