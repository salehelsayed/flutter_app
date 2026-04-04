# Session GM-009 Plan - Offline recipient receives later

## Final verdict

`implementation-ready`

Current repo evidence shows row `GM-009` is close but not yet exact:

- `test/features/groups/integration/group_resume_recovery_test.dart` already
  has `partial delivery with inbox drain completion`, which models one online
  reader plus multiple offline inbox-backed readers.
- That scenario proves eventual delivery after inbox drain, but it does not yet
  pin the exact row contract that the online reader gets the message
  immediately while the offline recipient gets it only after reconnect/store-
  and-forward, with one-copy assertions.

The smallest safe session is therefore to tighten the existing partial-delivery
integration scenario with timing-aware and exactly-once assertions.

## Final plan

### real scope

- Resolve source row `GM-009` only: `Offline recipient receives later`.
- Prefer test-only changes in
  `test/features/groups/integration/group_resume_recovery_test.dart`.
- Touch production code only if the tightened partial-delivery regression
  exposes a real repo bug.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into retry, restart, or multi-page backlog work.

### closure bar

- There is direct automated proof that Bob receives the group message while
  online before offline inbox drain, and the offline recipient receives exactly
  one copy only after the inbox drain/store-and-forward step.
- The direct partial-delivery proof passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves partial live and inbox-backed delivery, but the row
  is not yet closed because the current test does not explicitly pin immediate
  online delivery vs later offline drain delivery with one-copy assertions.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Production seam only if needed:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

### existing tests covering this area

- `partial delivery with inbox drain completion` already spans the correct live
  plus offline-delivery seam.
- Missing today:
  - explicit pre-drain assertions for the offline recipients
  - explicit one-copy assertions after inbox drain

### regression/tests to add first

- Tighten the existing partial-delivery scenario so it asserts:
  - the online reader receives the message before any offline drain
  - the offline recipient has no copy before drain
  - the offline recipient has exactly one copy after drain
- Only if that exposes a real bug, patch the minimal inbox-drain seam needed to
  satisfy it.

### step-by-step implementation plan

1. Re-read the live partial-delivery integration test and preserve unrelated
   edits.
2. Add exact pre-drain and post-drain assertions without broadening the test
   beyond the current seam.
3. Run the targeted partial-delivery proof.
4. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: eventual delivery alone is not enough unless the timing split
  between online and offline recipients is explicit.
- Scope risk: do not widen into backlog pagination or restart work.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat missing online immediate delivery, pre-drain offline delivery, or
  duplicate post-drain delivery as current-session blockers.

### done criteria

- `GM-009` has exact row-owned online-now / offline-later proof.
- Any delta stays limited to the narrowest partial-delivery integration
  regression needed.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - widening into retry logic
  - widening into multi-page inbox cursor coverage
  - redesigning the inbox bridge harness

### accepted differences / intentionally out of scope

- `GM-009` does not require device-lab notification proof.
- `GM-009` does not own restart recovery or transport-path split rows.

### dependency impact

- A truthful `GM-009` resolution reduces uncertainty for later offline and
  mixed-delivery rows, but it does not automatically close them.
