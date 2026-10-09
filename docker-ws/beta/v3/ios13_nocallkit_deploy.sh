#!/bin/bash
# O1 check (2026-10-08): the build_ios_flowlog.sh build with native iOS calls OFF (no CallKit/PushKit, in-app call
# screen), installed on the iPhone 13 only with its data kept. Restore the normal build with ios13_deploy.sh.
set -uo pipefail
cd /Volumes/CrucialX9/flutter_app || exit 1
. docker-ws/_flutter_sdk_env.sh
OUT=docker-ws/beta/v3/ios13_nocallkit_deploy.out
{
  echo "=== start $(date -u +%FT%TZ)"
  DEF=$(mktemp -t nock).json
  /usr/bin/python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); d["VOICE_CALL_IOS_NATIVE_ENABLED"]="false"
json.dump(d, open(sys.argv[2],"w"))' tool/build/voice_call_release_defines.json "$DEF"
  echo "defines: $(cat "$DEF")"
  STAMP=$(date +%y%m%d%H%M%S)
  BUILD_NAME="1.0.0-$(git rev-parse --short HEAD).nock.flowlog.t${STAMP}"
  scripts/ensure_go_ios_bindings.sh || { echo "V3 NOCK FAILED(go bindings)"; exit 1; }
  flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
      --dart-define-from-file="$DEF" --dart-define=FDC_FLOW_LOG=1 \
      --build-name="$BUILD_NAME" --build-number="$STAMP" || { echo "V3 NOCK FAILED(build)"; exit 1; }
  echo "V3 NOCK BUILT $BUILD_NAME bundleVersion=$STAMP"
  IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh
  echo "V3 NOCK EXIT $?"
} > "$OUT" 2>&1
tail -6 "$OUT"
