#!/usr/bin/env bash

set -euo pipefail

require_service_account=0
if [[ "${1:-}" == "--require-service-account" ]]; then
  require_service_account=1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GOOGLE_SERVICE_INFO="$ROOT_DIR/ios/Runner/GoogleService-Info.plist"
INFO_PLIST="$ROOT_DIR/ios/Runner/Info.plist"
RUNNER_ENTITLEMENTS="$ROOT_DIR/ios/Runner/Runner.entitlements"
PBXPROJ="$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj"

failures=0
warnings=0

pass() {
  printf 'PASS  %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'WARN  %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL  %s\n' "$1"
}

extract_plist_string() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    index($0, "<key>" key "</key>") { want = 1; next }
    want && match($0, /<string>([^<]+)<\/string>/) {
      value = $0
      sub(/^.*<string>/, "", value)
      sub(/<\/string>.*$/, "", value)
      print value
      exit
    }
  ' "$file"
}

contains_literal() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file"
}

expected_project_id="$(extract_plist_string "$GOOGLE_SERVICE_INFO" "PROJECT_ID")"
expected_bundle_id="$(extract_plist_string "$GOOGLE_SERVICE_INFO" "BUNDLE_ID")"
aps_environment="$(extract_plist_string "$RUNNER_ENTITLEMENTS" "aps-environment")"

echo "Push Release Gate"
echo "Repo root: $ROOT_DIR"
echo "Expected Firebase project: ${expected_project_id:-<missing>}"
echo "Expected iOS bundle id: ${expected_bundle_id:-<missing>}"
echo

if [[ -n "${expected_project_id}" ]]; then
  pass "GoogleService-Info.plist declares Firebase project $expected_project_id"
else
  fail "GoogleService-Info.plist is missing PROJECT_ID"
fi

if [[ -n "${expected_bundle_id}" ]]; then
  pass "GoogleService-Info.plist declares iOS bundle id $expected_bundle_id"
else
  fail "GoogleService-Info.plist is missing BUNDLE_ID"
fi

if [[ -n "${expected_bundle_id}" ]] && contains_literal "$PBXPROJ" "PRODUCT_BUNDLE_IDENTIFIER = ${expected_bundle_id};"; then
  pass "Runner.xcodeproj bundle identifier matches GoogleService-Info.plist"
else
  fail "Runner.xcodeproj bundle identifier does not match GoogleService-Info.plist"
fi

if contains_literal "$INFO_PLIST" "<string>fetch</string>"; then
  pass "Info.plist includes Background Modes fetch"
else
  fail "Info.plist is missing Background Modes fetch"
fi

if contains_literal "$INFO_PLIST" "<string>remote-notification</string>"; then
  pass "Info.plist includes Background Modes remote-notification"
else
  fail "Info.plist is missing Background Modes remote-notification"
fi

if [[ "$aps_environment" == "production" ]]; then
  pass "Runner.entitlements keeps production aps-environment"
else
  fail "Runner.entitlements aps-environment is not production"
fi

if [[ -n "${FIREBASE_SERVICE_ACCOUNT:-}" ]]; then
  if [[ ! -f "$FIREBASE_SERVICE_ACCOUNT" ]]; then
    fail "FIREBASE_SERVICE_ACCOUNT points to a missing file: $FIREBASE_SERVICE_ACCOUNT"
  else
    service_project_id="$(
      sed -nE 's/^[[:space:]]*"project_id"[[:space:]]*:[[:space:]]*"([^"]+)".*$/\1/p' \
        "$FIREBASE_SERVICE_ACCOUNT" \
        | head -n 1
    )"

    if [[ -z "$service_project_id" ]]; then
      fail "Service account JSON is missing project_id: $FIREBASE_SERVICE_ACCOUNT"
    elif [[ -n "$expected_project_id" && "$service_project_id" == "$expected_project_id" ]]; then
      pass "Service account project_id matches iOS Firebase project"
    else
      fail "Service account project_id ($service_project_id) does not match iOS Firebase project ($expected_project_id)"
    fi
  fi
elif [[ $require_service_account -eq 1 ]]; then
  fail "FIREBASE_SERVICE_ACCOUNT is not set"
else
  warn "FIREBASE_SERVICE_ACCOUNT is not set; service-account project check was skipped"
fi

echo
echo "Relay runtime markers to verify during smoke:"
echo "  - startup log contains: Push:       enabled"
echo "  - token registration log contains: [PUSH] Token registered for ... (ios)"
echo "  - 1:1 send log contains: [PUSH] Notification sent to ..."
echo "  - group send log contains: [PUSH] Group notification sent to ..."
echo

if [[ $failures -gt 0 ]]; then
  printf 'Result: FAIL (%d failures, %d warnings)\n' "$failures" "$warnings"
  exit 1
fi

printf 'Result: PASS (%d warnings)\n' "$warnings"
