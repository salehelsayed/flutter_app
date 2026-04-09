# Session 3 Plan — Make Group Sender Recovery Exact-Once Across Pause/Resume And Online Retry While Preserving Ordering

**Date:** 2026-04-06
**Status:** Plan only

## real scope

What changes in this session:

- keep the existing group recovery ordering explicit and protected on the
  production resume path: rejoin topics, drain group inbox, recover stuck
  sends, retry incomplete group uploads, retry failed group sends, then retry
  failed inbox stores
- keep the existing online-retrier ordering explicit and protected for the same
  group recovery sequence before the shared 1:1 retry work runs
- add the missing sender-oriented exact-once proof for an ordinary group text
  send that survives rapid pause/resume cycles while one member receives live
  delivery and another member depends on inbox recovery
- only tighten production lifecycle/retrier behavior if the new regressions
  expose a real duplicate-send, duplicate-row, or stranded-pending gap

What does not change in this session:

- no caller-surface background-task work; that was Session `2`
- no new sender-row state model beyond the landed Session `1` `pending` and
  inbox-retry contract
- no per-recipient ACK/read-receipt semantics, announcement auth redesign, or
  broader transport architecture work
- no closure-doc refresh; that stays in Session `4`

## closure bar

Session `3` is sufficient when all of the following are true:

- `handleAppResumed(...)` still preserves the intended group recovery order,
  including `retryFailedGroupInboxStores(...)` after group failed-send retry
- `PendingMessageRetrier` still preserves the same group recovery order on
  online sweeps before shared 1:1 retry work, and before the final group inbox
  retry
- a live-peer group text send whose inbox custody is still unresolved or failed
  can be finished from durable local state across repeated pause/resume cycles
  without creating a second sender row or a second live publish
- the sender row closes back to `sent` exactly once when inbox recovery
  succeeds, while the offline member still receives exactly one recovered copy
- existing 1:1 lifecycle behavior remains unchanged unless a narrow shared
  lifecycle/retrier compatibility fix is genuinely required

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
- landed sender contract:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-1-plan.md`
  `lib/features/groups/application/send_group_message_use_case.dart`
  `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- runtime recovery seams:
  `lib/core/lifecycle/handle_app_resumed.dart`
  `lib/core/services/pending_message_retrier.dart`
  `lib/core/lifecycle/handle_app_paused.dart`
  `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- current direct proof:
  `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
  `test/core/services/pending_message_retrier_test.dart`
  `test/core/services/pending_message_retrier_upload_ordering_test.dart`
  `test/core/services/pending_message_retrier_stuck_sending_test.dart`
  `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  `test/features/groups/integration/group_resume_recovery_test.dart`

Conflict rules:

- current code and tests beat stale prose
- the breakdown controls session scope/order unless current repo evidence proves
  it stale
- `test-gate-definitions.md` and `./scripts/run_test_gates.sh` define the
  named gate contract

## session classification

`implementation-ready`

## exact problem statement

The production runtime already has the intended group recovery hooks wired:

- `handleAppResumed(...)` runs group rejoin, group inbox drain, stuck-send
  recovery, incomplete group upload retry, failed group send retry, then later
  group inbox retry
- `PendingMessageRetrier` runs the same group sequence on online sweeps before
  the shared 1:1 recovery steps and before the final group inbox retry

What is still weak is the proof layer around the landed Session `1` sender
contract.

Current repo evidence shows:

- ordinary group integration tests cover inbox drain, failed-send retry,
  partial delivery, and reader recovery
- ordering tests already pin most of the runtime sequence
- there is still no direct ordinary-group sender proof equivalent to the 1:1
  rapid lock/unlock exact-once case, especially for a live-peer success row
  that stays `pending` until inbox custody closes

This session therefore starts as a proof-and-runtime-hygiene pass:

- add the missing sender-oriented rapid pause/resume exact-once regression
- extend or tighten lifecycle test harnesses only as needed to execute the real
  resume chain including `retryFailedGroupInboxStores(...)`
- touch production lifecycle/retrier code only if those regressions expose a
  real state-transition or ordering bug

## files and repos to inspect next

Primary production files:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_paused.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`

Primary test and harness files:

- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/core/services/pending_message_retrier_stuck_sending_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/shared/helpers/lifecycle_helpers.dart`

Compatibility-reference files only if the new regression exposes a shared seam
issue:

- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/shared/fakes/group_test_user.dart`

## existing tests covering this area

Already useful coverage exists:

- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` already
  proves resume ordering through group failed-send retry
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart` already
  proves late-step fault isolation and that group inbox retry still runs after
  later shared recovery errors
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
  already proves the full online-sweep order including the final
  `retryFailedGroupInboxStores(...)` step
- `test/features/groups/integration/group_resume_recovery_test.dart` already
  proves failed-send retry, partial delivery, inbox-drain dedupe, and sender
  state honesty for inbox-store failure

What is still missing today:

- no direct ordinary-group sender proof that repeated pause/resume cycles do
  not duplicate a live-peer publish while a pending row is later closed through
  inbox retry
- no direct resume-order proof in the group-specific lifecycle suite that the
  final group inbox retry remains behind group failed-send retry after the
  Session `1` pending-row contract landed
- the shared lifecycle helper used by rapid-cycle tests does not currently pass
  a `retryFailedGroupInboxStoresFn`, so it cannot exercise the full production
  group resume chain without a narrow harness update

## regression/tests to add first

Add or update these regressions before considering the session done:

1. In `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- extend the existing group ordering proof so the expected sequence ends with
  `retryFailedGroupInboxStores`
- keep the feature-flag-disabled proof intact so group recovery callbacks still
  short-circuit cleanly

2. In `test/shared/helpers/lifecycle_helpers.dart`
- add the narrow helper pass-through needed for
  `retryFailedGroupInboxStoresFn` so rapid-cycle integration tests can run the
  real group resume chain without bypassing the lifecycle helper

3. In `test/features/groups/integration/group_resume_recovery_test.dart`
- add one ordinary-group rapid pause/resume regression where:
  - one reader gets the live publish
  - one reader depends on inbox recovery
  - the sender row starts `pending`
  - repeated pause/resume cycles close the original row back to `sent`
  - only one publish occurs, inbox retry runs only until success, and both
    readers end with exactly one copy of the message

4. Only if the new integration proof exposes a real runtime bug:
- make the smallest production fix in `handle_app_resumed.dart`,
  `pending_message_retrier.dart`, or the relevant group retry use case
- add one additional direct regression for that exact bug before broadening
  further

## step-by-step implementation plan

1. Tighten the group-specific resume ordering test first so the intended
   runtime sequence is explicit in the direct lifecycle suite.
2. Extend the shared lifecycle test helper with the minimum pass-through needed
   to run group inbox retry during rapid pause/resume integration tests.
3. Add the ordinary-group rapid pause/resume exact-once integration regression
   against the existing Session `1` pending-row semantics.
4. Run the new direct tests before touching production runtime code.
5. If the new regression passes on current production code, stop widening
   production scope and treat the session as proof-driven acceptance of the
   existing runtime contract.
6. If the new regression fails, implement only the narrowest lifecycle or
   retrier fix required to restore exact-once closure, then refresh the direct
   proof.
7. Re-run the touched direct tests.
8. Run the required named gates.
9. Update the session breakdown ledger with the landed truth and record whether
   Session `4` remains acceptance-only or needs any refreshed assumptions.

## risks and edge cases

- Session `1` introduced `pending` rows for live-peer success while inbox
  custody is unresolved. Resume and retrier proofs must ensure those rows are
  owned by inbox retry rather than accidentally re-published as failed sends.
- The production runtime intentionally separates group failed-send retry from
  group inbox retry. The new tests must not collapse those steps into one fake
  callback or they will miss the real ordering contract.
- Rapid pause/resume tests can create false positives if the bridge helper
  auto-delivers inbox payloads without checking command counts. The proof must
  assert sender row count, publish count, and receiver message count directly.
- Shared lifecycle and retrier code also serves 1:1 chat. If a production fix
  is needed, keep it narrow and verify it does not perturb the existing 1:1
  contract.
- Existing dirty-worktree diffs outside this seam are unrelated and must not be
  reverted.

## exact tests and gates to run

Direct tests:

```bash
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded
```

Recommended adjacent direct regression if touched:

```bash
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh baseline
```

Only if a shared 1:1 lifecycle or retrier production seam is touched:

```bash
./scripts/run_test_gates.sh 1to1
```

## known-failure interpretation

- treat failures in the new rapid-cycle group regression as real Session `3`
  failures unless the assertion is clearly stronger than the proposal and the
  landed Session `1` sender contract
- if ordering tests fail, treat that as a runtime regression for this session,
  not as a documentation-only mismatch
- for named gates, only classify a failure as pre-existing if the same failure
  clearly reproduces on untouched scope outside group lifecycle/recovery work

## done criteria

- the plan file exists and matches the accepted Session `1` and Session `2`
  repo state
- the direct lifecycle and integration regressions prove the intended runtime
  ordering plus sender exact-once recovery
- any required production change is narrow, tested, and does not widen scope
- required named gates pass
- the session breakdown ledger is updated so Session `4` can proceed from the
  latest landed truth
