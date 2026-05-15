#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT_DIR/ios/Runner.xcworkspace"
SCHEME="Runner"
APP_PATH="$ROOT_DIR/build/ios/iphonesimulator/Runner.app"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.mknoon.app}"
READY_MARKER="MKNOON_APNS_TAP_READY"
RESULT_ROOT="$ROOT_DIR/build/ios-notification-tap-ui-smoke/$(date -u +%Y%m%dT%H%M%SZ)"
TAP_CONFIG_FILE="$ROOT_DIR/build/ios-notification-tap-ui-smoke/current_tap_config.json"

device_csv=""
skip_build=0
scenario_retries="${IOS_NOTIFICATION_TAP_SMOKE_RETRIES:-1}"
started_pid=""

usage() {
  cat <<'EOF'
Usage:
  scripts/run_ios_notification_tap_ui_smoke.sh [--devices <udid1>,<udid2>] [--bundle-id <bundle>] [--skip-build] [--retries <count>]

Runs the simulator-bound iOS APNs notification tap smoke:
  - iPhone 17 Pro warm one_to_one_text
  - iPhone 17 Pro warm group_text
  - iPhone 17 warm one_to_one_text
  - iPhone 17 warm group_text
  - primary simulator cold one_to_one_text

Without --devices, the script requires two booted iPhone simulators and prefers
booted devices named iPhone 17 Pro and iPhone 17.
EOF
}

while (($# > 0)); do
  case "$1" in
    --devices)
      device_csv="${2:?missing --devices value}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:?missing --bundle-id value}"
      shift 2
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    --retries)
      scenario_retries="${2:?missing --retries value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
}

device_name_for_udid() {
  local udid="$1"
  local devices_json
  devices_json="$(xcrun simctl list devices -j)"
  SIMCTL_DEVICES_JSON="$devices_json" node - "$udid" <<'NODE'
const wanted = process.argv[2];
const data = JSON.parse(process.env.SIMCTL_DEVICES_JSON || '{}');
for (const devices of Object.values(data.devices || {})) {
  for (const device of devices) {
    if (device.udid === wanted) {
      process.stdout.write(device.name || wanted);
      process.exit(0);
    }
  }
}
process.stdout.write(wanted);
NODE
}

is_booted_ios_device() {
  local udid="$1"
  local devices_json
  devices_json="$(xcrun simctl list devices booted -j)"
  SIMCTL_DEVICES_JSON="$devices_json" node - "$udid" <<'NODE'
const wanted = process.argv[2];
const data = JSON.parse(process.env.SIMCTL_DEVICES_JSON || '{}');
for (const [runtime, devices] of Object.entries(data.devices || {})) {
  if (!runtime.includes('iOS')) continue;
  for (const device of devices) {
    if (device.udid === wanted && device.state === 'Booted' && device.isAvailable !== false) {
      process.exit(0);
    }
  }
}
process.exit(1);
NODE
}

discover_booted_devices() {
  local devices_json
  devices_json="$(xcrun simctl list devices booted -j)"
  SIMCTL_DEVICES_JSON="$devices_json" node <<'NODE'
const data = JSON.parse(process.env.SIMCTL_DEVICES_JSON || '{}');
const devices = [];
for (const [runtime, runtimeDevices] of Object.entries(data.devices || {})) {
  if (!runtime.includes('iOS')) continue;
  for (const device of runtimeDevices) {
    if (device.state === 'Booted' && device.isAvailable !== false && device.name.startsWith('iPhone')) {
      devices.push(device);
    }
  }
}

const pro = devices.find((device) => device.name === 'iPhone 17 Pro');
const base = devices.find((device) => device.name === 'iPhone 17');
const selected = pro && base ? [pro, base] : devices.slice(0, 2);

if (selected.length < 2) {
  process.stderr.write('Expected two booted iOS iPhone simulators or --devices <udid1>,<udid2>.\n');
  process.exit(1);
}

for (const device of selected) {
  process.stdout.write(`${device.udid}\t${device.name}\n`);
}
NODE
}

split_devices() {
  if [[ -z "$device_csv" ]]; then
    discover_booted_devices
    return
  fi

  local -a ids=()
  IFS=',' read -r -a ids <<<"$device_csv"
  if ((${#ids[@]} != 2)); then
    printf 'Expected exactly two comma-separated simulator UDIDs in --devices.\n' >&2
    exit 2
  fi

  local id
  for id in "${ids[@]}"; do
    if ! is_booted_ios_device "$id"; then
      printf 'Simulator is not a booted iOS device: %s\n' "$id" >&2
      exit 1
    fi
    printf '%s\t%s\n' "$id" "$(device_name_for_udid "$id")"
  done
}

safe_name() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9_.-' '_'
}

start_log_stream() {
  local device="$1"
  local output_file="$2"
  local predicate='eventMessage CONTAINS "PUSH_DIAG" OR eventMessage CONTAINS "[FLOW]" OR eventMessage CONTAINS "IOS_APNS_" OR eventMessage CONTAINS "NOTIFICATION_TAP" OR eventMessage CONTAINS "MKNOON_APNS_TAP_READY"'

  xcrun simctl spawn "$device" log stream \
    --style compact \
    --level debug \
    --predicate "$predicate" \
    >>"$output_file" 2>&1 &
  started_pid="$!"
}

wait_for_pattern() {
  local file="$1"
  local pattern="$2"
  local watched_pid="$3"
  local timeout_seconds="$4"
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
    if [[ -f "$file" ]] && grep -Fq "$pattern" "$file"; then
      return 0
    fi
    if ! kill -0 "$watched_pid" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
  done

  return 1
}

wait_for_ready_signal() {
  local ready_file="$1"
  local log_file="$2"
  local watched_pid="$3"
  local timeout_seconds="$4"
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
    if [[ -f "$ready_file" ]]; then
      return 0
    fi
    if [[ -f "$log_file" ]] && grep -Fq "$READY_MARKER" "$log_file"; then
      return 0
    fi
    if ! kill -0 "$watched_pid" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
  done

  return 1
}

wait_for_any_pattern_after_line() {
  local file="$1"
  local start_line="$2"
  local watched_pid="$3"
  local timeout_seconds="$4"
  shift 4
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
    if [[ -f "$file" ]]; then
      local pattern
      for pattern in "$@"; do
        if tail -n "+$((start_line + 1))" "$file" | grep -Fq "$pattern"; then
          return 0
        fi
      done
    fi
    if ! kill -0 "$watched_pid" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
  done

  return 1
}

assert_log_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$file"; then
    printf 'Missing required marker "%s" in %s\n' "$pattern" "$file" >&2
    return 1
  fi
}

assert_log_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq "$pattern" "$file"; then
    printf 'Found forbidden marker "%s" in %s\n' "$pattern" "$file" >&2
    return 1
  fi
}

write_tap_config() {
  local expected_title="$1"
  local ready_file="$2"

  mkdir -p "$(dirname "$TAP_CONFIG_FILE")"
  TAP_EXPECTED_TITLE="$expected_title" TAP_READY_FILE="$ready_file" node <<'NODE' >"$TAP_CONFIG_FILE"
const config = {
  expectedTitle: process.env.TAP_EXPECTED_TITLE || 'New Message',
  readyFile: process.env.TAP_READY_FILE || '',
  preBackgroundWaitSeconds: process.env.TAP_PRE_BACKGROUND_WAIT_SECONDS || '8',
};
process.stdout.write(`${JSON.stringify(config, null, 2)}\n`);
NODE
}

install_app_on_device() {
  local device="$1"
  local name="$2"

  printf 'Installing %s on %s (%s)\n' "$APP_PATH" "$name" "$device"
  xcrun simctl install "$device" "$APP_PATH"
  xcrun simctl get_app_container "$device" "$BUNDLE_ID" >/dev/null
}

run_xcode_ui_test() {
  local device="$1"
  local xctest_selector="$2"
  local log_file="$3"
  local result_bundle="$4"
  local ready_file="$5"
  local expected_title="$6"

  write_tap_config "$expected_title" "$ready_file"

  (
    cd "$ROOT_DIR/ios"
    MKNOON_APNS_TAP_APP_BUNDLE_ID="$BUNDLE_ID" \
    MKNOON_APNS_TAP_EXPECTED_TITLE="$expected_title" \
    MKNOON_APNS_TAP_READY_FILE="$ready_file" \
    MKNOON_APNS_TAP_PRE_BACKGROUND_WAIT_SECONDS=8 \
    xcodebuild test \
      -workspace "$WORKSPACE" \
      -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,id=$device" \
      "$xctest_selector" \
      -resultBundlePath "$result_bundle"
  ) >>"$log_file" 2>&1 &
  started_pid="$!"
}

push_fixture() {
  local device="$1"
  local fixture="$2"
  local log_file="$3"
  local expected_title="$4"

  # Keep real simctl push in the acceptance path through the shared fixture
  # shaper. This smoke validates user-visible APNs tap routing; Simulator
  # Springboard hides alerts that also carry content-available=1, so keep
  # mutable-content coverage while omitting only the silent/background delivery
  # flag here.
  IOS_APNS_ALERT_TITLE="$expected_title" \
  IOS_APNS_CONTENT_AVAILABLE=0 \
  "$ROOT_DIR/scripts/push_fixture_to_simulator.sh" \
    --device "$device" \
    --bundle-id "$BUNDLE_ID" \
    "$fixture" \
    >>"$log_file" 2>&1
}

launch_warm_app_for_host_push() {
  local device="$1"
  local log_file="$2"
  local log_pid="$3"
  local start_line
  start_line="$(wc -l <"$log_file" | tr -d ' ')"

  printf 'Launching %s for warm APNs tap setup\n' "$BUNDLE_ID" >>"$log_file"
  xcrun simctl launch "$device" "$BUNDLE_ID" >>"$log_file" 2>&1

  if ! wait_for_any_pattern_after_line \
    "$log_file" \
    "$start_line" \
    "$log_pid" \
    90 \
    "P2P_SERVICE_START_NODE_CORE_SUCCESS" \
    "P2P_SERVICE_START_NODE_CORE_ALREADY_RUNNING" \
    'P2P_NODE_STATUS_RESPONSE","details":{"ok":true,"isStarted":true' \
    '"capability":"inbox","success":true'; then
    printf 'Timed out waiting for warm app node readiness in %s\n' "$log_file" >&2
    return 1
  fi

  xcrun simctl launch "$device" com.apple.springboard >>"$log_file" 2>&1
  sleep 2
}

assert_scenario_markers() {
  local mode="$1"
  local log_file="$2"
  local status=0

  assert_log_contains "$log_file" "ios_native_un_didReceive" || status=1

  if [[ "$mode" == "cold" ]]; then
    assert_log_contains "$log_file" "ios_notification_open_stored_pending" || status=1
    assert_log_contains "$log_file" "IOS_APNS_INITIAL_NOTIFICATION_OPENED" || status=1
  else
    assert_log_contains "$log_file" "ios_notification_open_forwarded_warm" || status=1
    assert_log_contains "$log_file" "IOS_APNS_NOTIFICATION_OPENED" || status=1
  fi

  assert_log_not_contains "$log_file" "IOS_APNS_NOTIFICATION_OPEN_ERROR" || status=1
  assert_log_not_contains "$log_file" "NOTIFICATION_TAP_NAV_ERROR" || status=1
  assert_log_not_contains "$log_file" "INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR" || status=1

  return "$status"
}

run_scenario_once() {
  local device="$1"
  local device_name="$2"
  local fixture="$3"
  local mode="$4"
  local label="$5"
  local safe_label
  safe_label="$(safe_name "$label")"
  local log_file="$RESULT_ROOT/$safe_label.combined.log"
  local ready_file="$RESULT_ROOT/$safe_label.ready"
  local expected_title="New Message ${SECONDS}_${RANDOM}"
  local prepare_selector="-only-testing:RunnerUITests/NotificationTapUITests/testPrepareWarmNotificationTap"
  local tap_selector="-only-testing:RunnerUITests/NotificationTapUITests/testTapExistingNotification"

  printf '\nRunning %s on %s (%s)\n' "$label" "$device_name" "$device"
  : >"$log_file"
  rm -f "$ready_file"

  local log_pid
  start_log_stream "$device" "$log_file"
  log_pid="$started_pid"

  if [[ "$mode" == "cold" ]]; then
    xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  else
    local prepare_pid
    local prepare_result_bundle="$RESULT_ROOT/$safe_label.prepare.xcresult"
    run_xcode_ui_test "$device" "$prepare_selector" "$log_file" "$prepare_result_bundle" "$ready_file" "$expected_title"
    prepare_pid="$started_pid"

    if ! wait_for_ready_signal "$ready_file" "$log_file" "$prepare_pid" 120; then
      printf 'Timed out waiting for %s in %s or %s\n' "$READY_MARKER" "$log_file" "$ready_file" >&2
      kill "$prepare_pid" >/dev/null 2>&1 || true
      kill "$log_pid" >/dev/null 2>&1 || true
      wait "$prepare_pid" >/dev/null 2>&1 || true
      wait "$log_pid" >/dev/null 2>&1 || true
      return 1
    fi

    local prepare_status=0
    wait "$prepare_pid" || prepare_status=$?
    if ((prepare_status != 0)); then
      kill "$log_pid" >/dev/null 2>&1 || true
      wait "$log_pid" >/dev/null 2>&1 || true
      printf 'xcodebuild warm prepare failed for %s; see %s\n' "$label" "$log_file" >&2
      return "$prepare_status"
    fi

    if ! launch_warm_app_for_host_push "$device" "$log_file" "$log_pid"; then
      kill "$log_pid" >/dev/null 2>&1 || true
      wait "$log_pid" >/dev/null 2>&1 || true
      return 1
    fi
  fi

  push_fixture "$device" "$fixture" "$log_file" "$expected_title"

  local tap_pid
  local tap_result_bundle="$RESULT_ROOT/$safe_label.tap.xcresult"
  run_xcode_ui_test "$device" "$tap_selector" "$log_file" "$tap_result_bundle" "$ready_file" "$expected_title"
  tap_pid="$started_pid"

  local tap_status=0
  wait "$tap_pid" || tap_status=$?
  sleep 2
  kill "$log_pid" >/dev/null 2>&1 || true
  wait "$log_pid" >/dev/null 2>&1 || true

  if ((tap_status != 0)); then
    printf 'xcodebuild UI test failed for %s; see %s\n' "$label" "$log_file" >&2
    return "$tap_status"
  fi

  if ! assert_scenario_markers "$mode" "$log_file"; then
    return 1
  fi
  printf 'PASS %s; log=%s\n' "$label" "$log_file"
}

run_scenario() {
  local device="$1"
  local device_name="$2"
  local fixture="$3"
  local mode="$4"
  local label="$5"
  local max_attempts=$((scenario_retries + 1))
  local attempt
  local status=0

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    local attempt_label="$label"
    if ((attempt > 1)); then
      attempt_label="$label retry_$attempt"
    fi

    if run_scenario_once "$device" "$device_name" "$fixture" "$mode" "$attempt_label"; then
      return 0
    else
      status=$?
    fi

    if ((attempt < max_attempts)); then
      printf 'Retrying %s after failed attempt %d/%d\n' "$label" "$attempt" "$max_attempts"
      sleep 3
    fi
  done

  return "$status"
}

main() {
  require_command flutter
  require_command node
  require_command xcodebuild
  require_command xcrun

  if ! [[ "$scenario_retries" =~ ^[0-9]+$ ]]; then
    printf '--retries must be a non-negative integer.\n' >&2
    exit 2
  fi

  mkdir -p "$RESULT_ROOT"

  if [[ "$skip_build" -eq 0 ]]; then
    flutter build ios --simulator --debug \
      --dart-define=AUTO_SETUP_USERNAME=TapSmoke
  fi

  if [[ ! -d "$APP_PATH" ]]; then
    printf 'Missing built app at %s; run flutter build ios --simulator --debug first.\n' "$APP_PATH" >&2
    exit 1
  fi

  local -a device_ids=()
  local -a device_names=()
  while IFS=$'\t' read -r id name; do
    device_ids+=("$id")
    device_names+=("$name")
  done < <(split_devices)
  if ((${#device_ids[@]} != 2)); then
    printf 'Expected exactly two booted iOS simulator devices.\n' >&2
    exit 1
  fi

  install_app_on_device "${device_ids[0]}" "${device_names[0]}"
  install_app_on_device "${device_ids[1]}" "${device_names[1]}"

  run_scenario "${device_ids[0]}" "${device_names[0]}" "one_to_one_text" "warm" "${device_names[0]} warm one_to_one_text"
  run_scenario "${device_ids[0]}" "${device_names[0]}" "group_text" "warm" "${device_names[0]} warm group_text"
  run_scenario "${device_ids[1]}" "${device_names[1]}" "one_to_one_text" "warm" "${device_names[1]} warm one_to_one_text"
  run_scenario "${device_ids[1]}" "${device_names[1]}" "group_text" "warm" "${device_names[1]} warm group_text"
  run_scenario "${device_ids[0]}" "${device_names[0]}" "one_to_one_text" "cold" "${device_names[0]} cold one_to_one_text"

  printf '\niOS notification tap UI smoke PASS. Logs: %s\n' "$RESULT_ROOT"
}

main "$@"
