# INTEGRATE-UP-008 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-008-plan.md`
- Source row: `UP-008` / Pending outbound group message survives restart and reconciles
- Row-owned source anchors:
  - `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
  - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`

Imported delta:
- Production send/retry/resume behavior was already present in current main and stayed unchanged.
- Added the row-owned file-backed DB proof that an outgoing `pending` row with `wire_envelope` and `inbox_retry_payload` survives close/reopen and remains eligible for inbox-store retry.
- Added the row-owned retry-owner proof that a fresh post-restart bridge retries the same pending row once, promotes it to `sent`, clears retry material, creates no duplicate row, and is idempotent.
- Added the row-owned fake-network resume proof that app-restart-style recovery closes Alice's pending row in place, Bob keeps one live copy, Carol drains one replayed copy, and no pending/failed duplicate remains.

Out of scope:
- No original source worktree plan recreation or rerun.
- No production rewrite, source-doc rewrite, COMPLETE_1 doc update, simulator/device proof, notification rows, media/reaction rows, share-target rows, adjacent UP rows, Android, or physical iOS.

Verification evidence:
- `dart format test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` - pass after formatting changed only the DB helper test.
- `dart format --set-exit-if-changed test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "UP-008 pending outbound retry row survives database restart and stays eligible"` - pass.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "UP-008 restart retry promotes pending outbound row without duplicate rows"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "UP-008 pending outbound group message survives restart and reconciles through inbox retry"` - pass.
- `flutter analyze --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` - pass before doc closure.
- No simulator/live proof was required because source `3-Party E2E` is `N/A`.

Controller status:
- The row is accepted. DB persistence, retry-owner, fake-network resume, format, analyzer, and diff evidence passed.
- Safe next action is `INTEGRATE-UP-009` after ledger sanity, dirty-state safety checks, and fresh row-specific revalidation.
