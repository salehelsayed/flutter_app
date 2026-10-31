#!/bin/bash
# Compare the iOS gomobile input digest with the stamp, the same way scripts/test/run_ios_nse_native_373.sh does.
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2; [ "${1:-}" = tools-first ] && TOOLS_FIRST=1
export PATH="${TOOLS_FIRST:+$PWD/go-mknoon/bin/tools:}$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
. scripts/gomobile_binding_inputs.sh
d="$(gomobile_binding_input_digest "$REPO" ios)"; s="$(tr -d '[:space:]' < ios/Runner/GoMknoon.inputs.sha256)"
echo "digest=${d:0:16} stamp=${s:0:16} $([ "$d" = "$s" ] && echo MATCH || echo STALE)"
