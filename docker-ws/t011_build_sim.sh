#!/bin/bash
# TRANSFER-011: signed debug iOS simulator build in build/wt-t011 (cb02da5e9). Run under the native lease:
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/t011_build_sim.sh
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-t011; SHA=cb02da5e9640a93ad9e98548ff1bb384a2f3ae3f
cd "$W" || exit 2
[ "$(git rev-parse HEAD)" = "$SHA" ] || { echo "WT HEAD mismatch"; exit 2; }
. docker-ws/_flutter_sdk_env.sh
echo "=== go ios $(date -u +%FT%TZ)"; scripts/ensure_go_ios_bindings.sh || { echo "SIM FAILED(go bindings)"; exit 3; }
echo "=== sim build $(date -u +%FT%TZ)"
flutter build ios --simulator --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true || { echo "SIM FAILED(build)"; exit 4; }
APP=build/ios/iphonesimulator/Runner.app
echo "appgroups=$(codesign -d --entitlements - "$APP" 2>&1 | grep -c application-groups)"
shasum -a 256 "$APP/Runner.debug.dylib" "$APP/Runner" 2>/dev/null
echo "=== done $(date -u +%FT%TZ)"
