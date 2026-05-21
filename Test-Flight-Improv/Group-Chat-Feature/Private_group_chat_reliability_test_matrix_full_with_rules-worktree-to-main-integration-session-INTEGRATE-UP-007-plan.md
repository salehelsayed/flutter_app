# INTEGRATE-UP-007 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-007-plan.md`
- Source row: `UP-007` / No native bridge call is made while holding a DB write transaction
- Row-owned source anchor: `test/features/groups/application/group_bridge_transaction_guard_test.dart`

Imported delta:
- Production transaction-guard behavior was already present in current main through `db_write_transaction.dart`, `GoBridgeClient.send`, and `FakeBridge.send`.
- Added the missing row-owned group-flow proof that instruments group/message repository write windows and bridge command timestamps while running create, add, remove, re-add, and send flows.
- The proof asserts no `group:create`, `group:updateConfig`, `group:publish`, `group:inboxStore`, signing, encryption, invite, or other bridge command overlaps a DB write transaction window.

Out of scope:
- No original source worktree plan recreation or rerun.
- No production rewrite, source-doc rewrite, COMPLETE_1 doc update, simulator/device proof, offline cursor behavior beyond the adjacent drain selector, notification rows, media/reaction rows, security/privacy rows, Android, or physical iOS.

Verification evidence:
- `dart format test/features/groups/application/group_bridge_transaction_guard_test.dart` - pass with 0 changed.
- `dart format --set-exit-if-changed test/features/groups/application/group_bridge_transaction_guard_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/application/group_bridge_transaction_guard_test.dart --plain-name "UP-007 create add remove re-add and send keep bridge calls outside write transactions"` - pass.
- `flutter test --no-pub test/core/database/db_write_transaction_guard_test.dart` - pass.
- `flutter test --no-pub test/features/groups/application/drain_lock_window_test.dart --plain-name "no bridge.send falls inside any inbox-page transaction window"` - pass.
- `dart analyze test/features/groups/application/group_bridge_transaction_guard_test.dart test/core/database/db_write_transaction_guard_test.dart` - pass, `No issues found!`.
- `flutter analyze --no-pub test/features/groups/application/group_bridge_transaction_guard_test.dart test/core/database/db_write_transaction_guard_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` - pass before doc closure.
- No simulator/live proof was required because source `Smoke`, `Fake Network`, and `3-Party E2E` are `N/A`.

Controller status:
- The row is accepted. Row-owned group-flow proof plus adjacent core guard and drain preservation selectors passed.
- Safe next action is `INTEGRATE-UP-008` after ledger sanity, dirty-state safety checks, and fresh row-specific revalidation.
