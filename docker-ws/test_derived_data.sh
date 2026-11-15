#!/bin/bash
# Persistent DerivedData for Hetzner TEST iOS builds (owner 11-15). Source it,
# then call prepare_test_derived_data <dir>. The folder keeps the previous
# build while Xcode and Flutter stay the same, and starts empty otherwise.
# Only ~/dd-hetzner-test-* folders are accepted, so store, upload and restore
# DerivedData can never be touched (10-31). Keep the folder on the internal
# disk (10-26).

prepare_test_derived_data() {
  local dir="$1" key record
  case "$(basename "$dir")" in
    dd-hetzner-test-*) ;;
    *)
      echo "prepare_test_derived_data: refusing $dir (not a dd-hetzner-test-* folder)" >&2
      return 2
      ;;
  esac
  key="$(xcodebuild -version 2>&1; flutter --version --machine 2>&1)"
  record="$dir/.mknoon-test-toolchain"
  if [ -f "$record" ] && [ "$(cat "$record")" = "$key" ]; then
    echo "test DerivedData kept: $dir"
    return 0
  fi
  rm -rf "$dir" || return 1
  mkdir -p "$dir" || return 1
  printf '%s' "$key" >"$record"
  echo "test DerivedData started empty: $dir"
}
