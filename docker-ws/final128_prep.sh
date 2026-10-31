#!/bin/bash
# Final 128: copy ignored inputs into build/wt-final128, then rebuild all Go bindings (Android AAR, iOS + macOS
# xcframeworks) from that tree's source. Logs to <evid>.
#   host-run bash docker-ws/final128_prep.sh <evid under repo>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W=$REPO/build/wt-final128; E="$REPO/${1:?evid}"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
bash "$REPO/docker-ws/wt_inputs_setup.sh" wt-final128 > "$E/inputs.log" 2>&1; echo "inputs exit=$?"
cd "$W" || exit 2
for p in android ios macos; do
  echo "== $p bindings $(date -u +%T)"
  bash scripts/ensure_go_${p}_bindings.sh > "$E/bind_$p.log" 2>&1; echo "$p exit=$?"
done
echo "== stamps"; for f in android/app/libs/GoMknoon.inputs.sha256 ios/Runner/GoMknoon.inputs.sha256; do echo "$(cut -c1-16 "$f") $f"; done
git status --porcelain | wc -l | sed 's/^/dirty=/'
echo "== done $(date -u +%T)"
