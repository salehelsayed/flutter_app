#!/bin/bash
# Transcription replay: two DEBUG Pixel APKs (Hetzner, TRANSLATE_PREVIEW + TRANSLATE_PREVIEW_DIAG) from build/wt-translate-129:
# <before sha> as <bn1>, <after sha> as <bn2>. Each APK is copied to <evidence>/apk/debug-<bn>.apk. Run under the native-build lease.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/transcribe_diag_debug_apks.sh <evidence> <before sha> <bn1> <after sha> <bn2>
set -uo pipefail
EV=${1:?evidence}; B=${2:?before}; BN1=${3:?bn1}; A=${4:?after}; BN2=${5:?bn2}
REPO=/Volumes/CrucialX9/flutter_app; W=$REPO/build/wt-translate-129; E="$REPO/$EV"; mkdir -p "$E/apk"
D="--dart-define=TRANSLATE_PREVIEW=true --dart-define=TRANSLATE_PREVIEW_DIAG=true"
one() {
  local sha=$1 bn=$2
  cd "$W" || exit 2
  git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --porcelain --untracked-files=no; echo "STOP tree dirty"; exit 3; }
  git checkout --detach "$sha" 2>&1 | tail -1; echo "== $bn head=$(git rev-parse --short HEAD) $(date -u +%T)"
  bash "$REPO/docker-ws/wt_checks.sh" wt-translate-129 > "$E/wt_checks_$bn.log" 2>&1; echo "wt_checks exit=$?"; grep -E "errors=|warnings=" "$E/wt_checks_$bn.log"
  bash "$REPO/docker-ws/build_debug_apk_hetzner_wt.sh" wt-translate-129 "$EV/debug_apk_$bn.log" "$bn" "$D"; echo "debug apk exit=$?"
  local apk=$W/build/app/outputs/flutter-apk/app-debug.apk
  cp -p "$apk" "$E/apk/debug-$bn.apk" && echo "APK $EV/apk/debug-$bn.apk sha256=$(shasum -a 256 "$E/apk/debug-$bn.apk" | cut -c1-64)"
}
one "$B" "$BN1"
one "$A" "$BN2"
echo "done $(date -u +%T)"
