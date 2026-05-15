#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CHECKER="$ROOT_DIR/scripts/check_reliability_simulation_discovery.sh"

scope="all"
dry_run=0
continue_on_failure=0
include_direct_targets=0
start_at=1
only_selector=""

default_rendezvous_address="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
default_quic_relay_address="/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
default_relay_addresses="${default_rendezvous_address},${default_quic_relay_address}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_reliability_simulations.sh [all|1to1|group|intro] [options]

Options:
  --list, --dry-run          Validate discovery and print the command plan only.
  --continue-on-failure      Run the remaining commands after a failure.
  --include-direct-targets   Also run direct integration_test files even when a
                             selected runner already targets the same file.
  --start-at <N>             Run the planned command list starting at item N.
  --only <N|path>            Run only planned item N or the exact planned path.
  -h, --help                 Show this help.

Environment:
  MKNOON_RELAY_ADDRESSES            Relay addresses passed to tests/runners.
  RELIABILITY_RELAY_ADDRESSES       Fallback relay override used when
                                    MKNOON_RELAY_ADDRESSES is not set.
                                    Defaults to the app's built-in relay
                                    addresses.
  RELIABILITY_SINGLE_DEVICE_ID      Passed as -d to one-device Flutter tests/runners.
  RELIABILITY_MULTI_DEVICE_IDS      Comma-separated pair passed to two-device runners.
  FLUTTER_DEVICE_ID                 Fallback for one-device runs when it is not comma-separated.
  FLUTTER_MULTI_DEVICE_IDS          Fallback for two-device runners.
  IOS_NOTIFICATION_TAP_DEVICES      Passed as --devices to run_ios_notification_tap_ui_smoke.sh.
  RELIABILITY_WIFI_RELAY_PLATFORM   Platform passed to run_wifi_relay_fallback_smoke.dart
                                    (default: ios).
  DEVICE_A, DEVICE_B, DEVICE_C, DEVICE_D
                                    Used by smoke_test_friends.sh.
  RELIABILITY_NOTIFICATION_SOUND_INTERACTIVE=1
                                    Do not force notification sound smoke into
                                    non-interactive mode.
EOF
}

while (($# > 0)); do
  case "$1" in
    all|1to1|intro)
      scope="$1"
      shift
      ;;
    group|groups)
      scope="group"
      shift
      ;;
    --list|--dry-run)
      dry_run=1
      shift
      ;;
    --continue-on-failure)
      continue_on_failure=1
      shift
      ;;
    --include-direct-targets)
      include_direct_targets=1
      shift
      ;;
    --start-at)
      start_at="${2:?missing --start-at value}"
      if ! [[ "$start_at" =~ ^[0-9]+$ ]] || [ "$start_at" -lt 1 ]; then
        printf 'Invalid --start-at value: %s\n' "$start_at" >&2
        exit 2
      fi
      shift 2
      ;;
    --only)
      only_selector="${2:?missing --only value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -x "$CHECKER" ]; then
  printf 'Missing executable discovery checker: %s\n' "$CHECKER" >&2
  exit 1
fi

records_file="$(mktemp)"
selected_file="$(mktemp)"
targeted_tests_file="$(mktemp)"
plan_file="$(mktemp)"
indexed_plan_file="$(mktemp)"
active_plan_file="$(mktemp)"
failures_file="$(mktemp)"
trap 'rm -f "$records_file" "$selected_file" "$targeted_tests_file" "$plan_file" "$indexed_plan_file" "$active_plan_file" "$failures_file"' EXIT

printf 'Checking reliability simulation discovery...\n'
"$CHECKER" --records-tsv >"$records_file"

awk -F '\t' -v scope="$scope" '
  function selected(category) {
    return scope == "all" || category == scope
  }
  ($1 == "1to1" || $1 == "group" || $1 == "intro") &&
  ($2 == "runner" || $2 == "test") &&
  selected($1) {
    print
  }
' "$records_file" >"$selected_file"

if [ ! -s "$selected_file" ]; then
  printf 'No reliability simulation candidates matched scope: %s\n' "$scope" >&2
  exit 1
fi

extract_runner_targets() {
  local path="$1"
  [ -f "$path" ] || return 0
  awk '{
    line = $0
    while (match(line, /integration_test\/[A-Za-z0-9_\/.-]+_test\.dart/)) {
      print substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
    }
  }' "$path"
}

while IFS=$'\t' read -r category kind path note; do
  [ -n "$category" ] || continue
  if [ "$kind" = "runner" ]; then
    extract_runner_targets "$path"
  fi
done <"$selected_file" | sort -u >"$targeted_tests_file"

awk -F '\t' -v include_direct_targets="$include_direct_targets" '
  NR == FNR {
    targeted[$0] = 1
    next
  }
  {
    category = $1
    kind = $2
    path = $3
    if (seen[path]++) {
      next
    }
    if (kind == "test" && include_direct_targets != "1" && targeted[path]) {
      next
    }
    print kind "\t" path
  }
' "$targeted_tests_file" "$selected_file" >"$plan_file"

if [ ! -s "$plan_file" ]; then
  printf 'No runnable reliability simulation commands were planned for scope: %s\n' "$scope" >&2
  exit 1
fi

awk -F '\t' '{ print NR "\t" $0 }' "$plan_file" >"$indexed_plan_file"

awk -F '\t' -v start_at="$start_at" -v only_selector="$only_selector" '
  function is_number(value) {
    return value ~ /^[0-9]+$/
  }
  {
    plan_index = $1
    path = $3

    if (only_selector != "") {
      if (is_number(only_selector)) {
        if (plan_index == only_selector) {
          print
        }
      } else if (path == only_selector) {
        print
      }
      next
    }

    if (plan_index >= start_at) {
      print
    }
  }
' "$indexed_plan_file" >"$active_plan_file"

if [ ! -s "$active_plan_file" ]; then
  printf 'No runnable reliability simulation commands matched the requested resume filter.\n' >&2
  exit 1
fi

quote_for_display() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

relay_addresses() {
  if [ -n "${MKNOON_RELAY_ADDRESSES:-}" ]; then
    printf '%s\n' "$MKNOON_RELAY_ADDRESSES"
    return
  fi
  if [ -n "${RELIABILITY_RELAY_ADDRESSES:-}" ]; then
    printf '%s\n' "$RELIABILITY_RELAY_ADDRESSES"
    return
  fi
  printf '%s\n' "$default_relay_addresses"
}

print_relay_env_prefix() {
  printf 'MKNOON_RELAY_ADDRESSES=%s ' "$(quote_for_display "$(relay_addresses)")"
}

single_device_id() {
  if [ -n "${RELIABILITY_SINGLE_DEVICE_ID:-}" ]; then
    printf '%s\n' "$RELIABILITY_SINGLE_DEVICE_ID"
    return
  fi
  if [ -n "${FLUTTER_DEVICE_ID:-}" ] && [[ "$FLUTTER_DEVICE_ID" != *,* ]]; then
    printf '%s\n' "$FLUTTER_DEVICE_ID"
  fi
}

multi_device_ids() {
  if [ -n "${RELIABILITY_MULTI_DEVICE_IDS:-}" ]; then
    printf '%s\n' "$RELIABILITY_MULTI_DEVICE_IDS"
    return
  fi
  if [ -n "${FLUTTER_MULTI_DEVICE_IDS:-}" ]; then
    printf '%s\n' "$FLUTTER_MULTI_DEVICE_IDS"
    return
  fi
  if [ -n "${FLUTTER_DEVICE_ID:-}" ] && [[ "$FLUTTER_DEVICE_ID" == *,* ]]; then
    printf '%s\n' "$FLUTTER_DEVICE_ID"
  fi
}

ios_notification_tap_devices() {
  if [ -n "${IOS_NOTIFICATION_TAP_DEVICES:-}" ]; then
    printf '%s\n' "$IOS_NOTIFICATION_TAP_DEVICES"
    return
  fi
  multi_device_ids
}

four_device_ids() {
  if [ -n "${DEVICE_A:-}" ] &&
     [ -n "${DEVICE_B:-}" ] &&
     [ -n "${DEVICE_C:-}" ] &&
     [ -n "${DEVICE_D:-}" ]; then
    printf '%s,%s,%s,%s\n' "$DEVICE_A" "$DEVICE_B" "$DEVICE_C" "$DEVICE_D"
    return
  fi

  multi_device_ids
}

path_needs_four_device() {
  case "$1" in
    integration_test/scripts/run_group_invite_status_matrix_sim.dart|\
    integration_test/scripts/run_group_multi_party_device_real.dart)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_needs_multi_device() {
  case "$1" in
    integration_test/scripts/run_foreground_group_push_simulator_smoke.dart|\
    integration_test/scripts/run_group_multi_device_real.dart|\
    integration_test/scripts/run_notification_open_during_other_chat.dart|\
    integration_test/scripts/run_notification_sound_smoke.dart|\
    integration_test/scripts/run_routing_smoke_e2e.dart)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

device_arg_for_path() {
  local path="$1"

  if path_needs_four_device "$path"; then
    four_device_ids
    return
  fi

  if path_needs_multi_device "$path"; then
    multi_device_ids
    return
  fi

  single_device_id
}

platform_arg_for_path() {
  case "$1" in
    integration_test/scripts/run_wifi_relay_fallback_smoke.dart)
      printf '%s\n' "${RELIABILITY_WIFI_RELAY_PLATFORM:-ios}"
      ;;
  esac
}

print_command_for_path() {
  local kind="$1"
  local path="$2"
  local device_id
  local platform

  print_relay_env_prefix
  case "$path" in
    smoke_test_friends.sh)
      printf 'INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh'
      ;;
    scripts/run_ios_notification_tap_ui_smoke.sh)
      printf './%s' "$path"
      device_id="$(ios_notification_tap_devices)"
      if [ -n "$device_id" ]; then
        printf ' --devices %s' "$(quote_for_display "$device_id")"
      fi
      ;;
    scripts/smoke_test_push_decrypt_simulator.sh)
      printf './%s' "$path"
      if [ "${RELIABILITY_IOS_ONLY:-0}" = "1" ]; then
        printf ' --ios-only'
      fi
      ;;
    scripts/*.sh)
      printf './%s' "$path"
      ;;
    integration_test/scripts/run_notification_sound_smoke.dart)
      printf 'dart run %s' "$path"
      device_id="$(device_arg_for_path "$path")"
      if [ -n "$device_id" ]; then
        printf ' -d %s' "$(quote_for_display "$device_id")"
      fi
      if [ "${RELIABILITY_NOTIFICATION_SOUND_INTERACTIVE:-0}" != "1" ]; then
        printf ' --non-interactive'
      fi
      ;;
    integration_test/scripts/*.dart)
      printf 'dart run %s' "$path"
      device_id="$(device_arg_for_path "$path")"
      if [ -n "$device_id" ]; then
        printf ' -d %s' "$(quote_for_display "$device_id")"
      fi
      platform="$(platform_arg_for_path "$path")"
      if [ -n "$platform" ]; then
        printf ' -p %s' "$(quote_for_display "$platform")"
      fi
      ;;
    integration_test/*.dart)
      printf 'flutter test'
      device_id="$(single_device_id)"
      if [ -n "$device_id" ]; then
        printf ' -d %s' "$(quote_for_display "$device_id")"
      fi
      printf ' %s' "$(quote_for_display "--dart-define=MKNOON_RELAY_ADDRESSES=$(relay_addresses)")"
      printf ' %s' "$path"
      ;;
    *)
      printf '<unknown command for %s %s>' "$kind" "$path"
      ;;
  esac
}

run_path() {
  local kind="$1"
  local path="$2"
  local -a cmd=()
  local device_id
  local platform

  case "$path" in
    smoke_test_friends.sh)
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh
      ;;
    scripts/run_ios_notification_tap_ui_smoke.sh)
      cmd=("./$path")
      device_id="$(ios_notification_tap_devices)"
      if [ -n "$device_id" ]; then
        cmd+=(--devices "$device_id")
      fi
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" "${cmd[@]}"
      ;;
    scripts/smoke_test_push_decrypt_simulator.sh)
      cmd=("./$path")
      if [ "${RELIABILITY_IOS_ONLY:-0}" = "1" ]; then
        cmd+=(--ios-only)
      fi
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" "${cmd[@]}"
      ;;
    scripts/*.sh)
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" "./$path"
      ;;
    integration_test/scripts/run_notification_sound_smoke.dart)
      cmd=(dart run "$path")
      device_id="$(device_arg_for_path "$path")"
      if [ -n "$device_id" ]; then
        cmd+=(-d "$device_id")
      fi
      if [ "${RELIABILITY_NOTIFICATION_SOUND_INTERACTIVE:-0}" != "1" ]; then
        cmd+=(--non-interactive)
      fi
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" "${cmd[@]}"
      ;;
    integration_test/scripts/*.dart)
      cmd=(dart run "$path")
      device_id="$(device_arg_for_path "$path")"
      if [ -n "$device_id" ]; then
        cmd+=(-d "$device_id")
      fi
      platform="$(platform_arg_for_path "$path")"
      if [ -n "$platform" ]; then
        cmd+=(-p "$platform")
      fi
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" "${cmd[@]}"
      ;;
    integration_test/*.dart)
      cmd=(flutter test)
      device_id="$(single_device_id)"
      if [ -n "$device_id" ]; then
        cmd+=(-d "$device_id")
      fi
      cmd+=("--dart-define=MKNOON_RELAY_ADDRESSES=$(relay_addresses)")
      cmd+=("$path")
      MKNOON_RELAY_ADDRESSES="$(relay_addresses)" "${cmd[@]}"
      ;;
    *)
      printf 'No command mapping for %s %s\n' "$kind" "$path" >&2
      return 2
      ;;
  esac
}

printf '\nReliability simulation command plan: %s\n' "$scope"
printf 'Relay addresses: %s\n' "$(relay_addresses)"
if [ "$start_at" -ne 1 ]; then
  printf 'Resume filter: starting at planned item #%s\n' "$start_at"
fi
if [ -n "$only_selector" ]; then
  printf 'Resume filter: only %s\n' "$only_selector"
fi
command_count=0
while IFS=$'\t' read -r index kind path; do
  [ -n "$kind" ] || continue
  command_count=$((command_count + 1))
  printf '  %2d. ' "$index"
  print_command_for_path "$kind" "$path"
  printf '\n'
done <"$active_plan_file"

if [ "$dry_run" -eq 1 ]; then
  printf '\nDry run only. Discovery passed and no commands were executed.\n'
  exit 0
fi

printf '\nRunning %s reliability simulation command(s)...\n' "$command_count"
while IFS=$'\t' read -r index kind path; do
  [ -n "$kind" ] || continue
  printf '\n==> #%s ' "$index"
  print_command_for_path "$kind" "$path"
  printf '\n'

  if run_path "$kind" "$path"; then
    printf 'PASS: #%s %s\n' "$index" "$path"
  else
    status=$?
    printf 'FAIL: #%s %s exited with %s\n' "$index" "$path" "$status" >&2
    printf '%s\t%s\t%s\n' "$index" "$path" "$status" >>"$failures_file"
    if [ "$continue_on_failure" -ne 1 ]; then
      exit "$status"
    fi
  fi
done <"$active_plan_file"

failure_count="$(awk 'END { print NR + 0 }' "$failures_file")"
if [ "$failure_count" -gt 0 ]; then
  printf '\nReliability simulations failed (%s):\n' "$failure_count" >&2
  awk -F '\t' '{ printf "  - #%s %s exited with %s\n", $1, $2, $3 }' "$failures_file" >&2
  exit 1
fi

printf '\nPASS: reliability simulations completed for scope: %s\n' "$scope"
