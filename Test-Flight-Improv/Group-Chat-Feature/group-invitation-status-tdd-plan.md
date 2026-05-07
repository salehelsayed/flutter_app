# Group Invitation Status TDD Plan

Status: `execution-ready`

Session classification: `implementation-ready`

## Feedback Review Result

The feedback is accepted as structurally valid. The previous draft had placeholder test paths, did not name all production entry files, omitted the required named gates, and did not make the SQLite version/migration proof explicit enough for implementation.

Already sufficient and intentionally preserved: product behavior, non-goals, local-only/backward-compatible constraint, invite status states, TDD ordering, and the no-protocol-change guard.

## Real Scope

Add local, backward-compatible invite delivery status tracking so User A can open the Group Info `i` screen and see whether each invited member's invitation was sent, queued, failed, cannot be sent, or later joined.

This is a local app-state change only. It must not change the group invite wire protocol, `group_invite`, `members_added`, group key format, or legacy app behavior.

## Closure Bar

The work is good enough when a user who creates or adds group members during network failure can later open Group Info and tell which invitees likely received an invite and which invitees need manual resend. The status must survive app restart, must update when the existing `member_joined` event is observed, and must be covered by direct tests plus the required named gates.

## Source Of Truth

- Current production code and tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gates; it requires `./scripts/run_test_gates.sh groups` for group invite changes and `./scripts/run_test_gates.sh baseline` for every PR.
- Because this plan wires a SQLite migration through `lib/main.dart`, the Startup / Transport Gate also applies: `./scripts/run_test_gates.sh transport`.
- Current database version is `66` in `lib/main.dart`; this plan requires migration `067` and version `67` wiring if a new SQLite table is added.
- This document is the implementation contract unless code evidence during TDD proves a narrower change is sufficient.

## Exact Problem Statement

When group creation or add-member invite delivery partially fails, the creator may still see the group and locally added members. The existing UI does not persist or display whether each invitation was actually sent, stored for later delivery, failed, or cannot be sent. That leaves the creator unable to decide whether to manually resend.

The user-visible fix is a per-member invite status on the Group Info member list, with a manual `Send again` action only when the local record says the invite needs resend.

## Files And Repos To Inspect Next

Database and app bootstrap:

- `lib/core/database/migrations/067_group_invite_delivery_attempts.dart`
- `lib/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart`
- `lib/main.dart` for migration/version wiring and helper-backed repository construction
- `test/core/database/integration/full_migration_chain_test.dart`

Domain and repository:

- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart` as the closest existing invite repository pattern

Application entry points:

- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`

Group Info presentation entry points:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`

Typed seam files to keep coherent in one pass:

- `lib/main.dart` must construct the new helper-backed invite-status repository if production code depends on it.
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart` calls `createGroupWithMembers`; update it if create-flow invite-status persistence adds repository dependencies or result semantics.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` constructs `GroupInfoWired`; update it if Group Info needs invite-status or resend dependencies.
- `lib/features/groups/presentation/screens/group_info_wired.dart` constructs `ContactPickerWired`; update both caller and callee if add-member invite-status persistence needs the same dependency.
- Any constructor, callback, repository, or route initialization change must update all callers and direct tests in the same Executor pass.

## Existing Tests Covering This Area

- `test/features/groups/application/send_group_invite_use_case_test.dart` covers invite send outcomes but must be extended because success currently does not provide enough direct-vs-inbox detail for UI status.
- `test/features/groups/application/create_group_with_members_use_case_test.dart` covers local group creation with invite batch results but does not prove persisted per-member invite status.
- `test/features/groups/presentation/contact_picker_wired_test.dart` covers add-member invite warnings but does not prove status persistence.
- `test/features/groups/application/group_message_listener_test.dart` covers incoming group events and should be extended for `member_joined` to `joined` status.
- `test/features/groups/presentation/group_info_screen_test.dart` and `test/features/groups/presentation/group_info_wired_test.dart` cover Group Info rendering/wiring but not invite delivery status rows.
- `test/features/groups/presentation/create_group_picker_wired_test.dart` covers create-flow navigation and warning snackbar behavior, but not invite-status repository wiring.
- `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart` is the closest repository proof pattern for invite-related persistence.

## Regression/Tests To Add First

Add these failing tests before production code:

1. `test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`
   - Proves migration `067` creates `group_invite_delivery_attempts`.
   - Proves idempotency.
   - Proves the `(group_id, peer_id)` uniqueness contract and lookup indexes.

2. `test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`
   - Proves helper upsert, load by group/member, load all for group, delete-by-group/member if needed, and status update semantics.

3. `test/core/database/integration/full_migration_chain_test.dart`
   - Proves fresh install includes migration `067`.
   - Proves upgrade from the current chain through `067` preserves seeded group/member data.
   - Proves the table exists after the full chain.

4. `test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`
   - Proves repository round-trips all statuses.
   - Proves no-row legacy members project as `unknown`.
   - Proves repository maps helper rows without relying on UI logic.

5. Extend application tests:
   - `test/features/groups/application/send_group_invite_use_case_test.dart`
   - `test/features/groups/application/create_group_with_members_use_case_test.dart`
   - `test/features/groups/application/group_message_listener_test.dart`
   - Add `test/features/groups/application/resend_group_invite_use_case_test.dart`

6. Extend presentation tests:
   - `test/features/groups/presentation/contact_picker_wired_test.dart`
   - `test/features/groups/presentation/create_group_picker_wired_test.dart`
   - `test/features/groups/presentation/group_info_screen_test.dart`
   - `test/features/groups/presentation/group_info_wired_test.dart`

## Step-By-Step Implementation Plan

1. Write the failing persistence tests for migration `067`, DB helpers, full migration chain, and repository behavior.

2. Add migration `067_group_invite_delivery_attempts` and wire it into `lib/main.dart`:
   - import the new migration
   - bump encrypted DB version from `66` to `67`
   - call the migration in the fresh-install `onCreate` chain
   - add `if (oldVersion < 67) await runGroupInviteDeliveryAttemptsMigration(db);`

3. Add `group_invite_delivery_attempts` as a local-only table keyed by `(group_id, peer_id)`. Required status values:
   - `sent`: direct P2P invite succeeded
   - `queued`: direct failed but relay inbox store succeeded
   - `needs_resend`: direct and inbox failed, node stopped, or group key missing
   - `cannot_send`: missing secure key or invalid invite payload
   - `joined`: existing `member_joined` event observed for that peer
   - `unknown`: no local attempt record, mainly legacy/pre-migration rows

4. Add DB helpers, model, and repository. Repository tests own the proof that app code can upsert/load statuses; helper tests own SQL behavior.

5. Extend `send_group_invite_use_case.dart` so application code can distinguish direct success from inbox fallback success without changing the wire payload. Map direct success to `sent`, inbox fallback success to `queued`, and hard failures to `needs_resend` or `cannot_send`.

6. Wire create-group and add-member flows to persist one status row per selected invitee from `GroupInviteBatchResult`, including failure paths after local members have already been added.

7. Add resend use case. It must only rebuild and send the invite for the existing member, then update status. It must not add the member again and must not publish another `members_added`.

8. Extend `GroupMessageListener` handling of the existing `member_joined` system event to mark the matching member `joined`.

9. Wire helper-backed repository construction and typed callers coherently:
   - construct the new repository in `lib/main.dart`
   - pass dependencies through create/add-member and Group Info navigation seams only where needed
   - update caller-side tests whenever a constructor or callback signature changes

10. Update Group Info wired state and rows to load statuses, show compact status labels, and expose `Send again` only for `needs_resend`.

11. Run direct tests first, then named gates. Stop if any new direct test or gate failure is caused by this scope.

## Risks And Edge Cases

- `sendGroupInvite` success currently risks conflating direct delivery and inbox fallback. Tests must pin the mapping before UI status depends on it.
- `sent` and `queued` are delivery-attempt states, not acceptance states. Only `member_joined` may display `joined`.
- Legacy groups and old invite rows must show `unknown`, not failure.
- Manual resend must be idempotent and must not duplicate members or membership events.
- Missing secure key, invalid payload, and stopped node must not leave the user with a misleading `sent` label.
- If the app receives `member_joined` before a local invite status row exists, repository behavior should upsert `joined`.

## Exact Tests And Gates To Run

Direct persistence tests:

```sh
flutter test test/core/database/migrations/067_group_invite_delivery_attempts_test.dart
flutter test test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart
flutter test test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart
```

Direct application and presentation tests:

```sh
flutter test test/features/groups/application/send_group_invite_use_case_test.dart
flutter test test/features/groups/application/create_group_with_members_use_case_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/application/resend_group_invite_use_case_test.dart
flutter test test/features/groups/presentation/contact_picker_wired_test.dart
flutter test test/features/groups/presentation/create_group_picker_wired_test.dart
flutter test test/features/groups/presentation/group_info_screen_test.dart
flutter test test/features/groups/presentation/group_info_wired_test.dart
```

Focused regression commands:

```sh
flutter test test/features/groups/application test/features/groups/presentation
flutter test test/features/contact_request/integration/contact_request_flow_test.dart
```

Named gates:

```sh
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

Final hygiene:

```sh
git diff --check
```

## Known-Failure Interpretation

Treat unrelated existing local worktree changes outside the invite-status scope as out of scope. Any new failure in the direct tests or named gates above is a blocker when it is caused by these files or by the new tests. If `baseline`, `groups`, `transport`, or `completeness-check` is already red before implementation, capture the pre-existing failure, keep the direct invite-status suite green, and do not classify old red tests as regressions from this work.

## Done Criteria

- [ ] All new tests listed in `Regression/Tests To Add First` fail for the expected reason before production implementation.
- [ ] Migration `067_group_invite_delivery_attempts` is added, idempotent, wired in `lib/main.dart`, and covered by `full_migration_chain_test.dart`.
- [ ] Repository and DB helper tests prove status upsert/load and legacy `unknown` behavior.
- [ ] Create-group and add-member flows persist per-recipient invite status for direct success, inbox fallback, send failure, node stopped, missing key, and invalid payload.
- [ ] Group Info member list displays invite status and only shows `Send again` for `needs_resend`.
- [ ] Resend sends an invite only, does not duplicate members, and updates the visible status.
- [ ] Existing `member_joined` handling updates status to `joined`.
- [ ] All changed typed seams are coherent: repository construction, constructor parameters, route builders, callbacks, and their direct widget/application tests compile and pass together.
- [ ] Direct tests, `baseline`, `groups`, `transport`, `completeness-check`, and `git diff --check` pass or have documented unrelated pre-existing failures.
- [ ] No group invite protocol, `members_added`, or key material wire format changes are introduced.

## Scope Guard

- Do not add invite ACK messages, delivery receipts, remote acceptance receipts, or new wire payload fields.
- Do not auto-resend in this session. Manual resend from Group Info only.
- Do not remove locally added group members when invite delivery fails; existing behavior stays unchanged.
- Do not infer acceptance from `sent` or `queued`.
- Do not require non-updated users to understand, write, or preserve the new local status table.
- Do not broaden this into a group protocol redesign.

## Accepted Differences / Intentionally Out Of Scope

- Updated apps get clearer local status in Group Info; older apps simply lack the new local table and UI labels.
- `unknown` is acceptable for legacy rows because old app versions never recorded invite-attempt state.
- `queued` means the app stored the invite in the fallback path; it does not guarantee the recipient accepted or joined.
- A future protocol-level invite acknowledgment system would be a separate compatibility design and is intentionally out of scope.

## Dependency Impact

This plan is safe to implement before any protocol work because it only records local invite-attempt outcomes and existing join observations. Later work that wants true recipient acknowledgments must not reuse `sent` or `queued` as acceptance proof; it should add a separate protocol and migration plan with explicit compatibility handling.
