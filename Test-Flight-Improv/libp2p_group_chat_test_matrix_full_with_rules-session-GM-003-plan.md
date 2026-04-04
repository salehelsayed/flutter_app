# Session GM-003 Plan - Online fan-out

## Final verdict

`acceptance-only`

Current repo evidence suggests row `GM-003` may already be proven exactly at
the repo-owned seam:

- `test/features/groups/integration/group_messaging_smoke_test.dart` now
  drives a live 3-user group where A sends one message after A/B/C have
  hydrated the same group state, then asserts B and C each receive the message
  and A retains the local outgoing copy.
- `test/features/groups/application/send_group_message_use_case_test.dart`
  already proves the local send path returns success and persists the sender's
  outgoing message.
- The row contract is narrower than resume, retry, or offline inbox recovery,
  so `group_resume_recovery_test.dart` is supporting context rather than the
  main proof target.

The safest session is therefore to verify whether the existing smoke and direct
send tests already satisfy `GM-003`, tighten the proof only if an exact row
gap remains, and otherwise close the row with evidence only.

## Final plan

### real scope

- Resolve source row `GM-003` only: `Online fan-out`.
- Prefer no production code changes.
- Touch `test/features/groups/integration/group_messaging_smoke_test.dart`
  only if the current assertions do not quite prove the row contract.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into exactly-once display, reply threading, sequential ordering,
  resume recovery, offline bootstrap, or notification behavior.

### closure bar

- There is direct automated proof that, with A/B/C online in the same group,
  one message sent by A is received by both B and C.
- The proof also shows A gets the expected local success state for the send
  path, rather than waiting only on recipient assertions.
- The direct tests below pass.
- `groups` gate results are recorded honestly if the touched-file scope still
  requires them.

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
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`acceptance-only`

### exact problem statement

- The matrix row needs row-owned proof for online fan-out, not just broad
  family-level group coverage.
- The current tree appears to already prove the behavior, but the row is still
  unclassified in the matrix and breakdown.
- This session should only add or tighten assertions if the existing smoke test
  falls short of the exact row contract.

### files and repos to inspect next

- Primary proof target:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Supporting direct send contract:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Supporting implementation seam:
  - `lib/features/groups/application/send_group_message_use_case.dart`
- Context only if needed:
  - `test/features/groups/integration/group_resume_recovery_test.dart`

### existing tests covering this area

- `group_messaging_smoke_test.dart` already includes a 3-user online send where
  B and C each receive A's message and A keeps the local outgoing record.
- `send_group_message_use_case_test.dart` already verifies local success for
  the sender path.
- Missing only if audit proves it:
  - an explicit row-owned note tying the existing assertions to `GM-003`

### regression/tests to add first

- First try to close the row without new test code by verifying the current
  smoke scenario already proves:
  - B receives A's message
  - C receives A's message
  - A sees the local successful outgoing state
- Only if that evidence is ambiguous, add the narrowest assertion or reason
  comment needed in `group_messaging_smoke_test.dart`.

### step-by-step implementation plan

1. Re-read the live dirty worktree for the targeted test and docs so unrelated
   local edits are preserved.
2. Audit the current first smoke scenario and direct send tests against the
   exact `GM-003` row contract.
3. If the row is already proven, avoid code changes and move straight to direct
   test verification plus doc refresh.
4. If the proof is not exact enough, add the narrowest missing assertion in
   the smoke test and stop.
5. Run the direct tests and any still-required named gate.
6. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: broad group-messaging coverage is not enough unless the
  sender-success and recipient fan-out are both explicit.
- Scope risk: do not reopen dedupe, ordering, or retry behavior from adjacent
  rows just because the same smoke suite touches them.
- Dirty-worktree risk: preserve unrelated local changes already present in the
  repo.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh groups` only if the final touched-file scope
    still justifies a named gate rerun
- Do not run `baseline` or `transport` unless production code or lifecycle
  wiring changes unexpectedly.

### known-failure interpretation

- Treat failure of the online fan-out assertions or sender-local-success checks
  as a current-session blocker.
- If `groups` fails only in unrelated pre-existing suites, record the exact
  failures and keep `GM-003` scoped to whether its direct proof is green.

### done criteria

- `GM-003` has exact row-owned evidence in repo-local tests.
- Any code/test delta is limited to the narrowest proof needed for online
  fan-out.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - adding new transport or resume coverage
  - reopening create/bootstrap assertions from `GM-001`
  - bundling dedupe, reply, ordering, or notification behavior into this row
- Overengineering for this session would be adding new harnesses or widening
  beyond the already-landed online fan-out seam.

### accepted differences / intentionally out of scope

- `GM-003` does not require ciphertext proof, raw protocol validation, or
  device-lab evidence.
- `GM-003` does not own offline bootstrap, retry, or resume recovery rows.

### dependency impact

- A truthful `GM-003` resolution informs adjacent core-messaging rows, but it
  does not automatically close dedupe, reply, or ordering sessions.
- If `GM-003` unexpectedly needs product-code changes, later messaging rows
  should be refreshed against that result before they are closed.
