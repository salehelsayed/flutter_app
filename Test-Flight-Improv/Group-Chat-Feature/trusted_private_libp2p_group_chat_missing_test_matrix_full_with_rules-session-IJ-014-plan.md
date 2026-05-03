# IJ-014 Session Plan - Welcome/key repair state

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T05:17:00+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; session breakdown; `accept_pending_group_invite_use_case.dart`; `handle_incoming_group_invite_use_case.dart`; `group_invite_payload.dart`; `group_list_wired.dart`; invite/list tests | Existing coverage keeps missing/empty join material pending for repair before join, and the UI shows the repair warning. Remaining row-owned gap is post-parse join-material failure: `materializeAcceptedGroupInvitePayload` persists group/member/key state before `group:join`, then generic bridge failure clears pending invites. | Add a narrow key-material repair classification and rollback path, plus focused retry/mailbox/UI proof. |
| 2026-05-01T05:18:00+02:00 | Planner completed | same | Treat explicit welcome/key-package/key-material bridge errors as repairable, roll back partially materialized group/member/key state, and keep the pending invite row retryable. Keep generic transport/topic failures as existing `bridgeError` behavior. | Patch owner files and tests. |
| 2026-05-01T05:19:00+02:00 | Reviewer completed | same plus device checks | Plan can close IJ-014 for shipped inline group-key invites if closure states that first-class MLS/key-package transport and live 3-party proof remain outside current host evidence while relay/device env is unset. | Execute focused implementation. |
| 2026-05-01T05:20:00+02:00 | Arbiter completed | same | execution-ready. Current row is implementation-owned because the app can distinguish repairable key-material failures and preserve pending state without new protocol surface. | Run Executor. |

## Execution Progress

| timestamp | phase | files inspected or touched | command / evidence | decision | next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-01T05:20:30+02:00 | Contract extracted | `handle_incoming_group_invite_use_case.dart`; `accept_pending_group_invite_use_case.dart`; focused tests | Scope is key-material repair classification and rollback; generic join failures must preserve existing `bridgeError` behavior. | Safe to patch current-session owner files and tests. | Implement classifier, rollback, and focused IJ-014 tests. |
| 2026-05-01T05:21:30+02:00 | Executor completed focused patch | `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`; `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`; `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`; `test/features/groups/presentation/group_list_wired_test.dart` | Added repairable join-material error rollback and focused accept/direct/UI tests; `dart format` ran on touched Dart files. | Patch is current-session scoped. | Run focused IJ-014 tests. |
| 2026-05-01T05:22:30+02:00 | Focused IJ-014 tests passed | same | `accept_pending_group_invite_use_case_test.dart --plain-name 'IJ014'` passed (`+2`); `handle_incoming_group_invite_use_case_test.dart --plain-name 'IJ014'` passed (`+1`); `group_list_wired_test.dart --plain-name 'IJ014'` passed (`+1`). | Row-owned repair behavior is green. | Run adjacent UI preservation and broader invite gates. |
| 2026-05-01T05:23:00+02:00 | Adjacent UI preservation passed | `group_list_wired_test.dart` | `--plain-name 'accepting a pending invite joins the group and removes the row'` passed (`+1`); `--plain-name 'bridgeError accept keeps the joined group and shows recovery warning'` passed (`+1`). | Valid accept and generic bridgeError behavior remain green. | Run invite wildcard and integration gates. |
| 2026-05-01T05:23:30+02:00 | Invite and round-trip gates passed | invite application tests; invite integration tests | `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+104`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+14`). | Row-adjacent invite suites remain green after the repair-path patch. | Run onboarding and canonical groups gate. |
| 2026-05-01T05:24:00+02:00 | Integration and groups gates passed | onboarding integration; groups gate | `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+97`). | Authorized onboarding and canonical group messaging gate remain green. | Run full touched presentation file and diff hygiene. |
| 2026-05-01T05:24:30+02:00 | UI file and diff hygiene passed | `test/features/groups/presentation/group_list_wired_test.dart`; full diff | `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart` passed (`+17`); `git diff --check` passed. | The touched UI helper and repair-state row are green. | Close IJ-014 docs. |

## execution and closure evidence

Final execution verdict: `accepted`.

IJ-014 is covered for the shipped inline group-key invite contract. `handle_incoming_group_invite_use_case.dart` now treats explicit stale, invalid, or undecryptable join-material bridge failures as repairable, rolls back the partially saved group, member, and group-key state, and returns a repairable invalid-payload outcome instead of clearing the pending invite into an unusable group. The generic `bridgeError` branch remains intact for non-key-material join failures.

Focused accept-pending tests prove a repairable join-material failure keeps the pending row, creates no consumed tombstone, group, member, key, message, publish, mailbox drain, or `group:join` success side effect, and can retry successfully after fresh key material. The direct handler test proves the same rollback for direct materialization. The wired list test proves the pending invite remains visible and the shipped key-material warning is shown.

Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. IJ-014 does not claim a first-class MLS welcome/key-package transport, separate device identity registry, sibling-device approval flow, live three-party device proof, or real relay/device proof.

## real scope

Close IJ-014 for the shipped trusted-private invite contract by ensuring missing, stale, or undecryptable welcome/key material leaves the invite in an explicit repair-pending state instead of creating an unusable local group or silently consuming the pending invite.

## closure bar

IJ-014 closure required source matrix, inventory, and breakdown evidence that:

- invalid or missing inline group key material does not create group/member/key state or `group:join`
- explicit key-material/welcome/key-package bridge failures during accept roll back partial group/member/key state
- pending invites remain retryable after repairable key-material failures, and a later retry with fresh/valid material can succeed
- mailbox/offline inbox drain does not run before repaired admission succeeds
- the UI keeps the pending invite visible and shows the existing fresh-key-material warning

## source of truth

- Primary row: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` IJ-014.
- Current coverage note: `test-inventory.md` IJ-014.
- Session scope: ordered session row 13 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Production owner files: `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` and `lib/features/groups/application/accept_pending_group_invite_use_case.dart`.
- UI preservation file: `lib/features/groups/presentation/screens/group_list_wired.dart`.

## session classification

`needs_code_and_tests`.

The breakdown labels IJ-014 `evidence-gated`, but repo inspection found a current implementation-owned gap in repairable join-material failure handling.

## Device/Relay Proof Profile

Profile: `host-only` for required closure, with supporting `three-party/device-lab` and `group-real-network-nightly` evidence unavailable in this run.

Live availability checks for this run:

- `flutter devices --machine`: `emulator-5554`, physical iPhone `00008030-001A6D2801BB802E`, booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, plus macOS and Chrome.
- `xcrun simctl list devices available`: booted iOS simulators include `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`.
- `adb devices`: unavailable in this shell (`adb: command not found`).
- `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES`: unset.

Required closure evidence is host fake-repository/app-layer proof because the row-owned gap is app repair-state handling. Live 3-party and real relay/device proof remain supporting only while required env is unset.

## exact problem statement

`acceptPendingGroupInvite` already returns `repairPending` for malformed/missing join material before materialization. Once `materializeAcceptedGroupInvitePayload` starts, it saves group, members, and key before calling `group:join`. Generic bridge errors intentionally leave the durable group state for recovery, but explicit key-material/welcome/key-package failures should not consume the pending invite or leave a partially joined group.

## files and repos to inspect next

- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`

## step-by-step implementation plan

1. Add a small repairable join-material failure classifier for `BridgeCommandException` from `callGroupJoinWithConfig`.
2. In `materializeAcceptedGroupInvitePayload`, when that classifier matches, remove saved group members, keys, and group state, emit a repair event, and return `HandleGroupInviteResult.invalidPayload`.
3. Preserve existing generic `bridgeError` behavior for `JOIN_FAILED`, topic, timeout, and catch-all transport errors.
4. Add focused accept-pending tests for key-material bridge failure rollback, pending-row preservation, no mailbox drain, and successful retry after repair.
5. Add a direct handle test proving the same key-material bridge failure rolls back state.
6. Add or extend a wired list test proving the UI keeps the invite row and shows the existing fresh-key-material warning after a join-material bridge failure.
7. Run focused IJ-014 tests, invite wildcard, invite round trip, onboarding, groups gate, and `git diff --check`.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'IJ014'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'IJ014'`
- `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name 'IJ014'`
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- `./scripts/run_test_gates.sh groups`
- `git diff --check`
- Supporting only when configured: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`

## done criteria

- Focused IJ-014 application and UI tests pass.
- Existing generic `bridgeError` behavior remains covered and green.
- Invite wildcard and row-adjacent integration gates pass.
- Source matrix IJ-014 row is `Covered`.
- `test-inventory.md` IJ-014 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, and ordered session row record IJ-014 as accepted/Covered.

## scope guard

Do not implement a first-class MLS welcome/key-package protocol, new relay/device fixture orchestration, sibling-device approval, or a broad UI redesign in IJ-014. This row closes shipped inline group-key repair-state behavior.
