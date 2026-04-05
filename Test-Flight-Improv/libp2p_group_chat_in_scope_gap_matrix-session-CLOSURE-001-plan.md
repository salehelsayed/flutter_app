# Session CLOSURE-001 Plan - Final matrix closure refresh and gate classification

## Final verdict

`closure-only`

All row-owned sessions that remained runnable in
`Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
are now resolved, and the formerly blocked rows `MR-015`, `MR-024`, `SC-001`,
`SC-012`, and `SC-015` have since been truthfully closed in the source matrix
through follow-on rollout docs `56`, `57`, and `58`. This closure pass must
therefore persist a final program verdict of `closed`.

## Final plan

### real scope

- Refresh the source matrix and adjacent breakdown so every resolved row is
  marked with concrete evidence and the final persisted verdict is honest.
- Keep the change bounded to closure docs only:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - touched supporting docs such as
    `Test-Flight-Improv/14-regression-test-strategy.md` and
    `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- Do not reopen implementation unless closure review discovers a false row
  claim.
- Reconcile the formerly blocked row-owned sessions against the follow-on
  rollout artifacts that resolved them:
  - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
  - `Test-Flight-Improv/57-authenticated-group-membership-events.md`
  - `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`

### closure bar

- Every row-owned session that actually ran is reflected as `Closed` or
  `Covered` in the source matrix with file-and-test evidence.
- The breakdown ledger reflects no remaining runnable row-owned sessions.
- The final persisted program verdict is `closed` because every source row in
  the filtered matrix is now `Closed` or `Covered`.
- Gate definitions stay unchanged unless this closure pass truthfully changes a
  frozen gate classification.

### source of truth

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
- `Test-Flight-Improv/57-authenticated-group-membership-events.md`
- `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
- `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`

### session classification

`closure-only`

### exact problem statement

- The remaining risk is no longer missing runnable implementation work.
- The remaining risk is closure drift: if the matrix or breakdown still imply
  blocked rows or a stale `still_open` verdict after docs `56`, `57`, and `58`
  resolved those rows, the artifact becomes untrustworthy.

### step-by-step implementation plan

1. Reconcile the formerly blocked rows `MR-015`, `MR-024`, `SC-001`, `SC-012`,
   and `SC-015` against the now-closed source matrix and follow-on rollout docs
   `56`, `57`, and `58`.
2. Mark the refreshed row-owned sessions and `CLOSURE-001` accepted in the
   breakdown ledger.
3. Persist the final matrix verdict as `closed`.
4. Leave `Test-Flight-Improv/test-gate-definitions.md` unchanged unless a real
   gate reclassification is needed.

### exact tests and gates to run

- Reuse the row-owned proof already recorded for the formerly blocked and final
  closure rows:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

### done criteria

- No row-owned runnable sessions remain in the breakdown.
- The source matrix and breakdown tell the same truthful story.
- The persisted program verdict is `closed` because every source row in the
  filtered matrix is now `Closed` or `Covered`.
