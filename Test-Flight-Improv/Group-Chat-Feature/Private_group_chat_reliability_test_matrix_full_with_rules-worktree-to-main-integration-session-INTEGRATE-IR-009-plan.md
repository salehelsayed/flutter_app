# INTEGRATE-IR-009 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-009` / `Replay item is not acknowledged before local persistence succeeds`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-009-plan.md`.
- Source closure state: covered/accepted with direct drain and fake-network proofs.
- Source proof profile: host-only. Unit, Integration, and Fake Network are required; Smoke is recommended; `3-Party E2E` is `N/A`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-009 imports only missing row-owned proof artifacts for local replay persistence failure before cursor, receipt, or read-ack commitment:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Added `IR-009 persistence failure retries same page before cursor or ack commit`.
  - The fixture is reconciled to current main's replay-local-membership precondition by seeding the local member inside the row-owned test.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Added `IR-009 failed replay persistence retries same cursor and stores missed fake-network message once`.

Production code stayed untouched because current main already processes replay messages before the Phase 2 cursor/receipt transaction and propagates local save failures before cursor/ack commit.

Out of scope: retrieve-call failures (`IR-008`), history-gap parsing/repair (`IR-010`/`IR-012`), relay ACLs, media, UI, notification, criteria/live harnesses, iOS 26.2 proof, and adjacent replay rows.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-009 persistence failure retries same page before cursor or ack commit'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-009 failed replay persistence retries same cursor and stores missed fake-network message once'
flutter analyze --no-pub lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'PREREQ-GROUP-SYNC-RECEIPTS failed page commit|PREREQ-GROUP-SYNC-RECEIPTS listener replay failure|PREREQ-GROUP-SYNC-RECEIPTS system replay failure|BB-013 group:inboxRetrieve timeout|IR-002 cursor drain resumes|IR-003 timestamp high-water|GO-008 cursor error flow logs|IR-008 retrieve failure'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-004 live plus inbox replay duplicate|IR-003 timestamp replay boundary|temporary partition replays missed backlog|GR-015 relay reconnect|IR-008 failed inbox retrieve'
git diff --check
```

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +212 -3, red only on preserved non-IR-009 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

No iOS 26.2 simulator/live proof was run or required because source `3-Party E2E` is `N/A`.

## Closure Verdict

`INTEGRATE-IR-009` is accepted. Main now has the row-owned direct and fake-network proofs that failed local replay persistence leaves message rows, durable cursor, delivered/read receipts, and read-state ack uncommitted, then retries the same cursor/page and persists the missed message exactly once before committing ack/cursor state.
