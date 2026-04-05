# Session SC-018 Plan - Older membership or role event cannot roll back newer state

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-018` needs durable ordering state, not just a
listener-local guard:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-018` as `needs_code_and_tests`.
- `GroupMessageListener` currently applies membership system messages in arrival
  order with no persisted watermark, so a stale replay after restart can still
  roll back newer state.
- The existing data model already has durable signals we can bootstrap from for
  upgraded installs: group creation time, member `joinedAt`, and latest group
  key `createdAt`.

The smallest safe session is therefore to add one persisted group-level
membership-event watermark, seed stale-detection from current persisted facts
when the new watermark is still null, and prove across listener restart that an
older membership snapshot cannot revive or re-remove state after a newer one.

## Final plan

### real scope

- Close source row `SC-018` only: prevent older membership snapshots from
  rolling back newer persisted member/admin-role state.
- Add one durable field on groups for the latest applied membership-event
  timestamp.
- Update the listener to:
  - compare incoming membership-event timestamps against the persisted
    watermark or a persisted-state fallback baseline
  - ignore stale `member_added`, `members_added`, and `member_removed` events
  - persist the new watermark after applying a newer event
- Use incoming system-message timestamps for added-member `joinedAt` so replay
  ordering stays deterministic.
- Preferred direct test home:
  - `test/features/groups/application/group_message_listener_test.dart`
- Persistence coverage:
  - migration test for the new groups column
  - repository round-trip test for the new field
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The groups schema has a durable membership-event watermark column, wired
  through the model and repository.
- The listener ignores stale membership snapshots based on the persisted
  watermark or fallback persisted baseline.
- Direct regressions prove across listener restart that:
  - an older `member_added` cannot revive state after a newer removal
  - an older `member_removed` cannot roll back a newer add/admin-role state
- Migration and repository tests pass, and the named `groups` gate passes.
- `SC-018` is updated to `Closed` or `Covered` only after the row docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Persistence seam:
  - `lib/core/database/migrations/`
  - `lib/core/database/helpers/groups_db_helpers.dart`
  - `lib/features/groups/domain/models/group_model.dart`
  - `lib/features/groups/domain/repositories/group_repository_impl.dart`
- Runtime seam:
  - `lib/features/groups/application/group_message_listener.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo currently has no durable notion of “newer membership snapshot already
  applied,” so stale replay can be applied in reverse order after restart.
- A listener-local watermark would not survive restart and would not honestly
  close the row.
- The new field should stay narrow: one group-level watermark, not a new event
  protocol or broad validator redesign.

### regression/tests to add first

- Add restart-aware stale-event regressions in
  `test/features/groups/application/group_message_listener_test.dart`.
- Add a migration test for the new groups column.
- Add a repository round-trip test for the new field.

### step-by-step implementation plan

1. Add the new groups column via an additive migration and wire it in
   `lib/main.dart`.
2. Thread the field through `GroupModel` and the repository mapping.
3. Update `GroupMessageListener` to compare membership-event timestamps against
   the persisted watermark or fallback baseline before applying them.
4. Add the restart-aware regressions, repository test, and migration test.
5. Run the focused suites and named gate below.
6. Update the row-owned docs only after the proof passes.

### risks and edge cases

- Preserve upgrade behavior for existing installs with null watermarks by
  deriving a fallback baseline from current persisted member/key facts.
- Do not let malformed or missing timestamps break valid current behavior;
  valid repo-generated events already carry timestamps and are the closure bar.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
  - `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart`
  - `flutter test --no-pub test/core/database/migrations/048_groups_last_membership_event_at_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the restart-aware regressions still allow rollback, treat that as in-scope
  evidence the watermark is not durable enough.
- If the gate exposes unrelated failures, keep them separate unless they touch
  group membership-event ordering.

### done criteria

- The new groups watermark field migrates cleanly and round-trips through the
  repository.
- Older membership snapshots are ignored after newer ones across listener
  restart in direct regressions.
- The direct suites above pass.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-018` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  stale-event rollback as open.

### scope guard

- Do not widen into signed-event validation; that remains `SC-015`.
- Do not widen into remove-vs-send ordering; that remains `MR-015` and
  `SC-012`.
- Do not invent a new network protocol when one persisted local watermark is
  enough.

### accepted differences / intentionally out of scope

- This session does not add standalone promote/demote event types.
- This session does not redesign validator enforcement beyond stale-event
  rejection in the Flutter repo-owned layer.

### dependency impact

- `SC-018` can close independently once the durable watermark and restart-aware
  regressions land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
