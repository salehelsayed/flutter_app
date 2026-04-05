# 57 - Authenticated Group Membership Events Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/57-authenticated-group-membership-events-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/57-authenticated-group-membership-events.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `57` is closed only when the repo-owned membership-event seam stops
accepting unauthorized add/remove state changes while preserving current valid
admin behavior:

- inbound repo-owned membership system events (`member_added`,
  `members_added`, `member_removed`) are applied only when the sender is
  authorized by trustworthy local admin facts rather than by UI gating alone
  or by trusting the inbound snapshot
- the same authorization rule applies on both live delivery and replayed
  listener paths
- unauthorized inbound events from non-admin senders do not mutate member
  state, do not update validator config, and do not emit misleading timeline
  side effects
- valid authorized add/remove flows still work, including duplicate-event and
  stale-event protections that already exist in the listener
- `SC-001` and `SC-015` become truthful closures in the maintained group
  matrix docs without overclaiming unsupported promotion/demotion product flows
- direct regressions and the named gate contract pass

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/57-authenticated-group-membership-events.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

Current repo facts that govern the split:

- `lib/features/groups/application/group_message_listener.dart` currently
  applies `member_added`, `members_added`, and `member_removed` system
  messages after stale-event checks, but it does not verify sender admin
  authority before mutating local membership state.
- The same listener owns both live handling and replay through
  `handleReplayEnvelope(...)`, so one listener-layer authorization rule can
  cover both live and replay paths.
- `lib/features/groups/domain/repositories/group_repository.dart` already
  exposes `getGroup(...)`, `getMember(...)`, and `getMembers(...)`, so the
  listener can consult durable local admin facts without inventing new storage
  layers first.
- Repo search shows no current landed membership-role event types beyond
  `member_added`, `members_added`, and `member_removed`; promotion/demotion
  flows remain unsupported scope rather than missing test coverage.
- `test/features/groups/application/group_message_listener_test.dart` already
  carries the direct regression family for membership system events, including
  duplicate handling, stale-event handling, timeline emission, and removal
  behavior.
- `test/features/groups/integration/group_membership_smoke_test.dart` already
  carries the three-user membership convergence surface and is the natural
  integration seam for a raw bypass regression that proves unauthorized events
  are ignored across peers.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` still
  keep `SC-001` and `SC-015` open specifically because
  `group_message_listener.dart` lacks sender-role authentication.

Source-of-truth conflicts that materially affected decomposition:

- The proposal leaves room for validator, signed-payload, or listener-layer
  enforcement, but current repo evidence shows the app-owned closure seam is
  the Flutter listener that currently applies inbound membership events.
- The matrix rows mention membership and role events broadly, but the current
  landed product contract does not include promotion/demotion system-message
  flows; closure must stay truthful to the repo-owned add/remove seam instead
  of silently inventing new role-management work.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Authenticate repo-owned membership system events in the listener` | `implementation-ready` | `Test-Flight-Improv/57-authenticated-group-membership-events-session-1-plan.md` | none | `completed` | `Test-Flight-Improv/57-authenticated-group-membership-events-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` | Completed on `2026-04-05`: `group_message_listener.dart` now rejects unauthorized repo-owned membership system events unless the sender matches durable local creator/admin facts, and the direct listener plus peer-visible raw-bypass regressions landed in `group_message_listener_test.dart` and `group_membership_smoke_test.dart`. The named reruns passed with `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. |

## Ordered session breakdown

### Session 1

- Title:
  `Authenticate repo-owned membership system events in the listener`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/57-authenticated-group-membership-events-session-1-plan.md`
- Exact scope:
  - add one listener-owned authorization gate for inbound repo-owned
    membership system events before local state is mutated
  - use trustworthy local group/admin facts for the decision instead of
    trusting the inbound `groupConfig` snapshot
  - apply that rule to live and replayed listener handling for
    `member_added`, `members_added`, and `member_removed`
  - preserve current valid authorized behavior, duplicate-event idempotence,
    stale-event rollback protection, readable timeline emission, and the
    existing remove-vs-send cutoff work
  - add direct listener regressions for unauthorized add/remove/batch-add
    events plus at least one authorized-control regression that proves the
    guard does not block valid admin behavior
  - add one integration-level raw bypass regression on the existing
    group-membership surface so `SC-001` closes on peer-visible state rather
    than unit evidence alone
  - update the maintained architecture/matrix docs and this breakdown once the
    code and proof land
- Why it is its own session:
  - this is one coherent listener-owned trust seam
  - the same direct regression family and the same named gates cover the whole
    slice
  - splitting implementation, proof, and closure docs would add bookkeeping
    without independent verification value because `SC-001` and `SC-015` only
    close when all three land together
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/57-authenticated-group-membership-events-session-breakdown.md`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart` only if
    final planning needs one replay-owned proof beyond the listener-level
    replay regression
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/57-authenticated-group-membership-events-session-breakdown.md`
  - intentionally unchanged unless execution widens:
    - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- A docs-only pass would leave the unauthorized listener mutation path intact.
- Closing `SC-001` without the direct listener regressions and one peer-visible
  integration proof would overclaim raw bypass resistance.
- The report only closes when implementation, proof, and matrix truth updates
  land together on this one seam.

## Why this is not more sessions

- The code change, direct tests, integration proof, and matrix refresh all sit
  on the same listener-owned boundary and use the same named gate contract.
- There is no separate validator/server prerequisite session justified by the
  current repo because the open gap is already identified as app-layer
  acceptance of unauthorized membership events.
- A separate acceptance-only session would be bookkeeping without a different
  seam, gate, or closure bar.

## Regression and gate contract

- Add the exact unauthorized membership-event regressions first in
  `test/features/groups/application/group_message_listener_test.dart`.
- Add the peer-visible raw bypass proof on the existing integration surface in
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Run the exact direct suites for touched group listener and membership tests.
- Run `./scripts/run_test_gates.sh groups`.
- Run `./scripts/run_test_gates.sh baseline` because Flutter production group
  code changes.
- Do not widen into `transport` or `1to1` unless final planning proves the
  implementation changed lifecycle/rejoin infrastructure outside the group
  listener seam.

## Matrix update contract

- Update:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Session ownership:
  - Session `1` owns the closure update because there is only one meaningful
    implementation seam for `SC-001` and `SC-015`.
- Truthfulness rule:
  - close the rows for repo-owned authenticated add/remove membership events
    without claiming unsupported promotion/demotion product flows were newly
    implemented.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- No new signed-event payload architecture is required if the listener-layer
  authorization closes the repo-owned gap truthfully.
- Promotion/demotion or richer multi-admin role-management flows remain out of
  current repo-owned product scope.
- Validator-layer hardening may still be future work, but this report closes at
  the app-owned listener seam if unauthorized inbound events are no longer
  applied locally.

## Finished doc verdict

- Verdict date:
  `2026-04-05`
- Current doc status:
  `closed`
- Stop-policy result:
  `finish_current_doc_before_advancing` satisfied; doc `58` may start
- Closure basis:
  - the repo-owned Flutter listener now applies `member_added`,
    `members_added`, and `member_removed` only when the sender matches durable
    local creator/admin facts rather than trusting the inbound snapshot
  - the same authorization rule now covers live delivery and replay because
    both paths flow through `GroupMessageListener`
  - unauthorized inbound membership events no longer mutate member state, sync
    validator config, or persist misleading timeline side effects
  - `Test-Flight-Improv/09-network-group-messaging.md`,
    `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, and
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    now close `SC-001` and `SC-015` truthfully at the landed listener seam
  - direct evidence passed in:
    `test/features/groups/application/group_message_listener_test.dart` and
    `test/features/groups/integration/group_membership_smoke_test.dart`
  - named gates passed with:
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- Residual truth outside this doc's scope:
  - promotion/demotion role-event flows remain outside current repo-owned
    product scope
  - validator-layer or signed-payload hardening may still be future work, but
    unauthorized repo-owned add/remove membership events no longer apply at the
    Flutter listener seam

## Exact docs/files used as evidence

- `Test-Flight-Improv/57-authenticated-group-membership-events.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The session set is the minimum safe slice: one listener-owned authorization
  seam, one direct regression family, one integration closure proof, and one
  matrix-truth update pass.
- It does not invent unsupported role-management scope, and it does not defer
  the proof needed to close the matrix rows truthfully.
