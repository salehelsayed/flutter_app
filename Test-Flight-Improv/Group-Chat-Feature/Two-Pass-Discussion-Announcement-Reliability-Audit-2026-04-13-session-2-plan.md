# Session Plan: 2

## Real Scope

- Close only the remaining degraded pending-invite accept gap: when
  `acceptPendingGroupInvite(...)` returns `bridgeError`, existing members still
  need one durable `member_joined` owner.
- Preserve the already-landed success-branch join timeline behavior, the
  current degraded snackbar copy, and pending-row cleanup.
- Prove the degraded path does not create duplicate join history when later
  rejoin and inbox-drain recovery still run.
- Do not widen into general invite redesign, startup transport work, or
  broader replay durability changes.

## Closure Bar

- The `bridgeError` branch no longer exits before all join-event ownership is
  decided.
- Existing members have one truthful durable path to the `member_joined`
  timeline in the degraded accept case.
- The degraded accept UI remains honest (`recovery is still catching up`).
- Later rejoin/drain recovery does not create a second join timeline event for
  the same accept.
- Direct tests and required named gates pass, or any unrelated blocker is
  recorded explicitly.

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
- Current code and tests beat stale prose. In particular, this session starts
  from the current partial worktree state where the success branch already has
  join-timeline publishing and related tests.

## Session Classification

- `implementation-ready`

## Exact Problem Statement

- The current worktree already added `_publishAcceptedJoinTimelineIfPossible(...)`
  for the success branch, but the `HandleGroupInviteResult.bridgeError` branch
  still deletes the pending row and returns the group immediately with no
  durable join owner for existing members.
- Existing tests currently prove:
  - success-path durable join publishing
  - degraded warning copy and pending-row cleanup
  - later rejoin/drain convergence without recreating the invite row
- They do not yet prove that the degraded accept path itself owns one durable
  `member_joined` contract or that later recovery avoids duplicating it.

## Files And Repos To Inspect Next

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`

## Existing Tests Covering This Area

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  now covers success-path join publishing and degraded persistence, but not a
  degraded durable join owner.
- `test/features/groups/presentation/group_list_wired_test.dart` covers the
  honest degraded warning and invite-row removal.
- `test/features/groups/integration/invite_round_trip_test.dart` covers later
  rejoin/drain convergence without the pending row, but not the degraded join
  event owner.
- `test/features/groups/application/group_message_listener_test.dart` already
  proves `member_joined` system messages materialize into durable timeline
  history and should only be rerun if this session changes that contract.

## Regression / Tests To Add First

1. Add a unit regression proving the degraded `bridgeError` accept path now
   owns one durable `member_joined` outcome for existing members.
2. Extend the widget/integration proof so the degraded accept path keeps the
   honest warning while later recovery still does not duplicate the join event.
3. Reuse the existing success-path join tests as a no-regression check.

## Step-By-Step Implementation Plan

1. Inspect the current partial success-branch helper and decide the smallest
   safe way to reuse or extend it for the degraded path.
2. Prefer the smallest coherent owner:
   - reuse the existing join-timeline helper on the degraded branch if that
     truthfully closes the gap without duplication, or
   - add one narrow recovery-time owner only if immediate degraded ownership
     cannot be made truthful.
3. Add the degraded-branch regression first in the accept use-case test.
4. Refresh the widget and integration tests so they prove:
   - the degraded warning remains
   - the durable join owner exists
   - later rejoin/drain does not create a duplicate join event
5. Run the direct suites first; rerun `group_message_listener_test.dart` only
   if the chosen fix changes how `member_joined` is materialized.
6. Run `./scripts/run_test_gates.sh groups`.
7. Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` to avoid
   the local multi-device ambiguity already observed in Session `1`.
8. Leave maintained matrix/audit/test-inventory refresh for Session `3`; only
   the breakdown ledger should move in this session.

## Risks And Edge Cases

- Avoid double-writing join history between the immediate accept branch and any
  later rejoin/drain path.
- Do not regress the existing success-path join publishing behavior.
- Do not silently downgrade the honest degraded UX into a misleading “fully
  joined” state.
- If the fix stores a durable replay owner, keep it narrow and tied to this
  specific join event rather than broad replay redesign.

## Exact Tests And Gates To Run

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
  only if the chosen fix changes `member_joined` materialization
- `./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

## Known-Failure Interpretation

- Treat a new degraded-accept join-owner failure in the direct suites as a
  session blocker until the implementation closes it.
- If `baseline` fails without `FLUTTER_DEVICE_ID`, that is environment noise,
  not a product blocker; use the explicit-device form above for the actual gate
  signal.
- If named gates fail outside the invite-accept seam, record the exact failure
  and do not overclaim acceptance.

## Done Criteria

- The degraded `bridgeError` path owns one truthful durable `member_joined`
  contract.
- Existing members do not get duplicate join history when later recovery runs.
- The degraded warning copy and pending-row cleanup remain intact.
- Required direct tests pass.
- Required named gates pass with the explicit baseline device selection noted
  above.

## Scope Guard

- Do not redesign pending invite review, onboarding, or contact eligibility.
- Do not widen into generic transport watchdog or startup repair work unless
  the current code proves it is strictly necessary for this one join owner.
- Do not refresh maintained matrix/audit docs in this session.

## Accepted Differences / Intentionally Out Of Scope

- The downgraded reaction replay durability concern remains explicit residual
  follow-up for Session `3`.
- Session `2` does not solve broader group replay durability or non-friend
  onboarding policy.

## Dependency Impact

- Session `3` depends on truthful accepted evidence from this session before it
  can refresh maintained closure docs and final verdict language.
- Session `1` is already accepted and should not be reopened from this invite
  fix.
