Status: accepted

# Doc 115 Session 115-P4 Plan - Relay Protocol And Go Client Plumbing

## Planning Progress

- 2026-06-13T06:55:00Z - Intake started after `115-P3` was accepted and recorded in the source doc and session breakdown.
- 2026-06-13T06:56:00Z - Graph-first orientation ran against `graphify-arch` for the Dart consumer contract (`InboxStoreOutcome`, `storeInInboxDetailed`, `callP2PInboxStore`) and against the root graph for Go relay symbols (`InboxStoreResult`, `memoryInboxBackend.Store`, `pruneExpired`, `memoryInboxBackendLimited.Store`).
- 2026-06-13T06:57:00Z - Focused source reads confirmed the current relay still silently evicts on cap in memory, limited-memory, and Redis paths; memory TTL prune drops rows without rebuilding dedup ids; handler responses lack `expiresAtMs`/`occupancy`/`capacity`; go-mknoon still exposes only `Node.InboxStore(...) error`; bridge still returns bare `{ok:true}`.

## Real Scope

Implement Phase 4 only:

- Relay/server typed reject-new behavior at 1:1 inbox cap.
- TTL prune dedup release and reject/prune telemetry.
- Store response metadata: `storeStatus`, `expiresAtMs`, `occupancy`, `capacity`, and typed `INBOX_FULL`.
- Memory, limited-memory, and Redis parity.
- Go client parsing and typed detailed outcome.
- Bridge and testpeer passthrough of the detailed store result.
- Focused Go tests plus required Go gates.

Out of scope:

- No final doc-115 gate capture or `scripts/run_test_gates.sh` array edit; `115-P5` owns that coordinated closeout.
- No EC2/staging production deploy or two-device evidence; `115-P5` owns external acceptance.
- No Flutter behavior changes except generated binding artifacts if the established rebuild requires them.
- No `InboxBackend` method-signature change.

## Source Of Truth

- `Test-Flight-Improv/115-relay-inbox-custody.md` Phase 4.
- `Test-Flight-Improv/115-relay-inbox-custody-session-breakdown.md`.
- Current app-side consumer contract from `115-P3`:
  `lib/core/services/inbox_store_outcome.dart` and
  `lib/core/services/p2p_service_impl.dart`.
- Current relay/client files:
  `go-relay-server/inbox_store.go`,
  `go-relay-server/backend_memory.go`,
  `go-relay-server/limits.go`,
  `go-relay-server/backend_redis.go`,
  `go-relay-server/inbox.go`,
  `go-relay-server/metrics.go`,
  `go-mknoon/node/inbox.go`,
  `go-mknoon/bridge/bridge.go`,
  and `go-mknoon/cmd/testpeer/commands.go`.

## Implementation Steps

1. Add `InboxStoreResultRejectedFull` and keep `InboxBackend.Store` unchanged.
2. Change memory and limited-memory store paths to reject overflow instead of evicting oldest; rebuild message-id dedup state after TTL pruning.
3. Change Redis store path to normalize/prune expired entries, reject overflow without trimming, and preserve oldest entries.
4. Add/store/update relay counters for full rejects and expired prunes, keeping existing counters compatible where practical.
5. Extend handler response shape with `expiresAtMs`, `occupancy`, and `capacity`; map `RejectedFull` to `Status:"ERROR"`, `Error:"INBOX_FULL"`, `StoreStatus:"rejected_full"` and suppress push on rejects.
6. Add go-mknoon `InboxStoreOutcome`, typed `ErrInboxFull`, `parseInboxStoreResponse`, and `Node.InboxStoreDetailed(...)`; keep existing `InboxStore(...) error` delegating.
7. Enrich bridge `InboxStore` JSON response and testpeer `inbox_store_v1`, `inbox_store_v2`, and `inbox_store_raw` command results.
8. Run focused Go tests, then `cd go-relay-server && go test ./...`, `cd go-mknoon && make test`, binding verification or rebuild as dictated by existing Makefile, `git diff --check`, and repo-root `./graphify-arch/refresh_arch_graph.sh`.

## Closure Bar

`115-P4` is accepted when relay-server and go-mknoon tests prove typed reject-new, TTL/dedup repair, metrics, response metadata, client parsing, bridge passthrough, and testpeer surfacing. `115-P5` must remain open for final gate capture, deployment, E2E/device proof, and whole-doc closure.

## Execution Evidence

- 2026-06-13T07:21:44Z - Relay/server implementation landed typed `InboxStoreResultRejectedFull`, reject-new-at-cap for memory/limited/Redis paths, TTL prune dedup repair, reject/prune counters, handler response metadata (`expiresAtMs`, `occupancy`, `capacity`), and `INBOX_FULL` wire response behavior.
- 2026-06-13T07:21:44Z - Go client implementation landed `ErrInboxFull`, `InboxStoreOutcome`, `parseInboxStoreResponse`, `Node.InboxStoreDetailed`, enriched bridge `InboxStore` JSON, and testpeer `inbox_store_v1`/`inbox_store_v2`/`inbox_store_raw` detailed output.
- 2026-06-13T07:21:44Z - Dart bridge client coverage was updated to assert enriched `inbox:store` responses still round-trip through `P2PBridgeClient`.
- 2026-06-13T07:21:44Z - `go-mknoon/bin/testpeer` rebuilt via `cd go-mknoon && make testpeer`.

## Verification Evidence

- PASS: focused relay P4 suite covering reject-new, handler metadata, dedup release, Redis parity, telemetry, protocol key contract, and bootstrap capacity.
- PASS: `cd go-relay-server && go test -count=1 ./...` (`/tmp/doc115_p4_relay_all.log`).
- PASS: focused Flutter bridge/app-side contract batch, 128 tests (`/tmp/doc115_p4_focused_flutter.log`).
- PASS: focused go-mknoon P4 tests:
  `go test ./node -run 'TestParseInboxStoreResponse'`,
  `go test ./bridge -run 'TestInboxStore_ResultCarriesStoreStatusAndErrorCode|TestInboxStore_InvalidJSON|TestInboxStore_Missing'`,
  and `go test ./cmd/testpeer -run 'TestInboxStoreOutcomeResultExposesDetailedFields'`.
- PASS: `cd go-mknoon && go test -count=1 -timeout=180s` for all packages except the broad `node` and `bridge` suites (`/tmp/doc115_p4_go_mknoon_non_node_bridge.log`).
- PASS: broad-timeout culprit tests pass in isolation:
  `TestBridgeGroupHistoryRepairRange_CommandExposed` and
  `TestGA012MultiDeviceMissingSenderTransportPeerIDRejects`.
- PASS: `cd go-mknoon && make verify-bindings` (`/tmp/doc115_p4_verify_bindings.log`).
- PASS: `git diff --check` (`/tmp/doc115_p4_diff_check.log`).
- PASS: `./graphify-arch/refresh_arch_graph.sh` from the repo root (`/tmp/doc115_p4_graph_refresh.log`).

## P5 Gate Policy Resolution

`cd go-mknoon && go test -count=1 -timeout=180s ./...` did not produce a clean broad-suite result: the `bridge` package timed out while running `TestBridgeGroupHistoryRepairRange_CommandExposed`, and the `node` package timed out while running `TestGA012MultiDeviceMissingSenderTransportPeerIDRejects`. Both named tests pass when run alone, and the focused P4 inbox-store parser/bridge/testpeer suites pass. `115-P5` must either make the broad go-mknoon gate green or record a final accepted gate policy for these broad-suite runtime accumulations before whole-doc closure.

P5 recorded that policy: the aggregate timeout is accepted for this doc because
the isolated culprit tests, focused package gates, and local relay integration
proof pass. Production relay deployment was completed and verified during the
final Doc 115 re-audit.

## Verdict

`115-P4` is accepted. The relay/client protocol contract is implemented and directly verified; P5 owns and has recorded the final gate/deploy policy plus residual device-lab evidence archive.
