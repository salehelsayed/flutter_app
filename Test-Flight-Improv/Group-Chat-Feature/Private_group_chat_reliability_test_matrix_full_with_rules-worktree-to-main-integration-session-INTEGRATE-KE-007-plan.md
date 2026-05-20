# INTEGRATE-KE-007 Integration Contract - First Post-Rotation Key Availability

Status: blocked_conflict

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

Current main already has related but non-identical behavior:

- rotation distribution is fail-closed before sender promotion;
- existing removal coverage proves the first post-removal send uses rotated epoch `2`;
- offline/future-epoch replay repair and key-update listener retry paths exist.

Current main does not have exact KE-007 integration artifacts:

- no `KE-007` selector exists under `lib`, `test`, `integration_test`, or `go-mknoon`;
- no `ke007FirstPostRotationProof` criteria or live-harness fields exist;
- no `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` constant exists;
- no `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` diagnostic or `_requestReceivedMessageKeyRepairIfLocalEpochIsBehind` live receive repair path exists.

The missing live higher-epoch receive repair behavior is owned by source row `KE-017` / target session `INTEGRATE-KE-017`, which is still pending. Importing the KE-007 fake-network proof now would either fail or require importing KE-017 production behavior out of order.

## Conflict Block

Verdict: `blocked_conflict`.

No code, tests, harness files, scripts, fixtures, or source matrix docs were modified for KE-007. The row is blocked before import because preserving both row contracts requires resolving the dependency between:

- `INTEGRATE-KE-007`: first post-rotation key availability proof;
- `INTEGRATE-KE-017`: received message epoch ahead of local key state triggers repair.

Affected overlap rows checked for preservation context: `KE-006`, `KE-017`, COMPLETE_1 `GM-014`, `GM-020`, `GI-020`, `GO-001`, and related key repair/replay coverage.

## Verification

No focused KE-007 tests or live iOS 26.2 proof were run because no row-owned code/test/harness delta was imported and the row is not accepted. Doc hygiene should be checked with scoped `git diff --check` after the ledger update.

## Safe Next Action

Resolve `INTEGRATE-KE-017` first, or explicitly authorize a combined reconciliation that preserves both KE-007 and KE-017 row contracts. The controller may only proceed to `INTEGRATE-KE-008` after verifying dirty state safety, dependency independence from this KE-007/KE-017 blocker, and recording this blocker in the integration breakdown.
