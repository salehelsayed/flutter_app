# Session GM-008 Plan - Retry without duplicates

## Final verdict

`implementation-ready`

Current repo evidence shows row `GM-008` is close but not yet exact:

- `test/features/groups/integration/group_resume_recovery_test.dart` already
  has `failed message retry after network recovery`, which proves sender state
  goes from `failed` to `sent` after retry and Bob eventually receives the
  retried message.
- The same file also contains dedicated dedupe coverage for duplicate delivery
  by shared `messageId`.
- The matrix row still needs the exact 3-user contract: under retry after
  unstable connectivity, Bob and Charlie each show one copy and the sender
  state resolves cleanly.

The smallest safe session is therefore to tighten the existing retry-after-
recovery integration test to include Charlie and exact one-copy recipient
assertions.

## Final plan

### real scope

- Resolve source row `GM-008` only: `Retry without duplicates`.
- Prefer test-only changes in
  `test/features/groups/integration/group_resume_recovery_test.dart`.
- Touch production code only if the widened retry regression exposes a real
  repo bug.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into general restart, inbox cursor, or ordering work.

### closure bar

- There is direct automated proof that after an initial failed group send and a
  retry on network recovery, the sender's message resolves to `sent` and both
  Bob and Charlie each store exactly one incoming copy of that retried message.
- The direct retry proof passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves retry recovery and separate dedupe behavior, but the
  exact row contract is not yet pinned in one row-owned multi-recipient retry
  scenario.
- A 2-user retry proof is not enough for the current matrix row.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Production seams only if needed:
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### existing tests covering this area

- `group_resume_recovery_test.dart` already proves retry after recovery for one
  recipient and separately proves dedupe by shared `messageId`.
- Missing today:
  - a row-owned 3-user retry proof asserting one delivered copy per recipient

### regression/tests to add first

- Tighten `failed message retry after network recovery` so Charlie is also a
  group member and the final assertions prove Bob and Charlie each have exactly
  one incoming message with the retried message id.
- Only if that exposes a real bug, patch the minimal retry/send seam needed to
  satisfy it.

### step-by-step implementation plan

1. Re-read the live retry integration test and preserve unrelated edits.
2. Extend the retry-after-recovery scenario to include Charlie.
3. Assert sender status resolves to `sent` and both recipients each have one
   incoming copy of the retried message id.
4. Run the targeted retry integration proof.
5. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: separate retry and dedupe tests are not enough unless the row
  gets one combined multi-recipient proof.
- Scope risk: do not widen into general inbox-drain or restart rows.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'failed message retry after network recovery'`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat duplicate recipient copies, missing delivery to Bob or Charlie, or a
  final sender status other than `sent` as current-session blockers.

### done criteria

- `GM-008` has exact row-owned retry-without-duplicates proof.
- Any delta stays limited to the narrowest retry integration regression needed.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - adding new retry infrastructure
  - widening into general reconnect or restart validation
  - refactoring existing retry helpers for style

### accepted differences / intentionally out of scope

- `GM-008` does not require protocol-layer retransmit proof outside the current
  repo-owned integration seam.
- `GM-008` does not own later restart or inbox-cursor rows.

### dependency impact

- A truthful `GM-008` resolution reduces uncertainty for later offline and
  retry-adjacent rows, but it does not automatically close them.
