#!/usr/bin/env bash

set -euo pipefail

# Pin the Go toolchain: go1.26.x's crypto/tls panics with quic-go v0.49.0
# ("where's my session ticket?") on the server side of a QUIC handshake, which
# SIGABRTs the receiver of a direct peer-to-peer QUIC connection. This is the
# Xcode build-phase auto-rebuild path, so it must not silently use a newer
# machine default. (The Makefile also exports this; set here too for the verify
# step and any direct `go` use.)
export GOTOOLCHAIN=go1.25.0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_root="$repo_root/go-mknoon"
framework_root="$repo_root/ios/Runner/GoMknoon.xcframework"
framework_info="$framework_root/Info.plist"
header="$framework_root/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers/Bridge.objc.h"
verify_script="$repo_root/scripts/verify_gomobile_bindings.sh"
input_helper="$repo_root/scripts/gomobile_binding_inputs.sh"
input_stamp="$repo_root/ios/Runner/GoMknoon.inputs.sha256"

# shellcheck source=gomobile_binding_inputs.sh
source "$input_helper"
input_digest="$(gomobile_binding_input_digest "$repo_root" ios)"
stored_digest=''
if [[ -f "$input_stamp" ]]; then
  stored_digest="$(tr -d '[:space:]' <"$input_stamp")"
fi

needs_rebuild=0
if [[ ! -f "$framework_info" || ! -f "$header" ]]; then
  needs_rebuild=1
elif [[ "$stored_digest" != "$input_digest" ]]; then
  needs_rebuild=1
elif ! "$verify_script" ios >/dev/null 2>&1; then
  needs_rebuild=1
fi

if [[ "$needs_rebuild" -eq 1 ]]; then
  export PATH="$PATH:$(go env GOPATH)/bin"
  rm -f "$input_stamp"
  (cd "$go_root" && make ios)
fi

"$verify_script" ios
input_digest="$(gomobile_binding_input_digest "$repo_root" ios)"
printf '%s\n' "$input_digest" >"$input_stamp.tmp"
mv "$input_stamp.tmp" "$input_stamp"

# Preserve the Xcode-declared DerivedData sentinel. The phase intentionally runs
# every build so toolchain-only changes reach the cheap content-digest check;
# gomobile itself still runs only when that digest changes. The output is not
# placed inside GoMknoon.xcframework because doing so creates a dependency cycle
# with Pods-NotificationService. Guard for manual/CI runs.
if [[ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]]; then
  mkdir -p "$(dirname "$SCRIPT_OUTPUT_FILE_0")"
  touch "$SCRIPT_OUTPUT_FILE_0"
fi
