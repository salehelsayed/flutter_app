# FDC-10 — Durable inbox backend (Redis) + relay pool  (Modification | Ops/Config)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§8 P2-2 "Durable inbox backend (NOT idempotency — that exists)"; §9 phase-3 ordering hazard; §12 "deposit to a relay pool, not one relay" / "small FIXED relay pool"; §6.2 circuit-v2 1-reservation/peer)

## Source Of Truth
- Proposal §8 P2-2, §9, §12. The proposal's own appendix (§12, Appendix evidence index) explicitly says store-dedup ALREADY EXISTS — this plan must NOT re-add it.
- `scripts/run_test_gates.sh` (the gate families) wins over prose where they conflict.
- Epic roadmap: FDC-00 (durability/pool is the "additive relay deploy" phase; P0-2 concurrent-inbox volume must land AFTER durability is live → see Dependency Impact).
- Go is the source of truth here: the path decision stays in Dart `sendChatMessage`; FDC-10 touches ONLY the relay server (durability) and the Go host's relay-address pool (deposit/retrieve targets). No Dart send-ladder edits.

## Session Classification
**evidence-gated.** The durability flip itself is a deploy/ops action (env var) on a relay environment whose `.env`/secrets are gitignored → the *live* effect is unverifiable from-repo (flagged throughout). The from-repo code surface is small, host-testable, and implementation-ready; the deploy + 2nd-relay provisioning steps are ops-gated.

## Exact Problem Statement
**What's broken/missing.** The relay inbox runs the **in-memory backend by default**: `loadBackendConfigFromEnv()` returns `backendKindMemory` whenever `RELAY_BACKEND` is unset (`server_bootstrap.go:36-39`), and `newControlPlaneStores` then builds `newMemoryInboxBackend…` + `newMemoryRendezvousBackend` + `newMemoryPushTokenStore` (`server_bootstrap.go:62-87`). A relay restart/bounce therefore **wipes the entire control plane**: pending inbox messages, registered FCM push tokens, rendezvous registrations, and (implicitly) any reservation/token state held only in process memory. The `backend_redis.go` durable path is fully implemented and wired (`server_bootstrap.go:88-129`) but **only activates when `RELAY_BACKEND=redis` + `REDIS_URL` are set on the box** — which the live deploy is not known to do (env gitignored, unverifiable from-repo).

Additionally, the shipped client targets a **single relay** (`DefaultRelayAddress` = one `mknoun.xyz` peer, `config.go:11`; node default pool = `[]string{DefaultRelayAddress}`, `node.go:272`). Even though the Go host already has full multi-relay machinery (`RelaySelector`, `ForEach`/`FanOut`/`ForEachWithResult`, `EnableMultiRelayRouting=true` default — `relay_selector.go`, `feature_flags.go:38`), nothing populates a pool, so a single relay host (or its single transport) is a hard SPOF for custody.

**Who feels it.** Every offline recipient whose message sat in a relay that bounced — the sender saw "delivered (inbox)" but the message is gone; the recipient never wakes to it. Also every user whose FCM token only lived in memory → silent push loss after a relay restart.

**Why now (ordering hazard, §9).** FDC-03/P0-2 *generalizes the concurrent inbox deposit* → it **raises inbox write volume** for all unknown-presence sends. If that lands before durability, the extra copies pile into a restart-losable in-memory store, *widening* the blast radius of a relay bounce. §9 says: pull durability EARLIER than the volume increase. Hence FDC-10 must be **live in production before FDC-03's inbox-volume ramps to production traffic** — FDC-03's *code* may still land and host-test first in the Phase-0 MVP cut (FDC-01→02→03→04); only the production volume ramp is gated on FDC-10, never the code merge (see FDC-00 "Dart-only describes the CODE surface, not production enablement" + "Recommended MVP cut").

**What must improve.**
1. Production relay runs the **Redis backend** so inbox + tokens + rendezvous survive a relay bounce.
2. The control plane can run as a **pool of ≥2 stateless relay front-ends sharing one Redis**, so a single front-end bounce does not interrupt custody (failover already proven by `failover_test.go`).
3. The shipped client warms/deposits/retrieves across a **relay pool** (≥2 transport addresses now: WSS+QUIC to the default peer; ≥2 distinct relay peers once ops provisions relay #2), not a single address.
4. Ops can **verify durability is actually live** (the recurring pain: live env gitignored → durability silently regressed to memory is undetectable today).

**What must stay unchanged → preserved sentinels.**
- Store dedup-by-`messageId` semantics (memory `backend_memory.go:114-145`, redis `backend_redis.go:263-325`) — DO NOT touch/re-add (proposal §8 P2-2 explicit).
- Default backend stays `memory` for local-dev/tests (`TestLoadBackendConfigFromEnv_DefaultsToMemory`) — do not flip the *code* default; the deploy sets the env.
- Inbox cap, FIFO order, pagination/cursor continuation, ack-by-entryId (`inbox_store.go`, `failover_test.go`).
- Older clients keep working (additive only; NET-REL-07): no protocol/wire change, no new required request field.

## Root Cause (verify→refute confirmed)
- **Durability default = memory.** `server_bootstrap.go:36-39` (`kind == "" → backendKindMemory`) + `:62-87` builds the in-memory stores. CONFIRMED by Read. The Redis path (`:88-129`) is correct and complete but env-gated.
- **No durability-visibility surface.** `main.go:162` logs `Control-plane backend: %s` once at boot, but there is **no metric and no testable summary** an operator can scrape to confirm the *running* relay is durable. Refuted alternative ("just read the log") = not machine-checkable, not alertable.
- **Single-relay default pool.** `config.go:11` single `DefaultRelayAddress`; `node.go:271-273` `if relayAddresses == nil { relayAddresses = []string{DefaultRelayAddress} }` (the swap line is `:272`; `limitRelayAddresses` runs next at `:274`, then `n.relayAddresses = relayAddresses` at `:275`). NOTE `node.go:253` is the unrelated private-key-decode error block — do NOT edit there. The pool machinery exists but is never seeded with >1 target by default. CONFIRMED by Read.

**Refuted — do NOT re-introduce:**
- "Add store idempotency / messageId dedup." It ALREADY EXISTS in BOTH backends (`backend_memory.go:114-145`, `backend_redis.go:263-325`, `inbox_store.go:6-9`). Re-adding it is forbidden scope.
- "Switch the 1:1 InboxStore deposit from `ForEach` to `FanOut` (redundant deposit to independent stores)." REFUTED as the durability mechanism: with a SHARED Redis backend, `ForEach` (deposit once — `go-mknoon/node/inbox.go:124`, stops on first nil — retrieve-from-any sees it, `failover_test.go` `TestTwoRelayServers_SharedInboxBackend`) is correct AND cheaper. Redundant FanOut to *independent* memory stores would split custody and make `InboxRetrieve`'s first-success `ForEachWithResult` (`go-mknoon/node/inbox.go:233`) MISS messages deposited on a non-first relay (`ForEachWithResult` returns on the first `err==nil` even when that relay had NO_MESSAGES, `relay_selector.go:176-179` + inbox.go:274-277). The pool's correctness comes from the shared durable backend, not from fan-out deposit. (Keep token reg/unreg on `FanOut` as-is — `go-mknoon/node/inbox.go:547,614` — that is per-front-end local state, correctly broadcast.) NOTE: these symbols live in `go-mknoon/node/inbox.go` (host side); the relay-server `inbox.go` has no `ForEach`/`FanOut`.

## Real Scope
**In scope**
- go-relay-server: a testable **durability-visibility** surface (`backendConfig.IsDurable()` + a `backendStartupSummary` string + a Prometheus gauge) so ops can confirm/alert. Guard tests locking the memory default + the redis-misconfig error paths.
- go-mknoon/node: ship a **default relay pool** (WSS+QUIC to the default peer now; deploy-injectable additional peers) via a `DefaultRelayAddresses()` helper consumed at `node.go:272` (the nil-default branch `:271-273`).
- Ops runbook (ops-gated): provision Redis, set `RELAY_BACKEND=redis`+`REDIS_URL` on each relay front-end, run ≥2 front-ends sharing the Redis, provision relay #2, inject its address into the client pool, smoke `-tags integration` cross-process durability.

**Out of scope (owning FDC-xx)**
- Generalized concurrent inbox / volume increase → **FDC-03 (P0-2)** (FDC-10 must precede it).
- Relay presence lookup (reservation truth) → FDC (P1-1).
- libp2p LAN-direct dial (bonsoir-fed) → FDC-11 (P2-1).
- Any Dart send-ladder / `send_chat_message_use_case.dart` change → other FDC plans.
- Redis HA/clustering/persistence-tuning (AOF/RDB) → ops hardening follow-up; this plan only flips to a single durable Redis + documents the new SPOF.

## Files To Inspect Next
**Production — relay server (go-relay-server/)**
- `server_bootstrap.go` — `backendConfig`, `loadBackendConfigFromEnv` (:35-54), `newControlPlaneStores` (:56-133). PRIMARY edit site (add `IsDurable()`, `backendStartupSummary`).
- `main.go` — boot/log path (:43-44 config load, :87-101 stores, :161-201 startup logs), metrics endpoint (:204-211). Add durability log line + gauge.
- `metrics.go` — Prometheus gauge registration pattern: mirror `connectionsActive` (`:10-13`, `promauto.NewGauge(prometheus.GaugeOpts{…})`, default registry, no `MustRegister`; imports already present) for `relay_backend_durable`. `metrics_test.go`'s `metricValue()` helper + scrape-contract test host the from-repo lock (TC-10-05).
- `backend_redis.go` / `backend_memory.go` / `inbox_store.go` — READ-ONLY context (dedup, caps, store iface). Do not edit.
**Production — Go host (go-mknoon/node/)**
- `config.go` — `DefaultRelayAddress` (:11), `DefaultQUICRelay` (:15), `NodeConfig.RelayAddresses` (:137). Add `DefaultRelayAddresses()`.
- `node.go` — relay-address default + parse (:269-312; nil-default `:271-273`, `limitRelayAddresses` `:274`, `n.relayAddresses=` `:275`, same-peer merge `relayInfoMap` `:279-302`). Consume the pool helper at `:272`. (Two more single-relay fallbacks live downstream: `:840` recovery-warm + `relay_selector.go:214` `buildRelaySelector` — fire only when `n.relayAddresses` is empty.)
- `relay_selector.go` / `feature_flags.go` / `feature_flags_runtime.go` / `inbox.go` — READ-ONLY context (selector, flags, deposit/retrieve). Do not edit.
**Tests**
- go-relay-server: `server_bootstrap_test.go` (extend), `failover_test.go` (reuse as durability proof), `redis_failover_integration_test.go` (reuse; `-tags integration`).
- go-mknoon: `multi_relay_test.go` (extend), `feature_flags_runtime_test.go` (context).

## Existing Tests Covering This Area
- `go-relay-server/server_bootstrap_test.go`:
  - `TestLoadBackendConfigFromEnv_DefaultsToMemory` — EXISTS (locks memory default). **Reuse as preserved sentinel.**
  - `TestLoadBackendConfigFromEnv_NormalizesRedisPrefix` — EXISTS.
  - `TestNewControlPlaneStores_SelectsRedisBackends` — EXISTS (miniredis; proves redis wiring + shared state).
- `go-relay-server/failover_test.go`: `TestTwoRelayServers_SharedInboxBackend`, `…SharedRendezvousBackend`, `…SharedGroupInboxBackend`, `…SharedInboxPaginationContinuation`, `…SharedGroupCursorContinuation` — EXIST. **Reuse as the pool-failover/durability proof.** (NOTE: these use a *memory* backend shared by two store objects to model the shared-backend invariant; the Redis proof is the integration test below.)
- `go-relay-server/redis_failover_integration_test.go`: `TestRedisControlPlaneSharedAcrossProcesses` (+ helper) — EXISTS, `//go:build integration`, miniredis, **separate processes** → proves inbox/rendezvous/push/group survive a process restart on Redis. **This is the durability acceptance proof.** Not run by plain `go test ./...` (needs `-tags integration`).
- `go-mknoon/node/multi_relay_test.go`: 23 tests incl. `TestInboxStore_TriesSecondRelayWhenFirstFails`, `TestBuildRelaySelector_FallsBackToDefault`, `TestNewRelaySelector_TwoDistinctRelays`, `TestRelaySelector_FanOut_*` (2), `TestDialPeerViaRelay_SingleRelayStillWorks` — EXIST (lock pool/failover semantics). **Reuse; do not duplicate.** `TestNewRelaySelector_GroupsByPeerID` (`multi_relay_test.go:48-56`) is the closest analog to **TC-10-03**: it already asserts the same `Len()==1` / `len(Relays()[0].Addrs)==2` same-peer WSS+QUIC merge with synthetic addrs — mirror its assertion shape; TC-10-03's only delta is exercising the REAL `DefaultRelayAddress`+`DefaultQUICRelay` constants.
- `go-mknoon/node/feature_flags_runtime_test.go`: `TestStartNode_DisablesMultiRelayRoutingWhenFlagFalse`, `TestFeatureFlags_DefaultsRemainBackwardCompatible` — EXIST.
- **Harness family arrays:** Go tests are NOT in `scripts/run_test_gates.sh` readonly arrays — they run via `cd go-relay-server && go test ./...` and `cd go-mknoon && go test ./...` (auto-discovery, no array registration). The `transport` family array DOES list `wifi_relay_fallback_smoke_test.dart` (relay/inbox fallback smoke) and `background_reconnect_test.dart` — reuse as the Dart-side no-regression smoke.

## RED Test Catalog
All BEFORE prod code. Tier = lowest that fails for the real reason.

### TC-10-01 — durability is machine-checkable (`IsDurable`)
- **file::name** `go-relay-server/server_bootstrap_test.go::TestBackendConfig_IsDurable`
- **Tier** Go unit (server).
- **Shape/setup** Table: `{Kind: backendKindMemory}.IsDurable()` and `{Kind: backendKindRedis}.IsDurable()`.
- **RED-on-HEAD-because** `backendConfig.IsDurable()` does not exist → compile failure (RED).
- **GREEN-asserts** memory→`false`, redis→`true`.
- **Mutation-that-re-reds** invert the method body (`return c.Kind == backendKindMemory`) → memory case re-reds.
- **Distinct-event discriminator** n/a (pure value).

### TC-10-02 — operator-visible durability summary line
- **file::name** `go-relay-server/server_bootstrap_test.go::TestBackendStartupSummary_ReportsDurability`
- **Tier** Go unit (server).
- **Shape/setup** `backendStartupSummary(backendConfig{Kind: backendKindRedis, RedisPrefix:"relay:"})` and same with `backendKindMemory`.
- **RED-on-HEAD-because** `backendStartupSummary` does not exist → compile failure (RED).
- **GREEN-asserts** redis string contains `backend=redis` AND `durable=true`; memory string contains `backend=memory` AND `durable=false`. (This is the exact line `main.go` logs and the gauge label source — the ops "is durability live?" hook.)
- **Mutation-that-re-reds** drop the `durable=` token (or hardcode `durable=true`) → memory case re-reds.
- **Distinct-event discriminator** the `durable=` token distinguishes "redis selected" from "redis-but-fell-back" if a future fallback path is added.

### TC-10-03 — client default pool seeds WSS+QUIC (not a single address)
- **file::name** `go-mknoon/node/multi_relay_test.go::TestDefaultRelayAddresses_IncludesWssAndQuic`
- **Tier** Go unit (host).
- **Shape/setup** `addrs := DefaultRelayAddresses()`; build `NewRelaySelector(addrs)`.
- **RED-on-HEAD-because** `DefaultRelayAddresses()` does not exist → compile failure (RED).
- **GREEN-asserts** `addrs` contains BOTH `DefaultRelayAddress` (WSS) and `DefaultQUICRelay`; selector `.Len()==1` (same peer, merged — both multiaddrs end in `/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`, verified byte-identical) AND that one relay's `.Addrs` has length 2 (WSS+QUIC transport redundancy). Accessor: `sel.Relays()[0].Addrs`; the peer-ID field is `RelayInfo.ID` (not `PeerID`). This ships transport redundancy *today* without requiring relay #2.
- **Mutation-that-re-reds** return only `[]string{DefaultRelayAddress}` → `Addrs` length 1 re-reds.
- **Distinct-event discriminator** n/a.

### TC-10-04 — node default consumes the pool helper (nil RelayAddresses)
- **file::name** `go-mknoon/node/multi_relay_test.go::TestStartNode_NilRelayAddresses_UsesDefaultPool`
- **Tier** Go unit (host); construct a `Node` with `NodeConfig.RelayAddresses == nil` and inspect `n.relayAddresses` (mirrors `feature_flags_runtime_test.go:58-59` which already reads `n.relayAddresses`). No live host needed for the address-population assertion (assert before/independent of dial).
- **RED-on-HEAD-because** `node.go:272` hardcodes `[]string{DefaultRelayAddress}` → `n.relayAddresses` lacks the QUIC entry; asserting equality to `DefaultRelayAddresses()` fails (RED).
- **GREEN-asserts** `n.relayAddresses` (set at `node.go:275`, pre-merge) equals `DefaultRelayAddresses()` after `limitRelayAddresses` keeps all because `EnableMultiRelayRouting=true` (the helper is peer-agnostic — it would truncate any >1-address list when the flag is off; the same-peer WSS+QUIC merge to one `RelayInfo` happens LATER in `relayInfoMap`, `node.go:293-294`, and does not affect `n.relayAddresses`).
- **Mutation-that-re-reds** revert `:272` to `[]string{DefaultRelayAddress}` → re-reds (missing QUIC).
- **Distinct-event discriminator** n/a.

### TC-10-05 — durability gauge is from-repo machine-checkable (not ops-only)
- **file::name** `go-relay-server/metrics_test.go::TestRelayBackendDurableGauge`
- **Tier** Go unit (server).
- **Shape/setup** add a tiny `setBackendDurabilityGauge(c backendConfig)` helper that sets `relayBackendDurable` to `1` when `c.IsDurable()` else `0`; call it with `{Kind: backendKindRedis}` then read back via the existing `metricValue(t, relayBackendDurable)` helper (`metrics_test.go:15-30`), then with `{Kind: backendKindMemory}`. (Alternative/extra: a scrape-contract assert that `promhttp.Handler()` body contains `relay_backend_durable`, mirroring `TestRelayMetricsHandlerScrapeContract`, `:139-168`.)
- **RED-on-HEAD-because** the `relayBackendDurable` gauge (and `setBackendDurabilityGauge`) do not exist → compile failure (RED).
- **GREEN-asserts** `metricValue==1` after the redis config, `==0` after the memory config.
- **Mutation-that-re-reds** hardcode the helper to `Set(1)` → memory case re-reds. (This is what makes the lock test the `IsDurable()→gauge` mapping, not just promauto.)
- **Distinct-event discriminator** the 0/1 value distinguishes a durable-redis boot from a silently-memory boot — the from-repo half of "is durability live?"; the ops `curl :2112` is the LIVE half. INV-3 demands the gauge, so it must be locked, not deferred to ops.

### Preserved-sentinel locks (GREEN-on-HEAD characterization, flagged NOT-RED — they guard the invariants, no prod behavior change)
- **P-A** `server_bootstrap_test.go::TestLoadBackendConfigFromEnv_DefaultsToMemory` — EXISTS; reuse (code default stays memory).
- **P-B (NEW characterization)** `server_bootstrap_test.go::TestNewControlPlaneStores_RedisRequiresURL` — `newControlPlaneStores(ctx,{Kind:redis,RedisURL:""},…)` returns an error containing `REDIS_URL is required`. Green on HEAD (`server_bootstrap.go:89-91`); locks the deploy-misconfig guard so a future refactor can't silently fall back to memory. Mutation (drop the empty-URL check) re-reds.
- **P-C (NEW characterization)** `server_bootstrap_test.go::TestNewControlPlaneStores_UnknownBackendErrors` — `{Kind:"postgres"}` returns error `unsupported relay backend`. Green on HEAD (`:130-131`). Mutation (default to memory) re-reds.
- **P-D** `failover_test.go::TestTwoRelayServers_SharedInboxBackend` — EXISTS; reuse as the shared-backend custody invariant (deposit-A / retrieve-B exactly once).
- **P-E** `redis_failover_integration_test.go::TestRedisControlPlaneSharedAcrossProcesses` — EXISTS (`-tags integration`); reuse as the Redis cross-process durability acceptance proof.

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Durability is machine-checkable | memory→not durable, redis→durable | Go unit (server) | server_bootstrap_test.go::TestBackendConfig_IsDurable | `IsDurable()` absent (compile) | invert body | `cd go-relay-server && go test ./...` | auto (go test, no array) |
| Ops can verify durability is live | summary line carries `backend=`+`durable=` | Go unit (server) | server_bootstrap_test.go::TestBackendStartupSummary_ReportsDurability | helper absent (compile) | drop `durable=` token | `cd go-relay-server && go test ./...` | auto (go test) |
| Durability gauge is from-repo checkable | gauge==1 redis / ==0 memory | Go unit (server) | metrics_test.go::TestRelayBackendDurableGauge | gauge+helper absent (compile) | hardcode helper to `Set(1)` | `cd go-relay-server && go test ./...` | auto (go test) |
| Client ships a pool, not one address | default = WSS+QUIC merged to 1 peer / 2 addrs | Go unit (host) | multi_relay_test.go::TestDefaultRelayAddresses_IncludesWssAndQuic | `DefaultRelayAddresses()` absent (compile) | return single WSS | `cd go-mknoon && go test ./...` | auto (go test) |
| Node default uses the pool | nil RelayAddresses → pool, not single | Go unit (host) | multi_relay_test.go::TestStartNode_NilRelayAddresses_UsesDefaultPool | node.go:272 hardcodes single | revert `:272` to `[]string{DefaultRelayAddress}` | `cd go-mknoon && go test ./...` | auto (go test) |
| Code default stays memory (dev/test) | unset env → memory | Go unit (server) | server_bootstrap_test.go::TestLoadBackendConfigFromEnv_DefaultsToMemory (EXISTS) | preservation (green) | flip default to redis | `cd go-relay-server && go test ./...` | auto (go test) |
| Redis deploy misconfig fails loudly | redis+no URL → error | Go unit (server) | server_bootstrap_test.go::TestNewControlPlaneStores_RedisRequiresURL (NEW) | preservation (green @ :89-91) | drop empty-URL check | `cd go-relay-server && go test ./...` | auto (go test) |
| Unknown backend fails loudly | bad kind → error | Go unit (server) | server_bootstrap_test.go::TestNewControlPlaneStores_UnknownBackendErrors (NEW) | preservation (green @ :130-131) | default→memory | `cd go-relay-server && go test ./...` | auto (go test) |
| Shared backend = single custody | deposit-A retrieve-B once | Go unit (server) | failover_test.go::TestTwoRelayServers_SharedInboxBackend (EXISTS) | preservation (green) | break shared backend wiring | `cd go-relay-server && go test ./...` | auto (go test) |
| Redis survives process restart | inbox/rendezvous/push/group persist | Go integration (server) | redis_failover_integration_test.go::TestRedisControlPlaneSharedAcrossProcesses (EXISTS) | preservation (green) | n/a (durability proof) | `cd go-relay-server && go test -tags integration ./...` | auto (go test, tag-gated) |
| Existing pool failover unbroken | InboxStore tries 2nd relay | Go unit (host) | multi_relay_test.go::TestInboxStore_TriesSecondRelayWhenFirstFails (EXISTS) | preservation (green) | n/a | `cd go-mknoon && go test ./...` | auto (go test) |
| Single-relay client still works | pool of 1 unaffected | Go unit (host) | multi_relay_test.go::TestDialPeerViaRelay_SingleRelayStillWorks (EXISTS) | preservation (green) | n/a | `cd go-mknoon && go test ./...` | auto (go test) |
| Dart-side relay/inbox fallback smoke | offline→inbox still delivers | integration_test (transport) | wifi_relay_fallback_smoke_test.dart (EXISTS) | preservation (green) | n/a | `./scripts/run_test_gates.sh transport` | listed in `transport` readonly array |
| Live relay actually durable | running relay reports durable | ops/deploy | ops runbook step (ops-gated) | UNVERIFIABLE from-repo (env gitignored) | n/a | curl `/metrics` `relay_backend_durable 1` on the box | N/A (ops) |

## Blind-Spot Sweep
- **Lifecycle/derived-state durability.** The whole point: inbox + FCM tokens + rendezvous + reservation state must survive a relay process restart. Covered by P-E (Redis cross-process) for inbox/rendezvous/push/group. Reservation state is a libp2p circuit-v2 in-host concern (not in our store) — a front-end bounce drops its own reservations; the POOL (≥2 front-ends sharing Redis) is what keeps custody continuous → covered by P-D + ops runbook. ROW satisfied.
- **Sibling-surface consistency.** Group inbox + push tokens + rendezvous all flip durability *together* (single `cfg.Kind` switch in `newControlPlaneStores`) — no half-durable state. Locked by `TestNewControlPlaneStores_SelectsRedisBackends` (all four backends asserted redis) + P-C. ROW satisfied.
- **Destructive-action side-effects.** Inbox `Retrieve` is a destructive read; with a shared backend, retrieve-from-any consumes once (P-D, `…SharedInboxPaginationContinuation` proves no double-read across front-ends). With a pool of INDEPENDENT memory stores this would double-deliver/drop → that's exactly why the plan REFUSES independent-store fan-out deposit (see Root Cause refutation). ROW satisfied.
- **Invariant re-verification under new transitions.** New transition = "relay front-end bounces under load while client deposits." Receiver dedup-by-messageId (unchanged, `backend_*:Store`) + shared backend means a re-deposit after failover is a `duplicate` no-op. Locked by existing dedup tests (`inbox_dedup_test.go`) + P-D. The client's ForEach store retries the 2nd relay on first-relay failure (`TestInboxStore_TriesSecondRelayWhenFirstFails`) and lands in the SAME Redis. ROW satisfied.
- **Older-client compatibility (NET-REL-07).** No wire/protocol change; `IsDurable`/summary/gauge are server-internal; the client pool change is additive (more addresses). Older clients with a single relay address still work (`TestDialPeerViaRelay_SingleRelayStillWorks`). ROW satisfied.
- **New SPOF introduced.** Redis itself becomes a custody SPOF (Root Cause noted). N/A for from-repo test (HA/persistence is ops follow-up); flagged in Risks + openIssues, not in this plan's code scope.

## Invariants (locked by tests)
- INV-1: Code default backend = memory (P-A). Production durability is an *env*, never a code-default flip.
- INV-2: `redis` selected ⟺ all four backends are redis-typed and share state (`TestNewControlPlaneStores_SelectsRedisBackends`).
- INV-3: Durability is machine-checkable (`IsDurable` + summary + gauge) (TC-10-01/02/05).
- INV-4: Shared backend ⇒ deposit-once / retrieve-from-any-front-end-exactly-once (P-D, P-E).
- INV-5: messageId dedup is preserved, never re-implemented (existing `inbox_dedup_test.go`).
- INV-6: Client default targets a pool (≥WSS+QUIC), node consumes it (TC-10-03/04); single-relay path still works (existing).
- INV-7: All relay changes additive; older clients unaffected (existing + Blind-Spot).

## Step-By-Step Implementation Plan
RED first each step; name the seam.

1. **RED** TC-10-01: add `TestBackendConfig_IsDurable` → fails to compile. **GREEN**: add `func (c backendConfig) IsDurable() bool { return c.Kind == backendKindRedis }` in `server_bootstrap.go` (seam: `backendConfig` value type). Stop-if: any non-memory/non-redis kind must be reachable only via the existing `:130` error path — do not broaden `IsDurable` to assume durable.
2. **RED** TC-10-02: `TestBackendStartupSummary_ReportsDurability`. **GREEN**: add `func backendStartupSummary(c backendConfig) string` returning `fmt.Sprintf("backend=%s durable=%v prefix=%s", c.Kind, c.IsDurable(), c.RedisPrefix)`. Wire into `main.go` (seam: replace/augment the `:162` log with `log.Printf("Control-plane: %s", backendStartupSummary(backendCfg))`) and register a Prometheus gauge `relay_backend_durable` (seam: add `var relayBackendDurable = promauto.NewGauge(prometheus.GaugeOpts{Name:"relay_backend_durable", Help:"…"})` in `metrics.go` exactly like `connectionsActive` `:10-13` — default registry, no `MustRegister`, imports already present). Set it via a small `setBackendDurabilityGauge(backendCfg)` helper (`Set(1)` when `IsDurable()` else `Set(0)`) called in `main.go` near `:106`. The gauge IS cheaply unit-locked from-repo (TC-10-05 below — RED first); only the *log line* stays ops-observable. The LIVE-box value is the ops `curl :2112` check (flagged).
3. **RED** P-B/P-C: add `TestNewControlPlaneStores_RedisRequiresURL` + `TestNewControlPlaneStores_UnknownBackendErrors` → GREEN on HEAD (characterization; they pin `:89-91` and `:130-131`). No prod change. Run to confirm green; they exist to catch future regressions.
4. **RED** TC-10-03: `TestDefaultRelayAddresses_IncludesWssAndQuic`. **GREEN**: add `func DefaultRelayAddresses() []string { return []string{DefaultRelayAddress, DefaultQUICRelay} }` in `config.go` (seam: package-level helper; the ops-provisioned relay #2 addresses are appended here at deploy time or injected via `NodeConfig.RelayAddresses`). Stop-if: relay #2's real peerID/host is NOT known from-repo → keep the code default to the single-peer WSS+QUIC pool; do not invent a fake 2nd peerID.
5. **RED** TC-10-04: `TestStartNode_NilRelayAddresses_UsesDefaultPool`. **GREEN**: at `node.go:272` change `relayAddresses = []string{DefaultRelayAddress}` → `relayAddresses = DefaultRelayAddresses()` (seam: the nil-default branch `:271-273`; `limitRelayAddresses(relayAddresses, flags)` runs next at `:274`, then `n.relayAddresses = relayAddresses` at `:275`). Re-run existing `multi_relay_test.go` + `feature_flags_runtime_test.go`. **No reconciliation is needed**: `TestStartNode_DisablesMultiRelayRoutingWhenFlagFalse` passes an EXPLICIT `RelayAddresses: []string{addr1, addr2}` (`feature_flags_runtime_test.go:41-52`) — non-nil, so it NEVER reaches the nil-default branch this step edits or `DefaultRelayAddresses()` — and asserts only `len(n.relayAddresses)==1` (`:58-59`), never which address survives. So step 5 cannot affect it. `limitRelayAddresses` performs NO sort (`feature_flags_runtime.go:25-28` = order-preserving copy then `[:1]` when the flag is off, by ADDRESS count); WSS stays the surviving flag-off address only because `DefaultRelayAddresses()` lists it FIRST (`config.go:11` before `:15`). **Also (consistency, optional):** besides `:272`, two downstream fallbacks still default to single `[]string{DefaultRelayAddress}` — `node.go:840` (recovery-warm) and `relay_selector.go:214` (`buildRelaySelector`); they fire only when `n.relayAddresses` is empty (e.g. the explicit-empty-slice disable-warmup path), so they don't affect TC-10-04, but for a fully consistent WSS+QUIC default point them at `DefaultRelayAddresses()` too (or leave as a flagged follow-up). Stop-if: relay #2's real peerID/host is NOT known from-repo → keep the single-peer WSS+QUIC default (carried from step 4).
6. **Run full Go suites** (both modules) + `-tags integration` for the Redis proof. Then the Dart transport smoke.
7. **Ops (ops-gated, NOT from-repo):** provision Redis; set `RELAY_BACKEND=redis`+`REDIS_URL`+`REDIS_PREFIX` on each relay front-end; run ≥2 front-ends on the same Redis; provision relay #2 (distinct peerID/host) and append its WSS+QUIC to `DefaultRelayAddresses()` (or inject via client config); verify `curl :2112/metrics | grep relay_backend_durable` returns 1 on every box; run the `-tags integration` suite against the live Redis URL if reproducible.

## Risks And Edge Cases
- **Redis becomes a custody SPOF.** Pinned by: ops runbook (managed Redis + AOF/RDB persistence) — flagged openIssue; not code-scoped here. The pool of front-ends does NOT remove the Redis SPOF.
- **`limitRelayAddresses` truncates QUIC when `EnableMultiRelayRouting=false`** (`feature_flags_runtime.go:20-30` cuts to `[:1]` by address count, no sort — order-preserving copy then `[:1]`). Only the *nil-default* path is affected, and only when the flag is off; the flag-off node still keeps the proven WSS address because `DefaultRelayAddresses()` lists WSS first (`[]string{DefaultRelayAddress, DefaultQUICRelay}`). `feature_flags_runtime_test.go:58-59` exercises an explicit `[addr1,addr2]` (not the default pool) and is unaffected by step 5 — no reconciliation required.
- **Deploy silently stays memory** (env not set). Pinned by TC-10-01/02 gauge + ops `curl` check (the recurring "unverifiable from-repo" pain → now alertable).
- **Mixed pool (one redis front-end + one memory front-end)** would split custody. Pinned by: ops runbook (all front-ends share the SAME `REDIS_URL`/prefix) + P-D semantics; not enforceable from-repo across boxes (flagged).
- **Prefix collision** across environments (`REDIS_PREFIX` default `relay:`) — `TestLoadBackendConfigFromEnv_NormalizesRedisPrefix` (EXISTS) + runbook mandates per-env prefix.
- **Older client on single relay** — `TestDialPeerViaRelay_SingleRelayStillWorks` (EXISTS).

## Device/Relay Proof Profile
- **Host-only closure (from-repo):** TC-10-01..04 + P-A/B/C/D via `cd go-relay-server && go test ./...` and `cd go-mknoon && go test ./...`; P-E via `cd go-relay-server && go test -tags integration ./...` (miniredis, cross-process). These CLOSE the code change.
- **Requires live relay/ops (NOT from-repo, evidence-gated):** actual Redis flip on the box, multi-front-end pool, relay #2 provisioning, `/metrics` durability scrape. The live relay env is gitignored → **unverifiable from-repo; flag in PR.**
- **Optional sim smoke:** `./scripts/check_reliability_simulation_discovery.sh` then `/sims 1to1 --only N` for an offline→inbox→wake round-trip against a durable relay (only meaningful against a live durable deploy; not a from-repo gate).

## Acceptance Gates (LITERAL)
```
# Go relay server — unit + bootstrap + failover (durability code + guards)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...        # expected: PASS (191 pass / 0 fail / 2 skip)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && make lint                                              # expected: 0 issues
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test -race ./...                                    # expected: PASS (no data race in shared-backend/pool wiring)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go mod tidy && git diff --exit-code go.mod go.sum     # miniredis dep stays tidy
# Go relay server — Redis cross-process durability proof (tag-gated; needs miniredis dep present)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test -tags integration ./...   # expected: PASS incl TestRedisControlPlaneSharedAcrossProcesses
# Go host — relay pool / multi-relay
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...               # expected: PASS (all pkgs green / 0 fail (go1.25.0, ~1171 tests))
# Dart transport smoke — relay/inbox fallback unbroken
./scripts/run_test_gates.sh transport                                                       # expected: PASS (device/fixture-gated (skips on lone sim))
# Dart 1:1 — offline_inbox_roundtrip unbroken
./scripts/run_test_gates.sh 1to1                                                            # expected: PASS (1226)
# Hygiene
flutter analyze                                                                             # expected: 0 new
git diff --check                                                                            # expected: clean
# OPS-GATED (NOT from-repo; live env gitignored → unverifiable here):
#   curl -s http://<relay-host>:2112/metrics | grep relay_backend_durable     # expected: relay_backend_durable 1  on every front-end
```

## Known-Failure Interpretation
- `redis_failover_integration_test.go` is `//go:build integration` → ABSENT from plain `go test ./...`; a "no Redis test ran" on the plain gate is EXPECTED, not a regression — the durability proof requires `-tags integration` (+ the `miniredis` dep). If `-tags integration` fails to build on the dep, that is an env gap, not a code defect.
- `feature_flags_runtime_test.go:58-59` (expects `len(n.relayAddresses)==1` with multi-relay flag OFF) MUST stay green after step 5. It uses an EXPLICIT `[]string{addr1, addr2}` (non-nil), so step 5's nil-default edit cannot reach it, and it asserts only `len==1` (not which address survives) — there is no sort to "fix." A failure there would mean `limitRelayAddresses` stopped truncating to `[:1]` when the flag is off, unrelated to ordering or the default pool; do not weaken the test.
- Any Dart `transport`/`1to1` flake unrelated to relay backend (e.g. durable-media-upload flake noted in prior sessions) is pre-existing, not FDC-10.

## Done Criteria
- [ ] TC-10-01..05 RED-first then GREEN; each mutation re-reds.
- [ ] P-B/P-C added (green characterization); P-A/P-D/P-E reused and green.
- [ ] New exported identifiers carry doc comments (`DefaultRelayAddresses`, `IsDurable`, etc.).
- [ ] `cd go-relay-server && go test ./...` and `cd go-mknoon && go test ./...` PASS.
- [ ] `cd go-relay-server && go test -tags integration ./...` PASS (Redis durability proof).
- [ ] `./scripts/run_test_gates.sh transport` and `1to1` PASS (no regression).
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Ops runbook written (Redis flip, pool, gauge scrape) — deploy steps marked ops-gated.
- [ ] PR flags: live relay env gitignored → durability flip unverifiable from-repo; relay #2 not yet provisioned (pool ships as 1-peer / WSS+QUIC).

## Scope Guard (hard Do-not)
- **Do NOT** change group inbox / group-cursor durability — the group inbox flips backend TOGETHER with 1:1 via the single `cfg.Kind` switch; `SharedGroupInboxBackend` / `SharedGroupCursorContinuation` (`failover_test.go`) + the Redis cross-process group-persist proof must stay green (**group-safety floor**).
- Do NOT add/re-implement messageId dedup or any store idempotency (it EXISTS — proposal §8 P2-2).
- Do NOT flip the *code* default backend to redis (deploy env only; INV-1).
- Do NOT switch the 1:1 InboxStore deposit to FanOut/independent-store redundancy (breaks shared-custody + first-success retrieve; Root Cause refutation).
- Do NOT touch the Dart send ladder (`send_chat_message_use_case.dart`) or any path-decision logic.
- Do NOT invent a fake relay #2 peerID/host in code (ops-provisioned).
- Do NOT change inbox wire protocol / add required request fields (NET-REL-07).

## Accepted Differences
- The shipped default pool is **1 relay peer with 2 transports (WSS+QUIC)**, not 2 distinct relay peers, until ops provisions relay #2. This still removes the single-transport SPOF and exercises the pool machinery; multi-peer is a deploy-time append to `DefaultRelayAddresses()`.
- Durability of the *live* relay is asserted via a metric/log + ops `curl`, not a from-repo test (env gitignored).

## Dependency Impact
- **gatedBy:** none.
- **Unblocks / ordering:** FDC-03 (P0-2 generalized concurrent inbox / volume increase) MUST land AFTER FDC-10 (proposal §9 phase-3 hazard: don't raise inbox volume into a restart-losable store). FDC-10 is the prerequisite durability for the concurrent-inbox volume bump.
- **Collision risk:** `go-mknoon/node/node.go` (Node.Start relay-address block, :269-312) and `config.go` (relay consts/timeouts) are co-edited by sibling FDC Go-host plans (warmPeer, cold-start re-timing); `go-relay-server/main.go` is co-edited by the presence-lookup plan (P1-1). Run FDC-10 sequentially with those on the shared files. No Dart collisions (FDC-10 touches no Dart prod).
