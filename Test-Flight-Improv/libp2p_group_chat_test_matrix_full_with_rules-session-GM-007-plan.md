# Session GM-007 Plan - Simultaneous send

## Final verdict

`implementation-ready`

Current repo evidence shows row `GM-007` is not yet pinned exactly:

- `test/features/groups/integration/group_messaging_smoke_test.dart` already
  proves sequential multi-user sends via the round-robin scenario, but that is
  not the same as A and B sending at nearly the same time.
- No current row-owned smoke proof explicitly asserts that C receives both
  near-simultaneous sends without loss or merge corruption.

The smallest safe session is therefore to add one focused simultaneous-send
smoke scenario and stop there.

## Final plan

### real scope

- Resolve source row `GM-007` only: `Simultaneous send`.
- Prefer test-only changes in
  `test/features/groups/integration/group_messaging_smoke_test.dart`.
- Touch production code only if the new simultaneous-send regression exposes a
  real repo bug.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into ordering, retry, dedupe, or restart work.

### closure bar

- There is direct automated proof that when A and B send nearly at the same
  time in the same group, C receives both messages and they remain distinct.
- The direct smoke proof passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already covers multi-user fan-out, but the matrix row specifically
  requires near-simultaneous send proof.
- Sequential sends are not enough to truthfully close the row.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Production seam only if needed:
  - `lib/features/groups/application/send_group_message_use_case.dart`

### existing tests covering this area

- `group_messaging_smoke_test.dart` has strong sequential and round-robin
  coverage.
- Missing today:
  - a row-owned simultaneous-send assertion proving C receives both messages
    distinctly

### regression/tests to add first

- Add a 3-user simultaneous-send smoke scenario where Alice and Bob send via
  `Future.wait` and Charlie is asserted to receive both messages exactly once.
- Only if that regression exposes a real product bug, patch the minimal
  production seam needed to satisfy it.

### step-by-step implementation plan

1. Re-read the live smoke test file and preserve unrelated edits.
2. Add the smallest simultaneous-send scenario that exercises A/B concurrent
   sends into the same group.
3. Assert Charlie receives both distinct messages without loss or merge.
4. Run the direct smoke suite.
5. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: sequential fan-out is not a substitute for simultaneous-send
  proof.
- Scope risk: do not broaden into ordering or retry semantics.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat loss of one message, merged text, or duplicate recipient state in the
  simultaneous-send scenario as a current-session blocker.

### done criteria

- `GM-007` has exact row-owned simultaneous-send proof.
- Any delta stays limited to the narrowest multi-user smoke regression needed.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - adding ordering assertions
  - adding retry or duplicate-delivery coverage
  - redesigning the fake group harness

### accepted differences / intentionally out of scope

- `GM-007` does not require protocol-level race proof beyond the repo-owned
  smoke seam.
- `GM-007` does not own sender ordering or resume behavior.

### dependency impact

- A truthful `GM-007` resolution reduces uncertainty for later retry and
  ordering rows, but it does not automatically close them.
