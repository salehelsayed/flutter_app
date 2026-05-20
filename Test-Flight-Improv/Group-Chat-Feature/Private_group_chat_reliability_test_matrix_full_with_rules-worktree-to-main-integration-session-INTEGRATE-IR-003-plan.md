# INTEGRATE-IR-003 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile only the row-owned IR-003 worktree delta for timestamp-based group inbox retrieval boundary safety. Do not regenerate the original implementation plan and do not broaden into cursor pagination, failed retrieve rollback, history repair, relay ACL, UI, notification, or live-device proof work.

## Source Of Truth

- Source row: `IR-003 | Timestamp-based retrieval has no boundary skips or duplicates`
- Source plan: `worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-003-plan.md`
- Source verdict: accepted / covered

## Imported Delta

- `go-mknoon/node/group_inbox.go`: direct legacy `GroupInboxRetrieve` now sends `sinceTimestamp - 1` for positive timestamp boundaries via the already-present inclusive helper.
- `go-mknoon/node/group_inbox_test.go`: reconciled the existing GI-009 request-shape expectation to the inclusive boundary and added `TestIR003GroupInboxRetrieveUsesInclusiveSinceBoundary`.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`: added `IR-003 timestamp high-water replay includes boundary messages and dedupes ids`.
- `test/features/groups/integration/group_resume_recovery_test.dart`: added `IR-003 timestamp replay boundary drains same-ms fake-network messages once`.

## Already Present / Skipped

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` already stores synthetic timestamp cursors using `maxTimestampMs - 1`; no production Dart change was imported.
- `GroupInboxRetrieveWithCursorResult` already routes synthetic since cursors through the inclusive timestamp helper; existing ST-004/synthetic-cursor selectors were preserved.
- Relay `RetrieveSince` strict lower-bound behavior was not changed.

## Verification

- `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestIR003GroupInboxRetrieveUsesInclusiveSinceBoundary|TestGroupInboxRetrieveWithCursorResult_SyntheticSinceCursorUsesTimestampRetrieve|TestGI009GroupInboxRetrieveSendsSinceTimestampRequestShape' -count=1`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-003'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-003'`
- Native/relay preservation, app/fake-network preservation selectors, scoped analyzer, baseline gate, named `groups` gate residual classification, completeness residual classification, and `git diff --check` recorded in the integration breakdown.

## Live Proof

No iOS 26.2 live proof was required. Source `3-Party E2E` is `N/A`, and no `ir003` live harness scenario exists.
