#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

go_fixture=go-relay-server/production_audio_call_device_fixture_test.go
dart_fixture=integration_test/scripts/production_audio_call_local_fixture.dart
wrapper=integration_test/scripts/run_production_audio_call_sims.dart
lock=tool/call_audio_oracle/coturn.lock.json

for path in "$go_fixture" "$dart_fixture" "$wrapper" "$lock"; do
  [ -f "$path" ] || fail "missing production audio-call fixture contract file: $path"
done

wrapper_probe_file="$(mktemp)"
trap 'rm -f "$wrapper_probe_file"' EXIT
dart "$wrapper" --probe-source-extension >"$wrapper_probe_file"
WRAPPER_PROBE_FILE="$wrapper_probe_file" python3 - <<'PY'
import json
import os

with open(os.environ["WRAPPER_PROBE_FILE"], encoding="utf-8") as source:
    probe = json.load(source)

assert probe == {
    "scenario": "android.production_1to1_audio_call",
    "executionBoundary": "ephemeral_production_relay_coturn_fixture",
    "coturn": "digest-pinned",
    "mediaOracle": "pion-known-opus",
    "centralPreparation": True,
    "goToolchain": "go1.25.0",
}
PY

for fragment in \
  'TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown' \
  'startDirectMediaDeviceFixture' \
  'registerRelayProtocolHandlers' \
  'NewTurnCredentialService' \
  'mknoon.call_audio_oracle.credentials.v1' \
  'fixture_instance_sha256' \
  'coturn/coturn:4.17.2-r0' \
  'CALL_AUDIO_ORACLE_CREDENTIALS_FILE' \
  'CALL_AUDIO_ORACLE_RESULT_FILE'; do
  rg -Fq "$fragment" "$go_fixture" ||
    fail "Go fixture omitted required production fragment: $fragment"
done

for fragment in \
  'ProductionAudioCallLocalFixtureLease' \
  'resolveProductionAudioCallLocalFixtureHostIp' \
  "'GOTOOLCHAIN': 'go1.25.0'" \
  'verifyAndroidPairAndReachability' \
  'runAudioOracle' \
  'expectedFixtureInstanceSha256' \
  "r'^TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown$'" \
  "r'^TestKnownOpusBothDirectionsOverRestAuthenticatedCoturn$'" \
  '.postUrl(Uri.parse(probeUrl))' \
  'HttpStatus.noContent'; do
  rg -Fq "$fragment" "$dart_fixture" ||
    fail "Dart fixture adapter omitted required fragment: $fragment"
done

for fragment in \
  'coturnInstanceIdentitySha256' \
  'PLAN399_LOCAL_COTURN_INSTANCE_SHA256'; do
  rg -Fq "$fragment" "$wrapper" ||
    fail "production audio-call wrapper omitted fixture-instance binding: $fragment"
done

if rg -n 'static-auth-secret|primarySecret|password' "$dart_fixture" >/dev/null; then
  fail 'Dart fixture adapter may not receive or retain TURN secret/password material'
fi

printf 'PASS: combined production audio-call relay/coturn fixture contract is pinned and private\n'
