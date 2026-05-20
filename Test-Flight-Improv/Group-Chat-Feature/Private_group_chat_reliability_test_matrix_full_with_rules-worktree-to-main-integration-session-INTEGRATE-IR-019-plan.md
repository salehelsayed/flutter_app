# INTEGRATE-IR-019 Hidden Replay Message Id Integration Contract

Status: accepted

## Historical Source

- Source row: `IR-019` / `Inbox retrieval preserves message id hidden inside encrypted envelope`.
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-019-plan.md`.
- Source closure status: accepted / closed.

This contract is for worktree-to-main import, reconciliation, and verification only. It does not recreate the original implementation plan and does not reimplement the row from scratch.

## Main Classification

Current main already has the production behavior: `decodeInboxMessage` decrypts signed replay envelopes from relay messages shaped as `from`/`message`/`timestamp`, `drainGroupOfflineInbox` reads `payload['messageId']`, and `handleIncomingGroupMessage` dedupes by that message id without overwriting an existing trusted local row.

Missing meaningful row-owned delta:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`: direct drain proof for a signed replay envelope without top-level `messageId`.
- `test/features/groups/integration/group_resume_recovery_test.dart`: helper support for omitting the envelope message id and a fake-network replay dedupe proof.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`: row inventory/count update.
- Integration breakdown ledger and verdict updates.

## Scope Guard

Import only IR-019-owned tests/docs. Do not import source production files, relay/native changes, IR-016 retention behavior, IR-017 overflow behavior, IR-018 restart freshness behavior, IR-020 deletion-policy behavior, notification routing, simulator proof, or unrelated replay rows.

## Required Verification

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-019'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-019'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'DE-004 listener-backed live plus replay dedupes while preserving replay receipts and metadata'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GP-026 same message is not duplicated if both pubsub and group inbox deliver it'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event'
flutter analyze --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

No iOS 26.2 live proof is required because the source IR-019 proof profile is host-only.

## Execution Results

- Imported only row-owned test/docs deltas. Production code stayed unchanged because current main already decrypts signed replay envelopes from relay messages shaped as `from`/`message`/`timestamp`, extracts `payload['messageId']`, and dedupes by message id.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` adds `IR-019 decrypts hidden payload message id for inbox dedupe`.
- `test/features/groups/integration/group_resume_recovery_test.dart` adds `includeEnvelopeMessageId` helper support and `IR-019 fake-network replay dedupes by decrypted payload id without outer id`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` records the two row-owned tests and count updates.

Evidence passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-019' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-019' # +1
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'DE-004 listener-backed live plus replay dedupes while preserving replay receipts and metadata' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GP-026 same message is not duplicated if both pubsub and group inbox deliver it' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event' # +1
flutter analyze --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart # No issues found
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart # 0 changed
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups # +220 -3, red only on BB-007, BB-012, GM-029
./scripts/run_test_gates.sh completeness-check # 732/733, red only on test/shared/fakes/fake_group_pubsub_network_test.dart
```

## Closure Verdict

INTEGRATE-IR-019 is accepted. No simulator or iOS 26.2 proof is required or claimed. IR-016 retention cutoff, IR-017 dispatcher overflow replay, IR-018 restart freshness, IR-020 local history deletion policy, relay architecture, notification routing, and adjacent replay rows remain out of scope.
