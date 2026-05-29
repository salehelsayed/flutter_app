# Test & Simulation Strategy (cross-cutting) — How We Prove Success

Prepared on: 2026-05-29
Status: Proposed (investigation complete, no code changed)
Tracking ID: NET-REL-06

## Why this doc exists

Every other doc in this folder proposes changes whose success is defined in terms
of *which transport/channel a message used* and *how fast*. The single biggest
risk to validating those changes is the **false-positive result**: a test that
goes green because the message was *delivered*, while never proving it traveled
over the *intended* path. This doc establishes the testing doctrine the per-doc
Test Plans build on:

1. The **harness inventory** — what already exists, grounded in real files.
2. The **negative-control principle** — every "we succeeded" test must be paired
   with a control that fails if the implementation cheats or regresses.
3. The **transport-proof primitives** — how to assert the *actual* path used.
4. The **happy/unhappy taxonomy** — both must be covered for every change.
5. What must be **built** (capabilities that don't exist yet).

> The load-bearing finding (verified): real-network E2E tests today deliberately
> accept the `{direct, relay, inbox}` set (`transport_e2e_test.dart` A2/A5/A7
> `pass = transport=='direct' || transport=='relay'`, lines ~916/945/1320;
> `wifi_relay_fallback_smoke_test.dart` `_isAcceptedLiveIncomingTransport` accepts
> `direct||relay||inbox`, ~501-503) to dodge connectivity flake. **No integration
> test currently proves `local`/`wifi` was used over relay.** That is precisely
> the false-result gap we must close for NET-REL-01/03/05.

## 1. Harness inventory (verified — what exists today)

### Go (`go-mknoon/`)
- **In-process relay harness** — `integration/local_relay_harness_test.go`: a real
  libp2p host with `EnableRelayService()` + `ForceReachabilityPublic()` (`:181-189`),
  hand-rolled rendezvous + inbox stream handlers over shared in-memory state.
  `startLocalRelayPair`, `startNodeWithRelays`, `stop/start/restart` for relay-drop
  injection. Runs anywhere (no external dependency).
- **Real external relay harness** — `integration/relay_test.go`: `requireRelay(t)`
  (`:28-66`) probes the production relay and `t.Skip`s if unreachable.
  `TestRelayTwoNodesMessage` (`:361-467`) is the real two-node delivery proof.
- **Transport label unit proof** — `node/transport_label_test.go`: `stubTransportStream`/
  `stubStreamConn` (`:18-116`) feed fabricated multiaddrs to `classifyStreamTransport`
  and assert `"direct"` vs `"relay"` (`:199-243`).
- **Relay-only forcing (NW002 pattern)** — `node/pubsub_delivery_test.go`:
  `clearNW002DirectRouteState` (`:114-137`) closes the peer + `Peerstore().ClearAddrs`
  both ways, `assertNW002NoDirectPeerstoreAddrs` (`:139-154`), then `DialPeerViaRelay`,
  then `assertNW002LimitedCircuitConn` asserts `conn.Stat().Limited == true` (`:156-172`).
- **Failure injection seams** — `node` test hooks: `openChatStreamHook`,
  `recoverPeerForSendHook`, `directConfirmTimeoutOverride`,
  `SetWaitForCircuitAddressHookForTests` (see `send_message_recovery_test.go`).
- **Relay state machine tests** — `node/relay_session_test.go`: drives
  `OnRequestFailed`/`OnRefreshFailed`/`OnReservationEnded`, asserts watchdog threshold
  and recovery coalescing with overridable `recoveryWaitTimeout`.
- **Watchdog/failover** — `integration/watchdog_failover_test.go`: real relay-drop,
  asserts `Status()` fields and inbox fallback through the surviving relay.
- **Benchmarks** — `node/benchmark_*_test.go`: measure send/ack/startup latency via
  `benchmarkPercentile` (p50/p95) but only `t.Logf` — **not** assertion gates.
- **Relay server** — `go-relay-server/*_test.go`: shared-backend failover tests
  (`failover_test.go`) and libp2p `mocknet` protocol tests (`inbox_test.go` with
  `recordingPushSender` FCM mock). **No `metrics_test.go` exists.**

### Flutter/Dart
- **Exact transport assertion (host)** — `test/features/conversation/application/send_chat_message_use_case_test.dart`:
  in-file `FakeP2PService` with configurable `sendMessageTransport`, `localPeers`,
  `probeRelayResult`, ordering callbacks, and call counters. Asserts
  `message.transport ∈ {local, direct, relay, inbox}` deterministically, plus
  `localSendCallCount`, `probeRelayCallCount`, `recordSuccessfulSendProof(sendPath:)`.
- **Multi-node in-memory network** — `test/shared/fakes/fake_p2p_network.dart` +
  `fake_p2p_service_integration.dart`: `setOnline(bool)`, `transportMode`
  ('wifi'/'relay'/'inbox'), `simulateTransportSwitch`, `localPeers`, `localAckDelay`/
  `discoverDelay`/`dialDelay`/`sendDelay`, `discoverAlwaysFails`/`dialAlwaysFails`,
  delete-on-read inbox. The closest Dart analog to a controllable network.
- **LAN WebSocket integration** — `integration_test/wifi_transport_test.dart`: two real
  `LocalWsServer` over loopback (no mDNS, no relay). Proves the WS mechanism *by
  construction* (no other transport exists in-process) — but does **not** exercise the
  `sendChatMessage` race and never sets `transport == 'local'`.
- **Fake discovery** — `test/core/local_discovery/fake_local_discovery_service.dart`:
  manual `addPeer`/`removePeer`, tracks advertised peerId/port — mDNS without Bonsoir.
- **Offline round-trip** — `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`:
  `setOnline(false)` → send lands in inbox → `drainOfflineInbox()` → dedup on receive.
- **Real-network multi-device** — `integration_test/group_multi_party_device_real_harness.dart`
  + `scripts/run_group_multi_party_device_real.dart` + `scripts/group_multi_party_device_criteria.dart`:
  drives 2-4 real iOS sims/devices over a **real relay**, filesystem-coordinated, per-role
  encrypted DBs, identity handoff, **process-death + relaunch**, ~90 scenarios with strict
  verdict JSON (`relayLifecycleProof`, `inboxStored`, per-device `transportPeerId` distinctness).
- **Gate/sim scripts** — `scripts/run_test_gates.sh` (`TRANSPORT_TESTS`,
  `NIGHTLY_ONLY_TESTS` incl. `wifi_transport_test.dart`, `ONE_TO_ONE_TESTS`),
  `scripts/run_reliability_simulations.sh`, `reset_simulators.sh` (sets
  `DISABLE_LOCAL_DISCOVERY=true` → multi-sim runs use **relay**, not wifi).

## 1b. Test fidelity tiers — what each tier can and cannot guarantee

QA round 2 surfaced the single most important truth for "guaranteeing correctness
end-to-end": **most of our transport assertions live in fakes that prove the
*decision logic*, not the real wire.** Be explicit about which tier a test lives in,
because each guarantees something different — and a fake-tier pass must never be
read as an E2E guarantee.

| Tier | Example | Genuinely proves | Does NOT prove |
|---|---|---|---|
| **T1 — fake/use-case** | `send_chat_message_use_case_test.dart` with `FakeP2PService` | The **real `sendChatMessage` orchestration logic** (which rung fires, race winner, call counts, persistence dedup, budget params). `transport=='local'` here proves the use case *picked the local branch given a rigged `isLocalPeer`*. | That real mDNS detected the peer, that a real LAN socket carried it, or that the real Go classifier produced `direct`/`relay`. The fake *hands back* the transport string. |
| **T2 — Go real-stack (isolated)** | `transport_label_test.go`, NW002 in `pubsub_delivery_test.go`, `relay_test.go`, `watchdog_failover_test.go` | The **Go layer in isolation**: `classifyStreamTransport` correctness, a real `conn.Stat().Limited==true` over a real circuit, real relay delivery/failover. | Anything above the Go boundary — that the Dart app surfaces the right label to the user-visible `message.transport`. |
| **T3 — full-stack real (Dart→bridge→Go→relay)** | `transport_e2e_test.dart`, `group_multi_party_device_real_harness.dart` | **Liveness + dedup over the real wire**: a message really delivered, duplicates really collapsed (D1/D3/D4). | **Which transport won** — these deliberately accept the `{direct,relay,inbox}` set, and `reset_simulators.sh` sets `DISABLE_LOCAL_DISCOVERY=true`, so they *structurally cannot* prove `local`. |

**The headline E2E gap (verified):** there is **no test anywhere — fake or real —
that drives the real use-case → real bridge → real Go node and asserts a *specific*
transport**, and in particular none that proves `local`/wifi beats relay end-to-end.
T1 fakes the transport; T3 refuses to pin it. Closing this is the core of guaranteeing
correctness, and it is why several items in §5 must be BUILT before the per-doc happy
paths can be honestly claimed "covered."

**Three distinct fake networks exist — do not conflate them** (QA correction):
- `test/shared/fakes/fake_p2p_network.dart` — simple knobs only (`deliveryDelay`,
  `ackDelay`, `deliveryFails`, `inboxDisabled`, `duplicateOnDeliver`).
- `test/shared/fakes/fake_p2p_service_integration.dart` — the rich one
  (`transportMode`, `simulateTransportSwitch`, `setOnline`, `*Delay`, `*AlwaysFails`,
  `localPeers`). Budget-cut and transport-switch tests must build on THIS.
- the inline `FakeP2PNetwork`/`TestUser` in `two_user_message_exchange_test.dart`
  (`setOnline`, `drainOfflineInboxCount`) — the one `offline_inbox_roundtrip_test.dart`
  and `f2_transport_switch_recovery_test.dart` actually use, which lacks the switch/delay
  knobs. (So `f2_transport_switch_recovery_test.dart` does NOT actually simulate a
  transport switch today — it just sends twice and checks both are fast.)

## 2. The negative-control principle (mandatory for every "success" test)

A success assertion is only trustworthy if a paired control would FAIL when the
implementation doesn't actually do the intended thing. For each new test, write
its control:

| If the happy test asserts… | The negative control that prevents a false pass |
|---|---|
| "message used `local`/wifi transport" | A run with the LAN path blocked (relay reachable) must NOT report `local` — proves the label isn't hard-coded/defaulted. AND `probeRelayCallCount == 0` + `localSendCallCount == 1` so we know relay wasn't silently used. |
| "message used `direct`" | Force relay-only (NW002 clear-addrs) in a sibling test and assert the SAME scenario reports `relay` + `conn.Stat().Limited == true`. If both report `direct`, the assertion is meaningless. |
| "relay→direct upgrade happened" | A symmetric-NAT/no-direct-address control must report NO upgrade and stay `relay` with bounded attempts. Proves the upgrade detector isn't always-true. |
| "delivered via inbox when offline" | An online control must deliver live (NOT inbox), and `storeInInboxCallCount == 0`. Proves inbox isn't always firing. |
| "no duplicate on concurrent live+inbox" | A control that sends two DIFFERENT messageIds must surface TWO messages. Proves dedup isn't swallowing everything. |
| "metric counts direct vs relay correctly" | Drive a known mix (e.g. 3 relay, 1 inbox via forced conditions) and assert exact counts — not just "counter > 0". Proves the census isn't mislabeling. |
| "latency under budget X" | Assert the budget is actually *enforced* (a deliberately slow path must be cut at the budget), not just that a fast run happened to be fast. |

Guard specifically against the two false-result modes this codebase already
exhibits:
- **Default-bias:** `p2p_service_impl.dart:159` defaults missing transport to
  `'relay'`. Any transport-census test must distinguish a real `relay` from an
  *unknown-defaulted-to-relay* — assert on an explicit label, and add a case where
  the label is genuinely absent and confirm it is counted as `unknown`, not `relay`.
- **Set-acceptance:** never copy the `direct||relay||inbox` set-acceptance from the
  existing E2E tests into a test whose whole point is to prove a *specific* path.
  Set-acceptance is fine for "did it deliver at all" liveness; it is a false
  positive for "did it take the fast path."

## 3. Transport-proof primitives (how to assert the ACTUAL path)

- **Go, real connection:** `conn.Stat().Limited == true` ⇒ circuit/relay;
  `false` ⇒ direct. (`assertNW002LimitedCircuitConn`.)
- **Go, label:** the `transport` field on the `message:received` event, produced by
  `classifyStreamTransport` (`/p2p-circuit` substring ⇒ `relay`). Unit-assertable
  via `stubTransportStream`.
- **Go, relay-only forcing:** NW002 clear-addrs + `DialPeerViaRelay`.
- **Go, direct-only forcing:** empty `RelayAddresses` + `DialPeer(peer, host.Addrs())`.
- **Go, offline:** don't connect the recipient; deliver via `InboxStore`/`InboxRetrieve`.
- **Dart, exact:** `FakeP2PService.sendMessageTransport` → assert
  `message.transport == '<expected>'` + the call-count controls.
- **Dart, multi-node:** `FakeP2PNetwork.transportMode` + `setOnline` + `*AlwaysFails`.
- **Inbox has no transport *label*** in Go — it's a separate API path; assert it by
  *which API delivered* (message arrives via `InboxRetrieve`, not the live event),
  and on the Dart side by `transport == 'inbox'` + `storeInInboxCallCount`.

## 4. Happy / unhappy taxonomy (apply to every workstream)

- **Happy:** the intended path is available and wins (LAN peer reachable → `local`;
  online cross-network → `direct`/`relay`; recipient online → live delivery).
- **Unhappy — degraded:** intended path slow/partially available (stale LAN entry,
  relay reserving, partial mesh) → must fall back correctly and bounded in time.
- **Unhappy — unavailable:** intended path impossible (peer offline, relay-only,
  permission denied, symmetric NAT) → must reach the durable fallback (inbox) and
  never silently drop or hang past budget.
- **Unhappy — adversarial/edge:** duplicate messageId, crash mid-persist, relay drop
  mid-send, two paths winning simultaneously, malformed frames. Must not duplicate,
  corrupt, or wedge.

## 5. What must be BUILT (capabilities that don't exist)

1. **Real wifi-vs-relay pinning harness.** Two real app instances on the same LAN
   with mDNS enabled AND relay reachable, asserting the receiver stored
   `transport == 'local'` (or a Go FLOW event proving a LAN/direct stream). Today
   `wifi_transport_test.dart` tests the WS server in isolation and `reset_simulators.sh`
   *disables* discovery — so "same-WiFi beats relay" is unproven end-to-end.
2. **A LAN-block / relay-disable primitive** for cross-network simulation (force
   "LAN impossible, relay only" and "relay impossible, inbox only" at the app level).
3. **Hard latency-budget gates.** Convert benchmark `t.Logf` percentiles into
   `t.Fatalf` threshold assertions for the budgets each doc defines.
4. **Hole-punch observation tests** (NET-REL-02/03): assert a relay→direct upgrade is
   detected and counted; assert the no-upgrade control stays relay.
5. **Transport-census + metrics tests** (NET-REL-04): client-side counters with exact
   expected counts; relay `metrics_test.go` for the existing Prometheus surface
   (assert **deltas** on the global `promauto` counters, run non-parallel, and note
   `inbox.go:699` increments the store counter even on duplicates).
6. **Explicit `unknown` transport label** (or test that absent ≠ relay) to kill the
   default-bias false positive — and the guard must test the **receive path**
   (`p2p_service_impl.dart:159` `onMessageReceived`, which applies `?? 'relay'`), NOT
   the send fake. By the time anything downstream sees the message the default is
   already applied, so the assertion must inject an inbound `transport: null`
   `ChatMessage` through the real handler.
7. **A real bridge-boundary transport test:** feed a real `message:received` JSON with
   `transport` = `"relay"` / `"direct"` / absent through the real `GoBridgeClient`
   decode → `P2PServiceImpl.onMessageReceived` and assert the surfaced label is
   relay/direct/`unknown`. This is the only thing that closes the T1↔T2 seam (proves
   the real Go label survives the bridge into the app), short of a device test.
8. **A test-only reachability + holepunch-tracer seam in `node`** (NET-REL-02/03): a
   relay→direct *upgrade* cannot be exercised through the production node path
   (`ForceReachabilityPrivate` + no tracer option + no NAT emulation). A real upgrade
   is only demonstrable as a **component test** mirroring go-libp2p's own
   `holepunch_test.go` (inject a public addr + mock Identify on loopback). Treat
   "upgrade happens" as component/protocol-feasibility, and make the **stay-on-relay
   negative control the first-class E2E test**.
9. **A real-stack concurrent-fallback liveness proof** (NET-REL-05): a `transport_e2e`-
   style scenario that sends one low-confidence message and asserts (via Go FLOW
   events/counters) that BOTH a live stream attempt AND an `InboxStore` occurred and
   the receiver got exactly one — guards the "passes via dedup though live never
   fired" false positive that a T1 fake cannot.
10. **A discovery-enabled multi-device variant** (drop `DISABLE_LOCAL_DISCOVERY=true`)
    so the real multi-device harness can ever produce a `local` transport.

## 5b. Test execution environment (verified)

- **iOS simulators:** `reset_simulators.sh` boots up to **4** sims (`DEVICE_A..D`,
  `INTRO_E2E_DEVICE_SET=three|four`, default 3). The group multi-party real harness
  uses **3–4 real sims** (alice/bob/charlie/dana) over the real relay; some reliability
  runners use 2; `transport_e2e`/`wifi_relay_fallback` use **1 sim + a Go CLI peer**.
- **Real network:** real-relay tests exist (`relay_test.go` integration tag;
  `transport_e2e_test.dart`; `multi_relay_failover_test.dart`; the group multi-party
  harness) but are **nightly/manual/skip-if-unreachable — never blocking PR gates.**
- **CRITICAL constraint for LAN tests:** all simulator runs set
  `DISABLE_LOCAL_DISCOVERY=true` because iOS simulators **share the host's single
  Bonjour/mDNS stack**, making inter-sim LAN discovery unreliable. So the 4-sim harness
  **structurally cannot produce a `local` transport.** The NET-REL-01 LAN-pinning test
  (I3) therefore needs **two real physical devices on the same WiFi**, or a dedicated
  discovery-enabled build variant — NOT the standard simulator setup. This is why
  "discovery-enabled multi-device variant" is in the BUILD list (§5 item 10).

## 6. How to run (grounded)

- Go fast: `cd go-mknoon && make test` (excludes integration build tag).
- Go integration: `go test -tags=integration ./integration/...` (real-relay tests
  auto-skip if unreachable; honor `SKIP_RELAY_TESTS`).
- Relay server: `cd go-relay-server && go test ./...`.
- Dart host: `flutter test <path>`.
- Dart on-device: `flutter test integration_test/<file>.dart -d <device>` (iOS
  physical via `flutter drive`).
- Gates: `./scripts/run_test_gates.sh <gate>` (e.g. `transport`, `1to1`,
  `group-real-network-nightly`).
- Reliability sims: `./scripts/run_reliability_simulations.sh <scope>`.
- Multi-device real: `dart run integration_test/scripts/run_group_multi_party_device_real.dart -d <ids>`.

## References

- Go infra: `integration/local_relay_harness_test.go`, `relay_test.go`,
  `multi_relay_test.go`, `watchdog_failover_test.go`, `node/transport_label_test.go`,
  `node/pubsub_delivery_test.go` (NW002), `node/send_message_recovery_test.go`,
  `node/relay_session_test.go`, `node/benchmark_*_test.go`, `go-relay-server/*_test.go`.
- Dart infra: `send_chat_message_use_case_test.dart`, `fake_p2p_network.dart`,
  `fake_p2p_service_integration.dart`, `wifi_transport_test.dart`,
  `offline_inbox_roundtrip_test.dart`, `group_multi_party_device_real_harness.dart`,
  `scripts/run_*.dart`, `scripts/run_test_gates.sh`, `scripts/run_reliability_simulations.sh`,
  `reset_simulators.sh`.
- Cross-ref: per-doc Test Plans in NET-REL-01..05 build on these primitives.
