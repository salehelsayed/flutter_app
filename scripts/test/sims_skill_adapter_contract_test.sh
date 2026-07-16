#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADAPTER="$ROOT_DIR/.claude/skills/sims/scripts/run_with_devices.sh"
TMP_DIR="$(mktemp -d)"
FAKE_REPO="$TMP_DIR/repo"
SHIM_DIR="$TMP_DIR/bin"
ARGS_LOG="$TMP_DIR/args.log"
ENV_LOG="$TMP_DIR/env.log"
DISCOVERY_LOG="$TMP_DIR/discovery.log"
OUTPUT_LOG="$TMP_DIR/output.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$FAKE_REPO/scripts" "$SHIM_DIR"

cat >"$FAKE_REPO/scripts/run_test_gates.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$SIMS_ADAPTER_ARGS_LOG"
printf '%s\n' "${MKNOON_RELAY_ADDRESSES-<unset>}" >"$SIMS_ADAPTER_ENV_LOG"
if [[ " $* " == *" --format json "* ]]; then
  printf '{"schemaVersion":1,"mode":"major"}\n'
fi
exit "${SIMS_FAKE_STATUS:-0}"
SH
chmod +x "$FAKE_REPO/scripts/run_test_gates.sh"

for command_name in flutter xcrun adb; do
  cat >"$SHIM_DIR/$command_name" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0") $*" >>"$SIMS_DISCOVERY_LOG"
if [ "${SIMS_FAKE_DISCOVERY:-0}" = "1" ]; then
  case "$(basename "$0")" in
    flutter)
      cat <<'JSON'
[
  {"id":"ios-first-in-flutter-output","name":"iPhone First","targetPlatform":"ios","emulator":true},
  {"id":"android-emulator","name":"Android Emulator","targetPlatform":"android-x64","emulator":true},
  {"id":"android-physical","name":"Android Physical","targetPlatform":"android-arm64","emulator":false}
]
JSON
      exit 0
      ;;
    xcrun)
      cat <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-test":[
  {"udid":"ios-a","name":"iPhone A","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-A"},
  {"udid":"ios-b","name":"iPhone B","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-B"}
]}}
JSON
      exit 0
      ;;
  esac
fi
exit 97
SH
  chmod +x "$SHIM_DIR/$command_name"
done

run_adapter() {
  rm -f "$ARGS_LOG" "$ENV_LOG" "$DISCOVERY_LOG" "$OUTPUT_LOG"
  (
    unset MKNOON_RELAY_ADDRESSES
    cd "$FAKE_REPO"
    PATH="$SHIM_DIR:$PATH" \
      SIMS_ADAPTER_ARGS_LOG="$ARGS_LOG" \
      SIMS_ADAPTER_ENV_LOG="$ENV_LOG" \
      SIMS_DISCOVERY_LOG="$DISCOVERY_LOG" \
      "$ADAPTER" "$@"
  ) >"$OUTPUT_LOG" 2>&1
}

# No mode and no adapter arguments is the release-safe major shorthand.
run_adapter
expected_default="$(printf '%s\n' sims major)"
actual_default="$(cat "$ARGS_LOG")"
[ "$actual_default" = "$expected_default" ] ||
  fail 'no-argument adapter invocation did not delegate to sims major'
[ "$(cat "$ENV_LOG")" = '<unset>' ] ||
  fail 'canonical sims invocation injected a legacy relay address'
[ ! -s "$DISCOVERY_LOG" ] ||
  fail 'canonical sims invocation performed skill-local device discovery'
grep -q 'the skill adapter selected none' "$OUTPUT_LOG" ||
  fail 'adapter did not disclose that target/build selection is repo-owned'

# Canonical aliases normalize only spelling and forward every supported value.
run_adapter full --dry-run --parallel --continue-on-failure \
  --fix-as-you-go --resume --prepare-builds \
  --only android.voice_recorder_native_smoke \
  --family 1to1 --lane android-device --format json
expected_flags="$(printf '%s\n' \
  sims full --list --simultaneous --continue-on-failure --fix-as-you-go \
  --resume --prepare-builds --only android.voice_recorder_native_smoke \
  --family 1to1 --lane android-device --format json)"
actual_flags="$(cat "$ARGS_LOG")"
[ "$actual_flags" = "$expected_flags" ] ||
  fail 'canonical mode/options did not reach the repo gate intact'
[ ! -s "$DISCOVERY_LOG" ] ||
  fail 'full mode performed hidden iOS/Android discovery in the adapter'

# Machine-readable repo output must not be polluted by adapter diagnostics.
stdout_log="$TMP_DIR/stdout.log"
stderr_log="$TMP_DIR/stderr.log"
(
  unset MKNOON_RELAY_ADDRESSES
  cd "$FAKE_REPO"
  PATH="$SHIM_DIR:$PATH" \
    SIMS_ADAPTER_ARGS_LOG="$ARGS_LOG" \
    SIMS_ADAPTER_ENV_LOG="$ENV_LOG" \
    SIMS_DISCOVERY_LOG="$DISCOVERY_LOG" \
    "$ADAPTER" major --list --format json
) >"$stdout_log" 2>"$stderr_log"
[ "$(cat "$stdout_log")" = '{"schemaVersion":1,"mode":"major"}' ] ||
  fail 'adapter diagnostics polluted machine-readable JSON stdout'
grep -q 'the skill adapter selected none' "$stderr_log" ||
  fail 'adapter diagnostics were not preserved on stderr'

# The repo gate's terminal status is the adapter's terminal status.
set +e
(
  unset MKNOON_RELAY_ADDRESSES
  cd "$FAKE_REPO"
  PATH="$SHIM_DIR:$PATH" \
    SIMS_ADAPTER_ARGS_LOG="$ARGS_LOG" \
    SIMS_ADAPTER_ENV_LOG="$ENV_LOG" \
    SIMS_DISCOVERY_LOG="$DISCOVERY_LOG" \
    SIMS_FAKE_STATUS=23 \
    "$ADAPTER" smoke
) >"$OUTPUT_LOG" 2>&1
status=$?
set -e
[ "$status" -eq 23 ] ||
  fail "adapter replaced repo gate exit status 23 with $status"

# Numeric legacy resume controls are rejected rather than silently forwarded
# into a stable-ID sims plan.
set +e
(
  cd "$FAKE_REPO"
  "$ADAPTER" major --start-at 4
) >"$OUTPUT_LOG" 2>&1
status=$?
set -e
[ "$status" -eq 2 ] ||
  fail "canonical sims accepted legacy --start-at (status $status)"

# The retained compatibility resolver follows the project live-matrix default:
# physical Android + Android emulator, even when Flutter lists iOS first.
rm -f "$DISCOVERY_LOG" "$OUTPUT_LOG"
(
  unset RELIABILITY_SINGLE_DEVICE_ID RELIABILITY_MULTI_DEVICE_IDS \
    FLUTTER_DEVICE_ID FLUTTER_MULTI_DEVICE_IDS \
    IOS_NOTIFICATION_TAP_DEVICES SIMULATOR_DEVICE \
    IOS_SECONDARY_SIMULATOR_DEVICE ANDROID_SERIAL \
    DEVICE_A DEVICE_B DEVICE_C DEVICE_D
  cd "$FAKE_REPO"
  PATH="$SHIM_DIR:$PATH" \
    SIMS_DISCOVERY_LOG="$DISCOVERY_LOG" \
    SIMS_FAKE_DISCOVERY=1 \
    "$ADAPTER" 1to1 --print-env
) >"$OUTPUT_LOG" 2>&1
grep -q '^export RELIABILITY_SINGLE_DEVICE_ID=android-physical$' "$OUTPUT_LOG" ||
  fail 'legacy one-device fallback still preferred iOS over physical Android'
grep -q '^export RELIABILITY_MULTI_DEVICE_IDS=android-physical,android-emulator$' "$OUTPUT_LOG" ||
  fail 'legacy two-peer fallback did not prefer physical Android + emulator'
grep -q '^export SIMULATOR_DEVICE=ios-a$' "$OUTPUT_LOG" ||
  fail 'explicitly iOS-only compatibility variables lost their platform scope'

printf 'PASS: sims skill adapter contract\n'
