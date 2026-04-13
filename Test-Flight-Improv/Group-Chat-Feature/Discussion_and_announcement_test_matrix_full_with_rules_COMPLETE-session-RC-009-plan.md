# Session Plan: RC-009

## Row Contract

- source row: `RC-009`
- matrix contract: Decryption failure or payload-parse failure creates no ghost message and remains diagnosable.
- current source truth before execution: `Partial`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - wrong-key and malformed-payload failures still emit the owned Go diagnostics without a visible group message callback
  - wrong-nonce failure is now covered through the shared raw-envelope harness with the same no-ghost-message contract
  - Flutter owns an explicit diagnostic routing surface for `group:decryption_failed` and `group:payload_parse_failed` instead of silently treating them as unknown push events

## Scope Guard

- keep scope on receive-path rejection truth only
- do not broaden into dispatcher-overflow monitoring or later key-race rows
- prefer a small bridge diagnostic surface plus direct Go / Dart regressions over adding UI affordances

## Planned Proof

1. Add a Flutter-owned group diagnostic stream in the bridge layer and route `group:decryption_failed` / `group:payload_parse_failed` through it while keeping `onGroupMessageReceived` untouched.
2. Add bridge unit tests proving those diagnostic events surface to Flutter and do not create a message callback side effect.
3. Add a Go wrong-nonce decryption-failure regression using the shared `group_security_harness_test.go` mutation helper.
4. Run the targeted Go and Dart tests, then update the matrix, inventory, and breakdown if the row-owned closure bar is satisfied.

## Files Expected

- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
