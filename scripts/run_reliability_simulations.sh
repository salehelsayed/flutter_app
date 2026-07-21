#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CHECKER="$ROOT_DIR/scripts/check_reliability_simulation_discovery.sh"

scope="all"
dry_run=0
continue_on_failure=0
include_direct_targets=0
simultaneous=0
max_parallel="${SIMS_MAX_PARALLEL:-4}"
start_at=1
only_selector=""
excluded_paths=()
excluded_path_count=0

default_rendezvous_address="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
default_quic_relay_address="/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
default_relay_addresses="${default_rendezvous_address},${default_quic_relay_address}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_reliability_simulations.sh [all|1to1|group|intro|move-feature] [options]

Options:
  --list, --dry-run          Validate discovery and print the command plan only.
  --continue-on-failure      Run the remaining commands after a failure.
  --include-direct-targets   Also run direct integration_test files even when a
                             selected runner already targets the same file.
  --simultaneous             Compatibility flag. Legacy reliability rows all
                             remain serial because they share device/build/relay
                             state. Use the typed `sims` gate for manifest-owned
                             resource-aware concurrency.
  --start-at <N>             Run the planned command list starting at item N.
  --only <N|path|path:scenario>
                             Run only planned item N, path, or path:scenario.
  --exclude-path <path>      Omit one exact discovered path. Repeatable and
                             reserved for typed sims aggregate ownership.
  -h, --help                 Show this help.

Environment:
  MKNOON_RELAY_ADDRESSES            Relay addresses passed to tests/runners.
  RELIABILITY_RELAY_ADDRESSES       Fallback relay override used when
                                    MKNOON_RELAY_ADDRESSES is not set.
                                    Defaults to the app's built-in relay
                                    addresses.
  RELIABILITY_GROUP_TIER            Multi-party group scenario tier:
                                    smoke or full (default: full). The smoke
                                    tier is a routine subset; full remains the
                                    nightly/release requirement.
  RELIABILITY_SINGLE_DEVICE_ID      Passed as -d to one-device Flutter tests/runners.
  RELIABILITY_MULTI_DEVICE_IDS      Comma-separated pair passed to two-device runners.
  FLUTTER_DEVICE_ID                 Fallback for one-device runs when it is not comma-separated.
  FLUTTER_MULTI_DEVICE_IDS          Fallback for two-device runners.
  IOS_NOTIFICATION_TAP_DEVICES      Passed as --devices to run_ios_notification_tap_ui_smoke.sh.
  RELIABILITY_WIFI_RELAY_PLATFORM   Platform passed to run_wifi_relay_fallback_smoke.dart
                                    (default: ios).
  DEVICE_A, DEVICE_B, DEVICE_C, DEVICE_D
                                    Used by smoke_test_friends.sh.
  RELIABILITY_REUSE_BUILT_APP=1    Reuse an existing
                                    build/ios/iphonesimulator/Runner.app for
                                    shell/UI harnesses that support skipping
                                    their build step.
  RELIABILITY_NOTIFICATION_SOUND_INTERACTIVE=1
                                    Do not force notification sound smoke into
                                    non-interactive mode.
  SIMS_MAX_PARALLEL                 Compatibility bound accepted by
                                    --simultaneous (default: 4; range: 1-64).
EOF
}

while (($# > 0)); do
  case "$1" in
    all|1to1|intro|move-feature)
      scope="$1"
      shift
      ;;
    group|groups)
      scope="group"
      shift
      ;;
    move|moves|account-migration|account_migration)
      scope="move-feature"
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
    --simultaneous|--parallel)
      simultaneous=1
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
    --exclude-path)
      excluded_paths[$excluded_path_count]="${2:?missing --exclude-path value}"
      excluded_path_count=$((excluded_path_count + 1))
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

if [ "$simultaneous" -eq 1 ] &&
   ! [[ "$max_parallel" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]]; then
  printf 'Invalid SIMS_MAX_PARALLEL: %s (expected 1 through 64).\n' \
    "$max_parallel" >&2
  exit 2
fi

if [ ! -x "$CHECKER" ]; then
  printf 'Missing executable discovery checker: %s\n' "$CHECKER" >&2
  exit 1
fi

records_file="$(mktemp)"
selected_file="$(mktemp)"
targeted_tests_file="$(mktemp)"
raw_plan_file="$(mktemp)"
plan_file="$(mktemp)"
indexed_plan_file="$(mktemp)"
active_plan_file="$(mktemp)"
serial_plan_file="$(mktemp)"
parallel_plan_file="$(mktemp)"
failures_file="$(mktemp)"
group_multi_party_all_scenarios_file="$(mktemp)"
parallel_work_dir="$(mktemp -d)"
trap 'rm -f "$records_file" "$selected_file" "$targeted_tests_file" "$raw_plan_file" "$plan_file" "$indexed_plan_file" "$active_plan_file" "$serial_plan_file" "$parallel_plan_file" "$failures_file" "$group_multi_party_all_scenarios_file"; rm -rf "$parallel_work_dir"' EXIT

printf 'Checking reliability simulation discovery...\n'
"$CHECKER" --records-tsv >"$records_file"

awk -F '\t' -v scope="$scope" '
  function selected(category) {
    return scope == "all" || category == scope
  }
  ($1 == "1to1" || $1 == "group" || $1 == "intro" || $1 == "move-feature") &&
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

if [ -s "$targeted_tests_file" ]; then
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
      print kind "\t" path "\t"
    }
  ' "$targeted_tests_file" "$selected_file" >"$raw_plan_file"
else
  awk -F '\t' '
    {
      kind = $2
      path = $3
      if (seen[path]++) {
        next
      }
      print kind "\t" path "\t"
    }
  ' "$selected_file" >"$raw_plan_file"
fi

# Apply typed-owner exclusions after runner target deduplication. This prevents
# an excluded owning runner from accidentally re-introducing its direct proof
# file as a second executable row.
for ((excluded_path_index = 0; excluded_path_index < excluded_path_count; excluded_path_index++)); do
  excluded_path="${excluded_paths[$excluded_path_index]}"
  filtered_raw_plan_file="$(mktemp)"
  awk -F '\t' -v excluded_path="$excluded_path" \
    '$2 != excluded_path { print }' \
    "$raw_plan_file" >"$filtered_raw_plan_file"
  mv "$filtered_raw_plan_file" "$raw_plan_file"
done

group_multi_party_tier() {
  local tier="${RELIABILITY_GROUP_TIER:-full}"
  case "$tier" in
    full|smoke)
      printf '%s\n' "$tier"
      ;;
    *)
      printf 'Invalid RELIABILITY_GROUP_TIER: %s (expected smoke or full).\n' "$tier" >&2
      return 2
      ;;
  esac
}

group_multi_party_tier_scenario_arg() {
  local tier

  if ! tier="$(group_multi_party_tier)"; then
    return 2
  fi
  if [ "$tier" = "smoke" ]; then
    printf 'smoke\n'
  else
    printf 'all\n'
  fi
}

all_group_multi_party_scenarios() {
  if [ ! -s "$group_multi_party_all_scenarios_file" ]; then
    if ! dart integration_test/scripts/run_group_multi_party_device_real.dart \
      --scenario all \
      --list-scenarios |
      awk 'NF { print }' >"$group_multi_party_all_scenarios_file"; then
      printf 'Failed to list full group multi-party reliability scenarios.\n' >&2
      return 1
    fi
  fi
  cat "$group_multi_party_all_scenarios_file"
}

is_group_multi_party_scenario() {
  local scenario="$1"

  case "$scenario" in
    all|smoke|slice_b_live)
      return 0
      ;;
  esac
  all_group_multi_party_scenarios | grep -Fxq -- "$scenario"
}

group_multi_party_only_scenario() {
  local path="$1"
  local selector="$only_selector"
  local scenario=""

  [ -n "$selector" ] || return 1
  if [ "$selector" = "$path" ]; then
    return 1
  fi

  case "$selector" in
    "$path":*)
      scenario="${selector#"$path:"}"
      ;;
    "$path --scenario "*)
      scenario="${selector#"$path --scenario "}"
      ;;
    *)
      scenario="$selector"
      ;;
  esac

  if is_group_multi_party_scenario "$scenario"; then
    printf '%s\n' "$scenario"
    return 0
  fi
  return 1
}

group_lifecycle_sim_scenarios() {
  cat <<'EOF'
ADMIN_METADATA
DELETE_PRESERVES_FRIENDS
INVITE_ACCEPT_SPINNER
NEW_MEMBER_MEDIA
EOF
}

while IFS=$'\t' read -r kind path scenario; do
  [ -n "$kind" ] || continue
  if [ "$path" = "integration_test/group_lifecycle_simulator_harness.dart" ]; then
    while IFS= read -r expanded_scenario; do
      [ -n "$expanded_scenario" ] || continue
      printf '%s\t%s\t%s\n' "$kind" "$path" "$expanded_scenario"
    done < <(group_lifecycle_sim_scenarios)
    continue
  fi
  if [ "$path" = "integration_test/scripts/run_group_multi_party_device_real.dart" ]; then
    if expanded_scenario="$(group_multi_party_only_scenario "$path")"; then
      printf '%s\t%s\t%s\n' "$kind" "$path" "$expanded_scenario"
      continue
    fi
    if ! expanded_scenario="$(group_multi_party_tier_scenario_arg)"; then
      exit 2
    fi
    printf '%s\t%s\t%s\n' "$kind" "$path" "$expanded_scenario"
    continue
  fi
  if [ "$path" = "integration_test/scripts/run_invite_reliability_multi_device.dart" ]; then
    # Plan 267 keeps the existing invite-reliability proof independently
    # runnable while registering the latency evidence campaign as a distinct
    # selector. A generic path-only row would make --only path:scenario fail.
    printf '%s\t%s\tinvite_reliability\n' "$kind" "$path"
    printf '%s\t%s\tinvite_send_latency\n' "$kind" "$path"
    continue
  fi
  printf '%s\t%s\t%s\n' "$kind" "$path" "$scenario"
done <"$raw_plan_file" >"$plan_file"

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
    scenario = $4
    path_scenario = path ":" scenario
    path_arg = path " --scenario " scenario

    if (only_selector != "") {
      if (is_number(only_selector)) {
        if (plan_index == only_selector) {
          print
        }
      } else {
        selector_matches = path == only_selector
        if (scenario != "") {
          if (path_scenario == only_selector || path_arg == only_selector) {
            selector_matches = 1
          }
          if (scenario == only_selector) {
            selector_matches = 1
          }
        }
        if (selector_matches) {
          print
        }
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

resource_class_for_path() {
  # Plan 258 removed artifact-only support files from this executable catalog.
  # Resource-aware overlap is now compiled from tool/sims/critical_features.json;
  # this compatibility runner has no typed lock metadata and therefore fails
  # closed by serializing every row.
  printf 'exclusive-shared-device-build\n'
}

while IFS=$'\t' read -r index kind path scenario; do
  [ -n "$kind" ] || continue
  if [ "$simultaneous" -eq 1 ] &&
     [ "$(resource_class_for_path "$path")" = "post-capture-validator" ]; then
    printf '%s\t%s\t%s\t%s\n' "$index" "$kind" "$path" "$scenario" \
      >>"$parallel_plan_file"
  else
    printf '%s\t%s\t%s\t%s\n' "$index" "$kind" "$path" "$scenario" \
      >>"$serial_plan_file"
  fi
done <"$active_plan_file"

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
    integration_test/scripts/run_b1b_sibling_device_convergence.dart|\
    integration_test/scripts/run_group_multi_device_real.dart|\
    integration_test/scripts/run_invite_reliability_multi_device.dart|\
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

mode_arg_for_path() {
  local path="$1"
  local scenario="${2:-}"

  case "$path:$scenario" in
    integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency)
      printf 'baseline\n'
      ;;
  esac
}

requires_explicit_multi_device_ids() {
  local path="$1"
  local scenario="${2:-}"

  [ "$path:$scenario" = \
    "integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency" ]
}

print_device_arg_for_path() {
  local path="$1"
  local scenario="${2:-}"
  local device_id

  device_id="$(device_arg_for_path "$path")"
  if [ -n "$device_id" ]; then
    printf ' -d %s' "$(quote_for_display "$device_id")"
    return
  fi

  if requires_explicit_multi_device_ids "$path" "$scenario"; then
    printf ' -d %s' \
      "$(quote_for_display '<required:RELIABILITY_MULTI_DEVICE_IDS>')"
  fi
}

validate_required_device_args() {
  local index
  local kind
  local path
  local scenario

  while IFS=$'\t' read -r index kind path scenario; do
    [ -n "$path" ] || continue
    if requires_explicit_multi_device_ids "$path" "$scenario" &&
       [ -z "$(device_arg_for_path "$path")" ]; then
      printf 'Missing explicit two-device IDs for %s:%s.\n' \
        "$path" "$scenario" >&2
      printf 'Set RELIABILITY_MULTI_DEVICE_IDS=<physical-android-id>,<android-emulator-id> ' >&2
      printf '(fallbacks: FLUTTER_MULTI_DEVICE_IDS or comma-separated FLUTTER_DEVICE_ID).\n' >&2
      return 64
    fi
  done <"$active_plan_file"
}

print_command_for_path() {
  local kind="$1"
  local path="$2"
  local scenario="${3:-}"
  local device_id
  local mode
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
      if [ "${RELIABILITY_REUSE_BUILT_APP:-0}" = "1" ]; then
        printf ' --skip-build'
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
      print_device_arg_for_path "$path" "$scenario"
      if [ "${RELIABILITY_NOTIFICATION_SOUND_INTERACTIVE:-0}" != "1" ]; then
        printf ' --non-interactive'
      fi
      ;;
    integration_test/scripts/*.dart)
      printf 'dart run %s' "$path"
      if [ -n "$scenario" ]; then
        printf ' --scenario %s' "$(quote_for_display "$scenario")"
      fi
      mode="$(mode_arg_for_path "$path" "$scenario")"
      if [ -n "$mode" ]; then
        printf ' --mode %s' "$(quote_for_display "$mode")"
      fi
      print_device_arg_for_path "$path" "$scenario"
      platform="$(platform_arg_for_path "$path")"
      if [ -n "$platform" ]; then
        printf ' -p %s' "$(quote_for_display "$platform")"
      fi
      ;;
    integration_test/*.dart)
      printf 'flutter test --no-pub'
      device_id="$(single_device_id)"
      if [ -n "$device_id" ]; then
        printf ' -d %s' "$(quote_for_display "$device_id")"
      fi
      printf ' %s' "$(quote_for_display "--dart-define=MKNOON_RELAY_ADDRESSES=$(relay_addresses)")"
      if [ "$path" = "integration_test/group_lifecycle_simulator_harness.dart" ] && [ -n "$scenario" ]; then
        printf ' %s' "$(quote_for_display "--dart-define=GROUP_SIM_SCENARIO=$scenario")"
      fi
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
  local scenario="${3:-}"
  local -a cmd=()
  local device_id
  local mode
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
      if [ "${RELIABILITY_REUSE_BUILT_APP:-0}" = "1" ]; then
        cmd+=(--skip-build)
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
      if [ -n "$scenario" ]; then
        cmd+=(--scenario "$scenario")
      fi
      mode="$(mode_arg_for_path "$path" "$scenario")"
      if [ -n "$mode" ]; then
        cmd+=(--mode "$mode")
      fi
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
      cmd=(flutter test --no-pub)
      device_id="$(single_device_id)"
      if [ -n "$device_id" ]; then
        cmd+=(-d "$device_id")
      fi
      cmd+=("--dart-define=MKNOON_RELAY_ADDRESSES=$(relay_addresses)")
      if [ "$path" = "integration_test/group_lifecycle_simulator_harness.dart" ] && [ -n "$scenario" ]; then
        cmd+=("--dart-define=GROUP_SIM_SCENARIO=$scenario")
      fi
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
if [ "$simultaneous" -eq 1 ]; then
  printf 'Simultaneous policy: legacy reliability rows serialize; typed resource-aware overlap is owned by the sims manifest scheduler (compatibility max %s).\n' \
    "$max_parallel"
fi
group_multi_party_active_count="$(
  awk -F '\t' '
    $3 == "integration_test/scripts/run_group_multi_party_device_real.dart" {
      count++
    }
    END { print count + 0 }
  ' "$active_plan_file"
)"
if [ "$group_multi_party_active_count" -gt 0 ]; then
  group_multi_party_active_scenarios="$(
    awk -F '\t' '
      $3 == "integration_test/scripts/run_group_multi_party_device_real.dart" {
        if ($4 != "") {
          if (scenarios != "") scenarios = scenarios ","
          scenarios = scenarios $4
        }
      }
      END { print scenarios }
    ' "$active_plan_file"
  )"
  printf 'Group multi-party tier: %s (%s active plan row(s): %s; full remains nightly/release requirement)\n' \
    "$(group_multi_party_tier)" \
    "$group_multi_party_active_count" \
    "$group_multi_party_active_scenarios"
fi
if [ "$start_at" -ne 1 ]; then
  printf 'Resume filter: starting at planned item #%s\n' "$start_at"
fi
if [ -n "$only_selector" ]; then
  printf 'Resume filter: only %s\n' "$only_selector"
fi
command_count=0
while IFS=$'\t' read -r index kind path scenario; do
  [ -n "$kind" ] || continue
  command_count=$((command_count + 1))
  printf '  %2d. ' "$index"
  print_command_for_path "$kind" "$path" "$scenario"
  if [ "$simultaneous" -eq 1 ]; then
    printf ' [resource: %s]' "$(resource_class_for_path "$path")"
  fi
  printf '\n'
done <"$active_plan_file"

if [ "$dry_run" -eq 1 ]; then
  printf '\nDry run only. Discovery passed and no commands were executed.\n'
  exit 0
fi

validate_required_device_args

preflight_transport_census_processes() {
  local matches

  matches="$(
    ps -axo pid=,ppid=,stat=,etime=,command= |
      awk '
        /run_transport_census_cli\.dart|transport_census_harness\.dart|go-mknoon\/bin\/testpeer/ &&
        $0 !~ /awk / &&
        $0 !~ /ps -axo/ &&
        # Exclude git invocations: an IDE/git "diff"/"status" lists the changed
        # go-mknoon/bin/testpeer path as an argument, which is NOT an actual
        # testpeer node. Matching "[ /]git " covers both PATH git ("... git ")
        # and a full path ("/usr/bin/git ") without excluding real testpeer procs.
        $0 !~ /[ \/]git / {
          print
        }
      '
  )"

  if [ -n "$matches" ]; then
    printf '\nReliability preflight failed: transport census/testpeer processes are already running.\n' >&2
    printf 'These clients can consume relay capacity and make later group roles fail online readiness.\n' >&2
    printf 'Stop them before running reliability-sim:\n' >&2
    printf '%s\n' "$matches" >&2
    return 1
  fi
}

if [ -s "$serial_plan_file" ]; then
  preflight_transport_census_processes
fi

printf '\nRunning %s reliability simulation command(s)...\n' "$command_count"
if [ "$simultaneous" -eq 1 ]; then
  serial_count="$(awk 'END { print NR + 0 }' "$serial_plan_file")"
  parallel_count="$(awk 'END { print NR + 0 }' "$parallel_plan_file")"
  printf 'Schedule: %s exclusive legacy row(s), %s manifest-owned parallel row(s) in this compatibility runner (max %s).\n' \
    "$serial_count" "$parallel_count" "$max_parallel"
fi
# Read the plan on FD 3, not stdin: run_path executes real commands (e.g. smoke
# shell scripts that read stdin), and if the loop fed them from "$active_plan_file"
# on stdin they would consume the remaining plan lines — silently skipping the
# last item(s), e.g. the trailing intro smoke under --start-at.
while IFS=$'\t' read -r index kind path scenario <&3; do
  [ -n "$kind" ] || continue
  printf '\n==> #%s ' "$index"
  print_command_for_path "$kind" "$path" "$scenario"
  printf '\n'

  if run_path "$kind" "$path" "$scenario"; then
    if [ -n "$scenario" ]; then
      printf 'PASS: #%s %s --scenario %s\n' "$index" "$path" "$scenario"
    else
      printf 'PASS: #%s %s\n' "$index" "$path"
    fi
  else
    status=$?
    if [ -n "$scenario" ]; then
      printf 'FAIL: #%s %s --scenario %s exited with %s\n' "$index" "$path" "$scenario" "$status" >&2
      printf '%s\t%s --scenario %s\t%s\n' "$index" "$path" "$scenario" "$status" >>"$failures_file"
    else
      printf 'FAIL: #%s %s exited with %s\n' "$index" "$path" "$status" >&2
      printf '%s\t%s\t%s\n' "$index" "$path" "$status" >>"$failures_file"
    fi
    if [ "$continue_on_failure" -ne 1 ]; then
      exit "$status"
    fi
  fi
done 3<"$serial_plan_file"

run_parallel_batch() {
  local -a rows=("$@")
  local -a pids=()
  local -a log_files=()
  local -a indexes=()
  local -a paths=()
  local -a scenarios=()
  local row
  local index
  local kind
  local path
  local scenario
  local log_file
  local status
  local first_failure=0
  local i

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r index kind path scenario <<<"$row"
    log_file="$parallel_work_dir/$index.log"
    : >"$log_file"

    printf '\n==> #%s [parallel post-capture] ' "$index"
    print_command_for_path "$kind" "$path" "$scenario"
    printf '\n'

    (
      run_path "$kind" "$path" "$scenario"
    ) >"$log_file" 2>&1 &
    pids+=("$!")
    log_files+=("$log_file")
    indexes+=("$index")
    paths+=("$path")
    scenarios+=("$scenario")
  done

  for ((i = 0; i < ${#pids[@]}; i++)); do
    if wait "${pids[$i]}"; then
      status=0
    else
      status=$?
    fi

    if [ -s "${log_files[$i]}" ]; then
      cat "${log_files[$i]}"
    fi

    if [ "$status" -eq 0 ]; then
      if [ -n "${scenarios[$i]}" ]; then
        printf 'PASS: #%s %s --scenario %s\n' \
          "${indexes[$i]}" "${paths[$i]}" "${scenarios[$i]}"
      else
        printf 'PASS: #%s %s\n' "${indexes[$i]}" "${paths[$i]}"
      fi
      continue
    fi

    if [ -n "${scenarios[$i]}" ]; then
      printf 'FAIL: #%s %s --scenario %s exited with %s\n' \
        "${indexes[$i]}" "${paths[$i]}" "${scenarios[$i]}" "$status" >&2
      printf '%s\t%s --scenario %s\t%s\n' \
        "${indexes[$i]}" "${paths[$i]}" "${scenarios[$i]}" "$status" \
        >>"$failures_file"
    else
      printf 'FAIL: #%s %s exited with %s\n' \
        "${indexes[$i]}" "${paths[$i]}" "$status" >&2
      printf '%s\t%s\t%s\n' \
        "${indexes[$i]}" "${paths[$i]}" "$status" >>"$failures_file"
    fi
    if [ "$first_failure" -eq 0 ]; then
      first_failure="$status"
    fi
  done

  if [ "$first_failure" -ne 0 ] && [ "$continue_on_failure" -ne 1 ]; then
    return "$first_failure"
  fi
}

run_parallel_queue() {
  local -a batch=()
  local row
  local status

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    batch+=("$row")
    if [ "${#batch[@]}" -ge "$max_parallel" ]; then
      if run_parallel_batch "${batch[@]}"; then
        batch=()
      else
        status=$?
        return "$status"
      fi
    fi
  done <"$parallel_plan_file"

  if [ "${#batch[@]}" -gt 0 ]; then
    if run_parallel_batch "${batch[@]}"; then
      :
    else
      status=$?
      return "$status"
    fi
  fi
}

if [ -s "$parallel_plan_file" ]; then
  if run_parallel_queue; then
    :
  else
    status=$?
    exit "$status"
  fi
fi

failure_count="$(awk 'END { print NR + 0 }' "$failures_file")"
if [ "$failure_count" -gt 0 ]; then
  printf '\nReliability simulations failed (%s):\n' "$failure_count" >&2
  awk -F '\t' '{ printf "  - #%s %s exited with %s\n", $1, $2, $3 }' "$failures_file" >&2
  exit 1
fi

printf '\nPASS: reliability simulations completed for scope: %s\n' "$scope"
