# 63 Session 1 Plan: Define Group Backlog Retention Contract

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- define one explicit repo-owned retention contract for relay-backed group
  backlog, including the concrete supported window and the persisted
  group-owned state later sessions will read
- add one small domain policy seam that names the retention window in code so
  later sessions do not re-derive or silently fork it
- add the minimum additive group-storage fields needed to record that a
  retention boundary was encountered without widening into replay or UI logic
- map the new retention fields through `GroupModel`, DB helpers, repository
  loading, and the database create/upgrade chain
- add direct migration, model, repository, and full migration-chain proof for
  the new retention contract

Out of scope for this session:

- filtering replayed messages during inbox drain
- notification, unread, or duplicate-handling behavior changes
- any group conversation, group list, or push-open UX
- matrix or architecture-doc closure work

### Closure bar

Session `1` is done only when:

- the repo names one concrete retention window for group backlog instead of
  leaving it contract-undefined
- the local schema can persist the minimum backlog-gap state required by later
  sessions
- `GroupModel` and `GroupRepositoryImpl` round-trip that state without changing
  existing non-retention group behavior
- fresh installs and upgrades land on the same schema through `lib/main.dart`
- direct tests prove the migration path and repository/model mapping

### Source of truth

- active session contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/63-group-message-retention-boundary.md`
- regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate contract:
  `Test-Flight-Improv/test-gate-definitions.md`
- current group schema owner:
  `lib/core/database/migrations/017_groups_tables.dart`
- DB lifecycle owner:
  `lib/main.dart`
- current group model/repository seams:
  `lib/features/groups/domain/models/group_model.dart`
  `lib/features/groups/domain/repositories/group_repository_impl.dart`

On disagreement, current code/tests beat stale prose.

### Session classification

- `implementation-ready`

### Exact problem statement

`UX-008` is still open because the repo has replay support but no explicit,
durable retention contract for long-offline group backlog. Later sessions
cannot truthfully filter expired backlog or explain it in the UI until the app
first owns a concrete retention rule and a stable persisted way to record that
the boundary was hit.

### Files and repos to inspect next

Production and storage files:

- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- `lib/core/database/helpers/groups_db_helpers.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/main.dart`

Reference migration/test patterns:

- `lib/core/database/migrations/050_groups_mute_column.dart`
- `lib/core/database/migrations/052_groups_dissolve_columns.dart`
- `test/core/database/migrations/050_groups_mute_column_test.dart`
- `test/core/database/migrations/052_groups_dissolve_columns_test.dart`

Direct tests:

- `test/features/groups/domain/models/group_model_test.dart`
- `test/features/groups/domain/models/group_backlog_retention_policy_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

### Existing tests covering this area

- `test/features/groups/domain/models/group_model_test.dart` already proves
  map/round-trip behavior for muted and dissolved group fields, so it is the
  right seam for new retention-field coverage
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  already exercises group persistence across the in-memory SQLite repo wiring
- `test/core/database/integration/full_migration_chain_test.dart` already
  proves fresh-install and upgrade parity through the current `052` chain
- `test/core/database/migrations/050_groups_mute_column_test.dart` and
  `test/core/database/migrations/052_groups_dissolve_columns_test.dart` show
  the expected additive migration-test pattern for group columns

Missing today:

- no named group backlog retention policy constant or helper in the domain seam
- no migration test for group backlog-retention columns
- no model/repository proof for retention-boundary state
- no full-chain assertion that future installs/upgrades include the new fields

### Regression/tests to add first

- add `test/core/database/migrations/053_groups_backlog_retention_columns_test.dart`
  first so the new upgrade migration is proven before the model layer changes
- add `test/features/groups/domain/models/group_backlog_retention_policy_test.dart`
  first so the chosen retention window is explicit and pinned before later
  sessions depend on it
- extend `test/features/groups/domain/models/group_model_test.dart` with a
  round-trip case for the new retention fields before wiring `GroupModel`
- extend `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  with a persistence round-trip for the same fields before broader runtime work
- extend `test/core/database/integration/full_migration_chain_test.dart` once
  the migration exists so fresh-install and upgrade parity stay locked

### Step-by-step implementation plan

1. Add a small domain policy file that names the concrete repo-owned retention
   window and pin it with a direct unit test.
2. Add the next additive groups migration
   (`053_groups_backlog_retention_columns.dart`) plus matching fresh-install
   schema updates in `017_groups_tables.dart`.
3. Wire the new migration into `lib/main.dart` so `onCreate`, `onUpgrade`, and
   the current database version stay aligned.
4. Extend `GroupModel.fromMap`, `toMap`, and `copyWith` with the new retention
   fields, then thread them through `GroupRepositoryImpl`’s existing group
   load/save/update path.
5. Add or extend the direct migration, model, repository, and full-chain tests
   listed above.
6. Run the direct tests first; only after they are green, run the required
   named gates for changed Flutter/group code.
7. Stop and tighten the plan instead of widening scope if the implementation
   starts needing replay filtering, UI copy, or matrix/doc updates.

### Risks and edge cases

- keep the migration additive and idempotent; do not rebuild the `groups` table
  or change unrelated existing group columns
- do not overload invite expiry or dissolve semantics; backlog-retention state
  is a separate contract
- preserve non-retention active-group behavior, ordering, and active-group
  queries in this session
- avoid picking retention fields that later sessions cannot interpret
  truthfully for mixed-window recovery

### Exact tests and gates to run

Direct tests:

- `flutter test test/core/database/migrations/053_groups_backlog_retention_columns_test.dart`
- `flutter test test/features/groups/domain/models/group_backlog_retention_policy_test.dart`
- `flutter test test/features/groups/domain/models/group_model_test.dart`
- `flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `flutter test test/core/database/integration/full_migration_chain_test.dart`

Named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- if `baseline` still fails in the existing share/loading harness outside the
  session write scope, record that as unchanged pre-existing noise only with the
  exact failing file and message
- any new failure in the direct migration/model/repository suites is a session
  blocker
- any `groups` gate failure touching the newly added retention fields, group
  schema loading, or compile-shape fallout is a session regression and must be
  fixed here

### Done criteria

- one concrete group backlog retention window is encoded in the repo
- the minimum durable retention-boundary state is stored and round-trips
  cleanly
- the new schema lands on both fresh installs and upgrades
- the direct tests above pass
- required named gates are run and any unchanged known failures are recorded
- Session `2` can depend on stable persisted retention facts rather than ad hoc
  in-memory state

### Scope guard

- do not filter inbox replay in this session
- do not touch `drain_group_offline_inbox_use_case.dart`,
  `group_message_listener.dart`, or UI files except for compile-shape fallout
  from the new storage contract
- do not add user-facing copy, placeholders, or matrix/audit doc updates
- do not broaden into relay-server pruning or out-of-tree infra work

### Accepted differences / intentionally out of scope

- this session does not prove upstream relay pruning; it only establishes the
  app-owned retention contract and persisted state the repo can enforce later
- exact expired-backlog copy and mixed-window UX remain Session `3` work
- final `UX-008` closure remains Session `4` work

### Dependency impact

- Session `2` depends on this plan landing stable retention fields and one
  explicit retention window
- Session `3` should not ship copy until Session `2` proves the retained versus
  expired replay behavior
- Session `4` should be skipped or refreshed if this session lands a smaller
  storage contract than planned

## Structural blockers remaining

- `none`

## Incremental details intentionally deferred

- final naming of the user-facing copy for expired backlog
- whether later sessions surface the boundary in the conversation screen, group
  list, or both

## Accepted differences intentionally left unchanged

- no server-side pruning work in this session
- no replay filtering or UI behavior in this session

## Exact docs/files used as evidence

- `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- `Test-Flight-Improv/63-group-message-retention-boundary.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- `lib/core/database/helpers/groups_db_helpers.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/main.dart`
- `test/core/database/migrations/050_groups_mute_column_test.dart`
- `test/core/database/migrations/052_groups_dissolve_columns_test.dart`
- `test/features/groups/domain/models/group_backlog_retention_policy_test.dart`
- `test/features/groups/domain/models/group_model_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now because it stays inside one coherent seam:
group storage contract plus the tests that prove that contract. It does not ask
Session `1` to solve replay behavior or UI truth, but it leaves later sessions
with a durable, explicit retention boundary they can enforce and present
without inventing new persistence rules mid-rollout.
