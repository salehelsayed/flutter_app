#!/bin/bash
# Regenerate the iOS gomobile bindings (scripts/ensure_go_ios_bindings.sh) with before/after sha256 of the
# binding binaries and the input stamp, all output in an evidence folder.
#   host-run bash docker-ws/regen_ios_bindings_recorded.sh <evidence dir under build/kayan-safe/>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
E="$REPO/${1:?evidence}"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
hashes() {
  for f in ios/Runner/GoMknoon.xcframework/*/GoMknoon.framework/GoMknoon \
           ios/Runner/GoMknoonNSE.xcframework/*/GoMknoonNSE.framework/GoMknoonNSE \
           ios/Runner/GoMknoon.inputs.sha256; do
    [ -f "$f" ] && shasum -a 256 "$f" || echo "missing  $f"
  done
}
hashes > "$E/bindings-before.sha256"
bash scripts/ensure_go_ios_bindings.sh > "$E/ensure_go_ios_bindings.log" 2>&1; rc=$?
hashes > "$E/bindings-after.sha256"
echo "ENSURE_EXIT=$rc"; diff "$E/bindings-before.sha256" "$E/bindings-after.sha256" > /dev/null && echo "UNCHANGED" || echo "CHANGED"
tail -5 "$E/ensure_go_ios_bindings.log"
exit $rc
