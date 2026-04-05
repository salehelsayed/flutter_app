# 58 Session 1 Plan: Split Supported Offline Bystander Membership Sync From Unsupported Admin-Role Propagation

## Final verdict

`implementation-ready`

## Real scope

- Narrow `MR-024` in the maintained group matrices so it covers only the
  landed offline bystander reconnect contract for supported add/remove
  membership-list changes.
- Close that narrowed row on the existing reconnect proof in
  `test/features/groups/integration/group_resume_recovery_test.dart`.
- Update `Test-Flight-Improv/09-network-group-messaging.md` so the
  architecture note also states that supported offline membership churn
  converges for reconnecting bystanders.
- Keep unsupported promotion/admin-transfer propagation explicit unsupported
  scope rather than silently turning it into a repo-owned failure or feature
  commitment.

## Closure bar

Session `1` is good enough only when all of the following are true:

- `MR-024` no longer mixes supported offline membership-list convergence with
  unsupported admin-role propagation
- the narrowed row closes only on direct repo proof for reconnecting
  bystanders after supported add/remove membership churn
- unsupported promotion/admin-transfer propagation remains explicit unsupported
  scope in the maintained docs
- `Test-Flight-Improv/09-network-group-messaging.md`,
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` all
  tell the same final story

## Source of truth

- Active task docs:
  - `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
  - `Test-Flight-Improv/58-offline-group-membership-sync-scope-split-session-breakdown.md`
- Governing docs:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Existing direct evidence:
  - `test/features/groups/integration/group_resume_recovery_test.dart`

On disagreement, the landed reconnect regression and current supported product
scope beat stale mixed-row prose.

## Exact problem statement

The repo already has direct proof that an offline bystander reconnects after
supported membership churn and converges to the final member list. The open
problem is that `MR-024` still asks for both that supported behavior and
unsupported promotion/admin-role propagation in one row, which makes the
closure story untruthful.

What must improve:

- the matrix wording must separate supported offline bystander membership sync
  from unsupported admin-role propagation

What must stay true:

- supported add/remove reconnect convergence stays closed on actual evidence
- unsupported promotion/admin-transfer propagation remains unsupported scope
- no new reconnect code or role-management feature is invented

## Files and docs to inspect next

- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## Existing tests covering this area

- `test/features/groups/integration/group_resume_recovery_test.dart` already
  contains `offline member reconnects after membership churn and converges to
  the final member list`, which is the exact supported reconnect seam this
  session needs.
- `SC-007` and `UX-010` are already closed in the in-scope matrix on the same
  reconnect/member-list convergence behavior.
- Unsupported admin-role propagation already remains explicit unsupported scope
  in rows such as `MR-016`, `MR-019`, and `MR-021`.

## Regression/tests to run

- Run:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- Record same-day broader gate evidence from:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

## Step-by-step implementation plan

1. Create the doc-scoped breakdown and plan artifacts.
2. Rewrite `MR-024` in both maintained matrices so it describes only supported
   offline bystander member-list convergence after add/remove churn.
3. Update the architecture note to say the same thing and explicitly leave
   richer admin-role propagation unsupported.
4. Re-run the direct reconnect regression.
5. Update the breakdown with the completed session result and finished doc
   verdict once the docs and evidence agree.

## Risks and edge cases

- Do not overclaim unsupported promotion/admin-transfer propagation just
  because the old row wording mentioned it.
- Do not widen into code changes unless the direct reconnect proof fails.
- Do not duplicate unsupported-scope rows unnecessarily when the current
  matrices already record those gaps elsewhere.

## Exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- Named gates:
  - reuse same-day `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
    evidence because this session is docs-only

## Known-failure interpretation

- Treat failure in `group_resume_recovery_test.dart` as a blocker that reopens
  the assumption that the supported reconnect seam is already proved.
- Treat unrelated dirty-worktree or macOS warning output as non-blocking unless
  the reconnect regression itself fails.

## Done criteria

- the maintained docs no longer mix supported offline member-list convergence
  with unsupported admin-role propagation
- the narrowed reconnect contract is closed on direct evidence
- the breakdown records a finished doc verdict with truthful residual scope

## Scope guard

- Do not invent promotion, demotion, or admin-transfer features.
- Do not touch group listener or inbox-drain production code unless the direct
  reconnect test disproves the current closure claim.
- Do not widen into unrelated notification, startup, or transport work.
