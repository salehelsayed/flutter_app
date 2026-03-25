#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_root="$repo_root/go-mknoon"
aar="$repo_root/android/app/libs/GoMknoon.aar"
sources_jar="$repo_root/android/app/libs/GoMknoon-sources.jar"
verify_script="$repo_root/scripts/verify_gomobile_bindings.sh"

needs_rebuild=0
if [[ ! -f "$aar" || ! -s "$aar" ]]; then
  needs_rebuild=1
elif find "$go_root" -type f -name '*.go' -newer "$aar" | grep -q .; then
  needs_rebuild=1
elif ! "$verify_script" android >/dev/null 2>&1; then
  needs_rebuild=1
fi

if [[ "$needs_rebuild" -eq 1 ]]; then
  export PATH="$PATH:$(go env GOPATH)/bin"
  rm -f "$aar" "$sources_jar"
  (cd "$go_root" && make android)
fi

"$verify_script" android
