#!/usr/bin/env bash

# Plan 378 — notification sound-disposition process contract.
#
# The sound-smoke orchestrator owns ONE machine-readable scenario -> disposition
# table (S1..S16). This contract pins that table byte-exactly, pins the offline
# OS-capture decision function that the live device path reuses, and pins that
# every scenario is actually visible to the reliability-simulation discovery
# gate. Without these three cases a card can land on the wrong notification
# channel — or a whole scenario family can go unregistered — while every gate
# stays green.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

orchestrator=integration_test/scripts/run_notification_sound_smoke.dart
runner=(dart "$orchestrator")

# The orchestrator resolves the Android application id from the environment
# first; pin it so the offline dumpsys fixtures below are package-deterministic
# on any checkout.
export ANDROID_APP_PACKAGE=com.mknoon.app

# ---------------------------------------------------------------------------
# case1_print_disposition_contract
#
# `--print-disposition-contract` must emit the pinned S1..S16 table WITHOUT a
# device pair. NOTE: never pass `-d` to this orchestrator from a contract test —
# with two live devices attached it would start a real two-device run.
# ---------------------------------------------------------------------------
case1_print_disposition_contract() {
  local actual="$tmp_dir/disposition.actual"
  local expected="$tmp_dir/disposition.expected"
  local status=0

  set +e
  "${runner[@]}" --print-disposition-contract >"$actual" 2>"$tmp_dir/disposition.err"
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf 'observed exit=%s stdout:\n' "$status" >&2
    cat "$actual" >&2
    printf 'stderr:\n' >&2
    cat "$tmp_dir/disposition.err" >&2
    fail '--print-disposition-contract did not exit 0 without a device pair'
  fi

  printf '%s\n' \
    '# notification-sound-smoke disposition contract v1' \
    '# scenario|disposition|lane|expectedChannel' \
    'S1|audibleStrict|direct|mknoon_messages' \
    'S2|audibleStrict|group|mknoon_messages' \
    'S3|audibleStrict|announcement|mknoon_messages' \
    'S4|suppressed|direct|none' \
    'S5|consistency|direct|silentFlag' \
    'S6|consistency|direct|silentFlag' \
    'S7|consistency|direct|silentFlag' \
    'S8|consistency|group|silentFlag' \
    'S9|consistency|group|silentFlag' \
    'S10|consistency|group|silentFlag' \
    'S11|consistency|announcement|silentFlag' \
    'S12|consistency|announcement|silentFlag' \
    'S13|consistency|announcement|silentFlag' \
    'S14|toneDebounce|direct|mknoon_messages_silent' \
    'S15|suppressed|group|none' \
    'S16|audibleStrict|direct|mknoon_messages' >"$expected"

  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" >&2 || true
    fail 'scenario disposition table drifted from the pinned S1..S16 contract'
  fi
}

# ---------------------------------------------------------------------------
# case2_verify_os_capture_fixtures
#
# `--verify-os-capture <scenario> <dumpsys-file> <verdict-json>` runs the SAME
# pure decision function the live device path uses, offline. Three canned dumps
# are enough to pin the contradiction that HEAD's either-channel predicate
# silently accepted.
# ---------------------------------------------------------------------------
write_dump_fixture() {
  # $1 = destination file, $2 = channel
  local destination="$1"
  local channel="$2"
  cat >"$destination" <<EOF
Current Notification List:
  NotificationRecord(0x1a2b3c: pkg=com.mknoon.app user=UserHandle{0} id=1701 tag=null importance=4 key=0|com.mknoon.app|1701|null|10123: Notification(channel=$channel shortcut=null contentView=null vibrate=null sound=null defaults=0x0 flags=0x8 color=0x00000000 category=msg vis=PRIVATE)
      groupKey=0|com.mknoon.app|g:mknoon|10123
      android.title=String (AliceNotif)
      android.text=String (S1: notification sound 1:1)

Ranking Config:
  Ranking:
EOF
}

write_empty_dump_fixture() {
  cat >"$1" <<'EOF'
Current Notification List:

Ranking Config:
  Ranking:
EOF
}

run_verify() {
  # $1 = scenario, $2 = dump file, $3 = verdict file; echoes "<status>|<line>"
  local status=0
  local out="$tmp_dir/verify.out"
  set +e
  "${runner[@]}" --verify-os-capture "$1" "$2" "$3" >"$out" 2>"$tmp_dir/verify.err"
  status=$?
  set -e
  printf '%s|%s\n' "$status" "$(grep -F 'os-capture-verdict' "$out" || true)"
}

case2_verify_os_capture_fixtures() {
  local audible_dump="$tmp_dir/dump.audible"
  local silent_dump="$tmp_dir/dump.silent"
  local empty_dump="$tmp_dir/dump.empty"
  write_dump_fixture "$audible_dump" mknoon_messages
  write_dump_fixture "$silent_dump" mknoon_messages_silent
  write_empty_dump_fixture "$empty_dump"

  local shown_false="$tmp_dir/verdict.shown_false.json"
  printf '%s\n' '{"shownCalls":[{"silent":false}]}' >"$shown_false"
  local shown_none="$tmp_dir/verdict.shown_none.json"
  printf '%s\n' '{"shownCalls":[]}' >"$shown_none"

  # 2a: audible-expected scenario + audible record -> pass.
  local result
  result="$(run_verify S1 "$audible_dump" "$shown_false")"
  [ "${result%%|*}" = 0 ] ||
    fail "audible fixture did not pass the OS-capture decision (got: $result)"
  case "$result" in
    *"result=pass"*"reason=ok"*) ;;
    *) fail "audible fixture emitted no passing verdict line (got: $result)" ;;
  esac

  # 2b: audible-expected scenario + SILENT-channel record -> typed failure.
  # This is the contradiction HEAD's either-channel predicate accepted.
  result="$(run_verify S1 "$silent_dump" "$shown_false")"
  [ "${result%%|*}" != 0 ] ||
    fail 'audible-expected scenario accepted a silent-channel record'
  case "$result" in
    *"result=fail"*"reason=channel_contradiction"*) ;;
    *) fail "channel contradiction was not typed (got: $result)" ;;
  esac

  # 2c: suppressed-expected scenario + any record -> typed failure.
  result="$(run_verify S4 "$audible_dump" "$shown_none")"
  [ "${result%%|*}" != 0 ] ||
    fail 'suppressed-expected scenario accepted an OS notification record'
  case "$result" in
    *"result=fail"*"reason=unexpected_notification"*) ;;
    *) fail "suppressed violation was not typed (got: $result)" ;;
  esac

  # Sanity: the suppressed scenario still passes on an empty shade, so 2c is a
  # contradiction assertion and not an always-fail.
  result="$(run_verify S4 "$empty_dump" "$shown_none")"
  [ "${result%%|*}" = 0 ] ||
    fail "suppressed scenario failed on an empty shade (got: $result)"
}

# ---------------------------------------------------------------------------
# case3_discovery_rows
#
# Every S1..S16 row must be visible to the reliability-simulation discovery
# gate under the correct family. HEAD registers only S1..S4 (the S5..S13
# map-loop emission is unparseable by the discovery awk) and still exits 0 —
# invisible-but-green.
# ---------------------------------------------------------------------------
case3_discovery_rows() {
  local tsv="$tmp_dir/discovery.tsv"
  ./scripts/check_reliability_simulation_discovery.sh --checks-tsv >"$tsv"

  local actual="$tmp_dir/discovery.actual"
  local expected="$tmp_dir/discovery.expected"
  awk -F'\t' \
    '$2 == "integration_test/scripts/run_notification_sound_smoke.dart" {
       print $1 "\t" $3
     }' "$tsv" |
    LC_ALL=C sort >"$actual"

  printf '%s\t%s\n' \
    1to1 S1 \
    1to1 S14 \
    1to1 S16 \
    1to1 S4 \
    1to1 S5 \
    1to1 S6 \
    1to1 S7 \
    group S10 \
    group S11 \
    group S12 \
    group S13 \
    group S15 \
    group S2 \
    group S3 \
    group S8 \
    group S9 >"$expected"

  if ! cmp -s "$expected" "$actual"; then
    printf 'observed %s sound-smoke discovery rows:\n' "$(wc -l <"$actual" | tr -d ' ')" >&2
    diff -u "$expected" "$actual" >&2 || true
    fail 'sound-smoke scenarios are not all registered under the correct discovery families'
  fi
}

case1_print_disposition_contract
case2_verify_os_capture_fixtures
case3_discovery_rows

printf 'PASS: notification sound disposition contract\n'
