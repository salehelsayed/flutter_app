# Session Plan: SV-005

## Row Contract

- source row: `SV-005`
- matrix contract: Tampered payload, wrong key, tampered nonce, or tampered ciphertext creates no visible message and yields diagnosable rejection.
- current source truth before execution: `Partial`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - wrong-key, tampered-nonce, and tampered-ciphertext group envelopes are all rejected without a `group_message:received` event
  - Flutter already owns a diagnosable rejection surface for those Go diagnostic events through the bridge-level group diagnostics stream from `RC-009`
  - the row is closed without widening scope into replay resistance, key grace, or dispatcher-overflow work

## Scope Guard

- keep scope on malformed encrypted group-message rejection only
- prefer one missing node-level tampered-ciphertext regression plus row-truth doc alignment over new product features
- do not widen into retry/recovery observability or key-rotation race work

## Planned Proof

1. Reuse the shared Go security harness to add a tampered-ciphertext node regression that emits `group:decryption_failed` and never emits `group_message:received`.
2. Reuse the existing `RC-009` bridge diagnostic tests as the Flutter-owned diagnosable rejection proof instead of adding a second routing surface.
3. Run the targeted Go decryption-failure suite and, if needed, the existing Flutter bridge diagnostic tests to keep the row-owned evidence explicit.
4. Update the matrix, inventory, and breakdown once the combined no-ghost-message plus diagnosable-rejection contract is directly cited.

## Files Expected

- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `test/core/bridge/go_bridge_client_test.dart` (evidence reuse unless a new assertion is needed)
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
