#!/usr/bin/env bash

set -euo pipefail

# Pin the Go toolchain so this Gradle build-phase auto-rebuild path never
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
aar="$repo_root/android/app/libs/GoMknoon.aar"
sources_jar="$repo_root/android/app/libs/GoMknoon-sources.jar"
verify_script="$repo_root/scripts/verify_gomobile_bindings.sh"
input_helper="$repo_root/scripts/gomobile_binding_inputs.sh"
input_stamp="$repo_root/android/app/libs/GoMknoon.inputs.sha256"

# Keep gomobile's Makefile NDK selection aligned with Android SDK discovery.
if [[ -z "${ANDROID_HOME:-}" && -n "${ANDROID_SDK_ROOT:-}" ]]; then
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
fi
if [[ -z "${ANDROID_HOME:-}" && -f "$repo_root/android/local.properties" ]]; then
  sdk_dir="$(sed -nE \
    's/^[[:space:]]*sdk\.dir[[:space:]]*[:=][[:space:]]*(.*)$/\1/p' \
    "$repo_root/android/local.properties" | tail -n 1)"
  if [[ -n "$sdk_dir" ]]; then
    export ANDROID_HOME="$sdk_dir"
  fi
fi
# shellcheck source=gomobile_binding_inputs.sh
source "$input_helper"
input_digest="$(gomobile_binding_input_digest "$repo_root" android)"
stored_digest=''
if [[ -f "$input_stamp" ]]; then
  stored_digest="$(tr -d '[:space:]' <"$input_stamp")"
fi

needs_rebuild=0
if [[ ! -f "$aar" || ! -s "$aar" ]]; then
  needs_rebuild=1
elif [[ "$stored_digest" != "$input_digest" ]]; then
  needs_rebuild=1
elif ! "$verify_script" android >/dev/null 2>&1; then
  needs_rebuild=1
fi

if [[ "$needs_rebuild" -eq 1 ]]; then
  export PATH="$PATH:$(go env GOPATH)/bin"
  rm -f "$aar" "$sources_jar" "$input_stamp"
  (cd "$go_root" && make android)
fi

"$verify_script" android
input_digest="$(gomobile_binding_input_digest "$repo_root" android)"
printf '%s\n' "$input_digest" >"$input_stamp.tmp"
mv "$input_stamp.tmp" "$input_stamp"
