# 61 Session 2 Plan: Pending Invite Lifecycle and Acceptance Use Cases

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add durable repo-local pending group invite persistence instead of
  auto-joining immediately on invite receipt
- refactor invite receipt so validated invites are stored for review and do not
  create joined group state yet
- add explicit accept, decline, and expiry use cases over pending invites
- preserve the existing join plus inbox-drain contract once a user explicitly
  accepts a pending invite
- add direct repository/application coverage plus an integration invite
  round-trip for pending, accept, decline, duplicate, and expiry outcomes

Out of scope for this session:

- the user-facing pending-invite review UI and mute/invite controls, which
  belong to session `3`
- audit and matrix doc closure, which belongs to session `4`

### Closure bar

Session `2` is done only when:

- valid incoming invites are stored durably as pending review items without
  joining the group or draining inbox content immediately
- accepting a pending invite materializes the real group, joins the topic, and
  reuses the expected inbox-drain contract
- declining or expiring a pending invite removes it cleanly without ghost
  group, member, or key state
- duplicate already-joined groups stay rejected instead of creating stale
  pending rows
- the direct tests pass, plus the required named `groups` gate

### Source of truth

- active session contract:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls.md`
- gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`

### Exact problem statement

The repo currently treats a valid invite as an implicit join. Session `2`
must split invite receipt from invite acceptance so the app can preserve the
existing join mechanics while giving later UI a truthful pending-review
contract instead of a hidden auto-join side effect.

### Files and repos to inspect next

Production files:

- `lib/core/database/helpers/groups_db_helpers.dart`
- `lib/core/database/migrations/050_groups_mute_column.dart`
- `lib/main.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`

Direct tests:

- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`

### Step-by-step implementation plan

1. Add a `pending_group_invites` persistence contract with a doc-safe
   migration, model, helpers, repository, and test fake.
2. Refactor invite parsing/validation so valid invites can be stored as
   pending items without immediately materializing a group.
3. Add accept, decline, and expiry use cases that consume pending invites and
   reuse the existing group join plus inbox-drain path on accept.
4. Update `GroupInviteListener` to store pending invites and emit a pending
   stream instead of auto-broadcasting joined groups.
5. Add direct repository/application regressions and an integration round-trip
   covering pending storage, accept, decline, duplicate, and expiry.
6. Run the targeted tests and `./scripts/run_test_gates.sh groups`.

### Risks and edge cases

- do not materialize group, member, or key rows before explicit acceptance
- delete stale pending rows when they expire or when acceptance discovers the
  group already exists
- keep the existing duplicate-group and join-time bridge behavior intact for
  acceptance
- store enough invite preview data for the later UI session without inventing
  a separate source of truth

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/group_invite_listener_test.dart`
- `flutter test test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `flutter test test/features/groups/integration/invite_round_trip_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- pending invite storage plus accept/decline/expiry behavior lands with direct
  and integration proof
- the `groups` gate passes
- the doc-61 session-2 ledger entry can truthfully move out of `in_progress`

### Scope guard

- do not start the session-3 pending review UI in this session
- do not close audit or matrix docs here
