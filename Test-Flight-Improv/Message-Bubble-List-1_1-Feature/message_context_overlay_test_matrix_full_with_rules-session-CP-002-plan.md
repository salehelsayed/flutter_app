# Session CP-002 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.

## Final plan

### real scope

- Close source row CP-002 for "Copy happy path in the shared feed direct-thread host" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership for this session: tests only.

### closure bar

- Source row CP-002 is updated in Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md to Covered or Closed with exact file-and-test evidence.
- This session does not finish accepted while the matrix row still reads as open work or only implied coverage.

### source of truth

- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md
- Current code and repo-local tests beat stale prose when they disagree.

### session classification

- implementation-ready

### exact problem statement

- Copy happy path in the shared feed direct-thread host
- Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### files and repos to inspect next

- lib/features/conversation/presentation/widgets/message_context_overlay.dart
- lib/features/conversation/presentation/screens/conversation_screen.dart
- lib/features/feed/presentation/screens/feed_screen.dart
- test/features/conversation/presentation/widgets/message_context_overlay_test.dart
- test/features/conversation/presentation/screens/conversation_screen_test.dart
- test/features/feed/presentation/screens/feed_screen_test.dart

### existing tests covering this area

- Re-audit test/features/conversation/presentation/widgets/message_context_overlay_test.dart for exact row proof before adding new coverage.
- Re-audit test/features/conversation/presentation/screens/conversation_screen_test.dart for exact row proof before adding new coverage.
- Re-audit test/features/feed/presentation/screens/feed_screen_test.dart for exact row proof before adding new coverage.

### regression/tests to add first

- Add or tighten the smallest direct regression that proves the row-owned behavior before widening into broader seams.

### step-by-step implementation plan

1. Re-audit the listed direct tests and owning production files to confirm whether the row is already covered or still open.
2. Add the smallest missing code or test needed to close the row without merging it into adjacent sessions.
3. Run the exact direct tests and any named gates needed to prove the row, then update the matrix and ledger only after they pass.

### risks and edge cases

- copy_text_present_gate
- copy_local_only_invariant
- copy_host_parity
- No earlier session dependency was recorded, but refresh against landed code before execution anyway.

### exact tests and gates to run

- flutter test --no-pub test/features/conversation/presentation/widgets/message_context_overlay_test.dart
- flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart
- flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart
- Named gate: copy_text_present_gate
- Named gate: copy_local_only_invariant
- Named gate: copy_host_parity

### known-failure interpretation

- If the direct regression fails because the row is truly open, keep the session open or blocked and do not mark the matrix as covered.
- Ignore unrelated pre-existing failures outside the owning seam, but record them if they block direct proof.

### done criteria

- Repo-local evidence or newly landed code/tests prove the exact row contract.
- The source matrix row is updated with concrete evidence and this session ledger is refreshed accordingly.

### scope guard

- Do not collapse this row into a seam bucket or broad feature-status claim.
- Do not reopen unrelated product work, architecture changes, or non-owning sessions.

### accepted differences / intentionally out of scope

- Only the row-owned contract is in scope; neighboring matrix rows stay unchanged unless their own proof is directly affected and separately recorded.

### dependency impact

- Later sessions may reuse this row’s landed evidence, but they still need their own matrix updates and acceptance.

## Structural blockers remaining

- none recorded at plan creation time

## Incremental details intentionally deferred

- Broader parity or cross-row cleanup beyond the owning source row.

## Accepted differences intentionally left unchanged

- The session remains row-owned even when the same tests or files also matter to adjacent rows.

## Exact docs/files used as evidence

- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md
- lib/features/conversation/presentation/widgets/message_context_overlay.dart
- lib/features/conversation/presentation/screens/conversation_screen.dart
- lib/features/feed/presentation/screens/feed_screen.dart
- test/features/conversation/presentation/widgets/message_context_overlay_test.dart
- test/features/conversation/presentation/screens/conversation_screen_test.dart
- test/features/feed/presentation/screens/feed_screen_test.dart
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md

## Why the plan is safe or unsafe to implement now

- Safe because the breakdown already narrowed the seam, named the likely files/tests, and kept closure tied to an exact matrix row instead of a broad feature claim.
