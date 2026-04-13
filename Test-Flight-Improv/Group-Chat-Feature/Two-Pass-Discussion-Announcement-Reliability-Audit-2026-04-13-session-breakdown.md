# Two-Pass Discussion / Announcement Reliability Audit Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13.md`
- Decomposition date:
  `2026-04-13`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`
- The smallest safe split is two implementation sessions plus one acceptance
  and closure session.
- The reaction sender-binding seam and the degraded invite-accept
  `member_joined` seam touch different correctness owners, different direct
  regressions, and different maintained-doc claims.
- The downgraded reaction replay durability concern remains explicit follow-up
  work, not a third implementation slice in this rollout.

## Overall closure bar

Treat this audit as finished only when the repo truthfully owns the two kept
`P1` seams from the adjudicated audit without widening into unrelated
discussion or announcement scope:

- receive-side group reactions reject any mismatch between the outer envelope
  `senderId` and the decrypted inner `payload.senderPeerId` before storing or
  removing reactions
- replay callers that route through `handleIncomingGroupReaction(...)` prove the
  same mismatch rejection, so offline drain, resume, and rejoin cannot poison
  who appears to have reacted
- degraded pending-invite acceptance owns one durable `member_joined` contract
  for existing members, either immediately or through one explicit recovery
  owner that later convergence proves exactly once
- the shipped accept surfaces keep the current honest degraded-state messaging
  (`recovery is still catching up`) without dropping the durable join contract
  for existing members
- maintained discussion and announcement docs stop overclaiming the old
  degraded-accept behavior and carry the downgraded reaction replay durability
  concern as explicit residual follow-up instead of silent closure
- this rollout does not widen into broader reaction replay durability redesign,
  announcement UX redesign, or non-friend onboarding work

The expected finished state is:

- `accepted_with_explicit_follow_up`

The explicit follow-up is the already-downgraded best-effort reaction replay
durability concern from the source audit. This rollout should leave that item
truthfully residual-only unless execution proves it is already fully owned.

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13.md`
- `Test-Flight-Improv/Group-Chat-Feature/Narrowed-Discussion-Announcement-Audit-2026-04-13.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Current repo facts that govern the split:

- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  validates group membership with the outer `senderId` but persists and removes
  reactions using the decrypted inner `payload.senderPeerId`; the current unit
  suite proves happy paths and stale-member tolerance but does not reject the
  mismatch seam named in the audit.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  routes replayed `group_reaction` items through that same
  `handleIncomingGroupReaction(...)` receive seam, so the identity mismatch is
  not just a live-listener problem.
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  already rejects transport-sender versus payload-sender mismatch for invites,
  so leaving reactions looser would be an inconsistent trust boundary rather
  than an established repo-wide policy.
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  only calls `_publishAcceptedJoinTimelineIfPossible(...)` on the
  `HandleGroupInviteResult.success` branch. The `bridgeError` branch clears the
  pending invite row and returns the locally persisted group without any durable
  join-event owner for existing members.
- `lib/features/groups/presentation/screens/group_list_wired.dart` already
  passes the receiver identity material needed for join publishing into
  `acceptPendingGroupInvite(...)`, so the missing degraded join contract is not
  caused by absent caller data.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  proves success-path durable join history plus bridge-error local persistence,
  but it does not yet prove a degraded accept still results in one durable join
  timeline event for existing members.
- `test/features/groups/presentation/group_list_wired_test.dart` proves the
  shipped accept surface keeps the honest degraded warning and removes the
  pending invite row, but it does not prove a durable degraded-accept join
  owner.
- `test/features/groups/integration/invite_round_trip_test.dart` proves later
  bridge-error rejoin and drain convergence without recreating the pending row,
  but it does not prove that existing members get one durable `member_joined`
  timeline event in that degraded path.
- The source audit and narrowed audit both downgrade reaction replay durability
  to a best-effort concern rather than a release-blocking contradiction. That
  is sufficient to keep it as explicit follow-up rather than opening a new
  implementation session here.

Source-of-truth conflicts that materially affected decomposition:

- `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md` and
  `test-inventory.md` currently mark invite-accept durability and degraded
  accept recovery rows as accepted, but current code inspection shows the
  `bridgeError` branch returns before any durable `member_joined` owner runs.
  This breakdown reopens only that narrow degraded-accept residual, not the
  entire invite or join flow.
- The repo already enforces sender-mismatch rejection on group invites, so the
  reaction sender-binding fix is a narrow consistency and trust hardening slice,
  not a new architectural direction.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Bind incoming group reaction identity to the outer sender across live and replay receive` | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md` | Sender mismatch is now rejected before reaction mutation on live and replay receive; direct suites passed, `groups` passed, and `baseline` passed with `FLUTTER_DEVICE_ID=macos` because the local environment had multiple connected targets. |
| `2` | `Give degraded pending-invite acceptance one durable member_joined owner` | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-2-plan.md` | none | `accepted` | `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md` | The `bridgeError` path now reuses the durable join helper, stores replay even when live publish fails, and direct suites plus `groups` and explicit-device `baseline` passed. |
| `3` | `Refresh maintained discussion and announcement closure docs and record the remaining follow-up honestly` | `acceptance-only` | `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`, `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md` | Maintained docs now match the landed invite-accept and reaction receive evidence, and they preserve the downgraded reaction replay durability concern as explicit residual follow-up. |

## Pipeline progress

- `2026-04-13`: Reusable breakdown artifact created via bounded local
  decomposition fallback after the spawned decomposition attempt produced no
  doc-owned artifact.
- `2026-04-13`: Sessions `1` and `2` are both implementation-ready. Session
  `1` is the recommended first runnable slice because it closes the smaller
  receive-side trust seam without reopening invite recovery ownership.
- `2026-04-13`: Session `1` planning child no-progressed, so the controller
  wrote the bounded local plan fallback at
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-1-plan.md`.
- `2026-04-13`: Session `1` is accepted. The receive path now rejects outer
  sender versus inner payload sender mismatch before persisting or removing
  reactions, replay coverage proves the same rejection, the direct suites
  passed, `./scripts/run_test_gates.sh groups` passed, and
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed after
  forcing a single device because the local environment had multiple connected
  targets.
- `2026-04-13`: Session `2` planning child no-progressed, so the controller
  wrote the bounded local plan fallback at
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-2-plan.md`.
- `2026-04-13`: Session `2` is accepted. The degraded `bridgeError` accept
  path now still attempts the durable join helper, warns honestly if live
  `group:publish` fails, stores the join event for replay recipients anyway,
  and the direct accept/widget/integration suites passed along with
  `./scripts/run_test_gates.sh groups` and
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- `2026-04-13`: Session `3` fresh-child planning/closure no-progressed after
  rereading artifacts without producing a doc-owned result, so the controller
  wrote the bounded local plan fallback at
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-3-plan.md`.
- `2026-04-13`: Session `3` is accepted. The maintained matrix, audit, and
  test inventory now reflect the landed sender-binding and degraded
  invite-accept proof, and they preserve the downgraded reaction replay
  durability concern as explicit residual follow-up instead of silently
  closing it.

## Final program verdict

- Status:
  `accepted_with_explicit_follow_up`
- Last updated:
  `2026-04-13`
- Completion summary:
  - decomposition is complete
  - Session `1` is accepted
  - Session `2` is accepted
  - Session `3` is accepted
  - maintained docs now truthfully close the sender-binding and degraded
    invite-accept seams
  - explicit residual follow-up remains: sender-side group reaction replay
    storage is still best-effort when `group:inboxStore` fails during reaction
    add/remove, so this rollout does not claim a retry owner for that path

## Ordered session breakdown

### Session 1

- Title:
  `Bind incoming group reaction identity to the outer sender across live and replay receive`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-1-plan.md`
- Exact scope:
  - reject add and remove reaction payloads when the outer receive
    `senderId` does not match the decrypted inner `payload.senderPeerId`
  - keep the current stale-member-list tolerance only for cases where the
    sender identities match but membership state is locally stale
  - carry the same sender-binding contract through replay callers that already
    reuse `handleIncomingGroupReaction(...)`
  - add focused receive and replay regressions for mismatch rejection without
    regressing accepted reaction happy paths
- Why it is its own session:
  - this is one isolated trust seam in the group reaction receive path
  - it has its own direct regression family and can land independently without
    invite, UI, or broader recovery changes
  - splitting live receive from replay receive would be bookkeeping only
    because both routes already converge on the same handler
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely direct tests/regressions:
  - `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - rerun `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` only if the execution broadens replay expectations materially
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - update this breakdown artifact ledger
  - defer maintained matrix and audit refresh to Session `3`
- Dependency on earlier sessions:
  - none
- Execution-safety corrections that must be carried into the session plan:
  - do not regress the accepted reaction happy path, replay happy path, or
    stale-member-list tolerance when sender identities actually match
  - do not widen this slice into reaction-inspection UI or replay-durability
    redesign; this session is only about sender identity truth on receive

### Session 2

- Title:
  `Give degraded pending-invite acceptance one durable member_joined owner`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-2-plan.md`
- Exact scope:
  - make the `bridgeError` pending-invite accept path own one durable
    `member_joined` contract for existing members, either immediately or
    through one explicit accepted recovery owner that later convergence proves
    exactly once
  - preserve the current honest degraded-state UX and pending-invite-row
    cleanup while fixing the missing timeline ownership
  - prove that the degraded accept path does not duplicate join history when
    later rejoin and drain recovery still run
  - refresh the shipped accept-flow tests so success and degraded branches both
    have truthful join-contract evidence
- Why it is its own session:
  - this seam spans local invite acceptance, possible later rejoin ownership,
    and existing-member timeline visibility
  - it needs a different direct regression family from Session `1`
  - splitting immediate accept behavior from later recovery ownership would
    risk a misleading half-state with no truthful closure bar
- Likely code-entry files:
  - `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  - `lib/features/groups/application/rejoin_group_topics_use_case.dart`
  - `lib/features/groups/application/group_recovery_gate.dart`
  - `lib/features/groups/presentation/screens/group_list_wired.dart`
  - `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  - `test/features/groups/presentation/group_list_wired_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely direct tests/regressions:
  - `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart`
  - `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
  - rerun `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` if the chosen fix changes how existing members materialize the join event
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if execution broadens into
    startup, resume, or watchdog rejoin wiring beyond the existing
    invite-accept and direct recovery seams
- Matrix/closure docs to update when done:
  - update this breakdown artifact ledger
  - defer maintained matrix and audit refresh to Session `3`
- Dependency on earlier sessions:
  - none
- Execution-safety corrections that must be carried into the session plan:
  - do not duplicate `member_joined` history between the immediate accept path
    and any later recovery owner
  - do not widen this slice into generic invite-review redesign or new manual
    retry UX unless current code evidence forces that change
  - if a later recovery owner is chosen, it must survive pending-row deletion
    and prove eventual existing-member visibility without relying on hidden
    manual steps

### Session 3

- Title:
  `Refresh maintained discussion and announcement closure docs and record the remaining follow-up honestly`
- Session id:
  `3`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-3-plan.md`
- Exact scope:
  - rerun the direct suites and named gates required by Sessions `1` and `2`
  - refresh the maintained discussion and announcement matrix, audit, and test
    inventory so the landed evidence truthfully covers the reaction
    sender-binding proof and the degraded invite-accept durable join contract
  - keep the downgraded reaction replay durability concern explicit as
    residual-only follow-up unless execution proves it is already fully owned
  - update this breakdown artifact with the final ledger and persisted program
    verdict
- Why it is its own session:
  - maintained-doc closure should happen only after both implementation seams
    are real and re-verified
  - keeping closure separate prevents premature doc cleanup or accidental
    expansion into the downgraded `P2` durability follow-up
- Likely code-entry files:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md`
  - any direct regression files refreshed by Sessions `1` and `2`
- Likely direct tests/regressions:
  - `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart`
  - `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
  - rerun `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` only if Sessions `1` or `2` broaden replay or rejoin behavior materially
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if Session `2` broadens into
    startup, resume, or watchdog rejoin wiring outside the existing direct test
    families
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - this breakdown artifact ledger
- Dependency on earlier sessions:
  - Session `1`
  - Session `2`

## Why this is not fewer sessions

- One giant implementation session would mix a narrow reaction receive trust
  fix with a different invite-accept recovery-owner seam and make it too easy
  to overclaim closure without refreshing the maintained docs honestly.
- Session `3` exists because the source audit is primarily a truth and closure
  artifact; the final program verdict must be based on rerun evidence and doc
  refresh, not only on landed code.

## Why this is not more sessions

- Splitting live reaction receive from replay reaction receive would be
  bookkeeping only because both routes already converge on the same handler.
- Splitting degraded invite acceptance from its later recovery proof would
  leave no independently truthful closure point for existing-member join
  visibility.
- The downgraded reaction replay durability concern is explicit follow-up, not
  a safe extra implementation session in this rollout.

## Regression and gate contract

- Follow `Test-Flight-Improv/14-regression-test-strategy.md` and
  `Test-Flight-Improv/test-gate-definitions.md`.
- Session `1` must add the direct sender-mismatch regression first for the
  exact receive seam named in the audit.
- Session `2` must add the degraded-accept join-ownership regression first so
  the bridge-error path cannot silently remain under-claimed.
- Sessions `1` and `2` should run:
  - the session-owned direct suites
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` is conditional, not automatic. Run it
  only if Session `2` broadens into startup, resume, or watchdog rejoin wiring
  that the current direct invite-accept suites no longer cover adequately.
- Session `3` must rerun the landed direct suites from Sessions `1` and `2`,
  then rerun the required named gates before updating the maintained docs.

## Matrix update contract

- Reuse the existing maintained docs:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Session `3` owns those doc updates because it will have the final accepted
  implementation facts and rerun evidence.
- No new matrix or closure doc is needed for this narrow audit follow-up.

## Downstream execution path

- Session `1` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `2` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `3` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- This rollout does not solve the downgraded best-effort reaction replay
  durability concern unless current code and execution evidence unexpectedly
  show it is already fully owned.
- This rollout does not reopen reaction inspection UX, non-friend onboarding,
  or broader announcement product-scope work.
- The current honest degraded invite-accept copy may remain, as long as the
  durable join ownership gap is actually closed.
