# GR-017 Session Plan: Preserve Group Retry State Through Recovery

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-017`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 07:31:00 CEST | Controller | Source matrix GR-017 row; breakdown row 159; existing retry tests in `test/features/groups/integration/group_resume_recovery_test.dart`; `lib/core/lifecycle/handle_app_resumed.dart`; `lib/features/groups/application/retry_failed_group_messages_use_case.dart`; `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`; `lib/core/services/pending_message_retrier.dart`; native relay recovery selector | The source row was still `Open` and the breakdown marked GR-017 `needs_repo_evidence` / `evidence-gated`. Existing production already keeps failed outgoing rows and pending inbox-store retry rows in separate retry queues, and resume wiring invokes both, but no exact row-owned proof staged both retry states across a recovery pass. | Add exact row-owned Flutter fake-network recovery proof; run focused GR-017, adjacent failed-message retry, pending inbox-store retry, pending retrier ordering, native recovery, format, and diff hygiene gates. |

## Scope

GR-017 owns recovery behavior for app-layer group retry state: a failed direct send and a pending durable inbox-store retry must survive relay/watchdog recovery and be retried or surfaced honestly instead of being silently dropped.

Out of scope: physical relay-device E2E and broad GE smoke coverage. Those remain owned by later GE rows.

## Execution Contract

1. Add a row-named Flutter integration test in `test/features/groups/integration/group_resume_recovery_test.dart`.
2. Stage one failed outgoing group message by failing the first publish and its fallback inbox-store attempt, proving the row remains `failed`, `inboxStored == false`, and has `inboxRetryPayload`.
3. Stage one pending inbox-store retry by allowing live publish but failing durable inbox-store, proving the row remains `pending`, `inboxStored == false`, and has `inboxRetryPayload`.
4. Trigger app resume recovery through `handleAppResumed` with group repositories wired, and run the real `retryFailedGroupMessages` and `retryFailedGroupInboxStores` callbacks.
5. Prove failed-message retry runs before inbox-store retry, both local rows close as `sent` with durable inbox stored and cleared retry payloads, and no duplicate live delivery occurs.
6. Inject the resulting durable inbox store payloads into the offline reader cursor inbox, drain, and prove both retry-state messages render exactly once.

## Required Gates

| Gate | Command |
|---|---|
| Focused Flutter proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-017'` |
| Adjacent failed-message retry proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'zero-peer inbox failure stays owned by failed-message retry and recovers in place'` |
| Adjacent inbox-store retry proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'rapid pause/resume closes a pending live-peer send via inbox retry exactly once'` |
| Pending retrier ordering proof | `flutter test --no-pub test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name 'online sweep runs rejoin, drain, group retries, shared 1:1 retries, then group inbox retry'` |
| Native recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` from `go-mknoon` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before GR-017 closure: worktree already contained prior rollout edits and accepted GR-004 through GR-016 changes. GR-017 scope is limited to `test/features/groups/integration/group_resume_recovery_test.dart`, this plan, the source matrix row GR-017, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `test/features/groups/integration/group_resume_recovery_test.dart::GR-017 recovery preserves failed direct and pending inbox retry state`.
- No production code changed for GR-017. Existing `handleAppResumed`, `retryFailedGroupMessages`, `retryFailedGroupInboxStores`, and pending retrier ordering satisfy the row once exact combined retry-state proof was added.
- The test creates Alice, a live reader, and an offline inbox reader in one private group and saves group keys for all participants.
- It fails Alice's first publish and fallback inbox store to stage a failed outgoing row with `inboxRetryPayload`.
- It then fails only the durable inbox-store side of a live publish to stage a pending inbox retry row while the live reader receives that message once.
- It calls `handleAppResumed` with `FakeP2PService(recoveryMethod: 'watchdog_restart')`, real group repositories, and the real group retry callbacks.
- It proves retry order is `retryFailedGroupMessages` followed by `retryFailedGroupInboxStores`, and both rows become `sent`, `inboxStored == true`, and `inboxRetryPayload == null`.
- It verifies publish/inbox-store command counts, injects the latest successful durable inbox store payloads for both deterministic message ids into the offline reader cursor inbox, drains, and proves the live and offline readers each have exactly one copy of both messages.

## Verification

- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-017'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'zero-peer inbox failure stays owned by failed-message retry and recovers in place'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'rapid pause/resume closes a pending live-peer send via inbox retry exactly once'` passed (`+1`).
- `flutter test --no-pub test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name 'online sweep runs rejoin, drain, group retries, shared 1:1 retries, then group inbox retry'` passed (`+1`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` passed (`ok github.com/mknoon/go-mknoon/node (cached)`).
- `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` passed.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-017 is `Covered` by row-owned Flutter fake-network evidence proving recovery preserves and closes both failed direct retry state and pending inbox-store retry state without duplicate delivery, backed by pending retrier ordering and native recovery evidence. Residual-only: no production code changed; physical multi-device relay E2E remains for later GE rows. GE-001 is the next unresolved P0 session in ledger order; no final program verdict was written.
