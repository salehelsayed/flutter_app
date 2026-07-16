#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ios_phase="$(sed -n \
  '/77715C4E00D1DB8B21DC2285 .*Ensure GoMknoon iOS Bindings.* = {/,/^[[:space:]]*};/p' \
  ios/Runner.xcodeproj/project.pbxproj)"
case "$ios_phase" in
  *'/Users/'*|*'_test.go'*)
    fail 'iOS gomobile phase retained machine-specific or test-only inputs'
    ;;
esac
case "$ios_phase" in
  *'alwaysOutOfDate = 1;'*'$(SRCROOT)/../scripts/gomobile_binding_inputs.sh'*'$(SRCROOT)/../scripts/ensure_go_ios_bindings.sh'*) ;;
  *) fail 'iOS gomobile phase is not a portable always-on digest check' ;;
esac

android_gradle="$(cat android/app/build.gradle.kts)"
case "$android_gradle" in
  *'gomobile_binding_inputs.sh'*'GoMknoon.inputs.sha256'*'outputs.upToDateWhen { false }'*) ;;
  *) fail 'Android gomobile task is not an always-on deterministic digest check' ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p \
  "$tmp_dir/scripts" \
  "$tmp_dir/go-mknoon/bridge" \
  "$tmp_dir/android/app/libs" \
  "$tmp_dir/ios/Runner/GoMknoon.xcframework/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers" \
  "$tmp_dir/bin"

cp scripts/ensure_go_android_bindings.sh "$tmp_dir/scripts/"
cp scripts/ensure_go_ios_bindings.sh "$tmp_dir/scripts/"
cp scripts/gomobile_binding_inputs.sh "$tmp_dir/scripts/"
chmod +x \
  "$tmp_dir/scripts/ensure_go_android_bindings.sh" \
  "$tmp_dir/scripts/ensure_go_ios_bindings.sh"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$tmp_dir/scripts/verify_gomobile_bindings.sh"
chmod +x "$tmp_dir/scripts/verify_gomobile_bindings.sh"

cat_make="$tmp_dir/bin/make"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$1" >>"${TEST_BUILD_LOG:?}"' \
  'case "$1" in' \
  '  android)' \
  '    mkdir -p "${TEST_ROOT:?}/android/app/libs"' \
  '    printf "rebuilt android\n" >"$TEST_ROOT/android/app/libs/GoMknoon.aar"' \
  '    ;;' \
  '  ios)' \
  '    framework="$TEST_ROOT/ios/Runner/GoMknoon.xcframework"' \
  '    headers="$framework/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers"' \
  '    mkdir -p "$headers"' \
  '    printf "rebuilt ios\n" >"$framework/Info.plist"' \
  '    printf "header\n" >"$headers/Bridge.objc.h"' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  >"$cat_make"
chmod +x "$cat_make"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "env" ] && [ "${2:-}" = "GOPATH" ]; then' \
  '  printf "%s\n" "${TEST_ROOT:?}/gopath"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-}" = "version" ]; then' \
  '  printf "%s\n" "${TEST_GO_VERSION:-go-a}"' \
  '  exit 0' \
  'fi' \
  'exit 64' \
  >"$tmp_dir/bin/go"
chmod +x "$tmp_dir/bin/go"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "${TEST_GOMOBILE_VERSION:-gomobile-a}"' \
  >"$tmp_dir/bin/gomobile"
chmod +x "$tmp_dir/bin/gomobile"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "${TEST_XCODE_VERSION:-xcode-a}"' \
  >"$tmp_dir/bin/xcodebuild"
chmod +x "$tmp_dir/bin/xcodebuild"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "${TEST_XCODE_SDK_VERSION:-sdk-a}"' \
  >"$tmp_dir/bin/xcrun"
chmod +x "$tmp_dir/bin/xcrun"

production="$tmp_dir/go-mknoon/bridge/bridge.go"
test_source="$tmp_dir/go-mknoon/bridge/bridge_test.go"
go_mod="$tmp_dir/go-mknoon/go.mod"
aar="$tmp_dir/android/app/libs/GoMknoon.aar"
framework="$tmp_dir/ios/Runner/GoMknoon.xcframework"
header="$framework/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers/Bridge.objc.h"
printf 'package bridge\n' >"$production"
printf 'package bridge\n' >"$test_source"
printf 'module example.test/app\n' >"$go_mod"
printf 'sum\n' >"$tmp_dir/go-mknoon/go.sum"
printf 'android:\n\t@true\n' >"$tmp_dir/go-mknoon/Makefile"
printf 'original android\n' >"$aar"
printf 'original ios\n' >"$framework/Info.plist"
printf 'header\n' >"$header"
ndk="$tmp_dir/android-sdk/ndk/28.2.13676358"
mkdir -p "$ndk"
printf 'Pkg.Revision = 28.2.13676358\n' >"$ndk/source.properties"
build_log="$tmp_dir/build.log"
: >"$build_log"
gomobile_version='gomobile-a'

run_android() {
  TEST_ROOT="$tmp_dir" \
    TEST_BUILD_LOG="$build_log" \
    TEST_GOMOBILE_VERSION="$gomobile_version" \
    ANDROID_HOME="$tmp_dir/android-sdk" \
    PATH="$tmp_dir/bin:$PATH" \
    "$tmp_dir/scripts/ensure_go_android_bindings.sh"
}

run_ios() {
  TEST_ROOT="$tmp_dir" \
    TEST_BUILD_LOG="$build_log" \
    TEST_GOMOBILE_VERSION="$gomobile_version" \
    PATH="$tmp_dir/bin:$PATH" \
    "$tmp_dir/scripts/ensure_go_ios_bindings.sh"
}

# A missing deterministic stamp causes one bootstrap rebuild per platform.
run_android
run_ios
[ "$(grep -c '^android$' "$build_log")" -eq 1 ] ||
  fail 'Android binding stamp bootstrap did not rebuild exactly once'
[ "$(grep -c '^ios$' "$build_log")" -eq 1 ] ||
  fail 'iOS binding stamp bootstrap did not rebuild exactly once'

# A changed Go test must not rebuild a gomobile artifact.
: >"$build_log"
printf 'package bridge // test-only change\n' >"$test_source"
run_android
run_ios
[ ! -s "$build_log" ] || fail '_test.go edit triggered a gomobile rebuild'

# Content changes invalidate even when their mtimes remain older than artifacts.
printf 'module example.test/changed\n' >"$go_mod"
touch -t 202001010000 "$go_mod"
touch -t 203001010000 "$aar" "$framework/Info.plist" "$header"
run_android
run_ios
[ "$(grep -c '^android$' "$build_log")" -eq 1 ] ||
  fail 'older-mtime go.mod edit did not rebuild Android exactly once'
[ "$(grep -c '^ios$' "$build_log")" -eq 1 ] ||
  fail 'older-mtime go.mod edit did not rebuild iOS exactly once'

# A production source content change also rebuilds once with preserved mtime.
: >"$build_log"
printf 'package bridge // production change\n' >"$production"
touch -t 202001010000 "$production"
run_android
run_ios
[ "$(grep -c '^android$' "$build_log")" -eq 1 ] ||
  fail 'production Go edit did not rebuild Android exactly once'
[ "$(grep -c '^ios$' "$build_log")" -eq 1 ] ||
  fail 'production Go edit did not rebuild iOS exactly once'

# A gomobile identity change rebuilds once per platform, then both reuse it.
: >"$build_log"
gomobile_version='gomobile-b'
run_android
run_ios
[ "$(grep -c '^android$' "$build_log")" -eq 1 ] ||
  fail 'gomobile identity change did not rebuild Android exactly once'
[ "$(grep -c '^ios$' "$build_log")" -eq 1 ] ||
  fail 'gomobile identity change did not rebuild iOS exactly once'
: >"$build_log"
run_android
run_ios
[ ! -s "$build_log" ] || fail 'unchanged stamped bindings rebuilt again'

# The NDK identity is Android-only; iOS continues reusing its stamped binding.
printf 'Pkg.Revision = 28.2.13676358-hotfix\n' >"$ndk/source.properties"
run_android
run_ios
[ "$(grep -c '^android$' "$build_log")" -eq 1 ] ||
  fail 'NDK identity change did not rebuild Android exactly once'
[ "$(grep -c '^ios$' "$build_log" || true)" -eq 0 ] ||
  fail 'Android NDK identity change rebuilt the iOS binding'

printf 'PASS: gomobile deterministic stamp tracks content/toolchains once\n'
