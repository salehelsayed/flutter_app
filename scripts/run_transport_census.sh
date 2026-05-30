#!/usr/bin/env bash
#
# run_transport_census.sh — TWO-device orchestrator for the 1:1 transport census.
#
# Both devices run the SAME harness (integration_test/transport_census_harness.dart),
# each with a FRESH in-harness identity saved to a fresh per-role test DB. There
# is NO cross-device filesystem and NO onboarding/contacts precondition.
#
# Coordination is a ONE-DIRECTION stdout->dart-define exchange:
#   1. Launch the RECEIVER in the BACKGROUND. It prints exactly one line:
#        CENSUS_PEER_IDENTITY={"peerId":...,"publicKey":...,"mlKemPublicKey":...,"rendezvous":...}
#   2. The orchestrator polls receiver.log for that line and extracts the JSON.
#   3. Launch the SENDER in the FOREGROUND with --dart-define=CENSUS_PEER_JSON=<json>.
#      It adds the receiver as a contact and sends N real 1:1 messages, then
#      dumps the SENDER-vantage census between ===CENSUS_BEGIN===/===CENSUS_END===.
#
# Per-device dispatch:
#   - iOS device id (UUID/UDID) -> flutter drive (integration_test driver, --publish-port)
#   - any other device id       -> flutter test
#
# Usage:
#   scripts/run_transport_census.sh \
#     --condition <label> --n <int> --cold <true|false> \
#     --sender-device <id> --receiver-device <id> \
#     [--interval-ms <int>] [--relay <csv>] [--run-id <id>]
#
# Example (Condition A_cold, iPhone13 sends; Pixel6 receives):
#   scripts/run_transport_census.sh --condition A_cold --n 50 --cold true \
#     --sender-device 00008110-00184D622289801E \
#     --receiver-device 21071FDF600CSC
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CONDITION="unspecified"
N=50
COLD="true"
SENDER_DEVICE=""
RECEIVER_DEVICE=""
RELAY="${MKNOON_RELAY_ADDRESSES:-}"
INTERVAL_MS=2500
RUN_ID="$(date +%s)"

HARNESS="integration_test/transport_census_harness.dart"

# ---------------------------------------------------------------------------
# Arg parsing (flags)
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --condition)        CONDITION="$2"; shift 2 ;;
    --n)                N="$2"; shift 2 ;;
    --cold)             COLD="$2"; shift 2 ;;
    --sender-device)    SENDER_DEVICE="$2"; shift 2 ;;
    --receiver-device)  RECEIVER_DEVICE="$2"; shift 2 ;;
    --interval-ms)      INTERVAL_MS="$2"; shift 2 ;;
    --relay)            RELAY="$2"; shift 2 ;;
    --run-id)           RUN_ID="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$SENDER_DEVICE" ]]; then
  echo "ERROR: --sender-device is required" >&2
  exit 64
fi
if [[ -z "$RECEIVER_DEVICE" ]]; then
  echo "ERROR: --receiver-device is required" >&2
  exit 64
fi

# ---------------------------------------------------------------------------
# Host log dir + per-role logs
# ---------------------------------------------------------------------------
LOG_DIR="/tmp/transport_census_${RUN_ID}"
mkdir -p "$LOG_DIR"
RECEIVER_LOG="$LOG_DIR/receiver.log"
SENDER_LOG="$LOG_DIR/sender.log"

cat <<EOF
============================================================
[CENSUS] Transport census (TWO-device orchestrator)
[CENSUS]   condition=$CONDITION n=$N cold=$COLD interval=${INTERVAL_MS}ms
[CENSUS]   sender-device=$SENDER_DEVICE
[CENSUS]   receiver-device=$RECEIVER_DEVICE
[CENSUS]   relay=${RELAY:-<built-in default relay>}
[CENSUS]   run-id=$RUN_ID  logs=$LOG_DIR
============================================================
[CENSUS] Both devices run the harness with a FRESH identity per run.
[CENSUS]   * The receiver auto-announces its identity on stdout; this script
[CENSUS]     wires it to the sender. No onboarding/contacts precondition.
[CENSUS]   * Condition A (same-LAN): put BOTH phones on the SAME Wi-Fi.
[CENSUS]   * Condition B (cross-network): put ONE phone on cellular / a
[CENSUS]     DIFFERENT network so the LAN/direct path is unavailable.
[CENSUS]   * iOS: allow the Local Network permission prompt on first launch.
============================================================
EOF

# ---------------------------------------------------------------------------
# iOS detection: an iOS device id is a CoreDevice UUID (8 hex + dash + 16 hex)
# or a classic UDID. Everything else -> flutter test (e.g. Android serials).
# ---------------------------------------------------------------------------
is_ios_device() {
  local id="$1"
  if [[ "$id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$ ]]; then return 0; fi
  if [[ "$id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then return 0; fi
  return 1
}

# Build a launch command array for a given device + extra dart-defines.
# Usage: build_cmd <device-id> <define...>  -> sets global LAUNCH_CMD array.
#
# NOTE: we use `flutter test` for BOTH iOS and Android. `flutter test
# integration_test/... -d <ios-device>` runs on a physical iPhone AND forwards
# the app's print() output (verified earlier: wifi_transport_test 12/12 on the
# iPhone via flutter test). `flutter drive` does NOT forward the app's stdout
# (so the census dump never reaches the log) and wedged on connect — so it is
# NOT used here.
build_cmd() {
  local device="$1"; shift
  LAUNCH_CMD=(flutter test "$HARNESS" "$@" -d "$device")
}

# ---------------------------------------------------------------------------
# 1. Launch the RECEIVER in the BACKGROUND.
# ---------------------------------------------------------------------------
RECEIVER_DEFINES=(
  "--dart-define=CENSUS_ROLE=receiver"
  "--dart-define=CENSUS_CONDITION=${CONDITION}"
  "--dart-define=CENSUS_N=${N}"
  "--dart-define=CENSUS_SEND_INTERVAL_MS=${INTERVAL_MS}"
  "--dart-define=E2E_DB_NAME=census_receiver.db"
  "--dart-define=MKNOON_RELAY_ADDRESSES=${RELAY}"
)
build_cmd "$RECEIVER_DEVICE" "${RECEIVER_DEFINES[@]}"

echo "[CENSUS] launching RECEIVER (background):"
echo "[CENSUS]   ${LAUNCH_CMD[*]}"
echo "[CENSUS]   log: $RECEIVER_LOG"
echo ""

# Run in its own process group so we can kill the whole tree later.
set +e
"${LAUNCH_CMD[@]}" >"$RECEIVER_LOG" 2>&1 &
RECEIVER_PID=$!
set -e

cleanup_receiver() {
  echo "[CENSUS] stopping receiver (pid $RECEIVER_PID)..."
  kill "$RECEIVER_PID" 2>/dev/null || true
  # Best-effort: kill the whole process group too.
  kill -- "-$RECEIVER_PID" 2>/dev/null || true
}
trap cleanup_receiver EXIT

# ---------------------------------------------------------------------------
# 2. Poll receiver.log for the CENSUS_PEER_IDENTITY= line.
# ---------------------------------------------------------------------------
echo "[CENSUS] waiting for receiver identity (timeout 480s)..."
PEER_JSON=""
DEADLINE=$(( $(date +%s) + 480 ))
while [[ $(date +%s) -lt $DEADLINE ]]; do
  if [[ -f "$RECEIVER_LOG" ]]; then
    LINE="$(grep -m1 'CENSUS_PEER_IDENTITY=' "$RECEIVER_LOG" || true)"
    if [[ -n "$LINE" ]]; then
      # Everything after the FIRST '=' is the JSON payload.
      PEER_JSON="${LINE#*CENSUS_PEER_IDENTITY=}"
      break
    fi
  fi
  # Bail early if the receiver process already died.
  if ! kill -0 "$RECEIVER_PID" 2>/dev/null; then
    echo "[CENSUS] ERROR: receiver process exited before announcing identity." >&2
    echo "[CENSUS] ---- receiver.log tail ----" >&2
    tail -n 60 "$RECEIVER_LOG" >&2 || true
    exit 1
  fi
  sleep 2
done

if [[ -z "$PEER_JSON" ]]; then
  echo "[CENSUS] ERROR: receiver never announced CENSUS_PEER_IDENTITY within 480s." >&2
  echo "[CENSUS] ---- receiver.log tail ----" >&2
  tail -n 60 "$RECEIVER_LOG" >&2 || true
  exit 1
fi

echo "[CENSUS] received peer identity JSON:"
echo "[CENSUS]   $PEER_JSON"
echo ""

# ---------------------------------------------------------------------------
# 3. Launch the SENDER in the FOREGROUND with the peer JSON injected.
# ---------------------------------------------------------------------------
# Base64-encode the peer JSON so the dart-define value has NO quotes/spaces
# (raw JSON with `"` breaks dart-define/Xcode arg handling). The harness
# decodes CENSUS_PEER_B64 in preference to CENSUS_PEER_JSON.
PEER_B64="$(printf '%s' "$PEER_JSON" | base64 | tr -d '\n')"

SENDER_DEFINES=(
  "--dart-define=CENSUS_ROLE=sender"
  "--dart-define=CENSUS_CONDITION=${CONDITION}"
  "--dart-define=CENSUS_N=${N}"
  "--dart-define=CENSUS_COLD=${COLD}"
  "--dart-define=CENSUS_SEND_INTERVAL_MS=${INTERVAL_MS}"
  "--dart-define=E2E_DB_NAME=census_sender.db"
  "--dart-define=MKNOON_RELAY_ADDRESSES=${RELAY}"
  "--dart-define=CENSUS_PEER_B64=${PEER_B64}"
)
build_cmd "$SENDER_DEVICE" "${SENDER_DEFINES[@]}"

echo "[CENSUS] launching SENDER (foreground):"
echo "[CENSUS]   ${LAUNCH_CMD[*]}"
echo "[CENSUS]   log: $SENDER_LOG"
echo ""

RC=0
"${LAUNCH_CMD[@]}" 2>&1 | tee "$SENDER_LOG" || RC=$?

# ---------------------------------------------------------------------------
# 4. Print the SENDER-vantage census block, then stop the receiver.
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "[CENSUS] RUN COMPLETE — condition=$CONDITION rc=$RC"
echo "[CENSUS] sender log:   $SENDER_LOG"
echo "[CENSUS] receiver log: $RECEIVER_LOG"
echo "============================================================"
echo "[CENSUS] ===== census block (SENDER vantage — authoritative) ====="
awk '/===CENSUS_BEGIN===/,/===CENSUS_END===/' "$SENDER_LOG" || true

# trap EXIT will kill the receiver.
exit "$RC"
