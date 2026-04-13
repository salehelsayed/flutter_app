# Session Plan: PREREQ-GROUP-DISPATCHER-OVERFLOW

## Session Contract

- source row: `shared prerequisite for RC-010 and SV-012`
- session classification after execution: `accepted`
- closure target for this session: surface native dispatcher pressure and overflow diagnostics through owned Go and Flutter contracts so later row-owned receive and monitoring sessions no longer depend on a silent bounded queue

## Scope Guard

- keep this session on dispatcher diagnostics and routing
- do not widen into unrelated receive ordering or replay encryption work
- keep the diagnostic payload focused on queue depth, dropped/coalesced counts, delivered count, and the last event that pushed the queue toward overflow

## Executed Proof

1. `go-mknoon/node/event_dispatcher.go` now emits coalesced `group:dispatcher_pressure` and `group:dispatcher_overflow` diagnostics with queue-depth, dropped-count, coalesced-count, delivered-count, and last-event data.
2. `go-mknoon/node/node_test.go` now proves those diagnostics are emitted under burst load with the expected near-overflow and overflow states.
3. `lib/core/bridge/go_bridge_client.dart` now routes those push events into Flutter's `groupDiagnosticEventStream`, the push diagnostics logger, and owned flow logs.
4. `test/core/bridge/go_bridge_client_test.dart` now proves `group:dispatcher_overflow` reaches diagnostics and flow logs without invoking the group message callback.

## Files Expected

- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/node_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

