# RP-004 Session Plan - Local and receive-side mutation authorization

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T05:36:00+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; session breakdown; local add/remove/role/rotate/metadata/send/reaction use-case tests; `group_message_listener.dart`; `group_key_update_listener.dart`; listener tests | Existing tests pin many local guards and the generic system-event receive guard for member, role, metadata, and dissolve mutations. A row-owned receive gap remains: direct `group_key_update` messages decrypt and apply `group:updateKey` without re-authorizing `message.from` as a current member with key-rotation permission. | Reclassify RP-004 from tests-only to code-and-tests for the direct key-update receive path. |
| 2026-05-01T05:36:30+02:00 | Planner completed | same | Patch only the direct key-update receive path. Require the sender to be a current group member whose effective permissions allow `rotateKeys` before bridge update, event-log append, or key save. Preserve missing-group, dissolved-group, decrypt-failure, replay, and bridge-failure behavior. | Implement auth guard and focused RP-004 tests. |

## Execution Progress

| timestamp | phase | files inspected or touched | command / evidence | decision | next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-01T05:38:00+02:00 | Direct key-update guard implemented | `lib/features/groups/application/group_key_update_listener.dart`; `test/features/groups/application/group_key_update_listener_test.dart` | Added current-member `rotateKeys` receive authorization before `group:updateKey`, event-log append, or key save; added RP004 unauthorized and rotate-permission direct key-update tests. | The discovered receive-side key-rotation gap is patched in the row owner. | Run focused key-update tests. |
| 2026-05-01T05:38:30+02:00 | Focused key-update tests passed | `group_key_update_listener_test.dart` | `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'RP004'` passed (`+2`); full `group_key_update_listener_test.dart` passed (`+18`). | Direct key-update receive authorization and existing listener behavior are green. | Run local and generic receive authorization matrix tests. |
| 2026-05-01T05:39:20+02:00 | Local and receive auth checks passed | group listener, add/remove/role/rotate/metadata/send/reaction tests | `group_message_listener_test.dart --plain-name 'unauthorized mutation system events leave local state and bridge unchanged'` passed (`+1`); focused local mutation guards for add, remove, role update, key rotate, metadata edit, send, send reaction, and remove reaction each passed (`+1`). | Existing shipped local and generic receive mutation guards remain green. | Run smoke, integration, and groups gates. |
| 2026-05-01T05:42:10+02:00 | Integration fixture recovery completed | `member_removal_integration_test.dart` | The broad application suite exposed receive-key-update fixtures that predated sender authorization. Receiver fixtures now save the key-update sender as an authorized member at receipt time; `member_removal_integration_test.dart` passed (`+5`). | Fixture updates are aligned with the new receive auth contract. | Run integration and canonical group gates. |
| 2026-05-01T05:43:00+02:00 | Integration and groups gates passed | groups integration suite; canonical groups gate | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`); `git diff --check` passed. | RP-004 row gates are green. | Close docs. |

## execution and closure evidence

Final execution verdict: `accepted`.

RP-004 is covered for shipped trusted-private group mutating actions. `GroupKeyUpdateListener` now re-authorizes direct key-update receive messages by loading `message.from` as a current group member and requiring effective `rotateKeys` permission before the local Go validator is updated, the event log is appended, or the new key is saved. Unauthorized direct key updates still decrypt far enough to identify the group and epoch, then stop without bridge mutation, event-log state, or key persistence.

Focused RP004 tests prove an unauthorized writer cannot apply a direct key update and that a writer with an explicit `rotateKeys` override can apply one. Existing tests prove local authorization for add, remove, role update, key rotation, metadata edit, send, and reactions, and receive-side authorization for member, role, metadata, and dissolve system events. `member_removal_integration_test.dart` fixtures now model the receiver-side membership state required by the new direct key-update auth contract.

The broad command `flutter test --no-pub test/features/groups/application` still fails one unrelated existing test, `MD-011 removed member cannot decode future media replay with only the old epoch` in `drain_group_offline_inbox_use_case_test.dart`; that test also fails in isolation and is not caused by the RP-004 key-update authorization changes. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. RP-004 does not claim first-class product flows for unshipped group pin, message edit/delete, or ban surfaces; ban-equivalent removal and shipped role/metadata/key/send/reaction/invite paths are covered.

## real scope

Close RP-004 for shipped trusted-private group mutating actions by proving local actions reject unauthorized callers before side effects and receive-side mutation paths re-authorize senders before applying local state. This session owns the discovered direct key-update receive authorization gap because key rotation is explicitly named by RP-004.

## closure bar

RP-004 can close only when:

- direct key-update receive messages from non-members or members without `rotateKeys` are ignored before `group:updateKey`, event-log append, or key save
- direct key-update receive messages from authorized admins or members with an explicit `rotateKeys` override still apply
- existing generic system-event receive authorization coverage for member, role, metadata, and dissolve mutations remains green
- existing local authorization tests for add, remove, role update, key rotate, metadata edit, send, and reactions remain green
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`needs_code_and_tests`.

The initial breakdown classified RP-004 as test-only, but planning found an implementation-owned receive-side gap in `GroupKeyUpdateListener`.

## files to touch

- `lib/features/groups/application/group_key_update_listener.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`

## files to cite as existing RP-004 evidence

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/remove_group_reaction_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## step-by-step implementation plan

1. Add a direct key-update sender authorization check after group lookup and dissolved-state rejection.
2. Load `message.from` as a current group member and require effective `rotateKeys` permission for that member role.
3. Return before `group:updateKey`, event-log append, or key save when the sender is missing, removed, stale, or unauthorized.
4. Update key-update listener test helpers so success fixtures include an authorized sender member.
5. Add focused RP-004 tests for unauthorized direct key update rejection and explicit rotate-permission acceptance.
6. Run focused key-update tests, existing receive mutation guard tests, local mutation guard tests, integration smoke, groups gate, and `git diff --check`.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'RP004'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'unauthorized mutation system events leave local state and bridge unchanged'`
- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'rechecks revoked invite permission before adding a queued member'`
- `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name 'rechecks revoked remove permission before removing a queued target'`
- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'rechecks revoked manage-roles permission before applying queued role update'`
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'rechecks revoked rotate permission before generating a queued key'`
- `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart --plain-name 'rejects non-admin edits'`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects stale send after local membership removal before persistence'`
- `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name 'non-member is rejected'`
- `flutter test --no-pub test/features/groups/application/remove_group_reaction_use_case_test.dart --plain-name 'non-member is rejected'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `./scripts/run_test_gates.sh groups`
- `git diff --check`
- Supporting only when configured: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`

## done criteria

- Focused RP-004 direct key-update tests pass.
- Broader RP-004 local and receive authorization evidence gates pass.
- Source matrix RP-004 row is `Covered`.
- `test-inventory.md` RP-004 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record RP-004 as accepted/Covered.

## scope guard

Do not implement unrelated first-class pin, ban, message edit, or message delete product surfaces in RP-004. This session closes authorization for shipped mutating surfaces and explicitly records any unavailable real-device or unshipped-surface proof without claiming those surfaces exist.
