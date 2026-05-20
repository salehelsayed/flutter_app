# INTEGRATE-DE-014 Decryption Failure Repair Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-014` Decryption failure is diagnostic and recoverable, not a silent drop.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-014-plan.md`.
- Source status: accepted/covered with live decryption-failure placeholder evidence, durable replay pending-key repair evidence, later live-delivery preservation, and host-only proof classification.

## Integration Scope

Imported only the missing row-owned harness/test proof artifacts. Current main already had the production live and durable pending-key repair behavior from earlier key-repair work, but the exact DE-014 selectors and fake-user pending-repair injection hook were missing.

In scope:
- `test/shared/fakes/group_test_user.dart`: add optional `pendingKeyRepairRepo` injection into `GroupMessageListener` for row-owned fake-network repair proofs.
- `test/features/groups/application/group_message_listener_test.dart`: add the DE-014 live decryption-failure placeholder plus later valid event proof.
- `test/features/groups/integration/group_resume_recovery_test.dart`: add a local in-memory pending-key repair repository helper and the DE-014 durable replay repair plus later fake-network delivery proof.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Production decryption/repair behavior changes, DE-015 payload parse diagnostics, DE-016 validation diagnostics, DE-017 membership/content ordering, DE-019 EventChannel recovery, DE-020 starvation, source docs wholesale, COMPLETE_1 docs, native/bridge changes, unrelated fake-network helper expansion, criteria/live-harness changes, simulator/device proof, 3-party E2E, UI, notification, media, relay durability, and unrelated adjacent-row tests.

## Verification

Focused row checks:
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-014'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-014'` passed (`+1`).

Affected preservation checks:
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GO-004'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'` passed (`+1`).

Static and hygiene checks:
- `dart format test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` completed (`0 changed` after patch formatting).
- `flutter analyze --no-pub test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`No issues found!`).
- Scoped `git diff --check` passed before ledger closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+205 -3` only on preserved non-DE-014 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-014 required host Flutter listener and fake-network durable-repair proof only; no iOS 26.2 simulator/live proof was required or run.
