# Session UX-007 Plan - Large message or attachment

## Final verdict

`implementation-ready`

Current repo evidence shows `UX-007` is now a bounded direct-proof gap, not a
new product-behavior build:

- The settled ordinary-media size-budget contract already landed in the shared
  attach/hydration work tracked by
  `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`.
- Group closure docs already record the live `5 GB` ordinary-attachment budget
  and the hydrated pending-media path as supported behavior.
- What remains missing for this matrix row is one row-owned group proof that
  the overflow/compress contract behaves honestly at the live composer seam:
  oversized attachments become sendable once compression brings them under the
  budget, and still-oversized results fail cleanly without leaving broken
  pending state behind.

## Final plan

### real scope

- Close source row `UX-007` only: add narrow group composer regressions that
  lock the large-attachment overflow contract already present in production.
- Keep the change bounded to:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`

### closure bar

- A group gallery attachment that exceeds the configured budget surfaces the
  overflow dialog with explicit compress/cancel semantics.
- If compression reduces the attachment below the budget, the processed file is
  staged in the group composer as the pending attachment.
- If the compressed result still exceeds the budget, the user sees the explicit
  failure snackbar and the composer keeps no leftover pending attachment state.
- Direct proof passes and the named `groups` gate passes.
- `UX-007` is updated to `Closed` or `Covered` only after docs cite the landed
  regression.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- The repo already supports the attach-time size-budget contract, but the group
  matrix row still lacks a row-owned regression that proves the overflow
  decision, compression handoff, and clean-failure behavior at the live group
  composer seam.
- This row should lock the current budget behavior in place, not redesign the
  settled 5 GB cap or upload architecture.

### regression/tests to add first

- Add direct widget regressions in
  `test/features/groups/presentation/group_conversation_wired_test.dart` that:
  - attach an oversized gallery image under original-quality budgeting
  - accept compression and verify the compressed file becomes the staged
    pending attachment when it fits
  - verify the explicit failure snackbar plus empty pending state when the
    compressed result still exceeds the budget

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on group large-attachment
   proof only.
2. Add the narrow overflow/compress regressions to
   `test/features/groups/presentation/group_conversation_wired_test.dart`.
3. Reuse the existing `maxAttachmentBudgetBytes`,
   `preparePendingComposerMedia(...)`, and group composer pending-attachment
   seams instead of widening into new production behavior.
4. Run the direct widget suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, regression strategy, and the
   media-size breakdown only after the proof passes.

### risks and edge cases

- The row is about ordinary attachments, not the recorder-only `100 MB` voice
  limit.
- Keep the proof on the group composer seam; do not widen into 1:1 or feed
  launcher behavior here.
- The failure branch must prove no leftover pending attachment survives, not
  just that a snackbar appears.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the oversize dialog never appears, the budget contract is not being
  enforced honestly for the tested group path and the row remains open.
- If compression succeeds but the composer stages the wrong file or leaves no
  attachment, the row remains open.
- If the over-budget-after-compression path leaves a pending attachment behind,
  the row remains open because partial broken state still exists.

### done criteria

- Direct group regressions prove both the successful compress-under-budget path
  and the clean reject-after-compression path.
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `UX-007` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and the media-size breakdown records that the row now
  has row-owned proof instead of only cross-feature session evidence.

### scope guard

- Do not change the settled attachment budget unless the new regression exposes
  a real defect.
- Do not widen into upload-progress or wake-lock work; that is already closed
  elsewhere.
- Do not add new integration/device tests if the deterministic widget proof
  closes the row honestly.

### accepted differences / intentionally out of scope

- The broader 1:1 attach-time budget contract remains owned by the media-size
  rollout docs rather than this group-specific matrix row.
- True background upload behavior remains out of scope.

### dependency impact

- `UX-007` can close independently once the group overflow regressions land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
