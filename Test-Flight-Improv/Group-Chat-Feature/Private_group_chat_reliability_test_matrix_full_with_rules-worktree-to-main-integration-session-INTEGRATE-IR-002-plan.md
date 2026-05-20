# INTEGRATE-IR-002 Minimal Integration Contract

## Status

accepted

## Historical Source Of Truth

- Worktree row plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-002-plan.md`
- Source row: `IR-002 Cursor-based retrieval is exactly-once across pages`
- Source closure verdict: accepted, host proof only; `3-Party E2E` was `N/A`

## Integration Scope

Import only missing row-owned IR-002 proof artifacts into the current main checkout:

- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- this integration breakdown ledger

Production code stayed untouched. Current main already has the durable cursor/page-drain behavior through the existing bridge and drain implementation, and COMPLETE_1 already has broader GI-017 cursor paging coverage. The missing IR-002 delta was the exact row-owned bridge metadata parser proof plus restart-between-pages durable cursor drain proof.

## Verification Contract

- Run focused IR-002 bridge and drain selectors.
- Run adjacent cursor/history preservation selectors and affected fake-network resume recovery checks.
- Run scoped analyzer/format/diff hygiene.
- Run named host gates and record preserved residuals.
- No iOS 26.2 live proof is required for IR-002 because the source row classifies `3-Party E2E` as `N/A`.

## Final Execution Verdict

Accepted on 2026-05-19. Imported only the two missing row-owned tests. `bridge_group_helpers_test.dart` now proves `GroupInboxPage` cursor, message, request limit, and history-gap metadata parsing. `drain_group_offline_inbox_use_case_test.dart` now proves page-1-only drain persists a durable cursor, a fresh bridge after restart resumes at that cursor, remaining pages drain exactly once, the final cursor advances to the synthetic since cursor, and a post-complete redrain creates no duplicates. The imported drain fixture was reconciled to current main by adding the local member precondition needed by the current handler.

Verification passed:

- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'IR-002'` (`+1`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-002'` (`+1`)
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'parses valid history gap metadata from cursor response'` (`+1`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'temporary partition replays missed backlog in cursor order and resumes live delivery after heal'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'GR-015|GR-016'` (`+2`)
- `flutter analyze --no-pub test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (`No issues found!`)
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+209 -3` only on preserved `BB-007`, `BB-012`, and `GM-029`
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`)
- `git diff --check` PASS

The affected COMPLETE_1 GI-017 selector was also sampled and remains red in current main with `Expected: <120> / Actual: <0>` at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:9694`. That selector belongs to existing COMPLETE_1 coverage, not the IR-002 source row import, and was not rewritten under this row.
