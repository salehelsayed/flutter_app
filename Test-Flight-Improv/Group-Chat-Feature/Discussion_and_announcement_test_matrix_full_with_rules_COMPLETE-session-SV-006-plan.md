# Session Plan: SV-006

## Row Contract

- source row: `SV-006`
- matrix contract: Previous-key grace during rotation accepts legitimate in-flight traffic without reopening indefinite stale-key access.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - an old-epoch envelope still decrypts and emits `group_message:received` while the grace window is active
  - that same previous-epoch path stops delivering once the grace window expires
  - the row is closed using the existing generic Flutter receive-path proof plus row-specific Go grace-window evidence, without widening into race conditions or new rotation features

## Scope Guard

- keep scope on previous-key grace acceptance and expiry only
- prefer one missing live-subscription rejection regression over broader rotation refactors
- do not widen into concurrent admin races (`SV-007`) or replay security rows already closed

## Planned Proof

1. Reuse the shared key/grace harness to add a node-level regression where a previous-epoch envelope is published after the grace window expires and must not emit a visible `group_message:received`.
2. Reuse the existing validator and live-subscription grace tests as the positive acceptance proof during the grace window.
3. Cite the existing Flutter receive-path coverage as parity proof for any valid `group_message:received` event that survives Go validation.
4. Run the targeted Go grace suite, then update the matrix, inventory, and breakdown if the row-owned contract is fully explicit.

## Files Expected

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `test/features/groups/application/group_message_listener_test.dart` and `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` (evidence reuse only)
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
