# Session 4 Plan — Land The Missing Parity Proofs And Refresh Maintained Closure References

**Date:** 2026-04-06
**Status:** Plan only

## real scope

What changes in this session:

- accept the already-landed Session `2` caller parity proofs in feed inline
  reply and share-to-group as part of the final report-level parity layer
- add the missing ordinary-group conversation text send lock/unmount proofs
  with live peers and with zero peers so the main conversation direct proof is
  no longer announcement-only
- refresh the maintained closure references so they truthfully describe the
  landed sender-trust send-then-lock parity contract for group discussion and
  announcements
- rerun the focused direct suites plus the named gates required for this final
  acceptance pass

What does not change in this session:

- no new production Flutter or Go behavior unless the final parity regressions
  expose a real bug
- no new per-recipient ACK/read-receipt semantics or broader transport claims
- no new share surface or feed UX work beyond proving the already-landed
  parity behavior

## closure bar

Session `4` is sufficient when all of the following are true:

- ordinary group conversation text send has direct lock/unmount parity proofs
  for both live-peer and zero-peer publish shapes
- the final acceptance layer still includes sender-perspective mixed-topology
  rapid pause/resume proof from Session `3`, plus the caller-parity proofs from
  Session `2`
- focused direct suites and named gates pass for the final landed state
- `20-group-discussion-reliability-closure-reference.md` and
  `21-announcement-reliability-closure-reference.md` describe the current
  sender-trust parity contract without overstating per-recipient guarantees

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
- maintained closure refs:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- main conversation acceptance proof:
  `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- caller-parity proof:
  `test/features/feed/presentation/screens/feed_wired_test.dart`
  `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- mixed-topology rapid-cycle proof:
  `test/features/groups/integration/group_resume_recovery_test.dart`

Conflict rules:

- current landed code and tests beat stale prose
- the breakdown controls final proof/doc scope unless current repo evidence
  proves it stale
- `test-gate-definitions.md` and `./scripts/run_test_gates.sh` define the
  named gate contract

## session classification

`acceptance-only`

## exact problem statement

Sessions `1` through `3` already landed the shared sender contract,
caller-surface parity, and exact-once pause/resume proof.

What remained open at decomposition time was the acceptance layer:

- the main conversation direct bg-task suite still had announcement-specific
  lock/unmount text proofs but no ordinary-group equivalents
- the maintained closure refs still described a weaker group/announcement
  sender-trust story than the repo now supports after Reports `67` Session `1`
  through `3`

This session therefore closes the report by:

1. adding the missing ordinary-group direct proofs,
2. revalidating the existing feed/share/resume acceptance evidence,
3. updating the maintained closure refs to match the landed reality.

## files and repos to inspect next

Primary files:

- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`

## existing tests covering this area

Already useful coverage exists:

- `group_conversation_wired_bg_task_test.dart` already proves ordinary text
  background-task ordering and announcement lock/unmount text parity
- `feed_wired_test.dart` already proves inline group reply owns
  `bg:begin/bg:end` and preserves queued/pending honesty
- `share_batch_delivery_coordinator_test.dart` already proves share-to-group
  owns the same background-task contract and truthful queued vs sent reporting
- `group_resume_recovery_test.dart` now proves the ordinary-group mixed live +
  offline rapid pause/resume exact-once closure added in Session `3`

What is still missing today:

- no direct ordinary-group lock/unmount proof with live peers
- no direct ordinary-group lock/unmount proof with zero peers
- maintained closure refs do not yet explicitly claim the landed parity level

## regression/tests to add first

1. In `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- add one ordinary-group text lock/unmount proof with live peers
- add one ordinary-group text lock/unmount proof with zero peers

2. Re-run the focused direct suites:
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart`

3. Re-run the named gates for the final accepted state:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh feed`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`

4. Update the maintained closure refs and the breakdown ledger only after the
   proofs above are green.

## step-by-step implementation plan

1. Accept Session `3` in the breakdown with the now-passed gate evidence.
2. Add the two ordinary-group direct lock/unmount regressions.
3. Run the focused direct suites for group conversation, group resume, feed,
   and share parity.
4. Run the final named gates required by the breakdown.
5. Refresh the group and announcement closure refs to match the landed
   sender-trust parity contract.
6. Update the breakdown ledger, pipeline progress, and final program verdict.

## risks and edge cases

- Do not restate the current contract as per-recipient proof; parity is still
  sender-trust closure on top of receipt-less group delivery.
- The ordinary-group direct proofs should mirror the announcement tests closely
  enough to demonstrate parity without inventing new harness behavior.
- The final closure refs must stay aligned with the landed repo truth and avoid
  reopening broader background-upload or product-scope claims.
