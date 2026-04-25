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
  clear_results_for_devices "$DEVICE_A" "$DEVICE_B" "$DEVICE_C"
}

clear_results_for_devices() {
  for dev in "$@"; do
    local docs
    docs=$(get_docs_dir "$dev")
    [ -n "$docs" ] || continue
    rm -f "$docs/$RESULT_FILE"
  done
}

relaunch_all() {
  relaunch_devices "$DEVICE_A" "$DEVICE_B" "$DEVICE_C"
}

relaunch_devices() {
  for dev in "$@"; do
    xcrun simctl terminate "$dev" "$BUNDLE_ID" 2>/dev/null || true
  done
  sleep 1
  for dev in "$@"; do
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
try:
    with open(path) as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    # The app rewrites this file as it moves from running to complete.
    print("running")
    sys.exit(0)
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
  wait_for_results_for_devices "$step_id" "$DEVICE_A" "$DEVICE_B" "$DEVICE_C"
}

wait_for_results_for_devices() {
  local step_id="$1"
  shift
  for dev in "$@"; do
    wait_for_step_result "$dev" "$step_id"
  done
}

result_file_path() {
  local docs
  docs=$(get_docs_dir "$1")
  echo "$docs/$RESULT_FILE"
}

capture_step_screenshots() {
  local step_id="$1"
  local dir="$PWD/$ARTIFACT_ROOT/$step_id"
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

assert_chat_message_for_contact() {
  local result_path="$1"
  local contact_peer_id="$2"
  local expected_text="$3"
  python3 - "$result_path" "$contact_peer_id" "$expected_text" <<'PY'
import json, sys
result_path, contact_peer_id, expected_text = sys.argv[1:]
snapshot = json.load(open(result_path))["snapshot"]
messages = []
for row in snapshot.get("chatMessages", []):
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
    b_to_c_contacts = [c for c in b_snap["contacts"] if c["peerId"] == peer_c]
    c_to_b_contacts = [c for c in c_snap["contacts"] if c["peerId"] == peer_b]
    assert len(b_to_c_contacts) == 1, b_snap
    assert len(c_to_b_contacts) == 1, c_snap
PY
}

pair_intro_id_from_result() {
  local result_path="$1"
  python3 - "$result_path" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
result_path, peer_a, peer_b, peer_c = sys.argv[1:]
snapshot = json.load(open(result_path))["snapshot"]
rows = [
    row for row in snapshot["introductions"]
    if row["introducerId"] == peer_a
    and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
]
assert len(rows) == 1, snapshot
print(rows[0]["id"])
PY
}

assert_pair_intro_id_equals() {
  local result_path="$1"
  local expected_intro_id="$2"
  python3 - "$result_path" "$PEER_A" "$PEER_B" "$PEER_C" "$expected_intro_id" <<'PY'
import json, sys
result_path, peer_a, peer_b, peer_c, expected_intro_id = sys.argv[1:]
snapshot = json.load(open(result_path))["snapshot"]
rows = [
    row for row in snapshot["introductions"]
    if row["introducerId"] == peer_a
    and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
]
assert len(rows) == 1, snapshot
assert rows[0]["id"] == expected_intro_id, rows
PY
}

assert_partial_fanout_mid_state() {
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c = sys.argv[1:]
result_a = json.load(open(path_a))
result_b = json.load(open(path_b))
result_c = json.load(open(path_c))
assert result_a["stepId"] == "partial-send", result_a
assert result_b["stepId"] == "partial-send", result_b
assert result_c["stepId"] == "partial-send", result_c
snap_a = result_a["snapshot"]
snap_b = result_b["snapshot"]
snap_c = result_c["snapshot"]

def pair_rows(snapshot):
    return [
        row for row in snapshot["introductions"]
        if row["introducerId"] == peer_a
        and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
    ]

a_rows = pair_rows(snap_a)
b_rows = pair_rows(snap_b)
c_rows = pair_rows(snap_c)

assert len(a_rows) == 1, snap_a
assert len(b_rows) == 1, snap_b
assert len(c_rows) == 0, snap_c
assert a_rows[0]["id"] == b_rows[0]["id"], (a_rows, b_rows)
# The responder's local row is the proof that B received and acted.
# The introducer-side snapshot can lag while the same intro is still pending.
assert a_rows[0]["recipientStatus"] in {"pending", "accepted"}, a_rows
assert a_rows[0]["introducedStatus"] == "pending", a_rows
assert a_rows[0]["overallStatus"] == "pending", a_rows
assert b_rows[0]["recipientStatus"] == "accepted", b_rows
assert b_rows[0]["introducedStatus"] == "pending", b_rows
assert b_rows[0]["overallStatus"] == "pending", b_rows

b_contacts = [c["peerId"] for c in snap_b["contacts"]]
c_contacts = [c["peerId"] for c in snap_c["contacts"]]
assert peer_c not in b_contacts, snap_b
assert peer_b not in c_contacts, snap_c

node_action = result_c.get("nodeAction") or {}
assert node_action.get("action") == "stop_node", result_c
PY
}

assert_partition_mid_state() {
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c = sys.argv[1:]
result_a = json.load(open(path_a))
result_b = json.load(open(path_b))
result_c = json.load(open(path_c))
snap_a = result_a["snapshot"]
snap_b = result_b["snapshot"]
snap_c = result_c["snapshot"]

def pair_rows(snapshot):
    return [
        row for row in snapshot["introductions"]
        if row["introducerId"] == peer_a
        and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
    ]

a_rows = pair_rows(snap_a)
b_rows = pair_rows(snap_b)
c_rows = pair_rows(snap_c)

assert len(a_rows) == 1, snap_a
assert len(b_rows) == 1, snap_b
assert len(c_rows) == 1, snap_c
assert a_rows[0]["id"] == b_rows[0]["id"] == c_rows[0]["id"], (a_rows, b_rows, c_rows)

if a_rows[0]["overallStatus"] == "pending":
    assert a_rows[0]["recipientStatus"] == "pending", a_rows
    assert a_rows[0]["introducedStatus"] == "pending", a_rows
else:
    assert a_rows[0]["overallStatus"] == "mutual_accepted", a_rows
    assert a_rows[0]["recipientStatus"] == "accepted", a_rows
    assert a_rows[0]["introducedStatus"] == "accepted", a_rows
assert b_rows[0]["overallStatus"] == "mutual_accepted", b_rows
assert c_rows[0]["overallStatus"] == "mutual_accepted", c_rows

b_to_c_contacts = [c for c in snap_b["contacts"] if c["peerId"] == peer_c]
c_to_b_contacts = [c for c in snap_c["contacts"] if c["peerId"] == peer_b]
assert len(b_to_c_contacts) == 1, snap_b
assert len(c_to_b_contacts) == 1, snap_c

node_action = result_a.get("nodeAction") or {}
assert node_action.get("action") == "stop_node", result_a
PY
}

assert_pass_fallback_mid_state() {
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c = sys.argv[1:]
result_a = json.load(open(path_a))
result_b = json.load(open(path_b))
result_c = json.load(open(path_c))
snap_a = result_a["snapshot"]
snap_b = result_b["snapshot"]
snap_c = result_c["snapshot"]

def pair_rows(snapshot):
    return [
        row for row in snapshot["introductions"]
        if row["introducerId"] == peer_a
        and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
    ]

a_rows = pair_rows(snap_a)
b_rows = pair_rows(snap_b)
c_rows = pair_rows(snap_c)

assert len(a_rows) == 1, snap_a
assert len(b_rows) == 1, snap_b
assert len(c_rows) == 1, snap_c
assert a_rows[0]["id"] == b_rows[0]["id"] == c_rows[0]["id"], (a_rows, b_rows, c_rows)
assert a_rows[0]["overallStatus"] == "pending", a_rows
assert b_rows[0]["overallStatus"] == "passed", b_rows
assert c_rows[0]["overallStatus"] == "pending", c_rows

b_to_c_contacts = [c for c in snap_b["contacts"] if c["peerId"] == peer_c]
c_to_b_contacts = [c for c in snap_c["contacts"] if c["peerId"] == peer_b]
assert len(b_to_c_contacts) == 0, snap_b
assert len(c_to_b_contacts) == 0, snap_c

node_action_a = result_a.get("nodeAction") or {}
node_action_c = result_c.get("nodeAction") or {}
assert node_action_a.get("action") == "stop_node", result_a
assert node_action_c.get("action") == "stop_node", result_c
PY
}

assert_pass_terminal_state() {
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c = sys.argv[1:]
snap_a = json.load(open(path_a))["snapshot"]
snap_b = json.load(open(path_b))["snapshot"]
snap_c = json.load(open(path_c))["snapshot"]

def pair_rows(snapshot):
    return [
        row for row in snapshot["introductions"]
        if row["introducerId"] == peer_a
        and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
    ]

a_rows = pair_rows(snap_a)
b_rows = pair_rows(snap_b)
c_rows = pair_rows(snap_c)

assert len(a_rows) == 1, snap_a
assert len(b_rows) == 1, snap_b
assert len(c_rows) == 1, snap_c
assert a_rows[0]["id"] == b_rows[0]["id"] == c_rows[0]["id"], (a_rows, b_rows, c_rows)
assert a_rows[0]["overallStatus"] == "passed", a_rows
assert b_rows[0]["overallStatus"] == "passed", b_rows
assert c_rows[0]["overallStatus"] == "passed", c_rows

b_to_c_contacts = [c for c in snap_b["contacts"] if c["peerId"] == peer_c]
c_to_b_contacts = [c for c in snap_c["contacts"] if c["peerId"] == peer_b]
assert len(b_to_c_contacts) == 0, snap_b
assert len(c_to_b_contacts) == 0, snap_c
PY
}

assert_split_brain_mid_state() {
  python3 - "$(result_file_path "$DEVICE_A")" "$(result_file_path "$DEVICE_B")" "$(result_file_path "$DEVICE_C")" "$PEER_A" "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_a, path_b, path_c, peer_a, peer_b, peer_c = sys.argv[1:]
result_a = json.load(open(path_a))
result_b = json.load(open(path_b))
result_c = json.load(open(path_c))
snap_a = result_a["snapshot"]
snap_b = result_b["snapshot"]
snap_c = result_c["snapshot"]

def pair_rows(snapshot):
    return [
        row for row in snapshot["introductions"]
        if row["introducerId"] == peer_a
        and {row["recipientId"], row["introducedId"]} == {peer_b, peer_c}
    ]

a_rows = pair_rows(snap_a)
b_rows = pair_rows(snap_b)
c_rows = pair_rows(snap_c)

assert len(a_rows) == 1, snap_a
assert len(b_rows) == 1, snap_b
assert len(c_rows) == 1, snap_c
assert a_rows[0]["id"] == b_rows[0]["id"] == c_rows[0]["id"], (a_rows, b_rows, c_rows)
assert b_rows[0]["recipientStatus"] == "accepted", b_rows
assert b_rows[0]["introducedStatus"] == "pending", b_rows
assert b_rows[0]["overallStatus"] == "pending", b_rows
assert c_rows[0]["overallStatus"] == "mutual_accepted", c_rows

b_to_c_contacts = [c for c in snap_b["contacts"] if c["peerId"] == peer_c]
c_to_b_contacts = [c for c in snap_c["contacts"] if c["peerId"] == peer_b]
assert len(b_to_c_contacts) == 0, snap_b
assert len(c_to_b_contacts) == 1, snap_c
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

assert_offline_first_chat_messages() {
  assert_chat_message_for_contact \
    "$(result_file_path "$DEVICE_B")" \
    "$PEER_C" \
    "hello after intro"
  assert_chat_message_for_contact \
    "$(result_file_path "$DEVICE_C")" \
    "$PEER_B" \
    "hello after intro"
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

run_partial_fanout_send_phase() {
  local step_id="partial-send"
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
  "contact_settle_delay_ms": 5000,
  "introduction_settle_delay_ms": 2500,
  "poll_cycles": 25,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "contact_settle_delay_ms": 3000,
  "introduction_action": "accept_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "node_action_before_intro_phase": "stop_node",
  "introduction_action": "none",
  "poll_cycles": 30,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_partial_fanout_recovery_phase() {
  local step_id="partial-recover"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 25,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "accept_all",
  "idle_cycles_after_seen": 12,
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_partition_divergent_accept_phase() {
  local step_id="partition-divergent-accepts"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "node_action_before_intro_phase": "stop_node",
  "node_action_settle_delay_ms": 4000,
  "introduction_action": "none",
  "poll_cycles": 0,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "accept_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "contact_settle_delay_ms": 3000,
  "introduction_action": "accept_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_partition_heal_phase() {
  local step_id="partition-heal"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_pass_fallback_phase() {
  local step_id="pass-fallback-disconnected"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "node_action_before_intro_phase": "stop_node",
  "introduction_action": "none",
  "poll_cycles": 0,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "contact_settle_delay_ms": 3000,
  "introduction_action": "pass_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "node_action_before_intro_phase": "stop_node",
  "introduction_action": "none",
  "poll_cycles": 0,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_pass_fallback_recovery_phase() {
  local step_id="pass-fallback-recover"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_split_brain_second_accept_phase() {
  local step_id="split-brain-second-accept"
  clear_results_for_devices "$DEVICE_A" "$DEVICE_C"

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "contact_settle_delay_ms": 3000,
  "introduction_action": "accept_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  xcrun simctl terminate "$DEVICE_B" "$BUNDLE_ID" 2>/dev/null || true
  relaunch_devices "$DEVICE_A" "$DEVICE_C"
  wait_for_results_for_devices "$step_id" "$DEVICE_A" "$DEVICE_C"
}

run_split_brain_recovery_phase() {
  local step_id="split-brain-recover"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
}

run_first_chat_phase() {
  local step_id="offline-first-chat"
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "send_chat_messages": [
    {
      "targetPeerId": "$PEER_C",
      "text": "hello after intro"
    }
  ],
  "chat_settle_delay_ms": 1500,
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "expected_chat_messages": [
    {
      "contactPeerId": "$PEER_B",
      "text": "hello after intro",
      "isIncoming": true
    }
  ],
  "chat_poll_cycles": 35,
  "chat_poll_interval_ms": 500,
  "poll_cycles": 20,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_all
  wait_for_all_results "$step_id"
  assert_offline_first_chat_messages
}

scenario_happy_path() {
  echo ""
  echo "=== Scenario 1/10: Happy path mutual acceptance ==="
  prepare_devices
  run_handshake_phase "happy-handshake"
  run_intro_phase "happy-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_resend_refresh_pending() {
  echo ""
  echo "=== Scenario 2/10: Re-send refreshes both pending rows ==="
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
  echo "=== Scenario 3/10: Re-send revives a passed intro ==="
  prepare_devices
  run_handshake_phase "pass-handshake"
  run_intro_phase "pass-first-intro" "pass_all" "none"
  run_intro_phase "pass-resend-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_repair_missing_side() {
  echo ""
  echo "=== Scenario 4/10: Re-send repairs the missing side ==="
  prepare_devices
  run_handshake_phase "repair-handshake"
  run_intro_phase "repair-first-intro" "none" "drop_first"
  run_intro_phase "repair-resend-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_visible_copy_review() {
  echo ""
  echo "=== Scenario 5/10: Visible intro copy across all three users ==="
  prepare_devices
  run_handshake_phase "copy-handshake"
  run_copy_send_phase
  run_copy_accept_phase
  assert_pair_state "mutual_accepted" "yes"
}

scenario_partial_fanout_same_intro_recovery() {
  echo ""
  echo "=== Scenario 6/10: Partial fan-out recovers on the same intro ==="
  prepare_devices
  run_handshake_phase "partial-handshake"
  run_partial_fanout_send_phase
  assert_partial_fanout_mid_state
  PARTIAL_INTRO_ID=$(pair_intro_id_from_result "$(result_file_path "$DEVICE_B")")
  run_partial_fanout_recovery_phase
  assert_pair_state "mutual_accepted" "yes"
  assert_pair_intro_id_equals "$(result_file_path "$DEVICE_A")" "$PARTIAL_INTRO_ID"
  assert_pair_intro_id_equals "$(result_file_path "$DEVICE_B")" "$PARTIAL_INTRO_ID"
  assert_pair_intro_id_equals "$(result_file_path "$DEVICE_C")" "$PARTIAL_INTRO_ID"
}

scenario_partition_heal_divergent_accepts() {
  echo ""
  echo "=== Scenario 7/10: Partitioned accept deliveries heal back to one intro truth ==="
  prepare_devices
  run_handshake_phase "partition-handshake"
  run_intro_phase "partition-send" "none" "none"
  run_partition_divergent_accept_phase
  assert_partition_mid_state
  run_partition_heal_phase
  assert_pair_state "mutual_accepted" "yes"
}

scenario_offline_relay_first_chat() {
  echo ""
  echo "=== Scenario 8/10: Offline intro relay heals to mutual acceptance and first chat ==="
  prepare_devices
  run_handshake_phase "offline-chat-handshake"
  run_partial_fanout_send_phase
  assert_partial_fanout_mid_state
  run_partial_fanout_recovery_phase
  assert_pair_state "mutual_accepted" "yes"
  run_first_chat_phase
  assert_pair_state "mutual_accepted" "yes"
}

scenario_pass_fallback_recovery() {
  echo ""
  echo "=== Scenario 9/10: Pass notifications drain from inbox after both targets recover ==="
  prepare_devices
  run_handshake_phase "pass-fallback-handshake"
  run_intro_phase "pass-fallback-send" "none" "none"
  run_pass_fallback_phase
  assert_pass_fallback_mid_state
  run_pass_fallback_recovery_phase
  assert_pass_terminal_state
}

scenario_split_brain_mutual_acceptance_recovery() {
  echo ""
  echo "=== Scenario 10/10: Waiting vs connected split heals after reconnect ==="
  prepare_devices
  run_handshake_phase "split-brain-handshake"
  run_intro_phase "split-brain-send" "none" "none"
  run_intro_phase "split-brain-first-accept" "accept_all" "none"
  run_split_brain_second_accept_phase
  assert_split_brain_mid_state
  run_split_brain_recovery_phase
  assert_pair_state "mutual_accepted" "yes"
}

case "$INTRO_E2E_SCENARIO" in
  all)
    scenario_happy_path
    scenario_resend_refresh_pending
    scenario_resend_after_pass
    scenario_repair_missing_side
    scenario_visible_copy_review
    scenario_partial_fanout_same_intro_recovery
    scenario_partition_heal_divergent_accepts
    scenario_offline_relay_first_chat
    scenario_pass_fallback_recovery
    scenario_split_brain_mutual_acceptance_recovery
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
  partial)
    scenario_partial_fanout_same_intro_recovery
    ;;
  partition)
    scenario_partition_heal_divergent_accepts
    ;;
  offline-chat)
    scenario_offline_relay_first_chat
    ;;
  pass-fallback)
    scenario_pass_fallback_recovery
    ;;
  split-brain)
    scenario_split_brain_mutual_acceptance_recovery
    ;;
  *)
    echo "ERROR: Unknown INTRO_E2E_SCENARIO=$INTRO_E2E_SCENARIO" >&2
    exit 1
    ;;
esac

echo ""
echo "=== Intro E2E harness passed ==="
