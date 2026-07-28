# 295 - DTR-17 P2P service component decomposition

Status: Plan-green; implementation-complete 2026-07-28
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-17`)
Classification: Plan-green
Closure tier: device
Roadmap ID / wave: `DTR-17` / Wave 4C — Listener, transport, and layering
decomposition
Owner authorization: `DTR17-AUTH-01`; in the current 2026-07-28 request, the
project owner explicitly ordered Codex to plan, critically review, update, and
implement DTR-17.
Date: 2026-07-28

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-28 CEST | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | The TDD query anchored the 5,662-line `P2PServiceImpl` and its direct tests at current fingerprint `4a6dc01007486bc2`. | Verify current responsibilities, callers, tests, and gates in source. |
| 2026-07-28 CEST | Evidence Collector — production | P2P facade/implementation; production bootstrap; application root; bridge, lifecycle, notification, and LAN callers | Inbox custody and peer/LAN session policy are cohesive cuts. Bridge callback registration, node lifecycle, readiness/recovery, state projection, push-token recovery, and disposal remain cyclic and must stay facade-owned. | Freeze the public facade and exact component ports. |
| 2026-07-28 CEST | Evidence Collector — proof | core P2P/lifecycle suites; 1:1, transport, core, performance, architecture, roots, and completeness gates | Existing tests deeply cover both behavior clusters, but no causal contract requires component ownership or prevents cosmetic file splitting/concrete back-references. | Add one causal AST/source ownership contract plus exact preservation rows. |
| 2026-07-28 CEST | Planner | roadmap; tier/template/sufficiency references; live device matrix; dirty-tree snapshot | Two private part-file coordinators are the smallest meaningful split that preserves DTR-12’s exact exception identities and does not pre-empt DTR-18. The physical Pixel 6 `21071FDF600CSC` is available for the roadmap-required transport lane. | Run the requested independent `$tdd-review`, patch only verified deltas, then execute under `DTR17-AUTH-01`. |
| 2026-07-28 CEST | Independent reviewers | plan; P2P implementation; Bridge/GoBridgeClient; application disposal; focused tests; architecture and gate tooling | `plan-fixes-required`: direction confirmed, but the constructor count, post-stop callback claim, exact ownership/port manifest, public shim ownership, callback-reinitialize proof, and teardown proof needed correction. | Apply only these verified deltas, re-run the counterexample sweep, and accept or block the plan. |
| 2026-07-28 CEST | Final verifier | corrected plan; exact current source anchors; refined Graphify review context | All verified gaps are repaired; five-lens verdict `ready`. No third component, public/API change, exception rebaseline, new async boundary, or extra device campaign is justified. | Start causal contract/registration RED, then implement the accepted literal manifest. |

## Problem And Evidence

- Behavior to improve: the P2P implementation must expose the same stable
  facade while durable inbox custody/replay and peer/LAN session policy gain
  explicit, independently bounded component ownership.
- Impact: `lib/core/services/p2p_service_impl.dart` is 5,662 lines.
  `P2PServiceImpl` begins at `:110`, implements the base service plus nine
  optional capabilities at `:110-121`, directly owns every bridge callback,
  inbox replay state, peer/LAN caches, health/recovery state, and public
  delegation, and has a 19-parameter constructor at `:404-448`. A change to one
  responsibility is therefore reviewed and tested through the whole service.
- Confirmed current gap:
  - no P2P component/ownership contract exists;
  - durable inbox staging, replay, ack, drain, direct/LAN commit, store,
    retrieve, and attention logic live in the facade at
    `p2p_service_impl.dart:1070-2297,4150-4385,4774-5009,5135-5197,5385-5401`;
  - LAN discovery/advertising, warm/connectivity debounce, sticky transport,
    relay presence/liveness/drop state, and local send/media live in the same
    facade at `:852-1068,2611-2825,3715-3853,4420-4708,5199-5384,5403-5627`;
  - the sole production constructor is
    `lib/app/bootstrap/production_application_bootstrap.dart:3207`, while
    `lib/app/application_root.dart:214` intentionally retains the concrete
    facade for additive capabilities.
- Confirmed safe seam:
  - `_P2PInboxCoordinator` can own durable inbox state and decisions through
    explicit state/readiness, bridge, replay, message-emission, proof, and
    diagnostics ports;
  - `_P2PPeerTransportCoordinator` can own peer/LAN state and decisions through
    explicit node-state, gate, dial, drain, local-service, and event ports;
  - `P2PServiceImpl` remains the sole public facade, bridge callback registrar,
    node lifecycle/readiness/recovery/state owner, and disposer.
- Existing coverage:
  - `test/core/services/p2p_service_impl_test.dart` contains the broad
    start/warm/inbox/readiness/relay/state contract;
  - durable replay/ordering is pinned by
    `p2p_service_inbox_ack_ordering_test.dart`,
    `p2p_service_contact_request_inbox_replay_test.dart`,
    `p2p_service_impl_health_drain_test.dart`, and
    `p2p_service_impl_inbox_proof_kick_test.dart`;
  - peer/LAN behavior is pinned by early-discovery, address-update, LAN
    availability/forward/media, inbound transport, upgrade, learned-transport,
    presence, liveness, stop-race, and fault-injection suites;
  - lifecycle/production wiring is pinned by
    `main_replay_disposition_wiring_test.dart`,
    `main_presence_lifecycle_wiring_test.dart`,
    `main_keepalive_wiring_test.dart`, background reconnect, and connectivity
    lifecycle tests.
- Missing coverage: no test requires the two component files/interfaces,
  proves their exact field/method ownership and port-only dependency, freezes
  the complete facade constructor/implements/public-member shape, keeps bridge
  callback slots facade-owned, or verifies the new causal test enters all
  three affected curated inventories.
- Confirmed boundary constraints:
  - `Bridge` has single mutable callback slots at
    `lib/core/bridge/bridge.dart:28-42`; components must not register or clear
    them independently;
  - the LAN inbound commit handler installed by the facade at
    `p2p_service_impl.dart:479` must retain stage-before-ACK behavior;
  - eight current core-to-feature exception identities for
    `p2p_service_impl.dart` are pinned at
    `tool/architecture_guard/architecture_boundary_exceptions.json:2032-2134`
    and owned by DTR-18. New ordinary Dart libraries importing those feature
    types would create prohibited new identities, so the two components are
    `part` files in the same library.
- Refuted findings:
  - a third node-session extraction is not a safe “more complete” version of
    this plan: readiness, recovery, inbox drains, LAN advertising, mutable
    bridge slots, and disposal have late-bound cycles, so it would either
    create a concrete back-reference or change ordering;
  - moving the components into `lib/app/**` would not merely decompose the
    service; it would consume DTR-18’s layering/exception-relocation scope;
  - an arbitrary LOC target does not prove ownership and is not used.
- Unresolved findings: none blocking. The raw Android notification convergence
  probe’s direct inbox retrieve bypass remains deliberate debug proof, not a
  production facade ownership claim.
- Affected production, test, gate, and documentation files:
  `lib/core/services/p2p_service_impl.dart`; new
  `lib/core/services/p2p_impl/p2p_inbox_coordinator.dart` and
  `p2p_peer_transport_coordinator.dart`; new
  `test/core/services/p2p_service_impl_composition_contract_test.dart`;
  existing focused P2P/lifecycle suites; both gate scripts; C4 component/file
  documentation; this roadmap, plan, and index.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `4a6dc01007486bc2`; current.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-17 decompose P2PServiceImpl behind stable interfaces after DTR-14: responsibilities, callers, tests, 1to1 transport core-host-all performance-host gates" --profile tdd --budget 700`.
- Anchors:
  `P2PServiceImpl` ->
  `lib/core/services/p2p_service_impl.dart:110`
  (`lib_core_services_p2p_service_impl_p2pserviceimpl`).
- Surfaced proof/gate files:
  `p2p_service_impl_wake_attach_test.dart`,
  `p2p_service_impl_test.dart`, production P2P consumers, and core/1:1 gate
  registration.
- Graph gaps requiring source search: exact method clusters, mutable callback
  ownership, lifecycle/headless/debug bypasses, DTR-12 exception identities,
  the richer versus host-only 1:1 inventories, transport device semantics, and
  performance thresholds.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add two library-private component parts under
  `lib/core/services/p2p_impl/`:
  - `_P2PInboxCoordinator` owns inbox staging-entry construction, predecrypt,
    replay/disposition/quarantine, single-flight drain/pagination, replay-before-
    ack, deferred startup drain state, direct/LAN durable commit decisions,
    detailed store/readiness/wake attachment, retrieve, and attention count;
  - `_P2PPeerTransportCoordinator` owns early LAN discovery/advertising and
    peer forwarding, warm attempt/network-change debounce, learned transport,
    presence cache/get/set, liveness/drop state, direct-address predicates,
    local discovery/send/media, and related transport diagnostics.
- Give each coordinator one narrow private port object (or exact typed
  immutable port object. Port members are typed state snapshots and I/O
  primitives; they may not be service locators or callbacks that simply move a
  transferred decision back into the facade. A component may not retain,
  accept, cast to, or dynamically recover a `P2PServiceImpl` reference.
- Keep `P2PServiceImpl` as the unchanged public facade. It constructs both
  coordinators internally and delegates the transferred `P2PService`,
  `DetailedInboxStore`, `P2PFullInboxDrain`, `DurableLanSender`,
  `RelayPresenceLookup`, `RelayPresenceSet`, `PeerLivenessProbe`,
  `PeerDropSignal`, and `InboxAttentionSignal` members.
- Keep bridge callback registration/clearing, node start/stop/raw
  discover/dial/send, readiness/health/recovery/state projection, push-token
  recovery, stream-controller ownership, and final disposal in the facade.
  The facade dispatches inbound direct/LAN events and state transitions to the
  coordinators through their ports.
- Keep `_handlePeerConnected`, `_handlePeerDisconnected`,
  `_handleAddressesUpdated`, and `_handleRelayStateChanged` as facade-owned
  lifecycle/state handlers. They may call narrow peer-coordinator cache,
  diagnostic, and advert-port operations, but state projection, readiness,
  recovery, push re-registration, and stop guards stay in the facade.
- Preserve the current 19-parameter constructor and every public/static member
  signature. In particular, `maxInboxPages`,
  `maxRecoverableInboxReplayEntries`, `maxConcurrentInboxDecrypts`,
  `debugLibp2pListenPort`, `startEarlyLocalDiscovery`, `onNetworkChanged`, and
  `hasNonCircuitDirectConn` remain declared on `P2PServiceImpl` as constants,
  static helpers, or thin delegates. Do not expose coordinator injection in
  production.
- Construct both immutable ports and coordinators before registering bridge
  callbacks or synchronous-capable local/network subscriptions. The facade
  owns those subscriptions and callback slots. On dispose it cancels/fences
  them in the current order, disposes coordinator-owned timers/cache state,
  closes facade controllers, and then clears all five P2P callback slots.
- Add one AST/source composition contract that verifies real ownership,
  delegation, port-only dependency, sole callback registration, API
  fingerprint, and exact gate membership. Migrate C4 descriptions to the new
  exact owners without changing broader layering direction.

Must preserve:

- Durable direct/LAN/relay ordering: stage before commit/ACK, replay before
  ack completion, no double confirm, retryable rows retained, and migration
  gating rechecked -> TC-295-03.
- Concurrent drain coalescing, stronger full-drain promotion, health-tick
  drain starvation guard, and stopped-to-started deferred drain -> TC-295-04.
- The current user-owned wake-token startup-readiness change in
  `p2p_service_impl.dart:4814-4943`: one original timeout budget, tokenless
  immediate dispatch, node-state race closure, remaining bridge budget, safe
  disposal/stream close, and observer isolation -> TC-295-05.
- LAN seed-before-dial, connectivity drain before active-peer early return,
  warm debounce/backoff, sticky transport invalidation, presence/liveness
  account gate, and normalized peer-drop state -> TC-295-06.
- Facade-only bridge callback assignment/clearing; one direct and one state
  callback still delegate exactly once after bridge reinitialize; the four
  lifecycle/state callbacks remain inert after stop; current direct-message
  post-stop staging/emission remains unchanged; all five slots clear on
  dispose; and app disposal remains P2P before bridge -> TC-295-02/07.
- Local-network permission advert gate, address-shape parity, local media
  stream and direct-media predicates -> TC-295-07 and the transport lane.
- Production constructor, application-root concrete capability wiring,
  headless push staging, resume ordering, direct caller signatures, exported
  replay types, and every public `P2PService` default -> TC-295-02.

Hard `Do not`:

- Do not change schema, persistence formats, replay dispositions, ack/confirm
  protocol, crypto, relay/wire/native commands, notification routing, timing
  constants, event names/details, or public API behavior.
- Do not add a queue, isolate, stream relay, microtask, timer, or asynchronous
  hop merely to cross a component boundary.
- Do not let either component register/clear `Bridge` callbacks or own the
  bridge lifecycle.
- Do not inject a component through the public constructor, expose a new
  production facade, move the implementation out of its current library, or
  replace typed dependency ports with `dynamic`, untyped dependency maps,
  service locators, or a concrete facade back-reference. Existing
  `Map<String, dynamic>` wire/diagnostic payloads remain valid data, not
  dependency injection.
- Do not add, move, delete, or rebaseline a DTR-12 architecture exception.
  DTR-18 owns the eight existing upward imports and broader relocation.
- Do not absorb DTR-16 listener decomposition, DTR-18 orchestration moves,
  dependency upgrades, or unrelated P2P behavior fixes.

Deferred / accepted difference:

- Node lifecycle, health/recovery/readiness projection, bridge callback slots,
  stream controllers, push-token re-registration, and final disposal remain in
  `P2PServiceImpl`; owner DTR-18 or a separately reviewed follow-up, because a
  third split now creates cyclic ordering risk.
- `android_notification_payload_e2e.dart` retains its debug-only raw inbox
  retrieve convergence probe; owner debug E2E proof, because it is not a
  production bypass of facade behavior.
- The existing eight core-to-feature imports remain at the exact original
  source identity; owner DTR-18.

Dependencies:

- DTR-14 and Wave 4B are Plan-green/Wave-accepted, so DTR-17’s predecessor is
  satisfied.
- `DTR17-AUTH-01` authorizes only this reviewed two-coordinator boundary.
- DTR-16 may proceed independently. DTR-18 must wait for both stable facades.

### Literal Ownership And Port Manifest

Inbox coordinator:

- Move the existing dependency/state fields
  `_receivedWakeTokenStore`, `_acceptedInboxWakeTokenHashObserver`,
  `_inboxStagingRepository`, `_replayRecoveredInboxChatMessage`,
  `_replayLiveLanChatMessage`, `_replayLiveDirectChatMessage`,
  `_replayRecoveredInboxIntroductionMessage`,
  `_replayRecoveredInboxContactRequest`,
  `_replayRecoveredInboxReaction`,
  `_replayRecoveredInboxMessageDeletion`, `_predecryptInboxChatEntry`,
  `_drainInProgress`, `_drainInProgressWaitsAllPages`,
  `_pendingStartupDrain`, and `_pendingStartupDrainWaitForAllPages`.
- Move the complete current decision bodies
  `_normalizeInboxTimestamp`, `_messageTypeFromEnvelope`,
  `_stagingEntryFromRawInboxMessage`, `_stagingEntryFromDirectMessage`,
  `_stagingEntryFromLanMessage`, `_shouldDurablyStageDeferredDirectChat`,
  `_messageWithoutConfirmNonce`, `_replayUnstagedReaction`,
  `_processDurablyStagedDirectChat`, `_replayDurablyStagedLanChat`,
  `_predecryptInboxChatEntries`, `_replayStagedInboxEntries`,
  `_quarantineRecoveredInboxEntry`, `_applyRecoveredInboxOutcome`,
  `_retrievePendingInboxPage`, `_drainOfflineInbox`,
  `_continueDrainingOfflineInboxDurably`, `_drainOfflineInboxDurably`,
  `_commitInboundLanChatMessage`, `_handleMessageReceived`,
  `storeInInbox`, `storeInInboxDetailed`, `_waitForNodeStart`,
  `_inboxStoreReadinessFailure`, `retrieveInbox`, `drainOfflineInbox`,
  `drainOfflineInboxFully`, `_scheduleStartupDrain`, and
  `countNeedsAttentionInboxEntries`.
- Add one typed `onNodeStateTransition(previous, current)` entrypoint that owns
  only the deferred-startup-drain decision currently embedded in
  `_emitState`; the facade invokes the returned action at that same point.
- `_P2PInboxPort` exposes only `readNodeState`, `nodeStateStream`,
  `allowsAccountNetworkSideEffects`, the typed direct-confirm/store/retrieve/
  ack bridge primitives, `emitIncomingMessage`, `isMessageStreamClosed`,
  `recordTransport`, `recordSuccessfulInboxProof`, and
  `recordInboxProofFailure`. Replay/wake/predecrypt/repository dependencies are
  coordinator constructor values, not reverse facade callbacks. The port does
  not expose `Bridge`, a controller, or a general send/lookup facility.

Peer/LAN coordinator:

- Move `_LearnedTransport`, `_PresenceCacheEntry`, and `_WarmAttempt`, plus the
  state/dependency fields `_localP2P`, `_transportMetrics`,
  `_peersUpgradedToDirect`, `_learnedTransport`, `_presenceCache`,
  `_presenceCacheTtl`, `_warmAttempts`, `_activePeerId`,
  `_lastNetworkRewarmAt`, `_localDiscoveryActive`,
  `_lanDialForwardedPeerIds`, `_lanEmptyReResolvedPeerIds`,
  `_resolvedAdvertQuicPort`, `_resolvedAdvertTcpPort`,
  `_localNetworkProven`, `_lanPermProbeTimer`, and
  `_suspectedDroppedPeers`.
- Move the current LAN lifecycle/advertising bodies
  `_startLocalDiscovery`, `_libp2pListenPort`, `_setLocalDiscoveryActive`,
  `_setLocalDiscoveryInactive`, `_startLanPermProbe`,
  `_recordLanAvailability`, `_forwardLanPeersToLibp2pDial`,
  `_reResolveEmptyLanPeer`, `_maybePublishLibp2pAdvertPorts`, and the decision
  body now inside the discovered-peer subscription; warm-policy bodies
  `_shortPeer`, `warmPeer`, `_onWarmDialOutcome`, `onNetworkChanged`, and the
  four `_warm*` constants; typed transport-diagnostic/cache bodies
  `_shortId`, `_recordPeerUpgrade`, `_recordPeerDowngrade`,
  `_resolveFullPeerId`, and `_inferTransportForPeer`; and relay/local public
  decision bodies `probeRelay`, `lookupRelayPresence`,
  `_relayPresenceFromString`, `setPresence`, `pingPeer`,
  `isPeerSuspectedDropped`, `setPeerDropSuspected`, `isConnectedToPeer`,
  `isLocalPeer`, `hasNonCircuitDirectConn`, `_libp2pLanMediaEnabled`,
  `lastKnownGoodTransport`, `recordSuccessfulTransport`,
  `discoverLocalPeer`, `sendLocalMessageDurable`, `sendLocalMessage`,
  `sendLocalMedia`, and `_sendLibp2pLanMedia`.
- Add typed event entrypoints for peer disconnect, relay-health transition,
  listen-address update, discovered-peer snapshot, and a facade-parsed
  `_PeerTransportDiagnostic`; the four raw Bridge state handlers remain in the
  facade and contain no transferred cache/advert decision bodies.
- `_P2PPeerTransportPort` exposes only `readNodeState`,
  `allowsAccountNetworkSideEffects`, typed raw dial/drain, relay
  probe/presence/ping, LAN-forward/media I/O primitives, and the existing event
  emitter shape. It exposes no `Bridge`, controller, callback slot, service
  locator, or general facade callback.

Facade-retained exact owners:

- Keep the exported replay enum/typedefs and `maxInboxReplayAttempts`, the
  unchanged implements list and 19-parameter constructor, all controllers,
  node/readiness/recovery/health/push fields and methods, raw node
  start/stop/send/discover/dial, `_emitIncomingMessage`, `_emitState`,
  `_computeDirectReady`, all five callback handlers and callback slots, and
  final `dispose`.
- Keep facade declarations and thin delegates for `maxInboxPages`,
  `maxRecoverableInboxReplayEntries`, `maxConcurrentInboxDecrypts`,
  `foregroundInboxTimeout`, `debugLibp2pListenPort`,
  `startEarlyLocalDiscovery`, `warmPeer`, `onNetworkChanged`, every moved
  capability-interface member listed above, and
  `hasNonCircuitDirectConn`.
- Keep `_localMessageSub`, `_localPeersSub`, `_localMediaSub`,
  `_transportDiagnosticSub`, `_networkChangeSignal`, `_networkChangeSub`, and
  `_healthCheckTimer` facade-owned. Their listener closures may perform raw
  payload conversion/stream emission only, then delegate the transferred
  decision. `_lanPermProbeTimer` is coordinator-owned; facade disposal cancels
  subscriptions in the existing order, calls the peer coordinator’s bounded
  timer/cache disposal before local-service/controller teardown, then clears
  all five bridge slots.

Whole-unit declaration whitelist:

- `p2p_inbox_coordinator.dart` may declare only `_P2PInboxPort` and
  `_P2PInboxCoordinator`.
- `p2p_peer_transport_coordinator.dart` may declare only
  `_LearnedTransport`, `_PresenceCacheEntry`, `_WarmAttempt`,
  `_PeerTransportDiagnostic`, `_P2PPeerTransportPort`, and
  `_P2PPeerTransportCoordinator`.
- Every declaration is library-private. Neither part may declare an extension,
  mixin, top-level function/variable, second coordinator, or unlisted adapter;
  this prevents part-file privacy from hiding a facade back-reference or
  displaced decision logic.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-295-01 | The facade transfers the literal ownership manifest below into two real part-file coordinators behind typed immutable ports; each part contains only its private port/value/coordinator declarations, has no extension/mixin/top-level escape, never names/casts/accepts `P2PServiceImpl`, never owns a bridge callback slot, and does not use `dynamic` as a dependency type (existing dynamic wire payload values remain allowed) | `test/core/services/p2p_service_impl_composition_contract_test.dart::DTR-17 transfers exact P2P owners behind port-only coordinators` | Host analyzer AST/source / real repository | causal assertion RED: both parts/ports are absent and all enumerated owners remain in `P2PServiceImpl` -> GREEN: exact declarations and event/delegation paths are component-owned, facade owner bodies are absent, and forbidden coupling/escape declarations are absent | restore any enumerated owner body to the facade, add a ceremonial/extra top-level declaration, pass the facade into a component, encode a transferred decision in a port callback, bypass a delegate, register a bridge callback in a part, or use an untyped dependency -> TC-295-01 red | `flutter test --no-pub test/core/services/p2p_service_impl_composition_contract_test.dart --plain-name 'DTR-17 transfers exact P2P owners behind port-only coordinators'`; add exactly once to `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `TRANSPORT_TESTS`; AUTO `core-host-all` |
| TC-295-02 | `P2PServiceImpl` keeps the exact implements list, 19 constructor parameters/defaults/order, public/static member signatures/constants/streams and named public shims, sole production construction, facade-only five bridge callback assignments and clears, and concrete application-root capability wiring; a representative direct/state callback still reaches its coordinator exactly once after `GoBridgeClient.reinitialize()` | `p2p_service_impl_composition_contract_test.dart::TC-295-02 freezes the P2P facade API callback ownership and production construction`; `p2p_service_impl_composition_contract_test.dart::TC-295-02 callbacks survive bridge reinitialize and delegate once`; `test/core/bootstrap/main_bootstrap_boundary_test.dart::DTR-14 main delegates bootstrap through stable application interfaces`; `test/core/lifecycle/main_replay_disposition_wiring_test.dart`; `main_presence_lifecycle_wiring_test.dart`; `main_keepalive_wiring_test.dart` | Host compile + analyzer AST/source and mock-channel Go bridge / exact production files | GREEN API sentinel plus callback behavior on current source -> remains exact after internal composition | change constructor/member shape, add public component injection, move/duplicate a callback assignment, target stale coordinator state after reinitialize, clear from a component, change production count, or hoist an optional capability onto base `P2PService` -> TC-295-02 red | exact focused command below; new contract registration from TC-295-01; existing files AUTO `core-host-all` and curated 1:1 where registered |
| TC-295-03 | Inbox coordinator preserves durable direct/LAN/relay custody: stage before commit, replay before ack completion, ack once after replay, retry/quarantine rules, no double confirm, and migration-gated staged rows remain unacked | `test/core/services/p2p_service_inbox_ack_ordering_test.dart::{staged entries replay and reach the render stream even when the inbox ack never completes, replay commit precedes ack completion and the ack is still sent exactly once, migration-gated page stays staged-not-replayed-not-acked}`; focused durable cases in `p2p_service_impl_test.dart`; `p2p_service_contact_request_inbox_replay_test.dart` | Host service/integration / fake bridge + in-memory staging repository | GREEN sentinel -> identical ordering/dispositions through coordinator | ack before replay, emit before staging, delete a retryable row, confirm twice, route LAN only through `localMessageStream`, or skip the gate before ack -> named sentinel red | exact files; AUTO `core-host-all`; existing `ONE_TO_ONE_TESTS` coverage |
| TC-295-04 | Inbox coordinator owns one single-flight drain, full-drain promotion, stopped-started deferral, connectivity-triggered roster drain, and per-health-tick starvation prevention without changing lifecycle ordering | `p2p_service_impl_test.dart::{TC-182-04: flap-burst coalesces to ONE connectivity drain (5s floor), TC-182-06: connectivity event before node-start defers then fires on start, drainOfflineInbox defers when node not started and fires on started transition}`; `p2p_service_impl_health_drain_test.dart::{healthy tick drains exactly once; concurrent manual drain coalesces, recovery tick still drains}` | Host service / fake bridge, clock, and gated async drains | GREEN sentinel -> same exact counts, discriminator events, and ordering after ownership move | create one coordinator per call, clear the latch early, place drain after active-peer return, let two callers retrieve, or return from recovery before drain -> named sentinel red | exact files; AUTO `core-host-all`; both are existing curated 1:1 paths |
| TC-295-05 | Detailed inbox store keeps token-by-peer lookup, tokenless immediate dispatch, token-bearing node readiness under one original deadline, remaining bridge budget, accepted-only hash observation, and safe close/dispose behavior | `test/core/debug/wake_token_directionality_readiness_test.dart::{buffers store until ready, normal tokenless store dispatches without waiting for startup, disposal completes a buffered store as failed without dispatch}`; `test/core/services/p2p_service_impl_wake_attach_test.dart::{threads token by toPeerId; empty when absent; served from cache (no per-message SecureKeyStore read), E2E observer sees hashes only after an accepted real attachment}` | Host service / fake bridge, token store, state stream, stopwatch, and observer | GREEN sentinel on the current user-owned implementation -> remains GREEN after moving its exact decision owner | start a second timeout, await readiness for tokenless stores, pass the original rather than remaining budget, miss the check/listen race, observe a rejected store, or let close throw/hang -> TC-295-05 red | exact two files; AUTO `core-host-all`; run directly because not every file is curated |
| TC-295-06 | Peer transport coordinator preserves early LAN discovery, LAN-seed-before-warm-dial, same-tick debounce/backoff, connectivity drain before active-peer return, sticky transport TTL/invalidation, presence get/set, ping, and normalized drop latch | `test/core/services/p2p_service_early_discovery_ordering_test.dart::startNode starts local discovery before the inbox-drain warm body, exactly once`; `p2p_service_impl_test.dart::{TC-182-03: connectivity drain AND re-warm both fire with an active peer, TC-182-04: flap-burst coalesces to ONE connectivity drain (5s floor)}`; `p2p_service_learned_transport_invalidation_test.dart::disconnect invalidates the learned transport`; `p2p_service_impl_presence_cache_test.dart::lookupRelayPresence caches within TTL and re-queries after expiry`; `p2p_service_peer_liveness_test.dart::{TC-183-09b: a THROWING bridge degrades to false (never throws) + emits EXCEPTION, TC-187-21 (impl): set/get/clear normalizes the peer key}` | Host service / fake local P2P, bridge, clock, gate, and connectivity stream | GREEN sentinel -> identical bridge calls, counts, ordering, cache results, and never-throw outcomes through coordinator | dial before LAN seed, set in-flight after first await, clear escalation, early-return before drain, retain stale local/direct cache, bypass migration gate, throw a ping, or stop normalizing drop keys -> corresponding sentinel red | exact focused command; AUTO `core-host-all`; existing 1:1 registration |
| TC-295-07 | Local address/advert/media and shutdown paths remain safe: permission-gated re-advertise, address shape parity, durable LAN ack/media stream, one facade callback owner, the four state/lifecycle callbacks remain inert after stop, current direct-message post-stop behavior is preserved, all five callbacks clear on dispose, the coordinator timer and facade subscriptions become inert, and application teardown keeps P2P before Bridge | `test/core/services/p2p_service_addresses_updated_test.dart::{onAddressesUpdated callback is registered on bridge, dispose clears all five P2P bridge callback slots}`; `p2p_service_addr_shape_parity_test.dart::TC-190-05: 0.0.0.0-mined and real-addr listenAddresses shapes derive identical advert ports (no rollout advert churn)`; `p2p_service_local_media_wiring_test.dart::U4 happy: inbound PUT surfaces on incomingLocalMediaStream via the wired consumer (offer accepted, SHA-256 verified, file on disk)`; `p2p_service_impl_lan_media_test.dart::TD1: flag ON + non-circuit direct conn ⇒ libp2p-LAN leg invoked with the ciphertext path`; `p2p_service_stop_race_test.dart::{stopNode during relay:reconnect does not resurrect started state, dispose during relay:reconnect does not throw on closed stream controller, bridge state callbacks after stopNode are ignored, direct-message callback after stopNode preserves current staging/emission behavior}`; `p2p_service_lan_availability_test.dart::TC-295-07 dispose cancels facade inputs and coordinator LAN timer`; `p2p_service_impl_composition_contract_test.dart::TC-295-07 clears callbacks and preserves coordinator/application teardown order`; `p2p_service_fault_injection_test.dart::8. Timer cleanup: dispose succeeds cleanly after recovery` | Host service/integration / fake bridge/local services, mock-channel Go bridge, and real temp files | GREEN sentinel -> same state, handler, stream, callback, and disposal outcomes | add/remove a direct-message stop guard, re-advertise before proof, lose a port shape, bypass durable commit, close a controller before in-flight work is fenced, leave a timer/subscription live, register/clear callbacks in two owners, or dispose Bridge first -> corresponding sentinel red | exact focused files; AUTO `core-host-all`; LAN media remains in `TRANSPORT_TESTS` |
| TC-295-08 | The causal contract is selected exactly once by richer 1:1, host 1:1, and transport arrays; both part files are main-reachable; C4 names the two coordinators and the facade-retained lifecycle/callback owners; DTR-12 remains exactly 182 dependency/24 placement pins with the same eight original P2P exception identities | `p2p_service_impl_composition_contract_test.dart::TC-295-08 registers the ownership contract in every affected lane without exception drift`; its exact C4 owner assertions; `architecture-boundaries`; `runtime-roots`; `completeness-check` | Host AST/tool / real scripts, C4 files, manifest, and runtime roots | causal registration/documentation RED until three exact entries and both C4 owner descriptions exist -> GREEN with exact membership, AUTO core discovery, reachable/explained parts, and zero exception drift | omit/duplicate an array entry, register only one 1:1 inventory, leave C4 stale, create an ordinary feature-importing library, add/rebaseline/move an exception, or leave a part unexplained/unclassified -> TC-295-08 red | composition test plus literal policy/list commands below; three manual arrays; AUTO `core-host-all` |
| TC-295-09 | Internal delegation adds no new scheduling hop and preserves existing node-start, online, event-queue, resume/recovery, and inbox-delivery hard budgets | `test/performance/benchmark_node_startup_test.dart::B3: Cold start respects 6s budget`; `benchmark_time_to_online_test.dart::M6: cold-start sendable metric stays under the 6s budget`; `benchmark_event_queue_test.dart::I-Dart-1: Push events arrive at Dart within idle budget`; `benchmark_inbox_delivery_timing_test.dart::E6: deliveryMs is within fast budget for in-memory fakes`; full `performance-host` also retains background-resume and relay-recovery thresholds | Host deterministic performance / fake bridge and clocked event paths | GREEN sentinel -> all existing binary thresholds and zero failures remain GREEN | add a stream relay, timer, queue, isolate, microtask boundary, duplicate event dispatch, or serial wait between facade and component -> relevant hard budget red | `./scripts/run_host_test_gates.sh performance-host --batch-flutter --concurrency 4 --reporter failures-only`; AUTO performance glob |
| TC-295-10 | The existing real-device transport lane still starts/reconnects through the Go bridge/relay, exercises warm/LAN/media transport paths, and completes with no failures after the Dart ownership split | roadmap-required `./scripts/run_test_gates.sh transport` inventory on physical Android `21071FDF600CSC` | Device / Pixel 6 Android 16 plus real Go bridge and configured relay | supporting device proof (not a causal RED) -> all selected host/device tests exit 0 on the pinned target | break bridge callback dispatch, registration, relay recovery, local media, or startup sequencing -> transport lane fails | `FLUTTER_DEVICE_ID=21071FDF600CSC ./scripts/run_test_gates.sh transport`; existing `TRANSPORT_TESTS`, with TC-295-01 newly registered |

### Test Notes

- TC-295-01 must check both files exist before parsing, then compare exact
  declaration, field, method, port-member, and facade-delegate ownership from
  the literal manifest. A part directive, class name, or LOC reduction alone is
  insufficient. It must parse the whole part unit, enforce the declaration
  whitelist, and reject `P2PServiceImpl`, service-locator, callback-slot, and
  `dynamic` dependency types. It must allow existing `Map<String, dynamic>`
  wire/persistence payload values inside method bodies.
- TC-295-02 fingerprints constructor order/name/type/requiredness/defaults, the
  implements list, public/static members, callback assignment/clear sites, and
  single production construction. Its real `GoBridgeClient` mock-channel test
  snapshots all five P2P slots, reinitializes, then dispatches one direct and
  one state event and observes exactly one facade/coordinator effect. Comments
  and joined-source searches do not satisfy owner checks.
- TC-295-03 discriminates replay and ack events/order; a final “message
  visible” result alone can hide ack-before-replay or duplicate confirmation.
- TC-295-04 distinguishes the roster-wide connectivity drain from peer re-warm
  and requires one retrieve under concurrent callers.
- TC-295-05 is preservation of the current dirty-tree Plan-290 seam, not a new
  DTR-17 behavior fix. Execution must snapshot and retain those edits.
- TC-295-07 must separately prove all four guarded state callbacks, the
  deliberately unguarded direct-message callback, all-five-slot disposal,
  facade subscription cancellation, coordinator timer cancellation, and
  application P2P-before-Bridge ordering; “dispose did not throw” is not causal
  evidence for those distinct mutations.
- TC-295-10 is a single-device transport preservation leg, not a two-peer or
  cross-platform claim. No iPhone is required.

## Implementation Steps

1. Snapshot `git status --short` and preserve every unrelated/user-owned dirty
   path. Add TC-295-01/02/08 and the three exact registrations before
   production edits. Run the named TC-295-01 selector and record its assertion
   RED: missing coordinators/current facade ownership.
2. Add the two `part` directives and typed private port contracts. Construct
   both port objects and coordinators in the constructor body before bridge
   callback registration or any synchronous-capable subscription, without
   changing the public constructor.
   Stop-if: either component requires a concrete facade back-reference,
   callback-slot ownership, new async hop, or new architecture exception.
3. Inbox slice:
   - move staging-entry construction, replay/disposition/quarantine, and drain
     state/logic;
   - move direct/LAN durable commit decisions and have the facade dispatch its
     existing bridge/local handlers;
   - move detailed store/readiness/wake, retrieve, deferred drain, and attention
     logic;
   - after each move, run TC-295-01 and the exact inbox/ack/health/wake
     preservation files.
4. Peer/LAN slice:
   - move early discovery/advertise/forwarding and local send/media;
   - move warm/network debounce, learned transport, presence/liveness/drop
     state and decisions;
   - make discovered-peer/network listener closures thin typed delegates, keep
     every subscription, raw Bridge payload parse, node/state/recovery callback
     handler, and final disposal owner in the facade, and dispose the
     coordinator timer/cache state in the frozen teardown sequence;
   - run focused peer/LAN/stop/fault tests after each sub-slice.
5. Update the exact C4 owners, then run causal GREEN, representative mutation
   re-reds, all focused preservation tests, registration/policy gates, 1:1,
   `core-host-all`, justified `performance-host`, and the pinned transport
   device lane.
6. Run strict analysis and diff hygiene. Refresh the architecture graph once
   after the coherent app-owned change and run the affected query for every
   changed production file. Record execution evidence in this plan and update
   the roadmap/index disposition without claiming Wave 4C acceptance.

## Risks And Blind Spots

- Cosmetic file splitting through library privacy -> TC-295-01 forbids a
  facade back-reference and requires exact moved fields/methods and real
  delegation.
- Mutable Bridge slot overwrite or post-dispose callback -> TC-295-02/07 keeps
  registration/clearing solely in the facade and exercises stop/reinitialize
  ordering, including the deliberately different post-stop direct path.
- Replay/ack/confirm reordering or duplicate work -> TC-295-03/04.
- Derived cache/latch survival across connectivity/state transitions ->
  TC-295-04/06 reconstructs or invalidates coordinator state through exact
  transition ports; no durable format changes.
- Sibling-surface consistency: direct bridge, LAN commit, relay drain,
  background staged push, and debug raw convergence paths are explicitly
  distinguished; TC-295-03/05/07 cover changed production paths and the debug
  bypass is accepted out of scope.
- Destructive-action side effects: no deletion behavior is changed; staged row
  delete/preserve and relay ack effects remain exact in TC-295-03.
- Invariant re-verification under new transitions: startup, health recovery,
  connectivity flap, bridge reinitialize, stop, and dispose re-check their
  relevant ports in TC-295-02/04/06/07.
- Rollback: the change is source-only. Reverting the two part files,
  delegations, registrations, and documentation restores the prior facade with
  no schema/wire/data migration. Stop-if prevents a partial component merge.

## Gate Cadence

- Per-plan closure: causal composition contract; exact inbox/peer/lifecycle
  sentinels; curated `1to1`; pinned physical-Android `transport`;
  `core-host-all`; justified `performance-host`; architecture, runtime-root,
  completeness, analyzer, and diff gates.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 4C dependency
  batch (`DTR-16`, `DTR-17`, and `DTR-18`) is complete, and once at final
  rollout/release closure. Run `performance-host` with this plan, at Wave 4C
  closure when still justified, and at final release closure.
- Shared tests outside feature/core globs:
  `test/performance/**` runs through `performance-host`; the transport
  `integration_test/**` paths run through the pinned transport lane.

## Device/Relay Proof Profile

- Profile: single-device.
- Boundary being proven: the existing transport inventory still crosses the
  real Android Go bridge/relay/startup/reconnect boundary after Dart ownership
  moves. It does not claim new wire behavior or two-peer convergence.
- Live availability check:
  `flutter devices --machine; adb devices -l; xcrun simctl list devices available`
  -> physical Pixel 6 `21071FDF600CSC` (Android 16/API 36), Android emulators
  `emulator-5554` and `emulator-5556`, and iOS targets are available.
- Required setup: pin `FLUTTER_DEVICE_ID=21071FDF600CSC`; use the repository’s
  configured real bridge/relay fixtures; no user taps.
- Two-peer default: N/A — the selected transport gate is a single-app/device
  preservation inventory and makes no two-peer claim.
- Closure role: required supporting boundary evidence because DTR-17’s roadmap
  floor explicitly names `transport`.
- `FLUTTER_DEVICE_ID`: sufficient for this single-device row.
- Registration: existing `TRANSPORT_TESTS`; add TC-295-01 exactly once.
- Discovery command:
  `flutter devices --machine` -> `21071FDF600CSC` must be listed and supported.
- Closure command:
  `FLUTTER_DEVICE_ID=21071FDF600CSC ./scripts/run_test_gates.sh transport` ->
  every selected host/device test exits 0 with zero failures.
- Deferred device work: no iOS, two-peer, crypto, or multi-relay campaign;
  those boundaries are unchanged and are not claimed.

## Acceptance Gates

```bash
# Snapshot before execution; preserve and attribute unrelated dirty paths.
git status --short

# First causal RED before production edits: expect non-zero because both named
# coordinators are absent and exact owners remain in the facade.
flutter test --no-pub \
  test/core/services/p2p_service_impl_composition_contract_test.dart \
  --plain-name 'DTR-17 transfers exact P2P owners behind port-only coordinators'

# Focused structural/API GREEN: exit 0; exact ownership, typed ports, facade
# fingerprint, callback ownership, and three-array registration all pass.
flutter test --no-pub \
  test/core/services/p2p_service_impl_composition_contract_test.dart

# Inbox preservation: exit 0; durable staging/replay/ack/defer/coalescing/wake
# contracts pass with no changed event/order behavior.
flutter test --no-pub \
  test/core/services/p2p_service_impl_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/core/services/p2p_service_contact_request_inbox_replay_test.dart \
  test/core/services/p2p_service_impl_health_drain_test.dart \
  test/core/services/p2p_service_impl_inbox_proof_kick_test.dart \
  test/core/services/p2p_service_impl_wake_attach_test.dart \
  test/core/debug/wake_token_directionality_readiness_test.dart

# Peer/LAN/lifecycle preservation: exit 0; callbacks, warm/cache/presence,
# address/media, recovery, stop, and fault paths pass.
flutter test --no-pub \
  test/core/services/p2p_service_early_discovery_ordering_test.dart \
  test/core/services/p2p_service_inbound_transport_test.dart \
  test/core/services/p2p_service_transport_upgrade_test.dart \
  test/core/services/p2p_service_learned_transport_invalidation_test.dart \
  test/core/services/p2p_service_impl_presence_cache_test.dart \
  test/core/services/p2p_service_peer_liveness_test.dart \
  test/core/services/p2p_service_addresses_updated_test.dart \
  test/core/services/p2p_service_lan_availability_test.dart \
  test/core/services/p2p_service_local_media_wiring_test.dart \
  test/core/services/p2p_service_impl_lan_media_test.dart \
  test/core/services/p2p_service_stop_race_test.dart \
  test/core/services/p2p_service_fault_injection_test.dart \
  test/core/bridge/go_bridge_client_test.dart \
  test/core/lifecycle/background_reconnect_smoke_test.dart \
  test/core/lifecycle/connectivity_lifecycle_test.dart \
  test/core/lifecycle/main_replay_disposition_wiring_test.dart \
  test/core/bootstrap/main_bootstrap_boundary_test.dart

# Required curated 1:1 gate: exit 0 with its relay tail.
./scripts/run_test_gates.sh 1to1

# Required affected core family: exit 0 and zero failed tests.
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Required hot-path preservation: exit 0 and every existing binary threshold
# remains green; no new scheduling threshold is invented.
./scripts/run_host_test_gates.sh performance-host \
  --batch-flutter --concurrency 4 --reporter failures-only

# Device availability and roadmap-required transport preservation.
flutter devices --machine
FLUTTER_DEVICE_ID=21071FDF600CSC \
  ./scripts/run_test_gates.sh transport

# Policy/discovery: exit 0; same 182/24 baseline, exact original P2P exception
# identities, reachable parts, and no unclassified test.
./scripts/run_test_gates.sh architecture-boundaries
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check

# Hygiene: zero new diagnostics and no whitespace errors.
./scripts/check_flutter_analyze_strict.sh
git diff --check

# Only after the coherent authorized implementation.
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py affected \
  lib/core/services/p2p_service_impl.dart \
  lib/core/services/p2p_impl/p2p_inbox_coordinator.dart \
  lib/core/services/p2p_impl/p2p_peer_transport_coordinator.dart \
  --budget 600
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-295-01 fails its explicit missing-component/current-owner
  assertions on the pre-refactor tree. All preservation rows are GREEN
  sentinels and must remain green; they are not mislabeled RED.
- Green sentinel: exact inbox, peer/LAN, lifecycle, production-construction,
  performance, architecture, and device-transport contracts named above.
- Pre-existing dirty tree / known failure: Wave 4A/4B work, Plan-290’s
  wake-readiness changes, roadmap/index/gate edits, Graphify outputs, and
  unrelated app/tests are user-owned. Snapshot and attribute them; never
  revert, overwrite, or claim them as DTR-17.
- Environment blocker: none at planning time. Physical Android
  `21071FDF600CSC` is currently available; if it is absent at execution time,
  re-resolve the live matrix and pin another available supported target. An
  unavailable version-specific device is N/A, not a failed gate.
- Scope drift: a third lifecycle component, concrete facade back-reference,
  callback ownership outside the facade, public/API change, new async hop,
  schema/wire/native/crypto behavior change, or architecture exception change
  blocks completion and requires replanning.

- [x] Every component responsibility, facade owner, bypass, and preservation
      boundary has a named automated test or justified device proof.
- [x] TC-295-01 causal RED/GREEN and representative ownership/delegation/
      callback mutations re-red for the documented reason.
- [x] Exact inbox, peer/LAN, lifecycle, facade/API, and performance sentinels
      pass.
- [x] TC-295-01 occurs exactly once in all three manual arrays and is
      auto-discovered by `core-host-all`.
- [x] `performance-host` and pinned physical-Android `transport` pass with
      semantic outcomes.
- [x] `1to1` and `core-host-all` are aggregate-clean: `1to1` passed 2,464
      Flutter tests plus its relay Go tails; `core-host-all` passed 2,840
      Flutter tests across 365 paths plus the Android renderer manifest tail.
- [x] Architecture pins/exception identities, runtime roots, and completeness
      remain exact and trustworthy.
- [x] Strict analysis reports the exact three reviewed generated-l10n
      suppressions and zero issues; targeted analysis and `git diff --check`
      are clean.
- [x] Scope Contract And Guard is respected. The DTR-17 extraction received
      its required incremental Graphify refresh; the later integrated
      aggregate-blocker repair received one separate required refresh, leaving
      the graph current at fingerprint `5f2656692cadb1f9`.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/core/services/p2p_service_impl_composition_contract_test.dart --plain-name 'DTR-17 transfers exact P2P owners behind port-only coordinators'`.
- Preservation command:
  `flutter test --no-pub test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_inbox_ack_ordering_test.dart test/core/services/p2p_service_impl_health_drain_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_stop_race_test.dart`.
- Manual registration: add
  `test/core/services/p2p_service_impl_composition_contract_test.dart` exactly
  once to `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `TRANSPORT_TESTS`.
  `core-host-all` discovers it automatically.
- Migration: none.
- Boundary closure: host causality/preservation plus the existing transport
  inventory on physical Android `21071FDF600CSC`; no two-peer/iOS/crypto/schema
  claim.
- Per-plan cadence: focused tests, `1to1`, `transport`, `core-host-all`, and
  justified `performance-host`; Wave 4C and final release each own one full
  `host-all`.
- Unresolved evidence: none for Plan 295. Wave 4C acceptance and its aggregate
  `host-all` remain separate and are not claimed.

## Reviewer Findings

- Initial independent verdict: `plan-fixes-required`; both reviewers confirmed
  the two-coordinator core bet and found no migration, device, protocol, or
  layering blocker.
- Review grounding:
  - source verification covered the current constructor, all five Bridge
    callbacks, stop/dispose paths, application teardown, exact inbox and
    peer/LAN ownership candidates, curated arrays, DTR-12 manifest, and live
    device profile;
  - the refined Graphify review query anchored
    `_LearnedTransport` in `p2p_service_impl.dart` at fingerprint
    `4a6dc01007486bc2`. Its stale marker is caused by concurrent DTR-16 test work,
    not a changed DTR-17 production anchor, so every conclusion was rechecked
    in current source.
- Required and applied:
  - corrected the constructor from 21 to 19 parameters;
  - replaced the vague owner ranges with literal field/method/public-shim,
    whole-unit declaration, immutable-port, subscription, timer, construction,
    and disposal manifests;
  - narrowed the `dynamic` ban to dependency/escape typing while preserving
    existing dynamic wire and persistence payloads;
  - kept the full address/relay/peer lifecycle callbacks in the facade and
    delegated only typed cache/advert/diagnostic decisions;
  - retained public constants/static helpers and capability members as facade
    declarations with thin delegation;
  - corrected the false blanket post-stop claim, added a sentinel for the
    deliberately unguarded direct-message path, and strengthened the four
    guarded state-callback proof;
  - added causal P2P callback-after-`GoBridgeClient.reinitialize`, all-five-slot
    clearing, subscription/timer inertness, and application
    P2P-before-Bridge teardown proof;
  - made both C4 owner updates part of TC-295-08 rather than an unproved
    documentation side effect.
- Implementation adversarial audit required and applied:
  - preserved branch-local transport-diagnostic parsing after a focused RED
    showed eager facade casts could reject otherwise irrelevant payload
    fields;
  - removed the declared-but-unused raw `discoverPeer` port instead of
    retaining a ceremonial dependency;
  - added a coordinator disposal fence and causal delayed-local-start and
    delayed-presence tests so late async completions cannot re-arm timers,
    repopulate caches, or resume forwarding after disposal;
  - strengthened the structural contract after mutation proved the analyzer
    identifier visitor did not see named types, then required exact callback
    handler targets as well as facade-only assignment counts.
- Rejected as unnecessary: a third lifecycle/session coordinator, moving raw
  callback slots or state/recovery projection, a DTR-12 exception rebaseline,
  a new async boundary, a two-peer/iOS campaign, and per-plan full `host-all`.
- Final five-lens verdict:
  - behavioral truth: exact direct/LAN stage/replay/ack, warm, cache, presence,
    liveness, media, readiness, and post-stop semantics have named proofs;
  - regression resistance: the literal manifest, facade fingerprint, real
    callback dispatch, and representative mutations reject cosmetic splits;
  - state/cleanup: ownership and ordering of all subscriptions, the LAN timer,
    coordinator lifetime, controllers, callback slots, and app teardown are
    explicit;
  - architecture: private parts preserve the eight exact DTR-12 identities and
    defer relocation to DTR-18;
  - evidence economy: focused/family/performance/device gates match changed
    boundaries, with aggregate `host-all` deferred by repository cadence.
- Final verdict after the repairs: `ready`; execute Plan 295 without widening
  its literal ownership manifest.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-28 CEST | reviewed / ready | plan, index, roadmap, P2P/Bridge/application source, tests, gate tooling | `$tdd-review`: initial fixes required; corrected plan passed the refined Graphify/source counterexample sweep | two independent reviewers confirmed the core bet; only verified deltas applied | none | add causal contract/registrations and record RED |
| 2026-07-28 CEST | RED | new composition contract; three curated arrays | `flutter test --no-pub test/core/services/p2p_service_impl_composition_contract_test.dart --plain-name 'DTR-17 transfers exact P2P owners behind port-only coordinators'` -> exit 1 | exact missing paths were `p2p_inbox_coordinator.dart` and `p2p_peer_transport_coordinator.dart`; failure occurred before any DTR-17 production edit | expected causal RED | implement the accepted two-coordinator ownership manifest |
| 2026-07-28 CEST | implementation GREEN | P2P facade; two private coordinator parts; composition/callback/lifecycle tests; gate arrays; C4 | structural contract 4/4; inbox family 150/150; callback/lifecycle family 136/136; expanded peer/LAN/lifecycle family 254/254 | exact facade API and five callback slots remain stable; inbox custody/replay and peer/LAN policy have real port-only owners | none | run adversarial implementation audit and mutations |
| 2026-07-28 CEST | adversarial audit | peer coordinator; facade; transport/LAN/presence and composition tests | diagnostic unused-field selector RED then GREEN; delayed local-start RED then GREEN; delayed presence GREEN; three representative structural mutations RED and restored contract 4/4 GREEN with identical production hashes | branch-local parsing, disposal inertness, forbidden back-reference detection, thin delegation, and exact callback targets are now causal | removed unused `discoverPeer` port; no scope widening | run required families/device/policy |
| 2026-07-28 CEST | required family/device proof | host performance inventory; physical Pixel 6 `21071FDF600CSC` transport inventory | `performance-host` 21 files / 106 tests GREEN; pinned `transport` host contract 12/12 plus native reconnect 1/1, fallback 1/1, transport E2E 3/3, media stable-ID 7/7, warm-peer/LAN 1/1 GREEN | no new async hop or performance threshold; real Android Go bridge/relay/startup/reconnect and LAN/media paths remain sound | none | run policy and aggregate gates |
| 2026-07-28 CEST | policy / graph closure | architecture/runtime inventories; all ten DTR-17 Dart files; Graphify | architecture tests 6/6 and exact 182/24 baseline; runtime roots 20/20 trustworthy/no drift; completeness 1357/1357; targeted analyze clean; diff check clean; one incremental Graphify refresh plus affected query | exact DTR-12 identities and runtime reachability preserved | strict wrapper stops before analysis on the unrelated DTR-16 ratchet; scoped analyzer is clean | record aggregate blockers without claiming Wave acceptance |
| 2026-07-28 CEST | aggregate verification | `1to1`; `core-host-all`; strict wrapper | latest `1to1` `+2463 -1`, with the sole `PendingMessageRetrier` selector immediately GREEN 1/1 in isolation; `core-host-all` `+2839 -1`; strict wrapper exit 1 | every DTR-17-focused/registered test observed GREEN; core and strict failures are the same unexpected `ignore: unused_field` at `group_message_listener_system_transition_processor.dart:76` in concurrent DTR-16 work | aggregate-gate blocker outside DTR-17; do not edit or claim it | rerun aggregate gates after their owning work stabilizes; Wave 4C/full `host-all` remain later |
| 2026-07-28 CEST | Plan-green aggregate closure | deterministic retrier ordering test; DTR-16 system-transition lifecycle emission port; required and affected gates; Graphify | retrier file `4/4`; DTR-16 structural contract `2/2`; system/lifecycle selectors `11/11`; strict analysis zero issues at the exact three reviewed generated-l10n suppressions; `1to1` `+2464` plus relay Go tails; `core-host-all` `+2840` across 365 paths plus Android renderer manifest; affected `groups` `+3265` plus all Go/relay tails; `feature-host-all` `+8441 ~1` across 811 paths; architecture `6/6` and exact `182/24`; completeness `1357/1357`; diff hygiene clean; incremental Graphify refresh current at `5f2656692cadb1f9` | the load-sensitive test now awaits an explicit retry callback instead of sleeping; the concurrent DTR-16 callback is live only at processor-to-facade emission fences, so accepted durable work still completes and the suppression is gone; DTR-17 production scope is unchanged | none for Plan 295 | Plan-green; defer Wave 4C/full `host-all` until the dependency batch is complete |
