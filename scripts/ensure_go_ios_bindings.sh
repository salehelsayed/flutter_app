#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_root="$repo_root/go-mknoon"
framework_root="$repo_root/ios/Runner/GoMknoon.xcframework"
framework_info="$framework_root/Info.plist"
header="$framework_root/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers/Bridge.objc.h"
verify_script="$repo_root/scripts/verify_gomobile_bindings.sh"

needs_rebuild=0
if [[ ! -f "$framework_info" || ! -f "$header" ]]; then
  needs_rebuild=1
elif find "$go_root" -type f -name '*.go' -newer "$framework_info" | grep -q .; then
  needs_rebuild=1
elif ! "$verify_script" ios >/dev/null 2>&1; then
  needs_rebuild=1
fi

if [[ "$needs_rebuild" -eq 1 ]]; then
  export PATH="$PATH:$(go env GOPATH)/bin"
  (cd "$go_root" && make ios)
fi

"$verify_script" ios

# Stamp the Xcode-declared output (a DerivedData sentinel) so the build system can
# skip this phase when no Go sources changed. The output is deliberately NOT a file
# inside GoMknoon.xcframework — declaring framework-internal files as outputs of
# this Runner script phase creates a build-dependency cycle with
# Pods-NotificationService (which links the same GoMknoon pod) and breaks on-device
# builds. SCRIPT_OUTPUT_FILE_0 is set by Xcode; guard for manual/CI runs.
if [[ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]]; then
  mkdir -p "$(dirname "$SCRIPT_OUTPUT_FILE_0")"
  touch "$SCRIPT_OUTPUT_FILE_0"
fi
