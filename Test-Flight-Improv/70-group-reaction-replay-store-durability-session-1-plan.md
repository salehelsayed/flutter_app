# 70 Session 1 Plan: Durable Sender-Owned Reaction Replay Outbox

## Final Verdict

- Status:
  `accepted`
- Accepted on:
  `2026-04-13`
- Why:
  - the repo now owns a dedicated `group_reaction_replay_outbox` persistence
    contract through migration `054`, DB helpers, a model, a repository, and a
    test fake
  - `sendGroupReaction(...)` and `removeGroupReaction(...)` now persist the
    exact `group:inboxStore` retry payload before the first store attempt and
    update the row to `stored` or `failed` instead of leaving replay storage as
    best-effort work
  - the direct migration and use-case suites passed, followed by green
    `groups` and `baseline` gates on the landed code

## Landed Scope

- add one sender-owned durable outbox for group reaction replay add/remove
  attempts
- persist the exact retry payload needed for later replay storage without
  recomputing the envelope after key rotation or membership drift
- keep live publish plus local optimistic reaction truth unchanged
- mark immediate successful replay storage rows `stored` instead of deleting
  them so later retry state and diagnostics stay truthful

Out of scope for this session:

- consuming the new outbox from resume or pending-retry owners
- refreshing maintained audit or matrix docs

## Files

Production:

- `lib/core/database/migrations/054_group_reaction_replay_outbox.dart`
- `lib/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart`
- `lib/features/groups/domain/models/group_reaction_replay_outbox_entry.dart`
- `lib/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart`
- `lib/features/groups/domain/repositories/group_reaction_replay_outbox_repository_impl.dart`
- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/remove_group_reaction_use_case.dart`
- `lib/main.dart`

Direct tests:

- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/remove_group_reaction_use_case_test.dart`
- `test/core/database/migrations/054_group_reaction_replay_outbox_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

## Verification

Direct tests:

- `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
- `flutter test test/features/groups/application/remove_group_reaction_use_case_test.dart`
- `flutter test test/core/database/migrations/054_group_reaction_replay_outbox_test.dart`
- `flutter test test/core/database/integration/full_migration_chain_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`

## Accepted Differences

- Session `1` keeps successful reaction replay rows as `stored` rather than
  deleting them. The durable owner is still truthful because later retry logic
  loads only retryable rows.
- The dedicated outbox remains feature-local and does not overload
  `group_messages` or `message_reactions` with sender-owned delivery state.

## Scope Guard

- do not add a second retry owner in this session
- do not redesign receive-side reaction handling or announcement permissions
- do not widen into UI warnings, participant inspection, or notification work
