# INTEGRATE-DE-008 Publish Timeout Retry-Ownership Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-008` Publish timeout does not create a permanently invisible pending message.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-008-plan.md`.
- Source status: accepted/covered with direct send, failed-message retry, fake-network retry, host gates, completeness, and diff evidence. The source plan classified DE-008 as tests/docs-only; production behavior was already sufficient.

## Integration Scope

Import only missing row-owned proof artifacts and documentation. Current main production behavior already maps `BRIDGE_TIMEOUT` plus durable inbox custody to visible `sent` success and maps timeout without custody to visible failed-message retry ownership, so production code stayed untouched.

In scope:
- `test/features/groups/application/send_group_message_use_case_test.dart`: row-name and strengthen durable-timeout visibility, and add no-custody timeout failed-row ownership proof.
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`: add DE-008 timeout-owned failed-row retry proof and reconcile same-file preservation fixtures with current sender-membership authorization.
- `test/features/groups/integration/group_resume_recovery_test.dart`: add a test-local publish-timeout bridge knob and fake-network DE-008 retry proof.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Production behavior rewrites, DE-009+, callback routing, native dispatcher panic handling, receipt protocol generation, UI, notifications, media, Go/relay behavior, criteria/live-harness scripts, source docs wholesale, COMPLETE_1 docs, simulator/device proof, and 3-party E2E.

## Verification

Focused row checks:
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-008'` passed (`+2`).
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name 'DE-008'` passed (`+1`) after seeding the current-main sender/recipient membership fixture.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-008'` passed (`+1`).

Affected preservation checks:
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'pre-persist:|GO-002 publish success|DE-006 topicPeers|DE-007 zero-peer|BB-013 group:publish timeout|publish timeout'` passed (`+9`).
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --name 'DE-008|retries a failed text row even when inboxRetryPayload was cleared after inbox success|retries a zero-peer plus inbox-fail row through the failed-message retry owner'` passed (`+3`) after reconciling the two preservation fixtures with sender/recipient membership.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'GO-002 retry promotes pending inbox store failure to sent'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-008|DE-005 sender self echo|zero-peer inbox failure stays owned|DE-006 partial live fanout|GP-007|publish with zero peers falls back to inbox'` passed (`+6`).

Static and hygiene checks:
- `flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/retry_failed_group_messages_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with `No issues found!`.
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed.
- Scoped `git diff --check` on the DE-008 test files passed before doc closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+202 -3` only on preserved non-DE-008 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-008 is host/fake-network proof only; no iOS 26.2 simulator/live proof was required or run.
