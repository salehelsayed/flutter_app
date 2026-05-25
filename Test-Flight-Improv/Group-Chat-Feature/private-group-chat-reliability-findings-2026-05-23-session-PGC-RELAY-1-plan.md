# Session PGC-RELAY-1 Plan: Group Inbox Recipient ACL

Status: execution-ready

## Planning Progress

- 2026-05-23 23:22:45 CEST | role: Reviewer completed | files inspected since last update: full draft plan artifact | decision/blocker: sufficient with adjustments; direct `GroupInboxStore.Store`/concrete backend `Store` helper wording could leave a no-ACL write path ambiguous | next action: Arbiter pass
- 2026-05-23 23:23:13 CEST | role: Arbiter started/completed | files inspected since last update: reviewer pass 1 and draft plan | decision/blocker: one structural blocker found: ambiguous direct-store compatibility could preserve the row defect; no accepted differences need reopening | next action: patch the plan once, then run final reviewer and arbiter passes
- 2026-05-23 23:24:57 CEST | role: Final Reviewer started | files inspected since last update: patched plan sections for closure bar, regression tests, implementation steps, done criteria, and accepted differences | decision/blocker: checking whether the structural direct-store blocker is resolved | next action: complete final sufficiency review
- 2026-05-23 23:24:57 CEST | role: Final Reviewer completed | files inspected since last update: patched full plan artifact | decision/blocker: sufficient as-is; no missing files, tests, gates, or scope guard gaps found | next action: final Arbiter pass
- 2026-05-23 23:25:24 CEST | role: Final Arbiter started/completed | files inspected since last update: final reviewer pass and patched full plan artifact | decision/blocker: no structural blockers remain; incremental helper-test placement detail intentionally deferred | next action: mark execution-ready

## real scope

Make the `go-relay-server` group inbox backend contract require recipient ACL persistence for group offline inbox writes.

In scope:

- `go-relay-server/group_inbox_store.go`: move recipient-scoped store into the required `GroupInboxBackend` contract and remove the optional `GroupInboxRecipientBackend` fallback path from `GroupInboxStore.store`.
- `go-relay-server/inbox.go`: keep stream-level `group_store` requiring non-empty `recipientPeerIds`, keep `from` bound to the authenticated remote peer, and keep `group_retrieve` / cursor retrieve deriving requester identity from the authenticated stream peer.
- `go-relay-server/backend_memory.go` and `go-relay-server/backend_redis.go`: keep memory and Redis backends satisfying the mandatory recipient-aware contract.
- Direct store compatibility helpers only if needed for existing tests; any retained helper must route through recipient-aware storage with a sender-only ACL, not an empty ACL.
- Focused Go tests only under `go-relay-server`.

Out of scope:

- Flutter/Dart group send, drain, listener, DB, notification route, key, membership, or UI behavior.
- `go-mknoon` node or bridge behavior.
- New relay auth, membership validation, encryption/signature format changes, push payload redesign, or Redis schema migration beyond preserving the existing `recipientPeerIds` JSON field.

## closure bar

PGC-015 is good enough when every relay group inbox backend accepted by `NewGroupInboxStoreWithBackend` must implement recipient-scoped storage, the required backend interface no longer includes the legacy non-ACL `Store` method, `GroupInboxStore.store` cannot silently fall back to a non-ACL backend, stream `group_store` still rejects missing recipients before storage, and authorized retrieve/cursor paths still expose messages only to the sender or listed recipients.

The row cannot be closed by stream-handler tests alone. Closure requires a backend-contract regression that fails against the current optional interface and legacy interface method, focused stream authorization regressions, and green module-local Go gates.

## source of truth

- Primary row source: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md` row `PGC-015`.
- Session source: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md` session `PGC-RELAY-1`.
- Current code and tests in `go-relay-server` win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; for this Go-only backend session, exact `go-relay-server` commands below are the required gates.
- If gate docs and scripts disagree, `scripts/run_test_gates.sh` wins for named Flutter gates, but no Flutter named gate is required unless implementation unexpectedly touches Flutter, `go-mknoon`, or gate definitions.

## session classification

`implementation-ready`

## exact problem statement

Row `PGC-015` says relay recipient ACL is optional in relay core. Current stream handling already rejects empty `recipientPeerIds` for `group_store` and retrieves by authenticated remote peer, but `GroupInboxStore.store` can still type-assert an optional `GroupInboxRecipientBackend`; if the backend does not implement it, the store falls back to `backend.Store(groupId, from, message)` and drops recipient ACL data.

The user-visible risk is private group offline replay loss or privacy breakage after backend substitution or shared-state migration: a backend can compile and be wired while not persisting recipient ACLs, making recipient-scoped retrieve unable to enforce the intended sender/recipient access contract.

Must improve:

- backend substitutions fail at compile time or direct construction time unless they support recipient-scoped store;
- writes that include recipient lists must persist normalized recipient IDs;
- direct relay group inbox helper writes, if retained, must not create new empty-ACL records when sender identity is available;
- stream retrieval remains bound to authenticated stream peer, not caller-supplied requester fields.

Must stay unchanged:

- non-destructive group inbox retrieve behavior;
- cursor pagination and history-gap metadata;
- push fanout after durable store;
- one-to-one inbox behavior;
- existing memory and Redis storage ordering, TTL, cap, and stats behavior.

## files and repos to inspect next

Production files:

- `go-relay-server/group_inbox_store.go`
- `go-relay-server/inbox.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/server_bootstrap.go`

Focused tests:

- `go-relay-server/group_inbox_test.go`
- `go-relay-server/inbox_test.go`
- `go-relay-server/backend_redis_test.go`
- `go-relay-server/failover_test.go`
- `go-relay-server/limits_test.go`
- `go-relay-server/server_bootstrap_test.go`

Gate/config docs:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh` only to confirm no Flutter named gate was made necessary.

## existing tests covering this area

Current coverage already pins adjacent behavior:

- `TestHandleInboxStream_GroupRetrieveFiltersByRecipientAuthorization` proves authenticated stream retrieve returns the recipient message, denies an intruder, and lets the sender read its own stored replay.
- `TestHandleInboxStream_GroupRetrieveCursorSkipsUnauthorizedMessages` proves cursor paging skips messages whose recipient ACL excludes the requester.
- `TestGI017GroupInboxStoreAuthorizedCursorPaginationReturns120MessagesExactlyOnce` proves authorized cursor pagination over 120 messages and denies an unauthorized peer.
- `TestHandleInboxStream_GroupStoreRejectsSpoofedFromPeer` proves `group_store` cannot spoof `from`.
- `TestHandleInboxStream_GroupStoreFansOutPushToRecipientsWithTokens` proves group push fanout runs after durable group store and skips sender push.
- `TestTwoRelayServers_SharedGroupInboxBackend` proves shared group inbox backend visibility across relay instances.
- `TestRedisGroupInboxBackend_CursorStableAcrossClients` and `TestRedisGroupInboxBackend_PreservesOpaqueReplayEnvelopeAcrossClients` prove Redis group inbox cursor/order/envelope persistence across clients.

Missing coverage:

- no direct test proves `GroupInboxBackend` itself requires `StoreWithRecipients`;
- no direct test proves `GroupInboxStore.store` has no optional fallback to a backend that drops recipient ACLs;
- no direct test proves helper `Store` methods, if retained, avoid empty-ACL writes;
- no direct stream regression currently named for missing/empty `recipientPeerIds`, even though the handler has the check.

## regression/tests to add first

Add these before implementation:

1. `TestGroupInboxBackendContractRequiresRecipientStore` in `go-relay-server/group_inbox_test.go` or a new `go-relay-server/group_inbox_store_test.go`.
   - Use `reflect.TypeOf((*GroupInboxBackend)(nil)).Elem()` and assert the interface has `StoreWithRecipients`.
   - Assert the same interface does not expose legacy `Store(groupId, from, message string) error`.
   - This should fail before the contract change and pass after the backend interface requires recipient-scoped store and drops the non-ACL method from the required contract.
2. `TestGroupInboxStorePassesRecipientACLToBackendContract` in `go-relay-server/group_inbox_test.go`.
   - Use a custom test backend that records the exact `recipientPeerIds` passed to `StoreWithRecipients`.
   - Call `StoreWithPushRecipients` with duplicates and blanks, then assert the backend saw normalized recipients and that `RetrieveAuthorized` admits only sender/listed recipient.
3. `TestGroupInboxStoreStoreHelperUsesSenderACL` in `go-relay-server/group_inbox_test.go` if `GroupInboxStore.Store` remains.
   - Call `Store("group", "peer-a", "msg")`, retrieve the raw message, and assert `RecipientPeerIds` is exactly `["peer-a"]`.
4. `TestHandleInboxStream_GroupStoreRejectsMissingRecipientPeerIds` in `go-relay-server/inbox_test.go`.
   - Send `group_store` with nil/empty `recipientPeerIds`.
   - Assert `ERROR`, error text containing `recipientPeerIds`, and zero persisted group inbox messages.
5. `TestRedisGroupInboxBackend_PreservesRecipientPeerIdsAcrossClients` in `go-relay-server/backend_redis_test.go` if Redis tests do not already assert the field.
   - Store with `StoreWithRecipients` through client A, retrieve through client B, and assert normalized `RecipientPeerIds`.
6. If concrete `memoryGroupInboxBackend.Store` or `redisGroupInboxBackend.Store` helpers are retained, add helper-specific tests proving each retained helper stores sender-only ACL rather than an empty ACL. If those helpers are removed and all tests use `StoreWithRecipients`, no helper-specific backend test is required.

If the first reflection test unexpectedly passes before implementation, stop and inspect whether a prior worktree change already made the backend contract mandatory. Do not keep implementing unless `GroupInboxStore.store` still has the optional fallback or tests still miss the stream/backend ACL proof.

## step-by-step implementation plan

1. Add the regression tests above and run the first direct selector. Confirm `TestGroupInboxBackendContractRequiresRecipientStore` fails for the expected reason before code changes.
2. In `go-relay-server/group_inbox_store.go`, replace the required `GroupInboxBackend.Store(...)` method with required `StoreWithRecipients(groupId, from, message string, recipientPeerIds []string) error`. Remove the separate optional `GroupInboxRecipientBackend` interface unless another file still needs it after refactor.
3. In `go-relay-server/inbox.go`, replace the optional type assertion in `GroupInboxStore.store` with a direct call to `s.backend.StoreWithRecipients(...)`. Do not call `s.backend.Store(...)` from that path.
4. Normalize recipients in `GroupInboxStore.store` before the backend call so custom backends receive the same deduplicated non-empty ACL as memory and Redis. Return an error for empty normalized recipients from recipient-aware store calls.
5. Keep or narrow `GroupInboxStore.Store(groupId, from, message)` only as a compatibility helper for existing non-authorized store tests. If it remains, it must call the same recipient-aware path with `[]string{from}` and must not create an empty ACL record.
6. Remove concrete backend `Store(...)` helper methods if practical. If memory or Redis helpers are retained for direct tests, keep them outside the `GroupInboxBackend` contract and make them call `StoreWithRecipients(..., []string{from})`.
7. Update memory and Redis backend compile-time assertions or method sets as needed. They already have `StoreWithRecipients`; do not change ordering, TTL, cap, ID, or pruning semantics.
8. Update focused tests that call backend or store `Store(...)` only if the interface change requires it. Prefer `StoreWithPushRecipients` / `StoreWithRecipients` in ACL-sensitive tests; leave unrelated legacy tests alone when they are verifying ordering, TTL, or pagination behavior and can use sender-only ACL safely.
9. Run `gofmt` on changed Go files.
10. Run the exact direct Go selectors listed below. Fix only failures caused by this contract change.
11. Run full `go-relay-server` module tests and diff hygiene.
12. Update row `PGC-015` and this breakdown ledger only in the implementation/closure session, not during this planning-only turn.

Stop early if tests prove the backend contract is already mandatory and no optional fallback remains. In that case, classify PGC-015 as stale/already-covered with evidence instead of making a cosmetic refactor.

## risks and edge cases

- A custom backend that previously implemented only `Store` should no longer be accepted as a `GroupInboxBackend`.
- Direct helper calls to `GroupInboxStore.Store` or concrete backend `Store` can accidentally preserve the old no-ACL write path; remove those helpers or keep them sender-ACL-only and outside the required backend contract.
- Redis JSON decode must continue accepting stored records with absent `recipientPeerIds` from older data, but new writes must persist the normalized field when recipients are supplied.
- Authorized cursor pagination must continue skipping unauthorized messages without ending pagination early.
- Push fanout must still occur after durable store, and duplicate group message fanout behavior must not change.
- Existing failover/shared-backend tests must still pass with memory and Redis backends.

## exact tests and gates to run

Regression-first expected failing proof:

```bash
cd go-relay-server && go test ./... -run 'TestGroupInboxBackendContractRequiresRecipientStore' -count=1 -v
```

Focused direct Go tests after implementation:

```bash
cd go-relay-server && go test ./... -run 'TestGroupInboxBackendContractRequiresRecipientStore|TestGroupInboxStorePassesRecipientACLToBackendContract|TestGroupInboxStoreStoreHelperUsesSenderACL|TestMemoryGroupInboxBackendStoreHelperUsesSenderACL|TestHandleInboxStream_GroupStoreRejectsMissingRecipientPeerIds|TestHandleInboxStream_GroupStoreRejectsSpoofedFromPeer|TestHandleInboxStream_GroupRetrieveFiltersByRecipientAuthorization|TestHandleInboxStream_GroupRetrieveCursorSkipsUnauthorizedMessages|TestGI017GroupInboxStoreAuthorizedCursorPaginationReturns120MessagesExactlyOnce|TestTwoRelayServers_SharedGroupInboxBackend|TestRedisGroupInboxBackend_PreservesRecipientPeerIdsAcrossClients|TestRedisGroupInboxBackendStoreHelperUsesSenderACL|TestRedisGroupInboxBackend_CursorStableAcrossClients|TestRedisGroupInboxBackend_PreservesOpaqueReplayEnvelopeAcrossClients' -count=1 -v
```

Focused existing slice:

```bash
cd go-relay-server && go test ./... -run 'GroupInbox|GroupStore|GroupRetrieve|RedisGroupInbox|TwoRelayServers_SharedGroupInbox' -count=1 -v
```

Full module gate:

```bash
cd go-relay-server && go test ./... -count=1
```

Formatting and diff hygiene:

```bash
gofmt -w go-relay-server/group_inbox_store.go go-relay-server/inbox.go go-relay-server/backend_memory.go go-relay-server/backend_redis.go go-relay-server/group_inbox_test.go go-relay-server/inbox_test.go go-relay-server/backend_redis_test.go
git diff --check
```

Named Flutter gates:

- None required for the intended scope because this is a Go relay backend contract change only.
- If implementation unexpectedly edits Flutter, `go-mknoon`, scripts, gate definitions, or integration harnesses, stop and replan before adding broader gates.

## known-failure interpretation

- The regression-first command must fail before implementation for the missing `StoreWithRecipients` method on `GroupInboxBackend`. Any other failure in that command is not valid PGC-015 evidence.
- After implementation, any failure in the direct group inbox, group store, group retrieve, Redis group inbox, or shared group backend selectors is a session blocker.
- A full `go test ./... -count=1` failure outside the direct PGC-015 selectors may be treated as pre-existing only if it is documented with exact failing test output and reproduced without the PGC-015 diff or already tracked in repo evidence. Do not use an unrelated historical failure to waive a new compile failure or ACL behavior failure.
- The dirty worktree contains unrelated modified and untracked files; do not revert or overwrite them while interpreting failures.

## done criteria

- `GroupInboxBackend` requires recipient-scoped storage.
- `GroupInboxBackend` no longer requires or exposes the legacy non-ACL `Store` method.
- `GroupInboxStore.store` no longer contains an optional recipient backend type assertion or fallback that can drop supplied recipients.
- Any retained `Store` helper writes through recipient-aware storage with sender-only ACL.
- Stream `group_store` rejects missing/empty `recipientPeerIds` with no stored message.
- Authorized retrieve and cursor retrieve still deny peers not in sender/recipient ACL.
- Memory and Redis group inbox backends compile and preserve recipient IDs on new writes.
- All required direct Go tests, full `go-relay-server` module tests, `gofmt`, and `git diff --check` pass or any unrelated full-module failure is documented under the known-failure rule.
- Row `PGC-015` and the session breakdown ledger are ready for closure update by the implementation/closure workflow.

## scope guard

Do not change:

- Flutter/Dart product code or tests.
- `go-mknoon` node, bridge, pubsub validators, group crypto, membership validation, or transport behavior.
- one-to-one inbox APIs, push token storage, push notification payload shape, media relay, rendezvous, profiles, limits unrelated to group inbox ACL, or server bootstrap behavior beyond compile-required backend interface updates.
- authenticated stream identity rules. `group_retrieve` must continue using `s.Conn().RemotePeer().String()`, not a requester field from JSON.
- Redis key layout or a data migration. Backward decode of old records without `recipientPeerIds` should remain tolerant.
- Matrix and breakdown status during this planning-only task.

Overengineering would include adding group membership ACL validation in the relay, a new auth service, admin role checks, encrypted-envelope changes, background push redesign, simulator E2E coverage, or broad gate-definition changes.

## accepted differences / intentionally out of scope

- Relay backend ACL persistence is not the same as group membership correctness. The relay enforces sender/recipient storage and authenticated retrieve filtering; app/node membership validation remains owned by other sessions.
- Legacy records that already lack `recipientPeerIds` may remain unreadable to recipients under authorized retrieve. Backfilling historical ACLs is intentionally out of scope because the relay cannot reconstruct the intended recipient set safely.
- Direct non-stream helper reads through `Retrieve` are allowed to remain for tests and backend maintenance. Direct helper writes are allowed only if they create a sender-only ACL and stay outside the required backend contract.

## dependency impact

Later private-group reliability work that depends on durable offline replay privacy can assume group inbox backends cannot be substituted without recipient ACL support. If this plan changes to evidence-only or stale/already-covered, downstream sessions that rely on relay backend ACL hardening should refresh their source assumptions before closure.

## planner notes

- Exact source row and session both classify PGC-015 as implementation-ready with no dependency on earlier sessions.
- `go test ./... -list 'GroupInbox|GroupStore|GroupRetrieve|RedisGroupInbox|TwoRelayServers_SharedGroupInbox'` was run in `go-relay-server` during planning and confirmed the existing selector names used above.

## reviewer pass 1

Sufficiency: sufficient with adjustments.

Missing or weak items:

- The plan correctly requires `StoreWithRecipients` on the backend interface and removal of the optional fallback, but the `GroupInboxStore.Store` and concrete backend `Store` compatibility helper language is too permissive. It could leave an ambiguous no-ACL direct write path in relay core.
- The normalization expectation for custom backends should be explicit: either `GroupInboxStore` normalizes before the backend call or the backend contract comment makes normalization mandatory. Store-level normalization is safer for custom backend consistency and does not broaden product scope.

Stale or incorrect assumptions: none found against current source row, breakdown, or relay code.

Overengineering: none, as long as implementation does not add membership validation, new auth services, Redis migrations, Flutter gates, or simulator coverage.

Decomposition: narrow enough after tightening the direct-store rule.

Minimum needed to make the plan sufficient:

- Make the plan require no new relay group inbox write path to persist an empty ACL when a sender/recipient context is available.
- Prefer removing `Store` from `GroupInboxBackend`; if concrete helper methods remain, mark them outside the backend contract and route them through recipient-aware storage with at least sender-only ACL.

## arbiter pass 1

Structural blockers:

- Direct-store ambiguity is structural. If `GroupInboxStore.Store` or concrete backend `Store` methods can still persist a new group inbox message without recipient ACL context, the plan would not safely close PGC-015.

Incremental details:

- Exact file placement for the new reflection test can remain flexible between `group_inbox_test.go` and a small `group_inbox_store_test.go`.

Accepted differences:

- Relay ACL persistence remains separate from app/node group membership validation and historical ACL backfill.

## final reviewer pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none. The plan now requires a failing backend-interface reflection regression, recipient pass-through proof, helper write ACL proof if helpers remain, missing-recipient stream proof, Redis recipient persistence proof, focused existing authorization selectors, full `go-relay-server` module tests, `gofmt`, and `git diff --check`.

Stale or incorrect assumptions: none found. Current code still has `GroupInboxBackend.Store`, optional `GroupInboxRecipientBackend`, and the fallback path this plan targets.

Overengineering: none. The scope guard explicitly blocks Flutter, `go-mknoon`, membership validation, auth redesign, Redis migration, push redesign, simulator E2E, and gate-definition expansion.

Decomposition: sufficient. One backend contract change, one store-call path change, compile-required backend/test updates, and direct Go verification.

Minimum needed: already included.

## final arbiter pass

Structural blockers:

- None remaining.

Incremental details:

- Exact file placement for the reflection/backend contract test remains flexible between `group_inbox_test.go` and a new `group_inbox_store_test.go`.
- Helper-specific backend tests are conditional: add them only for retained concrete `Store` helpers.

Accepted differences:

- Relay ACL persistence remains separate from app/node membership correctness.
- Historical records without recipient ACLs are not backfilled in this session.

## final planning output

Final verdict: execution-ready for row `PGC-015` / session `PGC-RELAY-1`.

Final plan: implement the mandatory recipient-aware `GroupInboxBackend` contract in `go-relay-server`, remove the optional recipient-backend fallback, prevent retained helper writes from creating empty ACL records, and prove the contract with focused Go regressions and full module tests.

Structural blockers remaining: none.

Incremental details intentionally deferred: exact test file placement and helper-specific tests only if helpers are retained.

Accepted differences intentionally left unchanged: no Flutter/Dart work, no `go-mknoon` work, no relay membership validator, no Redis migration, no push redesign, and no historical ACL backfill.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-relay-server/group_inbox_store.go`
- `go-relay-server/inbox.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/inbox_test.go`
- `go-relay-server/backend_redis_test.go`
- `go-relay-server/failover_test.go`
- `go-relay-server/limits_test.go`
- `go-relay-server/server_bootstrap.go`
- `go-relay-server/server_bootstrap_test.go`

Why the plan is safe to implement now: the source row is implementation-ready with no earlier-session dependency; the code gap is isolated to the relay-server group inbox backend contract and store path; direct regressions are named before code changes; the exact Go gates are bounded; and the scope guard blocks unrelated product, transport, membership, push, and migration work.

## execution progress

- 2026-05-23 23:53 CEST | phase: RED regression proof | files touched: `go-relay-server/group_inbox_test.go`, `go-relay-server/inbox_test.go`, `go-relay-server/backend_redis_test.go` | command: `cd go-relay-server && go test ./... -run 'TestGroupInboxBackendContractRequiresRecipientStore' -count=1 -v` | result: failed as expected with `GroupInboxBackend must require StoreWithRecipients`.
- 2026-05-23 23:53 CEST | phase: implementation | files touched: `go-relay-server/group_inbox_store.go`, `go-relay-server/inbox.go`, `go-relay-server/backend_memory.go`, `go-relay-server/backend_redis.go` | result: `GroupInboxBackend` now requires `StoreWithRecipients`, optional fallback was removed, store wrapper normalizes/rejects empty ACLs, retained helpers use sender-only ACLs.
- 2026-05-23 23:53 CEST | phase: focused verification | command: `cd go-relay-server && go test ./... -run 'TestGroupInboxBackendContractRequiresRecipientStore|TestGroupInboxStorePassesRecipientACLToBackendContract|TestGroupInboxStoreStoreHelperUsesSenderACL|TestMemoryGroupInboxBackendStoreHelperUsesSenderACL|TestHandleInboxStream_GroupStoreRejectsMissingRecipientPeerIds|TestHandleInboxStream_GroupStoreRejectsSpoofedFromPeer|TestHandleInboxStream_GroupRetrieveFiltersByRecipientAuthorization|TestHandleInboxStream_GroupRetrieveCursorSkipsUnauthorizedMessages|TestGI017GroupInboxStoreAuthorizedCursorPaginationReturns120MessagesExactlyOnce|TestTwoRelayServers_SharedGroupInboxBackend|TestRedisGroupInboxBackend_PreservesRecipientPeerIdsAcrossClients|TestRedisGroupInboxBackendStoreHelperUsesSenderACL|TestRedisGroupInboxBackend_CursorStableAcrossClients|TestRedisGroupInboxBackend_PreservesOpaqueReplayEnvelopeAcrossClients' -count=1 -v` | result: passed.
- 2026-05-23 23:53 CEST | phase: focused slice verification | command: `cd go-relay-server && go test ./... -run 'GroupInbox|GroupStore|GroupRetrieve|RedisGroupInbox|TwoRelayServers_SharedGroupInbox' -count=1 -v` | result: passed.
- 2026-05-23 23:53 CEST | phase: full module and hygiene | commands: `cd go-relay-server && go test ./... -count=1`; `git diff --check` | result: both passed.

## execution result

Final verdict: accepted.

Files changed:

- `go-relay-server/group_inbox_store.go`
- `go-relay-server/inbox.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/inbox_test.go`
- `go-relay-server/backend_redis_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-RELAY-1-plan.md`

Required evidence:

- Backend contract regression proves `GroupInboxBackend` requires `StoreWithRecipients` and no longer exposes legacy `Store`.
- Store-level regression proves normalized recipient ACLs reach the required backend contract and authorized retrieve denies unlisted peers.
- Helper regressions prove retained memory, Redis, and wrapper `Store` helpers persist sender-only ACLs instead of empty ACLs.
- Stream regression proves `group_store` rejects omitted and empty `recipientPeerIds` without storing messages.
- Redis regression proves recipient ACLs persist across clients.

Unrelated failures: none observed in the required relay-server gates.
