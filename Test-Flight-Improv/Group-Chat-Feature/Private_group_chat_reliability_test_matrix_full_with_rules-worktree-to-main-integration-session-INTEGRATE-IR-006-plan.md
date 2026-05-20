# INTEGRATE-IR-006 Active Recipient Inbox Store Integration Contract

Status: accepted

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-006-plan.md`
- Source row: `IR-006` / `Group inbox store targets exact active recipients at send time`
- Source closure verdict: `closed` / `accepted`
- Source evidence recorded focused direct selector `+1`, focused fake-network selector `+1`, scoped analyzer clean, host `groups` `+153`, `completeness-check` `732/732`, and `git diff --check`.

## Integration Scope

This is a standard worktree-to-main import/reconcile/verify contract, not a new implementation rollout.

Current main already has the meaningful production behavior: `send_group_message_use_case.dart` computes `recipientPeerIds` from the send-time membership snapshot, applies the existing membership cutoff, requires deliverable member identity, excludes the sender, and dedupes recipients. The source worktree production delta was simpler than current main and was not imported.

Imported only the missing row-owned proof artifacts:

- Added `IR-006 group inbox store targets exact active recipients at send time` to `test/features/groups/application/send_group_message_use_case_test.dart`.
- Renamed/extended the existing KE-021 fake-network proof to `IR-006 KE-021 removed member is not targeted by future fake-network key or inbox payloads` in `test/features/groups/integration/group_messaging_smoke_test.dart`.
- Updated `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Updated the active worktree-to-main integration breakdown ledger.

Out of scope: source matrix rewrite, source session breakdown rewrite, production recipient-helper replacement, IR-007 retry ownership, IR-008/IR-009 ack/cursor rollback, relay-side ACL enforcement, media `allowedPeers`, criteria/live harnesses, iOS/live proof, UI, notification, Android, physical iOS, and adjacent replay-row closure.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'IR-006'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'IR-006'
flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-004'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-007'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'KE-021'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-021'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-019'
```

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-006 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

iOS 26.2 live proof is not required for IR-006 because the source row marks 3-party E2E as `N/A`.

## Verdict

`INTEGRATE-IR-006` is accepted. Production behavior stayed untouched because current main already has equal or stronger send-time active-recipient computation. The row-owned direct and fake-network proof artifacts are now present in main, focused and affected preservation checks pass, and residual named-gate failures are preserved outside IR-006.
