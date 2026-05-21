# INTEGRATE-ST-004 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-004`: "Clock skew and timestamp fuzz for replay boundaries."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-004-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "ST-004 clock skew keeps cursor exact and timestamp fallback inclusive"`
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "ST-004 clock skew fake-network replay keeps relay boundary exact"`
  - `cd go-mknoon && go test ./node -run TestST004 -count=1`
- Source 3-party E2E: `N/A`.

## Imported Delta

- Imported the missing row-owned direct Dart replay-boundary selector in `drain_group_offline_inbox_use_case_test.dart`.
- Imported the missing row-owned fake-network replay-boundary selector in `group_resume_recovery_test.dart`.
- Production `drain_group_offline_inbox_use_case.dart` already matched the source row's relay-timestamp high-water behavior in current main, and native `TestST004` was already present, so no production or Go test delta was imported.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "ST-004 clock skew keeps cursor exact and timestamp fallback inclusive"`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "ST-004 clock skew fake-network replay keeps relay boundary exact"`
- `cd go-mknoon && go test ./node -run TestST004 -count=1`
- `flutter analyze --no-pub lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- `gofmt -l go-mknoon/node/group_inbox_test.go`

No iOS simulator/live proof was required because the source row is host/native/fake-network only.

## Verdict

`accepted`

ST-004 is imported and verified. The integration stayed limited to row-owned replay-boundary proof selectors and documentation ledger updates. Existing blocked rows remain unchanged.
