# Session SC-007 Plan - Stale client resync

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-007` is a real behavior gap, not just a proof
gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-007` as `implementation-ready` with `code changes and tests`
  ownership.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` already says
  startup/watchdog rejoin and inbox catch-up exist, but the repo does not yet
  force stale membership/admin replay to settle before admin-only actions can
  proceed.
- `lib/core/lifecycle/handle_app_resumed.dart` already sequences rejoin before
  drain, but there is no shared runtime fence that blocks admin-only group
  actions while that recovery is still in flight.
- `lib/features/identity/presentation/startup_router.dart` currently kicks
  rejoin and drain separately instead of one recovery scope, which keeps the
  stale-config window larger than necessary.

The smallest safe session is therefore to add one runtime group-recovery fence,
use it around resume/startup recovery, reject admin-only group actions while
that fence is active, land a direct regression proving the blocked-path plus
replay outcome, and then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `SC-007` only: ensure a client with stale cached
  membership/admin state cannot execute admin-only group actions until resume
  recovery has replayed the latest valid membership state.
- Add the narrowest runtime guard that covers:
  - resume recovery in `handleAppResumed(...)`
  - startup recovery in `StartupRouter`
  - admin-only group actions that currently trust stale local state
- Preferred implementation seam:
  - add a lightweight shared recovery gate in the group application layer
  - wrap rejoin + drain inside that gate
  - fail fast in `addGroupMember(...)`, `removeGroupMember(...)`, and
    announcement-only `sendGroupMessage(...)` while recovery is active
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- A stale client cannot run an admin-only group action while resume/startup
  group recovery is in flight.
- The blocked path is covered by direct repo-local regression proof.
- Recovery still completes and replays the pending membership change so the
  stale client converges to the latest valid state.
- Direct proof passes, and the named `groups` gate passes.
- `SC-007` is updated to `Closed` or `Covered` only after the row docs cite the
  landed code/test evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo can already rejoin topics and drain offline group inboxes.
- The open gap is narrower but real: those recovery steps do not currently own
  a shared runtime barrier that stops stale admin/member cache from being used
  for admin-only actions before replay finishes.
- This session should not widen into unsupported admin-promotion flows,
  authenticated membership events, or stale-event rollback prevention.

### regression/tests to add first

- Add a direct recovery regression proving that while resume recovery is
  waiting to replay a pending `member_removed` system message, the stale client
  cannot execute an admin-only group action, and once recovery completes the
  client converges to the removed state.
- Add narrow unit coverage that the admin-only use cases reject while the
  recovery fence is active.

### step-by-step implementation plan

1. Add a lightweight shared runtime recovery gate in the group application
   layer with re-entrant `run(...)` semantics and an observable `isActive`
   check.
2. Wrap resume/startup group recovery so `rejoinGroupTopics(...)` and
   `drainGroupOfflineInbox(...)` execute inside one recovery fence.
3. Make `addGroupMember(...)` and `removeGroupMember(...)` fail fast with a
   clear stale-recovery error while the fence is active.
4. Make `sendGroupMessage(...)` fail fast for announcement-group sends while
   the fence is active so stale admin-role cache cannot be used before replay.
5. Add/extend direct tests for:
   - resume-time blocked admin action before replay
   - use-case rejection while the recovery fence is active
   - startup/resume sequencing remaining intact
6. Run the direct suites and named gate below.
7. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep the fence runtime-only; do not introduce new DB state unless the direct
  regression proves it is unavoidable.
- Do not overclaim broader stale-event ordering guarantees; this row is about
  recovery-before-admin-action, not arbitrary event rollback.
- Avoid blocking ordinary chat sends unless required by current repo-owned
  scope; the guard should stay tied to admin-only actions.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the blocked-path regression fails, treat that as in-scope evidence that
  stale local state can still drive admin-only behavior during recovery.
- If the `groups` gate exposes unrelated pre-existing failures, keep them
  separate unless they touch the stale-resync seam.

### done criteria

- Resume/startup recovery owns one shared runtime fence across rejoin + inbox
  drain.
- Admin-only group actions are rejected while that fence is active.
- Direct proof shows the stale client cannot act before replay and then
  converges to the latest valid membership state.
- The direct suites above pass.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-007` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  this row as only partially covered.

### scope guard

- Do not widen into promotion/demotion feature work; that remains outside the
  current repo-owned scope.
- Do not broaden into signed membership-event authentication; that remains
  `SC-015`.
- Do not broaden into stale-event rollback metadata; that remains `SC-018`.

### accepted differences / intentionally out of scope

- The repo may still rely on later rows for stronger stale-event ordering and
  authenticated admin-change semantics.
- Ordinary non-privileged chat sends do not need new blocking in this session
  unless existing code disproves that assumption.

### dependency impact

- `SC-007` can close independently once the stale-recovery fence and direct
  regression land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
