# Session Plan: 1

## Real Scope

- Bind receive-side group reaction handling to the outer transport `senderId`
  for both add and remove actions.
- Preserve the current stale-member-list tolerance only when the outer sender
  and decrypted inner payload sender match.
- Extend the same proof through replay callers that already route into
  `handleIncomingGroupReaction(...)`.
- Do not widen into broader reaction replay durability, UI, or product-scope
  work.

## Closure Bar

- `handleIncomingGroupReaction(...)` rejects mismatched outer/inner sender
  identity for both add and remove reaction payloads.
- Live receive happy paths and stale-member tolerance still work when the
  identities match.
- Replay paths that call the same handler prove the mismatch is rejected there
  too.
- Direct tests and the required named gates pass, or any unrelated pre-existing
  failure is called out explicitly without overclaiming closure.

## Source Of Truth

- Active session contract:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md`
- Governing audit:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13.md`
- Supporting audit:
  `Test-Flight-Improv/Group-Chat-Feature/Narrowed-Discussion-Announcement-Audit-2026-04-13.md`
- Regression and gate definitions:
  `Test-Flight-Improv/14-regression-test-strategy.md`
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests beat stale prose on disagreement.

## Session Classification

- `implementation-ready`

## Exact Problem Statement

- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  validates membership against the outer `senderId` but persists/removes
  reactions using the inner decrypted `payload.senderPeerId`.
- That leaves a trust seam where a mismatched payload can attribute a reaction
  to the wrong peer or remove the wrong peer's reaction.
- Current tests cover happy-path add/remove behavior and stale-member
  tolerance, but they do not reject sender mismatch on live receive or replay.
- The session must close only that sender-binding seam and keep the accepted
  replay and reaction behavior otherwise unchanged.

## Files And Repos To Inspect Next

- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## Existing Tests Covering This Area

- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  covers add/remove happy paths, unknown-group parse failures, and
  stale-member tolerance.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  covers replayed reaction happy-path persistence when `reactionRepo` is
  supplied.
- `test/features/groups/integration/group_resume_recovery_test.dart` is the
  conditional broader replay/resume regression if the fix changes shared replay
  expectations materially.

## Regression / Tests To Add First

1. Add a unit regression proving live receive rejects add/remove reactions when
   outer `senderId` and inner `payload.senderPeerId` differ.
2. Add a replay regression proving a replayed `group_reaction` item with a
   mismatched inner sender is ignored and does not persist a reaction.
3. Keep existing happy-path and stale-member tests green to prove the fix is
   narrow.

## Step-By-Step Implementation Plan

1. Tighten `handleIncomingGroupReaction(...)` so sender mismatch is rejected
   before any add/remove mutation is persisted.
2. Introduce the smallest explicit result or branch needed to distinguish
   sender mismatch from other existing outcomes without widening consumers.
3. Add unit tests for mismatched add/remove payloads plus a replay regression
   in the drain suite.
4. Run the direct suites first.
5. If the replay change affects broader resume semantics, run the conditional
   integration suite; otherwise stop at the direct suites plus named gates.
6. Run `./scripts/run_test_gates.sh groups` and
   `./scripts/run_test_gates.sh baseline`.
7. Leave maintained matrix/audit/test-inventory updates for Session `3`; only
   the breakdown ledger should move during this session.

## Risks And Edge Cases

- Do not break remove semantics by rejecting a valid remove whose sender matches
  but whose local member list is stale.
- Do not let replay code silently store the mismatched reaction as a normal
  message or another fallback type.
- Avoid changing any public product contract around best-effort replay
  durability; this session is sender identity truth only.

## Exact Tests And Gates To Run

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
  only if replay expectations broaden materially
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`

## Known-Failure Interpretation

- Treat a new mismatch-regression failure in the direct suites as a session
  blocker until the implementation closes it.
- If a named gate fails outside the touched sender-binding seam, record the
  exact failing test and evidence instead of overclaiming acceptance.
- No broad replay-durability redesign or unrelated gate cleanup is in scope for
  this session.

## Done Criteria

- Sender mismatch is rejected for both live and replayed add/remove reactions.
- Matching-sender happy paths and stale-member tolerance still pass.
- Required direct tests pass.
- Required named gates pass, or any unrelated pre-existing blocker is recorded
  honestly.
- Only the session plan, code/tests, and breakdown ledger move in this session.

## Scope Guard

- Do not redesign replay durability or retry ownership.
- Do not change reaction UI, reaction inspection, or long-press behavior.
- Do not widen into invite acceptance, group recovery ownership, or matrix/doc
  refresh beyond the breakdown ledger.

## Accepted Differences / Intentionally Out Of Scope

- The downgraded reaction replay durability concern remains explicit residual
  follow-up for Session `3` unless current execution proves it is already fully
  owned.
- This session does not solve broader encrypted replay or recovery architecture
  beyond the sender-binding seam.

## Dependency Impact

- Session `3` depends on truthful accepted evidence from this session before it
  can refresh maintained closure docs.
- Session `2` is independent and should not be reopened by this sender-binding
  fix.
