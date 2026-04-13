# Session Plan: RC-010

## Row Contract

- source row: `RC-010`
- matrix contract: Dispatcher overflow or high-burst receive load has an owned contract and monitoring story.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows burst pressure and overflow are surfaced explicitly instead of leaving the app to look healthy while native events are dropped

## Scope Guard

- keep scope on the owned high-burst contract
- do not widen into unrelated message-ordering or UI rendering work
- prefer one native burst proof plus one Flutter diagnostic-routing proof over broader product-surface changes

## Executed Proof

1. `go-mknoon/node/event_dispatcher.go` now emits `group:dispatcher_pressure` and `group:dispatcher_overflow` diagnostics with queue-depth, dropped-count, delivered-count, and last-event data.
2. `go-mknoon/node/node_test.go` now proves those diagnostics are emitted under burst load with the expected near-overflow and overflow states.
3. `test/core/bridge/go_bridge_client_test.dart` now proves overflow diagnostics reach Flutter's diagnostics stream and flow logs without invoking the group message callback.

## Files Expected

- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/node_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

