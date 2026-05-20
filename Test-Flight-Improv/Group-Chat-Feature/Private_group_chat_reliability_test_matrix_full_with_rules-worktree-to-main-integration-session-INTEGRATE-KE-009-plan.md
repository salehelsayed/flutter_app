# INTEGRATE-KE-009 Integration Contract - Config Before Key Receive Gap

Status: blocked_conflict

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-009`
- Integration session: `INTEGRATE-KE-009`
- Title: `Out-of-order config-before-key does not create a receive-dead member`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-009-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

When Charlie receives membership/config state before the current group key, Charlie must not become a permanently receive-dead member:

- Charlie has active membership/config state while the current epoch key is still missing.
- A current-epoch message delivered during that window requests missing-key repair and remains replayable/visible after the current key arrives.
- Once the current key arrives, pending key repair retry runs for that epoch and Charlie continues receiving current-epoch messages.

## Source-Owned Historical Deltas

The accepted worktree plan lists these row-owned proof files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- source matrix, source session-breakdown, and source `test-inventory.md`

The source fake-network proof is `KE-009 config-before-key member repairs first current-epoch message`. It depends on the live receive path emitting `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` and requesting repair with `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` / `received_message_epoch_missing_local_key` when a normal received group message has an epoch higher than the receiver's local key state.

## Target Reconciliation

Current main has partial supporting infrastructure:

- generic pending key repair queue and retry paths exist;
- `private_readd_current` and KE-008 re-add activation proof are accepted in main;
- related COMPLETE_1 rows such as `GM-014`, `GM-035`, `GE-011`, and `GE-020` cover adjacent re-add, no-deaf-member, fallback, and convergence behavior.

Current main does not have exact KE-009 artifacts:

- no `KE-009` selector exists in the target smoke test;
- no `ke009ConfigBeforeKeyProof` criteria or live-harness fields exist;
- no `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` constant exists;
- no `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` diagnostic exists;
- the exact higher-epoch normal receive repair hook is absent.

That missing higher-epoch normal receive repair behavior is source row `KE-017` / target session `INTEGRATE-KE-017`, which remains pending. Importing the exact KE-009 host proof now would either fail or require importing KE-017 production behavior out of order. Importing only the `private_readd_current` criteria/live fields would overclaim KE-009 because the required fake-network ordering proof cannot pass in current main.

## Conflict Block

Verdict: `blocked_conflict`.

No code, tests, harness files, scripts, fixtures, or source matrix docs were modified for KE-009. The row is blocked before import because preserving both row contracts requires resolving the dependency between:

- `INTEGRATE-KE-009`: config-before-key receive gap repair proof;
- `INTEGRATE-KE-017`: received message epoch ahead of local key state triggers repair.

The existing `INTEGRATE-KE-007` conflict blocker is the same dependency family and remains preserved. Accepted `ML-007` and `KE-008` `private_readd_current` proof fields remain intact and were not broadened under KE-009.

Affected overlap rows checked for preservation context: `KE-007`, `KE-017`, `ML-007`, `KE-008`, COMPLETE_1 `GM-014`, `GM-035`, `GE-011`, and `GE-020`.

## Verification

No focused KE-009 tests or live iOS 26.2 proof were run because no row-owned code/test/harness delta was imported and the row is not accepted. Doc hygiene should be checked with scoped `git diff --check` after the ledger update.

## Safe Next Action

Resolve `INTEGRATE-KE-017` first, or explicitly authorize a combined reconciliation that preserves KE-007, KE-009, and KE-017 row contracts. The controller may only proceed to `INTEGRATE-KE-010` after verifying dirty state safety, dependency independence from the KE-007/KE-009/KE-017 blockers, and recording this blocker in the integration breakdown.
