# Session MR-014 Plan - Removed while offline

## Final verdict

`acceptance-only`

Current repo evidence shows this row is still an explicit product gap rather
than already-covered behavior:

- the current remove flow publishes `member_removed` through live
  `group:publish` and rotates keys, but it does not persist a removal-control
  event through the relay inbox for an offline removed peer
- the removed-state notice now depends on the live `groupRemovedStream`
  reaching the active conversation route, so an offline peer has no repo-local
  catch-up path that would move it into removed state on reconnect

The safest session is therefore to close the row truthfully as an open
repo-owned gap instead of overclaiming live-only removal coverage as offline
reconnect proof.

## Final plan

### real scope

- Resolve source row `MR-014` only: `Removed while offline`.
- Prefer no production or test edits.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  so the row is truthfully classified as still open on the current repo state.
- Do not widen into new control-plane delivery, relay-inbox redesign, or
  restart recovery implementation.

### closure bar

- The row is not overclaimed as already covered.
- The matrix and breakdown explicitly record that offline removed-state sync is
  still missing in the current repo-owned contract.
- Supporting direct evidence below is cited honestly.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Verified seam files:
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'current group removal shows a notice and exits the conversation route'`

### done criteria

- `MR-014` is truthfully documented as an open offline-removal gap.
- No live-only proof is misrepresented as reconnect-time removed-state sync.
- The matrix and breakdown can safely move on.
