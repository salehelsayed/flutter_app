#!/bin/bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────
DEVICE_A="347FB118-10D0-40C8-A05B-B0C3BD6B8CCD"
DEVICE_B="5BA69F1C-B112-47BE-B1FF-8C1003728C8F"
DEVICE_C="1B098DFF-6294-407A-A209-BBF360893485"
DEVICES=("$DEVICE_A" "$DEVICE_B" "$DEVICE_C")
NAMES=("a" "b" "c")
BUNDLE_ID="com.mknoon.app"

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
  echo "  [$name] Building with AUTO_SETUP_USERNAME=$name E2E_TEST_MODE=true ..."
  flutter build ios --simulator --no-pub \
    --dart-define="AUTO_SETUP_USERNAME=$name" \
    --dart-define=E2E_TEST_MODE=true \
    2>&1 | tail -3
  echo "  [$name] Installing + launching ..."
  xcrun simctl install "$dev" build/ios/iphonesimulator/Runner.app
  xcrun simctl privacy "$dev" grant notifications "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$dev" "$BUNDLE_ID"
  echo "  [$name] Running."
  echo ""
done

echo "=== All 3 simulators running: a, b, c ==="
