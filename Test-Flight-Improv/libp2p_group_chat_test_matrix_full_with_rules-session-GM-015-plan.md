# Session GM-015 Plan - Sender disconnected behavior

## Final verdict

`acceptance-only`

Current repo evidence suggests row `GM-015` is already proven across the
repo-owned send-failure and retry-recovery seams:

- `test/features/groups/application/send_group_message_use_case_test.dart`
  already proves publish failure returns `error`, persists the message as
  `failed`, and does not falsely mark it `sent`.
- `test/features/groups/integration/group_resume_recovery_test.dart` already
  proves a failed message can later retry successfully without creating
  duplicate recipient copies.
- Together, these cover the row's sender-disconnect contract closely enough
  that the likely remaining work is row-owned classification, not new code.

The safest session is therefore to rerun the direct failure and retry proofs on
the current repo state and close the row with evidence only if they remain
green.

## Final plan

### real scope

- Resolve source row `GM-015` only: `Sender disconnected behavior`.
- Prefer no production or test edits.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into general retry policy or transport redesign.

### closure bar

- There is direct automated proof that a send failure leaves the sender in a
  clear failed state instead of a false `sent` state.
- There is direct automated proof that later recovery does not create ghost
  duplicates for recipients.
- The direct proofs pass on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`

### session classification

`acceptance-only`

### exact problem statement

- The repo appears to already prove the sender-disconnect contract, but the row
  is still unclassified in the matrix and breakdown.
- This session should not add new tests unless the current failure/recovery
  evidence turns out to be insufficient.

### files and repos to inspect next

- Primary proof targets:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Supporting production seams:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`

### existing tests covering this area

- `persists explicit inbox success when publish fails` already proves failed
  state persistence on publish failure.
- `failed message retry after network recovery` already proves later recovery
  without duplicate recipient copies.
- Missing only if audit proves it:
  - a row-owned closure note tying those proofs to `GM-015`

### regression/tests to add first

- First try to close the row without edits by rerunning the existing failure
  and retry proofs on the current repo state.
- Only if those proofs are ambiguous, add the narrowest row-owned assertion
  needed.

### step-by-step implementation plan

1. Re-read the current failure and retry proofs and confirm they still match
   the row contract.
2. Rerun the targeted proof commands on the current repo state.
3. If they stay exact and green, move straight to doc refresh.
4. Only if a gap appears, add the narrowest missing assertion and stop.

### risks and edge cases

- Overclaim risk: do not widen this row into general retry policy beyond the
  current direct failure/recovery proofs.
- Scope risk: do not reopen other mixed-path or restart rows.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'persists explicit inbox success when publish fails'`
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'failed message retry after network recovery'`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat false `sent` state on publish failure or duplicate recipient copies
  after recovery as current-session blockers.

### done criteria

- `GM-015` has exact row-owned sender-disconnect proof.
- No broader retry/transport behavior is reopened.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - transport redesign
  - retry queue redesign
  - mixed-path or restart coverage beyond the current row contract

### accepted differences / intentionally out of scope

- `GM-015` does not claim device-lab disconnect instrumentation.
- `GM-015` does not own partial-fanout or offline-recipient rows.

### dependency impact

- A truthful `GM-015` resolution finishes the current P0 core messaging block
  but does not automatically close later P1 rows.
