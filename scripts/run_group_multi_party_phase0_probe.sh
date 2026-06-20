#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="com.mknoon.app"
APP_PATH="$ROOT_DIR/build/ios/iphonesimulator/Runner.app"
TARGET="integration_test/group_multi_party_phase0_runtime_channel_probe.dart"
RUN_ID="phase0_$(date +%Y%m%dT%H%M%S)"
OUT_DIR="$ROOT_DIR/build/group-multi-party-phase0/$RUN_ID"
SHARED_DIR="$OUT_DIR/shared"
LOG_DIR="$OUT_DIR/logs"

default_rendezvous_address="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
default_quic_relay_address="/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
relay_addresses="${MKNOON_RELAY_ADDRESSES:-${RELIABILITY_RELAY_ADDRESSES:-${default_rendezvous_address},${default_quic_relay_address}}}"
devices_arg="${1:-${RELIABILITY_MULTI_DEVICE_IDS:-}}"

if [ -z "$devices_arg" ]; then
  devices_arg="$(
    xcrun simctl list devices booted -j |
      python3 -c '
import json, sys
data = json.load(sys.stdin)
devices = []
for runtime_devices in data.get("devices", {}).values():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("state") == "Booted" and "iPhone" in device.get("name", ""):
            devices.append(device["udid"])
print(",".join(devices[:3]))
'
  )"
fi

IFS=',' read -r -a devices <<<"$devices_arg"
if [ "${#devices[@]}" -lt 3 ]; then
  printf 'Phase 0 probe needs three booted iPhone simulator device IDs; got: %s\n' "$devices_arg" >&2
  exit 2
fi

mkdir -p "$SHARED_DIR" "$LOG_DIR"

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

write_runtime_config() {
  local device="$1"
  local scenario="$2"
  local role="$3"
  local container="$4"
  local db_name="phase0_${scenario}_${RUN_ID}_${role}.db"
  local config_path="$container/Documents/group_multi_party_phase0_runtime.json"

  mkdir -p "$container/Documents"
  cat >"$config_path" <<JSON
{
  "scenario": $(json_escape "$scenario"),
  "role": $(json_escape "$role"),
  "runId": $(json_escape "$RUN_ID"),
  "mode": "phase0-probe",
  "dbName": $(json_escape "$db_name"),
  "sharedDir": $(json_escape "$SHARED_DIR")
}
JSON
  printf '%s\n' "$config_path"
}

wait_for_marker() {
  local marker="$1"
  local deadline=$((SECONDS + 45))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -s "$marker" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

timed_build() {
  local label="$1"
  local log_file="$LOG_DIR/build_${label}.log"
  local start
  local end
  start="$(date +%s)"
  flutter build ios --simulator --debug --no-pub \
    --target "$TARGET" \
    --dart-define=MKNOON_RELAY_ADDRESSES="$relay_addresses" \
    >"$log_file" 2>&1
  end="$(date +%s)"
  printf '%s\t%s\t%s\n' "$label" "$((end - start))" "$log_file" >>"$OUT_DIR/build_times.tsv"
}

roles=(alice bob charlie)
scenarios=(private_abc_create private_reaction_roundtrip)

printf 'runId=%s\n' "$RUN_ID" | tee "$OUT_DIR/summary.txt"
printf 'devices=%s,%s,%s\n' "${devices[0]}" "${devices[1]}" "${devices[2]}" | tee -a "$OUT_DIR/summary.txt"
printf 'sharedDir=%s\n' "$SHARED_DIR" | tee -a "$OUT_DIR/summary.txt"
printf 'relayAddresses=%s\n' "$relay_addresses" | tee -a "$OUT_DIR/summary.txt"

timed_build first

for device in "${devices[@]:0:3}"; do
  xcrun simctl install "$device" "$APP_PATH"
done

for scenario_index in "${!scenarios[@]}"; do
  scenario="${scenarios[$scenario_index]}"
  if [ "$scenario_index" -gt 0 ]; then
    timed_build "scenario_${scenario_index}_cache_probe"
  fi

  for role_index in "${!roles[@]}"; do
    role="${roles[$role_index]}"
    device="${devices[$role_index]}"
    xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
    container="$(xcrun simctl get_app_container "$device" "$BUNDLE_ID" data)"
    config_path="$(write_runtime_config "$device" "$scenario" "$role" "$container")"
    marker="$SHARED_DIR/phase0_${scenario}_${role}.json"
    rm -f "$marker"

    printf 'launch scenario=%s role=%s device=%s config=%s\n' \
      "$scenario" "$role" "$device" "$config_path" | tee -a "$OUT_DIR/summary.txt"
    xcrun simctl launch "$device" "$BUNDLE_ID" >"$LOG_DIR/${scenario}_${role}_launch.log" 2>&1
    if ! wait_for_marker "$marker"; then
      printf 'Timed out waiting for %s\n' "$marker" >&2
      exit 1
    fi
    xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  done
done

python3 - "$SHARED_DIR" "$OUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

shared_dir = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
markers = sorted(shared_dir.glob("phase0_*.json"))
payloads = [json.loads(path.read_text()) for path in markers]
expected = {
    (scenario, role)
    for scenario in ("private_abc_create", "private_reaction_roundtrip")
    for role in ("alice", "bob", "charlie")
}
seen = {(item["scenario"], item["role"]) for item in payloads}
missing = sorted(expected - seen)
if missing:
    raise SystemExit(f"missing runtime markers: {missing}")
for item in payloads:
    if item.get("source") != "documents-file":
        raise SystemExit(f"unexpected runtime source: {item}")
    if not item.get("dbName", "").startswith(f"phase0_{item['scenario']}_"):
        raise SystemExit(f"bad dbName: {item}")
result = {
    "ok": True,
    "markerCount": len(payloads),
    "markers": payloads,
}
(out_dir / "runtime_visibility_verdict.json").write_text(
    json.dumps(result, indent=2) + "\n"
)
PY

printf 'PASS: Phase 0 runtime channel probe artifacts in %s\n' "$OUT_DIR" | tee -a "$OUT_DIR/summary.txt"
