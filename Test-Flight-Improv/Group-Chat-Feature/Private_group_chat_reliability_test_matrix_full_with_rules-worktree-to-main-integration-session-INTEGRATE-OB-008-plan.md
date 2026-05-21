# INTEGRATE-OB-008 Retry Ownership Integration Contract

Status: accepted

## Source Of Truth
- Source row: `OB-008` / "Retry job ownership is unambiguous for each degraded branch".
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-008-plan.md`.
- Source closure status: accepted/covered as tests-only; no production, harness, fixture, criteria, script, or live-device changes were row-owned.

## Integration Scope
Import only the missing row-owned proof selectors for retry-owner disambiguation:

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Production retry-owner behavior in `send_group_message_use_case.dart`, `retry_failed_group_messages_use_case.dart`, and `retry_failed_group_inbox_stores_use_case.dart` was already present in current main and was not modified.

Out of scope: retry scheduling policy, UI retry controls, persisted retry-owner enums, media upload retry ownership, malformed event diagnostics (`OB-009`/`OB-010`), telemetry breadth (`OB-011`), stress rows, source matrix rewrites, COMPLETE_1 docs, and simulator/device proof.

## Imported Delta
- `OB-008 degraded send branches map to one retry owner` proves publish-success/inbox-fail maps only to failed-inbox-store retry; publish-fail/inbox-fail, publish-fail/inbox-ok, and zero-peer/inbox-fail map only to failed-message retry; timeout with durable inbox custody maps to no retry owner; and failed-message versus failed-inbox-store selector sets are disjoint.
- `OB-008 fake-network degraded branches use only their retry owner` proves the wrong retry owner returns zero, the correct owner recovers the row in place, and recipient delivery remains exactly once.

## Verification
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "OB-008"` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "OB-008"` (`+1`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'IR-007|GO-002|GI-006|DE-008|publish fail \+ inbox fail|0-peer \+ inbox fail|missing topicPeers \+ inbox fail'` (`+9`)
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --name 'DE-008|retries a zero-peer plus inbox-fail row'` (`+2`)
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --name 'IR-007|GO-002|handles callGroupInboxStore failure gracefully|deterministic restart retry'` (`+4`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'IR-007|UP-008|DE-008 publish failure branch retries over fake network'` (`+3`)
- `flutter analyze --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` (`No issues found!`)
- `git diff --check`

One optional broad retry-message preservation bundle failed only on the standalone pre-existing selector `continues after a per-message publish error`, which reproduces alone in untouched `retry_failed_group_messages_use_case_test.dart` and is outside OB-008.

## Device Proof
No simulator or live-device proof was required or claimed. Source 3-Party E2E is `N/A`, so the iOS 26.2-only device rule was not invoked.

## Closure Verdict
Accepted for `INTEGRATE-OB-008`. The integration imported only two row-owned tests and documentation updates, preserved current-main production behavior, and left unrelated `info.plist` and known blockers untouched.
