#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

device="${SIMULATOR_DEVICE:-booted}"
bundle_id="${IOS_BUNDLE_ID:-com.mknoon.app}"
dry_run=0
fixture=""

usage() {
  cat <<'EOF'
Usage:
  scripts/push_fixture_to_simulator.sh [--dry-run] [--device <simulator>] [--bundle-id <bundle>] <fixture>

Fixture can be an absolute/relative JSON path or a fixture id from:
  test/features/push/fixtures/
  test/features/push/frozen_payloads/

Environment:
  SIMULATOR_DEVICE   Default simulator target, defaults to booted
  IOS_BUNDLE_ID      Default app bundle id, defaults to com.mknoon.app
  IOS_APNS_ALERT_TITLE       Alert title, defaults to "New Message"
  IOS_APNS_ALERT_BODY        Alert body, defaults to "You have a new message"
  IOS_APNS_MUTABLE_CONTENT    Set to 0/false/no to omit mutable-content
  IOS_APNS_CONTENT_AVAILABLE  Set to 0/false/no to omit content-available
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
    --bundle-id)
      bundle_id="${2:?missing --bundle-id value}"
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

payload_file="$(mktemp "${TMPDIR:-/tmp}/mknoon-apns-payload.XXXXXX.json")"
trap 'rm -f "$payload_file"' EXIT

node - "$fixture_path" >"$payload_file" <<'NODE'
const fs = require('fs');

const fixturePath = process.argv[2];
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const routeData = fixture.routeData || fixture.data || fixture;

function enabled(name) {
  const value = String(process.env[name] || '1').trim().toLowerCase();
  return value !== '0' && value !== 'false' && value !== 'no';
}

const aps = {
  alert: {
    title: process.env.IOS_APNS_ALERT_TITLE || 'New Message',
    body: process.env.IOS_APNS_ALERT_BODY || 'You have a new message',
  },
};

if (enabled('IOS_APNS_MUTABLE_CONTENT')) {
  aps['mutable-content'] = 1;
}
if (enabled('IOS_APNS_CONTENT_AVAILABLE')) {
  aps['content-available'] = 1;
}

const payload = {
  aps,
  ...routeData,
};

if (routeData.groupId) {
  payload.aps['thread-id'] = String(routeData.groupId);
} else if (routeData.sender_id) {
  payload.aps['thread-id'] = String(routeData.sender_id);
}

process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
NODE

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Would push APNs fixture %s to simulator %s for %s:\n' \
    "$fixture_path" "$device" "$bundle_id"
  cat "$payload_file"
  exit 0
fi

xcrun simctl push "$device" "$bundle_id" "$payload_file"
