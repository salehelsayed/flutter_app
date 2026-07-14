# VC-00 — 1:1 Voice/Video Calls: Master Roadmap

**Code:** VC-00 · **Fidelity:** roadmap (artifact index + sequencing + decision record; no RED tests) · **Branch:** `new-orbit`
**Status:** accepted (post /tdd-review; contracts L1–L7 locked) · **Owns no production code** — this is the index/sequencer for the VC epic.

---

## Epic overview

Add **1:1 voice and video calls** (explicitly **no group calls**) to mknoon. Architecture decided
2026-07-13 from a full multi-agent audit of the transport/media/bridge/platform stack:

- **Media plane:** `flutter_webrtc` (P2P DTLS-SRTP; E2E by default). The JSON MethodChannel bridge
  cannot carry 50 pkt/s real-time frames, go-libp2p's WebRTC transport is datachannels-only, and no
  libp2p messenger has ever shipped calls — WebRTC is the media stack, libp2p stays the control
  plane.
- **Signaling plane:** the existing encrypted 1:1 envelope system (`{type, version, payload}` over
  `/mknoon/chat/1.0.0`) — the Signal/Matrix-proven pattern. New `call_*` types are a Dart-side
  dispatch change; Go is content-agnostic.
- **NAT plane:** STUN/TURN embedded into the existing `go-relay-server` (pion/turn — already an
  indirect dep, `go-relay-server/go.mod:111`), plus the **Path 3 reversal** (below) so 1:1 peers
  hold live circuits and DCUtR can upgrade them to direct QUIC.
- **Ring plane:** existing relay→FCM/APNs push bridge, extended with a high-priority call-invite
  push; Android full-screen intent + `phoneCall`/`microphone` FGS; iOS **adds the missing
  `voip`/`audio` UIBackgroundModes** + PushKit/CallKit.

This epic **supersedes** the dormant `Test-Flight-Improv/Voice-Video-Call-LiveKit-Feature/` plans
for the 1:1 scope (LiveKit SFU remains the escalation path if group calls ever enter scope; note
those docs misspell the production domain as `mknoon.xyz` — it is `mknoun.xyz`,
`go-relay-server/server_config.go:61`).

---

## DECISION RECORD — Path 3 reversal (product decision, 2026-07-13)

The July-1 "Path 3" closure (`Test-Flight-Improv/188-dcutr-1to1-forced-circuit-verification-spec.md:3,:10-11,:58-59`)
parked DCUtR dark and **declined Option B** (prod circuit-holding): 1:1 cross-network traffic is
store-and-forward by design, `warmPeer` deliberately avoids landing live `/p2p-circuit` connections
(`lib/core/services/p2p_service_impl.dart:2665-2670`), so DCUtR never has anything to upgrade.

**The user has explicitly reversed this decision for the VC epic:** 1:1 cross-network peers SHALL
hold live `/p2p-circuit` connections (Option B as defined at
`Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-CONVERGENCE-CHECKLIST.md:49`:
"flag-gated warmPeer/keepalive that dials + HOLDS a circuit to the active peer + a Go keepalive so
it isn't torn down"), and `enableDcutrUpgrade` SHALL graduate to default-ON so held circuits
upgrade to direct QUIC where punchable.

**Mechanism (adjudicated at /tdd-review, domain-verified against go-libp2p v0.39.1 source):**
flag-ON gates `libp2p.EnableHolePunching` participation while reachability **stays
`ForceReachabilityPrivate`**. The dormant FDC-12 wiring (flag-ON → `ForceReachabilityPublic`,
`feature_flags.go` doc + `node.go:393-395`) is **rejected**: forcing public kills autorelay
reservations/circuit publishing (the TC-189-41 / NO_CIRCUIT mechanism), so the node never receives
the inbound relayed connections that trigger DCUtR initiation. (Do not cite the older "puncher is
only built for private hosts" rationale — that libp2p gate was removed in v0.37.0; in v0.39.1 the
holepunch service needs only an inbound relayed conn + one observed public address.) HEAD punch
tolerance: because `EnableHolePunching` is always on today, VC-01's held circuits may legitimately
fire `holepunch:attempt` before VC-02 lands — VC-01 proofs record punch events, never fail on them;
punch-outcome assertions belong to VC-02 alone.

Consequences this roadmap owns:
- **CV-13 and CV-30 re-open** (both were closed "re-opens only with Option B",
  `FDC-CONVERGENCE-CHECKLIST.md:52,:66`). VC-01/VC-02 are their re-opening artifacts.
- The 188 guard tests and flag-polarity pins **flip by design** — each flipped pin is enumerated in
  VC-01/VC-02 RED catalogs (never silently deleted; each is re-pointed at the new invariant).
- The recorded "wasteful circuit" rationale (relay conn + dial backoff, not a measured battery
  number) is answered with: kill-switch flags, staged rollout, and a battery/data measurement gate
  inside VC-01 before flag graduation.
- Docs honesty stays: punch expectations remain literature figures (~70%±7.1% network-wide per
  punchr; ≈0% symmetric-CGNAT cellular↔cellular is a design assumption). TURN (VC-03) is therefore
  **not optional** — DCUtR reduces TURN usage, it does not replace it.

---

## Story map (each story = a self-contained working piece)

| Story | Title | Phase | Working piece when closed | Depends on |
|---|---|---|---|---|
| VC-01 | Live 1:1 circuit holding (Path 3 reversal ½) | 0 | Active 1:1 peers hold a protected, keepalive'd live circuit; measured hold-rate/duration metrics; relay limits raised + **EC2 redeploy verified** | — |
| VC-02 | DCUtR upgrade enablement (Path 3 reversal 2/2) | 0 | Held circuits upgrade to direct QUIC where punchable; punch attempt/success telemetry by network class; flag default ON behind kill-switch | VC-01 |
| VC-03 | STUN/TURN embedded in go-relay-server | 0 | Deployed relay serves STUN/TURN with ephemeral HMAC creds; live probe green against EC2; Prometheus TURN metrics | — |
| VC-04 | Call-signaling envelope types | 1 | Two peers exchange `call_*` envelopes fast-path-only with TTL, glare resolution, and forward-compat proof | — (VC-01 improves latency) |
| VC-05 | flutter_webrtc foreground 1:1 audio call | 2 | A real audio call connects device↔emulator (ICE via VC-03 creds, signaling via VC-04) with in-call UI | VC-03, VC-04 |
| VC-06 | Android ringing + background call | 3 | Killed/backgrounded Android callee rings full-screen and answers into a live call; relay call-push **EC2 redeploy verified** | VC-05 |
| VC-07 | iOS VoIP prerequisites (voip/audio background modes + CallKit/PushKit) | 3 | `UIBackgroundModes` gains `voip`+`audio` (test-locked), PushKit/CallKit wired; host-tier green; device evidence deferred-not-waived | VC-05 |
| VC-08 | Video calls | 4 | Device↔emulator video call with camera switch + speaker routing; 1:1-only enforced | VC-05 |
| VC-09 | Call reliability hardening + quality metrics | 5 | ICE restart on network switch survives; per-call quality metrics (setup ms, pair type, loss/RTT/jitter, drop cause) in flow events + relay Prometheus; "always relay" privacy toggle | VC-05 (VC-06/07 enrich) |

**MVP cut:** VC-03 → VC-04 → VC-05 (a working foreground audio call). VC-01/VC-02 run in parallel
as Phase 0 transport work; VC-06+ turn the MVP into a product.

---

## Sequencing & collision map

- **VC-01 → VC-02 are strictly sequential on the same committed tree** — both edit
  `go-mknoon/node/node.go` (host options :387-403), `go-mknoon/node/feature_flags.go`,
  `lib/core/bridge/p2p_bridge_client.dart` flag map (:76-79), and the same guard-test files
  (`feature_flags_runtime_test.go`, `reachability_default_guard_test.go`,
  `p2p_service_dcutr_flag_test.dart`, `p2p_bridge_client_test.dart` 9-key polarity pin). VC-02 on
  VC-01's committed tree, never on HEAD.
- **VC-01 also edits go-relay-server** (`limits.go:78-85` circuit limits) → ends with an EC2
  redeploy; coordinate with VC-03 (same `main.go` service wiring): land VC-03's TURN listener on
  VC-01's committed relay tree or vice-versa — one redeploy per landed story, never a combined
  untested binary.
- **VC-04 and VC-05 collide** on `lib/features/conversation/` routing and the new
  `lib/features/call/` feature dir — sequential.
- **VC-06 and VC-07 collide** on the relay push seam (where inbox deposit triggers FCM) — whichever
  lands second rebases the push-type switch; each ends with its own relay redeploy + live push
  verification.
- **Flag files are shared state:** every story that adds a feature flag touches
  `feature_flags.go` + `p2p_bridge_client.dart` + their polarity pins — expect small rebases.

---

## Locked cross-plan contracts (adjudicated at /tdd-review — plans conform, executors do not re-litigate)

| # | Contract | Locked value | Owner |
|---|---|---|---|
| L1 | Signaling offer TTL | `kCallOfferTtl = 45000 ms`; VC-06 ring timeout = min(45 s, TTL remaining from `sentAtMs`). The 30–60 s band is a design choice (Signal/Matrix precedent), not repo-derived. | VC-04 |
| L2 | Ring mechanism | ONE mechanism: caller-side relay action `call_push_request` (rate-limited per peer); relay dispatches by callee token type — FCM high-priority **data** push (Android) / APNs **voip** push (iOS PushKit token). Inbox "wake deposit" alternative rejected (`call_*` is never durable-inboxed, rule 5). | VC-06 (+VC-07 iOS leg) |
| L3 | TURN contract names | relay action `turn_credentials_get`; gomobile bridge command `turn:credentials` | VC-03 |
| L4 | Relay circuit limits | Duration 1 h / Data 64 MiB, env-tunable `RELAY_CIRCUIT_DURATION_SECONDS` / `RELAY_CIRCUIT_DATA_BYTES` | VC-01 |
| L5 | Test-family registration | No new family array this epic: headline call tests → `ONE_TO_ONE_TESTS`; heavy two-party e2e → `NIGHTLY_ONLY_TESTS`; device orchestrator `integration_test/scripts/run_call_device_real.dart` honoring `--scenario all --list-scenarios` | VC-05 |
| L6 | DCUtR mechanism | Flag gates `EnableHolePunching`; reachability stays Private (see decision record) | VC-02 |
| L7 | HEAD punch tolerance | Pre-VC-02, held circuits may fire `holepunch:attempt` — record, never fail | VC-01 |

## Non-negotiable cross-session rules (also stated inside each plan)

1. **Execution environment (user requirement):** the implementing AI agent runs the full loop
   end-to-end on a **USB-connected Android device (adb serial) + Android emulator(s)** — real
   two-party calls are proven device↔emulator (different networks where the scenario demands:
   device on cellular/hotspot, emulator on host WiFi NAT). Discover serials with `adb devices`;
   run per-device suites with `flutter test integration_test/<file> -d <serial>`; two-party
   orchestrators take `-d <serialA>,<serialB>` (see
   `integration_test/scripts/run_1to1_device_real.dart` conventions). iOS simulators/devices are
   NOT part of this rig: iOS-boundary rows use the orchestrator's **deferred-not-waived** pattern
   (prints the device recipe, exits 0 without claiming proof) and iOS *config* is still test-locked
   at host tier (VC-07).
2. **EC2 relay redeploy rule (user requirement):** any story that touches `go-relay-server/`
   (VC-01 limits, VC-03 TURN, VC-06/VC-07 push types) is **not done until the relay is rebuilt,
   redeployed to the EC2 instance (`mknoun.xyz` / 13.60.15.36, systemd service), and a live
   verification gate passes against the deployed instance** (e.g. TURN allocation probe, held
   circuit >2 min, call push received). Each plan carries the literal redeploy + probe commands and
   a rollback note (previous binary kept).
3. **Kill-switch + staged rollout:** the Path 3 reversal (VC-01) and DCUtR flip (VC-02) ship
   flag-gated (`MKNOON_*` dart-defines merged over `DefaultFeatureFlags()`), default-ON only after
   their measurement gates pass; the revert path (flag off → exact pre-epic behavior) is itself
   test-locked.
4. **Move-feature gate:** any NEW network primitive (circuit hold loop, TURN cred fetch, call
   signaling send, push registration) must honor `_allowsAccountNetworkSideEffects(...)` — the
   FDC-00 rule stands for VC.
5. **Signaling semantics:** `call_*` envelopes are **fast-path-only** (never durable-inboxed, never
   swept by `retry_unacked_messages_use_case.dart` / `PendingMessageRetrier`), carry a short TTL +
   `callId` idempotency, and account for Go's **ack-first-then-emit** ordering for non-deferred-ack
   types (`go-mknoon/node/node.go:1854-1858`) — an in-stream ack proves delivery to the node, not
   answer-side handling. Old-version forward-compat (unknown `type`) is a tested behavior, not an
   assumption.
6. **Gate hygiene:** every new `*_test.dart` must classify (`./scripts/run_test_gates.sh
   completeness-check` fails otherwise, classify_path at `scripts/run_test_gates.sh:870`); Go tests
   run only via pinned gate invocations with `GOTOOLCHAIN=go1.25.0` (Go 1.26 quic-go panic); new Go
   gates copy the synthetic-path pattern of `run_host_test_gates.sh:144-184`; when a named gate
   changes, update `scripts/run_test_gates.sh` + `test-gate-definitions.md` +
   `test-gates-reference.md` + `_current-test-map.md` together; pass counts drift — plans say
   "capture green baseline at execution start", never hardcode stale counts.
7. **00-INDEX convention:** feature subdirectories are NOT indexed in
   `Test-Flight-Improv/00-INDEX.md` (verified: zero references to the FDC or LiveKit dirs) — VC
   plans live only here, numbered VC-NN, exactly like the FDC epic.

---

## Metrics goals (the "understand areas of improvement" contract)

Every story ships its share of these; VC-09 closes the loop:

| Metric | Source | Sink |
|---|---|---|
| Circuit hold rate / duration / churn per active 1:1 session | VC-01 flow events (`flowEventLoggingEnabled`, force-on via `--dart-define=FDC_FLOW_LOG=1`, `lib/main.dart:320-330`) + Go events | flow-event log + `transport_metrics` |
| Punch attempt/success/failure by transport & network class | holepunch tracer (`go-mknoon/node/holepunch_tracer.go` emits `holepunch:attempt/success/failure`, `transport:upgraded`) | flow events; field runsheet results doc |
| TURN allocations, active relayed calls, relayed bytes | VC-03 pion/turn hooks | relay Prometheus (`go-relay-server/metrics.go` conventions, e.g. `relay_stream_duration_seconds` :257-262) |
| Call setup time (invite→connected), ICE pair type (host/srflx/relay), loss/RTT/jitter, drop cause | VC-05/VC-09 `getStats()` sampling | flow events + relay Prometheus counters |
| Ring latency (push sent→ring shown), answer latency | VC-06/VC-07 | flow events |
| Battery/data cost of held circuits (graduation gate) | VC-01 measurement runsheet | RESULTS doc in this dir |

---

## Reading order for a fresh session

1. **This file** — decision record, collisions, rules.
2. **The plan you're executing** (`VC-NN-*.md`) — its Source Of Truth, Real Scope, RED catalog,
   Acceptance Gates, Scope Guard, Dependency Impact.
3. Its cited anchors in real source (verify line numbers before editing — they drift).
4. For VC-01/VC-02: the 188 spec + FDC-CONVERGENCE-CHECKLIST rows being re-opened.

## Known gaps / risks

- `relay.DefaultLimit()` values (2 min / 128 KiB) are upstream-corroborated
  (go-libp2p v0.38.2; comment at `send_chat_message_use_case.dart:1588-1589`) but not verifiable
  in-repo in this container — VC-01 verifies the raised limits empirically against the redeployed
  relay (rule 2).
- Held circuits are connmgr-trim-eligible today (`connmgr.NewConnManager(10, 100, …)`
  `node.go:327`; **zero** `Protect()`/`TagPeer` call sites in app Go code) — VC-01 must `Protect()`
  held peers or the hold silently dies at high-water.
- iOS rig absence: VC-07 closes at host tier + deferred-not-waived device recipe; a macOS/iPhone
  session owns the CallKit device-proof.
- Battery cost of 8s-keepalive + held circuit is unmeasured — VC-01's measurement gate owns it.
