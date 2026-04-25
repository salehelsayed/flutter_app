#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dry_run=0
run_ios=1
run_android=1
list_scenarios=0
ios_device="${SIMULATOR_DEVICE:-booted}"
ios_secondary_device="${IOS_SECONDARY_SIMULATOR_DEVICE:-}"
android_device="${ANDROID_SERIAL:-}"
android_package="${ANDROID_PACKAGE:-com.mknoon.app}"

usage() {
  cat <<'EOF'
Usage:
  scripts/smoke_test_push_decrypt_simulator.sh [--dry-run] [--ios-only] [--android-only] [--list-scenarios]

Runs the push-decrypt simulator smoke harness over the required plan-73
S-iOS-1..19 and S-And-1..19 scenario rows. In --dry-run mode it validates APNs
and Android injection payload generation without requiring booted devices or an
installed app.

Environment:
  SIMULATOR_DEVICE                 Primary iOS simulator target, defaults to booted
  IOS_SECONDARY_SIMULATOR_DEVICE   Secondary iOS simulator target for S-iOS-17..19
  IOS_BUNDLE_ID                    iOS bundle id, defaults in push_fixture_to_simulator.sh
  ANDROID_SERIAL                   Android emulator serial
  ANDROID_PACKAGE                  Android package, defaults to com.mknoon.app
EOF
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --ios-only)
      run_ios=1
      run_android=0
      shift
      ;;
    --android-only)
      run_ios=0
      run_android=1
      shift
      ;;
    --list-scenarios)
      list_scenarios=1
      shift
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

readonly IOS_SCENARIOS=(
  "S-iOS-1|one_to_one_text|primary|1:1 text decrypted preview"
  "S-iOS-2|one_to_one_media_audio|primary|1:1 media voice-note descriptor"
  "S-iOS-3|group_text|primary|group text with decrypted sender prefix"
  "S-iOS-4|group_media_image|primary|group media photo descriptor"
  "S-iOS-5|one_to_one_text|primary|missing shared key fallback"
  "S-iOS-6|one_to_one_corrupt_ciphertext|primary|corrupt ciphertext fallback"
  "S-iOS-7|one_to_one_tampered_signature|primary|tampered signature fallback"
  "S-iOS-8|unknown_envelope_kind|primary|unknown envelope kind fallback"
  "S-iOS-9|group_dissolve|primary|group dissolve preview"
  "S-iOS-10|one_to_one_long_text|primary|long text preview cap"
  "S-iOS-11|one_to_one_text|primary|1:1 thread identifier"
  "S-iOS-12|group_text|primary|group thread identifier"
  "S-iOS-13|one_to_one_text|primary|active 1:1 conversation suppression payload"
  "S-iOS-14|group_text|primary|active group conversation suppression payload"
  "S-iOS-15|one_to_one_long_text|primary|preview cap suffix payload"
  "S-iOS-16|forbidden_field_canary_text|primary|forbidden-field canary payload"
  "S-iOS-17|one_to_one_text|both|dual-simulator 1:1 receiver delivery"
  "S-iOS-18|one_to_one_text|both|dual-simulator same-user multi-device delivery"
  "S-iOS-19|group_text|both|dual-simulator group fan-out delivery"
)

readonly ANDROID_SCENARIOS=(
  "S-And-1|one_to_one_text|none|1:1 text decrypted preview"
  "S-And-2|one_to_one_media_audio|none|1:1 media voice-note descriptor"
  "S-And-3|group_text|none|group text with decrypted sender prefix"
  "S-And-4|group_media_image|none|group media photo descriptor"
  "S-And-5|one_to_one_text|none|missing shared key fallback"
  "S-And-6|one_to_one_corrupt_ciphertext|none|corrupt ciphertext fallback"
  "S-And-7|one_to_one_tampered_signature|none|tampered signature fallback"
  "S-And-8|unknown_envelope_kind|none|unknown envelope kind fallback"
  "S-And-9|group_dissolve|none|group dissolve preview"
  "S-And-10|one_to_one_long_text|none|long text preview cap"
  "S-And-11|one_to_one_text|none|1:1 thread identifier"
  "S-And-12|group_text|none|group thread identifier"
  "S-And-13|one_to_one_text|none|active 1:1 conversation suppression payload"
  "S-And-14|group_text|none|active group conversation suppression payload"
  "S-And-15|one_to_one_long_text|none|preview cap suffix payload"
  "S-And-16|forbidden_field_canary_text|none|forbidden-field canary payload"
  "S-And-17|post_phase1_chat_text|none|FCM data-only wake payload"
  "S-And-18|pre_phase1_group_text_legacy|none|legacy plaintext dual-tolerance payload"
  "S-And-19|one_to_one_text|force_stop|background isolate cold-start payload"
)

verify_inventory() {
  local prefix="$1"
  shift
  local -a entries=("$@")
  local expected id found entry

  for expected in $(seq 1 19); do
    id="$prefix-$expected"
    found=0
    for entry in "${entries[@]}"; do
      if [[ "$entry" == "$id|"* ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -ne 1 ]]; then
      printf 'Missing required smoke scenario row: %s\n' "$id" >&2
      return 1
    fi
  done
}

list_scenario_entries() {
  local platform="$1"
  shift
  local entry scenario fixture target note

  for entry in "$@"; do
    IFS='|' read -r scenario fixture target note <<<"$entry"
    printf '%s\t%s\t%s\t%s\t%s\n' "$platform" "$scenario" "$fixture" "$target" "$note"
  done
}

run_injection() {
  local platform="$1"
  local scenario="$2"
  local fixture="$3"
  local target="${4:-}"
  local -a cmd=()

  case "$platform" in
    ios)
      cmd=("$ROOT_DIR/scripts/push_fixture_to_simulator.sh")
      if [[ -n "$target" ]]; then
        cmd+=(--device "$target")
      fi
      ;;
    android)
      cmd=("$ROOT_DIR/scripts/push_fixture_to_android_emulator.sh")
      if [[ -n "$android_device" ]]; then
        cmd+=(--device "$android_device")
      fi
      if [[ -n "$android_package" ]]; then
        cmd+=(--package "$android_package")
      fi
      ;;
    *)
      printf 'Unknown platform: %s\n' "$platform" >&2
      return 2
      ;;
  esac

  if [[ "$dry_run" -eq 1 ]]; then
    cmd+=(--dry-run)
  fi

  cmd+=("$fixture")

  if [[ -n "$target" ]]; then
    printf 'Running %s %s on %s with fixture %s\n' "$platform" "$scenario" "$target" "$fixture"
  else
    printf 'Running %s %s with fixture %s\n' "$platform" "$scenario" "$fixture"
  fi
  "${cmd[@]}"
}

resolve_adb() {
  local candidate

  if [[ -n "${ANDROID_ADB:-}" ]]; then
    [[ -x "$ANDROID_ADB" ]] || {
      printf 'ANDROID_ADB is not executable: %s\n' "$ANDROID_ADB" >&2
      return 1
    }
    printf '%s\n' "$ANDROID_ADB"
    return 0
  fi

  if candidate="$(command -v adb 2>/dev/null)"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "/usr/local/share/android-sdk/platform-tools/adb" \
    "/opt/homebrew/share/android-sdk/platform-tools/adb"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'adb not found; set ANDROID_ADB or add platform-tools to PATH.\n' >&2
  return 1
}

run_ios_scenario() {
  local scenario="$1"
  local fixture="$2"
  local target_spec="$3"
  local note="$4"

  printf 'Scenario %s: %s\n' "$scenario" "$note"
  case "$target_spec" in
    primary)
      run_injection ios "$scenario" "$fixture" "$ios_device"
      ;;
    both)
      if [[ -z "$ios_secondary_device" && "$dry_run" -eq 0 ]]; then
        printf '%s requires IOS_SECONDARY_SIMULATOR_DEVICE for non-dry-run dual-simulator coverage.\n' "$scenario" >&2
        return 1
      fi
      run_injection ios "$scenario" "$fixture" "$ios_device"
      if [[ -n "$ios_secondary_device" ]]; then
        run_injection ios "$scenario" "$fixture" "$ios_secondary_device"
      else
        printf 'Dry-run note: %s also targets IOS_SECONDARY_SIMULATOR_DEVICE when set.\n' "$scenario"
      fi
      ;;
    *)
      printf 'Unknown iOS target spec for %s: %s\n' "$scenario" "$target_spec" >&2
      return 2
      ;;
  esac
}

run_android_scenario() {
  local scenario="$1"
  local fixture="$2"
  local action="$3"
  local note="$4"
  local -a adb_cmd=()

  printf 'Scenario %s: %s\n' "$scenario" "$note"
  if [[ "$action" == "force_stop" && "$dry_run" -eq 0 ]]; then
    adb_cmd=("$(resolve_adb)")
    if [[ -n "$android_device" ]]; then
      adb_cmd+=(-s "$android_device")
    fi
    "${adb_cmd[@]}" shell am force-stop "$android_package"
  elif [[ "$action" != "none" && "$action" != "force_stop" ]]; then
    printf 'Unknown Android pre-action for %s: %s\n' "$scenario" "$action" >&2
    return 2
  fi

  run_injection android "$scenario" "$fixture"
}

verify_inventory "S-iOS" "${IOS_SCENARIOS[@]}"
verify_inventory "S-And" "${ANDROID_SCENARIOS[@]}"

if [[ "$list_scenarios" -eq 1 ]]; then
  if [[ "$run_ios" -eq 1 ]]; then
    list_scenario_entries ios "${IOS_SCENARIOS[@]}"
  fi
  if [[ "$run_android" -eq 1 ]]; then
    list_scenario_entries android "${ANDROID_SCENARIOS[@]}"
  fi
  exit 0
fi

if [[ "$run_ios" -eq 1 ]]; then
  for entry in "${IOS_SCENARIOS[@]}"; do
    IFS='|' read -r scenario fixture target note <<<"$entry"
    run_ios_scenario "$scenario" "$fixture" "$target" "$note"
  done
fi

if [[ "$run_android" -eq 1 ]]; then
  for entry in "${ANDROID_SCENARIOS[@]}"; do
    IFS='|' read -r scenario fixture action note <<<"$entry"
    run_android_scenario "$scenario" "$fixture" "$action" "$note"
  done
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Dry-run smoke completed for the full S-iOS-1..19 / S-And-1..19 fixture map. Full OS delivery requires booted simulator/emulator targets with the app installed.\n'
fi
