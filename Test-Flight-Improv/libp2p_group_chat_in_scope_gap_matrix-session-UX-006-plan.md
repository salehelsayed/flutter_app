# Session UX-006 Plan - Long text / emoji / RTL / special characters

## Final verdict

`implementation-ready`

Current repo evidence shows `UX-006` is a bounded end-to-end proof gap:

- Existing bidi-focused tests already cover mixed RTL/LTR preview behavior and
  sanitization at narrower layers.
- Group send/receive integration already proves ordinary text delivery.
- What remains missing is one row-owned regression that sends a deliberately
  long mixed-content message and proves the text survives end to end without
  corruption in delivery, storage, and local notification preview.

## Final plan

### real scope

- Close source row `UX-006` only: add one direct mixed-content message
  regression in the group integration smoke harness.
- Keep the change bounded to:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`

### closure bar

- One group message includes:
  - long text
  - emoji
  - Arabic/RTL text
  - special characters
- The receiver stores and reads back the exact text without corruption.
- The receiver's local notification preview carries the same mixed-content body
  correctly.
- Direct proof passes and the named `groups` gate passes.
- `UX-006` is updated to `Closed` or `Covered` only after docs cite the landed
  regression.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- The repo already has targeted bidi and preview tests, but no single row-owned
  integration proof that the whole mixed-content payload survives real group
  delivery and notification projection.
- This row should lock the current behavior in place, not redesign text
  sanitization or notification formatting.

### regression/tests to add first

- Add one integration regression in
  `test/features/groups/integration/group_membership_smoke_test.dart` that
  sends a long mixed-content message to a paused recipient with notification
  capture enabled and then checks the stored incoming text plus notification
  preview body.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on mixed-text delivery
   proof only.
2. Add the long/emoji/RTL/special-character regression to
   `test/features/groups/integration/group_membership_smoke_test.dart`.
3. Reuse the existing notification harness instead of widening into new UI
   widget tests.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `14-regression-test-strategy.md` only after the proof passes.

### risks and edge cases

- Unicode literals are intentional in this row because the behavior under test
  depends on them.
- Keep the payload free of invisible bidi-control characters unless the test is
  explicitly asserting sanitizer behavior; this row is about end-to-end
  preservation of normal user-visible content.
- Avoid widening into attachment coverage, which belongs to `UX-007`.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the stored incoming text differs from the sent text, the row remains open.
- If the notification preview mangles the mixed-content body, the row remains
  open.
- If the test only proves storage but not receiver-facing projection, the row
  remains underspecified.

### done criteria

- One exact regression proves mixed-content text survives delivery, storage,
  and notification preview.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `UX-006` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and the regression strategy doc records the new
  mixed-content lock.

### scope guard

- Do not change production text sanitization or notification code unless the
  regression exposes a real defect.
- Do not widen into media, attachment, or unread behavior in this row.
- Do not replace the targeted bidi tests; this row complements them.

### accepted differences / intentionally out of scope

- Invisible-control sanitizer behavior remains covered by lower-layer tests.
- Device-level rendering differences remain out of scope; the deterministic
  integration path is enough to lock the payload contract.

### dependency impact

- `UX-006` can close independently once the mixed-content regression lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
