#!/bin/bash
set -euo pipefail

DEVICE_A="347FB118-10D0-40C8-A05B-B0C3BD6B8CCD"
DEVICE_B="5BA69F1C-B112-47BE-B1FF-8C1003728C8F"
DEVICE_C="1B098DFF-6294-407A-A209-BBF360893485"
DEVICE_D="38FECA55-03C1-4907-BD9D-8E64BF8E3469"
BUNDLE_ID="com.mknoon.app"
EXPORT_FILE="intro_e2e_identity.json"
CONFIG_FILE="intro_e2e_config.json"
RESULT_FILE="intro_e2e_result.json"
INTRO_E2E_SCENARIO="${INTRO_E2E_SCENARIO:-all}"
ARTIFACT_ROOT="build/intro_e2e"
DOCS_A=""
DOCS_B=""
DOCS_C=""
DOCS_D=""

get_docs_dir() {
  case "$1" in
    "$DEVICE_A")
      if [ -n "$DOCS_A" ] && [ -d "$DOCS_A" ]; then
        echo "$DOCS_A"
        return
      fi
      ;;
    "$DEVICE_B")
      if [ -n "$DOCS_B" ] && [ -d "$DOCS_B" ]; then
        echo "$DOCS_B"
        return
      fi
      ;;
    "$DEVICE_C")
      if [ -n "$DOCS_C" ] && [ -d "$DOCS_C" ]; then
        echo "$DOCS_C"
        return
      fi
      ;;
    "$DEVICE_D")
      if [ -n "$DOCS_D" ] && [ -d "$DOCS_D" ]; then
        echo "$DOCS_D"
        return
      fi
      ;;
  esac

  local container
  container=$(xcrun simctl get_app_container "$1" "$BUNDLE_ID" data 2>/dev/null)
  if [ -z "$container" ]; then
    echo ""
    return
  fi
  echo "$container/Documents"
}

cache_docs_dirs() {
  DOCS_A=$(get_docs_dir "$DEVICE_A")
  DOCS_B=$(get_docs_dir "$DEVICE_B")
  DOCS_C=$(get_docs_dir "$DEVICE_C")
}

cache_four_docs_dirs() {
  cache_docs_dirs
  DOCS_D=$(get_docs_dir "$DEVICE_D")
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
  # Config files are polled by the running debug app. Stop the target app before
  # staging a new phase config so the previous phase cannot consume it early.
  xcrun simctl terminate "$device" "$BUNDLE_ID" 2>/dev/null || true
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

clear_four_results() {
  clear_results_for_devices "$DEVICE_A" "$DEVICE_B" "$DEVICE_C" "$DEVICE_D"
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

relaunch_four_devices() {
  relaunch_devices "$DEVICE_A" "$DEVICE_B" "$DEVICE_C" "$DEVICE_D"
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

wait_for_four_results() {
  local step_id="$1"
  wait_for_results_for_devices "$step_id" "$DEVICE_A" "$DEVICE_B" "$DEVICE_C" "$DEVICE_D"
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

assert_folded_duplicate_handshake() {
  python3 - \
    "$(result_file_path "$DEVICE_A")" \
    "$(result_file_path "$DEVICE_B")" \
    "$(result_file_path "$DEVICE_C")" \
    "$(result_file_path "$DEVICE_D")" \
    "$PEER_A" "$PEER_B" "$PEER_C" "$PEER_D" <<'PY'
import json, sys
path_a, path_b, path_c, path_d, peer_a, peer_b, peer_c, peer_d = sys.argv[1:]
snap_a = json.load(open(path_a))["snapshot"]
snap_b = json.load(open(path_b))["snapshot"]
snap_c = json.load(open(path_c))["snapshot"]
snap_d = json.load(open(path_d))["snapshot"]

def contact_peer_ids(snapshot):
    return {contact["peerId"] for contact in snapshot["contacts"]}

contacts_a = contact_peer_ids(snap_a)
contacts_b = contact_peer_ids(snap_b)
contacts_c = contact_peer_ids(snap_c)
contacts_d = contact_peer_ids(snap_d)

assert {peer_b, peer_c}.issubset(contacts_a), snap_a
assert {peer_b, peer_c}.issubset(contacts_d), snap_d
assert {peer_a, peer_d}.issubset(contacts_b), snap_b
assert {peer_a, peer_d}.issubset(contacts_c), snap_c
assert peer_c not in contacts_b, snap_b
assert peer_b not in contacts_c, snap_c
for snapshot in (snap_a, snap_b, snap_c, snap_d):
    assert not snapshot["pendingContactRequests"], snapshot
PY
}

folded_duplicate_intro_ids_from_result() {
  local result_path="$1"
  python3 - "$result_path" "$PEER_A" "$PEER_B" "$PEER_C" "$PEER_D" <<'PY'
import json, sys
result_path, peer_a, peer_b, peer_c, peer_d = sys.argv[1:]
snapshot = json.load(open(result_path))["snapshot"]
rows = [
    row for row in snapshot["introductions"]
    if row["introducerId"] in {peer_a, peer_d}
    and row["recipientId"] == peer_b
    and row["introducedId"] == peer_c
]
assert len(rows) == 2, snapshot
ids = {row["id"] for row in rows}
assert len(ids) == 2, rows
print(" ".join(sorted(ids)))
PY
}

assert_folded_duplicate_pending_state() {
  python3 - \
    "$(result_file_path "$DEVICE_B")" \
    "$(result_file_path "$DEVICE_C")" \
    "$PEER_A" "$PEER_B" "$PEER_C" "$PEER_D" <<'PY'
import json, sys
path_b, path_c, peer_a, peer_b, peer_c, peer_d = sys.argv[1:]
snap_b = json.load(open(path_b))["snapshot"]
snap_c = json.load(open(path_c))["snapshot"]

def duplicate_rows(snapshot):
    return [
        row for row in snapshot["introductions"]
        if row["introducerId"] in {peer_a, peer_d}
        and row["recipientId"] == peer_b
        and row["introducedId"] == peer_c
    ]

b_rows = duplicate_rows(snap_b)
c_rows = duplicate_rows(snap_c)
assert len(b_rows) == 2, snap_b
assert len(c_rows) == 2, snap_c

intro_ids = {row["id"] for row in b_rows}
assert len(intro_ids) == 2, b_rows
assert {row["id"] for row in c_rows} == intro_ids, (b_rows, c_rows)
assert {row["introducerId"] for row in b_rows} == {peer_a, peer_d}, b_rows
for row in [*b_rows, *c_rows]:
    assert row["recipientStatus"] == "pending", row
    assert row["introducedStatus"] == "pending", row
    assert row["overallStatus"] == "pending", row

def single_folded_item(snapshot, target_peer_id):
    rows = [
        item for item in snapshot.get("foldedReviewItems", [])
        if item["targetPeerId"] == target_peer_id
    ]
    assert len(rows) == 1, snapshot
    return rows[0]

b_folded = single_folded_item(snap_b, peer_c)
c_folded = single_folded_item(snap_c, peer_b)
for item in (b_folded, c_folded):
    assert set(item["introductionIds"]) == intro_ids, item
    assert set(item["pendingCurrentViewerDecisionIntroIds"]) == intro_ids, item
    assert item["acceptedCurrentViewerDecisionIntroIds"] == [], item
    assert item["passedCurrentViewerDecisionIntroIds"] == [], item
    assert item["displaySourceIntroductionId"] in intro_ids, item
    assert {
        attribution["introducerId"]
        for attribution in item["introducerAttributions"]
    } == {peer_a, peer_d}, item
PY
}

assert_folded_duplicate_accept_action() {
  local expected_intro_ids="$1"
  python3 - "$(result_file_path "$DEVICE_B")" "$expected_intro_ids" "$PEER_C" <<'PY'
import json, sys
path_b, expected_intro_ids, peer_c = sys.argv[1:]
expected = set(expected_intro_ids.split())
result_b = json.load(open(path_b))
intro_action = result_b.get("introAction") or {}
assert intro_action.get("action") == "accept_folded_all", result_b
assert set(intro_action.get("actedOn", [])) == expected, intro_action
folded_targets = intro_action.get("foldedTargets", [])
assert len(folded_targets) == 1, intro_action
target = folded_targets[0]
assert target["targetPeerId"] == peer_c, target
assert set(target["introductionIds"]) == expected, target
assert set(target["appliedIntroIds"]) == expected, target
assert target["skippedNotPendingIntroIds"] == [], target
assert target["failedIntroIds"] == [], target
results = target["results"]
assert len(results) == 2, target
for row in results:
    assert row["introductionId"] in expected, row
    assert row["outcome"] == "applied", row
    assert row["recipientStatus"] == "accepted", row
    assert row["introducedStatus"] in {"pending", "accepted"}, row
    assert row["overallStatus"] in {"pending", "mutual_accepted"}, row
PY
}

assert_folded_duplicate_terminal_state() {
  local expected_intro_ids="$1"
  python3 - \
    "$(result_file_path "$DEVICE_B")" \
    "$(result_file_path "$DEVICE_C")" \
    "$expected_intro_ids" \
    "$PEER_B" "$PEER_C" <<'PY'
import json, sys
path_b, path_c, expected_intro_ids, peer_b, peer_c = sys.argv[1:]
expected = set(expected_intro_ids.split())
snap_b = json.load(open(path_b))["snapshot"]
snap_c = json.load(open(path_c))["snapshot"]

def expected_rows(snapshot):
    rows = [row for row in snapshot["introductions"] if row["id"] in expected]
    assert len(rows) == len(expected), snapshot
    assert {row["id"] for row in rows} == expected, rows
    return rows

for row in [*expected_rows(snap_b), *expected_rows(snap_c)]:
    assert row["recipientStatus"] == "accepted", row
    assert row["introducedStatus"] == "accepted", row
    assert row["overallStatus"] == "mutual_accepted", row

b_to_c_contacts = [contact for contact in snap_b["contacts"] if contact["peerId"] == peer_c]
c_to_b_contacts = [contact for contact in snap_c["contacts"] if contact["peerId"] == peer_b]
assert len(b_to_c_contacts) == 1, snap_b
assert len(c_to_b_contacts) == 1, snap_c
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
  DOCS_A=""
  DOCS_B=""
  DOCS_C=""
  DOCS_D=""
  ./reset_simulators.sh
  cache_docs_dirs

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

prepare_four_devices() {
  echo ""
  echo "=== Preparing four intro E2E simulators ==="
  DOCS_A=""
  DOCS_B=""
  DOCS_C=""
  DOCS_D=""
  INTRO_E2E_DEVICE_SET=four ./reset_simulators.sh
  cache_four_docs_dirs

  EXPORT_A=$(read_export "$DEVICE_A")
  EXPORT_B=$(read_export "$DEVICE_B")
  EXPORT_C=$(read_export "$DEVICE_C")
  EXPORT_D=$(read_export "$DEVICE_D")

  PEER_A=$(peer_id_from_export "$EXPORT_A")
  PEER_B=$(peer_id_from_export "$EXPORT_B")
  PEER_C=$(peer_id_from_export "$EXPORT_C")
  PEER_D=$(peer_id_from_export "$EXPORT_D")
  USER_A=$(username_from_export "$EXPORT_A")
  USER_B=$(username_from_export "$EXPORT_B")
  USER_C=$(username_from_export "$EXPORT_C")
  USER_D=$(username_from_export "$EXPORT_D")

  CONTACT_A_JSON=$(contact_entry_json "$EXPORT_A")
  CONTACT_B_JSON=$(contact_entry_json "$EXPORT_B")
  CONTACT_C_JSON=$(contact_entry_json "$EXPORT_C")
  CONTACT_D_JSON=$(contact_entry_json "$EXPORT_D")

  echo "  [a] $USER_A $PEER_A"
  echo "  [b] $USER_B $PEER_B"
  echo "  [c] $USER_C $PEER_C"
  echo "  [d] $USER_D $PEER_D"
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

run_folded_duplicate_handshake_phase() {
  local step_id="$1"
  clear_four_results

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
    $CONTACT_A_JSON,
    $CONTACT_D_JSON
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
    $CONTACT_A_JSON,
    $CONTACT_D_JSON
  ],
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 25,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_D" "$(cat <<EOF
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

  relaunch_four_devices
  wait_for_four_results "$step_id"
  assert_folded_duplicate_handshake
}

run_folded_duplicate_send_phase() {
  local step_id="folded-duplicate-send"
  clear_four_results

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
  "contact_settle_delay_ms": 10000,
  "introduction_action": "none",
  "introduction_settle_delay_ms": 3000,
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
  "poll_cycles": 90,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 90,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_D" "$(cat <<EOF
{
  "stepId": "$step_id",
  "send_introductions": [
    {
      "recipientPeerId": "$PEER_B",
      "friendPeerIds": ["$PEER_C"]
    }
  ],
  "contact_request_action": "none",
  "contact_settle_delay_ms": 10000,
  "introduction_action": "none",
  "introduction_settle_delay_ms": 3000,
  "poll_cycles": 25,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_four_devices
  wait_for_four_results "$step_id"
  assert_folded_duplicate_pending_state
}

run_folded_duplicate_accept_phase() {
  local step_id="folded-duplicate-accept"
  clear_four_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 45,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "accept_folded_all",
  "idle_cycles_after_seen": 12,
  "poll_cycles": 90,
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
  "idle_cycles_after_seen": 12,
  "poll_cycles": 90,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_D" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "none",
  "introduction_action": "none",
  "poll_cycles": 45,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_four_devices
  wait_for_four_results "$step_id"
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
  "contact_settle_delay_ms": 10000,
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
  "poll_cycles": 70,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$step_id",
  "contact_request_action": "$c_contact_action",
  "introduction_action": "$c_intro_action",
  "poll_cycles": 70,
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
  "contact_settle_delay_ms": 10000,
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
  local stop_step_id="pass-fallback-stop-targets"
  local pass_step_id="pass-fallback-disconnected"
  xcrun simctl terminate "$DEVICE_B" "$BUNDLE_ID" 2>/dev/null || true
  clear_results

  write_config "$DEVICE_A" "$(cat <<EOF
{
  "stepId": "$stop_step_id",
  "contact_request_action": "none",
  "node_action_before_intro_phase": "stop_node",
  "introduction_action": "none",
  "poll_cycles": 0,
  "poll_interval_ms": 500
}
EOF
)"

  write_config "$DEVICE_C" "$(cat <<EOF
{
  "stepId": "$stop_step_id",
  "contact_request_action": "none",
  "node_action_before_intro_phase": "stop_node",
  "introduction_action": "none",
  "poll_cycles": 0,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_devices "$DEVICE_A" "$DEVICE_C"
  wait_for_results_for_devices "$stop_step_id" "$DEVICE_A" "$DEVICE_C"
  xcrun simctl terminate "$DEVICE_A" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$DEVICE_C" "$BUNDLE_ID" 2>/dev/null || true

  clear_results_for_devices "$DEVICE_B"
  write_config "$DEVICE_B" "$(cat <<EOF
{
  "stepId": "$pass_step_id",
  "contact_request_action": "none",
  "contact_settle_delay_ms": 3000,
  "introduction_action": "pass_all",
  "poll_cycles": 35,
  "poll_interval_ms": 500
}
EOF
)"

  relaunch_devices "$DEVICE_B"
  wait_for_results_for_devices "$pass_step_id" "$DEVICE_B"
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
  "contact_settle_delay_ms": 10000,
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
  "chat_poll_cycles": 120,
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
  echo "=== Scenario 1/11: Happy path mutual acceptance ==="
  prepare_devices
  run_handshake_phase "happy-handshake"
  run_intro_phase "happy-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_resend_refresh_pending() {
  echo ""
  echo "=== Scenario 2/11: Re-send refreshes both pending rows ==="
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
  echo "=== Scenario 3/11: Re-send revives a passed intro ==="
  prepare_devices
  run_handshake_phase "pass-handshake"
  run_intro_phase "pass-first-intro" "pass_all" "none"
  run_intro_phase "pass-resend-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_repair_missing_side() {
  echo ""
  echo "=== Scenario 4/11: Re-send repairs the missing side ==="
  prepare_devices
  run_handshake_phase "repair-handshake"
  run_intro_phase "repair-first-intro" "none" "drop_first"
  run_intro_phase "repair-resend-intro" "accept_all" "accept_all"
  assert_pair_state "mutual_accepted" "yes"
}

scenario_visible_copy_review() {
  echo ""
  echo "=== Scenario 5/11: Visible intro copy across all three users ==="
  prepare_devices
  run_handshake_phase "copy-handshake"
  run_copy_send_phase
  run_copy_accept_phase
  assert_pair_state "mutual_accepted" "yes"
}

scenario_partial_fanout_same_intro_recovery() {
  echo ""
  echo "=== Scenario 6/11: Partial fan-out recovers on the same intro ==="
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
  echo "=== Scenario 7/11: Partitioned accept deliveries heal back to one intro truth ==="
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
  echo "=== Scenario 8/11: Offline intro relay heals to mutual acceptance and first chat ==="
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
  echo "=== Scenario 9/11: Pass notifications drain from inbox after both targets recover ==="
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
  echo "=== Scenario 10/11: Waiting vs connected split heals after reconnect ==="
  prepare_devices
  run_handshake_phase "split-brain-handshake"
  run_intro_phase "split-brain-send" "none" "none"
  run_intro_phase "split-brain-first-accept" "accept_all" "none"
  run_split_brain_second_accept_phase
  assert_split_brain_mid_state
  run_split_brain_recovery_phase
  assert_pair_state "mutual_accepted" "yes"
}

scenario_folded_duplicate() {
  echo ""
  echo "=== Scenario 11/11: Four-identity folded duplicate acceptance ==="
  prepare_four_devices
  run_folded_duplicate_handshake_phase "folded-duplicate-handshake"
  run_folded_duplicate_send_phase
  FOLDED_DUPLICATE_INTRO_IDS=$(folded_duplicate_intro_ids_from_result "$(result_file_path "$DEVICE_B")")
  run_folded_duplicate_accept_phase
  assert_folded_duplicate_accept_action "$FOLDED_DUPLICATE_INTRO_IDS"
  assert_folded_duplicate_terminal_state "$FOLDED_DUPLICATE_INTRO_IDS"
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
    scenario_folded_duplicate
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
  folded-duplicate)
    scenario_folded_duplicate
    ;;
  *)
    echo "ERROR: Unknown INTRO_E2E_SCENARIO=$INTRO_E2E_SCENARIO" >&2
    exit 1
    ;;
esac

echo ""
echo "=== Intro E2E harness passed ==="
