# Session MR-003 Plan - New member cannot send before bootstrap completes

## Final verdict

`implementation-ready`

Current repo evidence shows `MR-003` is a bounded send-gate gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `MR-003` as `implementation-ready` with `code changes and tests`
  ownership.
- The repo already proves newly added members can send after bootstrap is
  complete.
- The missing behavior is narrower: the send path still falls back to key epoch
  `0` when no group key is present, so a just-added member can attempt a real
  send before bootstrap has actually supplied their group key.

The smallest safe session is therefore to block member-side sends when the
group key is still missing, land one unit proof for the guard and one
membership-smoke proof for the before-bootstrap vs after-bootstrap boundary,
then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `MR-003` only: prevent a newly added member from sending a
  group message before their bootstrap key exists locally, while preserving the
  existing post-bootstrap send path.
- Keep the change bounded to:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- A member-role group send with no local group key is rejected before publish
  or inbox-store bridge calls start.
- The blocked path does not deliver an invalid message to other peers.
- The same newly added member succeeds once bootstrap key state is present.
- Direct proof passes, and the named gate below passes or is recorded
  truthfully if an unrelated failure remains outside this row's write scope.
- `MR-003` is updated to `Closed` or `Covered` only after the docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves "new member can participate after bootstrap."
- What remains open is the pre-bootstrap boundary: a member-role sender with no
  local group key still falls back to epoch `0` instead of being blocked.
- This session should not widen into invite transport redesign, new queueing
  systems, or a broader membership bootstrap refactor.

### regression/tests to add first

- Add a unit regression proving `sendGroupMessage()` rejects a member-role send
  when the local group key is missing.
- Add an integration regression proving a newly added member is blocked before
  bootstrap completes, then succeeds after the bootstrap key is saved.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on the member-side send
   guard only.
2. Add a bounded missing-key guard to
   `lib/features/groups/application/send_group_message_use_case.dart`.
3. Add the unit proof in
   `test/features/groups/application/send_group_message_use_case_test.dart`.
4. Add the before-bootstrap vs after-bootstrap integration proof in
   `test/features/groups/integration/group_membership_smoke_test.dart`.
5. Run the direct suites and named gate below.
6. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Do not break valid initial epoch `0` sends for already bootstrapped groups
  that actually have a saved group key.
- Keep the guard tied to the missing-key seam; do not widen into unrelated role
  checks or recovery-state gating.
- Do not claim queue semantics if the landed behavior is an explicit block.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` only if the
    session touches membership UI or notification routing

### known-failure interpretation

- If the blocked member-side send still reaches publish or inbox-store bridge
  calls, the pre-bootstrap guard is not real.
- If other peers can receive the blocked send, the row remains open.
- If the member cannot send after the bootstrap key is present, the session
  regressed the valid post-bootstrap path.

### done criteria

- Member-role sends with no local group key are blocked before network send.
- The newly added member succeeds after bootstrap key persistence.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `MR-003` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no
  longer treats the bootstrap boundary as an open send guard gap.

### scope guard

- Do not add a new queued-send subsystem in this row.
- Do not redesign invite persistence or background bootstrap orchestration.
- Do not widen into admin-transfer, removal-ordering, or notification work.

### accepted differences / intentionally out of scope

- Auto-retry or queued resend after bootstrap finishes remains outside this row.
- Offline-add and offline-reinvite bootstrap journeys remain covered by their
  own rows and should not be reopened here.

### dependency impact

- `MR-003` can close independently once the missing-key send guard and the
  before-vs-after bootstrap proof land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
