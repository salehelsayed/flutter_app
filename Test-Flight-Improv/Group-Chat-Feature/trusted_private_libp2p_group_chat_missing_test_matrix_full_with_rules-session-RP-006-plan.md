# RP-006 Session Plan - Permission escalation protection

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:04:00+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; session breakdown; `group_role_update_authorization.dart`; `update_group_member_role_use_case.dart`; local and receive role-update tests | Existing tests prove a limited manager cannot promote another member to admin or grant unheld permissions, but the helper still allows a non-admin manager to demote or otherwise touch an existing admin because it only blocks `newRole == admin`. This is a row-owned permission-escalation gap. | Patch the shared role-update authorization helper, pass current target role into the local use case, and add local plus receive tests. |

## real scope

Close RP-006 for shipped role/permission escalation protection: a member with limited role-management permission can manage only non-admin roles and cannot grant themselves or others admin status, demote an existing admin, or grant permissions they do not already hold.

## closure bar

RP-006 can close only when:

- local `updateGroupMemberRole` rechecks the target's current role before accepting a limited-manager role change
- receive-side `member_role_updated` rejects limited-manager attempts to promote to admin, demote/touch an existing admin, or grant unheld permissions before local state, timeline, or bridge config mutation
- bounded allowed reader-to-writer role-management behavior remains green
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`needs_code_and_tests`.

## files to touch

- `lib/features/groups/application/group_role_update_authorization.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`

## step-by-step implementation plan

1. Tighten `canApplyGroupMemberRoleUpdate` so non-admin actors cannot change any target whose existing role is admin and cannot assign admin to any non-admin target.
2. Load the local target member before the local escalation check and pass `existingRole`/`existingPermissions` into the shared helper.
3. Add a local test proving a writer with `manageRoles` cannot demote an existing admin before bridge sync.
4. Add a receive test proving a limited manager's replayed `member_role_updated` cannot demote an admin before bridge sync, timeline, or member mutation.
5. Run focused RP-006 tests, full role/listener files, group smoke/integration gates, and `git diff --check`.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'writer with manage-roles permission cannot demote an admin'`
- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'writer with manage-roles permission cannot promote a member to admin'`
- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'allows writer with manage-roles permission override to update role'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'limited manager member_role_updated cannot demote an admin'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'limited manager member_role_updated cannot promote a member to admin'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'limited manager member_role_updated cannot grant unheld permissions'`
- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- Focused local and receive RP-006 escalation tests pass.
- Existing allowed limited-manager reader-to-writer behavior remains green.
- Listener unauthorized role/permission escalation tests remain green.
- Canonical group gates pass or any unrelated failure is explicitly classified.
- Source matrix RP-006 row is `Covered`.
- `test-inventory.md` RP-006 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record RP-006 as accepted/Covered.

## scope guard

Do not implement a first-class permission-edit UI/API, broad cryptographic signature matrix, account/device registry, or live real-device proof in RP-006. This row closes shipped local and receive-side role/permission escalation checks for current role-update surfaces; broader event-signature and real transport proof remain separate rows unless configured.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:11:43+02:00 | Executor completed | `group_role_update_authorization.dart`; `update_group_member_role_use_case.dart`; `update_group_member_role_use_case_test.dart`; `group_message_listener_test.dart`; `drain_group_offline_inbox_use_case_test.dart` | RP-006 shipped role-update escalation gap is fixed: non-admin managers cannot assign admin or touch existing admin roles, local role updates recheck the target's current role and permissions before mutation, and receive-side role updates reject limited-manager admin demotion/touch and unheld permission grants before bridge/timeline/state side effects. Two offline-inbox self-removal replay fixtures now seed the current admin sender member required by the stricter receive-side authorization contract. | Update source matrix, inventory, and breakdown to `Covered`, then run stale-status and diff hygiene checks. |
| 2026-05-01T06:11:43+02:00 | Verification completed | Focused RP-006 role-update and listener tests; full role-update file; full listener file; self-removal replay fixture tests; group smoke and integration gates; broad application JSON sweep | Focused RP-006 tests and full files passed; group membership smoke passed `+24`; `./scripts/run_test_gates.sh groups` passed `+97`; full group integration passed `+119`; broad group application sweep now fails only the pre-existing MD-011 future-media replay case in `drain_group_offline_inbox_use_case_test.dart`. | Record MD-011 as unrelated caveat; do not close cryptographic actor-signature, first-class permission-edit UI/API, pin/delete surfaces, or real-device proof under RP-006. |

## Final Execution Verdict

`accepted`: RP-006 is ready to mark `Covered` for shipped local and receive-side role/permission escalation protection. The remaining MD-011 failure is unrelated to RP-006, and unconfigured real-device or broader cryptographic signature proof remains out of this row's closure scope.
