#!/bin/bash
# Store release Android AAB only, for build/wt-release-<N> (same command as release_store_build_internal.sh's android step).
#   host-run bash docker-ws/release_store_aab.sh <N>
set -uo pipefail
N=${1:?build number}
W=/Volumes/CrucialX9/flutter_app/build/wt-release-$N; E="$W/.codex-test-logs/release-$N"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
DEF=tool/build/voice_call_release_defines.json
echo "== provenance $(date -u +%T) head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ') $(grep -E '^version:' pubspec.yaml)"
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=$DEF || { echo "RELEASE_GUARD FAILED"; exit 3; }
flutter build appbundle --release --target=lib/main.dart --dart-define-from-file=$DEF \
  --android-project-arg=enableAndroidNativeCalls=true > "$E/android_build.log" 2>&1; rc=$?; echo "android exit=$rc"
A=build/app/outputs/bundle/release/app-release.aab
[ -f "$A" ] && echo "aab=$W/$A sha256=$(shasum -a 256 "$A" | cut -c1-64) bytes=$(stat -f %z "$A")"
echo "aar_in_aab_go_runtime=$(unzip -l "$A" 2>/dev/null | grep -c 'libgojni.so')"
echo "== done $(date -u +%T)"; exit $rc
