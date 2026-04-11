# Session DL-006 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.

## Final plan

### real scope

- Close source row DL-006 for "“Delete for everyone” happy path over live delivery converges on both sides" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership for this session: no execution because already covered.

### closure bar

- Source row DL-006 is updated in Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md to Covered or Closed with exact file-and-test evidence.
- This session does not finish accepted while the matrix row still reads as open work or only implied coverage.

### source of truth

- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md
- Current code and repo-local tests beat stale prose when they disagree.

### session classification

- stale/already-covered

### exact problem statement

- “Delete for everyone” happy path over live delivery converges on both sides
- Exact repo proof exists for online delete-for-everyone sender hide plus receiver-side tombstone convergence.

### files and repos to inspect next

- lib/features/conversation/presentation/screens/conversation_screen.dart
- lib/features/feed/presentation/screens/feed_screen.dart
- lib/features/conversation/application/delete_message_use_case.dart
- lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart
- lib/features/conversation/application/delete_message_tombstone_visibility.dart
- lib/features/conversation/domain/models/conversation_message.dart
- lib/features/conversation/domain/repositories/message_repository_impl.dart
- test/features/conversation/integration/message_deletion_roundtrip_test.dart:42

### existing tests covering this area

- Re-audit test/features/conversation/integration/message_deletion_roundtrip_test.dart:42 for exact row proof before adding new coverage.

### regression/tests to add first

- No new regression should be added until the existing repo-local proof is re-confirmed and linked into the matrix.

### step-by-step implementation plan

1. Re-audit the listed direct tests and owning production files to confirm whether the row is already covered or still open.
2. If the row is exactly covered, update the source matrix with concrete file-and-test evidence and then refresh the session ledger.
3. Run the exact direct tests and any named gates needed to prove the row, then update the matrix and ledger only after they pass.

### risks and edge cases

- delete_overlay_gate
- delete_for_everyone_gate
- owned_path_cleanup_guard
- outgoing_tombstone_visibility
- startup_delete_before_render
- No earlier session dependency was recorded, but refresh against landed code before execution anyway.

### exact tests and gates to run

- flutter test --no-pub test/features/conversation/integration/message_deletion_roundtrip_test.dart:42
- Named gate: delete_overlay_gate
- Named gate: delete_for_everyone_gate
- Named gate: owned_path_cleanup_guard
- Named gate: outgoing_tombstone_visibility
- Named gate: startup_delete_before_render

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
- lib/features/conversation/presentation/screens/conversation_screen.dart
- lib/features/feed/presentation/screens/feed_screen.dart
- lib/features/conversation/application/delete_message_use_case.dart
- lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart
- lib/features/conversation/application/delete_message_tombstone_visibility.dart
- lib/features/conversation/domain/models/conversation_message.dart
- lib/features/conversation/domain/repositories/message_repository_impl.dart
- test/features/conversation/integration/message_deletion_roundtrip_test.dart:42
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md

## Why the plan is safe or unsafe to implement now

- Safe because the breakdown already narrowed the seam, named the likely files/tests, and kept closure tied to an exact matrix row instead of a broad feature claim.
