# INTEGRATE-IR-007 Integration Contract

Status: accepted

## Source Row

- Source row: `IR-007 - Inbox store failure owns retry without hiding message from sender`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-007-plan.md`
- Source status: accepted / closed in the source worktree.
- Integration mode: standard worktree-to-main import/reconcile/verify.

## Scope Guard

IR-007 imports only retry-ownership proof artifacts for normal group text sends when `group:inboxStore` fails.

In scope:
- publish succeeds but inbox store fails: sender row stays visible as `pending`, publish retry data is cleared, inbox retry data remains, and inbox retry stores the same message id once.
- publish fails or times out and inbox store also fails: sender row stays visible as `failed`, publish retry data remains, inbox-only retry does not claim it, and failed-message retry resends the same id without duplicate visible rows.

Out of scope:
- IR-006 recipient selection.
- IR-008 cursor/ack rollback and IR-009 persistence-before-ack.
- relay ACLs, media `allowedPeers`, UI, notifications, Android, physical iOS, macOS app-peer role work, and simulator/live proof.
- GO-002, GI-006, GP-026, and DE-008 ownership rewrites.

## Reconciliation Decision

Production code was already present in current main and was not modified. Current main already:
- builds and persists `inboxRetryPayload` before bridge calls in `send_group_message_use_case.dart`;
- treats inbox store failure as non-fatal for publish-success paths;
- leaves publish-success/inbox-failure rows as visible `pending` with `wireEnvelope == null`, `inboxStored == false`, and retry payload retained;
- leaves publish-fail/inbox-fail rows as visible `failed` with publish retry data retained;
- selects only outgoing `sent`/`pending` failed-inbox-store rows for `retryFailedGroupInboxStores`;
- promotes successful inbox retries to `sent`, marks `inboxStored`, and clears `inboxRetryPayload`.

The missing meaningful row-owned delta was proof coverage and row identity. The import added or reconciled only test artifacts:
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - added `_FailFirstNInboxStoreBridge`;
  - added `_groupInboxStoreReplayMessageIds`;
  - added `IR-007 publish success plus inbox failure is pending and inbox retry closes same id`;
  - added `IR-007 publish failure plus inbox failure is failed and owned by message retry`.
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - added `IR-007 inbox retry sends same pending message id once without duplicate rows`.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - promoted the existing pending live-peer fake-network proof to `IR-007 rapid pause/resume closes pending live-peer send via inbox retry exactly once` and strengthened retry-owner assertions;
  - promoted the existing DE-008 failed-message fake-network proof to `IR-007 DE-008 publish failure branch retries over fake network with same id and one row`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - records the row closure, count delta, and row-owned selectors.

## Verification

Focused IR-007 evidence:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'IR-007' # +2
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'IR-007' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-007' # +2
flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart lib/features/groups/application/retry_failed_group_messages_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart # No issues found
```

Affected preservation evidence:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'GO-002 publish success|DE-006 topicPeers|DE-006 partial topicPeers|DE-008 publish timeout|publish fail \\+ inbox fail|BB-013 group:publish timeout|BB-015 native publish failures|GI-007 relay non-OK' # +8
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'GO-002 retry promotes pending inbox store failure to sent' # +1
flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name 'DE-008' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-008|DE-006 partial live fanout|GR-017 recovery preserves failed direct and pending inbox retry state|rapid pause/resume closes pending live-peer send via inbox retry exactly once|zero-peer inbox failure stays owned' # +5
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'DE-006 full live fanout remains sent not delivered' # +1
```

Named gates and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups # +210 -3, residual only
./scripts/run_test_gates.sh completeness-check # 732/733, residual only
git diff --check # pass
```

The `groups` gate remains red only on preserved non-IR-007 residuals:
- `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`: `Expected: not null / Actual: <null>`.
- `BB-012 restart recovery drains replay before ack and stays live`: `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]`.
- `GM-029 config version monotonicity converges across A/B/C shuffled delivery`: `Expected: MemberRole.writer / Actual: MemberRole.reader`.

The `completeness-check` gate remains red only on the unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification gap (`732/733`).

## Device Proof

No iOS 26.2 simulator or live-device proof was required or run. The source row is host-only: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, and `3-Party E2E=N/A`.

## Closure Verdict

`INTEGRATE-IR-007` is accepted. Row-owned proof artifacts are present in main, production behavior was already present, focused and affected host checks passed, named gate residuals are unrelated and preserved, and no adjacent row is closed by this session.
