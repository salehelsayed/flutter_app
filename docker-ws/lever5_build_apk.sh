#!/bin/bash
# Build the H2 disposable debug APK com.mknoon.sims.lever5 (Google services off) in build/wt-lever5,
# pointed at the running H2 fixture relay read from its private state file. Shipping media lane (custody flag off).
#   host-run docker-ws/with_native_lease.py <log> -- bash <repo>/docker-ws/lever5_build_apk.sh <state.json>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; WT="$REPO/build/wt-lever5"; STATE="${1:?state}"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
RELAY="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["multiaddr"])' "$STATE")" || exit 2
for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/local.properties android/key.properties android/app/google-services.json .env; do
  [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
done
cd "$WT" || exit 3
"$SDK/bin/flutter" pub get --offline --enforce-lockfile || exit 4
"$SDK/bin/flutter" build apk --debug --no-pub \
  --dart-define=MKNOON_RELAY_ADDRESSES="$RELAY" \
  --android-project-arg=androidApplicationId=com.mknoon.sims.lever5 \
  --android-project-arg=disableGoogleServicesForDisposableProof=true
rc=$?
[ $rc -eq 0 ] && shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk | cut -c1-64
exit $rc
