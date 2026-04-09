# Session 1 Plan — Tighten The Shared Live-Peer Group Send Closure Contract

**Date:** 2026-04-06
**Status:** Plan only

## real scope

What changes in this session:

- tighten the shared `sendGroupMessage(...)` success contract so a live-peer or
  legacy publish success does not persist a row as durably `sent` while inbox
  custody is still unresolved
- use the existing `pending` status where the sender row must stay honest about
  outstanding inbox closure, while keeping zero-peer durable inbox success and
  timeout-to-inbox fallback as true `sent`
- promote pending rows back to `sent` when inbox storage eventually succeeds,
  both in the in-flight background completion path and in
  `retryFailedGroupInboxStores(...)`
- update the direct send and inbox-retry regressions so the repo stops encoding
  "publish succeeded, therefore the row is already sent" as the intended
  contract

What does not change in this session:

- no feed, share, or conversation-surface wiring changes unless a narrowly
  required compile/runtime fix is unavoidable
- no pause/resume ordering redesign, retrier sequencing work, or broader
  lifecycle changes beyond the inbox-retry promotion needed to finish this seam
- no announcement auth redesign, receiver-side dedupe redesign, or
  per-recipient ACK/read-receipt semantics
- no new DB migration unless current repo evidence proves the existing status
  and retry columns cannot express the honest contract

## closure bar

Session `1` is sufficient when all of the following are true:

- `sendGroupMessage(...)` no longer persists or returns a live-peer or
  legacy-success row as durably `sent` while `inboxStored` is unresolved or
  false
- the row stays retry-owned and honest with `status: 'pending'` plus retained
  `inboxRetryPayload` whenever publish succeeded but inbox custody is not yet
  durably closed
- the zero-peer durable inbox branch still returns
  `SendGroupMessageResult.successNoPeers` with persisted `status: 'sent'`
- the publish-timeout plus inbox-success fallback still returns durable success
  without reopening false failure UI
- background inbox completion and explicit inbox retry both promote a pending
  row back to `sent` and clear `inboxRetryPayload` once inbox custody lands
- the direct tests and required named gates pin this contract clearly enough
  that Session `2` can consume it without inferring sender-closure semantics

## source of truth

Authoritative sources for this session:

- controlling breakdown:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- proposal/spec:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named-gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`
- current production seam:
  `lib/features/groups/application/send_group_message_use_case.dart`
  `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
  `lib/features/groups/domain/models/group_message.dart`
  `lib/features/groups/domain/repositories/group_message_repository.dart`
  `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  `lib/core/database/helpers/group_messages_db_helpers.dart`
- current direct proof:
  `test/features/groups/application/send_group_message_use_case_test.dart`
  `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
  `test/features/conversation/presentation/widgets/letter_card_test.dart`

Conflict rules:

- current code and tests beat stale prose
- the breakdown controls session scope/order unless current repo evidence proves
  it stale
- `test-gate-definitions.md` and `./scripts/run_test_gates.sh` define the named
  gate contract

## session classification

`implementation-ready`

## exact problem statement

The current shared group send path already pre-persists a durable outgoing row
with `wireEnvelope` and `inboxRetryPayload`, but it still marks the row `sent`
too early in two important success branches:

- `topicPeers > 0`
- legacy bridge success where `topicPeers` is missing

In both branches, current code clears publish retry state and can return
`SendGroupMessageResult.success` while `inboxStored` is still unresolved or
already known false. The direct tests in
`test/features/groups/application/send_group_message_use_case_test.dart`
currently codify that behavior.

That leaves group and announcement text sends looking durably closed from the
sender perspective even though offline-member custody still depends on later
background completion or a later inbox retry.

This session must make the sender row honest without widening into a new
recipient-proof protocol and without breaking the already-correct branches:

- zero-peer + durable inbox success
- publish-timeout + durable inbox fallback
- publish-failure retry ownership
- announcement admin-only write bounds
- current receiver-side dedupe behavior

## files and repos to inspect next

Primary production files:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`

Caller-audit files for compatibility only, not default edit targets:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`

Primary direct tests:

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`

Compatibility-reference tests only if the contract change proves they need an
update:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`

## existing tests covering this area

Already useful coverage exists:

- `test/features/groups/application/send_group_message_use_case_test.dart`
  already pins the full 0-peer / peers>0 / legacy / publish-failure matrix and
  explicitly encodes the too-early `sent` behavior for live-peer success today
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  already proves inbox retry eligibility and confirms the query contract
- `lib/core/database/helpers/group_messages_db_helpers.dart` and
  `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
  already accept `status IN ('sent', 'pending')` for inbox-retry loading
- `lib/features/conversation/presentation/widgets/letter_card.dart` and
  `test/features/conversation/presentation/widgets/letter_card_test.dart`
  already render `pending` as a first-class sender status, so this session does
  not need to invent new UI semantics just to display honest state

What is still missing or misleading today:

- no direct proof that live-peer or legacy success remains `pending` until
  inbox custody is actually closed
- no direct proof that the background completion path promotes pending rows to
  `sent`
- no direct proof that explicit inbox retry promotes a pending row to `sent`
  instead of leaving it permanently half-closed

## regression/tests to add first

Add or update these direct regressions before considering the session done:

1. In `test/features/groups/application/send_group_message_use_case_test.dart`
- `peers > 0 + inbox fail` should still return success at the API level, but
  the returned/persisted row should be `status: 'pending'`, with
  `wireEnvelope` cleared and `inboxRetryPayload` retained
- `peers > 0 returns before inbox store finishes` should return quickly with
  `status: 'pending'`, then promote the persisted row to `sent` and clear
  `inboxRetryPayload` after the inbox future completes
- `missing topicPeers` legacy success should use the same honest pending-vs-sent
  rule rather than defaulting to unconditional `sent`
- `peers > 0 + inbox OK` must remain `status: 'sent'`
- `publish timeout + inbox OK` must remain durable `sent`

2. In `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- add one pending-row case proving a retry-eligible `status: 'pending'` row is
  promoted to `status: 'sent'`, `inboxStored: true`, and cleared
  `inboxRetryPayload` on success
- keep the existing sent-row compatibility proof so older already-sent rows can
  still be retried safely

3. In `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- only add or tighten coverage if the current helper tests do not already pin
  the `status IN ('sent', 'pending')` inbox-retry query semantics clearly

## step-by-step implementation plan

1. Tighten the direct tests in
   `test/features/groups/application/send_group_message_use_case_test.dart`
   first so the desired live-peer and legacy sender contract is explicit.
2. Tighten the direct tests in
   `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
   so pending rows must promote to `sent` when inbox retry succeeds.
3. Update `send_group_message_use_case.dart`:
   - keep zero-peer and timeout-fallback success branches as durable `sent`
   - change the live-peer and legacy-success branches to persist `pending`
     whenever inbox storage is unresolved or false
   - keep `wireEnvelope` cleared after publish success
   - retain `inboxRetryPayload` until inbox closure really succeeds
4. Tighten `_finalizeSuccessfulPublishInboxStoreInBackground(...)` so a
   background inbox success promotes the row to `sent` and clears retry payload,
   while a background inbox failure leaves the row pending and retry-owned.
5. Update `retry_failed_group_inbox_stores_use_case.dart` so a successful retry
   promotes pending rows to `sent`, marks `inboxStored: true`, and clears
   `inboxRetryPayload`.
6. Only if the direct implementation proves repository/helper semantics are not
   adequately covered, add the narrowest helper-level regression needed.
7. Re-run the touched direct tests.
8. Run the required named gates.
9. If the contract forces a caller-surface adjustment to stay truthful or to
   keep tests green, stop after the smallest compatible fix and record the
   remaining surface-parity follow-up for Session `2` rather than broadening
   this session by default.

## risks and edge cases

- `SendGroupMessageResult.success` is used by multiple callers. Changing API
  result semantics too early would widen this session into caller-surface work.
  Prefer preserving the result enum where possible and expressing honesty in the
  row status.
- If pending rows are introduced without retry promotion back to `sent`,
  messages can get stranded in a permanently half-closed state. The inbox-retry
  use case must be part of this session.
- The background finalization path currently only updates inbox fields. If it
  does not promote pending rows to `sent`, rapid lock/unlock cases will stay
  misleading.
- The zero-peer branch already maps durable relay custody to
  `successNoPeers`/`sent`; do not accidentally downgrade that branch into
  pending.
- The publish-timeout + inbox-success branch already avoids a false sender
  failure. Do not regress that fallback while tightening the live-peer branch.
- Announcement admin-only eligibility must stay intact. This session is about
  durable sender closure, not auth expansion.
- Existing dirty-worktree files outside this seam are unrelated and must not be
  reverted.

## exact tests and gates to run

Direct tests:

```bash
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
```

Conditional helper/UI compatibility tests only if touched:

```bash
flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
```

Required named gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh baseline
```

## known-failure interpretation

- Treat failures in the newly tightened direct group-send and inbox-retry tests
  as Session `1` regressions that must be fixed here.
- If `groups` or `baseline` fails in unrelated files already modified outside
  this seam, confirm whether the failure is pre-existing repo drift before
  classifying it as a new Session `1` regression.
- Do not downgrade a real send-contract failure into a docs-only note just
  because the broader gate output is noisy.

## done criteria

This session is complete when:

- live-peer and legacy publish success no longer persist a row as durably
  `sent` while inbox closure is unresolved
- the honest intermediate row is `pending`, with `inboxRetryPayload` retained
  until inbox success actually lands
- background inbox completion promotes the row to `sent`
- explicit inbox retry also promotes the row to `sent`
- zero-peer success and publish-timeout + inbox-success fallback still behave
  as durable success
- the direct tests and required named gates have been run
- no caller-surface, auth, or lifecycle redesign work has been silently folded
  into this session

## scope guard

- Do not redesign feed, share, or conversation-surface UX here unless a narrow
  compatibility fix is unavoidable.
- Do not widen into pause/resume ordering, retrier sequencing, or runtime
  recovery choreography; that is Session `3`.
- Do not add a new recipient-confirmation protocol, read receipts, or stronger
  cross-device ordering promises.
- Do not reopen zero-peer durable relay custody semantics; that branch is
  already the honest durable-success case.
- Do not introduce a DB migration unless existing columns truly cannot express
  the needed honest sender state.

## accepted differences / intentionally out of scope

- sender-trust parity stays below per-recipient ACK/read-receipt proof
- result-enum redesign is intentionally deferred unless current caller
  compatibility makes it unavoidable
- feed/share/main-surface parity remains Session `2` work; this session only
  establishes the shared sender-row closure contract they will adopt
- runtime resume/retry ordering remains Session `3` work apart from the minimal
  inbox-retry promotion required to avoid stranded pending rows

## dependency impact

- Session `2` depends on this plan establishing the honest shared sender-state
  contract before surface-level parity is refreshed.
- Session `3` depends on the resulting pending-vs-sent contract when it tightens
  resume/retry exact-once behavior.
- Session `4` depends on this session landing because the final parity proofs
  cannot truthfully claim sender-side closure while live-peer success still
  overstates completion.
- If current repo evidence disproves the need for `pending` and yields a
  smaller honest contract, stop and refresh the breakdown/plan rather than
  forcing this exact state model through implementation.
