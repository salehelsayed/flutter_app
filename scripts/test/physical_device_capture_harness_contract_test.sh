#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

core="integration_test/scripts/physical_device_capture_harness.dart"
[ -f "$core" ] || {
  printf 'FAIL: shared physical-device capture harness is missing\n' >&2
  exit 1
}

for runner in \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/scripts/run_group_muted_notification_android.dart \
  integration_test/scripts/run_group_notification_projection_android.dart \
  integration_test/scripts/run_group_strict_notification_sims.dart; do
  grep -Fq "import 'physical_device_capture_harness.dart';" "$runner" || {
    printf 'FAIL: %s does not import the shared capture harness\n' "$runner" >&2
    exit 1
  }
  grep -Fq 'PhysicalDeviceCaptureAdapter(' "$runner" || {
    printf 'FAIL: %s does not declare a plan adapter\n' "$runner" >&2
    exit 1
  }
  grep -Fq 'runPhysicalDeviceCapture(' "$runner" || {
    printf 'FAIL: %s bypasses the shared capture lifecycle\n' "$runner" >&2
    exit 1
  }
  if grep -Fq 'Process.start(' "$runner"; then
    printf 'FAIL: %s still launches capture directly\n' "$runner" >&2
    exit 1
  fi
done

printf 'PASS: physical-device plans use the shared capture adapter\n'
