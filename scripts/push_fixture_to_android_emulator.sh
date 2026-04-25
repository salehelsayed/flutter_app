#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

device="${ANDROID_SERIAL:-}"
package_name="${ANDROID_PACKAGE:-com.mknoon.app}"
receiver="${ANDROID_FCM_RECEIVER:-}"
adb_bin="${ANDROID_ADB:-}"
dry_run=0
fixture=""

usage() {
  cat <<'EOF'
Usage:
  scripts/push_fixture_to_android_emulator.sh [--dry-run] [--device <adb-serial>] [--package <package>] [--receiver <component>] <fixture>

Fixture can be an absolute/relative JSON path or a fixture id from:
  test/features/push/fixtures/
  test/features/push/frozen_payloads/

Environment:
  ANDROID_SERIAL        Default adb serial
  ANDROID_PACKAGE       Default package, defaults to com.mknoon.app
  ANDROID_FCM_RECEIVER  Receiver component override
  ANDROID_ADB           Optional adb binary override
EOF
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --device)
      device="${2:?missing --device value}"
      shift 2
      ;;
    --package)
      package_name="${2:?missing --package value}"
      shift 2
      ;;
    --receiver)
      receiver="${2:?missing --receiver value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$fixture" ]]; then
        usage
        exit 2
      fi
      fixture="$1"
      shift
      ;;
  esac
done

if [[ -z "$fixture" ]]; then
  usage
  exit 2
fi

if [[ -z "$receiver" ]]; then
  receiver="$package_name/io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver"
fi

resolve_fixture() {
  local input="$1"
  local candidate

  if [[ -f "$input" ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  for candidate in \
    "$ROOT_DIR/test/features/push/fixtures/$input" \
    "$ROOT_DIR/test/features/push/fixtures/$input.json" \
    "$ROOT_DIR/test/features/push/frozen_payloads/$input" \
    "$ROOT_DIR/test/features/push/frozen_payloads/$input.json"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

fixture_path="$(resolve_fixture "$fixture")" || {
  printf 'Fixture not found: %s\n' "$fixture" >&2
  exit 1
}

resolve_adb() {
  local candidate

  if [[ -n "$adb_bin" ]]; then
    [[ -x "$adb_bin" ]] || {
      printf 'ANDROID_ADB is not executable: %s\n' "$adb_bin" >&2
      return 1
    }
    printf '%s\n' "$adb_bin"
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

adb_bin="$(resolve_adb)"

cmd=("$adb_bin")
if [[ -n "$device" ]]; then
  cmd+=(-s "$device")
fi
cmd+=(
  shell am broadcast
  -a com.google.android.c2dm.intent.RECEIVE
  -n "$receiver"
  --es message_type gcm
)

while IFS=$'\t' read -r key value; do
  # `adb shell` forwards through the device shell, so values with spaces must
  # be shell-escaped before they reach `am broadcast`.
  cmd+=(--es "$key" "$(printf '%q' "$value")")
done < <(
  node - "$fixture_path" <<'NODE'
const fs = require('fs');

const fixturePath = process.argv[2];
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const routeData = fixture.routeData || fixture.data || fixture;
const messageId = routeData.message_id || routeData.messageId || fixture.messageId || `fixture-${Date.now()}`;

console.log(`google.message_id\t${String(messageId)}`);
for (const [key, value] of Object.entries(routeData)) {
  if (value === null || value === undefined) continue;
  if (typeof value === 'object') {
    console.log(`${key}\t${JSON.stringify(value)}`);
  } else {
    console.log(`${key}\t${String(value)}`);
  }
}
NODE
)

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Would inject Android FCM fixture %s through %s:\n' \
    "$fixture_path" "$receiver"
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
