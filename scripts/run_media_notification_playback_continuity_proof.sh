#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

device=""
package_name="com.mknoon.app.playbackproof"
production_package="com.mknoon.app"
output_dir=""
dry_run=false

fixture="integration_test/fixtures/received_video_picture_in_picture_fixture.mp4"
fixture_sha256="d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5"
fixture_bytes="2463571"
target="integration_test/media_notification_playback_continuity_test.dart"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_media_notification_playback_continuity_proof.sh \
    --device <explicit-physical-android-id> \
    [--package <disposable-application-id>] [--output <dir>] [--dry-run]
EOF
}

while (($# > 0)); do
  case "$1" in
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
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$device" || "$device" == "-" ]]; then
  printf 'A nonempty explicit --device ID is required.\n' >&2
  exit 2
fi
if [[ ! "$package_name" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]; then
  printf 'The Android application ID is malformed.\n' >&2
  exit 2
fi
if [[ "$package_name" == "$production_package" ]]; then
  printf 'The production application ID is forbidden for this disposable proof.\n' >&2
  exit 2
fi
if [[ ! -f "$fixture" ]]; then
  printf 'Reviewed playback fixture is missing: %s\n' "$fixture" >&2
  exit 1
fi

actual_sha256="$(shasum -a 256 "$fixture" | awk '{print $1}')"
actual_bytes="$(wc -c <"$fixture" | tr -d ' ')"
if [[ "$actual_sha256" != "$fixture_sha256" || "$actual_bytes" != "$fixture_bytes" ]]; then
  printf 'Reviewed playback fixture identity did not match.\n' >&2
  exit 1
fi

if [[ -z "$output_dir" ]]; then
  output_dir="build/media-notification-playback-proof/$(date -u +%Y%m%dT%H%M%SZ)"
fi

if [[ "$dry_run" == true ]]; then
  printf 'DRY_RUN device=%s package=%s target=%s output=%s\n' \
    "$device" "$package_name" "$target" "$output_dir"
  exit 0
fi

for command_name in adb flutter shasum awk wc; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
done

if [[ "$(adb -s "$device" get-state 2>/dev/null || true)" != "device" ]]; then
  printf 'Explicit Android target is unavailable: %s\n' "$device" >&2
  exit 1
fi
if [[ "$(adb -s "$device" shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]]; then
  printf 'Playback-continuity proof requires a physical Android target.\n' >&2
  exit 1
fi

proof_test_package="${package_name}.test"
for candidate_package in "$package_name" "$proof_test_package"; do
  if adb -s "$device" shell pm path "$candidate_package" 2>/dev/null | grep -q '^package:'; then
    printf 'Refusing to replace pre-existing package %s on %s.\n' \
      "$candidate_package" "$device" >&2
    exit 1
  fi
done

mkdir -p "$output_dir"
flutter_log="$output_dir/flutter-test.log"
host_log="$output_dir/host.log"
remote_tmp="/data/local/tmp/mknoon-playback-proof-${$}.mp4"
app_fixture="app_flutter/media/plan243-proof/received_video_picture_in_picture_fixture.mp4"
flutter_pid=""
install_started=false

cleanup() {
  local cleanup_status=$?
  trap - EXIT INT TERM
  if [[ -n "$flutter_pid" ]] && kill -0 "$flutter_pid" 2>/dev/null; then
    kill "$flutter_pid" 2>/dev/null || true
    wait "$flutter_pid" 2>/dev/null || true
  fi
  adb -s "$device" shell rm -f "$remote_tmp" >/dev/null 2>&1 || true
  if [[ "$install_started" == true ]]; then
    adb -s "$device" shell am force-stop "$package_name" >/dev/null 2>&1 || true
    adb -s "$device" uninstall "$package_name" >/dev/null 2>&1 || true
    adb -s "$device" uninstall "$proof_test_package" >/dev/null 2>&1 || true
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT INT TERM

printf 'device=%s package=%s fixtureSha256=%s fixtureBytes=%s\n' \
  "$device" "$package_name" "$fixture_sha256" "$fixture_bytes" >"$host_log"

install_started=true
ORG_GRADLE_PROJECT_androidApplicationId="$package_name" \
ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
flutter test --no-pub -d "$device" --reporter expanded \
  --dart-define=MEDIA_NOTIFICATION_PLAYBACK_PROOF_PLATFORM=android \
  "$target" >"$flutter_log" 2>&1 &
flutter_pid=$!

installed=false
for _ in $(seq 1 900); do
  if adb -s "$device" shell pm path "$package_name" 2>/dev/null | grep -q '^package:' && \
     adb -s "$device" shell run-as "$package_name" pwd >/dev/null 2>&1; then
    installed=true
    break
  fi
  if ! kill -0 "$flutter_pid" 2>/dev/null; then
    set +e
    wait "$flutter_pid"
    early_status=$?
    set -e
    flutter_pid=""
    tail -n 160 "$flutter_log" >&2 || true
    printf 'Flutter proof exited before its disposable app was ready (%s).\n' \
      "$early_status" >&2
    exit 1
  fi
  sleep 0.2
done
if [[ "$installed" != true ]]; then
  printf 'Timed out waiting for the disposable playback proof install.\n' >&2
  exit 1
fi

adb -s "$device" shell pm grant "$package_name" android.permission.POST_NOTIFICATIONS
adb -s "$device" push "$fixture" "$remote_tmp" >/dev/null
adb -s "$device" shell chmod 644 "$remote_tmp"
adb -s "$device" shell run-as "$package_name" mkdir -p app_flutter/media/plan243-proof
adb -s "$device" shell run-as "$package_name" cp "$remote_tmp" "$app_fixture"

copied_sha256="$(adb -s "$device" exec-out run-as "$package_name" cat "$app_fixture" | shasum -a 256 | awk '{print $1}')"
copied_bytes="$(adb -s "$device" shell run-as "$package_name" stat -c '%s' "$app_fixture" | tr -d '\r')"
if [[ "$copied_sha256" != "$fixture_sha256" || "$copied_bytes" != "$fixture_bytes" ]]; then
  printf 'App-owned fixture copy did not match the reviewed bytes.\n' >&2
  exit 1
fi
printf 'appFixtureSha256=%s appFixtureBytes=%s notificationPermission=pregranted\n' \
  "$copied_sha256" "$copied_bytes" >>"$host_log"

set +e
wait "$flutter_pid"
flutter_status=$?
set -e
flutter_pid=""
if [[ "$flutter_status" -ne 0 ]]; then
  tail -n 220 "$flutter_log" >&2 || true
  printf 'Playback-continuity proof failed with exit %s.\n' "$flutter_status" >&2
  exit "$flutter_status"
fi
if ! grep -Fq 'All tests passed!' "$flutter_log"; then
  tail -n 220 "$flutter_log" >&2 || true
  printf 'Playback-continuity proof did not report test completion.\n' >&2
  exit 1
fi

printf 'PASS device=%s package=%s output=%s\n' "$device" "$package_name" "$output_dir"
