# 56 Session 1 Plan: Choose and Enforce the Live Remove-vs-Send Cutoff

## Final verdict

`implementation-ready`

## Real scope

- Add the smallest receiver-side cutoff rule needed so a message from a member
  who has already been removed is accepted or rejected deterministically when
  peers process it after the removal event.
- Reuse the persisted synthetic `member_removed` timeline entry as the
  sender-specific cutoff source instead of inventing a new protocol or
  transport layer.
- Add direct unit coverage for the cutoff rule and one live fake-network proof
  that delayed delivery after removal respects the same rule.
- Keep Session `1` scoped to the live listener/ingest seam. Do not update the
  architecture note or matrix docs here; Session `2` owns the final doc truth
  pass once replay and reconnect evidence also exists.

## Closure bar

Session `1` is good enough only when all of the following are true:

- incoming group messages from a sender who is no longer a member are rejected
  when their message timestamp is at or after that sender's persisted removal
  cutoff
- delayed messages from that removed sender are still accepted when their
  message timestamp is strictly before the removal watermark
- the old stale-member tolerance remains intact when no removal cutoff exists
  for that sender
- direct tests prove both accepted-before-cutoff and rejected-at-or-after-cutoff
  behavior
- one live fake-network regression proves remaining peers converge on the same
  result after a removal event when a delayed removed-sender envelope arrives

## Source of truth

- Active task docs:
  - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
  - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`
- Governing architecture and matrices:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Regression and gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Code and tests that currently define the seam:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/repositories/group_message_repository.dart`
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `test/shared/fakes/group_test_user.dart`

On disagreement, current code and direct tests beat stale prose. This session
must fit the current persisted removal-event path rather than inventing a new
protocol contract.

## Session classification

`implementation-ready`

## Exact problem statement

The repo already proves:

- removed members stop sending after self-removal cleanup
- group sends are pre-persisted before publish completes
- membership events persist synthetic `member_removed` timeline entries for
  remaining peers

What is still missing is one deterministic rule for a delayed normal message
from a sender who has been removed but whose message arrives after peers have
processed the removal event. Today
`handle_incoming_group_message_use_case.dart` still accepts unknown senders as
stale-member tolerance without consulting any sender-specific persisted removal
cutoff, so a post-removal message can still land purely because it arrived
late.

User-visible behavior to improve:

- remaining peers must converge on one accepted-or-rejected result for a
  removed sender's delayed message based on that sender's persisted removal
  event

Behavior that must stay unchanged:

- pre-removal delayed messages must still land
- normal stale-member tolerance must remain when there is no applied removal
  cutoff for that sender yet
- self-removal cleanup and ordinary post-cleanup send rejection stay as they are

## Files and repos to inspect next

- Production:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/repositories/group_message_repository.dart`
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  - `lib/core/database/helpers/group_messages_db_helpers.dart`
  - `lib/main.dart`
- Direct tests:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Test harness:
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `test/shared/fakes/group_test_user.dart`

## Existing tests covering this area

- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  covers unknown-group handling, stale unknown-sender tolerance, dedupe, and
  persistence, but it does not yet consult a sender-specific persisted removal
  cutoff.
- `test/features/groups/application/group_message_listener_test.dart`
  already proves `member_removed` events persist a synthetic removal timeline
  entry for remaining peers, which is the current sender-specific cutoff
  primitive this session should reuse.
- `test/features/groups/integration/group_membership_smoke_test.dart`
  proves removed members cannot send after self-removal cleanup, but it does
  not pin a delayed message that crosses the removal boundary.

## Regression/tests to add first

- Add unit regressions in
  `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  for:
  - removed sender message accepted when timestamp is before that sender's
    persisted synthetic `member_removed` timeline entry
  - removed sender message rejected when timestamp is equal to or after that
    sender's persisted synthetic `member_removed` timeline entry
  - unknown sender still accepted when the group has no persisted removal
    cutoff for that sender
  - unknown sender for another peer still accepted when the persisted removal
    entry belongs to someone else
- Add one live fake-network regression in
  `test/features/groups/integration/group_membership_smoke_test.dart` proving
  remaining peers accept a delayed removed-sender envelope from before the
  cutoff and reject a delayed removed-sender envelope from after the cutoff.

These tests prove the exact seam without widening into replay/startup work that
belongs to Session `2`.

## Step-by-step implementation plan

1. Tighten `handle_incoming_group_message_use_case.dart` so unknown senders are
   no longer blindly accepted once the repo has a persisted removal event for
   that same sender.
2. Implement the minimal cutoff rule:
   - if sender is still a member, process normally
   - if sender is unknown and there is no persisted removal event for that
     sender, preserve the existing stale-member tolerance
   - if sender is unknown and there is a persisted removal event for that
     sender, accept only when the message timestamp is strictly before that
     removal timestamp; otherwise ignore the message
3. Add the smallest repository lookup needed to retrieve the latest persisted
   synthetic removal event for one sender without widening into a broader
   history redesign.
4. Emit one explicit flow event for the reject path so later debugging can tell
   the difference between duplicate, unknown-group, and removed-after-cutoff
   drops.
5. Add the unit regressions first, then land the production change.
6. Add the live fake-network regression proving accepted-before-cutoff and
   rejected-after-cutoff behavior for remaining peers after a removal event.
7. Run the direct tests and the required named gates for the actual changed
   surface.
8. If direct evidence shows the fake-network seam cannot express the rule
   honestly without replay/inbox wiring, stop and roll the remainder into
   Session `2` rather than widening Session `1`.

## Risks and edge cases

- `timestamp` parsing:
  malformed timestamps currently fall back to `now`; that may cause a removed
  sender message to be rejected after cutoff, which is acceptable and should
  not be loosened in this session.
- equality semantics:
  the rule must pick one side for exact equality. This plan uses
  `timestamp < removalCutoff` as accepted and `>=` as rejected.
- stale-member tolerance:
  the new rule must not reject an unknown sender merely because some other
  member was removed earlier; the cutoff has to stay sender-specific.
- receipt-less sender UX:
  this session does not try to invent sender receipts or a remote ACK model.
  Remaining-peer convergence is the truthful contract for now.

## Exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
- Conditional extra gates:
  - do not run `transport` unless the implementation widens into inbox-drain,
    resume, or reconnect production code
  - do not run `1to1` unless shared non-group messaging infrastructure is touched

## Known-failure interpretation

- Treat failures in the new or touched direct tests as session blockers.
- Treat failures in unrelated dirty-worktree group files as blockers only if
  the failing stack actually intersects this session's changed seam.
- If `baseline` or `groups` fails in a clearly unrelated pre-existing area,
  record the failing command and file as a known pre-existing blocker instead
  of silently claiming the gate passed.

## Done criteria

- production code applies the cutoff rule exactly as specified above
- direct unit coverage proves accepted-before-cutoff, rejected-at-or-after-cutoff,
  and no-watermark tolerance
- live fake-network coverage proves remaining peers converge on the same result
  after removal when delayed removed-sender envelopes arrive
- required direct tests pass
- required named gates are run and either pass or are recorded truthfully as
  unrelated pre-existing blockers
- the session result is written back into
  `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`

## Scope guard

- Do not redesign group transport, validator protocol, or key distribution.
- Do not widen into replay/startup/reconnect flow changes; that belongs to
  Session `2`.
- Do not update the architecture note or matrix docs in this session.
- Do not add a new groups-table cutoff field or protocol field; this session
  should derive the cutoff from the persisted synthetic removal timeline entry.
- Do not change unrelated add/remove/admin-role flows.

## Accepted differences / intentionally out of scope

- This session does not promise sender-side certainty at the exact race moment;
  the current group model is still receipt-less and relies on eventual
  remaining-peer convergence plus self-removal cleanup.
- This session does not solve clock-skew as a protocol problem. It reuses the
  repo's current timestamp-based ordering primitive because that is the current
  persisted signal available without widening scope.

## Dependency impact

- Session `2` depends on this session choosing and proving the canonical cutoff
  rule before replay/reconnect tests and doc closure updates can be truthful.
- If Session `1` lands a different sender-specific lookup than currently
  expected, Session `2` must be replanned against that landed reality before
  execution.

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- a dedicated flow-event regression for the new reject event can be added later
  if debugging evidence shows it is needed

## Accepted differences intentionally left unchanged

- no sender receipt/ACK redesign
- no matrix or architecture doc updates until Session `2`

## Exact docs/files used as evidence

- `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
- `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`

## Why the plan is safe to implement now

The plan stays on one coherent seam that already persists sender-specific
removal evidence in the timeline path. It avoids inventing new protocol
metadata or group-table schema, keeps replay/startup work in Session `2`, and
gives execution one exact rule to prove before any broader closure claims.
