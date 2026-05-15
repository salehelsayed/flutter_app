#!/bin/bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────
DEVICE_A="347FB118-10D0-40C8-A05B-B0C3BD6B8CCD"
DEVICE_B="5BA69F1C-B112-47BE-B1FF-8C1003728C8F"
DEVICE_C="1B098DFF-6294-407A-A209-BBF360893485"
DEVICE_D="38FECA55-03C1-4907-BD9D-8E64BF8E3469"
INTRO_E2E_DEVICE_SET="${INTRO_E2E_DEVICE_SET:-three}"

case "$INTRO_E2E_DEVICE_SET" in
  three)
    DEVICES=("$DEVICE_A" "$DEVICE_B" "$DEVICE_C")
    NAMES=("a" "b" "c")
    ;;
  four)
    DEVICES=("$DEVICE_A" "$DEVICE_B" "$DEVICE_C" "$DEVICE_D")
    NAMES=("a" "b" "c" "d")
    ;;
  *)
    echo "ERROR: Unknown INTRO_E2E_DEVICE_SET=$INTRO_E2E_DEVICE_SET" >&2
    exit 1
    ;;
esac

BUNDLE_ID="com.mknoon.app"
DEVICE_COUNT="${#DEVICES[@]}"

flutter_build_for_name() {
  local name="$1"
  local log_file
  local attempt
  log_file="$(mktemp "${TMPDIR:-/tmp}/intro-e2e-flutter-build.XXXXXX")"

  for attempt in 1 2; do
    if flutter build ios --simulator --no-pub \
      --dart-define="AUTO_SETUP_USERNAME=$name" \
      --dart-define=E2E_TEST_MODE=true \
      --dart-define=DISABLE_LOCAL_DISCOVERY=true \
      >"$log_file" 2>&1; then
      tail -3 "$log_file"
      rm -f "$log_file"
      return 0
    fi

    if [ "$attempt" -lt 2 ] &&
       grep -q 'Xcode build is missing expected TARGET_BUILD_DIR build setting' "$log_file"; then
      tail -6 "$log_file" >&2
      echo "  [$name] Retrying Flutter build after transient Xcode build-settings failure ..." >&2
      sleep 5
      continue
    fi

    tail -40 "$log_file" >&2
    echo "  [$name] Flutter build log: $log_file" >&2
    return 1
  done
}

# ── Step 1: Uninstall ──────────────────────────────────────
echo "=== Step 1/3: Uninstalling from all devices ==="
for dev in "${DEVICES[@]}"; do
  xcrun simctl uninstall "$dev" "$BUNDLE_ID" 2>/dev/null || true
done
echo "  Done."

# ── Step 2: Boot simulators ───────────────────────────────
echo ""
echo "=== Step 2/3: Booting simulators ==="
for dev in "${DEVICES[@]}"; do
  xcrun simctl boot "$dev" 2>/dev/null || true
done
open -a Simulator
sleep 2
echo "  Done."

# ── Pre-grant notification permission ─────────────────────
echo ""
echo "=== Pre-granting notification permission ==="
for dev in "${DEVICES[@]}"; do
  xcrun simctl privacy "$dev" grant notifications "$BUNDLE_ID" 2>/dev/null || true
done
echo "  Done."

# ── Step 3: Build + install + launch per device ───────────
echo ""
echo "=== Step 3/3: Building & launching (one build per device) ==="
echo ""

for i in "${!DEVICES[@]}"; do
  dev="${DEVICES[$i]}"
  name="${NAMES[$i]}"
  echo "  [$name] Building with AUTO_SETUP_USERNAME=$name E2E_TEST_MODE=true DISABLE_LOCAL_DISCOVERY=true ..."
  flutter_build_for_name "$name"
  echo "  [$name] Installing + launching ..."
  xcrun simctl install "$dev" build/ios/iphonesimulator/Runner.app
  xcrun simctl privacy "$dev" grant notifications "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$dev" "$BUNDLE_ID"
  echo "  [$name] Running."
  echo ""
done

echo "=== All $DEVICE_COUNT simulators running: ${NAMES[*]} ==="
