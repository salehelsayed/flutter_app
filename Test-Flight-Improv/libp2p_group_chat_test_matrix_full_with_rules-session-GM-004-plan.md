# Session GM-004 Plan - Exactly-once display

## Final verdict

`acceptance-only`

Current repo evidence suggests row `GM-004` is already proven at the
repo-owned seam:

- the opening scenario in
  `test/features/groups/integration/group_messaging_smoke_test.dart` sends one
  group message from A after A/B/C have hydrated the same group, then asserts
  B sees exactly one incoming copy and C sees exactly one incoming copy
- the same scenario also confirms A stores only the one local outgoing copy for
  that send, which makes duplicate fan-out or duplicate local persistence
  visible in the same proof
- no product code changes are indicated by the current repo state; the likely
  missing work is only row-owned classification and closure

The safest session is therefore to verify the existing smoke proof is exact for
`GM-004`, avoid new code unless a real gap appears, and otherwise close the row
with evidence only.

## Final plan

### real scope

- Resolve source row `GM-004` only: `Exactly-once display`.
- Prefer no production or test edits.
- Touch `test/features/groups/integration/group_messaging_smoke_test.dart`
  only if the current assertions are not exact enough to prove one-copy display
  for recipients.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into reply behavior, ordering, retry, notification, or
  offline/rejoin work.

### closure bar

- There is direct automated proof that one send from A yields exactly one
  displayed incoming message for B and exactly one displayed incoming message
  for C.
- The proof does not rely on broad messaging-family claims; it points to a
  row-owned deterministic scenario.
- The direct proof remains green on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`acceptance-only`

### exact problem statement

- The matrix row needs explicit row-owned proof that recipients do not display
  duplicate copies from one send.
- The current smoke scenario appears to prove that already, but the row is not
  yet marked covered in the matrix and breakdown.
- This session should add assertions only if the existing one-message counts do
  not truthfully satisfy the exact row contract.

### files and repos to inspect next

- Primary proof target:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Supporting send seam only if needed:
  - `lib/features/groups/application/send_group_message_use_case.dart`

### existing tests covering this area

- `group_messaging_smoke_test.dart` already checks that after one send, Bob has
  exactly one incoming message and Charlie has exactly one incoming message.
- Missing only if audit proves it:
  - a row-owned doc note tying the existing counts to `GM-004`

### regression/tests to add first

- First try to close the row without new test code by reusing the current
  smoke proof on the unchanged repo state.
- Only if the evidence is ambiguous, add the narrowest assertion or comment
  needed to make the one-copy contract explicit.

### step-by-step implementation plan

1. Re-read the current smoke scenario and confirm it still proves one-copy
   recipient display on the current repo state.
2. Reuse the already-verified direct smoke result if no GM-004-specific code or
   test delta is needed.
3. If a proof gap appears, add only the narrowest missing assertion in the
   smoke suite.
4. Update the matrix row note and breakdown ledger only after the evidence is
   verified.

### risks and edge cases

- Overclaim risk: do not treat general message delivery as sufficient unless
  the counts stay exactly one for both recipients.
- Scope risk: do not reopen ordering or reply rows just because the same smoke
  suite covers them nearby.
- Dirty-worktree risk: preserve unrelated user edits.

### exact tests and gates to run

- Direct proof:
  - reuse the current successful run of
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
    because no GM-004-specific code or test delta is planned beyond doc updates
- Named gates:
  - none unless a GM-004-specific code or test delta lands

### known-failure interpretation

- Treat any mismatch in the one-copy recipient counts as a current-session
  blocker.
- If later verification reveals new code/test changes before closure, rerun the
  smoke suite and record the updated result honestly.

### done criteria

- `GM-004` has exact row-owned evidence for one-copy recipient display.
- No broader behavior is reopened.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - adding retry, ordering, reply, or notification coverage
  - changing product code without a direct duplicate-display regression
- Overengineering for this session would be building new dedupe harnesses when
  the existing smoke proof already satisfies the row.

### accepted differences / intentionally out of scope

- `GM-004` does not require protocol-layer duplicate rejection proof or
  cross-device notification dedupe evidence.
- `GM-004` does not own retry or replay semantics after reconnect.

### dependency impact

- A truthful `GM-004` resolution narrows uncertainty for adjacent messaging
  rows, but it does not automatically close reply or ordering sessions.
