Status: execution-ready

# Report 84 - Relay Inbox Store Truthful Status TDD Plan

## Planning Progress

- 2026-05-07 13:50 CEST - Planner completed. Files inspected since last update: this plan artifact. Decision: no structural replanning needed; patched incremental execution-safety wording for the failing backend fake and read-only Go client boundary. Next action: reviewer pass.
- 2026-05-07 13:50 CEST - Reviewer started. Files inspected since last update: patched plan artifact. Decision: verify mandatory sections, direct tests, gates, scope guard, and stop rule after tightening. Next action: sufficiency review.
- 2026-05-07 13:51 CEST - Reviewer completed. Files inspected since last update: patched plan artifact. Decision: sufficient after adjustments; no missing structural files, regressions, gates, closure bar, scope guard, or stop rule. Next action: arbiter pass.
- 2026-05-07 13:51 CEST - Arbiter started. Files inspected since last update: reviewer findings. Decision: classify fake-backend/client-boundary edits as incremental details and confirm no structural blocker remains. Next action: final arbiter decision.
- 2026-05-07 13:51 CEST - Arbiter completed. Files inspected since last update: reviewer findings and patched plan artifact. Decision: no structural blockers remain; plan stays `execution-ready` for isolated execution-qa. Next action: run `$implementation-execution-qa-orchestrator` only when requested.

## Execution Progress

- 2026-05-07 18:08 CEST - Contract extracted. Files inspected since last update: `Test-Flight-Improv/84-relay-inbox-store-truthful-status-plan.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/test-gates-reference.md`, relay inbox code/test search results. Decision: Go relay-only execution is safe; required direct tests are focused relay TDD command, final `(cd go-relay-server && go test ./...)`, and `git diff --check`; Flutter named gates are not required unless scope expands into `go-mknoon`, bridge, Flutter retry/status code, or gate docs. Next action: spawn isolated Executor.
- 2026-05-07 18:09 CEST - Executor started. Files inspected since last update: `go-relay-server/inbox_store.go`, `go-relay-server/inbox.go`, `go-relay-server/backend_memory.go`, `go-relay-server/limits.go`, `go-relay-server/backend_redis.go`, `go-relay-server/inbox_test.go`, `go-relay-server/inbox_dedup_test.go`, `go-relay-server/backend_redis_test.go`. Decision: current repo matches planned old bool store contract and unconditional stream OK behavior; proceed with required RED regressions first. Next action: add stream/backend duplicate and failure tests.
- 2026-05-07 18:11 CEST - Focused RED complete. Files touched since last update: `go-relay-server/inbox_test.go`, `go-relay-server/inbox_dedup_test.go`, `go-relay-server/backend_redis_test.go`. Command: `(cd go-relay-server && go test ./... -run 'TestHandleInboxStream_StoreBackendErrorReturnsError|TestHandleInboxStream_StoreDuplicateReturnsOKWithoutSecondPendingMessage|TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure|TestRedisInboxBackend_DedupesByMessageIDAcrossClients')`. Result: failed as expected with undefined `InboxStoreResult` and old one-value `Store` signature. Next action: implement typed store result contract.
- 2026-05-07 18:16 CEST - Implementation completed. Files touched since last update: `go-relay-server/inbox_store.go`, `go-relay-server/inbox.go`, `go-relay-server/backend_memory.go`, `go-relay-server/limits.go`, `go-relay-server/backend_redis.go`, plus scoped test call-site updates in `go-relay-server/inbox_test.go`, `go-relay-server/inbox_dedup_test.go`, `go-relay-server/backend_redis_test.go`, `go-relay-server/limits_test.go`, `go-relay-server/failover_test.go`, `go-relay-server/server_bootstrap_test.go`, `go-relay-server/redis_failover_integration_test.go`. Decision: `InboxStoreResultStored`/`InboxStoreResultDuplicate` now represent successful store states and backend/write errors return `error`; stream store failures return relay `ERROR`, duplicates return `OK` with `storeStatus: duplicate`, and duplicate stores still skip push. Next action: run required validation.
- 2026-05-07 18:16 CEST - Boundary evidence checked. Files inspected since last update: `go-mknoon/node/inbox.go` only. Decision: `json.Unmarshal` ignores unknown `storeStatus`, and `resp.Status != "OK"` still returns `inbox store failed`; no Go node, bridge, Flutter retry/status, or gate-doc changes needed. Next action: finish validation.
- 2026-05-07 18:16 CEST - Validation completed. Commands: `gofmt -w inbox_store.go inbox.go backend_memory.go limits.go backend_redis.go inbox_test.go inbox_dedup_test.go backend_redis_test.go limits_test.go failover_test.go server_bootstrap_test.go redis_failover_integration_test.go`; `(cd go-relay-server && go test ./... -run 'TestHandleInboxStream_StoreBackendErrorReturnsError|TestHandleInboxStream_StoreDuplicateReturnsOKWithoutSecondPendingMessage|TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure|TestRedisInboxBackend_DedupesByMessageIDAcrossClients')`; `(cd go-relay-server && go test ./...)`; `git diff --check`. Results: focused green passed (`ok github.com/mknoon/relay-server 0.545s`), full relay suite passed (`ok github.com/mknoon/relay-server 9.076s`), diff check passed. Decision: Executor work complete with no missing required evidence. Next action: hand off for QA review.
- 2026-05-07 18:17 CEST - QA Reviewer started. Files inspected since last update: current git diff, plan contract, touched Go relay source/tests, and read-only Go node boundary. Decision: review scope adherence, behavior, tests, gates, and done criteria without fixing code. Next action: complete sufficiency review.
- 2026-05-07 18:21 CEST - QA Reviewer completed. Files inspected since last update: `go-relay-server/inbox_store.go`, `go-relay-server/inbox.go`, `go-relay-server/backend_memory.go`, `go-relay-server/limits.go`, `go-relay-server/backend_redis.go`, `go-relay-server/inbox_test.go`, `go-relay-server/backend_redis_test.go`, `go-relay-server/inbox_dedup_test.go`, `go-mknoon/node/inbox.go`. Commands independently run: `(cd go-relay-server && go test ./... -run 'TestHandleInboxStream_StoreBackendErrorReturnsError|TestHandleInboxStream_StoreDuplicateReturnsOKWithoutSecondPendingMessage|TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure|TestRedisInboxBackend_DedupesByMessageIDAcrossClients')`; `(cd go-relay-server && go test ./...)`; `git diff --check`; extra `(cd go-relay-server && go test ./... -count=1)`. Results: all passed. Decision: no blocking issues and no non-blocking follow-ups; Flutter gates remain unnecessary because scope stayed Go relay-only. Next action: final verdict accepted.
- 2026-05-07 18:21 CEST - Final verdict written. Files inspected since last update: QA result and execution progress. Decision: `accepted`; Report 84 closure bar and done criteria are met. Next action: none.

## real scope

Change only the Go relay 1:1 inbox store contract and the relay stream response path so a sender sees relay `OK` only when the message is either:

- newly persisted into the recipient's relay inbox, or
- already pending as an idempotent duplicate.

The fix must surface actual backend/write/serialization failures as relay `ERROR`. Because `go-mknoon/node.InboxStore` already returns an error when `resp.Status != "OK"`, this should preserve the existing sender-side retry behavior without changing Flutter status semantics.

This plan does not change direct peer delivery ACKs, UI wording, delivery receipts, multi-relay failover behavior, group inbox behavior, push-token routing, or any definition of "received" beyond "accepted into the 1:1 relay inbox."

## closure bar

The session is complete when:

- `HandleInboxStream` no longer reports `Status: "OK"` after a failed 1:1 inbox persistence attempt.
- Duplicate 1:1 inbox stores remain idempotent successes: they return relay `OK`, do not create a second pending message, and do not send a second push notification.
- Redis-backed inbox store failures are distinguishable from duplicate stores.
- Existing memory, limited-memory, Redis, and wrapper call sites compile against one truthful store result contract.
- The Go relay test suite has direct regressions for backend failure and duplicate idempotence.

## source of truth

Authoritative code:

- `go-relay-server/inbox.go`: `InboxStore.Store`, `inboxResponse`, and `HandleInboxStream`.
- `go-relay-server/inbox_store.go`: `InboxBackend` interface.
- `go-relay-server/backend_memory.go`: in-memory 1:1 inbox backend.
- `go-relay-server/limits.go`: limited in-memory 1:1 inbox backend.
- `go-relay-server/backend_redis.go`: Redis 1:1 inbox backend.
- `go-mknoon/node/inbox.go`: sender-side Go client behavior for relay inbox store response handling.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart` and `lib/features/conversation/application/retry_unacked_messages_use_case.dart`: Flutter retry behavior that marks a message delivered only when `p2pService.storeInInbox` returns true.

Authoritative tests and gates:

- `go-relay-server/inbox_test.go`: existing `setupInboxStreamEnv`, stream helpers, retrieve-pending/ack coverage, and best home for the stream-level regression.
- `go-relay-server/inbox_dedup_test.go`: existing duplicate and push-suppression behavior.
- `go-relay-server/backend_redis_test.go`: Redis backend dedupe and failure behavior.
- `Test-Flight-Improv/test-gate-definitions.md`: named gate source of truth.
- `scripts/run_test_gates.sh`: wins if it disagrees with gate docs.

If docs and code disagree, current code and tests win. If the gate docs and gate script disagree, the script wins.

## session classification

`implementation-ready`

The current code has a narrow, reproducible contract gap. No product decision is required because the user explicitly clarified that relay inbox acceptance is enough and multi-relay work is out of scope.

## exact problem statement

`HandleInboxStream` currently ignores the result of `InboxStore.Store` in the 1:1 `"store"` branch and unconditionally returns `Status: "OK"`. At the same time, `InboxBackend.Store` returns only `bool`, where `false` means both "duplicate" and "failed to persist" depending on the backend.

That means a relay-backed sender can be told "sent" after reconnecting to 5G even if the relay did not actually accept the message into the recipient's inbox. The sender-side Go client already treats relay `ERROR` as failure, and Flutter retry flows already keep retry state when `storeInInbox` returns false. The missing piece is the relay accurately reporting whether the store happened.

Behavior that must improve:

- A relay backend/write failure must not become a sender-visible success.
- The sender must retain existing retry behavior when the relay cannot store.

Behavior that must stay unchanged:

- A duplicate message already pending in the same recipient inbox remains an idempotent success.
- A successful relay inbox store is enough to mark the local sender row delivered via inbox.
- Receiver foreground/background retrieval and explicit inbox ack semantics stay unchanged.

## files and repos to inspect next

Production files:

- `go-relay-server/inbox_store.go`
- `go-relay-server/inbox.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/limits.go`
- `go-relay-server/backend_redis.go`
- `go-mknoon/node/inbox.go`

Tests to update or inspect:

- `go-relay-server/inbox_test.go`
- `go-relay-server/inbox_dedup_test.go`
- `go-relay-server/backend_redis_test.go`
- `go-relay-server/limits_test.go`
- `go-relay-server/failover_test.go`
- `go-relay-server/server_bootstrap_test.go`
- `go-relay-server/redis_failover_integration_test.go`

Docs/gates:

- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `Testing-Tracking/go-relay-server.md`

## existing tests covering this area

Existing useful coverage:

- `go-relay-server/inbox_test.go` has `setupInboxStreamEnv`, `sendInboxReq`, and `recvInboxResp`, which can exercise real `HandleInboxStream` behavior through libp2p mocknet streams.
- `TestHandleInboxStream_RetrievePendingAndAck` verifies store, retrieve-pending, and ack flow against the stream handler, but it only checks successful store status.
- `go-relay-server/inbox_dedup_test.go` verifies same-recipient duplicate suppression and push suppression.
- `go-relay-server/backend_redis_test.go` verifies Redis dedupe across clients, but currently expects duplicate as `false` and does not distinguish duplicate from backend failure.
- `go-mknoon/node/inbox.go` already rejects non-OK relay responses, so no new client-side status parser is needed for correctness.

Missing coverage:

- No stream-level test proves `HandleInboxStream` returns `ERROR` when `InboxStore.Store` cannot persist.
- No test proves duplicate store is an OK/idempotent response after the store contract is split from backend failure.
- No Redis test proves backend write/connect failure is returned as an error instead of a duplicate-looking false.

## regression/tests to add first

Add these tests before production implementation. The first red run may fail to compile once the tests reference the intended typed store contract; that is acceptable TDD evidence for a missing contract.

1. `go-relay-server/inbox_test.go`

   Add `TestHandleInboxStream_StoreBackendErrorReturnsError`.

   Shape:

   - Use `setupInboxStreamEnv`.
   - Construct `InboxStore` with a local fake `InboxBackend` whose `Store` returns an error. Implement the fake as a test-only backend that embeds or delegates to `newMemoryInboxBackend()` for non-`Store` methods and overrides only `Store`, so retrieval/count/ack behavior remains meaningful.
   - Send an inbox `store` request through a mocknet stream.
   - Assert `resp.Status == "ERROR"`.
   - Assert `resp.Error` is non-empty and includes enough context to identify store failure.
   - Assert no message is retrievable for the recipient.

   This is the incident-critical regression. It fails today because the stream handler ignores the store result and replies OK.

2. `go-relay-server/inbox_test.go`

   Add `TestHandleInboxStream_StoreDuplicateReturnsOKWithoutSecondPendingMessage`.

   Shape:

   - Use the memory backend and the existing stream harness.
   - Send the same encrypted v2/chat envelope ID twice to the same recipient.
   - Assert both stream responses are `OK`.
   - Assert first response `storeStatus` is `stored` and second response `storeStatus` is `duplicate`.
   - Assert `retrieve_pending` returns exactly one pending message.

   This pins the user's clarified rule: if the message is already in the inbox, success is acceptable.

3. `go-relay-server/backend_redis_test.go`

   Add `TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure`.

   Shape:

   - Create a Redis backend against `miniredis`.
   - Stop/close the server or otherwise use a dead client before `Store`.
   - Assert `Store` returns a non-nil error.
   - Assert the result is not `stored` or `duplicate`.

   This proves Redis backend failures are no longer indistinguishable from duplicates.

4. Update existing duplicate tests:

   - `TestRedisInboxBackend_DedupesByMessageIDAcrossClients` should expect first store result `stored`, second result `duplicate`, both with nil error, and final count 1.
   - Existing `inbox_dedup_test.go` duplicate and push suppression tests should assert the typed result where they currently rely on bool.

## step-by-step implementation plan

1. Red test pass:

   - Add the stream error test, duplicate idempotence stream test, and Redis failure test first.
   - Run focused tests and record the expected failing state:

     ```bash
     cd go-relay-server && go test ./... -run 'TestHandleInboxStream_StoreBackendErrorReturnsError|TestHandleInboxStream_StoreDuplicateReturnsOKWithoutSecondPendingMessage|TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure|TestRedisInboxBackend_DedupesByMessageIDAcrossClients'
     ```

2. Introduce a typed 1:1 inbox store result in `go-relay-server/inbox_store.go`.

   Suggested contract:

   ```go
   type InboxStoreResult string

   const (
       InboxStoreResultStored    InboxStoreResult = "stored"
       InboxStoreResultDuplicate InboxStoreResult = "duplicate"
   )

   type InboxBackend interface {
       Store(toPeerId string, entry inboxMessage) (InboxStoreResult, error)
       ...
   }
   ```

   No separate `failed` result is needed because failures should be represented as `error`.

3. Update memory-backed stores.

   - `memoryInboxBackend.Store`: return `(InboxStoreResultDuplicate, nil)` for same-recipient duplicate message IDs and `(InboxStoreResultStored, nil)` after append.
   - `memoryInboxBackendLimited.Store`: same result semantics, preserving cap and dedupe behavior.

4. Update Redis-backed store.

   - JSON marshal failure returns an error.
   - Redis `LRange`, watch retry, and replace-list errors return an error.
   - Existing pending duplicate returns `(InboxStoreResultDuplicate, nil)`.
   - Successful list replacement with appended payload returns `(InboxStoreResultStored, nil)`.
   - Preserve TTL/cap/prune behavior exactly unless a test proves the existing behavior already violates the new contract.

5. Update `InboxStore.Store` in `go-relay-server/inbox.go`.

   - Return `(InboxStoreResult, error)`.
   - If the backend returns error, log it and return the error.
   - If result is `duplicate`, preserve current metrics visibility by incrementing `inboxStoredCounter`, then return without firing push or recording `biz.RecordMessageStored()`.
   - If result is `stored`, increment `inboxStoredCounter`, record `biz.RecordMessageStored()`, log, and fire push only for supported user-visible envelopes.
   - Do not add a new duplicate metric or dashboard change in this session.

6. Update `inboxResponse` and `HandleInboxStream`.

   - Add `StoreStatus string` with JSON tag `json:"storeStatus,omitempty"` to `inboxResponse` for backward-compatible observability.
   - In the 1:1 `"store"` branch:
     - call `result, err := inbox.Store(req.To, entry)`.
     - on error, return `inboxResponse{Status: "ERROR", Error: "store failed: ..."}`.
     - on nil error, return `inboxResponse{Status: "OK", StoreStatus: string(result)}`.
   - Do not change request shape or `Status` strings.

7. Update all Go relay tests and call sites for the new return signature.

   - For setup stores where the result is not part of the assertion, use `_, err := inbox.Store(...)` and fail the test on unexpected error.
   - For duplicate tests, assert the exact result.
   - Do not silently ignore errors in test setup unless the test is intentionally about unrelated setup data and an error would already fail later in a clear way.

8. Confirm no Flutter implementation change is needed.

   - Re-read `go-mknoon/node/inbox.go` after the relay response change.
   - Treat `go-mknoon/node/inbox.go` as read-only evidence for this plan. Do not modify it just to parse the optional `storeStatus` field; Go JSON decoding already ignores unknown response fields.
   - If `resp.Status != "OK"` still returns an error, leave Go node and Flutter unchanged.
   - Stop if the implementation would require Go node, bridge, Flutter retry, or Flutter status-model changes; that would be broader than this plan and should be replanned.

9. Cleanup pass.

   - Run `gofmt` on touched Go files.
   - Keep comments short and only where they explain the stored-vs-duplicate-vs-error contract.
   - Do not refactor group inbox, push token storage, rendezvous, or retry orchestration.

## risks and edge cases

- Duplicate store vs backend failure: the core risk is accidentally treating duplicate as error, which would make idempotent retry noisy and could keep messages stuck after a successful prior inbox store.
- Backend failure after reconnect: the relay must return `ERROR` so the sender does not clear `wireEnvelope` or mark inbox delivery incorrectly.
- Redis watch conflicts: transient Redis watch failures should continue through existing retry helper behavior; final failure must become error.
- Redis prune-on-duplicate branch: when a duplicate is found and expired entries are pruned, the result should still be duplicate with nil error if Redis replacement succeeds; if replacement fails, return error.
- Push notification duplication: duplicate stores must not send push again.
- Metric naming mismatch: the existing counter currently increments for duplicate skips too. Preserve that behavior in this session even though the name is imperfect; changing dashboard semantics is out of scope.
- Large mechanical test updates: many tests call `InboxStore.Store`; update these carefully without changing asserted behavior.

## exact tests and gates to run

Required focused red/green commands during implementation:

```bash
cd go-relay-server && go test ./... -run 'TestHandleInboxStream_StoreBackendErrorReturnsError|TestHandleInboxStream_StoreDuplicateReturnsOKWithoutSecondPendingMessage|TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure|TestRedisInboxBackend_DedupesByMessageIDAcrossClients'
```

Required final Go relay command:

```bash
cd go-relay-server && go test ./...
```

Required repository hygiene:

```bash
git diff --check
```

Named Flutter gates:

- Not required if implementation stays inside `go-relay-server` and does not modify `go-mknoon`, Flutter retry code, bridge payloads, or gate docs.
- If implementation evidence shows `go-mknoon/node/inbox.go`, bridge APIs, or Flutter retry/status code must change, stop this session as blocked and replan instead of expanding under this contract. If a future replanned session does include those files, it should define exact module-local tests plus:

  ```bash
  ./scripts/run_test_gates.sh 1to1
  ./scripts/run_test_gates.sh transport
  ```

Gate-doc completeness:

- If any new Flutter test file is added or `Test-Flight-Improv/test-gate-definitions.md` is touched, run:

  ```bash
  ./scripts/run_test_gates.sh completeness-check
  ```

## known-failure interpretation

- A failing newly added relay test is expected during the red phase only.
- Existing skipped tests, such as the skipped push sender injection test, are not regressions.
- If `cd go-relay-server && go test ./...` exposes failures outside touched 1:1 inbox store behavior, rerun the same command before and after the change if needed to classify pre-existing failures. Do not claim closure while the new stream/backend regressions are red.
- If optional Flutter named gates are run because scope expanded, classify known simulator or integration infrastructure failures separately from relay-store correctness. Do not use unrelated Flutter infrastructure failures to block this Go-only fix unless the implementation touched that path.

## done criteria

- The new stream backend-error test fails before implementation and passes after implementation.
- The duplicate store stream test passes and proves duplicate remains OK with exactly one pending message.
- The Redis failure test passes and proves backend failure returns error.
- Existing Redis duplicate test passes with typed duplicate result.
- All direct `InboxStore.Store` and `InboxBackend.Store` call sites compile with the new contract.
- `cd go-relay-server && go test ./...` passes.
- `git diff --check` passes.
- No Flutter or product-status behavior changes are included unless a new blocker is discovered and replanned.

## scope guard

Do not implement:

- delivery receipts or receiver-read confirmation;
- multi-relay shared-state/failover changes;
- relay selection changes;
- Flutter UI status changes;
- retry scheduler refactors;
- group inbox contract changes;
- push-notification architecture changes;
- dashboard or alerting expansion beyond preserving existing metrics behavior.

Overengineering signals:

- adding a new sender-visible message state;
- adding a separate outbox/inbox reconciliation protocol;
- changing app delivery semantics from "accepted into inbox" to "opened by recipient";
- modifying multiple relay support even though the user explicitly said one relay is active right now.

## accepted differences / intentionally out of scope

- Inbox acceptance is treated as delivery for this plan. Actual user-b app retrieval, notification arrival, and UI rendering are not part of this fix.
- Direct peer ACK behavior stays different from relay inbox behavior: direct send can require receiver-side app confirmation, while relay inbox send succeeds at relay persistence.
- Multi-relay durability and shared-state failover remain out of scope because the user explicitly said to ignore that point for now.
- Group inbox behavior is intentionally not changed even though it already uses error-returning store semantics.

## dependency impact

This plan unblocks a reliable sender status contract for WiFi-to-5G fallback and offline inbox retry flows. Later work that investigates receiver catch-up, notification routing, multi-relay failover, or full delivery receipts should depend on this contract: sender-side inbox delivery means the relay accepted or already had the message, not merely that a stream response was written.

If implementation evidence shows the Go node does not propagate relay `ERROR` to Flutter as currently indicated by `go-mknoon/node/inbox.go`, stop and replan with `go-mknoon` bridge/client scope included.

## reviewer pass

Sufficiency: sufficient after current adjustments.

Missing files, tests, regressions, or gates:

- No structural file or gate is missing.
- The required stream, duplicate, and Redis regressions are named exactly.
- The required final Go relay suite and repository hygiene command are exact.
- Flutter named gates are correctly excluded for a Go-relay-only implementation, with an explicit replan stop if Go node, bridge, or Flutter scope becomes necessary.

Stale or incorrect assumptions:

- Current code still has `InboxBackend.Store(...) bool`; memory, limited memory, and Redis backends still collapse duplicate/failure into false or no error path.
- Current `HandleInboxStream` still ignores the store result and returns `Status: "OK"` for the 1:1 store branch.
- Current `go-mknoon/node/inbox.go` still returns an error when relay store response status is not `OK`, so client propagation remains read-only evidence.

Overengineering:

- The typed store result is not overengineering because the current bool contract is the root ambiguity.
- Adding delivery receipts, new UI states, duplicate metrics, or multi-relay recovery would be overengineering for this session.

Decomposition:

- The work is decomposed enough: first stream/backend tests, then store interface, then backend implementations, then wrapper/handler response, then mechanical call-site updates and Go relay gates.

Minimum needed to make the plan sufficient:

- Keep the typed result plus error contract.
- Keep the stream-level backend-error regression.
- Keep duplicate OK/idempotence regression.
- Keep Redis failure regression.
- Preserve existing metrics visibility and Flutter retry behavior.
- Stop and replan if client propagation evidence changes.

## arbiter decision

Structural blockers:

- None.

Incremental details:

- The fake backend shape and `storeStatus` response detail are now explicit enough for implementation.
- The Go client boundary is explicit: read `go-mknoon/node/inbox.go` as propagation evidence, but stop and replan if modifying it becomes necessary.
- Metric semantics are intentionally preserved to avoid unrelated dashboard drift.

Accepted differences:

- Relay inbox acceptance remains the sender delivery threshold for this plan.
- Receiver retrieval/rendering, delivery receipts, and multi-relay durability remain intentionally out of scope.

Final verdict:

- `execution-ready`
