# Session Plan: SV-012

## Row Contract

- source row: `SV-012`
- matrix contract: Native dispatcher overflow or dropped diagnostics are surfaced to monitoring instead of remaining silent.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows dispatcher overflow diagnostics reach owned Flutter monitoring surfaces and do not disappear silently in the bridge

## Scope Guard

- keep scope on monitoring visibility, not on broader receive semantics
- reuse the dispatcher prerequisite instead of adding another diagnostic channel
- prove both native emission and Flutter routing explicitly

## Executed Proof

1. `go-mknoon/node/node_test.go` now proves overflow diagnostics are emitted with queue-depth and dropped-count data.
2. `lib/core/bridge/go_bridge_client.dart` now routes `group:dispatcher_overflow` into Flutter's group diagnostics stream, push diagnostics logger, and flow logs.
3. `test/core/bridge/go_bridge_client_test.dart` now proves that routing happens without invoking the group message callback.

## Files Expected

- `go-mknoon/node/node_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

