#!/bin/bash
set -euo pipefail

DEVICE_A="347FB118-10D0-40C8-A05B-B0C3BD6B8CCD"
DEVICE_B="5BA69F1C-B112-47BE-B1FF-8C1003728C8F"
DEVICE_C="1B098DFF-6294-407A-A209-BBF360893485"
BUNDLE_ID="com.mknoon.app"
EXPORT_FILE="intro_e2e_identity.json"
CONFIG_FILE="intro_e2e_config.json"
RESULT_FILE="intro_e2e_result.json"
INTRO_E2E_SCENARIO="${INTRO_E2E_SCENARIO:-all}"
ARTIFACT_ROOT="build/intro_e2e"

get_docs_dir() {
  local container
  container=$(xcrun simctl get_app_container "$1" "$BUNDLE_ID" data 2>/dev/null)
  if [ -z "$container" ]; then
    echo ""
    return
  fi
  echo "$container/Documents"
}

contact_entry_json() {
  echo "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(json.dumps({
  "qrPayload": d["qrPayload"],
  "mlKemPublicKey": d.get("mlKemPublicKey"),
}))
'
}

read_export() {
  local device="$1"
  local docs
  docs=$(get_docs_dir "$device")
  if [ -z "$docs" ]; then
    echo "ERROR: Could not resolve Documents directory for $device" >&2
    exit 1
  fi
  local export_file="$docs/$EXPORT_FILE"
  local deadline=$((SECONDS + 240))
  while [ ! -f "$export_file" ]; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: Timed out waiting for $export_file" >&2
      exit 1
    fi
    sleep 2
  done
  cat "$export_file"
}

peer_id_from_export() {
  echo "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
qr = json.loads(d["qrPayload"])
print(qr["ns"])
'
}

username_from_export() {
  echo "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
qr = json.loads(d["qrPayload"])
print(qr["un"])
'
}

write_config() {
  local device="$1"
  local json="$2"
  local docs
  docs=$(get_docs_dir "$device")
  if [ -z "$docs" ]; then
    echo "ERROR: Could not resolve Documents directory for $device" >&2
    exit 1
  fi
  printf '%s\n' "$json" > "$docs/$CONFIG_FILE"
}

clear_results() {
  for dev in "$DEVICE_A" "$DEVICE_B" "$DEVICE_C"; do
    local docs
    docs=$(get_docs_dir "$dev")
    [ -n "$docs" ] || continue
    rm -f "$docs/$RESULT_FILE"
  done
}

relaunch_all() {
  for dev in "$DEVICE_A" "$DEVICE_B" "$DEVICE_C"; do
    xcrun simctl terminate "$dev" "$BUNDLE_ID" 2>/dev/null || true
  done
  sleep 1
  for dev in "$DEVICE_A" "$DEVICE_B" "$DEVICE_C"; do
    xcrun simctl launch "$dev" "$BUNDLE_ID" >/dev/null
  done
}

wait_for_step_result() {
  local device="$1"
  local step_id="$2"
  local docs
  docs=$(get_docs_dir "$device")
  local result_file="$docs/$RESULT_FILE"
  local deadline=$((SECONDS + 240))

  while true; do
    if [ -f "$result_file" ]; then
      local status
      status=$(python3 - "$result_file" "$step_id" <<'PY'
import json, sys
path, step_id = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
if data.get("stepId") != step_id:
    print("mismatch")
elif data.get("status") == "failed":
    print("failed")
elif data.get("status") == "complete":
    print("complete")
else:
    print("running")
PY
)
      case "$status" in
        complete)
          return
          ;;
        failed)
          echo "ERROR: Step $step_id failed on $device" >&2
          cat "$result_file" >&2
          exit 1
          ;;
      esac
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: Timed out waiting for $step_id on $device" >&2
      [ -f "$result_file" ] && cat "$result_file" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_all_results() {
  local step_id="$1"
  wait_for_step_result "$DEVICE_A" "$step_id"
  wait_for_step_result "$DEVICE_B" "$step_id"
  wait_for_step_result "$DEVICE_C" "$step_id"
}

result_file_path() {
  local docs
  docs=$(get_docs_dir "$1")
  echo "$docs/$RESULT_FILE"
}

capture_step_screenshots() {
  local step_id="$1"
  local dir="$ARTIFACT_ROOT/$step_id"
  mkdir -p "$dir"
  xcrun simctl io "$DEVICE_A" screenshot "$dir/a.png" >/dev/null
  xcrun simctl io "$DEVICE_B" screenshot "$dir/b.png" >/dev/null
  xcrun simctl io "$DEVICE_C" screenshot "$dir/c.png" >/dev/null
  echo "  Screenshots: $dir"
}

assert_system_message_for_contact() {
  local result_path="$1"
  local contact_peer_id="$2"
  local expected_text="$3"
  python3 - "$result_path" "$contact_peer_id" "$expected_text" <<'PY'
import json, sys
result_path, contact_peer_id, expected_text = sys.argv[1:]
snapshot = json.load(open(result_path))["snapshot"]
messages = []
for row in snapshot.get("systemMessages", []):
    if row.get("contactPeerId") == contact_peer_id:
        messages.extend(message.get("text") for message in row.get("messages", []))
assert expected_text in messages, {
    "contactPeerId": contact_peer_id,
    "expected": expected_text,
    "messages": messages,
}
PY
}

assert_handshake() {
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c = sys.argv[1:]
snap_a = json.load(open(path_a))["snapshot"]
snap_b = json.load(open(path_b))["snapshot"]
snap_c = json.load(open(path_c))["snapshot"]

contacts_a = {c["peerId"] for c in snap_a["contacts"]}
contacts_b = {c["peerId"] for c in snap_b["contacts"]}
contacts_c = {c["peerId"] for c in snap_c["contacts"]}

assert peer_b in contacts_a and peer_c in contacts_a, snap_a
assert peer_a in contacts_b, snap_b
assert peer_a in contacts_c, snap_c
assert not snap_a["pendingContactRequests"], snap_a
assert not snap_b["pendingContactRequests"], snap_b
assert not snap_c["pendingContactRequests"], snap_c
PY
}

assert_pair_state() {
  local expected_status="$1"
  local expect_contact="$2"
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" "$expected_status" "$expect_contact" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c, expected_status, expect_contact = sys.argv[1:]
snapshots = [json.load(open(path))["snapshot"] for path in (path_a, path_b, path_c)]
b_snap = snapshots[1]
c_snap = snapshots[2]

def pair_rows(snapshot):
    rows = []
    for row in snapshot["introductions"]:
        if row["introducerId"] != peer_a:
            continue
        if {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}:
            rows.append(row)
    return rows

b_rows = pair_rows(b_snap)
c_rows = pair_rows(c_snap)
assert len(b_rows) == 1, b_snap
assert len(c_rows) == 1, c_snap
assert b_rows[0]["id"] == c_rows[0]["id"], (b_rows, c_rows)
assert b_rows[0]["overallStatus"] == expected_status, b_rows
assert c_rows[0]["overallStatus"] == expected_status, c_rows

if expect_contact == "yes":
    b_contacts = {c["peerId"] for c in b_snap["contacts"]}
    c_contacts = {c["peerId"] for c in c_snap["contacts"]}
    assert peer_c in b_contacts, b_snap
    assert peer_b in c_contacts, c_snap
PY
}

assert_copy_send_messages() {
  assert_system_message_for_contact \
    "$(result_file_path "$DEVICE_A")" \
    "$PEER_B" \
    "You introduced $USER_C to $USER_B"
  assert_system_message_for_contact \
    "$(result_file_path "$DEVICE_B")" \
    "$PEER_A" \
    "$USER_A introduced $USER_C to you"
  assert_system_message_for_contact \
    "$(result_file_path "$DEVICE_C")" \
    "$PEER_A" \
    "$USER_A introduced you to $USER_B"
}

assert_copy_accept_messages() {
  assert_system_message_for_contact \
    "$(result_file_path "$DEVICE_A")" \
    "$PEER_B" \
    "You introduced $USER_C to $USER_B"
  assert_system_message_for_contact \
    "$(result_file_path "$DEVICE_B")" \
    "$PEER_C" \
    "You and $USER_C are now connected — introduced by $USER_A"
  assert_system_message_for_contact \
    "$(result_file_path "$DEVICE_C")" \
    "$PEER_B" \
    "You and $USER_B are now connected — introduced by $USER_A"
}

prepare_devices() {
  echo ""
  echo "=== Preparing three intro E2E simulators ==="
  ./reset_simulators.sh

  EXPORT_A=$(read_export "$DEVICE_A")
  EXPORT_B=$(read_export "$DEVICE_B")
  EXPORT_C=$(read_export "$DEVICE_C")

  PEER_A=$(peer_id_from_export "$EXPORT_A")
  PEER_B=$(peer_id_from_export "$EXPORT_B")
  PEER_C=$(peer_id_from_export "$EXPORT_C")
  USER_A=$(username_from_export "$EXPORT_A")
  USER_B=$(username_from_export "$EXPORT_B")
  USER_C=$(username_from_export "$EXPORT_C")

  CONTACT_A_JSON=$(contact_entry_json "$EXPORT_A")
  CONTACT_B_JSON=$(contact_entry_json "$EXPORT_B")
  CONTACT_C_JSON=$(contact_entry_json "$EXPORT_C")

  echo "  [a] $USER_A $PEER_A"
  echo "  [b] $USER_B $PEER_B"
  echo "  [c] $USER_C $PEER_C"
}

run_handshake_phase() {
  local step_id="$1"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "add_contacts": [
    $CONTACT_B_JSON,
    $CONTACT_C_JSON
  ],
  "contact_request_action": "none",
  "introduction_action": "none",
  "contact_settle_delay_ms": 1000
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "add_contacts": [
    $CONTACT_A_JSON
  ],
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 25,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "add_contacts": [
    $CONTACT_A_JSON
  ],
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 25,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
  assert_handshake
}

run_intro_phase() {
  local step_id="$1"
  local b_intro_action="$2"
  local c_intro_action="$3"
  local b_contact_action="${4:-none}"
  local c_contact_action="${5:-none}"

  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "send_introductions": [
    {
      "recipientPeerId": "$PEER_B",
      "friendPeerIds": ["$PEER_C"]
    }
  ],
  "contact_request_action": "none",
  "introduction_action": "none",
  "introduction_settle_delay_ms": 3000
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "$b_contact_action",
  "introduction_action": "$b_intro_action",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "$c_contact_action",
  "introduction_action": "$c_intro_action",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_copy_send_phase() {
  local step_id="copy-send"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "send_introductions": [
    {
      "recipientPeerId": "$PEER_B",
      "friendPeerIds": ["$PEER_C"]
    }
  ],
  "contact_request_action": "none",
  "introduction_action": "none",
  "introduction_settle_delay_ms": 3000,
  "open_conversation_with_peer_id": "$PEER_B",
  "post_navigation_delay_ms": 2500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500,
  "open_conversation_with_peer_id": "$PEER_A",
  "post_navigation_delay_ms": 2500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500,
  "open_conversation_with_peer_id": "$PEER_A",
  "post_navigation_delay_ms": 2500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
  assert_copy_send_messages
  capture_step_screenshots "$step_id"
}

run_copy_accept_phase() {
  local step_id="copy-accept"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500,
  "open_conversation_with_peer_id": "$PEER_B",
  "post_navigation_delay_ms": 2500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "accept_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500,
  "open_conversation_with_peer_id": "$PEER_C",
  "post_navigation_delay_ms": 2500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "accept_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500,
  "open_conversation_with_peer_id": "$PEER_B",
  "post_navigation_delay_ms": 2500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
  assert_copy_accept_messages
  capture_step_screenshots "$step_id"
}

scenario_happy_path() {
  echo ""
  echo "=== Scenario 1/4: Happy path mutual acceptance ==="
  prepare_devices
  run_handshake_phase "happy-handshake"
  run_intro_phase "happy-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_resend_refresh_pending() {
  echo ""
  echo "=== Scenario 2/4: Re-send refreshes both pending rows ==="
  prepare_devices
  run_handshake_phase "refresh-handshake"
  run_intro_phase "refresh-first-intro" "none" "none"
  run_intro_phase "refresh-resend-intro" "none" "none"
  assert_pair_state "pending" "no"
  run_intro_phase "refresh-final-accept" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_resend_after_pass() {
  echo ""
  echo "=== Scenario 3/4: Re-send revives a passed intro ==="
  prepare_devices
  run_handshake_phase "pass-handshake"
  run_intro_phase "pass-first-intro" "pass_all" "none"
  run_intro_phase "pass-resend-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_repair_missing_side() {
  echo ""
  echo "=== Scenario 4/4: Re-send repairs the missing side ==="
  prepare_devices
  run_handshake_phase "repair-handshake"
  run_intro_phase "repair-first-intro" "none" "drop_first"
  run_intro_phase "repair-resend-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_visible_copy_review() {
  echo ""
  echo "=== Scenario 5/5: Visible intro copy across all three users ==="
  prepare_devices
  run_handshake_phase "copy-handshake"
  run_copy_send_phase
  run_copy_accept_phase
  assert_pair_state "mutual_accepted" "yes"
}

case "$INTRO_E2E_SCENARIO" in
  all)
    scenario_happy_path
    scenario_resend_refresh_pending
    scenario_resend_after_pass
    scenario_repair_missing_side
    scenario_visible_copy_review
    ;;
  happy)
    scenario_happy_path
    ;;
  refresh)
    scenario_resend_refresh_pending
    ;;
  pass)
    scenario_resend_after_pass
    ;;
  repair)
    scenario_repair_missing_side
    ;;
  copy)
    scenario_visible_copy_review
    ;;
  *)
    echo "ERROR: Unknown INTRO_E2E_SCENARIO=$INTRO_E2E_SCENARIO" >&2
    exit 1
    ;;
esac

echo ""
echo "=== Intro E2E harness passed ==="
