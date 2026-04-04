# Session GM-013 Plan - Mixed delivery paths

## Final verdict

`acceptance-only`

Current repo evidence suggests row `GM-013` is already proven at the repo-owned
delivery seam:

- the tightened `partial delivery with inbox drain completion` scenario in
  `test/features/groups/integration/group_resume_recovery_test.dart` already
  covers one live online recipient plus offline inbox-backed recipients for the
  same group message
- that scenario now proves the online reader receives the message before inbox
  drain and the offline readers each receive exactly one copy after inbox drain
- this row is narrower than restart or notification work; it only needs
  truthful mixed-path delivery classification

The safest session is therefore to reuse that direct integration proof on the
current repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `GM-013` only: `Mixed delivery paths`.
- Prefer no production or test edits.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into retry, restart, or transport-implementation redesign.

### closure bar

- There is direct automated proof that one recipient receives the message via
  the live path while another receives the same message once via inbox/store-
  and-forward completion.
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

- The repo already appears to prove mixed live and inbox-backed delivery, but
  the row is still unclassified in the matrix and breakdown.
- This session should not add new tests unless the current partial-delivery
  evidence turns out to be insufficient.

### files and repos to inspect next

- Primary proof target:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Supporting production seam:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

### existing tests covering this area

- `partial delivery with inbox drain completion` already spans the exact mixed
  live + inbox seam.
- Missing only if audit proves it:
  - a row-owned closure note tying that proof to `GM-013`

### regression/tests to add first

- First try to close the row without edits by rerunning the current
  partial-delivery integration proof on the repo state that includes the
  tightened GM-009 assertions.
- Only if that proof is ambiguous, add the narrowest row-owned assertion needed.

### step-by-step implementation plan

1. Re-read the current partial-delivery proof and confirm it still matches the
   mixed-path row contract.
2. Rerun the targeted proof on the current repo state.
3. If it stays exact and green, move straight to doc refresh.
4. Only if a gap appears, add the narrowest missing assertion and stop.

### risks and edge cases

- Overclaim risk: do not reopen broader transport-path architecture beyond the
  direct row-owned proof.
- Scope risk: do not widen into restart or retry semantics.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat missing live delivery, missing inbox delivery, or duplicate mixed-path
  delivery as current-session blockers.

### done criteria

- `GM-013` has exact row-owned mixed-path proof.
- No broader transport behavior is reopened.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - transport redesign
  - multi-page backlog coverage
  - restart or notification behavior

### accepted differences / intentionally out of scope

- `GM-013` does not claim protocol-level direct-vs-relay instrumentation.
- `GM-013` does not own restart recovery or partial-fanout acceptance wording.

### dependency impact

- A truthful `GM-013` resolution informs `GM-014`, but it does not
  automatically close other transport-adjacent rows.
