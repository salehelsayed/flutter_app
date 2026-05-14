# GR-006 Session Plan: Acknowledge Recovery Only After Full Group Rejoin

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-006`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:49:00 CEST | Controller | Source matrix GR-006 row; breakdown row 154; `handle_app_resumed.dart` recovery acknowledgment predicate; `rejoin_group_topics_use_case.dart` result fields; `main.dart` pending retrier recovery callback; Go `AcknowledgeGroupRecovery` behavior; existing lifecycle/retrier/watchdog tests | The source row was `Open` and the breakdown marked GR-006 `needs_code_and_tests` / `implementation-ready`. Production acknowledged native recovery when `errorCount == 0`, which still cleared the native `needsGroupRecovery` flag when an active group was skipped due to missing key material. That is a repo-owned app gating gap because a partial rejoin could leave a group deaf while clearing the recovery signal. | Add an explicit recovery-ack eligibility predicate that requires no errors and no missing-key skips, use it in resume and pending-retrier paths, add row-owned Flutter regression proving partial rejoin does not acknowledge until the missing group key is restored, then run native/app/retrier/watchdog gates. |

## Scope

GR-006 owns the app-side acknowledgment predicate for native group recovery. The app must not call `group:acknowledgeRecovery` while any active group topic failed to rejoin or was skipped because it lacks key material.

Out of scope: native stopped-node acknowledgment errors, watchdog restart counter persistence, relay recovery thresholds, and multi-device end-to-end recovery. Those are owned by later GR/GE rows.

## Execution Contract

1. Add a clear reusable predicate on `RejoinGroupTopicsResult` for recovery acknowledgment eligibility.
2. Use that predicate in both `handleAppResumed` rejoin branches and in `main.dart`'s `PendingMessageRetrier` recovery-ack callback.
3. Add a row-named Flutter lifecycle regression with two active groups where the first resume rejoins only the keyed group and does not acknowledge, then a later resume after saving the missing key rejoins both groups and acknowledges.
4. Run focused GR-006, existing ack/no-ack lifecycle selectors, handleAppResumed ordering, pending retrier ack/no-ack selectors, native acknowledgment/relay-session selector, fake-network watchdog resume selectors, formatting, and `git diff --check`.
5. Update the source matrix, breakdown ledgers, and this plan with concrete evidence before acceptance.

## Required Gates

| Gate | Command |
|---|---|
| Focused GR-006 proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006 recovery ack waits until every active group topic rejoins'` |
| Existing lifecycle ack/no-ack proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'`; `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'in-place recovery without Go signal rejoins but does not ack'` |
| Resume ordering proof | `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores'` |
| Pending retrier proof | `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'successful retrier-owned nodeRequestedRecovery sends ack on immediate recovery'`; `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'successful retrier-owned recovery sends ack on the retry sweep path'`; `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'failed retrier-owned recovery does not send ack'` |
| Main wiring proof | `flutter test --no-pub test/core/lifecycle/main_resume_group_upload_wiring_test.dart --plain-name 'main.dart wires group retry callbacks into PendingMessageRetrier'` |
| Native acknowledgment proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'AcknowledgeGroupRecovery|GroupRecovery|RelaySession'` from `go-mknoon` |
| Fake-network watchdog proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` |
| Hygiene | `dart format --set-exit-if-changed lib/features/groups/application/rejoin_group_topics_use_case.dart lib/core/lifecycle/handle_app_resumed.dart lib/main.dart test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained many prior rollout edits, including unrelated `lib/main.dart` migration wiring changes from earlier sessions. GR-006 production scope is limited to the recovery-ack predicate and its call sites in `rejoin_group_topics_use_case.dart`, `handle_app_resumed.dart`, and the pending-retrier callback in `main.dart`, plus the row-owned lifecycle/wiring tests and closure docs.

## Execution Evidence

- Added `RejoinGroupTopicsResult.canAcknowledgeGroupRecovery`, which requires `!skipped`, `skippedNoKeyCount == 0`, and `errorCount == 0`.
- Updated both `handleAppResumed` recovery acknowledgment branches to use `rejoinResult.canAcknowledgeGroupRecovery` instead of only `errorCount == 0`.
- Updated `main.dart` pending-retrier recovery callback to use the same predicate before returning acknowledgment eligibility for node-requested recovery.
- Added `test/core/lifecycle/app_lifecycle_recovery_test.dart::GR-006 recovery ack waits until every active group topic rejoins`.
- Updated `test/core/lifecycle/main_resume_group_upload_wiring_test.dart` to assert the pending-retrier wiring uses `rejoinResult.canAcknowledgeGroupRecovery`.

## Verification

- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006 recovery ack waits until every active group topic rejoins'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'in-place recovery without Go signal rejoins but does not ack'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores'` passed (`+1`).
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'successful retrier-owned nodeRequestedRecovery sends ack on immediate recovery'` passed (`+1`).
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'successful retrier-owned recovery sends ack on the retry sweep path'` passed (`+1`).
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'failed retrier-owned recovery does not send ack'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/main_resume_group_upload_wiring_test.dart --plain-name 'main.dart wires group retry callbacks into PendingMessageRetrier'` passed (`+1`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'AcknowledgeGroupRecovery|GroupRecovery|RelaySession'` passed (`ok github.com/mknoon/go-mknoon/node 21.379s`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` passed (`+1`).
- `dart format --set-exit-if-changed lib/features/groups/application/rejoin_group_topics_use_case.dart lib/core/lifecycle/handle_app_resumed.dart lib/main.dart test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart` passed.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-006 is `Covered` by a code change plus row-owned Flutter lifecycle proof that native group recovery is not acknowledged after a partial rejoin with missing key material, and is acknowledged only after every active group topic can rejoin. Residual-only: none for GR-006. GR-008 is the next unresolved P0 session in ledger order; no final program verdict was written.
