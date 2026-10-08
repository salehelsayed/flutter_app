#!/usr/bin/env bash

set -euo pipefail

# Pin the Go toolchain so this Xcode build-phase auto-rebuild path never
# silently uses a newer machine default. Plan 406 moved it from go1.25.0 (Go
# 1.26+ crypto/tls crashed the old quic-go) to go1.27.1. (The Makefile also
# exports this; set here too for the verify step and any direct `go` use.)
export GOTOOLCHAIN=go1.27.1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_root="$repo_root/go-mknoon"
# gomobile/gobind at the version go.mod pins, installed into this checkout
# (go-mknoon/bin/tools) before the input digest reads the gomobile binary.
export PATH="$go_root/bin/tools:$PATH"
(cd "$go_root" && make -s gomobile-tools)
framework_root="$repo_root/macos/Runner/GoMknoon.xcframework"
framework_info="$framework_root/Info.plist"
header="$framework_root/macos-arm64_x86_64/GoMknoon.framework/Headers/Bridge.objc.h"
verify_script="$repo_root/scripts/verify_gomobile_bindings.sh"

needs_rebuild=0
if [[ ! -f "$framework_info" || ! -f "$header" ]]; then
  needs_rebuild=1
elif find "$go_root" -type f -name '*.go' -newer "$framework_info" | grep -q .; then
  needs_rebuild=1
elif ! "$verify_script" macos >/dev/null 2>&1; then
  needs_rebuild=1
fi

if [[ "$needs_rebuild" -eq 1 ]]; then
  export PATH="$PATH:$(go env GOPATH)/bin"
  (cd "$go_root" && make macos)
fi

"$verify_script" macos
