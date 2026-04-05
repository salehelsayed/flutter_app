# 59 - Post-Creation Admin Role Management Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`

## Overall closure bar

Report `59` closed only when post-creation admin-role management is a landed,
truthful product contract rather than explicit unsupported scope:

- group admins can promote another member to admin and revoke admin safely
  after creation without leaving the group leaderless
- non-admin and non-member role-change attempts fail deterministically and do
  not mutate local or peer-visible membership state
- multi-admin leave and the resulting admin-only permissions remain correct for
  the remaining admins and former admins
- members see the final agreed role state, including the product-visible badge
  and timeline/event surface the implementation chooses to ship
- conflicting or near-simultaneous admin-change flows converge to one explicit
  final state under tests rather than informal assumptions
- the maintained audit and matrix docs no longer mark these rows as unsupported
  when the code and tests now own them

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`

Current repo facts that govern the split:

- the repo already persists member roles and exposes
  `GroupRepository.updateMemberRole`, so role changes are not a schema-design
  problem; the missing seam is the shipped post-creation product flow and its
  convergence contract
- `leave_group_use_case.dart` already blocks the sole admin from leaving,
  which makes admin continuity a real product invariant that the new feature
  must preserve
- `group_info_screen.dart`, `group_info_wired.dart`, and
  `group_member_row.dart` currently expose add/remove membership and leave
  flows, but no promote/demote/transfer-style role actions
- `group_message_listener.dart` and its tests already own member-list
  convergence, authorization checks for membership system events, and several
  stale ordering protections; the new admin-role feature should extend that
  existing correctness seam rather than invent a separate state model
- `11-group-discussion-use-case-audit.md`,
  `09-network-group-messaging.md`, and
  `libp2p_group_chat_matrix_features_did_not_exist.md` still record richer
  admin tooling as unsupported scope, so a closure pass must update those docs
  after code/test truth lands

Source-of-truth conflicts that materially affected decomposition:

- the proposal allows flexibility on whether promote, transfer, and demote are
  separate UI actions, but the repo already has one member-management surface,
  so the safe split is by technical seam, not by each button label
- some lower-level convergence coverage already exists for membership adds and
  removals, but the matrix rows named by this doc remain unsupported until the
  exact admin-role journeys are implemented and re-closed with direct evidence

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Ship the role-change mutation contract and admin-continuity guards` | `implementation-ready` | `Test-Flight-Improv/59-post-creation-admin-role-management-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md` | Accepted on `2026-04-05` after landing the role-change use case, `member_role_updated` listener/timeline handling, test-user broadcast plumbing, and the direct use-case/listener/integration regressions, then verifying `flutter test test/features/groups/application/update_group_member_role_use_case_test.dart`, `flutter test test/features/groups/application/group_message_listener_test.dart`, `flutter test test/features/groups/application/leave_group_use_case_test.dart`, `flutter test test/features/groups/integration/group_membership_smoke_test.dart`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `./scripts/run_test_gates.sh groups`. One bounded local planning/execution fallback was used after the spawned doc-59 child steps no-progressed. |
| `2` | `Expose admin-role management in the group info surface and timeline` | `implementation-ready` | `Test-Flight-Improv/59-post-creation-admin-role-management-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md` | Accepted on `2026-04-05` after landing group-info promote/demote controls, repo-truth role refresh, confirmation/snackbar feedback, and `member_role_updated` broadcast/timeline wiring, then verifying `flutter test test/features/groups/presentation/group_info_screen_test.dart`, `flutter test test/features/groups/presentation/group_info_wired_test.dart`, `flutter test test/features/groups/integration/group_membership_smoke_test.dart`, and `./scripts/run_test_gates.sh groups`. |
| `3` | `Close the admin-role matrix rows with convergence proof and doc updates` | `implementation-ready` | `Test-Flight-Improv/59-post-creation-admin-role-management-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`, `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md` | Accepted on `2026-04-05` after landing authoritative membership-snapshot application, sender-side membership watermark persistence, multi-admin leave/convergence smoke proof, and the closure-doc refresh for `MR-016`, `MR-017`, `MR-018`, `MR-019`, `MR-021`, `UX-011`, `SC-013`, and `SC-014`, then verifying `flutter test test/features/groups/application/update_group_member_role_use_case_test.dart`, `flutter test test/features/groups/application/remove_group_member_use_case_test.dart`, `flutter test test/features/groups/application/group_message_listener_test.dart`, `flutter test test/features/groups/presentation/group_info_wired_test.dart`, `flutter test test/features/groups/integration/group_membership_smoke_test.dart`, and `./scripts/run_test_gates.sh groups`. |

## Pipeline progress

- `2026-04-05`: Session `1` moved to `accepted` after the doc-59 local
  pipeline fallback landed the core role-change contract and the required
  direct suites plus `baseline` and `groups` gates passed cleanly.
- `2026-04-05`: Session `2` moved to `accepted` after the shipped group-info
  surface gained promote/demote controls, repo-truth permission refresh, and
  direct presentation proof, with the `groups` gate passing cleanly.
- `2026-04-05`: Session `3` moved to `accepted` after the listener/use-case
  convergence contract started applying authoritative membership snapshots,
  acting peers started persisting the same membership watermark as recipients,
  the row-owned smoke/listener regressions passed, the maintained docs were
  refreshed, and `./scripts/run_test_gates.sh groups` passed cleanly.

## Final program verdict

- Status:
  `closed`
- Closed on:
  `2026-04-05`
- Closure summary:
  - doc `59` is now a landed product contract rather than unsupported scope
  - the repo ships post-creation admin promotion/demotion, multi-admin leave,
    and deterministic concurrent/conflicting admin-change convergence under
    authenticated authoritative snapshots plus persisted
    `lastMembershipEventAt`
  - the maintained audit and matrix docs now describe those rows as closed,
    and the unsupported-feature index no longer lists them
- Final verification:
  - `flutter test test/features/groups/application/update_group_member_role_use_case_test.dart`
  - `flutter test test/features/groups/application/remove_group_member_use_case_test.dart`
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
  - `./scripts/run_test_gates.sh groups`

## Ordered session breakdown

### Session 1

- Title:
  `Ship the role-change mutation contract and admin-continuity guards`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-1-plan.md`
- Exact scope:
  - create or tighten the application path that changes a member role after
    group creation and synchronizes the updated config/state to peers
  - enforce the caller/target guard rails for admin-only role changes,
    non-member rejection, and no leaderless-group outcome after demotion,
    revocation, or leave
  - make multi-admin leave use the landed continuity contract instead of the
    current sole-admin-only block path
  - persist or replay the authoritative role-change state through the existing
    group listener/config seam so peers converge on one final member/admin list
  - land narrow direct tests at the application/listener/integration layers for
    promote, demote, non-member rejection, and multi-admin leave correctness
- Why it is its own session:
  - this is the core correctness seam; it changes mutation rules, permission
    checks, and peer state propagation together
  - executing UI work before this seam lands would force the surface to guess
    at unsupported behavior
- Likely code-entry files:
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/group_membership_timeline_message.dart`
  - `lib/features/groups/domain/repositories/group_repository.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/domain/repositories/group_repository_impl.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
  - intentionally deferred to Session `3`:
    - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Expose admin-role management in the group info surface and timeline`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-2-plan.md`
- Exact scope:
  - add the post-creation admin-management controls to the existing group info
    member list without regressing add/remove-member behavior
  - surface the user-visible admin badge and action-state changes immediately
    after a landed role mutation, including the current user's own permissions
  - ship the product-visible timeline/system-event wording for role changes if
    the feature uses that surface to satisfy `MR-019`
  - confirm the UI blocks self-promotion and other unauthorized actions rather
    than exposing dead controls that silently fail
  - add widget/wired regressions for the visible action affordances, snackbars,
    confirmations, and state refresh after role changes
- Why it is its own session:
  - the UI/timeline surface is a separate verification seam from the core role
    mutation contract and has a different direct regression family
  - keeping it separate prevents one large mixed session from hiding whether a
    failure is in backend/admin logic or in the shipped surface behavior
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
  - `lib/features/groups/application/group_membership_timeline_message.dart`
  - `lib/features/groups/domain/models/group_member.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
  - intentionally deferred to Session `3`:
    - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Dependency on earlier sessions:
  - Session `1`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- Title:
  `Close the admin-role matrix rows with convergence proof and doc updates`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-3-plan.md`
- Exact scope:
  - add or tighten the exact regressions that close the doc-owned matrix rows,
    especially multi-admin leave plus the concurrent/conflicting admin-change
    outcomes in `SC-013` and `SC-014`
  - document the final explicit conflict-resolution and user-visible event
    contract that the landed code actually implements
  - update the maintained docs that currently mark this feature as unsupported
    so they align with the landed code/test truth
  - persist the finished doc verdict in this breakdown after the code, tests,
    and matrix docs all agree
- Why it is its own session:
  - the closure bar is broader than any single code edit: it requires final row
    evidence, matrix truth, and architecture/audit updates together
  - keeping this final proof pass separate avoids accepting the feature before
    the repo’s long-lived source-of-truth docs are corrected
- Likely code-entry files:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
  - `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
  - `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- Dependency on earlier sessions:
  - Session `1`
  - Session `2`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- One giant session would mix three different verification seams:
  mutation/authorization correctness, user-visible surface behavior, and final
  matrix/architecture closure. That would make regressions hard to localize and
  invite accepting incomplete doc truth.
- The current repo already has part of the lower-level membership convergence
  machinery, so the closure pass must explicitly verify and document the new
  admin-role rows rather than disappearing inside the feature implementation.

## Why this is not more sessions

- Promote, demote, and multi-admin leave share the same mutation/state-sync
  seam and the same group gate family, so splitting them into separate plans
  would be bookkeeping-heavy without independent verification value.
- A separate docs-only session is unnecessary because the doc truth depends on
  the exact convergence evidence that Session `3` must gather anyway.

## Regression and gate contract

- The direct regression focus is the groups feature family:
  `test/features/groups/application/group_message_listener_test.dart`,
  `test/features/groups/presentation/group_info_screen_test.dart`,
  `test/features/groups/presentation/group_info_wired_test.dart`, and
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- The named gate for landed code changes is:
  `./scripts/run_test_gates.sh groups`
- If the implementation touches shared startup/resume or notification routing
  while making admin-state refresh truthful, the session plan should name any
  additional direct suite explicitly instead of widening gates by assumption.

## Matrix update contract

- Update after implementation lands:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Session ownership:
  - Session `3` owns the matrix/audit/architecture closure because it is the
    first point where the final row truth can be asserted safely.
- Truthfulness rule:
  - only remove rows from unsupported scope when direct code-and-test evidence
    closes the row exactly
  - if the landed feature narrows any row contract, record that narrowing
    explicitly instead of overstating support

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- The proposal leaves flexibility on whether transfer-admin is a dedicated UI
  verb or a promote-plus-leave/demote contract; the implementation may choose
  the narrower surface as long as the supported journeys close truthfully.
- Exact timeline copy may change during implementation, but the shipped event
  contract must remain explicit and directly tested.

## Exact docs/files used as evidence

- `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The session set is the minimum safe split across distinct seams with distinct
  direct regressions.
- Every intended plan path is doc-scoped and non-colliding.
- The closure docs that still mark this feature unsupported are assigned
  explicitly instead of being left implicit for a later guess.
