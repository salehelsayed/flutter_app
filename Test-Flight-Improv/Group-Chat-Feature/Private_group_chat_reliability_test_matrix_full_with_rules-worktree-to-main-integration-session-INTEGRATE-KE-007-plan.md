# INTEGRATE-KE-007 Integration Contract - First Post-Rotation Key Availability

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-007`
- Integration session: `INTEGRATE-KE-007`
- Title: `Active members receive new key before the first message requiring it`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-007-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

After removal-driven key rotation, the first message encrypted at the rotated epoch must not permanently gap a remaining active member:

- Normal path: Alice waits for Bob's rotated key before the first post-removal send.
- Delayed-key path: if Bob's rotated key update is delayed past the rotation timeout and Alice sends at the rotated epoch, Bob requests key repair and retries when the delayed key arrives.

## Source-Owned Historical Deltas

The accepted worktree plan lists these row-owned proof files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

The source fake-network proof uses `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` and expects the live receive path to emit `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` for a received group message whose epoch is higher than the local key epoch.

## Target Reconciliation

KE-017 is now accepted in main, so the original conflict blocker is stale. Current main contains the higher-epoch receive repair contract KE-007 needs:

- `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` is defined in `lib/features/groups/application/group_pending_key_repair_service.dart`.
- `group_message_listener.dart` emits `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` and calls the received-message key-repair path when a normal received message is ahead of local key state.
- KE-017 focused host/fake-network coverage is accepted in main.

This pass imported only missing KE-007 row-owned proof artifacts:

- `test/features/groups/integration/group_messaging_smoke_test.dart` adds `KE-007 delayed rotated key triggers repair before retrying first post-rotation message`.
- `integration_test/group_multi_party_device_real_harness.dart` emits `ke007FirstPostRotationProof` on `private_online_remove`.
- `integration_test/scripts/group_multi_party_device_criteria.dart` validates `ke007FirstPostRotationProof`.
- `test/integration/group_multi_party_device_criteria_test.dart` adds KE-007 missing-proof and ordering negative criteria coverage and updates the valid fixture.

The fake-network selector was reconciled to the accepted ST-013 acknowledgement contract: key sends are acknowledged, while local key processing is delayed until the test releases the captured key update. This preserves real `P2PService.sendMessage` ack propagation and still proves the received-message repair retry path.

## Accepted Evidence

Verdict: `accepted`.

Focused host and criteria checks passed:

- `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --name "KE-007|KE-009|KE-017"` -> `+3: All tests passed!`
- `flutter test test/integration/group_multi_party_device_criteria_test.dart --name "private_online_remove|private_readd_current|KE-007|KE-009|KE-008|KE-010"` -> `+63: All tests passed!`

Required iOS 26.2 live proof passed:

- Scenario: `private_online_remove`
- Run id: `1779397676077`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_TUhhHG`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_online_remove proof passed: private_online_remove verdicts valid for alice, bob, charlie`
- Verdict proof fields:
  - Alice `ke007FirstPostRotationProof`: `rotatedKeyGenerated=true`, `rotatedEpoch=2`, `waitedForBobRotatedKeyBeforeFirstPostRemovalSend=true`, `sentFirstPostRemovalAtRotatedEpoch=true`, `firstPostRemovalEpoch=2`, `receivedBobAfterRemoval=true`
  - Bob `ke007FirstPostRotationProof`: `receivedRotatedKeyBeforeFirstPostRemovalMessage=true`, `hasRotatedEpochBeforeFirstPostRemovalMessage=true`, `rotatedEpoch=2`, `receivedAliceAfterRemoval=true`, `receivedAliceAfterRemovalAtRotatedEpoch=true`, `aliceMessageEpoch=2`, `sentPostRemovalAtRotatedEpoch=true`

## Scope Guard

No production code was changed for KE-007. Source docs, COMPLETE_1 docs, source worktree files, unrelated KE rows, ML rows, UI, media, notification, Android, and physical iOS stayed out of scope. The unrelated dirty `info.plist` was left unstaged and untouched.

## Safe Next Action

KE-007 is terminally accepted. The only remaining re-reconciliation target from this focused pass is KE-009, which is no longer conflict-blocked but is blocked on the shared `private_readd_current` live fixture until that fixture is repaired and rerun.
