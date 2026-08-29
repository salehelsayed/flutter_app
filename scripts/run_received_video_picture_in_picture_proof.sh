#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

platform=""
scenario=""
device=""
production_package="com.mknoon.app"
package_name="com.mknoon.app.pipproof"
output_dir=""
dry_run=false
allow_production_package_destruction=false

fixture="integration_test/fixtures/received_video_picture_in_picture_fixture.mp4"
fixture_sha256="d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5"
fixture_bytes="2463571"
fixture_duration="72.000000"
target="integration_test/received_video_picture_in_picture_proof_test.dart"
process_recreation_driver="test_driver/integration_test.dart"
PIP_MENU_ACTION_LATENCY_BUDGET_MS=750
PIP_MENU_ANIMATION_SETTLE_SECONDS=0.125
PIP_MENU_INPUT_TARGET='Embedded{PipMenuView}'

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_received_video_picture_in_picture_proof.sh \
    --platform android \
    --scenario <return|close|process-recreation|completion|engine-detach|interruption> \
    --device <explicit-adb-id> [--package <disposable-application-id>] \
    [--allow-production-package-destruction] [--output <dir>] [--dry-run]

Path 3 is Android-only. iOS and every other platform are rejected without
building, installing, querying, or driving a target.

The default application ID is disposable. The production application ID is
rejected unless explicitly acknowledged, and even then a pre-existing install
is never replaced or removed.
EOF
}

while (($# > 0)); do
  case "$1" in
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --scenario)
      scenario="${2:-}"
      shift 2
      ;;
    --device)
      device="${2:-}"
      shift 2
      ;;
    --package)
      package_name="${2:-}"
      shift 2
      ;;
    --output)
      output_dir="${2:-}"
      shift 2
      ;;
    --allow-production-package-destruction)
      allow_production_package_destruction=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
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

if [[ "$platform" != "android" ]]; then
  echo "Path 3 permits only --platform android; no Apple/other PiP proof is in scope." >&2
  exit 2
fi
case "$scenario" in
  return|close|process-recreation|completion|engine-detach|interruption) ;;
  *)
    echo "An exact supported --scenario is required." >&2
    exit 2
    ;;
esac
if [[ -z "$device" || "$device" == "-" ]]; then
  echo "A nonempty explicit --device ID is required." >&2
  exit 2
fi
if [[ ! "$package_name" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]; then
  echo "The Android application ID is malformed." >&2
  exit 2
fi
if [[ "$package_name" == "$production_package" && "$allow_production_package_destruction" != true ]]; then
  echo "The production application ID is forbidden for disposable PiP proof installs." >&2
  echo "Use the default proof ID, or explicitly acknowledge the destructive namespace override." >&2
  exit 2
fi
if [[ ! -f "$fixture" ]]; then
  echo "Reviewed PiP fixture is absent: $fixture" >&2
  exit 1
fi
if [[ "$scenario" == "process-recreation" && ! -f "$process_recreation_driver" ]]; then
  echo "Process-recreation integration driver is absent: $process_recreation_driver" >&2
  exit 1
fi

actual_sha256="$(shasum -a 256 "$fixture" | awk '{print $1}')"
actual_bytes="$(stat -f '%z' "$fixture" 2>/dev/null || stat -c '%s' "$fixture")"
if [[ "$actual_sha256" != "$fixture_sha256" || "$actual_bytes" != "$fixture_bytes" ]]; then
  echo "Reviewed PiP fixture hash/size mismatch." >&2
  exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe is required to bind the reviewed fixture duration." >&2
  exit 1
fi
actual_duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$fixture")"
if [[ "$actual_duration" != "$fixture_duration" ]]; then
  echo "Reviewed PiP fixture duration mismatch." >&2
  exit 1
fi

if [[ -z "$output_dir" ]]; then
  output_dir="build/received-video-pip-proof/${scenario}-$(date -u +%Y%m%dT%H%M%SZ)"
fi

if [[ "$dry_run" == true ]]; then
  printf 'DRY_RUN platform=%s scenario=%s device=%s package=%s\n' \
    "$platform" "$scenario" "$device" "$package_name"
  printf 'fixtureSha256=%s fixtureBytes=%s fixtureDuration=%s\n' \
    "$actual_sha256" "$actual_bytes" "$actual_duration"
  printf 'target=%s output=%s\n' "$target" "$output_dir"
  if [[ "$scenario" == "process-recreation" ]]; then
    printf 'ORG_GRADLE_PROJECT_androidApplicationId=%q ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false flutter drive -d %q --keep-app-running --driver %q --target %q --dart-define=PIP_PROOF_PLATFORM=android --dart-define=PIP_PROOF_SCENARIO=%q --dart-define=PIP_PROOF_PACKAGE=%q\n' \
      "$package_name" "$device" "$process_recreation_driver" "$target" "$scenario" "$package_name"
  elif [[ "$scenario" == "engine-detach" ]]; then
    printf 'ORG_GRADLE_PROJECT_androidApplicationId=%q ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=true ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false flutter test -d %q --dart-define=PIP_PROOF_PLATFORM=android --dart-define=PIP_PROOF_SCENARIO=%q %q\n' \
      "$package_name" "$device" "$scenario" "$target"
  elif [[ "$scenario" == "interruption" ]]; then
    printf 'ORG_GRADLE_PROJECT_androidApplicationId=%q ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=true flutter test -d %q --dart-define=PIP_PROOF_PLATFORM=android --dart-define=PIP_PROOF_SCENARIO=%q %q\n' \
      "$package_name" "$device" "$scenario" "$target"
  else
    printf 'ORG_GRADLE_PROJECT_androidApplicationId=%q ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false flutter test -d %q --dart-define=PIP_PROOF_PLATFORM=android --dart-define=PIP_PROOF_SCENARIO=%q %q\n' \
      "$package_name" "$device" "$scenario" "$target"
  fi
  exit 0
fi

for command_name in adb dart flutter shasum awk sed grep sort python3 stat; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command_name" >&2
    exit 1
  fi
done

device_rows="$(adb devices | awk -v id="$device" '$1 == id { print $2 }')"
if [[ "$(printf '%s\n' "$device_rows" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" || "$device_rows" != "device" ]]; then
  echo "Explicit Android target is not uniquely connected and ready: $device" >&2
  exit 1
fi
if [[ "$(adb -s "$device" get-state 2>/dev/null | tr -d '\r')" != "device" || \
      "$(adb -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
  echo "Explicit Android target is not adb-ready and boot-complete: $device" >&2
  exit 1
fi
android_sdk="$(adb -s "$device" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
if [[ ! "$android_sdk" =~ ^[0-9]+$ || "$android_sdk" -lt 26 ]]; then
  echo "Android PiP proof requires an available API 26+ target; observed API: $android_sdk" >&2
  exit 1
fi
if ! adb -s "$device" shell pm list features 2>/dev/null | tr -d '\r' | \
    grep -Fxq 'feature:android.software.picture_in_picture'; then
  echo "Android target does not advertise android.software.picture_in_picture." >&2
  exit 1
fi
proof_device_codename="$(adb -s "$device" shell getprop ro.product.device | tr -d '\r')"
proof_device_model="$(adb -s "$device" shell getprop ro.product.model | tr -d '\r')"
proof_wm_size="$(adb -s "$device" shell wm size | tr -d '\r')"
proof_wm_density="$(adb -s "$device" shell wm density | tr -d '\r')"
proof_display_width="$(sed -n 's/^Physical size: \([0-9][0-9]*\)x[0-9][0-9]*$/\1/p' <<<"$proof_wm_size")"
proof_display_height="$(sed -n 's/^Physical size: [0-9][0-9]*x\([0-9][0-9]*\)$/\1/p' <<<"$proof_wm_size")"
proof_display_density="$(sed -n 's/^Physical density: \([0-9][0-9]*\)$/\1/p' <<<"$proof_wm_density")"
proof_display_rotation="$(adb -s "$device" shell dumpsys display | \
  sed -n 's/.*mCurrentOrientation=\([0-9][0-9]*\).*/\1/p' | head -n 1)"

proof_test_package="${package_name}.test"
interruption_helper_class="com.mknoon.app.pipproof.PictureInPictureAudioFocusInterruptionProofActivity"
interruption_helper_component="$proof_test_package/$interruption_helper_class"
for candidate_package in "$package_name" "$proof_test_package"; do
  if adb -s "$device" shell pm path "$candidate_package" 2>/dev/null | grep -q '^package:'; then
    echo "Refusing PiP proof because $candidate_package is already installed on $device." >&2
    echo "The harness never replaces or uninstalls a pre-existing app." >&2
    exit 1
  fi
done

apksigner_bin="$(command -v apksigner 2>/dev/null || true)"
if [[ -z "$apksigner_bin" ]]; then
  android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "$android_sdk_root" && -d "$android_sdk_root/build-tools" ]]; then
    apksigner_bin="$(find "$android_sdk_root/build-tools" -type f -name apksigner 2>/dev/null | sort | tail -n 1)"
  fi
fi
if [[ -z "$apksigner_bin" ]]; then
  echo "Android apksigner is required to verify the disposable installed identity." >&2
  exit 1
fi
aapt_bin="$(command -v aapt 2>/dev/null || true)"
if [[ -z "$aapt_bin" ]]; then
  android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "$android_sdk_root" && -d "$android_sdk_root/build-tools" ]]; then
    aapt_bin="$(find "$android_sdk_root/build-tools" -type f -name aapt 2>/dev/null | sort | tail -n 1)"
  fi
fi
if [[ "$scenario" == "interruption" && -z "$aapt_bin" ]]; then
  echo "Android aapt is required to verify the interruption helper APK." >&2
  exit 1
fi

mkdir -p "$output_dir"
python_cache_dir="$output_dir/python-cache-${$}"
mkdir -p "$python_cache_dir"
export PYTHONPYCACHEPREFIX="$python_cache_dir"
flutter_log="$output_dir/flutter-test.log"
host_log="$output_dir/host.log"
remote_tmp="/data/local/tmp/mknoon-pip-proof-${$}.mp4"
pip_menu_remote_xml="/sdcard/mknoon-pip-menu-${$}.xml"
app_fixture="app_flutter/media/plan243-proof/received_video_picture_in_picture_fixture.mp4"
flutter_pid=""
test_install_started=false
installed_apk_copy=""
helper_installed_apk_copy=""
uid=""
interruption_helper_uid=""

cleanup() {
  local primary_exit=$?
  local cleanup_exit=0
  local cleanup_failed=false
  if [[ -n "$flutter_pid" ]]; then
    if kill -0 "$flutter_pid" 2>/dev/null; then
      kill "$flutter_pid" 2>/dev/null || true
    fi
    wait "$flutter_pid" 2>/dev/null || true
    flutter_pid=""
  fi
  if [[ "$test_install_started" == true ]]; then
    adb -s "$device" shell am force-stop "$package_name" >/dev/null 2>&1 || true
    adb -s "$device" shell am force-stop "$proof_test_package" >/dev/null 2>&1 || true
    adb -s "$device" uninstall "$package_name" >/dev/null 2>&1 || true
    adb -s "$device" uninstall "$proof_test_package" >/dev/null 2>&1 || true
    for candidate_package in "$package_name" "$proof_test_package"; do
      if adb -s "$device" shell pm path "$candidate_package" 2>/dev/null | grep -q '^package:'; then
        cleanup_failed=true
      fi
    done
    if [[ "$scenario" == "interruption" && \
          "$uid" =~ ^[0-9]+$ && \
          "$interruption_helper_uid" =~ ^[0-9]+$ ]]; then
      local cleanup_focus_settled=false
      local cleanup_audio="$output_dir/interruption-cleanup-audio.txt"
      local cleanup_audio_error="$output_dir/interruption-cleanup-audio-stderr.txt"
      local cleanup_focus_result="$output_dir/interruption-cleanup-focus.txt"
      local cleanup_focus_error="$output_dir/interruption-cleanup-focus-error.txt"
      local cleanup_attempt
      for cleanup_attempt in $(seq 1 50); do
        if adb -s "$device" shell dumpsys audio \
            >"$cleanup_audio" 2>"$cleanup_audio_error" && \
           [[ ! -s "$cleanup_audio_error" ]] && \
           python3 scripts/validate_android_picture_in_picture_interruption_cleanup.py \
             --audio "$cleanup_audio" \
             --app-package "$package_name" \
             --helper-package "$proof_test_package" \
             --app-uid "$uid" \
             --helper-uid "$interruption_helper_uid" \
             --output "$cleanup_focus_result" \
             >/dev/null 2>"$cleanup_focus_error"; then
          cleanup_focus_settled=true
          break
        fi
        sleep 0.1
      done
      if [[ "$cleanup_focus_settled" != true ]]; then
        cleanup_failed=true
      else
        cat "$cleanup_focus_result" >>"$host_log"
      fi
    fi
  fi
  adb -s "$device" shell rm -f \
    "$remote_tmp" "$pip_menu_remote_xml" \
    >/dev/null 2>&1 || true
  if [[ -n "$installed_apk_copy" ]]; then
    rm -f "$installed_apk_copy"
  fi
  if [[ -n "$helper_installed_apk_copy" ]]; then
    rm -f "$helper_installed_apk_copy"
  fi
  cleanup_verified=true
  if [[ "$cleanup_failed" == true ]]; then
    cleanup_verified=false
    cleanup_exit=1
  fi
  final_exit="$primary_exit"
  if [[ "$final_exit" == 0 && "$cleanup_exit" != 0 ]]; then
    final_exit="$cleanup_exit"
  fi
  printf 'primaryExit=%s cleanupExit=%s cleanupVerified=%s\n' \
    "$primary_exit" "$cleanup_exit" "$cleanup_verified" >>"$host_log"
  trap - EXIT INT TERM
  exit "$final_exit"
}
trap cleanup EXIT INT TERM

wait_for_flutter_shutdown() {
  local attempts="$1"
  local delay="$2"
  local i
  local status
  if [[ -z "$flutter_pid" ]]; then
    return 0
  fi
  for ((i = 0; i < attempts; i++)); do
    if ! kill -0 "$flutter_pid" 2>/dev/null; then
      break
    fi
    sleep "$delay"
  done
  if kill -0 "$flutter_pid" 2>/dev/null; then
    return 124
  fi
  wait "$flutter_pid"
  status=$?
  flutter_pid=""
  return "$status"
}

wait_for_log() {
  local needle="$1"
  local attempts="$2"
  local delay="$3"
  local i
  for ((i = 0; i < attempts; i++)); do
    if grep -Fq "$needle" "$flutter_log" 2>/dev/null || \
       adb -s "$device" logcat -d -v brief 2>/dev/null | grep -Fq "$needle"; then
      return 0
    fi
    if [[ -n "$flutter_pid" ]] && ! kill -0 "$flutter_pid" 2>/dev/null; then
      wait "$flutter_pid" 2>/dev/null || true
      flutter_pid=""
      echo "Flutter proof process exited before marker: $needle" >&2
      tail -n 120 "$flutter_log" >&2 || true
      return 1
    fi
    sleep "$delay"
  done
  echo "Timed out waiting for marker: $needle" >&2
  tail -n 120 "$flutter_log" >&2 || true
  return 1
}

monotonic_ms() {
  python3 -c 'import time; print(time.monotonic_ns() // 1000000)'
}

read_pip_menu_visibility() {
  local activities
  local input_targets
  local input_target_count
  if ! activities="$(adb -s "$device" shell dumpsys activity activities 2>/dev/null | tr -d '\r')"; then
    return 1
  fi
  input_targets="$(sed -n 's/^[[:space:]]*mImeInputTarget=//p' <<<"$activities")"
  input_target_count="$(printf '%s\n' "$input_targets" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$input_target_count" != "1" ]]; then
    return 1
  fi
  if [[ "$input_targets" == "$PIP_MENU_INPUT_TARGET" ]]; then
    printf 'visible\n'
  else
    printf 'hidden\n'
  fi
}

PIP_MENU_VISIBILITY_OBSERVED_MS=""
wait_for_pip_menu_visibility() {
  local expected="$1"
  local attempts="$2"
  local delay="$3"
  local evidence_log="$4"
  local observed
  local observed_ms
  local i
  for ((i = 0; i < attempts; i++)); do
    observed_ms="$(monotonic_ms)"
    if observed="$(read_pip_menu_visibility)"; then
      printf 'elapsedMs=%s expected=%s observed=%s signal=%s\n' \
        "$observed_ms" "$expected" "$observed" "$PIP_MENU_INPUT_TARGET" \
        >>"$evidence_log"
      if [[ "$observed" == "$expected" ]]; then
        PIP_MENU_VISIBILITY_OBSERVED_MS="$observed_ms"
        return 0
      fi
    else
      printf 'elapsedMs=%s expected=%s observed=unknown signal=%s\n' \
        "$observed_ms" "$expected" "$PIP_MENU_INPUT_TARGET" \
        >>"$evidence_log"
    fi
    sleep "$delay"
  done
  return 1
}

wait_for_exact_pinned_task_absent() {
  local task_id="$1"
  local attempts="$2"
  local delay="$3"
  local activities_file="$4"
  local i
  for ((i = 0; i < attempts; i++)); do
    if ! adb -s "$device" shell dumpsys activity activities >"$activities_file"; then
      return 1
    fi
    if ! grep -Eq "Task\\{[^#]*#${task_id}[[:space:]].*mode=pinned" "$activities_file"; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

capture_state() {
  local label="$1"
  adb -s "$device" shell dumpsys activity activities >"$output_dir/$label-activities.txt"
  adb -s "$device" shell dumpsys window windows >"$output_dir/$label-windows.txt"
  adb -s "$device" shell dumpsys audio >"$output_dir/$label-audio.txt"
  adb -s "$device" shell dumpsys SurfaceFlinger --list >"$output_dir/$label-surfaces.txt"
  adb -s "$device" exec-out screencap -p >"$output_dir/$label.png"
}

assert_no_pinned_owner() {
  local activities_file="$1"
  if grep -A20 -B5 -F 'ReceivedVideoPictureInPictureActivity' "$activities_file" | grep -q 'mode=pinned'; then
    echo "Dedicated PiP owner remained pinned after terminal settlement." >&2
    return 1
  fi
}

select_and_tap_pip_system_ui_control() {
  local action="$1"
  local pre_action_task_id="$2"
  local left="$3"
  local top="$4"
  local right="$5"
  local bottom="$6"
  local pre_reveal_bounds="$left $top $right $bottom"
  local reveal_x=$(((left + right) / 2))
  local reveal_y=$(((top + bottom) / 2))
  local post_reveal_activities="$output_dir/native-post-reveal-activities.txt"
  local post_reveal_pinned_task="$output_dir/native-post-reveal-pinned-task.txt"
  local post_reveal_task_ids
  local post_reveal_native_count
  local post_reveal_flutter_count
  local post_reveal_bounds_line
  local post_reveal_coordinates
  local hierarchy="$output_dir/native-active-pip-menu.xml"
  local dump_log="$output_dir/native-active-pip-menu-dump.txt"
  local menu_screenshot="$output_dir/native-active-pip-menu.png"
  local selection_json="$output_dir/native-active-pip-${action}-selection.json"
  local selection_normalized="$output_dir/native-active-pip-${action}-selection.txt"
  local selection_cli_log="$output_dir/native-active-pip-${action}-selection-cli.log"
  local selection_error="$output_dir/native-active-pip-${action}-selection-error.txt"
  local device_codename
  local device_model
  local wm_size
  local wm_density
  local display_width
  local display_height
  local display_density
  local display_rotation
  local use_pixel6_geometry=false
  local selector_source
  local resource_id
  local content_description
  local control_bounds
  local geometry_evidence
  local center
  local center_x
  local center_y
  local parser_status
  local validator_status
  local selection_link_count
  local pip_menu_visibility_log
  local pip_menu_validation_start_ms
  local pip_menu_validated_ms
  local pip_menu_validation_latency_ms
  local pip_menu_hidden_ms
  local action_ready_activities
  local action_ready_pinned_task
  local action_ready_task_ids
  local action_ready_native_count
  local action_ready_flutter_count
  local action_ready_bounds_line
  local action_ready_coordinates
  local pip_menu_action_reveal_ms
  local pip_menu_visible_ms
  local pip_menu_action_tap_ms
  local pip_menu_reveal_to_tap_ms
  local post_action_activities
  local native_action_terminal_marker

  device_codename="$proof_device_codename"
  device_model="$proof_device_model"
  wm_size="$proof_wm_size"
  wm_density="$proof_wm_density"
  display_width="$proof_display_width"
  display_height="$proof_display_height"
  display_density="$proof_display_density"
  display_rotation="$proof_display_rotation"
  if [[ "$device_codename" == "oriole" && \
        "$device_model" == "Pixel 6" && \
        "$android_sdk" == "36" && \
        "$wm_size" == "Physical size: 1080x2400" && \
        "$wm_density" == "Physical density: 420" && \
        "$display_rotation" == "0" ]]; then
    use_pixel6_geometry=true
  fi

  pip_menu_visibility_log="$output_dir/native-pip-menu-visibility.log"
  pip_menu_validation_start_ms="$(monotonic_ms)"
  adb -s "$device" shell input tap "$reveal_x" "$reveal_y"
  sleep 0.8
  adb -s "$device" shell dumpsys activity activities >"$post_reveal_activities"
  awk '
    /^[[:space:]]*\* Task\{/ {
      if (in_task && pinned) printf "%s", block
      in_task = 1
      pinned = 0
      block = ""
    }
    in_task {
      block = block $0 ORS
      if ($0 ~ /mode=pinned/) pinned = 1
    }
    END {
      if (in_task && pinned) printf "%s", block
    }
  ' "$post_reveal_activities" >"$post_reveal_pinned_task"
  post_reveal_task_ids="$(sed -nE \
    's/.*Task\{[^#]*#([0-9]+).*mode=pinned.*/\1/p' \
    "$post_reveal_pinned_task" | sort -u)"
  post_reveal_native_count="$(grep -Fc "$native_component" "$post_reveal_pinned_task" || true)"
  post_reveal_flutter_count="$(grep -Fc "$flutter_component" "$post_reveal_pinned_task" || true)"
  if [[ "$post_reveal_task_ids" != "$pre_action_task_id" || \
        ! -s "$post_reveal_pinned_task" || \
        "$post_reveal_native_count" -lt 1 || \
        "$post_reveal_flutter_count" -ne 0 ]]; then
    echo "The post-reveal task did not match the unique dedicated pre-action PiP owner." >&2
    return 1
  fi
  post_reveal_bounds_line="$(awk \
    '/mode=pinned/{p=1} p && /mBounds=Rect/{print; exit}' \
    "$post_reveal_pinned_task")"
  post_reveal_coordinates="$(sed -E \
    's/.*Rect\(([0-9]+), ([0-9]+) - ([0-9]+), ([0-9]+)\).*/\1 \2 \3 \4/' \
    <<<"$post_reveal_bounds_line")"
  if [[ ! "$post_reveal_coordinates" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]]; then
    echo "Could not parse the post-reveal live pinned PiP bounds." >&2
    return 1
  fi
  read -r left top right bottom <<<"$post_reveal_coordinates"
  adb -s "$device" exec-out screencap -p >"$menu_screenshot"
  printf 'preRevealBounds=%s postRevealBounds=%s postRevealTaskId=%s\n' \
    "$pre_reveal_bounds" "$post_reveal_coordinates" "$post_reveal_task_ids" \
    >>"$host_log"
  set +e
  if [[ "$use_pixel6_geometry" == true ]]; then
    dart run \
      integration_test/scripts/select_android_picture_in_picture_pixel6_api36_geometry.dart \
      "$action" "$menu_screenshot" "$left" "$top" "$right" "$bottom" \
      "$device_codename" "$device_model" "$android_sdk" \
      "$display_width" "$display_height" "$display_density" "$display_rotation" \
      --output "$selection_json" \
      >"$selection_cli_log" 2>"$selection_error"
    parser_status=$?
  else
    if adb -s "$device" shell uiautomator dump "$pip_menu_remote_xml" \
      >"$dump_log" 2>&1; then
      adb -s "$device" exec-out cat "$pip_menu_remote_xml" >"$hierarchy"
      adb -s "$device" shell rm -f "$pip_menu_remote_xml" >/dev/null 2>&1 || true
      dart run \
        integration_test/scripts/select_android_picture_in_picture_system_ui_control.dart \
        "$action" "$hierarchy" "$left" "$top" "$right" "$bottom" \
        --output "$selection_json" \
        >"$selection_cli_log" 2>"$selection_error"
      parser_status=$?
    else
      parser_status=3
      echo "Could not capture the revealed Android SystemUI PiP menu hierarchy." \
        >"$selection_error"
    fi
  fi
  set -e
  if [[ "$parser_status" != 0 ]]; then
    cat "$selection_error" >&2 || true
    echo "Refusing an unverified Android SystemUI PiP control coordinate." >&2
    return 1
  fi

  if [[ ! -f "$selection_json" || -L "$selection_json" ]]; then
    echo "Selector did not create one regular structured result file." >&2
    return 1
  fi
  selection_link_count="$(stat -f '%l' "$selection_json" 2>/dev/null || \
    stat -c '%h' "$selection_json")"
  if [[ "$selection_link_count" != 1 ]]; then
    echo "Selector result must be a single-link regular file." >&2
    return 1
  fi
  set +e
  python3 scripts/validate_android_picture_in_picture_system_ui_selection.py \
    "$selection_json" "$selection_normalized" \
    >>"$selection_cli_log" 2>>"$selection_error"
  validator_status=$?
  set -e
  if [[ "$validator_status" != 0 ]]; then
    cat "$selection_error" >&2 || true
    echo "Structured SystemUI PiP control selection failed exact validation." >&2
    return 1
  fi

  selector_source="$(sed -n 's/^selectorSource=//p' "$selection_normalized")"
  resource_id="$(sed -n 's/^resourceId=//p' "$selection_normalized")"
  content_description="$(sed -n 's/^contentDescription=//p' "$selection_normalized")"
  control_bounds="$(sed -n 's/^bounds=//p' "$selection_normalized")"
  geometry_evidence="$(sed -n 's/^geometryEvidence=//p' "$selection_normalized")"
  center="$(sed -n 's/^center=//p' "$selection_normalized")"
  if [[ "$(wc -l <"$selection_normalized" | tr -d ' ')" != 6 || \
        "$(grep -c '^selectorSource=' "$selection_normalized")" != 1 || \
        "$(grep -c '^resourceId=' "$selection_normalized")" != 1 || \
        "$(grep -c '^contentDescription=' "$selection_normalized")" != 1 || \
        "$(grep -c '^bounds=' "$selection_normalized")" != 1 || \
        "$(grep -c '^center=' "$selection_normalized")" != 1 || \
        "$(grep -c '^geometryEvidence=' "$selection_normalized")" != 1 || \
        ! "$center" =~ ^[0-9]+\ [0-9]+$ || \
        -z "$selector_source" || -z "$control_bounds" ]]; then
    echo "SystemUI PiP control selection output was incomplete or ambiguous." >&2
    return 1
  fi
  read -r center_x center_y <<<"$center"
  pip_menu_validated_ms="$(monotonic_ms)"
  pip_menu_validation_latency_ms=$((pip_menu_validated_ms - pip_menu_validation_start_ms))
  printf 'pipSystemUiAction=%s selectorSource=%s resourceId=%s contentDescription=%q controlBounds=%s action=%s,%s geometryEvidence=%s\n' \
    "$action" "$selector_source" "$resource_id" "$content_description" \
    "$control_bounds" "$center_x" "$center_y" "$geometry_evidence" >>"$host_log"
  printf 'pipMenuValidationStartMs=%s pipMenuValidatedMs=%s pipMenuValidationLatencyMs=%s\n' \
    "$pip_menu_validation_start_ms" "$pip_menu_validated_ms" \
    "$pip_menu_validation_latency_ms" >>"$host_log"

  if ! wait_for_pip_menu_visibility hidden 60 0.1 "$pip_menu_visibility_log"; then
    echo "The validated SystemUI PiP menu did not become unambiguously hidden." >&2
    return 1
  fi
  pip_menu_hidden_ms="$PIP_MENU_VISIBILITY_OBSERVED_MS"

  action_ready_activities="$output_dir/native-action-ready-activities.txt"
  action_ready_pinned_task="$output_dir/native-action-ready-pinned-task.txt"
  adb -s "$device" shell dumpsys activity activities >"$action_ready_activities"
  awk '
    /^[[:space:]]*\* Task\{/ {
      if (in_task && pinned) printf "%s", block
      in_task = 1
      pinned = 0
      block = ""
    }
    in_task {
      block = block $0 ORS
      if ($0 ~ /mode=pinned/) pinned = 1
    }
    END {
      if (in_task && pinned) printf "%s", block
    }
  ' "$action_ready_activities" >"$action_ready_pinned_task"
  action_ready_task_ids="$(sed -nE \
    's/.*Task\{[^#]*#([0-9]+).*mode=pinned.*/\1/p' \
    "$action_ready_pinned_task" | sort -u)"
  action_ready_native_count="$(grep -Fc "$native_component" "$action_ready_pinned_task" || true)"
  action_ready_flutter_count="$(grep -Fc "$flutter_component" "$action_ready_pinned_task" || true)"
  action_ready_bounds_line="$(awk \
    '/mode=pinned/{p=1} p && /mBounds=Rect/{print; exit}' \
    "$action_ready_pinned_task")"
  action_ready_coordinates="$(sed -E \
    's/.*Rect\(([0-9]+), ([0-9]+) - ([0-9]+), ([0-9]+)\).*/\1 \2 \3 \4/' \
    <<<"$action_ready_bounds_line")"
  if [[ "$action_ready_task_ids" != "$pre_action_task_id" || \
        ! -s "$action_ready_pinned_task" || \
        "$action_ready_native_count" -lt 1 || \
        "$action_ready_flutter_count" -ne 0 || \
        ! "$action_ready_coordinates" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ || \
        "$action_ready_coordinates" != "$post_reveal_coordinates" ]]; then
    echo "The action-ready task/bounds changed after geometry validation." >&2
    return 1
  fi

  pip_menu_action_reveal_ms="$(monotonic_ms)"
  adb -s "$device" shell input tap "$reveal_x" "$reveal_y"
  if ! wait_for_pip_menu_visibility visible 8 0.05 "$pip_menu_visibility_log"; then
    echo "The fresh SystemUI PiP menu did not expose its exact input target." >&2
    return 1
  fi
  pip_menu_visible_ms="$PIP_MENU_VISIBILITY_OBSERVED_MS"
  sleep "$PIP_MENU_ANIMATION_SETTLE_SECONDS"
  pip_menu_action_tap_ms="$(monotonic_ms)"
  pip_menu_reveal_to_tap_ms=$((pip_menu_action_tap_ms - pip_menu_action_reveal_ms))
  if ((pip_menu_reveal_to_tap_ms > PIP_MENU_ACTION_LATENCY_BUDGET_MS)); then
    echo "Refusing a SystemUI PiP action outside the live-menu latency budget." >&2
    return 1
  fi
  adb -s "$device" shell input tap "$center_x" "$center_y"
  printf 'pipMenuHiddenMs=%s pipMenuFinalRevealMs=%s pipMenuVisibleMs=%s pipMenuActionTapMs=%s pipMenuRevealToTapMs=%s pipMenuActionBudgetMs=%s\n' \
    "$pip_menu_hidden_ms" "$pip_menu_action_reveal_ms" "$pip_menu_visible_ms" \
    "$pip_menu_action_tap_ms" "$pip_menu_reveal_to_tap_ms" \
    "$PIP_MENU_ACTION_LATENCY_BUDGET_MS" >>"$host_log"

  post_action_activities="$output_dir/native-post-action-activities.txt"
  if ! wait_for_exact_pinned_task_absent \
      "$pre_action_task_id" 30 0.1 "$post_action_activities"; then
    echo "SystemUI PiP action left the exact task pinned." >&2
    return 1
  fi
  if [[ "$action" == "expand" ]]; then
    native_action_terminal_marker='[MKNOON_PIP] TERMINAL state=restoring reason=system_return'
  else
    native_action_terminal_marker='[MKNOON_PIP] TERMINAL state=stopped reason=system_close'
  fi
  if ! wait_for_log "$native_action_terminal_marker" 50 0.1; then
    echo "SystemUI PiP action removed the task without its exact native terminal." >&2
    return 1
  fi
}

adb -s "$device" logcat -c
printf 'platform=android scenario=%s device=%s package=%s fixtureSha256=%s\n' \
  "$scenario" "$device" "$package_name" "$fixture_sha256" >"$host_log"
printf 'androidSdk=%s pictureInPictureFeature=true disposableApplicationId=true\n' \
  "$android_sdk" >>"$host_log"

interruption_helper_apk=""
interruption_helper_local_sha256=""
interruption_helper_local_signer_sha256=""
if [[ "$scenario" == "interruption" ]]; then
  interruption_helper_build_log="$output_dir/interruption-helper-build.log"
  interruption_helper_apk="$output_dir/interruption-helper.apk"
  ORG_GRADLE_PROJECT_androidApplicationId="$package_name" \
  ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
  ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=true \
  ./android/gradlew -p android :app:assembleDebugAndroidTest \
    >"$interruption_helper_build_log" 2>&1
  interruption_helper_candidates="$(find \
    build/app/outputs/apk/androidTest/debug \
    -maxdepth 1 -type f -name '*.apk' -print 2>/dev/null | sort)"
  if [[ "$(printf '%s\n' "$interruption_helper_candidates" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
    echo "Interruption proof did not build exactly one androidTest helper APK." >&2
    exit 1
  fi
  cp "$interruption_helper_candidates" "$interruption_helper_apk"
  interruption_helper_badging="$output_dir/interruption-helper-badging.txt"
  interruption_helper_manifest="$output_dir/interruption-helper-manifest.txt"
  "$aapt_bin" dump badging "$interruption_helper_apk" >"$interruption_helper_badging"
  "$aapt_bin" dump xmltree "$interruption_helper_apk" AndroidManifest.xml \
    >"$interruption_helper_manifest"
  if ! grep -Fq "package: name='$proof_test_package'" "$interruption_helper_badging" || \
     [[ "$(grep -Fc "$interruption_helper_class" "$interruption_helper_manifest")" != "1" ]] || \
     grep -Fq 'E: intent-filter' "$interruption_helper_manifest" || \
     grep -Eqi 'ResolverActivity|ChooserActivity' "$interruption_helper_manifest"; then
    echo "Built interruption helper APK identity/component was not exact." >&2
    exit 1
  fi
  interruption_helper_local_sha256="$(shasum -a 256 "$interruption_helper_apk" | awk '{print $1}')"
  interruption_helper_local_signer_sha256="$($apksigner_bin verify --print-certs "$interruption_helper_apk" | \
    sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"
  if [[ ! "$interruption_helper_local_sha256" =~ ^[0-9a-f]{64}$ || \
        ! "$interruption_helper_local_signer_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Built interruption helper APK hash/signing identity was incomplete." >&2
    exit 1
  fi
  printf 'interruptionHelperBuilt=true helperPackage=%s helperComponent=%s helperApkSha256=%s helperSignerSha256=%s\n' \
    "$proof_test_package" "$interruption_helper_component" \
    "$interruption_helper_local_sha256" \
    "$interruption_helper_local_signer_sha256" >>"$host_log"
fi

test_install_started=true
if [[ "$scenario" == "process-recreation" ]]; then
  ORG_GRADLE_PROJECT_androidApplicationId="$package_name" \
  ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
  ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false \
  flutter drive \
    -d "$device" \
    --keep-app-running \
    --driver "$process_recreation_driver" \
    --target "$target" \
    --dart-define=PIP_PROOF_PLATFORM=android \
    --dart-define="PIP_PROOF_SCENARIO=$scenario" \
    --dart-define="PIP_PROOF_PACKAGE=$package_name" \
    >"$flutter_log" 2>&1 &
elif [[ "$scenario" == "engine-detach" ]]; then
  ORG_GRADLE_PROJECT_androidApplicationId="$package_name" \
  ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false \
  flutter test \
    -d "$device" \
    --dart-define=PIP_PROOF_PLATFORM=android \
    --dart-define="PIP_PROOF_SCENARIO=$scenario" \
    "$target" \
    >"$flutter_log" 2>&1 &
elif [[ "$scenario" == "interruption" ]]; then
  ORG_GRADLE_PROJECT_androidApplicationId="$package_name" \
  ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
  ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=true \
  flutter test \
    -d "$device" \
    --dart-define=PIP_PROOF_PLATFORM=android \
    --dart-define="PIP_PROOF_SCENARIO=$scenario" \
    "$target" \
    >"$flutter_log" 2>&1 &
else
  ORG_GRADLE_PROJECT_androidApplicationId="$package_name" \
  ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
  ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false \
  flutter test \
    -d "$device" \
    --dart-define=PIP_PROOF_PLATFORM=android \
    --dart-define="PIP_PROOF_SCENARIO=$scenario" \
    "$target" \
    >"$flutter_log" 2>&1 &
fi
flutter_pid=$!

installed=false
for _ in $(seq 1 900); do
  if adb -s "$device" shell pm path "$package_name" 2>/dev/null | grep -q '^package:' && \
     adb -s "$device" shell run-as "$package_name" pwd >/dev/null 2>&1; then
    installed=true
    break
  fi
  if ! kill -0 "$flutter_pid" 2>/dev/null; then
    wait "$flutter_pid" || true
    echo "Flutter proof failed before installing the test app." >&2
    tail -n 120 "$flutter_log" >&2 || true
    exit 1
  fi
  sleep 1
done
if [[ "$installed" != true ]]; then
  echo "Timed out waiting for the scenario-specific integration app install." >&2
  exit 1
fi

installed_path_rows="$(adb -s "$device" shell pm path "$package_name" 2>/dev/null | tr -d '\r' | sed -n 's/^package://p')"
if [[ "$(printf '%s\n' "$installed_path_rows" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
  echo "Disposable proof package did not resolve to one installed base APK." >&2
  exit 1
fi
installed_base_apk="$installed_path_rows"
package_dump="$output_dir/installed-package.txt"
adb -s "$device" shell dumpsys package "$package_name" >"$package_dump"
if ! grep -Fq "Package [$package_name]" "$package_dump"; then
  echo "Installed package identity did not match the disposable application ID." >&2
  exit 1
fi

local_debug_apk="build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -s "$local_debug_apk" ]]; then
  echo "Flutter proof debug APK was absent after install." >&2
  exit 1
fi
installed_apk_copy="$(mktemp "${TMPDIR:-/tmp}/mknoon-pip-installed.XXXXXX")"
adb -s "$device" pull "$installed_base_apk" "$installed_apk_copy" >/dev/null
local_apk_sha256="$(shasum -a 256 "$local_debug_apk" | awk '{print $1}')"
installed_apk_sha256="$(shasum -a 256 "$installed_apk_copy" | awk '{print $1}')"
if [[ "$installed_apk_sha256" != "$local_apk_sha256" ]]; then
  echo "Installed disposable APK bytes did not match the proof build." >&2
  exit 1
fi
local_signer_sha256="$($apksigner_bin verify --print-certs "$local_debug_apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"
installed_signer_sha256="$($apksigner_bin verify --print-certs "$installed_apk_copy" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"
if [[ -z "$local_signer_sha256" || "$installed_signer_sha256" != "$local_signer_sha256" ]]; then
  echo "Installed disposable APK signing identity did not match the proof build." >&2
  exit 1
fi
printf 'installedApplicationId=%s installedApkSha256=%s signingCertificateSha256=%s\n' \
  "$package_name" "$installed_apk_sha256" "$installed_signer_sha256" >>"$host_log"
uid="$(adb -s "$device" shell cmd package list packages -U "$package_name" | \
  tr -d '\r' | sed -nE \
  "s/^package:${package_name//./\\.} uid:([0-9]+)$/\\1/p")"
if [[ ! "$uid" =~ ^[0-9]+$ ]]; then
  echo "Could not resolve the disposable proof package UID." >&2
  exit 1
fi
rm -f "$installed_apk_copy"
installed_apk_copy=""

interruption_helper_uid=""
interruption_helper_resolved_component=""
if [[ "$scenario" == "interruption" ]]; then
  installed_base_manifest="$output_dir/installed-base-manifest.txt"
  "$aapt_bin" dump xmltree "$local_debug_apk" AndroidManifest.xml \
    >"$installed_base_manifest"
  if grep -Fq "$interruption_helper_class" "$installed_base_manifest"; then
    echo "Interruption helper leaked into the base proof APK." >&2
    exit 1
  fi
  interruption_helper_install_log="$output_dir/interruption-helper-install.txt"
  if ! adb -s "$device" install -t "$interruption_helper_apk" \
      >"$interruption_helper_install_log" 2>&1; then
    cat "$interruption_helper_install_log" >&2 || true
    echo "Could not install the separate interruption helper test APK." >&2
    exit 1
  fi
  if [[ "$(grep -Fc 'Success' "$interruption_helper_install_log")" != "1" ]]; then
    echo "Interruption helper install result was ambiguous." >&2
    exit 1
  fi
  helper_installed_path_rows="$(adb -s "$device" shell pm path "$proof_test_package" 2>/dev/null | \
    tr -d '\r' | sed -n 's/^package://p')"
  if [[ "$(printf '%s\n' "$helper_installed_path_rows" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
    echo "Interruption helper did not resolve to one installed base APK." >&2
    exit 1
  fi
  helper_installed_base_apk="$helper_installed_path_rows"
  interruption_helper_package_dump="$output_dir/interruption-helper-package.txt"
  adb -s "$device" shell dumpsys package "$proof_test_package" \
    >"$interruption_helper_package_dump"
  if [[ "$(grep -Fc "Package [$proof_test_package]" "$interruption_helper_package_dump")" != "1" ]]; then
    echo "Installed interruption helper package identity was not exact." >&2
    exit 1
  fi
  interruption_helper_resolved_component="$output_dir/interruption-helper-resolved-component.txt"
  interruption_helper_resolved_component_error="$output_dir/interruption-helper-resolved-component-stderr.txt"
  set +e
  adb -s "$device" shell cmd package resolve-activity --components --user 0 \
    -n "$interruption_helper_component" \
    >"$interruption_helper_resolved_component" \
    2>"$interruption_helper_resolved_component_error"
  interruption_helper_resolve_status=$?
  set -e
  interruption_helper_resolved_component_value="$(tr -d '\r' <"$interruption_helper_resolved_component")"
  interruption_helper_resolved_component_lines="$(printf '%s\n' \
    "$interruption_helper_resolved_component_value" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$interruption_helper_resolve_status" != "0" || \
        -s "$interruption_helper_resolved_component_error" || \
        "$interruption_helper_resolved_component_lines" != "1" || \
        "$interruption_helper_resolved_component_value" != "$interruption_helper_component" ]]; then
    echo "Installed interruption helper component did not resolve exactly once." >&2
    exit 1
  fi
  helper_installed_apk_copy="$(mktemp "${TMPDIR:-/tmp}/mknoon-pip-helper-installed.XXXXXX")"
  adb -s "$device" pull "$helper_installed_base_apk" "$helper_installed_apk_copy" \
    >/dev/null
  interruption_helper_installed_sha256="$(shasum -a 256 "$helper_installed_apk_copy" | awk '{print $1}')"
  interruption_helper_installed_signer_sha256="$($apksigner_bin verify --print-certs "$helper_installed_apk_copy" | \
    sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"
  if [[ "$interruption_helper_installed_sha256" != "$interruption_helper_local_sha256" || \
        "$interruption_helper_installed_signer_sha256" != "$interruption_helper_local_signer_sha256" || \
        "$interruption_helper_installed_signer_sha256" != "$installed_signer_sha256" ]]; then
    echo "Installed interruption helper bytes/signing identity did not match its build." >&2
    exit 1
  fi
  rm -f "$helper_installed_apk_copy"
  helper_installed_apk_copy=""
  interruption_helper_uid="$(adb -s "$device" shell cmd package list packages -U "$proof_test_package" | \
    tr -d '\r' | sed -nE \
    "s/^package:${proof_test_package//./\\.} uid:([0-9]+)$/\\1/p")"
  if [[ ! "$interruption_helper_uid" =~ ^[0-9]+$ || \
        "$interruption_helper_uid" == "$uid" ]]; then
    echo "Interruption helper did not have one distinct installed UID." >&2
    exit 1
  fi
  printf 'interruptionHelperInstalled=true helperPackage=%s helperComponent=%s helperUid=%s appUid=%s distinctUid=true installedApkSha256=%s installedSignerSha256=%s\n' \
    "$proof_test_package" "$interruption_helper_component" \
    "$interruption_helper_uid" "$uid" \
    "$interruption_helper_installed_sha256" \
    "$interruption_helper_installed_signer_sha256" >>"$host_log"
fi

adb -s "$device" push "$fixture" "$remote_tmp" >/dev/null
adb -s "$device" shell chmod 644 "$remote_tmp"
adb -s "$device" shell run-as "$package_name" mkdir -p app_flutter/media/plan243-proof
adb -s "$device" shell run-as "$package_name" cp "$remote_tmp" "$app_fixture"
copied_sha256="$(adb -s "$device" exec-out run-as "$package_name" cat "$app_fixture" | shasum -a 256 | awk '{print $1}')"
copied_bytes="$(adb -s "$device" shell run-as "$package_name" stat -c '%s' "$app_fixture" | tr -d '\r')"
if [[ "$copied_sha256" != "$fixture_sha256" || "$copied_bytes" != "$fixture_bytes" ]]; then
  echo "App-owned fixture copy did not match the reviewed bytes." >&2
  exit 1
fi
printf 'appFixtureSha256=%s appFixtureBytes=%s\n' "$copied_sha256" "$copied_bytes" >>"$host_log"

native_component="$package_name/com.mknoon.app.ReceivedVideoPictureInPictureActivity"
flutter_component="$package_name/com.mknoon.app.MainActivity"

protected_negative_marker="[PIP_PROOF] PROTECTED_NEGATIVE control=absent gatewayStart=false nativeOwner=false scenario=$scenario"
wait_for_log "$protected_negative_marker" 900 0.2
flutter_owner_ready_marker="[PIP_PROOF] FLUTTER_OWNER_READY scenario=$scenario controls=true timeVisible=true playing=true"
wait_for_log "$flutter_owner_ready_marker" 900 0.2
capture_state flutter-pre-handoff
if grep -q 'mode=pinned' "$output_dir/flutter-pre-handoff-activities.txt" || \
   grep -Fq "$native_component" "$output_dir/flutter-pre-handoff-activities.txt" || \
   ! grep -Fq "$flutter_component" "$output_dir/flutter-pre-handoff-activities.txt"; then
  echo "Pre-handoff ownership was not the fullscreen Flutter viewer alone." >&2
  exit 1
fi
pre_handoff_players="$(grep -cE \
  "AudioPlaybackConfiguration .*u/pid:${uid}/.*state:started" \
  "$output_dir/flutter-pre-handoff-audio.txt" || true)"
pre_handoff_audio_tracks="$(grep -E \
  "AudioPlaybackConfiguration .*u/pid:${uid}/.*state:started" \
  "$output_dir/flutter-pre-handoff-audio.txt" | \
  grep -c 'type:android.media.AudioTrack' || true)"
pre_handoff_media_players="$(grep -E \
  "AudioPlaybackConfiguration .*u/pid:${uid}/.*state:started" \
  "$output_dir/flutter-pre-handoff-audio.txt" | \
  grep -c 'type:android.media.MediaPlayer' || true)"
if [[ "$pre_handoff_players" != "1" || \
      "$pre_handoff_audio_tracks" != "1" || \
      "$pre_handoff_media_players" != "0" ]]; then
  echo "Expected exactly one Flutter AudioTrack and no native MediaPlayer before handoff." >&2
  exit 1
fi
adb -s "$device" shell run-as "$package_name" \
  touch app_flutter/media/plan243-proof/.flutter-owner-ready-captured-v1
printf 'preHandoffFlutterControls=true preHandoffTimeVisible=true flutterAudioTracks=1 nativeMediaPlayers=0 pinnedNativeTasks=0\n' \
  >>"$host_log"

wait_for_log "[PIP_PROOF] ACTIVE scenario=$scenario" 900 0.2
capture_state native-active
if ! grep -q 'mode=pinned' "$output_dir/native-active-activities.txt"; then
  echo "Android did not report a pinned PiP task." >&2
  exit 1
fi
pinned_task="$output_dir/native-active-pinned-task.txt"
awk '
  /^[[:space:]]*\* Task\{/ {
    if (in_task && pinned) printf "%s", block
    in_task = 1
    pinned = 0
    block = ""
  }
  in_task {
    block = block $0 ORS
    if ($0 ~ /mode=pinned/) pinned = 1
  }
  END {
    if (in_task && pinned) printf "%s", block
  }
' "$output_dir/native-active-activities.txt" >"$pinned_task"
pinned_task_ids="$(sed -nE \
  's/.*Task\{[^#]*#([0-9]+).*mode=pinned.*/\1/p' "$pinned_task" | \
  sort -u)"
if [[ "$(printf '%s\n' "$pinned_task_ids" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
  echo "Expected exactly one live pinned task before the SystemUI action." >&2
  exit 1
fi
if ! grep -Fq "$native_component" "$pinned_task" || grep -Fq "$flutter_component" "$pinned_task"; then
  echo "Pinned task was not the dedicated video-only native Activity." >&2
  exit 1
fi
if ! grep -F 'ReceivedVideoPictureInPictureActivity' "$output_dir/native-active-surfaces.txt" | \
    grep -Eq 'Surface|BLAST|Video'; then
  echo "SurfaceFlinger did not expose the dedicated native video owner." >&2
  exit 1
fi
printf 'pinnedComponent=%s flutterChatPinned=false nativeVideoSurface=true\n' \
  "$native_component" >>"$host_log"

active_players="$(grep -cE "AudioPlaybackConfiguration .*u/pid:${uid}/.*state:started" "$output_dir/native-active-audio.txt" || true)"
if [[ "$active_players" != "1" ]]; then
  echo "Expected exactly one active app audio/video owner, found $active_players." >&2
  exit 1
fi

case "$scenario" in
  return|close)
    pre_action_activities="$output_dir/native-pre-action-activities.txt"
    pre_action_pinned_task="$output_dir/native-pre-action-pinned-task.txt"
    adb -s "$device" shell dumpsys activity activities >"$pre_action_activities"
    awk '
      /^[[:space:]]*\* Task\{/ {
        if (in_task && pinned) printf "%s", block
        in_task = 1
        pinned = 0
        block = ""
      }
      in_task {
        block = block $0 ORS
        if ($0 ~ /mode=pinned/) pinned = 1
      }
      END {
        if (in_task && pinned) printf "%s", block
      }
    ' "$pre_action_activities" >"$pre_action_pinned_task"
    pre_action_task_ids="$(sed -nE \
      's/.*Task\{[^#]*#([0-9]+).*mode=pinned.*/\1/p' \
      "$pre_action_pinned_task" | sort -u)"
    pre_action_native_count="$(grep -Fc "$native_component" "$pre_action_pinned_task" || true)"
    pre_action_flutter_count="$(grep -Fc "$flutter_component" "$pre_action_pinned_task" || true)"
    if [[ "$(printf '%s\n' "$pre_action_task_ids" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" || \
          ! -s "$pre_action_pinned_task" || \
          "$pre_action_native_count" -lt 1 || \
          "$pre_action_flutter_count" -ne 0 ]]; then
      echo "The immediate pre-action task was not one unique dedicated PiP owner." >&2
      exit 1
    fi
    bounds_line="$(awk '/mode=pinned/{p=1} p && /mBounds=Rect/{print; exit}' "$pre_action_pinned_task")"
    coordinates="$(sed -E 's/.*Rect\(([0-9]+), ([0-9]+) - ([0-9]+), ([0-9]+)\).*/\1 \2 \3 \4/' <<<"$bounds_line")"
    if [[ ! "$coordinates" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]]; then
      echo "Could not parse the live pinned PiP bounds." >&2
      exit 1
    fi
    read -r left top right bottom <<<"$coordinates"
    center_x=$(((left + right) / 2))
    center_y=$(((top + bottom) / 2))
    if [[ "$scenario" == "return" ]]; then
      system_ui_action="expand"
    else
      system_ui_action="close"
    fi
    select_and_tap_pip_system_ui_control \
      "$system_ui_action" "$pre_action_task_ids" \
      "$left" "$top" "$right" "$bottom"
    printf 'preActionPinnedTaskId=%s pinnedBounds=%s\n' \
      "$pre_action_task_ids" "$coordinates" >>"$host_log"
    ;;
  completion)
    ;;
  engine-detach)
    engine_detach_action="com.mknoon.app.pipproof.action.PICTURE_IN_PICTURE_ENGINE_DETACH"
    engine_detach_receiver="$package_name/com.mknoon.app.PictureInPictureEngineDetachProofReceiver"
    engine_detach_broadcast_log="$output_dir/engine-detach-proof-broadcast.txt"
    adb -s "$device" logcat -c
    if ! adb -s "$device" shell am broadcast \
      -a "$engine_detach_action" \
      -n "$engine_detach_receiver" \
      >"$engine_detach_broadcast_log" 2>&1; then
      cat "$engine_detach_broadcast_log" >&2 || true
      echo "The explicit proof-only engine cleanup broadcast failed." >&2
      exit 1
    fi
    if [[ "$(grep -Fc 'Broadcast completed: result=-1' "$engine_detach_broadcast_log")" != "1" ]]; then
      cat "$engine_detach_broadcast_log" >&2 || true
      echo "The ordered proof-only broadcast was rejected or ambiguous." >&2
      exit 1
    fi
    ;;
  interruption)
    interruption_nonce="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    if [[ ! "$interruption_nonce" =~ ^[0-9a-f]{32}$ ]]; then
      echo "Could not create one exact interruption proof nonce." >&2
      exit 1
    fi
    interruption_start_output="$output_dir/interruption-helper-start.txt"
    interruption_logcat="$output_dir/interruption-focus-transfer-logcat.txt"
    interruption_result="$output_dir/interruption-focus-transfer.txt"
    interruption_error="$output_dir/interruption-focus-transfer-error.txt"
    interruption_helper_marker="[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST nonce=$interruption_nonce gain=GAIN usage=USAGE_MEDIA content=CONTENT_TYPE_MOVIE result=granted uid=$interruption_helper_uid"
    interruption_native_terminal="[MKNOON_PIP] TERMINAL state=stopped reason=interrupted"
    adb -s "$device" logcat -c
    if ! adb -s "$device" shell am start -W \
        -n "$interruption_helper_component" \
        --es proofNonce "$interruption_nonce" \
        >"$interruption_start_output" 2>&1; then
      cat "$interruption_start_output" >&2 || true
      echo "Explicit interruption helper Activity did not start." >&2
      exit 1
    fi
    wait_for_log "$interruption_helper_marker" 100 0.1
    wait_for_log "$interruption_native_terminal" 100 0.1
    interruption_settled=false
    for _ in $(seq 1 50); do
      capture_state interruption-focus-transferred
      adb -s "$device" logcat -d -v threadtime >"$interruption_logcat"
      set +e
      python3 scripts/validate_android_picture_in_picture_interruption.py \
        --resolved-component "$interruption_helper_resolved_component" \
        --start-output "$interruption_start_output" \
        --pre-activities "$output_dir/native-active-activities.txt" \
        --pre-audio "$output_dir/native-active-audio.txt" \
        --post-activities "$output_dir/interruption-focus-transferred-activities.txt" \
        --post-audio "$output_dir/interruption-focus-transferred-audio.txt" \
        --logcat "$interruption_logcat" \
        --app-component "$native_component" \
        --helper-component "$interruption_helper_component" \
        --app-package "$package_name" \
        --helper-package "$proof_test_package" \
        --app-uid "$uid" \
        --helper-uid "$interruption_helper_uid" \
        --nonce "$interruption_nonce" \
        --output "$interruption_result" \
        >/dev/null 2>"$interruption_error"
      interruption_status=$?
      set -e
      if [[ "$interruption_status" == "0" ]]; then
        interruption_settled=true
        break
      fi
      sleep 0.1
    done
    if [[ "$interruption_settled" != true ]]; then
      cat "$interruption_error" >&2 || true
      echo "Audio-focus interruption did not settle with exact causal ownership." >&2
      exit 1
    fi
    cat "$interruption_result" >>"$host_log"
    printf 'interruptionNonce=%s helperFocusGranted=true helperUid=%s appUid=%s nativeTerminal=true alternateNativeTerminals=0\n' \
      "$interruption_nonce" "$interruption_helper_uid" "$uid" >>"$host_log"
    ;;
  process-recreation)
    wait_for_log "[PIP_PROOF] PROCESS_RECREATION_KILL_READY" 150 0.2
    original_pid="$(adb -s "$device" shell pidof "$package_name" | tr -d '\r')"
    if [[ -z "$original_pid" ]]; then
      echo "Could not resolve the active proof process." >&2
      exit 1
    fi
    adb -s "$device" shell am force-stop "$package_name"
    if adb -s "$device" shell pidof "$package_name" | grep -q '[0-9]'; then
      echo "Proof process survived force-stop." >&2
      exit 1
    fi
    capture_state process-stopped
    assert_no_pinned_owner "$output_dir/process-stopped-activities.txt"
    set +e
    wait_for_flutter_shutdown 150 0.2
    flutter_shutdown_status=$?
    set -e
    if [[ "$flutter_shutdown_status" == "124" ]]; then
      echo "Flutter proof host did not exit after process recreation force-stop." >&2
      exit 1
    fi
    if ! adb -s "$device" shell pm path "$package_name" 2>/dev/null | \
      grep -q '^package:'; then
      echo "Process-recreation drive package disappeared before exact relaunch." >&2
      exit 1
    fi
    process_recreation_session="plan243-process_recreation"
    process_relaunch_marker="[PIP_PROOF] PROCESS_RECREATION_EMPTY fixture=verified nativeReplay=false scenario=process-recreation session=$process_recreation_session package=$package_name"
    process_relaunch_log="$output_dir/process-relaunch-am-start.txt"
    adb -s "$device" logcat -c
    if ! adb -s "$device" shell am start -W -n "$flutter_component" \
      -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
      >"$process_relaunch_log" 2>&1; then
      cat "$process_relaunch_log" >&2 || true
      echo "Exact process-recreation launcher start failed." >&2
      exit 1
    fi
    if ! grep -Fq 'Status: ok' "$process_relaunch_log"; then
      cat "$process_relaunch_log" >&2 || true
      echo "Exact process-recreation launcher did not report Status: ok." >&2
      exit 1
    fi
    wait_for_log "$process_relaunch_marker" 450 0.2
    relaunch_pid="$(adb -s "$device" shell pidof "$package_name" | tr -d '\r')"
    if [[ ! "$relaunch_pid" =~ ^[0-9]+$ || "$relaunch_pid" == "$original_pid" ]]; then
      echo "Relaunched proof package did not resolve to one fresh process." >&2
      exit 1
    fi
    process_relaunched_process="$output_dir/process-relaunched-process.txt"
    adb -s "$device" shell ps -A -o PID,NAME >"$process_relaunched_process"
    if [[ "$(awk -v pid="$relaunch_pid" -v package="$package_name" \
      '$1 == pid && $2 == package { count++ } END { print count + 0 }' \
      "$process_relaunched_process")" != "1" ]]; then
      echo "Relaunched PID was not bound to the exact disposable package." >&2
      exit 1
    fi
    process_relaunched_logcat="$output_dir/process-relaunched-logcat.txt"
    adb -s "$device" logcat -d --pid="$relaunch_pid" -v threadtime \
      >"$process_relaunched_logcat"
    if ! awk -v pid="$relaunch_pid" -v marker="$process_relaunch_marker" \
      '$3 == pid && index($0, marker) { count++ } END { exit count == 1 ? 0 : 1 }' \
      "$process_relaunched_logcat"; then
      echo "Retained relaunch log did not contain one exact PID/session marker." >&2
      exit 1
    fi
    if grep -Fq '[PIP_PROOF] ACTIVE scenario=process-recreation' \
        "$process_relaunched_logcat" || \
       grep -Fq '[PIP_PROOF] PROCESS_RECREATION_KILL_READY' \
        "$process_relaunched_logcat" || \
       grep -Fq 'ReceivedVideoPictureInPictureActivity' \
        "$process_relaunched_logcat"; then
      echo "Relaunched process replayed the received-video native PiP session." >&2
      exit 1
    fi
    capture_state process-relaunched
    assert_no_pinned_owner "$output_dir/process-relaunched-activities.txt"
    if grep -Fq "$native_component" "$output_dir/process-relaunched-activities.txt"; then
      echo "Relaunched task retained the received-video native Activity." >&2
      exit 1
    fi
    printf 'originalPid=%s relaunchPid=%s relaunchPackage=%s relaunchSession=%s relaunchEmpty=true nativeReplay=false\n' \
      "$original_pid" "$relaunch_pid" "$package_name" "$process_recreation_session" \
      >>"$host_log"
    echo "PASS platform=android scenario=$scenario device=$device output=$output_dir"
    exit 0
    ;;
esac

if [[ "$scenario" == "engine-detach" ]]; then
  engine_detach_control_marker="[MKNOON_PIP] PROOF_ENGINE_CLEANUP_CONTROL invoked=true"
  native_engine_detach_terminal="[MKNOON_PIP] TERMINAL state=stopped reason=flutter_engine_detached"
  dart_engine_detach_terminal="[PIP_PROOF] TERMINAL scenario=engine-detach state=stopped reason=flutterEngineDetached"
  wait_for_log "$engine_detach_control_marker" 150 0.2
  wait_for_log "$native_engine_detach_terminal" 150 0.2
  wait_for_log "$dart_engine_detach_terminal" 150 0.2
  set +e
  wait "$flutter_pid"
  flutter_status=$?
  set -e
  flutter_pid=""
  if [[ "$flutter_status" != "0" ]]; then
    echo "Flutter engine-detach proof did not exit normally: $flutter_status" >&2
    tail -n 160 "$flutter_log" >&2 || true
    exit 1
  fi
  capture_state engine-detach-terminal
  assert_no_pinned_owner "$output_dir/engine-detach-terminal-activities.txt"
  engine_detach_players="$(grep -cE \
    "AudioPlaybackConfiguration .*u/pid:${uid}/.*state:started" \
    "$output_dir/engine-detach-terminal-audio.txt" || true)"
  if [[ "$engine_detach_players" != "0" || \
        "$(grep -Fc "$native_component" "$output_dir/engine-detach-terminal-activities.txt")" != "0" || \
        "$(grep -c 'mode=pinned' "$output_dir/engine-detach-terminal-activities.txt")" != "0" ]]; then
    echo "Proof-only engine cleanup left native playback ownership behind." >&2
    exit 1
  fi
  engine_detach_terminal_logcat="$output_dir/engine-detach-terminal-logcat.txt"
  adb -s "$device" logcat -d -v threadtime >"$engine_detach_terminal_logcat"
  if [[ "$(grep -Fc "$engine_detach_control_marker" "$engine_detach_terminal_logcat")" != "1" || \
        "$(grep -Fc "$native_engine_detach_terminal" "$engine_detach_terminal_logcat")" != "1" || \
        "$(grep -Fc '[MKNOON_PIP] TERMINAL ' "$engine_detach_terminal_logcat")" != "1" || \
        "$(grep -Fc 'reason=system_close' "$engine_detach_terminal_logcat")" != "0" || \
        "$(grep -Fc '[MKNOON_PIP] MainActivity.cleanUpFlutterEngine' "$engine_detach_terminal_logcat")" != "0" || \
        "$(grep -Fc "$dart_engine_detach_terminal" "$flutter_log")" != "1" ]]; then
    echo "Engine-detach proof lacked one honest control/terminal or leaked system-close/callback evidence." >&2
    exit 1
  fi
  printf 'flutterHostExit=0 proofControl=true realCleanupCallback=false nativeTerminal=true dartTerminal=true systemCloseCount=0 ownerReleased=true\n' \
    >>"$host_log"
  echo "PASS platform=android scenario=$scenario device=$device output=$output_dir"
  exit 0
fi
if [[ "$scenario" == "return" || "$scenario" == "close" ]]; then
  if [[ "$scenario" == "return" ]]; then
    restored_playing=true
    restored_expected_players=1
  else
    restored_playing=false
    restored_expected_players=0
  fi
  restored_owner_marker="[PIP_PROOF] FLUTTER_OWNER_RESTORED scenario=$scenario controls=true timeVisible=true playing=$restored_playing"
  wait_for_log "$restored_owner_marker" 1500 0.2
  restored_owner_settled=false
  restored_ownership_result="$output_dir/post-terminal-restored-ownership.txt"
  restored_ownership_error="$output_dir/post-terminal-restored-ownership-error.txt"
  for _ in $(seq 1 150); do
    capture_state flutter-post-terminal
    set +e
    python3 scripts/validate_android_picture_in_picture_restored_ownership.py \
      --activities "$output_dir/flutter-post-terminal-activities.txt" \
      --audio "$output_dir/flutter-post-terminal-audio.txt" \
      --flutter-component "$flutter_component" \
      --native-component "$native_component" \
      --uid "$uid" \
      --expected-audio-tracks "$restored_expected_players" \
      --output "$restored_ownership_result" \
      >/dev/null 2>"$restored_ownership_error"
    restored_ownership_status=$?
    set -e
    if [[ "$restored_ownership_status" == "0" ]]; then
      restored_owner_settled=true
      break
    fi
    sleep 0.2
  done
  if [[ "$restored_owner_settled" != true ]]; then
    cat "$restored_ownership_error" >&2 || true
    echo "Post-terminal ownership did not settle semantically after the SystemUI terminal." >&2
    exit 1
  fi
  restored_audio_tracks="$(sed -nE \
    's/.*flutterAudioTracks=([0-9]+).*/\1/p' \
    "$restored_ownership_result")"
  if [[ ! "$restored_audio_tracks" =~ ^[0-9]+$ ]]; then
    echo "Semantic restored-ownership evidence was incomplete." >&2
    exit 1
  fi
  cat "$restored_ownership_result" >>"$host_log"
  adb -s "$device" shell run-as "$package_name" \
    touch app_flutter/media/plan243-proof/.flutter-owner-restored-captured-v1
  printf 'postTerminalFlutterControls=true postTerminalTimeVisible=true postTerminalPlaying=%s flutterAudioTracks=%s nativeMediaPlayers=0 pinnedNativeTasks=0\n' \
    "$restored_playing" "$restored_audio_tracks" >>"$host_log"
fi
wait_for_log "[PIP_PROOF] TERMINAL scenario=$scenario" 1500 0.2
set +e
wait "$flutter_pid"
flutter_status=$?
set -e
flutter_pid=""
if [[ "$flutter_status" != "0" ]]; then
  echo "Flutter integration proof exited nonzero: $flutter_status" >&2
  tail -n 160 "$flutter_log" >&2 || true
  exit 1
fi
if [[ "$scenario" == "interruption" ]]; then
  interruption_dart_terminal="[PIP_PROOF] TERMINAL scenario=interruption state=stopped reason=interrupted"
  if [[ "$(grep -Fc "$interruption_dart_terminal" "$flutter_log")" != "1" || \
        "$(grep -Fc '[PIP_PROOF] TERMINAL scenario=interruption' "$flutter_log")" != "1" ]]; then
    echo "Flutter interruption proof lacked one exact stopped/interrupted terminal." >&2
    exit 1
  fi
  printf 'dartTerminal=true dartState=stopped dartReason=interrupted alternateDartTerminals=0\n' \
    >>"$host_log"
fi

capture_state terminal
assert_no_pinned_owner "$output_dir/terminal-activities.txt"
remaining_players="$(grep -cE "AudioPlaybackConfiguration .*u/pid:${uid}/.*state:started" "$output_dir/terminal-audio.txt" || true)"
if [[ "$remaining_players" != "0" ]]; then
  echo "App audio/video ownership remained after terminal settlement." >&2
  exit 1
fi

echo "PASS platform=android scenario=$scenario device=$device output=$output_dir"
