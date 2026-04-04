# Session GM-012 Plan - App restart recovery

## Final verdict

`implementation-ready`

Current repo evidence shows row `GM-012` is close but not yet exact:

- `test/features/groups/integration/group_messaging_smoke_test.dart` already
  has `message is received after app restart with rejoin`, which proves Bob can
  receive a pre-restart and post-restart message around a rejoin flow.
- The row still needs explicit proof that the restarted thread state remains
  consistent for history count, unread count, and latest-message preview/summary.

The smallest safe session is therefore to tighten the existing restart smoke
scenario with summary and unread assertions instead of building a broader UI
restart harness.

## Final plan

### real scope

- Resolve source row `GM-012` only: `App restart recovery`.
- Prefer test-only changes in
  `test/features/groups/integration/group_messaging_smoke_test.dart`.
- Touch production code only if the tightened restart regression exposes a real
  repo bug.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into startup lifecycle redesign or notification-open work.

### closure bar

- There is direct automated proof that after the simulated restart/rejoin flow:
  - prior and new messages both remain in history
  - the unread count is consistent with the incoming messages
  - the latest thread summary points at the post-restart message
- The direct restart smoke proof passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/shared/fakes/in_memory_group_message_repository.dart`
  - `lib/features/groups/application/rejoin_group_topics_use_case.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves live delivery after rejoin, but the row is not fully
  closed until the restart path also pins history and summary consistency.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Supporting repository summary seam:
  - `test/shared/fakes/in_memory_group_message_repository.dart`
- Production seam only if needed:
  - `lib/features/groups/application/rejoin_group_topics_use_case.dart`

### existing tests covering this area

- The current restart smoke scenario proves Bob receives both messages across
  the rejoin boundary.
- Missing today:
  - explicit message-count, unread-count, and latest-summary assertions after
    restart

### regression/tests to add first

- Tighten the existing restart smoke scenario to assert:
  - two persisted incoming messages after restart
  - unread count remains `2`
  - latest thread summary points to `After restart`
- Only if that exposes a real bug, patch the minimal restart/rejoin seam needed
  to satisfy it.

### step-by-step implementation plan

1. Re-read the current restart smoke scenario and preserve unrelated edits.
2. Add summary and unread assertions after the post-restart send.
3. Run the direct smoke suite.
4. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: live delivery after rejoin is not enough unless the
  persisted-thread summary state also stays correct.
- Scope risk: do not widen into full widget restart harnesses or notification
  routing.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat missing history rows, wrong unread count, or stale latest-summary text
  after restart as current-session blockers.

### done criteria

- `GM-012` has exact row-owned restart recovery proof.
- Any delta stays limited to the narrowest restart smoke regression needed.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - adding a full widget/app restart harness
  - widening into startup orchestration changes
  - reopening notification or background-fetch behavior

### accepted differences / intentionally out of scope

- `GM-012` does not claim a device-lab cold-start proof.
- `GM-012` does not own notification-open preparation.

### dependency impact

- A truthful `GM-012` resolution reduces uncertainty for later restart/resume
  rows, but it does not automatically close notification or mixed-path rows.
