#!/bin/bash
# Translate preview build 165 (TRANSLATE_PREVIEW + ORBIT_GRAVITY_2D) for the iPhone 11: detach build/wt-final128i at 4e56989ed, pub get, then the
# internal-disk Hetzner release device build with ORBIT_GRAVITY_2D=true.
M=/Volumes/CrucialX9/flutter_app; E=.codex-test-logs/iphone11-165-20261028; C=4e56989ed
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd "$M/build/wt-final128i" || exit 2
echo "tree before: $(git rev-parse --short HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
git status --porcelain --untracked-files=no | head -20
git checkout --detach "$C" > "$M/$E/checkout.log" 2>&1 || { echo "CHECKOUT FAILED"; cat "$M/$E/checkout.log"; exit 3; }
echo "tree now: $(git rev-parse --short HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
flutter pub get > "$M/$E/pub_get.log" 2>&1; echo "pub get exit=$?"
export DD_OVERRIDE="$HOME/tmp-dd-161"; cd "$M" && python3 docker-ws/with_native_lease.py "$E/lease.log" -- bash docker-ws/ios_device_build_internal.sh wt-final128i "$E" 165 "--dart-define=ORBIT_GRAVITY_2D=true --dart-define=TRANSLATE_PREVIEW=true"
echo "BUILD WRAPPER DONE rc=$? $(date -u +%T)"
