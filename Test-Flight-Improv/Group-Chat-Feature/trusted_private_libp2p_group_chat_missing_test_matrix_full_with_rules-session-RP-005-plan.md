# RP-005 Session Plan - Stale permission rejection

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T05:48:00+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; session breakdown; stale local add/remove/role/rotate/metadata/send/retry tests; `group_message_listener.dart`; receive-side stale metadata and role tests | Existing tests pin local stale-permission rechecks for queued add, remove, role, rotate, metadata, send, and retry. Receive-side watermark tests pin older metadata/role/member events after newer state. A row-owned receive authorization gap remains: `_isAuthorizedMembershipEventSender` lets `group.createdBy` authorize membership and metadata events even when that peer is currently demoted or removed, so a stale creator-originated event can mutate receive-side state after permission loss. | Reclassify RP-005 from tests-only to code-and-tests for receive-side current-permission revalidation. |
| 2026-05-01T05:48:30+02:00 | Planner completed | same | Remove stale creator fallback as an authorization substitute when processing receive-side membership and metadata mutation events. Require current sender membership with the relevant effective authorization, preserving self-removal and existing role escalation checks. | Patch listener authorization and add focused RP005 receive-side tests. |

## real scope

Close RP-005 for shipped trusted-private stale-permission behavior: local queued actions re-read current permission/role state before side effects, and receive-side stale mutation events from demoted or removed actors are rejected before local state, timeline, or bridge sync changes.

## closure bar

RP-005 can close only when:

- demoted or removed creator/sender receive-side mutation events cannot rely on stored `createdBy` to mutate membership, metadata, role, dissolve, or key state
- existing local queued stale-permission guards remain green for invite/add, remove, role update, key rotation, metadata edit, send, and failed-message retry
- existing receive-side stale watermark tests remain green for older metadata/member events after newer state
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`needs_code_and_tests`.

The initial breakdown classified RP-005 as test-only, but planning found an implementation-owned receive-side stale-permission gap in `GroupMessageListener`.

## files to touch

- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_message_listener_test.dart`

## files to cite as existing RP-005 evidence

- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`

## step-by-step implementation plan

1. Tighten `_isAuthorizedMembershipEventSender` so stored `createdBy` is not enough after a sender is demoted or removed.
2. Preserve current admin authorization, current self-removal, and bounded member-role update authorization.
3. Add a focused RP005 listener test that sends stale receive-side metadata/member mutations from a demoted stored creator and proves no state, timeline, or bridge mutation.
4. Run focused RP005 listener tests, existing local stale-permission tests, listener stale watermark tests, integration/group gates, and `git diff --check`.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RP005'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'older group_metadata_updated cannot roll back a newer metadata state after restart'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'older member_role_updated cannot roll back a newer role change across restart'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'older member_role_updated cannot resurrect a member removed by a newer event across restart'`
- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'rechecks revoked invite permission before adding a queued member'`
- `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name 'rechecks revoked remove permission before removing a queued target'`
- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'rechecks revoked manage-roles permission before applying queued role update'`
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'rechecks revoked rotate permission before generating a queued key'`
- `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart --plain-name 'rechecks demoted local role before applying queued metadata edit'`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects stale send after local membership removal before persistence'`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name 'does not replay a failed text row after sender was removed locally'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`
- Supporting only when configured: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`

## done criteria

- Focused RP005 receive-side stale-permission tests pass.
- Existing local stale-permission focused tests pass.
- Listener stale watermark tests pass.
- Canonical group gates pass or any unrelated failure is explicitly classified.
- Source matrix RP-005 row is `Covered`.
- `test-inventory.md` RP-005 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record RP-005 as accepted/Covered.

## scope guard

Do not implement a broad offline queue engine, device-lab relay orchestration, or cryptographic actor-signature matrix in RP-005. This row closes current repo stale-permission revalidation for shipped local and receive mutation surfaces; EK/signature and real-device proof stay separate unless configured.

## Execution Progress

| timestamp | role | files changed or inspected | result | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T05:52:00+02:00 | Executor completed | `lib/features/groups/application/group_message_listener.dart`; `test/features/groups/application/group_message_listener_test.dart` | `_isAuthorizedMembershipEventSender` no longer uses stored `createdBy` as a receive-side authorization fallback after the actor is demoted or removed. Receive-side mutation events now require current sender membership and the relevant admin/role-update authorization, while current self-removal remains allowed. Added `RP005 demoted creator receive-side mutations are rejected before side effects`; also made legacy authorized admin and self-removal fixtures explicit under the stricter current-state guard. | Run focused stale-permission tests and broad group gates. |
| 2026-05-01T06:00:00+02:00 | QA completed | Focused RP005 listener test; metadata/role watermark tests; local stale add/remove/role/rotate/metadata/send/retry tests; full listener suite; group smoke/integration gates | Accepted. Focused RP005 listener proof passed (`+1`); metadata/role watermark tests passed (`+1` each); focused local stale queued-action guard tests passed (`+1` each); full `group_message_listener_test.dart` passed (`+81`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). Broad `flutter test --no-pub test/features/groups/application` still fails unrelated existing MD-011 drain-inbox media replay coverage, and the MD-011 test fails in isolation. | Close RP-005 in source matrix, inventory, and breakdown; keep MD-011 and unconfigured real-network nightly as explicit caveats. |

## Final Execution Verdict

Accepted. RP-005 is implementation-owned and now covered for shipped local stale-action rechecks plus receive-side stale membership/metadata mutation rejection. The source matrix and inventory may move to `Covered` with the evidence above. Supporting real-network nightly remains unrun because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset; unrelated MD-011 remains open outside RP-005.
