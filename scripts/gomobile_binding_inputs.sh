#!/usr/bin/env bash

# Shared deterministic input identity for the Android/iOS gomobile bindings.
# This file is sourced by the platform ensure scripts; it does not mutate the
# repository or build an artifact by itself.

gomobile_sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    openssl dgst -sha256 "$path" | awk '{print $NF}'
  fi
}

gomobile_sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    openssl dgst -sha256 | awk '{print $NF}'
  fi
}

gomobile_effective_binary() {
  local go_binary="$1"
  local candidate
  candidate="$(command -v gomobile 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if [[ -n "$go_binary" ]]; then
    local gopath
    gopath="$(GOTOOLCHAIN=go1.25.0 "$go_binary" env GOPATH 2>/dev/null || true)"
    gopath="${gopath%%:*}"
    candidate="$gopath/bin/gomobile"
    if [[ -n "$gopath" && -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  return 1
}

gomobile_android_ndk_directory() {
  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    printf '%s\n' "$ANDROID_NDK_HOME"
    return 0
  fi
  if [[ -z "${ANDROID_HOME:-}" || ! -d "$ANDROID_HOME/ndk" ]]; then
    return 1
  fi
  find "$ANDROID_HOME/ndk" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    LC_ALL=C sort -V |
    tail -n 1
}

gomobile_binding_input_digest() {
  local repo_root="$1"
  local platform="$2"
  local go_root="$repo_root/go-mknoon"
  local ensure_script="$repo_root/scripts/ensure_go_${platform}_bindings.sh"
  local verify_script="$repo_root/scripts/verify_gomobile_bindings.sh"
  local helper_script="$repo_root/scripts/gomobile_binding_inputs.sh"
  local go_binary
  local gomobile_binary
  go_binary="$(command -v go 2>/dev/null || true)"
  gomobile_binary="$(gomobile_effective_binary "$go_binary" || true)"

  {
    printf 'schema=mknoon.gomobile-binding-inputs.v1\n'
    printf 'platform=%s\n' "$platform"
    find "$go_root" -type f \
      \( \( -name '*.go' ! -name '*_test.go' \) \
        -o -name '*.s' -o -name '*.S' -o -name '*.c' -o -name '*.h' \
        -o -name '*.m' -o -name '*.mm' -o -name 'go.mod' -o -name 'go.sum' \) \
      ! -path '*/testdata/*' -print |
      LC_ALL=C sort |
      while IFS= read -r input; do
        [[ -n "$input" ]] || continue
        printf 'file=%s:%s\n' \
          "${input#"$repo_root"/}" "$(gomobile_sha256_file "$input")"
      done
    local fixed
    for fixed in \
      "$go_root/Makefile" \
      "$ensure_script" \
      "$verify_script" \
      "$helper_script"; do
      if [[ -f "$fixed" ]]; then
        printf 'file=%s:%s\n' \
          "${fixed#"$repo_root"/}" "$(gomobile_sha256_file "$fixed")"
      else
        printf 'file=%s:<missing>\n' "${fixed#"$repo_root"/}"
      fi
    done
    if [[ -n "$go_binary" && -f "$go_binary" ]]; then
      printf 'go.binary=%s\n' "$(gomobile_sha256_file "$go_binary")"
      printf 'go.version=%s\n' \
        "$(GOTOOLCHAIN=go1.25.0 "$go_binary" version 2>&1 || true)"
    else
      printf 'go=<missing>\n'
    fi
    if [[ -n "$gomobile_binary" && -f "$gomobile_binary" ]]; then
      printf 'gomobile.binary=%s\n' \
        "$(gomobile_sha256_file "$gomobile_binary")"
      printf 'gomobile.version=%s\n' \
        "$(GOTOOLCHAIN=go1.25.0 "$gomobile_binary" version 2>&1 || true)"
    else
      printf 'gomobile=<missing>\n'
    fi
    if [[ "$platform" == 'android' ]]; then
      local ndk
      ndk="$(gomobile_android_ndk_directory || true)"
      if [[ -n "$ndk" && -f "$ndk/source.properties" ]]; then
        printf 'ndk.version=%s\n' "$(basename "$ndk")"
        printf 'ndk.source-properties=%s\n' \
          "$(gomobile_sha256_file "$ndk/source.properties")"
      else
        printf 'ndk=<missing>\n'
      fi
    else
      printf 'xcode.version=%s\n' "$(xcodebuild -version 2>&1 || true)"
      printf 'iphoneos.sdk=%s\n' \
        "$(xcrun --sdk iphoneos --show-sdk-build-version 2>&1 || true)"
      printf 'iphonesimulator.sdk=%s\n' \
        "$(xcrun --sdk iphonesimulator --show-sdk-build-version 2>&1 || true)"
    fi
  } | gomobile_sha256_stream
}
