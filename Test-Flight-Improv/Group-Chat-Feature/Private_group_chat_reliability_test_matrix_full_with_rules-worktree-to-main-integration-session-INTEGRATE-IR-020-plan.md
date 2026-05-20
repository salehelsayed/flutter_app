# INTEGRATE-IR-020 - Local Delete Tombstone Import Contract

Status: accepted

Accepted: 2026-05-19 10:25 CEST

## Row Contract

Import and verify only the row-owned IR-020 delta from the historical worktree:
locally deleted group messages must not be resurrected by inbox replay or
history repair, and must not become unread again.

This is integration/reconciliation work, not a fresh implementation rollout.
The historical source plan and closure evidence are the source of truth:

- Source plan: `../worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-020-plan.md`
- Source status: accepted
- Source proof profile: Unit, Integration, Fake Network
- Simulator/device proof: not required for this row

## Controller Classification

Classification: partial.

Main already has adjacent duplicate replay, deleted-group, and removed-member
replay protections, but it does not have the durable per-message local deletion
tombstone table/helper, save skip, delete recording, in-memory fake behavior, or
IR-020 focused tests.

## Conflict Resolution

The source worktree wired IR-020 after a source-side `068_group_key_rotation_drafts`
migration. Main already owns `068_removed_group_member_snapshots`.

Integration rule for this row:

- Do not import source `068_group_key_rotation_drafts`.
- Preserve main's `068_removed_group_member_snapshots` migration and wiring.
- Add IR-020 as main's next migration, `069_group_message_local_deletions`.
- Merge full migration chain coverage by running main's `068` before IR-020
  `069`.

## Intended Row-Owned Files

- `lib/core/database/migrations/069_group_message_local_deletions.dart`
- `lib/core/database/helpers/group_message_local_deletions_db_helpers.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/main.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/core/database/migrations/069_group_message_local_deletions_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Required Verification

Focused row tests:

- `flutter test --no-pub test/core/database/migrations/069_group_message_local_deletions_test.dart --plain-name 'IR-020'`
- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-020'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-020'`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`

Preservation/focused gates:

- IR-019 direct and fake-network replay dedupe selectors
- DE-004 direct and fake-network replay dedupe selectors
- GP-026 fake-network duplicate delivery selector
- GI-034 direct duplicate notification/unread selector
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- Scoped format/analyze and `git diff --check`

## Guardrails

- Do not duplicate existing adjacent replay tests.
- Do not broaden into relay retention, remote delete-for-everyone, media,
  reactions, or unread UX outside locally deleted ids.
- Stop before later rows unless IR-020 ends as accepted, skipped already
  present, blocked conflict, or blocked external fixture.

## Acceptance Evidence

- Imported migration `069_group_message_local_deletions` after main's existing
  `068_removed_group_member_snapshots` migration; source-side
  `068_group_key_rotation_drafts` was not imported.
- Added durable local-deletion helpers, delete tombstone recording, replay save
  skip behavior, and in-memory fake repository parity.
- Added row-owned migration, repository, direct drain/history repair, and
  fake-network replay tests.
- Updated full migration chain coverage and test inventory counts.

Passing checks:

- `dart format --set-exit-if-changed ...` passed with `0 changed`.
- `flutter test --no-pub test/core/database/migrations/069_group_message_local_deletions_test.dart --plain-name 'IR-020'` passed (`+2`).
- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-020'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-020'` passed (`+1`).
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart` passed (`+7`).
- IR-019, DE-004, GP-026, GI-034, repeated-drain, local-delete listener, and
  remote `group_message_deleted` preservation selectors passed.
- Scoped `flutter analyze --no-pub ...` passed with `No issues found!`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at
  `+221 -3` only on preserved non-IR-020 residuals `BB-007`, `BB-012`, and
  `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated
  `test/shared/fakes/fake_group_pubsub_network_test.dart` classification
  (`733/734`).
- `git diff --check` passed.

Residual classification:

- `drain_followup_invariants_test.dart --plain-name 'mid-page sys-removal
  cleans up earlier-persisted messages'` remains red in unchanged
  listener/drain retained-history behavior: the flow emits
  `GROUP_MESSAGE_LISTENER_SELF_REMOVED_HISTORY_RETAINED` while the selector
  expects delete-group cleanup. This is outside IR-020's local per-message
  deletion contract and was not rewritten.
