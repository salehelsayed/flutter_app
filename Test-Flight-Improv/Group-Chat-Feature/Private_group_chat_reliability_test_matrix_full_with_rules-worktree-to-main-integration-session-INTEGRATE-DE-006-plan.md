# INTEGRATE-DE-006 TopicPeers Receipt-Distinction Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-006` Publish result `topicPeers` does not overclaim recipient receipt.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-006-plan.md`.
- Source commits: plan `6fc6c8bb7423dd30a8d64f9d03427820b6d5280a`; implementation `9e35311b151a3b70c6c99c39fad3925e71324b5f`.
- Source status: accepted/covered with host unit, fake-network, WU-3, groups, completeness, and diff evidence. No iOS 26.2 live proof was required for this row.

## Integration Scope

Import only the missing row-owned fanout evidence and proof assertions that distinguish live topic fanout from recipient delivered/read receipt evidence. Do not import source docs wholesale, regenerate the original source implementation plan, or close adjacent rows.

In scope:
- `lib/features/groups/application/send_group_message_use_case.dart`: add explicit `topicPeers` fanout classification details with `expectedRecipientCount`, `liveFanoutState`, `inboxStored`, `inboxPending`, and `recipientReceiptClaimed: false`.
- `test/features/groups/application/send_group_message_use_case_test.dart`: add DE-006 WU-3 matrix coverage for zero, partial, and full live fanout without receipt overclaiming, plus partial fanout with inbox failure.
- `test/features/groups/integration/group_messaging_smoke_test.dart`: add a fake-network proof that full live fanout remains sender-visible `sent`, not delivered.
- `test/features/groups/integration/group_resume_recovery_test.dart`: add a fake-network proof that partial live fanout does not claim offline-recipient receipt before durable inbox replay.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and this integration breakdown: record row-owned coverage and closure evidence.

Out of scope:
- `DE-007`, `DE-008`, receipt protocol generation, delivered/read receipt semantics, UI, notifications, Go/native dispatcher behavior, relay behavior, criteria/live-harness changes, source worktree docs, COMPLETE_1 docs, and broad gate residual repairs.

## Verification

Focused row checks:
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-006'` passed (`+2`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-006'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'DE-006'` passed (`+1`).

Affected preservation checks:
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'WU-3'` passed (`+29`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'publish with zero peers falls back to inbox|partial delivery with inbox drain completion'` passed (`+2`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'GE-010|GE-011'` passed (`+2`).
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'GO-002'` passed (`+1`).

Static and hygiene checks:
- `dart analyze lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with `No issues found!`.
- `dart format --set-exit-if-changed lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with `0 changed`.
- Scoped `git diff --check` on the four DE-006 Dart files passed before doc closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+200 -3` only on preserved non-DE-006 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-006 is host/fake-network proof only; no iOS 26.2 simulator/live proof was required or run.
