# INTEGRATE-DE-007 Zero-Peer Durable Replay Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-007` Zero-peer publish stores or schedules offline delivery for active members.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-007-plan.md`.
- Source status: accepted/covered with direct sender-state proof, fake-network replay proof, criteria proof, host gates, and iOS 26.2 `de007` proof. The source plan treated production behavior as already sufficient after inspection.

## Integration Scope

Import only missing row-owned proof artifacts and documentation. Current main production behavior already implements zero-peer durable inbox custody for active recipients, so no production code changed for DE-007.

In scope:
- `test/features/groups/application/send_group_message_use_case_test.dart`: DE-007 direct selector for zero live topic peers, durable recipient custody, sender `sent` status, cleared retry/wire payloads, and no recipient receipt claim.
- `test/features/groups/integration/group_resume_recovery_test.dart`: DE-007 fake-network selector proving active Bob and Charlie receive Alice's zero-peer message exactly once via durable replay.
- `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`: `de007` scenario, `de007ZeroPeerProof`, and positive/negative criteria coverage.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Production rewrites, DE-008+, timeout handling, callback routing, native dispatcher panic handling, receipt protocol generation, UI, notifications, media, source docs wholesale, COMPLETE_1 docs, and adjacent-row closure.

## Verification

Focused row checks:
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-007'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-007'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'DE-007'` passed (`+3`).

Affected preservation checks:
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'DE-006|GP-005|GP-007|GO-001|GO-002'` passed (`+6`).
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'GO-002 retry promotes pending inbox store failure to sent'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'publish with zero peers falls back to inbox|GP-007|GI-020|DE-006'` passed (`+4`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'DE-006|GE-010|GE-011'` passed (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'DE-002|DE-003|GE-010|GE-011|GO-001|GO-002|GM-035'` passed (`+20`).

Static and hygiene checks:
- `flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` passed with `No issues found!`.
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` passed with `Formatted 6 files (0 changed)`.
- Scoped `git diff --check` on DE-007 code/test/harness files passed before doc closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+201 -3` only on preserved non-DE-007 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

Live proof:
- iOS 26.2 `de007` proof passed with run id `1779140605428`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_de007_9O8Ctq`.
- Verdict: `de007 verdicts valid for alice, bob, charlie`.
- Proof facts: Alice recorded `de007ZeroPeerProof` with `sendResultSuccessNoPeers: true`, `inboxStored: true`, `publishedBeforeReceiversJoined: true`, `activeRecipientsCovered: true`, `activeRecipientCount: 2`, and message id `gmp_1779140605428_de007_aliceZeroPeer_alice`; Bob and Charlie each joined after Alice's send, received via offline replay, persisted exactly one visible row, and matched Alice's message id and sender.

## Verdict

Accepted. DE-007 imported row-owned proof artifacts only; production behavior was already present in current main.
