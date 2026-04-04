# Session MR-015 Plan - Removed while typing/sending

## Final verdict

`acceptance-only`

Current repo evidence shows this row is still an explicit ordering gap rather
than already-covered behavior:

- `test/features/groups/integration/group_membership_smoke_test.dart`
  now proves post-removal sends are rejected after self-removal cleanup, but
  that seam starts after the removal boundary has already been applied
- `test/features/groups/application/send_group_message_use_case_test.dart`
  proves sends are pre-persisted before publish completes
- `Test-Flight-Improv/09-network-group-messaging.md` still records ordering as
  best-effort, so the repo does not currently define or prove a deterministic
  remove-versus-send boundary while a send is already in flight

The safest session is therefore to close the row truthfully as an open
repo-owned ordering gap instead of overclaiming post-cleanup rejection as
boundary-order proof.

## Final plan

### real scope

- Resolve source row `MR-015` only: `Removed while typing/sending`.
- Prefer no production or test edits.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  so the row is truthfully classified as still open on the current repo state.
- Do not widen into transport-order redesign or new concurrency harness work in
  this session.

### closure bar

- The row is not overclaimed as already covered.
- The matrix and breakdown explicitly record that in-flight remove-versus-send
  ordering remains an open repo-owned gap.
- Supporting direct evidence below is cited honestly.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call'`

### done criteria

- `MR-015` is truthfully documented as an open ordering gap.
- Post-cleanup send rejection is not misrepresented as in-flight boundary
  coverage.
- The matrix and breakdown can safely move on.
