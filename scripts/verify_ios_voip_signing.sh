#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL ios-voip-signing: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail "expected one Runner.app path"

runner_app=$1
[[ "${runner_app##*/}" == "Runner.app" && -d "$runner_app" ]] || \
  fail "Runner.app is unavailable"

info_plist="$runner_app/Info.plist"
[[ -f "$info_plist" ]] || fail "Runner Info.plist is unavailable"

if ! bundled_environment=$(
  /usr/libexec/PlistBuddy -c 'Print :MknoonVoipEnvironment' "$info_plist" 2>/dev/null
); then
  fail "bundled environment is absent"
fi
case "$bundled_environment" in
  development|production) ;;
  *) fail "bundled environment is invalid" ;;
esac

codesign --verify --strict "$runner_app" >/dev/null 2>&1 || \
  fail "Runner signature is invalid"

temp_parent=${TMPDIR:-/tmp}
temp_parent=${temp_parent%/}
[[ -n "$temp_parent" && -d "$temp_parent" ]] || fail "temporary directory is unavailable"
temp_directory=$(mktemp -d "$temp_parent/mknoon-ios-voip-signing.XXXXXX") || \
  fail "temporary directory creation failed"
entitlements_plist="$temp_directory/runner-entitlements.plist"

cleanup() {
  if [[ -n "${temp_directory:-}" && -d "$temp_directory" &&
        "$temp_directory" == "$temp_parent"/mknoon-ios-voip-signing.* ]]; then
    rm -rf -- "$temp_directory"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

codesign --display --entitlements :- "$runner_app" \
  >"$entitlements_plist" 2>/dev/null || fail "Runner entitlements are unreadable"
[[ -s "$entitlements_plist" ]] || fail "Runner entitlements are unreadable"
plutil -lint "$entitlements_plist" >/dev/null 2>&1 || \
  fail "Runner entitlements are invalid"

if ! signed_environment=$(
  /usr/libexec/PlistBuddy -c 'Print :aps-environment' "$entitlements_plist" 2>/dev/null
); then
  fail "signed aps-environment is absent"
fi
case "$signed_environment" in
  development|production) ;;
  *) fail "signed aps-environment is invalid" ;;
esac

if [[ "$bundled_environment" != "$signed_environment" ]]; then
  printf 'FAIL ios-voip-signing: environment mismatch (bundle=%s, entitlement=%s)\n' \
    "$bundled_environment" "$signed_environment" >&2
  exit 1
fi

printf 'PASS ios-voip-signing: environment=%s\n' "$bundled_environment"
