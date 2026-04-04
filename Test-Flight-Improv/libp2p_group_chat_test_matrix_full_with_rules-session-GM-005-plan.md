# Session GM-005 Plan - Reply fan-out

## Final verdict

`implementation-ready`

Current repo evidence shows row `GM-005` is close to covered but not yet exact:

- `test/features/groups/integration/group_messaging_smoke_test.dart` already
  has a `quoted reply propagates to all recipients` scenario, but it only uses
  Alice and Bob.
- `test/features/groups/application/send_group_message_use_case_test.dart`
  already verifies `quotedMessageId` survives publish, inbox, and local save.
- The source matrix row requires a 3-user group where B replies to A's message
  and both A and C receive that reply once with the correct parent reference.

The smallest safe session is therefore to widen the existing quote-propagation
smoke proof to include the third recipient and stop there.

## Final plan

### real scope

- Resolve source row `GM-005` only: `Reply fan-out`.
- Prefer test-only changes in
  `test/features/groups/integration/group_messaging_smoke_test.dart`.
- Touch production code only if the widened 3-user regression exposes a real
  repo bug in quote propagation.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into ordering, dedupe, retry, or restart work.

### closure bar

- There is direct automated proof that in a 3-user group, B replies to A's
  message and both A and C receive that reply exactly once with the correct
  `quotedMessageId`.
- Bob's local reply state remains correct.
- The direct tests below pass.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves quote metadata propagation, but the current smoke
  proof does not include the third recipient required by `GM-005`.
- Without that third recipient, the row cannot be truthfully called closed.
- This session should land only the narrowest multi-recipient quote-fan-out
  regression needed for the matrix contract.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Supporting direct send proof:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Production seam only if needed:
  - `lib/features/groups/application/send_group_message_use_case.dart`

### existing tests covering this area

- `group_messaging_smoke_test.dart` already proves quote propagation in a
  2-user group.
- `send_group_message_use_case_test.dart` already proves `quotedMessageId`
  survives the send seam.
- Missing today:
  - direct proof that the non-sender third member receives the quoted reply
    once with the correct parent id

### regression/tests to add first

- Tighten the existing quoted-reply smoke scenario to include Charlie as a
  third participant and assert:
  - Alice receives Bob's reply once with the correct `quotedMessageId`
  - Charlie receives Bob's reply once with the correct `quotedMessageId`
  - Bob keeps the local outgoing quoted reply with the same parent id
- Only if that regression exposes a real bug, patch the minimal production seam
  needed to satisfy it.

### step-by-step implementation plan

1. Re-read the live dirty worktree for the targeted smoke test so unrelated
   local edits are preserved.
2. Expand the quoted-reply smoke scenario from 2 users to 3 users.
3. Add exact assertions for Alice, Charlie, and Bob around the reply count and
   `quotedMessageId`.
4. Run the direct tests below.
5. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: a 2-user quote test is not enough for this row.
- Scope risk: do not reopen generic fan-out, dedupe, or ordering behavior.
- Dirty-worktree risk: preserve unrelated user edits already present.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat failure of the widened Charlie recipient assertions as a current-session
  blocker.
- If the direct send suite fails only in unrelated pre-existing tests, record
  that honestly and keep the session scoped to the quoted-reply seam.

### done criteria

- `GM-005` has exact row-owned 3-user proof for reply fan-out.
- Any code/test delta is limited to the narrowest quote-propagation seam.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - adding ordering, dedupe, or retry coverage
  - redesigning the group test harness
  - widening quote behavior beyond the current parent-id propagation contract
- Overengineering for this session would be building a new harness instead of
  extending the existing smoke scenario.

### accepted differences / intentionally out of scope

- `GM-005` does not require protocol-level quote validation or device-lab
  evidence.
- `GM-005` does not own notification rendering of quoted replies.

### dependency impact

- A truthful `GM-005` resolution reduces uncertainty for adjacent reply and
  send rows, but it does not automatically close ordering or dedupe sessions.
