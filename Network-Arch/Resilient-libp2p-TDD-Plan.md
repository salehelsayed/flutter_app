# Proposal: Resilient libp2p Network Architecture

## Document Status

This document is a replacement proposal for the current ideas in
`Network-Arch/Issues.md`.

It is based on a code review of:

- `go-mknoon/node`
- `go-mknoon/bridge`
- `go-relay-server`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- group rejoin and group inbox recovery flows in Flutter

This proposal is intentionally test-first. Every phase below includes the unit
tests, integration tests, and smoke-tests that should be written before or
alongside implementation.

---

## Executive Summary

`Issues.md` is directionally correct about the biggest client-side problems:

- full node restart is the primary relay recovery path today
- relay health is inferred from circuit addresses instead of reservation truth
- resume recovery is immediate but too heavy
- group continuity is fragile after relay recovery
- only the first configured relay is used in several code paths

The main missing piece in `Issues.md` is server-side resilience.

Today the relay server is not only a circuit relay. It also owns:

- rendezvous registrations
- 1:1 inbox storage
- group inbox storage
- push token registration

Most of that state is currently in memory. That means adding a second relay
without shared backing state will split discovery and offline delivery instead
of making the network resilient.

The correct order is:

1. Preserve the good transport building blocks already in the app.
2. Make the user-facing send path and startup path faster before adding more
   moving parts.
3. Make relay-side control-plane state shared or durable.
4. Make the client multi-relay-aware for every control path, not only circuit
   relay dialing.
5. Replace full host restart with targeted relay-session recovery.
6. Make group rejoin and inbox recovery idempotent and automatic only when
   needed.
7. Keep restart as a watchdog fallback, not as the default path.

## Preserve What Already Works

The app already has the right primitives. This plan should preserve them:

- local WiFi delivery and local connection reuse
- reuse of already-open libp2p peer connections
- rendezvous for peer discovery
- relay plus hole punching support
- durable 1:1 inbox fallback
- concurrent live group publish plus durable group inbox fallback
- startup inbox drain

The plan below improves ordering, timing, and recovery semantics. It should not
discard the transport options that are already useful.

---

## Goals

- Users should not feel relay disconnects during normal chat usage.
- First-time identity creation should not pay returning-user recovery costs.
- Users should open the app and see queued inbox messages immediately.
- User-tapped chat sends should complete on a short interactive budget instead
  of waiting through stacked serial timeouts.
- 1:1 messages should keep a durable offline path.
- Group messages should survive transient relay loss and resume cleanly.
- Relay failover must preserve discovery and inbox behavior.
- Resume from background should be fast and targeted.
- Full restart should happen only after bounded retry failure or explicit
  corruption detection.
- The migration must be incremental and backward-compatible enough to avoid
  destabilizing the application.

## Non-Goals

- Re-architecting the media/profile transfer stack in the same rollout.
- Replacing GossipSub for group delivery.
- Shipping a brand new bridge API in one cutover.
- Solving every operational scaling problem in phase 1.

Media and profile HA can be planned later. They are adjacent, but they are not
the critical blocker for resilient chat delivery.

This does not exempt media and profile paths from baseline transport hygiene.
Shared stream deadline/reset enforcement and shared relay-selection helpers
should still apply where those paths reuse the same node and relay plumbing.

---

## Proposed Target Architecture

### 1. Multi-Relay Edge Tier With Shared Control State

Run at least two geographically separate relay nodes.

Each node may still run the current combined binary at first, but the following
state must move behind shared or durable storage:

- rendezvous registrations with TTL refresh
- 1:1 inbox messages
- group inbox messages
- push token registration metadata

Recommended first implementation:

- keep the current Go relay binary
- add storage interfaces
- back them with Redis for rendezvous, inbox, group inbox, and push tokens
- keep the existing in-memory implementation for local development and tests

This keeps the deployment change smaller than a full service split while fixing
the real single-point-of-failure problem.

### 2. Interactive Send Path With Short Bounded Race

Keep the current transport options, but make the interactive send policy
explicit and short-lived.

For 1:1 chat:

1. reuse an already-open libp2p connection immediately if one exists
2. if there is no open connection, start local WiFi and direct
   rendezvous/discover plus dial in parallel
3. let relay and DCUtR remain available as backup within the same active send
   window instead of acting as a long blocking preflight
4. if no active path confirms quickly, store to inbox deterministically

Principles:

- do not stack multiple long waits on a user-tapped send
- keep interactive budgets short and separate from background recovery budgets
- commit only the first successful active path for a message ID
- keep a lightweight recent-route hint only if the short race still needs help;
  do not start with a large route-cache subsystem

### 3. Startup Readiness Before Relay Cosmetics

On app open and app resume:

1. start the node core immediately
2. drain 1:1 inbox immediately in parallel with relay reservation
3. start local discovery in parallel
4. register the personal rendezvous namespace as soon as the first healthy
   relay path can support a discoverable peer record; do not wait for all relay
   warm attempts to settle
5. update only non-green connecting or warming UI from early relay-edge signals;
   keep the green online indicator bound to reservation or circuit-ready truth

Important rule:

- do not make inbox drain or first-send readiness wait for the green icon

The green icon may continue to mean "relay reservation ready", but the app
should feel ready before that where possible.

Fresh identity bootstrap rule:

- the very first app open after identity creation should use the lightest path
- start the node core and seek relay readiness
- skip inbox drain, group rejoin, and group inbox drain on that first launch
- defer any nonessential warm tasks until after the first route is interactive

Returning cold-start rule:

- if the phone was restarted and the user opens the app fresh, treat that as a
  cold returning-user start, not as a resume
- show locally persisted chat history immediately
- start node core immediately
- prioritize 1:1 inbox retrieval first
- if network readiness is slow right after device boot, use a short bounded
  retry burst for inbox and relay readiness before falling back to normal
  watchdog polling
- start local discovery in parallel
- defer group rejoin, group inbox drain, and push-token refresh until after the
  first inbox-first recovery attempt has run

### 4. Client Relay Session Manager

Add an explicit relay session manager inside `go-mknoon/node`.

This manager should track per-relay state independently of host lifetime:

- `disconnected`
- `connected`
- `reserving`
- `reserved`
- `degraded`
- `cooldown`

It should also track aggregate node state:

- `starting`
- `online`
- `recovering`
- `watchdog_restart`

The manager should use:

- AutoRelay reservation lifecycle signals through
  `autorelay.WithMetricsTracer(...)`
- peer connectedness events
- last successful reservation timestamp
- last successful personal rendezvous registration refresh
- last successful group rendezvous registration refresh

It must not use `h.Addrs()` as the only source of truth.

### 5. Timeout Policy by User Intent

Do not use one timeout profile for every network action.

The plan should separate:

- interactive text-send budgets
- startup and cold-start catch-up budgets
- background recovery budgets
- media-transfer budgets

Initial target budgets for implementation:

- local WiFi WebSocket connect for interactive text send: `1.0s-1.5s`
- local WiFi ACK wait for interactive text send: `0.75s-1.0s`
- already-open libp2p connection ACK budget: keep around `1.0s`
- direct peer dial for interactive send: `3s-4s`
- rendezvous discover for interactive send: `1.5s-2.0s`
- rendezvous discover for background recovery: keep longer budget
- relay probe: remove as a blocking foreground send gate
- relay health probe for recovery paths: `2s-3s`
- AutoRelay retry/backoff/min-interval: keep around `5s` for background healing
- cold-start inbox retrieve after reboot: short attempt plus bounded retry
  burst before normal watchdog behavior
- media transfer budgets: remain separate and longer than text-message budgets

Rules:

- foreground chat must use the short interactive budgets
- startup and cold-start must prefer inbox-first progress over long waits
- background healing may keep longer waits than foreground chat
- one slow path must not block the whole send pipeline if another path can win
- every outbound stream must set a stream-level deadline aligned to its chosen
  budget immediately after `NewStream`, rather than relying on context timeout
  alone
- timeout, protocol, or framing failures must reset the stream instead of
  leaving it to a normal close path when the transport is already unhealthy
- inbound chat and other long-lived request handlers must set bounded read or
  write deadlines so a slow or hung peer cannot bypass the timeout policy
- media and profile operations may keep longer budgets than chat, but they
  still must honor explicit stream deadlines and reset rules
- additive bridge and API timeout plumbing must land early enough that the
  timeout split is real in production code, not only written in the plan
- exact values may be tuned with telemetry after rollout, but the budget split
  itself is part of the architecture

### 6. Targeted Recovery First, Watchdog Restart Last

The existing `relay:reconnect` bridge command should remain for compatibility,
but its implementation should change:

- first attempt in-place relay-session refresh
- return whether recovery was `in_place` or `watchdog_restart`
- only restart the host after bounded failure
- serialize or singleflight overlapping recovery requests at the Go boundary so
  resume, watchdog, push-driven recovery, and manual bridge callers share one
  in-flight attempt instead of creating recovery storms

That allows Flutter to stay compatible while the behavior becomes safer.

### 7. Idempotent Resume Recovery

On app resume:

1. check bridge health
2. refresh relay session immediately
3. refresh personal rendezvous registration if needed
4. refresh group rendezvous registrations if needed
5. drain 1:1 inbox
6. drain group inbox
7. rejoin missing group topics only if watchdog restart happened or the Go node
   reports missing subscriptions

Resume should not blindly rebuild the entire host.

For personal 1:1 discoverability:

- refresh the personal rendezvous registration before TTL expiry while the app
  remains active
- immediately re-register the personal namespace after watchdog restart
- immediately re-register after relay recovery if the prior registration is
  stale or lost

### 8. Incremental Inbox and Group-Inbox Catch-Up

Inbox drain should be optimized for perceived readiness, not only for total
backlog completion.

For 1:1 inbox:

- startup and resume should fetch a fast first page on the short foreground
  budget
- if more backlog remains, continuation pages should drain in the background
  without blocking app-open readiness
- the current destructive FIFO retrieve model may remain acceptable at first,
  but the bridge contract should expose additive continuation metadata such as
  `hasMore` or equivalent so the client does not guess

For group inbox:

- resume and watchdog recovery should also use fast first page plus background
  continuation semantics
- `sinceTimestamp` alone is not a stable exactly-once pagination cursor once
  backlog exceeds one page
- group catch-up should move to an additive opaque cursor contract before
  paginated exactly-once recovery is considered complete

### 9. Group Delivery Model

Keep the current dual path for groups:

- live delivery through GossipSub
- durable fallback through relay group inbox

But tighten the semantics:

- `topicPeers == 0` is not a send failure if group inbox durability succeeds
- group recovery must dedupe by `messageId`, not only by content and timestamp
- after watchdog restart, group topics must be rejoined automatically
- after resume, group inbox must be drained automatically
- group rendezvous registrations must be refreshed before TTL expiry
- group mesh formation should reuse existing direct connections and actually use
  discovered or peerstore addresses before forcing relay-circuit dialing
- announcement groups use the same live plus durable transport model as chat
  groups; only write authorization is different
- announcement catch-up must be exactly-once for offline readers

### 10. Multi-Relay Routing Everywhere

All relay-dependent operations must stop using `relayAddrs[0]` semantics.

This applies to:

- relay probe / circuit dial
- rendezvous register
- rendezvous discover
- rendezvous unregister
- 1:1 inbox store/retrieve/register token
- group inbox store/retrieve
- media upload/download/list
- profile upload/download

Selection policy should be:

- prefer currently healthy relay
- fallback through remaining configured relays
- record last-success per operation

### 11. Event Delivery Backpressure and Coalescing

Go-to-Flutter push delivery must not synchronously block libp2p or pubsub
processing.

Minimum policy:

- move push delivery onto a bounded async dispatcher instead of calling the
  Dart callback inline on hot network goroutines
- keep chat and group message events lossless within the bounded queue
- allow status-like events such as `addresses:updated`, `relay:state`, and
  repeated discovery progress updates to coalesce to the newest state
- expose queue depth or overflow telemetry so backpressure is observable during
  rollout

### 12. Connection Churn Control

The client must avoid aggressive reconnect churn once multi-relay routing and
group recovery are enabled.

Minimum policy:

- protect relay peers and currently hot chat peers from accidental trimming
- add per-peer cooldown or backoff for repeated relay dial failures
- avoid redialing the same missing group peers every discovery tick without
  backoff
- add node-wide jitter and concurrency caps so many joined groups do not burst
  relay discovery and redial work at the same moment after resume or watchdog
  restart
- separate liveness checks from reconnect storms

### 13. Relay Capacity and Admission Protection

Multi-relay improves availability only if each relay also behaves reasonably
under load.

Before production rollout, add:

- finite relay limits instead of infinite relay service limits
- admission control or connection caps where appropriate
- basic overload or abuse behavior that fails predictably instead of degrading
  all users
- telemetry for saturation and shed behavior

---

## Compatibility Strategy

The plan should keep the app stable while the architecture evolves.

Compatibility rules:

- keep `relay:reconnect` command name
- extend `node:status` with new fields, do not remove old ones
- keep current `addresses:updated` push event
- add new relay-state push events instead of replacing existing ones
- prefer additive structured recovery result fields such as `recoveryMode`,
  `errorCode`, and `reason` over Dart string matching once recovery branching
  becomes more complex
- keep inbox and group-inbox continuation fields additive, for example
  `hasMore`, `nextCursor`, or equivalent metadata
- allow coalesced status-like push events to skip intermediate states by design
- use additive migration for new DB uniqueness/indexes related to group
  dedupe

Suggested new `node:status` fields:

- `relayState`
- `relayStates`
- `healthyRelayCount`
- `lastReservationAt`
- `watchdogRestartCount`
- `needsGroupRecovery`

Flutter can ignore these fields until the relevant phase is enabled.

---

## Phased TDD Implementation Plan

## Phase 0: Baseline Harness and Contract Locking

### Goal

Protect current user-visible behavior before changing recovery internals.

This phase does not change architecture yet. It strengthens the safety net.

### Production Scope

- No major behavior change.
- Add test helpers where necessary.
- Add missing diagnostics fields only if they are backward-compatible.

### RED Tests

#### Go Unit Tests

**File:** `go-mknoon/node/node_test.go`

- `TestReconnectRelays_LeavesPeerIdStable`
- `TestReconnectRelays_ClearsAndRebuildsPubSubState_CurrentBehavior`
- `TestStatus_BackwardCompatibleShape`

Purpose:

- lock the current restart semantics so later tests can prove the new behavior
  changed intentionally
- lock the current bridge JSON shape

#### Flutter Unit Tests

**File:** `test/core/services/p2p_service_impl_test.dart`

- `startNode preserves legacy status parsing when extra fields exist`
- `performImmediateHealthCheck ignores unknown relay fields before migration`

Purpose:

- ensure additive Go status fields do not break the current Dart parser

#### Existing Suites To Keep Green

- `flutter test test/core/services`
- `flutter test test/core/bridge`
- `flutter test test/core/lifecycle/background_reconnect_smoke_test.dart`
- `cd go-mknoon && go test ./node ./bridge`

### GREEN Implementation

- Add any missing fake bridge fields required for future relay-state events.
- Keep the app behavior unchanged.

### Exit Criteria

- Baseline targeted suites are green.
- New relay-related fields can be added without breaking Dart parsing.

---

## Phase 1: Interactive Send Path and Startup Readiness

### Goal

Make app open and user-tapped send feel immediate without waiting through
stacked transport timeouts.

### Production Scope

Likely files:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/p2p/application/start_node_use_case.dart`
- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/config.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/inbox.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/media.go`

Implementation steps:

1. Make one explicit interactive send policy for 1:1 chat:
   - reuse an already-open libp2p connection immediately
   - if no open connection exists, race local WiFi and direct
     rendezvous/discover plus dial
   - let relay remain a fast backup, not a long serial gate
   - fall back to inbox deterministically
2. Introduce separate interactive budgets versus background recovery budgets.
3. Set the initial timeout split:
   - local WiFi connect `1.0s-1.5s`
   - local WiFi ACK `0.75s-1.0s`
   - existing open libp2p ACK stays near `1.0s`
   - interactive peer dial `3s-4s`
   - interactive rendezvous discover `1.5s-2.0s`
   - relay probe removed from foreground send gating
   - recovery relay probe `2s-3s`
   - AutoRelay background healing remains around `5s`
4. Pull additive bridge and node timeout plumbing into this phase:
   - parse and honor existing Dart `timeoutMs` fields for discover and dial
   - add additive timeout plumbing for inbox retrieve and store where needed
   - honor existing Dart `serverAddresses` fields at the bridge boundary where
     they already exist, while keeping full multi-relay policy for Phase 3
5. Enforce stream-level timeout hygiene:
   - set stream deadlines immediately after opening outbound streams
   - reset streams on timeout, framing, or protocol failure instead of waiting
     for a normal close path
   - apply bounded deadlines to inbound chat reads and ACK writes
   - use the same helper pattern across chat, inbox, rendezvous, group inbox,
     media, and profile paths even when their timeout values differ
6. Remove stacked `5s` and `10s` waits from the interactive send hot path.
7. Drain 1:1 inbox immediately on app start and resume in parallel with relay
   reservation and local discovery:
   - fetch the first page on the short startup budget
   - continue remaining 1:1 pages in the background when the server indicates
     more backlog remains
8. Register the personal rendezvous namespace after the first healthy relay or
   reservation path is ready; do not wait for all relay warm attempts to settle.
9. Keep the green status indicator reservation or circuit-bound; early
   relay-edge signals may only advance non-green connecting UI or internal
   startup sequencing.
10. Add a fresh-identity bootstrap path:
   - after new identity creation, start node core immediately
   - skip inbox drain, group rejoin, and group inbox drain on that first launch
   - defer nonessential warm work until the first route is interactive
11. Add a returning cold-start path:
   - show local history immediately
   - prioritize 1:1 inbox retrieval on first open after reboot
   - use a short bounded retry burst if network readiness is slow right after
     device boot, for example `2-3` short inbox/relay attempts before normal
     watchdog behavior takes over
   - delay group rejoin, group inbox drain, and push-token refresh until after
     the first inbox-first recovery attempt
12. Add only a lightweight recent-route hint if the short-race policy still
   needs it after tests are in place.

### RED Tests

#### Flutter Unit Tests

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

- `existing connected peer is used before launching new transport attempts`
- `local wifi and direct send race commits only the first successful path`
- `slow local wifi does not block direct success beyond interactive budget`
- `interactive direct discover uses short budget while background discover remains longer`
- `relay probe does not block direct discovery on the interactive path`
- `all active send paths failing falls back to inbox once`
- `same messageId winning on two paths persists only one outgoing message`

**File:** `go-mknoon/bridge/bridge_test.go`

- `RendezvousDiscover_HonorsTimeoutMs`
- `DialPeer_HonorsTimeoutMs`
- `RendezvousRegister_ForwardsExistingServerAddresses`
- `InboxRetrieve_HonorsForegroundTimeoutWhenProvided`
- `InboxRetrieve_ExposesContinuationMetadataWhenBacklogRemains`

**File:** `go-mknoon/node/stream_timeout_test.go` or nearby node timeout tests

- `OutboundStreams_ApplyDeadlineAcrossChatInboxRendezvousGroupInboxAndMedia`
- `TimedOutOrMalformedStreams_ResetInsteadOfHanging`
- `InboundChatStream_UsesReadDeadlineAndResetsOnSlowPeer`

**File:** `test/core/services/p2p_service_impl_test.dart`

- `warmBackground drains inbox while relay reservation is still pending`
- `resume drains inbox before online indicator turns green`
- `startup inbox drain shows first page before background continuation completes`
- `fast circuit fallback poll updates online state when push event is delayed`
- `early relay edge signal does not mark online before circuit or reservation readiness`
- `cold start after reboot prioritizes inbox retrieval before secondary warm tasks`
- `cold start quick retry burst runs before watchdog timer path`
- `background relay healing keeps longer retry cadence than foreground send`

**File:** `test/core/local_discovery/local_ws_server_test.dart`

- `interactive local send timeout stays within bounded chat budget`
- `slow ack removes stale pooled connection without blocking later sends`
- `media path is not forced into text-message timeout budget`

**File:** `go-mknoon/node/config_test.go` or timeout policy tests near config

- `interactive and background timeout profiles remain distinct`
- `foreground relay probe is not required for active send path`

**File:** `go-mknoon/node/node_test.go`

- `AutoRegister_DoesNotWaitForAllRelayWarmAttemptsAfterFirstHealthyRelay`
- `AutoRegister_WaitsForDiscoverableCircuitRecordNotMereRelaySocket`

**File:** `test/features/identity/presentation/screens/startup_router_test.dart`

- `fresh identity creation uses light startup path without returning-user recovery`
- `fresh identity creation skips group rejoin and group inbox drain`
- `returning user startup still schedules inbox-first warm recovery`
- `returning cold start after reboot shows persisted conversation history before network warm completion`

**File:** `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

- `stays connecting until circuit or reservation-ready state arrives`
- `does not turn online from relay-edge signal without circuit or reservation readiness`

Purpose:

- prove the app stops stacking long waits on a user send
- prove startup inbox drain is not blocked by relay cosmetics
- prove bridge and node timeout plumbing lands in the same phase as the timeout policy
- prove stream-level deadlines and resets make the timeout policy real even on hung streams
- prove brand-new users do not pay returning-user warm-recovery cost
- prove returning users after device reboot get inbox-first recovery quickly
- prove foreground and background timeout budgets stay intentionally different
- prove startup discoverability is not gated by a dead secondary relay
- prove short parallel send races do not create duplicate persistence

#### Integration Tests With Fakes

**File:** `test/features/conversation/integration/two_user_message_exchange_test.dart`

- `existing direct connection wins over rediscovery on repeated sends`
- `peer moving from relay to shared wifi uses the fastest available path next`

**File:** `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

- `startup inbox drain completes before relay online state is green`
- `resume delivers queued inbox messages before later live reconnect finishes`
- `large 1:1 backlog shows first page quickly and drains remaining pages in background`
- `cold start after reboot retrieves queued inbox messages before group warm tasks finish`
- `foreground send completes on short budget while longer background recovery continues separately`

**File:** `test/core/resilience/f2_transport_switch_recovery_test.dart`

- `relay to wifi transport switch does not leave a long sending gap`
- `wifi losing the race still results in one delivered message through relay or inbox`

#### Device / Simulator Smoke Tests

Existing files to extend:

- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_transport_test.dart`

Scenarios:

1. two users are connected over the internet
2. both join the same WiFi
3. the next sends switch to WiFi without a visible lag spike
4. app launches with queued inbox messages while relay is still connecting
5. queued messages appear before the online icon turns green
6. returning user after phone reboot sees persisted history immediately and
   receives queued inbox messages before slower background warm tasks complete

### GREEN Implementation

- Refactor the send orchestration into one explicit short-race policy.
- Keep inbox fallback unchanged as the durable safety net.
- Keep rendezvous in use, but do not make it a long serial blocker.
- Land additive bridge timeout plumbing in the same phase as the timeout split.
- Land shared stream deadline and reset enforcement across the node transport helpers.
- Register personal rendezvous after the first healthy relay or reservation path.
- Keep the green icon reservation or circuit-bound even if startup gets earlier edge signals.

### Exit Criteria

- App startup can surface inbox messages before relay-ready UI state.
- Large 1:1 inbox backlog no longer blocks startup on a single one-shot drain.
- Returning cold start after reboot uses inbox-first recovery without waiting
  for watchdog timing.
- Interactive 1:1 send no longer waits through stacked long transport timeouts.
- Foreground and background timeout classes are enforced separately in code and tests.
- Hung outbound or inbound streams cannot bypass the timeout policy through blocking I/O alone.
- Personal startup discoverability is not delayed by dead secondary relay warm attempts.
- A parallel send race can produce at most one persisted outgoing message.

### Commands

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/local_discovery/local_ws_server_test.dart
flutter test test/features/identity/presentation/screens/startup_router_test.dart
flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart
flutter test test/features/conversation/integration/two_user_message_exchange_test.dart
flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart
flutter test test/core/resilience/f2_transport_switch_recovery_test.dart
flutter test integration_test/wifi_transport_test.dart -d <device>
flutter test integration_test/transport_e2e_test.dart -d <device>
```

---

## Phase 2: Shared Relay Control State

### Goal

Remove the real single point of failure before enabling multi-relay behavior.

### Production Scope

Likely files:

- `go-relay-server/main.go`
- `go-relay-server/rendezvous.go`
- `go-relay-server/inbox.go`
- new backend files such as:
  - `go-relay-server/rendezvous_store.go`
  - `go-relay-server/inbox_store.go`
  - `go-relay-server/group_inbox_store.go`
  - `go-relay-server/push_token_store.go`
  - `go-relay-server/backend_redis.go`

Implementation steps:

1. Introduce storage interfaces for rendezvous, inbox, group inbox, and push
   tokens.
2. Keep the current in-memory implementation as the default test/dev backend.
3. Add a shared backend implementation, preferably Redis first.
4. Define additive continuation contracts for inbox and group inbox:
   - 1:1 inbox may keep destructive FIFO pagination, but the backend and bridge
     must expose additive continuation metadata instead of relying on fixed
     one-shot retrieve assumptions
   - group inbox must gain a stable opaque cursor contract for paginated
     exactly-once catch-up; `sinceTimestamp` may remain as an additive legacy
     selector during migration
5. Make TTL refresh and cleanup backend-driven instead of process-local only.

### RED Tests

#### Go Unit Tests

**File:** `go-relay-server/rendezvous_test.go`

- `TestRendezvousStore_RegisterRefreshesTTL`
- `TestRendezvousStore_DiscoverExcludesExpiredEntries`
- `TestRendezvousStore_DiscoverSeesEntriesWrittenByAnotherStoreInstance`

**File:** `go-relay-server/inbox_test.go`

- `TestInboxStore_RetrieveExactlyOnceAcrossInstances`
- `TestInboxStore_RegisterTokenVisibleAcrossInstances`
- `TestInboxStore_PushTokenSurvivesServerRestart`
- `TestInboxStore_PaginatedRetrieveKeepsFIFOAcrossInstances`

**File:** `go-relay-server/group_inbox_test.go`

- `TestGroupInboxStore_RetrieveBySinceTimestampAcrossInstances`
- `TestGroupInboxStore_PruneUsesSharedBackendTTL`
- `TestGroupInboxStore_FailoverDoesNotDuplicateMessages`
- `TestGroupInboxStore_CursorPaginationStableAcrossInstances`

Purpose:

- prove that relay A can write state and relay B can read it
- prove TTL and cleanup are no longer tied to a single process
- prove shared-backend pagination stays stable across relay instances

#### Go Integration Tests

**File:** `go-relay-server/failover_test.go`

- `TestTwoRelayServers_SharedRendezvousBackend`
- `TestTwoRelayServers_SharedInboxBackend`
- `TestTwoRelayServers_SharedGroupInboxBackend`
- `TestTwoRelayServers_SharedInboxPaginationContinuation`
- `TestTwoRelayServers_SharedGroupCursorContinuation`

Suggested setup:

- boot two relay server instances with different peer IDs
- point both at the same backend
- register/store through instance A
- discover/retrieve through instance B

#### Smoke Tests

**File:** `Testing-Tracking/go-relay-server.md` or a new runbook entry

Manual smoke:

1. start two relay servers against shared backend
2. connect test peers through relay A
3. stop relay A
4. confirm rendezvous, inbox retrieval, and push token registration still work
   through relay B

### GREEN Implementation

- Add backend interfaces and concrete implementations.
- Wire configuration for shared backend.
- Add additive continuation metadata and stable group cursor support without
  breaking old clients.
- Keep in-memory fallback for local tests.

### Exit Criteria

- Two server instances can share rendezvous and inbox state.
- A relay process restart no longer deletes discovery and offline delivery
  state.
- Paginated inbox and group-inbox continuation works across relay failover.

### Commands

```bash
cd go-relay-server && go test ./...
```

---

## Phase 3: Multi-Relay Routing Everywhere

### Goal

Make every relay-dependent client operation try healthy relays, not only the
first configured address.

### Production Scope

Likely files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/inbox.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/media.go`
- `go-mknoon/bridge/bridge.go`
- `lib/core/bridge/p2p_bridge_client.dart`

Implementation steps:

1. Add relay selection helpers in Go:
   - parse all configured relays
   - group addresses by peer ID
   - try relays in health-priority order
2. Update bridge methods so optional `serverAddresses` are actually honored.
3. Reuse the same relay selection helpers for media and profile relay access so
   those paths do not keep dead-first-relay behavior.
4. Keep the default relay list additive and backward-compatible.

### RED Tests

#### Go Unit Tests

**File:** `go-mknoon/node/multi_relay_test.go`

- `TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails`
- `TestRendezvousRegister_TriesSecondRelayWhenFirstFails`
- `TestRendezvousDiscover_TriesSecondRelayWhenFirstFails`
- `TestInboxStore_TriesSecondRelayWhenFirstFails`
- `TestGroupInboxRetrieve_TriesSecondRelayWhenFirstFails`
- `TestMediaUpload_TriesSecondRelayWhenFirstFails`
- `TestProfileDownload_TriesSecondRelayWhenFirstFails`

Purpose:

- remove all `addrs[0]` assumptions

#### Bridge Unit Tests

**File:** `go-mknoon/bridge/bridge_test.go`

- `TestRendezvousRegister_PassesServerAddresses`
- `TestRendezvousDiscover_PassesServerAddresses`
- `TestGroupInboxStore_UsesProvidedServerAddresses`

#### Flutter Unit Tests

**File:** `test/core/bridge/p2p_bridge_client_test.dart`

- `callP2PNodeStart sends all default relay addresses`
- `callP2PRendezvousRegister forwards explicit serverAddresses`
- `callP2PRendezvousDiscover forwards explicit serverAddresses`

#### Go Integration Tests

**File:** `go-mknoon/integration/multi_relay_test.go`

- `TestPeerDialFallsBackToSecondRelay`
- `TestRendezvousDiscoveryFallsBackToSecondRelay`
- `TestInboxRetrieveFallsBackToSecondRelay`
- `TestMediaDownloadFallsBackToSecondRelay`

### GREEN Implementation

- Introduce reusable relay selection helpers.
- Update all control-plane calls and media/profile relay access to use them.

### Exit Criteria

- No control-plane path depends on `relayAddrs[0]`.
- A dead first relay does not block discovery, inbox, or group inbox.
- Media and profile relay access no longer depend on the first configured relay.

### Commands

```bash
cd go-mknoon && go test ./node ./bridge ./integration -run 'Relay|Rendezvous|Inbox|Media|Profile'
flutter test test/core/bridge
```

---

## Phase 4: Relay Session Manager and Reservation-Aware Health

### Goal

Stop treating the whole host as disposable when only relay reservation health
needs repair.

### Production Scope

Likely files:

- `go-mknoon/node/node.go`
- new files:
  - `go-mknoon/node/relay_session.go`
  - `go-mknoon/node/relay_session_test.go`
  - `go-mknoon/node/autorelay_metrics.go`
  - `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/config.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/events.go`
- `lib/features/p2p/domain/models/node_state.dart`

Implementation steps:

1. Add a relay-session manager to the Go node.
2. Hook AutoRelay metrics tracer:
   - reservation opened
   - reservation ended
   - reservation request finished
   - relay address updated
3. Track per-relay and aggregate relay session state.
4. Extend `node:status` with relay-state fields.
5. Move Go-to-Flutter push delivery off hot network goroutines:
   - use a bounded async dispatcher
   - coalesce status-like events to latest state
   - keep message-bearing events lossless
6. Emit new push events such as `relay:state`.
7. Add in-place recovery method:
   - reconnect relay peer
   - trigger reservation refresh
   - refresh registrations if needed
8. Serialize overlapping Go-side recovery attempts so bridge, watchdog,
   resume-driven, and push-driven callers share one in-flight refresh instead
   of racing each other.
9. Return additive structured recovery results and codes so callers do not
   branch on raw error strings.
10. Add connection churn controls:
   - protect relay peers and hot chat peers from trimming
   - add backoff or cooldown around repeated relay and group peer dial failure

### RED Tests

#### Go Unit Tests

**File:** `go-mknoon/node/relay_session_test.go`

- `TestRelaySession_TransitionsToReservedOnReservationOpened`
- `TestRelaySession_TransitionsToDegradedOnReservationEnded`
- `TestRelaySession_RequestFailureDoesNotRestartHostImmediately`
- `TestRelaySession_ReportsHealthyWhenReservationAndConnectednessAgree`
- `TestRelaySession_IgnoresStaleCircuitAddressesWithoutReservation`
- `TestRelaySession_CoalescesConcurrentRecoveryRequests`

**File:** `go-mknoon/node/node_test.go`

- `TestRefreshRelaySession_DoesNotReplaceHost`
- `TestRefreshRelaySession_PreservesPubSubMaps`
- `TestStatus_IncludesRelaySessionFields`
- `TestPersonalRendezvousRefresh_RenewsBeforeTTLExpiry`
- `TestWatchdogRestart_ReRegistersPersonalNamespaceImmediately`
- `TestConnManager_ProtectsRelayAndHotPeersDuringRecovery`
- `TestEmitEvent_SlowCallbackDoesNotBlockHotPath`
- `TestEventDispatcher_CoalescesAddressesUpdatedAndRelayState`
- `TestEventDispatcher_PreservesMessageEvents`

Purpose:

- prove host-preserving recovery
- move health truth away from `h.Addrs()` only

#### Bridge Unit Tests

**File:** `go-mknoon/bridge/bridge_test.go`

- `TestNodeStatus_ContainsRelayStateWithoutBreakingLegacyFields`
- `TestRelayReconnect_ReturnsRecoveryMode`
- `TestRelayReconnect_ConcurrentBridgeCallsShareSingleRecovery`
- `TestRelayReconnect_ReturnsStructuredRecoveryFields`

#### Flutter Unit Tests

**File:** `test/core/services/p2p_service_impl_test.dart`

- `health check uses relayState when present`
- `legacy circuitAddresses path still works when relayState absent`
- `relay state push updates current state without restart`
- `status push burst coalescing does not lose final online state`

#### Go Integration Tests

**File:** `go-mknoon/integration/relay_test.go`

- `TestRelayRefreshRecoversWithoutHostReplacement`
- `TestRelayRefreshPreservesJoinedGroupTopics`
- `TestRelayRefreshPreservesActivePeerConnectionsWhenPossible`
- `TestLongRunningNode_RemainsPersonallyDiscoverablePastSingleTTLWindow`

These should explicitly fail if recovery is still implemented by `Stop() +
Start()`.

### GREEN Implementation

- Add relay-session manager.
- Add bounded async Go-to-Flutter event delivery with status-event coalescing.
- Change `ReconnectRelays()` to:
  - attempt in-place refresh first
  - restart only on bounded failure
- serialize overlapping Go-side recovery attempts into one in-flight operation
- return additive structured recovery fields instead of requiring string
  matching in Dart
- refresh personal registrations before TTL expiry and immediately after watchdog restart
- protect relay and hot peers from avoidable trimming during recovery
- Keep the bridge command name for compatibility.

### Exit Criteria

- Relay recovery can succeed without replacing the host.
- Health decisions can use reservation truth instead of only circuit addresses.
- Long-running foreground nodes remain personally discoverable across TTL refresh windows.
- Slow Dart event handling no longer stalls Go event or pubsub processing.
- Overlapping Go-side recovery requests collapse to one in-flight attempt.
- Recovery callers can branch on structured fields instead of raw error text.

### Commands

```bash
cd go-mknoon && go test ./node ./bridge -run 'RelaySession|RefreshRelay|Status|Rendezvous'
flutter test test/core/services
flutter test test/core/bridge
```

---

## Phase 5: Event-Driven Resume and Watchdog Recovery

### Goal

Move recovery off the 30-second polling path and make resume targeted,
idempotent, and bounded.

### Production Scope

Likely files:

- `lib/core/services/p2p_service_impl.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `test/shared/fakes/lifecycle_bridge.dart`

Implementation steps:

1. Keep periodic health checks only as watchdog/background safety net.
2. Trigger immediate relay-session refresh on:
   - app resume
   - relay connectedness loss
   - relay-state degradation push
3. Prevent concurrent recovery attempts in both layers:
   - coalesce user and lifecycle callers in Flutter
   - rely on Go-side serialization so resume, watchdog, manual reconnect, and
     relay-state push cannot race at the bridge boundary
4. Surface whether the last recovery used in-place refresh or watchdog restart.

### RED Tests

#### Flutter Unit Tests

**File:** `test/core/lifecycle/connectivity_lifecycle_test.dart`

- `relay disconnect event triggers immediate recovery without waiting for timer`
- `performImmediateHealthCheck prefers in-place recovery over restart`
- `concurrent resume calls coalesce to one recovery`
- `manual reconnect plus resume coalesce to one recovery result`
- `recovery branching uses structured result fields when present`
- `failed in-place recovery escalates to watchdog only after threshold`

**File:** `test/core/lifecycle/background_reconnect_smoke_test.dart`

- `resume recovery restores online state without host restart`
- `event-driven relay-state push restores online state without timer alignment`
- `watchdog restart path is only used after repeated refresh failure`

**File:** `test/core/services/p2p_service_stop_race_test.dart`

- `stop during in-place recovery does not resurrect node`
- `dispose during relay-state push recovery is safe`

Purpose:

- keep the existing race-condition coverage while changing recovery semantics

#### Integration Tests With Fakes

**File:** `test/core/services/p2p_service_fault_injection_test.dart`

- `lost reservation retries in place before watchdog restart`
- `bridge healthy but first relay dead still recovers through second relay`

#### Device / Simulator Smoke Tests

**File:** `integration_test/background_reconnect_test.dart`

Extend or add:

- `resume with active 1:1 conversation keeps send/receive working`
- `resume with active group conversation keeps live receive working`

### GREEN Implementation

- Add relay-state event handlers in Dart.
- Narrow the health-check timer to a fallback role.
- Make resume orchestration rely on immediate recovery hooks.
- Keep Flutter coalescing additive to the Go-side recovery gate rather than the
  only protection against overlap.

### Exit Criteria

- The app no longer depends on 30-second timer alignment for relay recovery.
- Resume does not trigger full restart in the healthy-recovery case.
- Resume, manual reconnect, and relay-state push cannot create overlapping
  recovery storms.

### Commands

```bash
flutter test test/core/lifecycle
flutter test test/core/services
flutter test integration_test/background_reconnect_test.dart -d <device>
```

---

## Phase 6: Group Continuity and Exactly-Once Recovery

### Goal

Make groups survive relay recovery without silent delivery loss or duplicate
catch-up.

### Production Scope

Likely files:

- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`

Implementation steps:

1. Rejoin group topics automatically only when:
   - watchdog restart happened
   - Go reports missing joined topics
2. Drain group inbox on resume and after watchdog restart:
   - fetch the first page on the short resume budget
   - continue remaining pages in the background using a stable opaque cursor
     rather than relying on `sinceTimestamp` alone
3. Refresh group rendezvous registrations before TTL expiry for all joined
   groups, including announcement groups.
4. Improve group mesh formation:
   - reuse existing connections first
   - use discovered or peerstore addresses with normal connect or dial before
     forcing relay-circuit dialing
   - keep relay dialing as fallback when direct or upgraded paths are not ready
5. Change group dedupe to prefer `messageId` uniqueness.
6. Keep announcement groups on the same live plus durable network path as chat
   groups; only admin-only write authorization differs.
7. Keep live fanout diagnostics separate from durable-send success semantics.
8. Add per-peer cooldown or backoff so missing group peers are not redialed
   aggressively every discovery interval.
9. Add node-wide jitter and concurrency caps so many groups do not redial and
   rediscover in the same burst after resume or watchdog restart.

### RED Tests

#### Flutter Unit Tests

**File:** `test/features/groups/application/send_group_message_use_case_test.dart`

- `topicPeers zero does not fail group send when durable inbox store succeeds`
- `announcement admin send keeps success semantics when live fanout is zero`
- `announcement non-admin remains blocked before any network send starts`

**File:** `test/features/groups/application/rejoin_group_topics_use_case_test.dart`

- `rejoin is idempotent when topic already active`
- `rejoin runs after watchdog restart`
- `rejoin is skipped after successful in-place recovery`
- `announcement groups are rejoined and refreshed like normal groups`

**File:** `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

- `resume drains group inbox for every joined group`
- `drain after watchdog restart retrieves messages exactly once`
- `drain after in-place recovery still allowed and idempotent`
- `resume drains missed announcement messages exactly once for offline readers`
- `resume drains first group-inbox page before background continuation completes`
- `group inbox continuation uses cursor rather than timestamp guessing`

**File:** `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

- `deduplicates by messageId when pubsub and group inbox deliver same message`
- `duplicate group inbox replay does not resave media`

Purpose:

- remove the current dependency on content-plus-timestamp dedupe only

#### Go Unit Tests

**File:** `go-mknoon/node/pubsub_test.go`

- `PublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend`
- `GroupRecovery_PreservesTopicStateAcrossInPlaceRefresh`
- `AnnouncementGroup_AdminPublishWithZeroPeersStillUsesDurableFallback`
- `GroupDiscoveryLoop_BacksOffRepeatedDialFailures`
- `GroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback`
- `KnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay`
- `GroupRecoveryLimiter_CapsConcurrentDiscoveryAcrossGroups`
- `GroupRecoveryLimiter_JittersBurstAfterResume`

**File:** `go-mknoon/node/rendezvous_test.go` or a new group discovery refresh test

- `GroupRendezvousRefresh_KeepsRegistrationAlivePastTTL`
- `AnnouncementGroupRendezvousRefresh_UsesSameTTLRefreshPath`

**File:** `go-relay-server/group_inbox_test.go`

- `TestGroupInboxStore_CursorPaginationExactOnceAcrossPages`

#### Integration Tests With Fakes

**File:** `test/features/groups/integration/group_resume_recovery_test.dart`

- `member backgrounded during send receives missed group messages after resume`
- `same message is not duplicated if both pubsub and group inbox deliver it`
- `watchdog restart rejoins topics and receives subsequent live messages`
- `announcement reader backgrounded during send receives missed announces after resume`
- `group discovery remains live across ttl refresh window without manual rejoin`
- `group peers with usable direct addresses form live links without forced relay dial`
- `many joined groups resume without bursting recovery work all at once`

#### Device / Simulator Smoke Tests

New recommended file:

- `integration_test/group_recovery_e2e_test.dart`

Existing files to extend:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

Scenarios:

1. two devices in same group
2. device B backgrounds
3. device A sends N messages
4. device B resumes
5. device B receives all messages exactly once
6. subsequent live messages still arrive without app restart
7. same flow repeated for an announcement group where only admin writes
8. group remains discoverable and recoverable across TTL refresh window

### GREEN Implementation

- Add `messageId`-based group dedupe path.
- Hook resume recovery into group inbox drain.
- add periodic group rendezvous refresh for chat and announcement groups.
- make group discovery and known-member dialing actually use direct or
  peerstore addresses before relay fallback.
- add stable cursor-based group inbox continuation.
- add per-peer dial cooldown or backoff inside group discovery.
- add node-wide jitter and concurrency caps for multi-group recovery.
- Add Go-to-Flutter signal for watchdog restart / missing group topics.

### Exit Criteria

- Mid-session relay recovery does not silently break groups.
- Group catch-up after resume is exactly-once for persisted messages.
- announcement readers recover missed announces exactly once.
- group and announcement discovery do not expire silently on long-running apps.
- group live delivery does not stay unnecessarily relay-centric when direct
  paths are already usable.
- multi-group resume does not burst discovery and relay dial work in one spike.

### Commands

```bash
flutter test test/features/groups/application
flutter test test/features/groups/integration
cd go-mknoon && go test ./node -run 'Group|Publish|Rendezvous'
flutter test integration_test/group_recovery_e2e_test.dart -d <device>
```

---

## Phase 7: Watchdog, Chaos, and Deployment Validation

### Goal

Prove the new architecture is safe under failure, not only on happy-path local
tests.

### Production Scope

- Add bounded watchdog policy and metrics.
- Add operational telemetry and rollout flags.
- Validate failover behavior on real devices and real relay processes.
- Harden relay-server capacity behavior under load.

Suggested rollout flags:

- `enableSharedRelayBackend`
- `enableMultiRelayRouting`
- `enableReservationAwareHealth`
- `enableInPlaceRelayRecovery`
- `enableResumeGroupRecovery`

### RED Tests

#### Go Unit Tests

**File:** `go-mknoon/node/relay_session_test.go`

- `watchdog triggers after N consecutive refresh failures`
- `single successful refresh resets watchdog failure counter`
- `watchdog marks needsGroupRecovery for Flutter`

#### Go Integration Tests

**File:** `go-mknoon/integration/failover_test.go`

- `second relay available prevents watchdog restart`
- `all relays unavailable enters degraded state and later recovers`
- `rendezvous and inbox still work after relay A process restart`

**File:** `go-relay-server/limits_test.go` or equivalent relay hardening tests

- `finite relay limits reject excess load predictably`
- `admission control preserves latency for admitted peers under pressure`

#### Flutter Integration With Fakes

**File:** `test/core/resilience/network_failover_test.dart`

- `1:1 send path survives relay A loss`
- `group send path survives relay A loss`
- `resume during partial failover remains consistent`

#### Device Smoke and Soak

Recommended new files:

- `integration_test/multi_relay_failover_test.dart`
- `integration_test/relay_chaos_soak_test.dart`

Required device scenarios:

1. Android device on WiFi
2. Android device switching WiFi to mobile data
3. iOS device background/resume
4. two active relays, then kill one
5. all relays down, then one returns
6. group chat with one offline member and one online member
7. 30-60 minute soak with periodic background/resume and sends

### GREEN Implementation

- Add watchdog thresholds and telemetry.
- Add deployment flags.
- Replace infinite relay limits with explicit finite limits and document the chosen caps.
- Publish operational runbooks for relay cutover and rollback.

### Exit Criteria

- No user-visible regression in normal chat flows.
- Multi-relay failover works for:
  - discovery
  - 1:1 inbox
  - group inbox
  - push token registration
  - live relay circuits
- Restart is observed only as fallback, not primary behavior.
- Relay overload behavior is bounded and observable rather than unbounded.

### Commands

```bash
cd go-relay-server && go test ./...
cd go-mknoon && go test ./...
flutter test test/core/services
flutter test test/core/lifecycle
flutter test test/features/groups/application
flutter test test/features/groups/integration
flutter test integration_test/conversation_bridge_test.dart -d <device>
flutter test integration_test/background_reconnect_test.dart -d <device>
flutter test integration_test/group_recovery_e2e_test.dart -d <device>
flutter test integration_test/multi_relay_failover_test.dart -d <device>
dart run integration_test/scripts/run_transport_e2e.dart --device <device>
```

---

## Recommended Test Matrix

## Unit Tests

Must cover:

- interactive send ordering and short-race winner selection
- fresh-identity bootstrap path
- startup inbox-first behavior
- fast first-page plus background continuation semantics for 1:1 inbox
- returning cold start after reboot with quick bounded retry
- timeout-class separation between foreground chat, startup, recovery, and media
- stream-level deadline and reset enforcement across outbound and inbound paths
- relay selection and fallback
- reservation state transitions
- Go-side singleflight or serialization for overlapping recovery callers
- personal rendezvous TTL refresh and watchdog re-registration
- watchdog threshold logic
- node status backward compatibility
- structured recovery result and error fields
- bridge payload forwarding
- bounded async Go-to-Flutter event delivery and status-event coalescing
- group dedupe by `messageId`
- stable group inbox cursor semantics and paginated exactly-once continuation
- inbox and group inbox shared-store semantics

## Integration Tests With Fakes

Must cover:

- startup inbox drain while relay is still connecting
- transport switch from relay to WiFi without duplicate sends
- returning cold start after reboot recovers inbox before group warm tasks
- foreground send stays fast while background healing continues independently
- resume recovery orchestration
- resume and manual reconnect sharing one effective recovery
- race conditions during stop/dispose
- watchdog escalation
- exactly-once group recovery
- exactly-once announcement recovery for offline readers
- group and announcement TTL refresh behavior
- multi-page group catch-up continuation
- group mesh formation preferring direct or discovered paths before relay fallback
- startup discoverability after first healthy relay even if another relay is dead
- personal inbox drain after partial outage
- multi-group resume with node-wide recovery caps and jitter

## Go Process Integration Tests

Must cover:

- direct and relay send paths under separate interactive and recovery budgets
- cold-start inbox retry burst stays bounded before watchdog takes over
- two relay servers with shared backend
- relay failover for rendezvous
- relay failover for 1:1 inbox
- relay failover for group inbox
- inbox and group-inbox continuation across relay failover
- media and profile relay access failover through shared relay selection helpers
- in-place client relay refresh
- finite relay limits and admission behavior under load

## Device Smoke Tests

Must cover:

- app open with queued inbox while relay is still connecting
- 1:1 chat during background/resume
- group chat during background/resume
- relay A failure while app is foregrounded
- relay A failure while app is backgrounded
- network switch between transports
- startup with one dead relay and one healthy relay still becomes discoverable quickly
- large backlog app open still shows first page quickly
- many joined groups resume without bursty reconnect storms

---

## Risks and Mitigations

### Risk: Shared backend introduces operational complexity

Mitigation:

- keep in-memory backend for local dev
- add backend interfaces first
- add relay-server integration tests before rollout

### Risk: In-place recovery causes hidden stale state bugs

Mitigation:

- keep watchdog restart available
- add explicit host-preservation tests
- add per-phase rollout flags

### Risk: Parallel send races create duplicate active delivery

Mitigation:

- use one stable `messageId` across every active path attempt
- persist only the first successful winner
- add sender-side and receiver-side duplicate tests across WiFi, relay, and
  inbox

### Risk: Group recovery causes duplicate messages

Mitigation:

- move dedupe to `messageId`
- add group inbox plus pubsub duplicate tests

### Risk: Bridge schema drift breaks Flutter

Mitigation:

- additive JSON changes only
- lock legacy parsing with tests in phase 0

### Risk: Hung streams bypass the intended timeout policy

Mitigation:

- set stream deadlines immediately after opening streams
- reset timed-out or malformed streams instead of relying on normal close
- add inbound slow-peer tests and outbound hung-stream tests across chat,
  inbox, rendezvous, group-inbox, and media paths

### Risk: Relay reconnect churn increases battery use and trims important peers

Mitigation:

- add conn-manager protections for relay and hot peers
- add per-peer dial cooldown in group discovery
- add node-wide jitter and concurrency caps for multi-group recovery
- test repeated failure paths explicitly before rollout

### Risk: Slow Flutter callbacks stall Go networking or pubsub hot paths

Mitigation:

- move Go-to-Flutter push delivery onto a bounded async dispatcher
- coalesce status-like events while keeping message events lossless
- add overflow or queue-depth telemetry and explicit slow-callback tests

### Risk: Multi-relay improves availability but still collapses under load

Mitigation:

- replace infinite relay limits before production rollout
- add admission and overload tests
- include capacity telemetry in the final rollout phase

### Risk: Group live delivery stays unnecessarily relay-heavy

Mitigation:

- use discovered and peerstore addresses before relay fallback in group mesh
  formation
- add tests that prove direct or upgraded paths are used when already available

---

## Recommended Delivery Order

Do not implement these phases out of order.

Recommended order:

1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Phase 4
6. Phase 5
7. Phase 6
8. Phase 7

The most important sequencing rule is:

Do not ship multi-relay client logic before relay-side shared state exists.

Without that, the app may appear more available at the circuit level while
actually becoming less reliable for discovery and offline delivery.

The second most important sequencing rule is:

Do the user-visible send and startup improvements before the deeper recovery
rewrite.

That delivers a faster chat feel early, keeps the scope sufficient, and gives
later relay-resilience phases a tighter client-side test harness to build on.

---

## Final Recommendation

Proceed with the architecture change, but not exactly as described in
`Issues.md`.

The best path is:

- preserve the working transport building blocks
- improve app-open inbox delivery and interactive send ordering first
- add shared relay control-plane state second
- add multi-relay routing third
- add in-place relay-session recovery fourth
- finish with resume, group recovery, watchdog, and chaos validation

That sequence gives the application the highest chance of landing resilience
improvements without breaking the current chat experience.
