#!/bin/bash
# pub get, then the internal-disk Hetzner release device build (build 159) in build/wt-final128i.
M=/Volumes/CrucialX9/flutter_app; E=.codex-test-logs/iphone11-159-20261028
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
(cd "$M/build/wt-final128i" && flutter pub get) > "$M/$E/pub_get.log" 2>&1; echo "pub get exit=$?"
cd "$M" && python3 docker-ws/with_native_lease.py "$E/lease.log" -- bash docker-ws/ios_device_build_internal.sh wt-final128i "$E" 159
echo "BUILD WRAPPER DONE rc=$? $(date -u +%T)"
