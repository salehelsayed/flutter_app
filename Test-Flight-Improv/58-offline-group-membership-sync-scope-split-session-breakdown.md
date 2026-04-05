# 58 - Offline Group Membership Sync Scope Split Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `58` is closed only when the repo-owned offline-bystander reconnect
contract is separated cleanly from unsupported admin-role propagation:

- the maintained group matrices no longer mix supported offline bystander
  membership-list convergence with unsupported promotion/admin-transfer flows
- the supported reconnect contract closes only on existing repo proof for
  add/remove membership convergence, not on wishful future role-management
  behavior
- unsupported admin-role propagation stays explicit unsupported scope instead
  of being silently treated as a repo-owned failure
- the architecture note and matrix wording all tell the same truthful story
  about what the repo does and does not currently support
- direct evidence and the applicable group gate evidence are recorded

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

Current repo facts that govern the split:

- `test/features/groups/integration/group_resume_recovery_test.dart` already
  contains `offline member reconnects after membership churn and converges to
  the final member list`, which proves an offline bystander catches up to the
  supported add/remove member-list state after rejoin plus inbox drain.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` already closes
  `SC-007` and `UX-010` on that same reconnect/member-list convergence seam.
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  already keeps promotion and richer admin-role propagation explicit
  unsupported scope across rows such as `MR-016`, `MR-019`, and `MR-021`.
- The original gap was documentation truth: `MR-024` mixed supported offline
  bystander membership sync with unsupported admin-role propagation in one
  row before this session narrowed it to the landed reconnect seam.

Source-of-truth conflicts that materially affected decomposition:

- The proposal allows several split shapes, but current repo evidence already
  proves the supported add/remove reconnect seam, so the minimum safe move is
  to narrow `MR-024` to that landed contract rather than inventing new product
  rows or code work.
- The audit doc already records missing richer admin tooling, so this session
  should prefer reusing that unsupported-scope truth over creating duplicate
  fake feature obligations.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Split supported offline bystander membership sync from unsupported admin-role propagation` | `implementation-ready` | `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-1-plan.md` | none | `completed` | `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` | Completed on `2026-04-05`: `MR-024` now closes only the supported offline-bystander add/remove membership-sync seam, using the existing reconnect regression in `group_resume_recovery_test.dart` plus same-day `groups` gate evidence. Unsupported promotion/admin-transfer propagation remains explicit unsupported scope. |

## Ordered session breakdown

### Session 1

- Title:
  `Split supported offline bystander membership sync from unsupported admin-role propagation`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-1-plan.md`
- Exact scope:
  - narrow `MR-024` in the maintained group matrices to the landed offline
    bystander add/remove membership-sync contract
  - close that narrowed contract on the existing reconnect proof in
    `test/features/groups/integration/group_resume_recovery_test.dart`
  - update `Test-Flight-Improv/09-network-group-messaging.md` so the
    architecture note also states that supported offline membership churn
    converges for reconnecting bystanders
  - keep unsupported promotion/admin-transfer propagation explicit unsupported
    scope using the existing audit and matrix truth rather than inventing new
    product behavior
  - update this breakdown with the finished doc verdict once the docs and
    evidence align
- Why it is its own session:
  - the repo already has the needed reconnect proof, so this is one
    documentation-truth seam rather than new feature implementation
  - splitting the matrix rewrite from the architecture-note refresh would only
    create bookkeeping without a separate technical seam
- Likely code-entry files:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-breakdown.md`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-breakdown.md`
  - intentionally unchanged unless execution discovers contradiction:
    - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- A docs-only closure still needs one explicit session because the matrix row
  is currently untruthful and the report does not close until the maintained
  docs agree on the landed contract.

## Why this is not more sessions

- There is no new code seam or missing reconnect regression to justify a second
  implementation session.
- Unsupported admin-role propagation already has explicit unsupported scope in
  adjacent matrix rows, so a separate out-of-scope session would be redundant.

## Regression and gate contract

- Re-run the direct reconnect proof in
  `test/features/groups/integration/group_resume_recovery_test.dart`.
- Reuse same-day `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  evidence for the broader group gate because this session is docs-only and
  does not land new product code.

## Matrix update contract

- Update:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Session ownership:
  - Session `1` owns the split because this is one documentation-truth seam.
- Truthfulness rule:
  - close only the supported offline bystander add/remove member-list
    convergence seam
  - keep unsupported promotion/admin-transfer propagation explicit unsupported
    scope

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Promotion, demotion, and richer admin-transfer propagation remain outside the
  current repo-owned product scope.
- No new reconnect code is required if the existing proof already closes the
  supported membership-list convergence seam truthfully.

## Finished doc verdict

- Verdict date:
  `2026-04-05`
- Current doc status:
  `closed`
- Stop-policy result:
  `finish_current_doc_before_advancing` satisfied; batch is complete
- Closure basis:
  - `MR-024` no longer mixes supported offline bystander add/remove membership
    convergence with unsupported admin-role propagation
  - `Test-Flight-Improv/09-network-group-messaging.md`,
    `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, and
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    now tell the same truthful story about the landed reconnect seam
  - direct evidence passed in:
    `test/features/groups/integration/group_resume_recovery_test.dart`
  - same-day broader group evidence passed with:
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- Residual truth outside this doc's scope:
  - promotion, demotion, and richer admin-transfer propagation remain
    unsupported product scope
  - this doc closes only the supported offline bystander add/remove
    membership-list convergence seam

## Exact docs/files used as evidence

- `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The session set is the minimum safe slice: one documentation-truth pass that
  uses existing landed reconnect evidence instead of reopening product code.
