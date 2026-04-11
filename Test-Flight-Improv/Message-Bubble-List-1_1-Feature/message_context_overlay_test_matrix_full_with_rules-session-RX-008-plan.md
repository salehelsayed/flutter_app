# Session RX-008 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.

## Final plan

### real scope

- Close source row RX-008 for "Plaintext, tampered, or undecryptable reactions are rejected without local mutation" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership for this session: no execution because already covered.

### closure bar

- Source row RX-008 is updated in Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md to Covered or Closed with exact file-and-test evidence.
- This session does not finish accepted while the matrix row still reads as open work or only implied coverage.

### source of truth

- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md
- Current code and repo-local tests beat stale prose when they disagree.

### session classification

- stale/already-covered

### exact problem statement

- Plaintext, tampered, or undecryptable reactions are rejected without local mutation
- Exact repo proof exists for rejecting plaintext and undecryptable reaction envelopes without applying local mutation.

### files and repos to inspect next

- lib/features/conversation/presentation/widgets/reaction_bar.dart
- lib/features/conversation/presentation/widgets/reaction_display.dart
- lib/features/conversation/application/send_reaction_use_case.dart
- lib/features/conversation/application/remove_reaction_use_case.dart
- lib/features/conversation/application/handle_incoming_reaction_use_case.dart
- lib/features/conversation/application/reaction_listener.dart
- lib/features/conversation/domain/repositories/reaction_repository_impl.dart
- lib/core/database/helpers/reactions_db_helpers.dart
- test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:77
- test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:98
- test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:117

### existing tests covering this area

- Re-audit test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:77 for exact row proof before adding new coverage.
- Re-audit test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:98 for exact row proof before adding new coverage.
- Re-audit test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:117 for exact row proof before adding new coverage.

### regression/tests to add first

- No new regression should be added until the existing repo-local proof is re-confirmed and linked into the matrix.

### step-by-step implementation plan

1. Re-audit the listed direct tests and owning production files to confirm whether the row is already covered or still open.
2. If the row is exactly covered, update the source matrix with concrete file-and-test evidence and then refresh the session ledger.
3. Run the exact direct tests and any named gates needed to prove the row, then update the matrix and ledger only after they pass.

### risks and edge cases

- reaction_non_deleted_gate
- reaction_toggle_replace
- reaction_sender_auth
- reaction_decrypt_gate
- reaction_listener_lifecycle
- No earlier session dependency was recorded, but refresh against landed code before execution anyway.

### exact tests and gates to run

- flutter test --no-pub test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:77
- flutter test --no-pub test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:98
- flutter test --no-pub test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:117
- Named gate: reaction_non_deleted_gate
- Named gate: reaction_toggle_replace
- Named gate: reaction_sender_auth
- Named gate: reaction_decrypt_gate
- Named gate: reaction_listener_lifecycle

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
- lib/features/conversation/presentation/widgets/reaction_bar.dart
- lib/features/conversation/presentation/widgets/reaction_display.dart
- lib/features/conversation/application/send_reaction_use_case.dart
- lib/features/conversation/application/remove_reaction_use_case.dart
- lib/features/conversation/application/handle_incoming_reaction_use_case.dart
- lib/features/conversation/application/reaction_listener.dart
- lib/features/conversation/domain/repositories/reaction_repository_impl.dart
- lib/core/database/helpers/reactions_db_helpers.dart
- test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:77
- test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:98
- test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:117
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md

## Why the plan is safe or unsafe to implement now

- Safe because the breakdown already narrowed the seam, named the likely files/tests, and kept closure tied to an exact matrix row instead of a broad feature claim.
