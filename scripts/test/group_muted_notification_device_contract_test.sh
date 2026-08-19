#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

runner="integration_test/scripts/run_group_muted_notification_android.dart"

[ -f "$runner" ] || {
  printf 'FAIL: Plan 379 muted-group runner is missing\n' >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ---------------------------------------------------------------------------
# Case 1 - the muted validator accepts the happy artifact and rejects an
# artifact whose unread count did not grow across the suppressed send.
#
# Both fixtures come from the SAME shared builder the device capture stages
# call (`--emit-fixture`), so this contract cannot drift from what the capture
# actually writes, and the negative is the happy artifact with one observation
# changed rather than a hand-written blob.
# ---------------------------------------------------------------------------
mkdir -p "$tmp_dir/happy" "$tmp_dir/unread"

happy_artifact="$(
  dart run "$runner" --emit-fixture happy-message --output "$tmp_dir/happy" |
    awk '/^\// { print }'
)"
[ -f "$happy_artifact" ] || {
  printf 'FAIL: --emit-fixture happy-message did not write an artifact\n' >&2
  exit 1
}

unread_artifact="$(
  dart run "$runner" --emit-fixture unread-unchanged --output "$tmp_dir/unread" |
    awk '/^\// { print }'
)"
[ -f "$unread_artifact" ] || {
  printf 'FAIL: --emit-fixture unread-unchanged did not write an artifact\n' >&2
  exit 1
}

set +e
dart run "$runner" --validate-artifact "$happy_artifact" \
  >"$tmp_dir/happy.stdout" 2>"$tmp_dir/happy.stderr"
happy_status=$?
set -e
[ "$happy_status" -eq 0 ] || {
  printf 'FAIL: the muted validator rejected its own happy artifact\n' >&2
  cat "$tmp_dir/happy.stderr" >&2
  exit 1
}

set +e
dart run "$runner" --validate-artifact "$unread_artifact" \
  >"$tmp_dir/unread.stdout" 2>"$tmp_dir/unread.stderr"
unread_status=$?
set -e
[ "$unread_status" -ne 0 ] || {
  printf 'FAIL: an artifact with unchanged unread was accepted\n' >&2
  exit 1
}
grep -q 'unread must grow past the pre-send baseline' "$tmp_dir/unread.stderr" || {
  printf 'FAIL: unread rejection was not attributed to the unread rule\n' >&2
  cat "$tmp_dir/unread.stderr" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Case 1b - Plan 384's killed-app card scenario rides the SAME entry point.
#
# `--validate-artifact` dispatches on the artifact's own `scenario`, so this
# also pins that a third scenario is not silently handed to the muted
# validator, whose admission rejects it. The negative is the happy artifact
# with the graded dump replaced by the WARM-UP's card: Android replaces a
# conversation card in place, so a bare "a card exists" check would pass it.
# ---------------------------------------------------------------------------
mkdir -p "$tmp_dir/killed_happy" "$tmp_dir/killed_stale"

killed_happy_artifact="$(
  dart run "$runner" --emit-fixture happy-killed-text-card \
    --output "$tmp_dir/killed_happy" |
    awk '/^\// { print }'
)"
[ -f "$killed_happy_artifact" ] || {
  printf 'FAIL: --emit-fixture happy-killed-text-card wrote no artifact\n' >&2
  exit 1
}

killed_stale_artifact="$(
  dart run "$runner" --emit-fixture killed-text-card-stale-card \
    --output "$tmp_dir/killed_stale" |
    awk '/^\// { print }'
)"
[ -f "$killed_stale_artifact" ] || {
  printf 'FAIL: --emit-fixture killed-text-card-stale-card wrote no artifact\n' >&2
  exit 1
}

set +e
dart run "$runner" --validate-artifact "$killed_happy_artifact" \
  >"$tmp_dir/killed_happy.stdout" 2>"$tmp_dir/killed_happy.stderr"
killed_happy_status=$?
set -e
[ "$killed_happy_status" -eq 0 ] || {
  printf 'FAIL: the killed-card validator rejected its own happy artifact\n' >&2
  cat "$tmp_dir/killed_happy.stderr" >&2
  exit 1
}

set +e
dart run "$runner" --validate-artifact "$killed_stale_artifact" \
  >"$tmp_dir/killed_stale.stdout" 2>"$tmp_dir/killed_stale.stderr"
killed_stale_status=$?
set -e
[ "$killed_stale_status" -ne 0 ] || {
  printf 'FAIL: a killed-card artifact showing only the warm-up card was accepted\n' >&2
  exit 1
}
grep -q 'carrying the graded marker' "$tmp_dir/killed_stale.stderr" || {
  printf 'FAIL: stale-card rejection was not attributed to the graded-marker rule\n' >&2
  cat "$tmp_dir/killed_stale.stderr" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Case 2 - adapter stdout purity in the blocked lane.
#
# `tool/sims/executor.dart` scans every stdout line for the SIMS_RESULT_JSON
# marker and fails the harness when it appears more than once. The runner pipes
# the capture child's streams to stderr for exactly this reason.
# ---------------------------------------------------------------------------
set +e
env -u SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM dart run "$runner" \
  >"$tmp_dir/blocked.stdout" 2>"$tmp_dir/blocked.stderr"
blocked_status=$?
set -e

[ "$blocked_status" -eq 78 ] || {
  printf 'FAIL: unconfigured muted adapter exited %s, expected 78\n' \
    "$blocked_status" >&2
  exit 1
}
marker_lines="$(grep -c 'SIMS_RESULT_JSON' "$tmp_dir/blocked.stdout" || true)"
[ "$marker_lines" = "1" ] || {
  printf 'FAIL: blocked lane emitted %s SIMS_RESULT_JSON lines, expected 1\n' \
    "$marker_lines" >&2
  exit 1
}
grep -q '"status":"BLOCKED"' "$tmp_dir/blocked.stdout" || {
  printf 'FAIL: unconfigured muted adapter did not report BLOCKED\n' >&2
  exit 1
}
grep -q '"blocker":"missingArtifact"' "$tmp_dir/blocked.stdout" || {
  printf 'FAIL: blocked lane did not classify the missing prepared APK\n' >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Case 3 - ordered census of the scenarios this lane owns.
#
# Every id is OUT of `groupReactionNotificationScenarios`, so the Plan-257
# six-row censuses stay byte-identical; this is this lane's own pin. Plan 384's
# id is LAST so the shipped muted pair's declaration order never moves.
# ---------------------------------------------------------------------------
expected="$({
  printf '%s\n' android_group_muted_message_suppression
  printf '%s\n' android_group_muted_reaction_background_suppression
  printf '%s\n' android_group_text_killed_app_card
})"

actual="$(
  dart run "$runner" --list-scenarios |
    awk '/^[[:alnum:]_]+$/ { print }'
)"
[ "$actual" = "$expected" ] || {
  printf 'FAIL: muted scenario listing differs from the pinned census\n' >&2
  printf 'actual:\n%s\n' "$actual" >&2
  exit 1
}

# No id may carry the message-lifecycle suffix: that suffix is what routes a
# scenario into the reaction grammar, whose assertions contradict both mute and
# the killed-app card.
if printf '%s\n' "$actual" | grep -q '_message_unread_lifecycle$'; then
  printf 'FAIL: a muted id carries the reaction-grammar lifecycle suffix\n' >&2
  exit 1
fi

# No id may be a prefix of another: the Plan-257 runner selects proof rows with
# an anchored `--name`, and a prefix pair is what made `--plain-name` run two
# blocks against one artifact.
while read -r outer; do
  while read -r inner; do
    [ "$outer" = "$inner" ] && continue
    case "$inner" in
      "$outer"*)
        printf 'FAIL: scenario id %s is a prefix of %s\n' "$outer" "$inner" >&2
        exit 1
        ;;
    esac
  done <<EOF
$actual
EOF
done <<EOF
$actual
EOF

printf 'PASS: the Android muted-group lane is discoverable, fail-closed, and '
printf 'raw-evidence bound across all 3 scenarios\n'
