# 61 Session 1 Plan: Per-Group Mute Persistence and Notification Suppression

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add the repo-local mute state needed to remember whether one joined group
  should suppress local notifications
- create one narrow mutation path to mute and unmute a joined group
- teach `GroupMessageListener` to skip local notifications for muted groups
  while preserving message delivery, persistence, and unread state
- add direct model/repository/listener regressions for mute persistence and
  mute-aware notification gating

Out of scope for this session:

- pending invite persistence, accept/decline, or expiry behavior
- any new mute UI surface beyond the repo contract needed for later sessions
- maintained audit/matrix/doc closure, which belongs to later doc-61 sessions

### Closure bar

Session `1` is done only when:

- joined groups can persist a mute flag without regressing existing group load
  or migration behavior
- a bounded mutation path can mute and unmute one joined group
- muted groups still receive and persist incoming messages, but local
  notifications are not shown for those messages
- unmuted groups still obey the current notification rules and keep working
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

The repo already has a single notification suppression seam in
`GroupMessageListener`, but there is no per-group preference that lets one
group opt out of local notifications. This session must land the mute state and
listener contract first so later UI can toggle a truthful capability instead of
inventing one.

### Files and repos to inspect next

Production files:

- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/database/migrations/049_groups_metadata_columns.dart`
- `lib/main.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`

Direct tests:

- `test/features/groups/domain/models/group_model_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

### Step-by-step implementation plan

1. Add a new group mute column/migration and extend `GroupModel`.
2. Add a narrow application mutation helper/use case for mute and unmute.
3. Gate `GroupMessageListener` notifications on the new mute state while
   preserving all existing delivery and duplicate/active-conversation checks.
4. Add direct regression tests for model mapping, repo persistence, muted
   notification suppression, and unmuted notification behavior.
5. Run the direct tests and `./scripts/run_test_gates.sh groups`.

### Risks and edge cases

- do not let mute affect unread counts or message persistence
- keep the mute contract boolean and bounded for now; timed mute belongs to a
  later product choice
- do not let the migration break fresh installs or the session-60 metadata
  columns

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/domain/models/group_model_test.dart`
- `flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- the mute storage plus listener contract lands with direct tests
- the `groups` gate passes
- the doc-61 session-1 ledger entry can truthfully move out of `pending`

### Scope guard

- do not start pending invite lifecycle or UI work in this session
- do not redesign the broader notification service
