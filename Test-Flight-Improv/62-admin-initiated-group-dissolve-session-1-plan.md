# 62 Session 1 Plan: Persist Dissolved-Group State

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add durable dissolve fields to the `groups` table and keep fresh-install plus
  upgrade paths in sync
- map the new fields through `GroupModel`, DB helpers, and repository loading
  so later sessions can treat dissolved groups as first-class stored state
- add direct migration, model, repository, and full migration-chain regressions

Out of scope for this session:

- publishing or receiving `group_dissolved` system messages
- any UI affordance for dissolve or visible read-only state
- send blocking, rejoin skipping, or maintained-doc cleanup

### Closure bar

Session `1` is done only when:

- the local schema can persist `is_dissolved`, `dissolved_at`, and
  `dissolved_by`
- `GroupModel` can round-trip those fields without changing existing
  non-dissolved behavior
- fresh installs and upgrades land on the same schema through
  `lib/main.dart`
- direct tests prove both the migration path and repository/model mapping

### Source of truth

- active session contract:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- DB initialization owner:
  `lib/main.dart`
- current group storage seam:
  `lib/core/database/migrations/017_groups_tables.dart`
- current repo mapping seam:
  `lib/features/groups/domain/models/group_model.dart`

### Exact problem statement

The repo has no durable group-wide dissolve state. Before network propagation
or UI can be truthful, the local database and model layer need an explicit
read-only dissolved contract that survives restart and upgrade.

### Files and repos to inspect next

Production and storage files:

- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/database/migrations/050_groups_mute_column.dart`
- `lib/core/database/helpers/groups_db_helpers.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/main.dart`

Direct tests:

- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/groups/domain/models/group_model_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`

### Step-by-step implementation plan

1. Add the dissolve columns to fresh-install group schema and create the next
   sequential guarded migration for upgrades.
2. Bump the database version, wire the migration in `onCreate`, and add the
   matching `oldVersion < N` branch in `onUpgrade`.
3. Extend `GroupModel.fromMap`, `toMap`, and `copyWith` with the new dissolve
   fields.
4. Add migration, model, repository, and full migration-chain regressions that
   prove the fields persist and read back correctly.

### Risks and edge cases

- keep the migration additive and idempotent; do not rebuild the groups table
  unnecessarily
- do not overload existing archive fields; dissolve must remain distinct from
  archive and personal leave behavior
- preserve current ordering and active-group query behavior for non-dissolved
  groups in this session

### Exact tests and gates to run

Direct tests:

- `flutter test test/core/database/migrations/052_groups_dissolve_columns_test.dart`
- `flutter test test/features/groups/domain/models/group_model_test.dart`
- `flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `flutter test test/core/database/integration/full_migration_chain_test.dart`

### Done criteria

- dissolve state is durably persisted and readable after restart/upgrade
- session `2` can depend on stable persisted dissolve facts instead of ad hoc
  in-memory flags

### Scope guard

- do not implement publish/listener/UI behavior in this session
- do not update maintained audit or matrix docs until later sessions land
