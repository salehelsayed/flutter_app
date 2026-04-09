# Session 2 Plan — Bring Every Current Group Or Announcement Text Send Surface Onto The Same Interruption-Safe Entry Contract

**Date:** 2026-04-06
**Status:** Plan only

## real scope

What changes in this session:

- bring feed inline group reply onto the same bridge background-task entry
  contract the main group conversation already uses for text sends
- bring the current in-app share-to-group text send path onto the same
  interruption-safe bridge entry contract before it hands off to the shared
  group sender
- make share-to-group result classification truthful against the tightened
  Session `1` sender contract so a returned group row that is still
  `status: 'pending'` is not surfaced as fully sent
- add direct caller-surface regressions that prove these surfaces begin the
  bridge background task before publish work and end it only after the shared
  send finishes its durable handoff decision

What does not change in this session:

- no further change to the shared `sendGroupMessage(...)` sender-row contract
  beyond consuming the landed Session `1` semantics
- no pause/resume retrier sequencing or runtime recovery redesign; that stays
  in Session `3`
- no per-recipient ACK/read-receipt semantics, share UX redesign, or
  announcement auth redesign
- no broader media/background-upload product promise; the goal is caller-entry
  parity for the currently reachable text send surfaces

## closure bar

Session `2` is sufficient when all of the following are true:

- feed inline group reply acquires a bridge background task before invoking the
  shared group send and always releases it afterward
- the current share-to-group path acquires a bridge background task before its
  group-target send work and releases it afterward
- the share-to-group surface does not classify a group-target result as fully
  sent when the returned sender row is still `pending`
- existing feed optimistic inline-reply behavior and failure restore still work
- the main conversation send surface remains unchanged except for preserving
  compatibility with the new caller-parity proofs
- the direct tests and named gates make this caller-entry contract explicit
  enough that Session `3` can focus only on lifecycle/recovery work

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
- landed Session `1` sender contract:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-1-plan.md`
  `lib/features/groups/application/send_group_message_use_case.dart`
  `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- current caller seams:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  `lib/features/feed/presentation/screens/feed_wired.dart`
  `lib/features/share/application/share_batch_delivery_coordinator.dart`
  `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- current direct proof:
  `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  `test/features/feed/presentation/screens/feed_wired_test.dart`
  `test/features/share/application/share_batch_delivery_coordinator_test.dart`
  `test/features/share/integration/share_to_contact_smoke_test.dart`

Conflict rules:

- current code and tests beat stale prose
- the breakdown controls session scope/order unless current repo evidence proves
  it stale
- `test-gate-definitions.md` and `./scripts/run_test_gates.sh` define the
  named gate contract

## session classification

`implementation-ready`

## exact problem statement

Session `1` tightened the shared group sender so live-peer or legacy publish
success can now return a row that is still honestly `status: 'pending'` until
inbox custody closes. The main group conversation screen already wraps its text
and voice sends in `bg:begin/bg:end`, so that surface is aligned with the
send-then-lock bar.

Two reachable caller seams are still behind that standard:

- feed inline group reply calls `sendGroupMessage(...)` directly with optimistic
  UI but without its own bridge background task
- share-to-group also calls `sendGroupMessage(...)` directly and currently maps
  `SendGroupMessageResult.success` to a fully sent share result even when the
  returned row may still be `pending`

That means the caller-entry behavior is still surface-dependent, and the share
surface can overstate sender closure relative to the tightened Session `1`
contract.

This session must align those callers without reopening the sender core,
announcement auth, or lifecycle recovery.

## files and repos to inspect next

Primary production files:

- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  for parity reference only
- `lib/core/bridge/bridge.dart`

Primary direct tests:

- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

Compatibility-reference tests only if the contract change proves they need an
update:

- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`

## existing tests covering this area

Already useful coverage exists:

- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  already proves the main conversation screen starts `bg:begin` before publish
  work and closes `bg:end` after the shared group send finishes
- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves
  group inline reply optimistic UI, quote preservation, failure restore, and
  retry-discoverable pre-persist behavior
- `test/features/share/application/share_batch_delivery_coordinator_test.dart`
  already proves aggregate sent/queued/failed accounting at the coordinator
  layer

What is still missing or misleading today:

- no direct proof that feed inline group reply owns the same `bg:begin/bg:end`
  contract as the main group conversation surface
- no direct proof that share-to-group owns a background task around the group
  send handoff
- no direct proof that share-to-group treats a returned `pending` group row as
  queued/incomplete rather than fully sent

## regression/tests to add first

Add or update these direct regressions before considering the session done:

1. In `test/features/feed/presentation/screens/feed_wired_test.dart`
- add one narrow group-inline test proving `bg:begin` occurs before
  `group:publish` and `bg:end` occurs after `group:inboxStore`
- keep the existing optimistic session-reply and failure-restore assertions
  green so feed behavior stays truthful

2. In `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- add one real coordinator test proving a text-only group target starts
  `bg:begin`, runs the group publish/inbox store, and ends `bg:end`
- add one pending-row case proving a live-peer group share that returns
  `SendGroupMessageResult.success` plus `message.status == 'pending'` is
  classified as queued rather than sent
- keep the existing aggregate sent/queued/failed accounting proof intact

3. In `test/features/share/presentation/share_target_picker_wired_test.dart`
- only add or tighten coverage if a minimal UI wording change is needed to keep
  queued share feedback truthful after the new pending classification lands

## step-by-step implementation plan

1. Add the feed inline background-task regression first so the caller-entry
   contract is explicit before changing production code.
2. Add the real share-to-group coordinator regressions for background-task
   ownership and pending-result classification.
3. Update `feed_wired.dart` so `_onGroupInlineSend(...)` acquires
   `callBgBegin(widget.bridge)` before `sendGroupMessage(...)` and releases
   it in `finally`.
4. Update `share_batch_delivery_coordinator.dart` so `_sendToGroup(...)`
   acquires a bridge background task around the group-target send path and
   releases it in `finally`.
5. Tighten the group-target share result mapping so a returned message with
   `status == 'pending'` is surfaced as queued/incomplete rather than sent.
6. Only if the queued summary or detail text becomes misleading enough to fail
   truthfulness review, make the smallest compatible wording update in
   `share_target_picker_wired.dart` and pin it with one narrow UI regression.
7. Re-run the touched direct tests.
8. Run the required named gates.
9. Stop after caller-entry parity is landed; record any remaining lifecycle or
   exact-once recovery follow-up for Session `3` instead of widening this
   session.

## risks and edge cases

- `callBgBegin(...)` returns `null` when the bridge refuses or fails the
  request; callers must still no-op safely and avoid leaking exceptions.
- feed inline reply already uses optimistic UI. Adding a background-task wrapper
  must not break the fast local session-reply behavior or failure-restore path.
- the share coordinator can fan out to multiple targets. Group-target
  background-task ownership must not regress contact-target handling or widen
  into direct-chat scope unless the implementation accidentally couples them.
- the new Session `1` sender contract means `SendGroupMessageResult.success`
  is no longer enough by itself to imply a fully sent row for groups. The share
  surface must inspect the returned row status.
- share text-only parity is in scope; broader media/background-upload guarantees
  remain out of scope unless the minimal implementation naturally covers them
  without new product promises.
- announcement reader read-only behavior and admin-only writer enforcement must
  stay unchanged.

## exact tests and gates to run

Direct tests:

```bash
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart
```

Reference / compatibility proof if touched:

```bash
flutter test test/features/share/presentation/share_target_picker_wired_test.dart
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh baseline
```

Only if direct-chat feed send-entry code is touched materially:

```bash
./scripts/run_test_gates.sh 1to1
```

## known-failure interpretation

- treat failures in the two touched direct suites as regressions for this
  session unless the assertion was deliberately updated to match the new
  caller-entry contract
- for named gates, only classify a failure as pre-existing if the same failure
  clearly reproduces on untouched paths and is unrelated to feed inline group
  send or share-to-group handling
- do not treat dirty-worktree diffs outside this seam as evidence to widen or
  revert scope

## done criteria

- `feed_wired.dart` owns a background task around inline group send
- `share_batch_delivery_coordinator.dart` owns a background task around
  group-target send and does not overstate pending group rows as sent
- direct caller-surface tests explicitly pin the new background-task and
  pending-classification behavior
- the required named gates pass without reopening Session `1` semantics or
  broadening into Session `3` lifecycle work

## scope guard

- do not rework `sendGroupMessage(...)` semantics again in this session unless a
  narrowly required compatibility fix is unavoidable
- do not redesign share result UX, multi-target batching, or picker flows
- do not add new durable-runtime recovery logic here; Session `3` owns that
- do not broaden into media-upload architecture or platform-specific true
  background execution guarantees

## accepted differences / intentionally out of scope

- no new per-recipient proof or receipt semantics
- no promise that share media uploads complete under lock/background beyond the
  minimal caller-entry parity this session can safely add
- no changes to 1:1 share classification unless a small shared wording update
  is required for truthfulness
- no announcement role-policy changes

## dependency impact

- Session `3` depends on this session to make all current caller surfaces enter
  the shared group sender through one truthful interruption-safe contract before
  runtime recovery is tightened
- Session `4` depends on this session for feed/share parity proof and for any
  truthful share-surface classification it needs to assert in the final closure
  docs
