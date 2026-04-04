# Session GM-014 Plan - Partial fan-out

## Final verdict

`acceptance-only`

Current repo evidence suggests row `GM-014` is already proven at the
repo-owned delivery seam:

- the tightened `partial delivery with inbox drain completion` scenario in
  `test/features/groups/integration/group_resume_recovery_test.dart` already
  proves the send returns success even when some recipients are offline
- the same scenario proves the reachable reader gets the message immediately
  while the unreachable readers get exactly one copy later through inbox drain
- this row is narrower than transport internals; it only needs truthful
  partial-fanout acceptance wording

The safest session is therefore to reuse that direct integration proof on the
current repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `GM-014` only: `Partial fan-out`.
- Prefer no production or test edits.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into retry, restart, or transport redesign work.

### closure bar

- There is direct automated proof that the send is not marked failed just
  because one recipient is unreachable, reachable readers receive immediately,
  and unreachable readers receive later through inbox completion when
  supported.
- The direct partial-delivery proof passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

### session classification

`acceptance-only`

### exact problem statement

- The repo appears to already prove partial fan-out success semantics, but the
  row is still unclassified in the matrix and breakdown.
- This session should not add new tests unless the current partial-delivery
  evidence turns out to be insufficient.

### files and repos to inspect next

- Primary proof target:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Supporting production seam:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

### existing tests covering this area

- `partial delivery with inbox drain completion` already spans the exact
  reachable-now / unreachable-later seam.
- Missing only if audit proves it:
  - a row-owned closure note tying that proof to `GM-014`

### regression/tests to add first

- First try to close the row without edits by reusing the current passing
  partial-delivery proof on the unchanged repo state.
- Only if that proof is ambiguous, add the narrowest row-owned assertion needed.

### step-by-step implementation plan

1. Re-read the current partial-delivery proof and confirm it still matches the
   partial-fanout row contract.
2. Reuse the current accepted validation on the unchanged repo state.
3. If it stays exact, move straight to doc refresh.
4. Only if a gap appears, add the narrowest missing assertion and stop.

### risks and edge cases

- Overclaim risk: do not reopen transport internals beyond the direct row-owned
  success semantics already proven.
- Scope risk: do not widen into retry or restart semantics.

### exact tests and gates to run

- Direct tests:
  - reuse the current passing validation:
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat sender failure, missing immediate delivery to reachable peers, or
  missing later delivery to unreachable peers as current-session blockers.

### done criteria

- `GM-014` has exact row-owned partial-fanout proof.
- No broader transport behavior is reopened.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - transport redesign
  - retry semantics
  - restart or notification behavior

### accepted differences / intentionally out of scope

- `GM-014` does not claim protocol-level transport diagnostics.
- `GM-014` does not own retry-without-duplicates semantics.

### dependency impact

- A truthful `GM-014` resolution reduces uncertainty for later sender-state
  rows, but it does not automatically close `GM-015`.
