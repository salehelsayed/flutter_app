# VC-01 — Live 1:1 Circuit Holding (Path 3 reversal, part 1 of 2)  (Modification)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — grounded in `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md` (DECISION RECORD — Path 3 reversal, 2026-07-13) + the Option B definition at `Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-CONVERGENCE-CHECKLIST.md:49` (CV-10). This plan is the re-opening artifact for CV-13/CV-30 (checklist :52/:66). The reversal of the 188 Path-3 closure (`Test-Flight-Improv/188-dcutr-1to1-forced-circuit-verification-spec.md:11,:58-59`) is **sanctioned by the VC-00 decision record** — it is a product decision, not scope drift.

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | 5 grounding digests (circuits-dcutr, relay-server-ops, signaling-messaging, metrics-telemetry, harness-conventions); anchors re-verified on HEAD: `node.go:327,:387-403,:1392-1451,:1495-1505`, `limits.go:78-84`, `limits_test.go:191-208`, `feature_flags.go`, `feature_flags_runtime_test.go:10-58`, `feature_flags_merge_test.go:26-100`, `p2p_bridge_client.dart:32-91`, `p2p_bridge_client_test.dart:294-330`, `p2p_service_dcutr_flag_test.dart:65-102`, `go_bridge_client.dart:120-215`, `go_bridge_client_test.dart:130-225`, `active_peer_keepalive_use_case.dart`, `p2p_service_impl.dart:2612-2717,:5326`, `main.dart:316-335,:4080-4095`, `GoBridge.kt:125`, `GoBridge.swift:139-140`, `run_host_test_gates.sh:144-190`, `check_reliability_simulation_discovery.sh:388-405`, `run_1to1_device_real.dart:56-93` | all load-bearing anchors confirmed current; refuted digest claims NOT carried (see Root Cause) | plan authored |
| 2026-07-13 | Planner | (this file) | design: additive hold primitive + new flag; warmPeer byte-untouched → minimal pin blast radius (exactly 1 semantic pin flip) | hand to reviewer |
| 2026-07-13 | Reviewer (sufficiency) | (this file vs sufficiency-checklist) | see Reviewer Findings | arbiter |
| 2026-07-13 | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (`git status --short` snapshot — preserve pre-existing dirty tree, do NOT revert/absorb it) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + captured baseline counts) | gate green | |
| | EC2 redeploy + live probe (rule 2) | | (deploy log + >2 min hold evidence) | deployed relay verified | |
| | measurement runsheet | | (RESULTS doc) | graduation data captured | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Intent: VC-00 roadmap decision record + story map row VC-01; Option B definition `FDC-CONVERGENCE-CHECKLIST.md:49`.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose); host floors `scripts/run_host_test_gates.sh`.
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`; `./scripts/run_test_gates.sh completeness-check` (classify_path at `scripts/run_test_gates.sh:870`).
- Numbering: VC-NN inside this feature dir. **VC-00 rule 7: do NOT index this file in `Test-Flight-Improv/00-INDEX.md`** (feature subdirs are never indexed there).
- Relay ops: canonical redeploy procedure `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md:141-150` + `go-relay-server/README.md:1-39`.
- Pass counts drift: this plan states **"capture green baseline at execution start"** everywhere — never a hardcoded count (VC-00 rule 6).

## Session Classification
**implementation-ready** — every seam is verified at file:line on HEAD; the Dart/Go host contracts are fully host-testable; the device/relay legs have concrete registered runners; the relay change has a literal redeploy runbook. One deliberate iOS-boundary deferral (native `GoBridge.swift` dispatch is written and compiled, but iOS *device* evidence is deferred-not-waived — VC-00 rule 1: the rig is Android USB device + emulator).

### Non-negotiable VC-00 rules this plan touches (restated)
- **Rule 1 (execution environment):** the implementing agent runs the loop end-to-end on a USB-connected Android device + Android emulator(s); serials via `adb devices`; per-device suites `flutter test integration_test/<file> -d <serial>`; two-party orchestrator `-d <serialA>,<serialB>`. iOS device legs use the deferred-not-waived pattern. See **Execution Environment**.
- **Rule 2 (EC2 relay redeploy):** this story edits `go-relay-server/limits.go` → it is **not done** until the relay is rebuilt, redeployed to `mknoun.xyz` (13.60.15.36, systemd unit `relay-server`), and the live gate passes — the ONE committed predicate, used verbatim wherever this gate is stated: **PASS = the SAME held `/p2p-circuit` connection observed at `CIRCUIT_HOLD_ESTABLISHED` is still present at T+150 s AND zero `CIRCUIT_HOLD_LOST` and zero `CIRCUIT_HOLD_REHELD` events occur in [ESTABLISHED, T+150 s]** (the old `relay.DefaultLimit()` ≈ 2 min would kill it at ~120 s — that is the live discriminator; a kill→re-hold→present-again sequence is a FAIL of this gate, not a pass). See **EC2 Redeploy & Live Verification**.
- **Rule 3 (kill-switch + staged rollout):** the new behavior ships behind `enableLiveCircuitHold` (dart-define `MKNOON_ENABLE_LIVE_CIRCUIT_HOLD`, default **false**, merged over `DefaultFeatureFlags()`); the revert path (flag off → exact pre-epic behavior) is itself test-locked (TC-VC01-05/11/12/20). Default-ON graduation happens only after the battery/data measurement gate — **not in this story**.
- **Rule 4 (Move-feature gate):** the new network primitives `holdPeerCircuit`/`releasePeerCircuit` call `_allowsAccountNetworkSideEffects(...)` first-line, like every existing primitive (`p2p_service_impl.dart:2660` warmPeer precedent). Test-locked (TC-VC01-11).
- **Rule 6 (gate hygiene):** every new `*_test.dart` classifies (new `test/core/**` files auto-classify; `integration_test/*_proof_test.dart` auto-classifies at `run_test_gates.sh:1036-1039`); Go tests run **only** via pinned gate invocations with `GOTOOLCHAIN=go1.25.0`; the two new Go targets copy the synthetic-path pattern of `run_host_test_gates.sh:144-184`; gate changes update `scripts/run_test_gates.sh` + `test-gate-definitions.md` + `test-gates-reference.md` + `_current-test-map.md` together.

---

## Exact Problem Statement

**What's missing.** 1:1 cross-network traffic today is store-and-forward by design: `warmPeer` deliberately avoids landing a live `/p2p-circuit` connection (`lib/core/services/p2p_service_impl.dart:2665-2670` — "wasteful /p2p-circuit relay conn and accruing relay backoff"), the cross-network warm branch is a **speculative addressless dial** (`:2705-2713`), and the only code that constructs a circuit address — `dialPeerViaRelayWithTimeout` (`go-mknoon/node/node.go:1403-1451`, circuit addr built at `:1424-1436`) — is used **transiently** by `DialPeerViaRelay`/RelayProbe (`:1392-1401`) and `recoverPeerForSend` (`:1495-1505`), never held. Even if a circuit lands, it is disposable three times over: (a) **zero `Protect()`/`TagPeer` call sites exist in go-mknoon app+test code** (verified gap — only vendored `third_party/` pubsub `tag_tracer.go` has calls, pubsub-DIRECT-peers-only, irrelevant here; `connmgr.NewConnManager(10, 100, WithGracePeriod(time.Minute))` at `node.go:327` trims it above high-water 100), (b) the deployed relay bounds every circuit with `relay.DefaultLimit()` (`go-relay-server/limits.go:80` — upstream go-libp2p v0.38.2 ≈ **2 min / 128 KiB**, in-repo-unverifiable, corroborated by `send_chat_message_use_case.dart:1588-1590`), and (c) nothing re-establishes it on drop.

**Who feels it.** The VC epic: VC-02's DCUtR upgrade has **nothing to upgrade** without a held circuit (the 188 Path-3 finding), and VC-04's call signaling pays cold-dial/inbox latency on every envelope. Today's users feel it as the relay-live send leg (`send_chat_message_use_case.dart:901-903` `liveRelayEligible = _hasLiveCircuitConnection && …`) almost never being eligible cross-network.

**What must improve.** Flag-gated (`enableLiveCircuitHold`, default OFF): while the app is foregrounded with an active 1:1 conversation open and the peer is cross-network (not LAN-local), dial **and hold** a live `/p2p-circuit` connection to that peer — `Protect()`ed from connmgr trim — kept alive by the existing 8 s active-peer keepalive ping loop (`active_peer_keepalive_use_case.dart` — its pings ride the held circuit and keep it non-idle), re-established on drop with bounded backoff, released on chat close/background. Relay-side, per-circuit limits are raised to signaling-grade values so a held circuit survives (> 2 min, more than 128 KiB). Hold rate/duration/churn become observable flow events + `TransportMetrics` counters.

**What must stay unchanged → preserved-green sentinels.**
- **Flag OFF = byte-identical behavior to today** (VC-00 rule 3): no `circuit:hold` bridge command is ever sent, no `CIRCUIT_HOLD_*` flow events, `warmPeer` untouched. (TC-VC01-05/11/12/20.)
- **`enableDcutrUpgrade` stays dark** — the flip is VC-02, not here: `feature_flags_runtime_test.go:46` (`TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof`) must stay green.
- **Reachability untouched:** `node.go:393-396` `ForceReachabilityPrivate` default and its guards (`reachability_default_guard_test.go:12-21`, `integration/no_circuit_recovery_test.go:176-184`) stay green.
- **188 DCUtR observation guards stay green:** zero-punch negative control (`holepunch_negative_control_test.go:62,:118-147`), TC-188-03 peer-scoped (`holepunch_tracer_test.go:286`), TC-188-10 DirectDialEvt-never-upgrade (`:343`), TC-188-11 exactly-once (`:418`).
- **warmPeer/keepalive suites stay green:** `handle_app_resumed_warm_peer_test.dart`, `main_keepalive_wiring_test.dart`, `active_peer_keepalive_use_case_test.dart` — this plan does not edit `warmPeer` or the keepalive use case.
- **Relay finite-limits pins stay green:** `go-relay-server/limits_test.go:191-208` asserts `resources.Limit != nil` — the raise keeps limits **finite** (never nil/unlimited), so this pin survives.

---

## Root Cause (verify → refute confirmed)

Not a bug — a **recorded product decision being reversed** (VC-00 decision record). The mechanism that must change, verified on HEAD:

1. **No holder:** the only circuit dialer is transient (`node.go:1392-1451`; callers `:1396-1400` RelayProbe path and `:1495-1505` recoverPeerForSend). Nothing in Dart or Go keeps a circuit open on purpose.
2. **No protection:** `grep -rn -E 'Protect\(|TagPeer|Unprotect\(' go-mknoon --include='*.go'` → **zero call sites in app AND test code** (the only hits are vendored `third_party/go-libp2p-pubsub/tag_tracer.go:97,:103,:108`, which protect pubsub DIRECT peers only — irrelevant to 1:1 chat peers; `node_test.go:2844` only asserts `ConnManager() != nil` — its ":2873-2874 tagging happens later" comment is aspirational and false on HEAD). Any held circuit is trim-eligible above high-water 100 (`node.go:327`).
3. **Relay kills it anyway:** `limits.go:80` `resources.Limit = relay.DefaultLimit()` (≈ 2 min / 128 KiB upstream default, go.mod v0.38.2). `MaxCircuits=MaxConnectionsPerPeer=8` (`:82`), `MaxReservationsPerPeer=1` (`:83`), `MaxReservations=512` (`:43`).
4. **Nothing re-holds:** keepalive drop (`active_peer_keepalive_use_case.dart` miss-threshold 2) re-warms via `warmPeer` (`main.dart:4095`) — which by design does not land/hold a circuit.

**Refuted / do-NOT-re-introduce (from the adversarial refutation pass — never carry these):**
- ❌ "warmPeer never lands a circuit" — REFUTED: its addressless dial **can** transiently land a limited circuit conn when the peerstore has circuit addrs (`node.go` DialPeer path uses `WithAllowLimitedConn("peer-dial")`). What IS structural: warmPeer never **constructs** a circuit addr and never **holds/protects** one. Do not plan tests asserting "warmPeer produces zero circuits".
- ❌ "flag-default flips RED exactly two suites" — REFUTED (that was about the DCUtR flip; VC-02's problem). For THIS plan's flag **addition**, the verified blast radius is exactly the two pins listed in *Pinned-test flips* below.
- ❌ Doc cites `p2p_service_impl.dart:2578` / `node.go:1328/:1335` — DRIFTED; current lines are `:2612/:2665-2670` and `:1392/:1403`. Use current lines.
- ❌ "go_bridge_client.dart:140 peerPing native dispatch is still pending" — stale comment; native dispatch exists (`GoBridge.kt:125`, `GoBridge.swift:139-140`). The peer:ping chain is fully wired — the hold commands copy this landed pattern.
- ❌ (carried correction) `EnableDcutrUpgrade=ON` stops autorelay publishing circuit addresses (spec-189 NO_CIRCUIT wedge) — that hazard belongs to **VC-02**; VC-01 must NOT touch reachability, which is why the Scope Guard forbids it.

---

## Real Scope

**In scope (VC-01):**
1. **Feature flag `enableLiveCircuitHold`** (10th key, default false): Dart `defaultResilienceFeatureFlags()` (`p2p_bridge_client.dart:32`, new `bool.fromEnvironment('MKNOON_ENABLE_LIVE_CIRCUIT_HOLD', defaultValue: false)` entry following the FDC-12 pattern at `:76-79`); Go `FeatureFlags.EnableLiveCircuitHold` field + `DefaultFeatureFlags()` false + `MergeFeatureFlagsOverDefaults` case (`go-mknoon/node/feature_flags.go`).
2. **Go hold primitive** (new `go-mknoon/node/circuit_hold.go`): `HoldPeerCircuit(peerIdStr)` — flag-gated no-op when `EffectiveFlags().EnableLiveCircuitHold` is false; otherwise, if no live conn exists, dial via the **public `DialPeerViaRelay` wrapper** (`node.go:1392-1401`) — NOT `dialPeerViaRelayWithTimeout` (`node.go:1403`) directly — so every hold dial is observed by the `dialPeerViaRelayHook` seam (`node.go:99`, consulted at `:1397-1398`; this is what makes TC-VC01-05/08's dial-count spy faithful); then `h.ConnManager().Protect(pid, "live-circuit-hold")`; idempotent. `ReleasePeerCircuit(peerIdStr)` — `Unprotect(pid, "live-circuit-hold")`; never force-closes the conn. Circuit re-reservation is implicit: a drop → Dart re-hold → fresh relay dial (autorelay reservations stay owned by `node.go:410-413`).
3. **Bridge plumbing:** Go exported `CircuitHold`/`CircuitRelease` (new `go-mknoon/bridge/bridge_circuit_hold.go`, copying `bridge_ping.go:23` PeerPing shape); Dart `_cmdMap` entries `'circuit:hold' → circuitHold`, `'circuit:release' → circuitRelease` (`go_bridge_client.dart`, beside `'peer:ping'` at `:140`); native dispatch cases in `android/.../GoBridge.kt` (precedent `:125`) and `ios/Runner/GoBridge.swift` (precedent `:139-140`).
4. **Dart service primitives:** `P2PService.holdPeerCircuit(peerId)` / `releasePeerCircuit(peerId)` on `P2PServiceImpl` — first-line `_allowsAccountNetworkSideEffects('p2p_hold_circuit' / 'p2p_release_circuit')` (rule 4); flag read back from `currentState.featureFlags?['enableLiveCircuitHold'] ?? false` (the FDC-15 pattern, `p2p_service_impl.dart:5326`) → flag-off returns before any bridge call. Interface + `FakeP2PService`/fake implementers updated (compile errors enumerate them).
5. **Dart hold loop:** new `lib/core/services/live_circuit_hold_use_case.dart` (`LiveCircuitHoldUseCase`), modeled on `ActivePeerKeepAliveUseCase` (foreground-only, active-1:1-peer-scoped, never `group:`): establish hold when foreground + active cross-network 1:1 peer + flag on; re-establish on drop with bounded exponential backoff (2 s → 4 s → 8 s → … cap 60 s, reset on success); release on background/chat-close/peer-switch. Wired in `main.dart` beside `_keepAliveUseCase` (`:4080-4095`), fed by the same foreground/background + active-peer + drop signals (the existing 8 s keepalive ping traffic is what keeps the held circuit non-idle — no new Go loop).
6. **Telemetry:** flow events `CIRCUIT_HOLD_REQUESTED / CIRCUIT_HOLD_ESTABLISHED / CIRCUIT_HOLD_LOST / CIRCUIT_HOLD_REHELD {attempt, backoffMs} / CIRCUIT_HOLD_RELEASED {heldMs}` via `emitFlowEvent` (sanitizer-covered, `flow_event_emitter.dart`); `TransportMetrics` counters + bounded hold-duration samples (`recordCircuitHoldEstablished/Lost/Duration`, `transport_metrics.dart` conventions). Force-on capture via `--dart-define=FDC_FLOW_LOG=1` (`main.dart:325-335`).
7. **Relay limits (go-relay-server):** `ServerLimits` gains `CircuitDurationSeconds` (default **3600** = 1 h) and `CircuitDataBytes` (default **64 MiB**), env-overridable (`RELAY_CIRCUIT_DURATION_SECONDS`, `RELAY_CIRCUIT_DATA_BYTES`) — **epic contract lock L4: these values and env names are canonical here in VC-01; other VC plans cite them verbatim**; `relayResourcesFromServerLimits` (`limits.go:78-84`) builds `resources.Limit` from them instead of `relay.DefaultLimit()`. **Justification (signaling-grade, NOT media):** a held circuit carries 8 s keepalive pings (~45 KB/h) plus live-relay chat/signaling envelopes capped at 96 KiB each (`kLiveRelayMaxPayloadBytes`, `send_chat_message_use_case.dart:110`); 1 h duration means at most one cheap re-hold per hour of continuous chat (the relay `Duration` deadline is absolute, not idle-based — domain-verified against upstream `relay.go`: even a fully-active held circuit dies at exactly 1 h and re-holds via TC-VC01-13's loop); 64 MiB ≈ 680 max-size envelopes per circuit — generous for signaling, still **finite** so a media/streaming abuse dies (and the `limits_test.go:204-206` finite-Limit pin stays green). `MaxCircuits=8/peer` and `MaxReservationsPerPeer=1` are **kept** (one active 1:1 hold per device needs 1-2 circuits; 8 is ample headroom). Version const `main.go:25` bumped `1.5.1 → 1.6.0` so `relay-server version` proves the deploy.
8. **EC2 redeploy + live verification** of (7) per rule 2.
9. **Measurement runsheet** (battery/data, the flag-graduation gate) + RESULTS doc in this dir.

**Out of scope → owning story (Scope Guard below):** `enableDcutrUpgrade` default flip and any reachability change (**VC-02**); STUN/TURN (**VC-03**); `call_*` signaling envelopes (**VC-04**); flag default-ON graduation (post-measurement follow-up); relay Prometheus per-circuit-hold metrics (**VC-09**); iOS device evidence (deferred-not-waived; macOS/iPhone session).

---

## Files To Inspect Next

**Production (entry/use-case, models, helpers):**
- `lib/core/bridge/p2p_bridge_client.dart:32-91` — flag map (edit: 10th key).
- `lib/core/bridge/go_bridge_client.dart:120-215` — `_cmdMap` (edit: 2 commands).
- `lib/core/services/p2p_service.dart` + `lib/core/services/p2p_service_impl.dart` — new primitives; gate precedent `:2660`; flag-readback precedent `:5326`.
- `lib/core/services/live_circuit_hold_use_case.dart` — NEW; model on `active_peer_keepalive_use_case.dart`.
- `lib/main.dart:4080-4095` — wiring beside `_keepAliveUseCase`; `:325-335` FDC_FLOW_LOG force-on.
- `lib/core/debug/transport_metrics.dart` — new counters (`recordHolePunch*` pattern `:218-227`).
- `go-mknoon/node/feature_flags.go` (field + default + merge case), `go-mknoon/node/circuit_hold.go` (NEW), `go-mknoon/node/node.go:327,:1392-1451` (read-only context: connmgr + circuit dialer to reuse).
- `go-mknoon/bridge/bridge_circuit_hold.go` (NEW; `bridge_ping.go` shape), `go-mknoon/bridge/bridge.go:560,:582-584` (flag decode seam — read-only).
- `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt` (+2 cases), `ios/Runner/GoBridge.swift` (+2 cases).
- `go-relay-server/limits.go` (+2 ServerLimits fields, env plumbing, `relayResourcesFromServerLimits`), `go-relay-server/main.go:25` (version bump).

**Direct tests + integration tests:** listed per-row in the RED Test Catalog. Harness/registration files: `scripts/run_test_gates.sh` (ONE_TO_ONE_TESTS array `:21`), `scripts/run_host_test_gates.sh:144-184` (synthetic Go paths), `scripts/check_reliability_simulation_discovery.sh:388-405` (classify_path case), `integration_test/scripts/run_1to1_device_real.dart:56` (scenario table).

**Dependency-only context (do NOT edit):** `active_peer_keepalive_use_case.dart` (keepalive stays as-is), `send_chat_message_use_case.dart:901-903,:1563-1568` (liveRelayEligible — emergent beneficiary), `node.go:387-403` (reachability — forbidden), `holepunch_tracer.go` (VC-02's surface).

---

## Existing Tests Covering This Area

### Pinned-test flips (enumerated per VC-00 decision record — each re-pointed, never silently deleted)

Full sweep of the circuits-dcutr digest's pin list against this plan's actual edits. Because VC-01 leaves `warmPeer`, the keepalive use case, reachability, and the DCUtR default **byte-untouched**, the RED blast radius is exactly **two** pins:

| Pinned test | Pins today | VC-01 effect | Re-pointed at |
|---|---|---|---|
| `test/core/bridge/p2p_bridge_client_test.dart::'pins exactly the 9 canonical keys with intended polarity'` (`:294`, `hasLength(9)` at `:314`) | exact 9-key flag map + polarity | **REDs** (10th key added) | TC-VC01-01: "pins exactly the **10** canonical keys" with `enableLiveCircuitHold: false` in the independent literal |
| `go-mknoon/node/feature_flags_merge_test.go::TestMergeFeatureFlags_EveryStructFieldIsMergeable` (`:61`, reflective) | every `FeatureFlags` field has a merge case | **REDs transiently** the moment the Go field lands without its merge case | itself — green again once the `"enableLiveCircuitHold"` case is added (this is the structural guard working as designed, TC-VC01-04) |

**Explicitly NOT flipped (verified mechanism per pin):** `feature_flags_runtime_test.go:10` (`DefaultsRemainBackwardCompatible` — per-field asserts, additive field invisible) and `:46` (`FdcTransportFlagsShipDark…` — DCUtR polarity untouched); `dcutr_upgrade_flag_test.go` (:15/:39/:55 — explicit-flag function table); `reachability_default_guard_test.go:12` + `integration/no_circuit_recovery_test.go:176` (reachability untouched — Scope Guard); `feature_flags_merge_test.go:26` (omitted-key semantics unchanged); `holepunch_negative_control_test.go:62` and `holepunch_tracer_test.go:286/:343/:418` (TC-188 guards — no tracer/reachability edit); `test/core/services/p2p_service_dcutr_flag_test.dart:65-102` (containsKey-based, additive-safe); `test/core/bridge/go_bridge_client_test.dart` cmd-map pins (`:130-225` — iterate their own literal maps; new commands are additive); `test/core/lifecycle/handle_app_resumed_warm_peer_test.dart`, `test/core/lifecycle/main_keepalive_wiring_test.dart`, `test/core/services/active_peer_keepalive_use_case_test.dart`, `test/core/services/p2p_service_transport_upgrade_test.dart` (warm/keepalive/upgrade surfaces untouched). Spec-doc invariant TC-188-12 "prod-unchanged" is overturned **by the VC-00 decision record**, not by this plan silently.

### Coverage gaps this plan fills
- No test anywhere exercises `Protect()`/`Unprotect` (zero call sites — verified gap) → TC-VC01-06/07.
- No test holds or re-establishes a circuit → TC-VC01-06/08/13/19.
- No relay test asserts per-circuit `Limit` values (only non-nil, `limits_test.go:204-206`) → TC-VC01-17/18.
- No flow event observes circuit-hold lifecycle → TC-VC01-12/14/15/16.

**Already in curated family arrays?** `p2p_bridge_client_test.dart`, `go_bridge_client_test.dart`, `p2p_service_impl_test.dart` are in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:21`). New headline files must be **manually added** (registration column in the matrix).

---

## RED Test Catalog  (each test is authored RED before ITS slice's production code — INV-RED-FIRST, per-slice cadence per Step 2)

> Convention: tests for brand-new APIs are RED on HEAD as **compile failures** (symbol does not exist) — the documented, expected RED reason. Behavioral REDs are stated per test. Go tests run ONLY via the pinned invocations in Acceptance Gates (`GOTOOLCHAIN=go1.25.0`).

1. **TC-VC01-01** `test/core/bridge/p2p_bridge_client_test.dart::'pins exactly the 10 canonical keys with intended polarity'` (re-point of the 9-key pin at `:294`)
   - Tier: unit/application. Shape: independent 10-entry literal incl. `'enableLiveCircuitHold': false`; `hasLength(10)`; per-key polarity loop.
   - RED on HEAD because: `defaultResilienceFeatureFlags()` returns 9 keys; `hasLength(10)` and the key lookup fail.
   - GREEN asserts: exact 10-key set; `enableLiveCircuitHold == false` (load-bearing Dart default, rule 3).
   - Mutation re-red: remove the new map entry → set/length mismatch; flip default to true → polarity loop REDs.
2. **TC-VC01-02** `test/core/services/p2p_service_circuit_hold_flag_test.dart::'VC-01: enableLiveCircuitHold defaults to false in the node:start featureFlags map'` (+ `'…defaultResilienceFeatureFlags includes enableLiveCircuitHold:false'`) — mirrors `p2p_service_dcutr_flag_test.dart:65-102` (payload-capturing bridge).
   - Tier: unit/application. RED on HEAD: key absent from captured `node:start` payload.
   - GREEN: `flags.containsKey('enableLiveCircuitHold')` && value false. Mutation: drop the map entry → RED.
3. **TC-VC01-03** `go-mknoon/node/feature_flags_runtime_test.go::TestFeatureFlags_LiveCircuitHoldShipsDark`
   - Tier: Go host (pinned invocation `-run 'FeatureFlag'` — existing synthetic path `GO_NODE_FEATUREFLAGS_RUN='FeatureFlag'` sweeps it, `run_host_test_gates.sh:162`).
   - RED on HEAD: `FeatureFlags` has no `EnableLiveCircuitHold` field (compile). GREEN: `DefaultFeatureFlags().EnableLiveCircuitHold == false`. Mutation: flip Go default true → RED.
4. **TC-VC01-04** `go-mknoon/node/feature_flags_merge_test.go::TestFeatureFlags_LiveCircuitHold_MergePresence` (+ the existing reflective `TestMergeFeatureFlags_EveryStructFieldIsMergeable:61` as the structural guard)
   - Tier: Go host (same `-run 'FeatureFlag'` invocation). RED on HEAD: compile (field absent).
   - GREEN: omitted key keeps false; present `true` overrides; present explicit `false` stays false. Mutation: delete the merge `case "enableLiveCircuitHold"` → the reflective test REDs.
5. **TC-VC01-05** `go-mknoon/node/circuit_hold_test.go::TestCircuitHold_FlagOff_NoDialNoProtect`
   - Tier: Go host (NEW synthetic path, see registration). Shape: node with default flags (hold flag false); call `HoldPeerCircuit`.
   - RED on HEAD: compile (func absent). GREEN: returns a flag-off sentinel error/no-op, **zero** dial attempts (hook `dialPeerViaRelayHook`, `node.go:99`, consulted at `:1397-1398` — faithful only because `HoldPeerCircuit` routes through `DialPeerViaRelay`, Real Scope item 2) **and** `len(h.Network().ConnsToPeer(pid)) == 0` (connection-level belt-and-braces no call-path choice can bypass), `IsProtected == false`. Mutation: remove the flag gate in `HoldPeerCircuit` → dial hook fires → RED. **This is the Go half of the rule-3 revert lock.**
6. **TC-VC01-06** `go-mknoon/node/circuit_hold_test.go::TestCircuitHold_DialsCircuitAndProtectsPeer`
   - Tier: Go host. Shape: two in-process hosts joined through a local relay (reuse the relay-pair harness pattern of `holepunch_negative_control_test.go`), flag ON via `FeatureFlags{EnableLiveCircuitHold: true}`.
   - RED on HEAD: compile. GREEN: a live conn to the peer exists whose multiaddr contains `/p2p-circuit`; `h.ConnManager().IsProtected(pid, "live-circuit-hold") == true`.
   - Mutation re-red: **delete the `Protect(...)` call** (revert the single protection line) → `IsProtected` false → RED. (Closes the zero-Protect-call-sites gap.)
7. **TC-VC01-07** `go-mknoon/node/circuit_hold_test.go::TestCircuitRelease_UnprotectsWithoutClosingConn`
   - Tier: Go host. RED on HEAD: compile. GREEN: after Hold→Release, `IsProtected == false` **and** the connection is still open (release is destructive to protection only — it never `ClosePeer`s an in-use conn). Mutation: add a `ClosePeer` to release → conn-open assert REDs; remove `Unprotect` → IsProtected assert REDs.
8. **TC-VC01-08** `go-mknoon/node/circuit_hold_test.go::TestCircuitHold_IdempotentWhenAlreadyHeld`
   - Tier: Go host. GREEN: second `HoldPeerCircuit` returns nil, exactly one extra dial max (no dial when conn live; dial count observed via `dialPeerViaRelayHook` — valid because hold dials route through `DialPeerViaRelay`, Real Scope item 2), still protected. RED on HEAD: compile. Mutation: make hold unconditionally re-dial → dial-count assert REDs.
9. **TC-VC01-09** `go-mknoon/bridge/circuit_hold_bridge_test.go::TestCircuitHoldBridge_ParsesParamsAndRoutes` (+ `TestCircuitHoldBridge_FlagOffReturnsOkFalse`)
   - Tier: Go host (NEW bridge synthetic path). RED on HEAD: compile (exports absent). GREEN: `CircuitHold(`{"peerId":…}`)`/`CircuitRelease` decode params, route to the node methods, return the standard `{ok:…}` JSON envelope; malformed JSON → `ok:false`. Mutation: break param key → RED.
10. **TC-VC01-10** `test/core/bridge/go_bridge_client_test.dart::'circuit:hold calls circuitHold with payload JSON'` (+ `'circuit:release calls circuitRelease with payload JSON'`) — added to the `payloadCmds` pin map (`:163` block).
    - Tier: unit. RED on HEAD: `_cmdMap` (`go_bridge_client.dart:97`) has no `circuit:hold` → `decoded['ok']` false with `errorCode: 'UNKNOWN_COMMAND'` (`go_bridge_client.dart:902`; the envelope is pinned by the existing `go_bridge_client_test.dart:520` unknown-command test — MethodChannel never called). GREEN: routes to method `circuitHold` with JSON payload. Mutation: remove the `_cmdMap` entry → RED.
11. **TC-VC01-11** `test/core/services/p2p_service_circuit_hold_test.dart` — three tests:
    (a) `'flag-off holdPeerCircuit sends NO bridge command'` — bridge-call-capturing fake; `currentState.featureFlags` without/false key. RED on HEAD: compile (method absent). GREEN: zero bridge sends. Mutation: remove the flag-readback guard → bridge call fires → RED. **(Dart half of the rule-3 revert lock.)**
    (b) `'flag-on holdPeerCircuit sends circuit:hold with the peerId'` — GREEN: exactly one `circuit:hold` with `{peerId}`.
    (c) `'denied account gate blocks holdPeerCircuit before any bridge call'` — gate fake denies `p2p_hold_circuit`. GREEN: zero bridge sends. Mutation: **delete the first-line `_allowsAccountNetworkSideEffects` call** → RED. (VC-00 rule 4 lock; same trio for `releasePeerCircuit`/`p2p_release_circuit` in the same file.)
12. **TC-VC01-12** `test/core/services/live_circuit_hold_use_case_test.dart` — core loop:
    - `'flag-on foreground active cross-network 1:1 peer → exactly one hold request'` (RED: compile);
    - `'LAN-local active peer is never held'` (isLocalPeer → zero holds);
    - `'group: active peer is never held'` (sibling-surface parity with keepalive);
    - `'flag-off → zero holds, zero flow events'` (revert lock at the loop tier).
    - Mutations: drop the `isLocalPeer` guard → local test REDs; drop the flag guard → flag-off test REDs; hold on every tick → "exactly one" REDs.
13. **TC-VC01-13** `test/core/services/live_circuit_hold_use_case_test.dart::'drop → re-hold with bounded exponential backoff, cap, and reset-on-success'`
    - Tier: unit (fake async, manual ticks). RED on HEAD: compile. GREEN: after a drop signal, re-hold attempts at 2/4/8… s, capped at 60 s, `CIRCUIT_HOLD_REHELD {attempt, backoffMs}` emitted per attempt; a successful re-hold **re-requests protection** (the hold callback fires again — invariant re-verification, not just a latch flip) and resets the backoff. Mutation: remove the cap → cap assert REDs; skip the re-hold callback on success path → re-verify assert REDs.
14. **TC-VC01-14** `test/core/services/live_circuit_hold_use_case_test.dart::'background/chat-close releases the hold with CIRCUIT_HOLD_RELEASED{heldMs} and re-arms on reopen'`
    - Tier: unit. RED on HEAD: compile. GREEN: `onBackgrounded()`/active-peer-cleared → exactly one release callback + `CIRCUIT_HOLD_RELEASED` with `heldMs > 0`; a subsequent `onForegrounded()` with the chat still active **re-establishes** (derived hold state is reconstructed, not assumed — lifecycle durability). Mutation: drop the release-on-background → RED; drop re-arm → reopen assert REDs.
15. **TC-VC01-15** `test/core/services/live_circuit_hold_use_case_test.dart::'hold path emits CIRCUIT_HOLD_ESTABLISHED and NOT P2P_SERVICE_WARM_PEER_DIAL'` (distinct-event discriminator)
    - Tier: unit, `debugSetFlowEventSink` capture. RED on HEAD: compile / event never emitted. GREEN: captured events contain `CIRCUIT_HOLD_ESTABLISHED` AND do **not** contain `P2P_SERVICE_WARM_PEER_DIAL` (`p2p_service_impl.dart:2699` event name) — proves the hold is its own primitive, not a re-labeled speculative warm dial. Mutation: implement hold by delegating to `warmPeer` → discriminator REDs.
16. **TC-VC01-16** `test/core/debug/transport_metrics_circuit_hold_test.dart` — `'records hold established/lost counts and bounded duration samples'`, `'reset() zeroes circuit-hold counters'` (mirrors `transport_metrics_holepunch_test.dart`).
    - Tier: unit. RED on HEAD: compile (recorders absent). GREEN: counters + median/p95 duration surface in `baselineReport()`. Mutation: stop feeding `recordCircuitHoldLost` from the use case's lost path → count assert REDs (wired-feed test included).
17. **TC-VC01-17** `go-relay-server/limits_test.go::TestRelayCircuitLimits_SignalingGradeDefaults`
    - Tier: Go host (relay). RED on HEAD: compile (`CircuitDurationSeconds` field absent) — and semantically HEAD sets `Limit = relay.DefaultLimit()` (≈2 min/128 KiB). GREEN: `relayResourcesFromServerLimits(DefaultServerLimits()).Limit.Duration == time.Hour` && `.Data == 64<<20` && `Limit != nil` (finite — preserves the `:204-206` pin). Mutation: revert `limits.go` to `relay.DefaultLimit()` → RED.
18. **TC-VC01-18** `go-relay-server/limits_test.go::TestRelayCircuitLimits_EnvOverride`
    - Tier: Go host (relay). RED on HEAD: compile. GREEN: `RELAY_CIRCUIT_DURATION_SECONDS=120` / `RELAY_CIRCUIT_DATA_BYTES=131072` round-trip through `loadServerLimitsFromEnv()` (t.Setenv), invalid/empty falls back to defaults (`envIntOrDefault` semantics). Mutation: drop the env plumbing → RED.
19. **TC-VC01-19** `integration_test/live_circuit_hold_proof_test.dart::'VC-01 D1: held circuit to the peer survives >2 minutes through the DEPLOYED relay'` — `@Tags(['device'])` **PROD-CRITICAL** (the single path proving the wire leg end-to-end; do NOT treat host coverage as sufficient on its own).
    - Tier: device-proof (USB Android device ↔ Android emulator, cross-network, real Go bridge, deployed `mknoun.xyz` relay). Build with `--dart-define=MKNOON_ENABLE_LIVE_CIRCUIT_HOLD=true --dart-define=FDC_FLOW_LOG=1`.
    - RED on HEAD (two independent reasons): (a) app: no hold machinery → no `CIRCUIT_HOLD_ESTABLISHED`; (b) relay: even a manually-landed circuit dies at ≈120 s under the deployed `relay.DefaultLimit()` — **the >2 min survival is the live discriminator that only the redeployed relay + hold code together can turn green.**
    - GREEN asserts (D1, the rule-2 predicate verbatim): `CIRCUIT_HOLD_ESTABLISHED` observed; **PASS = the SAME held `/p2p-circuit` connection observed at `CIRCUIT_HOLD_ESTABLISHED` is still present at T+150 s AND zero `CIRCUIT_HOLD_LOST` and zero `CIRCUIT_HOLD_REHELD` events occur in [ESTABLISHED, T+150 s]**; a message sent at T+140 s commits on the relay-live leg. (A re-held circuit inside the window is a FAIL — it is exactly what the OLD 2-min relay would produce.)
    - **D2 recovery leg (runs only AFTER D1 passes — INV-4 on the real path):** mid-hold, force a genuine drop (`ssh -i se.pem ubuntu@mknoun.xyz 'sudo systemctl restart relay-server'`, or a 5 s airplane-mode toggle on the USB device), then assert the logcat sequence `CIRCUIT_HOLD_LOST` → `CIRCUIT_HOLD_REHELD` → a live `/p2p-circuit` connection to the peer present again within 60 s, and a message sent post-recovery commits. This is the real-drop coverage the host-tier fakes (TC-VC01-13) structurally cannot provide.
    - Repeat/flake policy (pre-committed): closure requires **2 consecutive D1 passes**; a single failure is re-run once — two failures = product/deploy FAIL, investigate before touching code.
    - HEAD punch tolerance (epic lock L7): `EnableHolePunching` is always on on HEAD, so a held circuit plus observed public addresses can legitimately fire `holepunch:attempt` before VC-02 lands — the proof **tolerates and RECORDS** punch events (into the RESULTS doc), never fails on them; punch-outcome assertions belong to VC-02 alone.
    - Mutation re-red: run the same test against a relay still on `1.5.1` (rollback binary) → circuit dies ~120 s → RED. Run flag-off build → no `CIRCUIT_HOLD_*` events → RED (see TC-VC01-20 for the flag-off assertion as a pass).
20. **TC-VC01-20** flag-off byte-identical device sweep (runsheet step R-6, not a new file): flag-OFF build, 10-minute foreground chat session, `adb logcat` grep — **zero** `CIRCUIT_HOLD_` lines and **zero** `circuit:hold` bridge commands. Host-tier locks are TC-VC01-05/11a/12(flag-off); this sweep is the device-tier confirmation. RED-equivalent on a broken revert path: any `CIRCUIT_HOLD_` line appears. L7 note: `holepunch:*` events in the same logs are **tolerated and recorded, never a failure** — on HEAD `EnableHolePunching` is always on and punch attempts can fire independently of this flag; only `CIRCUIT_HOLD_`/`circuit:hold` lines are this sweep's pass/fail signal.
21. **TC-VC01-21** `test/core/lifecycle/main_circuit_hold_wiring_test.dart` — mirrors `main_keepalive_wiring_test.dart`: the app shell arms the hold loop on foreground, releases on background, and feeds it the same active-peer + drop signals as the keepalive.
    - Tier: unit/lifecycle. RED on HEAD: compile (use case absent from wiring). GREEN: wiring asserts above. Mutation: revert the `main.dart` wiring block → RED.

---

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-VC01-01 | flag-map polarity (10 keys) | unit | `test/core/bridge/p2p_bridge_client_test.dart::pins exactly the 10 canonical keys…` | map has 9 keys | drop new entry / flip default | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` (auto for host-all glob) |
| TC-VC01-02 | node:start payload default-off | unit | `test/core/services/p2p_service_circuit_hold_flag_test.dart::VC-01…` (2 tests) | key absent from payload | drop map entry | `./scripts/run_test_gates.sh 1to1` + `run_host_test_gates.sh core-host-all` | AUTO (`test/core/**` glob) **+ add path to `ONE_TO_ONE_TESTS` array** (`run_test_gates.sh:21`) |
| TC-VC01-03 | Go default dark | Go host | `go-mknoon/node/feature_flags_runtime_test.go::TestFeatureFlags_LiveCircuitHoldShipsDark` | compile: field absent | flip Go default true | `./scripts/run_host_test_gates.sh host-all` (pinned `go test ./node -run 'FeatureFlag'`, GOTOOLCHAIN=go1.25.0) | existing synthetic path `GO_NODE_FEATUREFLAGS_RUN='FeatureFlag'` matches by name — verify it lists at execution |
| TC-VC01-04 | Go merge presence | Go host | `go-mknoon/node/feature_flags_merge_test.go::TestFeatureFlags_LiveCircuitHold_MergePresence` (+ reflective `:61`) | compile: field absent | delete merge case → reflective test REDs | same pinned `-run 'FeatureFlag'` invocation | existing synthetic path (regex `FeatureFlag` matches) |
| TC-VC01-05 | Go flag-off no-op (revert lock) | Go host | `go-mknoon/node/circuit_hold_test.go::TestCircuitHold_FlagOff_NoDialNoProtect` | compile: func absent | remove flag gate | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CircuitHold\|CircuitRelease' -count=1)` via host-all | **NEW synthetic path** `GO_NODE_CIRCUIT_HOLD_TEST` + `RUN='CircuitHold\|CircuitRelease'` in `run_host_test_gates.sh` (copy `:144-184` pattern: matcher + print + run branches) |
| TC-VC01-06 | hold dials + Protects | Go host | `…circuit_hold_test.go::TestCircuitHold_DialsCircuitAndProtectsPeer` | compile | delete `Protect(...)` line | same NEW pinned invocation | same NEW synthetic path |
| TC-VC01-07 | release unprotects, never closes | Go host | `…circuit_hold_test.go::TestCircuitRelease_UnprotectsWithoutClosingConn` | compile | remove `Unprotect` / add ClosePeer | same | same |
| TC-VC01-08 | hold idempotent | Go host | `…circuit_hold_test.go::TestCircuitHold_IdempotentWhenAlreadyHeld` | compile | unconditional re-dial | same | same |
| TC-VC01-09 | bridge exports route | Go host | `go-mknoon/bridge/circuit_hold_bridge_test.go::TestCircuitHoldBridge_*` | compile: exports absent | break param key | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'CircuitHoldBridge' -count=1)` via host-all | **NEW synthetic path** `GO_BRIDGE_CIRCUIT_HOLD_TEST` + `RUN='CircuitHoldBridge'` (own path — separate package, like `GO_BRIDGE_FEATUREFLAGS`) |
| TC-VC01-10 | Dart cmd routing | unit | `test/core/bridge/go_bridge_client_test.dart::circuit:hold calls circuitHold…` (+release) | UNKNOWN_COMMAND: cmd unknown | remove `_cmdMap` entry | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` |
| TC-VC01-11 | service primitives: move gate + flag-off + flag-on (×hold/release) | unit | `test/core/services/p2p_service_circuit_hold_test.dart` (6 tests) | compile: methods absent | delete gate call / flag guard | `run_host_test_gates.sh core-host-all` | AUTO (`test/core/services/` glob + classify_path core branch) |
| TC-VC01-12 | hold loop scoping (cross-network only; never local/group/flag-off) | unit | `test/core/services/live_circuit_hold_use_case_test.dart` (4 tests) | compile: class absent | drop isLocal/flag guard | `./scripts/run_test_gates.sh 1to1` + `core-host-all` | AUTO glob **+ add path to `ONE_TO_ONE_TESTS` array** (headline 1:1 transport case) |
| TC-VC01-13 | re-hold bounded backoff + invariant re-verify | unit | `…live_circuit_hold_use_case_test.dart::drop → re-hold…` | compile | remove cap / skip re-protect | same as TC-VC01-12 | same file (already registered above) |
| TC-VC01-14 | release-on-bg/close + heldMs + reopen re-arm (lifecycle durability) | unit | `…live_circuit_hold_use_case_test.dart::background/chat-close releases…` | compile | drop release / drop re-arm | same | same file |
| TC-VC01-15 | discriminator: hold ≠ warm dial | unit | `…live_circuit_hold_use_case_test.dart::…ESTABLISHED and NOT P2P_SERVICE_WARM_PEER_DIAL` | event never emitted | delegate hold to warmPeer | same | same file |
| TC-VC01-16 | metrics counters + durations | unit | `test/core/debug/transport_metrics_circuit_hold_test.dart` (2 tests) | compile: recorders absent | unwire lost-path feed | `run_host_test_gates.sh core-host-all` | AUTO (`test/core/debug/` glob) |
| TC-VC01-17 | relay signaling-grade limits | Go host (relay) | `go-relay-server/limits_test.go::TestRelayCircuitLimits_SignalingGradeDefaults` | compile + HEAD uses DefaultLimit | revert to `relay.DefaultLimit()` | `./scripts/run_test_gates.sh all` (runs `run_relay_all_go_gate` `:865-868`, GOTOOLCHAIN=go1.25.0) | AUTO within relay module (`go test ./...` sweeps the file; gate already wired at `run_test_gates.sh:1156`) |
| TC-VC01-18 | relay env override | Go host (relay) | `…limits_test.go::TestRelayCircuitLimits_EnvOverride` | compile | drop env plumbing | same relay gate | AUTO (same) |
| TC-VC01-19 | **PROD-CRITICAL** held circuit survives (D1: SAME conn at T+150 s, zero LOST/REHELD in window) + real drop→re-hold recovery (D2) via DEPLOYED relay | device-proof | `integration_test/live_circuit_hold_proof_test.dart::VC-01 D1…` | no hold machinery + deployed 2-min limit kills circuit | run vs rolled-back relay 1.5.1 / flag-off build | `flutter test integration_test/live_circuit_hold_proof_test.dart -d <serial> --dart-define=MKNOON_ENABLE_LIVE_CIRCUIT_HOLD=true --dart-define=FDC_FLOW_LOG=1` + orchestrator | `@Tags(['device'])`; run_test_gates classify_path **auto** (`*_proof_test.dart` branch `:1036-1039`); **NEW classify_path case** in `check_reliability_simulation_discovery.sh` (`record "1to1" … "test"`, syntax `:388-405`); **NEW orchestrator `--scenario vc01_live_circuit_hold_2min`** in `run_1to1_device_real.dart` (`_scenarios:56`, mode `device+relay`) |
| TC-VC01-20 | flag-off byte-identical (device sweep) | device (runsheet) | Measurement runsheet step R-6 (zero `CIRCUIT_HOLD_` logcat lines) | n/a — pass-condition sweep; host locks are TC-VC01-05/11/12 | re-enable hold under flag-off → lines appear | runsheet R-6 command (below) | runsheet step (manual; host locks carry the gate registration) |
| TC-VC01-21 | app-shell wiring armed fg / released bg / drop-fed | unit/lifecycle | `test/core/lifecycle/main_circuit_hold_wiring_test.dart` | compile: wiring absent | revert main.dart wiring block | `run_host_test_gates.sh core-host-all` | AUTO (`test/core/lifecycle/` glob) |
| PRESERVE-P1 | DCUtR stays dark + zero-punch | Go host | `feature_flags_runtime_test.go:46` + `holepunch_negative_control_test.go:62` | n/a (green sentinel) | n/a — must never red | pinned `-run 'FeatureFlag'` + `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestHolePunchNegativeControl' -count=1)` | existing (host-all synthetic + explicit sentinel run) |
| PRESERVE-P2 | 188 guards (TC-188-03/10/11) | Go host | `holepunch_tracer_test.go:286/:343/:418` | n/a (green) | n/a | explicit sentinel run (Acceptance Gates) | existing |
| PRESERVE-P3 | reachability guards | Go host | `reachability_default_guard_test.go:12` + `integration/no_circuit_recovery_test.go:176` | n/a (green) | n/a | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./integration -run 'TestDefaultFlagsKeepPrivateReachability' -count=1)` | existing |
| PRESERVE-P4 | warm/keepalive suites untouched | unit | `handle_app_resumed_warm_peer_test.dart`, `main_keepalive_wiring_test.dart`, `active_peer_keepalive_use_case_test.dart` | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` + `core-host-all` | existing |
| PRESERVE-P5 | dcutr flag Dart pins additive-safe | unit | `p2p_service_dcutr_flag_test.dart:65-102` | n/a (green) | n/a | `core-host-all` | existing |
| PRESERVE-P6 | relay finite-limit + reservation pins | Go host (relay) | `limits_test.go:191-235` (`Limit != nil`, MaxCircuits, reservations) | n/a (green) | n/a | relay gate (`all`) | existing |
| REGRESSION floor | no 1:1/groups/feed/baseline/transport breakage | gate | full suites | n/a | n/a | `./scripts/run_test_gates.sh baseline` · `feed` · `groups` · `transport` · `run_host_test_gates.sh feature-host-all` | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the hold is in-memory derived state (protection flag in Go connmgr + loop state in Dart). Reopen/re-foreground must **reconstruct** it, not assume it: TC-VC01-14 (background→foreground re-arm) and TC-VC01-13 (post-drop re-hold re-requests protection, not just a latch flip). Process-restart: the loop re-derives entirely from the active-conversation signal on next open — no persisted rows exist to get stale (nothing is written to SQLCipher; **no migration**).
- **Sibling-surface consistency:** the keepalive's scoping rules are mirrored exactly — foreground-only, active-1:1-peer-only, **never `group:` peers** (TC-VC01-12), never LAN-local (TC-VC01-12). The move-feature gate applies to BOTH new primitives, hold and release (TC-VC01-11 covers both tokens). Deliberate asymmetry vs `warmPeer` (hold is circuit-constructing, warm is not) is test-locked by the TC-VC01-15 discriminator.
- **Destructive-action side-effects:** `ReleasePeerCircuit` asserts **what is removed** (the protection tag) and **what is preserved** (the open connection — never `ClosePeer`d) in TC-VC01-07; the Dart release path asserts exactly one release + `heldMs` accounting (TC-VC01-14). No files/DB rows are involved.
- **Invariant re-verification under new transitions:** the new drop→re-hold transition re-verifies the full held-state invariant set (live circuit conn + `IsProtected` + flow event) rather than only flipping a "held" flag — TC-VC01-13 (Dart loop re-invokes the hold primitive; the primitive itself re-dials + re-protects per TC-VC01-06/08). The connmgr-trim invariant after re-hold is re-checked by TC-VC01-08 (still protected after idempotent re-hold).

---

## Invariants (locked by tests)

- **INV-1 (revert path / rule 3):** flag OFF ⇒ zero hold dials, zero `Protect` calls, zero `circuit:hold` bridge commands, zero `CIRCUIT_HOLD_*` flow events — byte-identical to today. → TC-VC01-05, 11a, 12(flag-off), 20.
- **INV-2 (protection):** a held peer is `Protect(pid,"live-circuit-hold")`ed for the entire hold; release unprotects without closing. → TC-VC01-06/07/08.
- **INV-3 (scoping):** holds are foreground-only, active-1:1-peer-only, cross-network-only; never local, never group. → TC-VC01-12/14/21.
- **INV-4 (re-establish):** a dropped held circuit is re-held with bounded (≤60 s) exponential backoff that resets on success and re-verifies protection. → TC-VC01-13 (host, fake drops) + TC-VC01-19 D2 (live real-drop leg).
- **INV-5 (relay survivability):** the deployed relay's per-circuit limit is 1 h / 64 MiB — finite, signaling-grade, env-tunable. → TC-VC01-17/18 + TC-VC01-19 (live).
- **INV-6 (observability):** every hold lifecycle transition emits a distinct flow event; hold ≠ warm dial (discriminator). → TC-VC01-15/16.
- **INV-7 (move gate / rule 4):** both new primitives call `_allowsAccountNetworkSideEffects` first-line. → TC-VC01-11.
- **INV-8 (no collateral reversal):** DCUtR default, reachability, warmPeer, keepalive semantics unchanged. → PRESERVE-P1..P5.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan

> **Stop-if (global):** any PRESERVE-P1..P6 sentinel reds at any step → stop and replan; that is collateral reversal (VC-02's or nobody's territory), not a migration.

1. **Snapshot:** record `git status --short` (preserve the pre-existing dirty tree — do not revert/absorb/reformat it); capture green baselines: `./scripts/run_test_gates.sh 1to1`, `run_host_test_gates.sh feature-host-all` + `core-host-all`, `./scripts/run_test_gates.sh all` (record counts at execution start).
2. **RED (up-front subset only — per-slice cadence for the rest):** author ONLY the re-pointed pin (TC-VC01-01, the 9→10 key flip) and the not-yet-runnable proof-test file (TC-VC01-19); confirm TC-VC01-01 REDs 9-vs-10. **Every other TC is authored RED inside its own slice (steps 3–8), immediately before that slice's implementation** — so a seam surprise (e.g. the step-6 fake-explosion stop-if) never invalidates pre-written RED files for later slices. Each slice: author its REDs → run its focused RED command (Acceptance Gates §RED) → confirm each fails for its documented reason → implement → GREEN.
3. **Flag plumbing (Dart+Go):** author TC-VC01-02..04 REDs (key absent / compile), then implement: add the 10th map entry in `p2p_bridge_client.dart` (seam: `defaultResilienceFeatureFlags()` `:32`); add `EnableLiveCircuitHold` field + `DefaultFeatureFlags()` false + merge case in `feature_flags.go`. GREEN: TC-VC01-01..04. Stop-if: any OTHER flag pin reds (would mean the map/merge edit leaked).
4. **Go hold primitive:** author TC-VC01-05..08 REDs (`circuit_hold_test.go`), confirm compile-RED, then implement: new `go-mknoon/node/circuit_hold.go` — `HoldPeerCircuit` (flag gate → live-conn check → dial via the **public `DialPeerViaRelay`** wrapper `node.go:1392-1401` so the `dialPeerViaRelayHook` seam observes the dial → `ConnManager().Protect`), `ReleasePeerCircuit` (`Unprotect` only). Seam: new file; `node.go` untouched (wrapper reused as-is). GREEN: TC-VC01-05..08.
5. **Bridge + native + Dart routing:** author TC-VC01-09/10 REDs (compile / UNKNOWN_COMMAND), then implement: `bridge_circuit_hold.go` exports (seam: `bridge_ping.go` shape); `GoBridge.kt` + `GoBridge.swift` cases (seam: beside `peerPing`, `:125` / `:139-140`); `go_bridge_client.dart` `_cmdMap` entries. GREEN: TC-VC01-09/10. Rebuild the gomobile artifacts for the device leg (Android `.aar` required for TC-VC01-19; iOS framework compiled but device-unproven — deferred-not-waived).
6. **Dart service primitives:** author TC-VC01-11 REDs (compile), then implement: `holdPeerCircuit`/`releasePeerCircuit` on `P2PService` + `P2PServiceImpl` (first-line gate, flag readback via `currentState.featureFlags`); update `FakeP2PService` + any implementers the compiler names. GREEN: TC-VC01-11. Stop-if: interface change breaks >a-handful of fakes with non-mechanical fixes → replan the seam as injected callbacks instead.
7. **Hold loop + wiring + metrics:** author TC-VC01-12..16 and TC-VC01-21 REDs (compile), then implement: `live_circuit_hold_use_case.dart` (backoff, release, flow events, TransportMetrics feed); `main.dart` wiring beside `_keepAliveUseCase:4080-4095`; `transport_metrics.dart` recorders. GREEN: TC-VC01-12..16, 21.
8. **Relay limits:** author TC-VC01-17/18 REDs (compile + DefaultLimit), then implement: `limits.go` fields + env + `relayResourcesFromServerLimits`; `main.go:25` version → `1.6.0`. GREEN: TC-VC01-17/18; PRESERVE-P6 still green. *Optional early live probe (pull-forward):* the relay slice MAY be deployed now, ahead of the remaining app slices (still one relay change per deploy — it is the same single change): land a manual circuit via the existing `DialPeerViaRelay`/RelayProbe path and observe it alive past 120 s — surfaces live-env surprises (e.g. on-box env overrides, redeploy pre-flight step 0) before a full app-implementation cycle. The rule-2 gate (TC-VC01-19) still runs at step 11 regardless.
9. **Harness registration (rule 6):** add the two new synthetic Go paths to `run_host_test_gates.sh` (matcher + `print_command_for_path` + `run_path` branches, GOTOOLCHAIN-pinned); add `p2p_service_circuit_hold_flag_test.dart` + `live_circuit_hold_use_case_test.dart` to `ONE_TO_ONE_TESTS`; add the `check_reliability_simulation_discovery.sh` classify_path case + the `vc01_live_circuit_hold_2min` orchestrator scenario; update the four gate docs together (`run_test_gates.sh`-adjacent: `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md`). Verify: `./scripts/run_test_gates.sh completeness-check` + `./scripts/check_reliability_simulation_discovery.sh` + `run_host_test_gates.sh host-all --list` shows the new Go paths.
10. **Rerun direct → preservation → named gates** (Acceptance Gates). Re-run every mutation to confirm re-RED.
11. **EC2 redeploy + live verification** (next section) — then run TC-VC01-19 on the device rig and the measurement runsheet (R-1..R-6).

---

## Execution Environment  (VC-00 rule 1 — commands for the implementing AI agent)

**Rig:** one USB-connected Android device + one Android emulator, both with the app built from this tree. Cross-network setup for the proof leg: USB device on **cellular/hotspot**, emulator on **host WiFi NAT** (different networks ⇒ relay is the only path — exactly the held-circuit scenario).

```bash
# 1. Discover serials (USB device = e.g. 21071FDF600CSC; emulator = e.g. emulator-5554)
adb devices

# 2. Launch/verify an emulator if none listed
flutter emulators; flutter emulators --launch <emulator-id>; adb devices

# 3. Single-device host-of-proof run (flag ON, flow-log forced for capture)
flutter test integration_test/live_circuit_hold_proof_test.dart \
  -d <usb-serial> \
  --dart-define=MKNOON_ENABLE_LIVE_CIRCUIT_HOLD=true \
  --dart-define=FDC_FLOW_LOG=1

# 4. Two-party orchestrated run (device A = USB holder side, device B = emulator peer)
dart run integration_test/scripts/run_1to1_device_real.dart \
  --scenario vc01_live_circuit_hold_2min -d <usb-serial>,<emulator-serial>
#   (the scenario is registered in _scenarios and prints per-leg recipes; --list-scenarios must show it)

# 5. Log capture (start BEFORE acting; two terminals, one per device)
adb -s <usb-serial>      logcat -v time | grep -E 'FLOW.*(CIRCUIT_HOLD_|KEEPALIVE_|MSG_)' | tee vc01-device.log
adb -s <emulator-serial> logcat -v time | grep -E 'FLOW.*(CIRCUIT_HOLD_|KEEPALIVE_|MSG_)' | tee vc01-emulator.log
```

**Which legs run where:** the **hold side** (active conversation open) runs on the USB device (real radio, real battery for the runsheet); the emulator is the remote peer (its side needs no hold — it only answers pings/messages). Relay: the deployed `mknoun.xyz` pair (`/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` + quic-v1 :4002 — `run_test_gates.sh:568`; `run_reliability_simulations.sh` defaults to it when `MKNOON_RELAY_ADDRESSES` unset).

**iOS boundary (deferred-not-waived):** `GoBridge.swift` gains the two dispatch cases and must compile, but no iOS simulator/device is in this rig. The orchestrator scenario prints the iPhone recipe and exits 0 without claiming proof for any iOS leg (the `run_1to1_device_real.dart` deferred-not-waived convention). iOS device evidence is owned by a future macOS/iPhone session — recorded in the RESULTS doc as deferred, never marked proven.

---

## EC2 Redeploy & Live Verification  (VC-00 rule 2 — literal, operator-run, never part of a test run)

Grounded in the canonical procedure (`Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md:141-150`; unit `relay-server`, `go-relay-server/README.md:1-39`). One relay change per deploy (`173-…-tdd-plan.md:156`); coordinate with **VC-03** (same `main.go`): whichever lands second rebases onto the other's committed relay tree — never a combined untested binary.

```bash
# 0. PRE-FLIGHT — on-box inspection + rollback artifact (NEW — no runbook step existed for this; keep it)
ssh -i se.pem ubuntu@mknoun.xyz '/usr/local/bin/relay-server version && systemctl is-active relay-server'
#   expect: 1.5.1 / active. Also inspect the live env (repo cannot verify it — RELAY_BACKEND etc.):
ssh -i se.pem ubuntu@mknoun.xyz 'sudo systemctl cat relay-server'
ssh -i se.pem ubuntu@mknoun.xyz 'sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.pre-vc01'   # NEW rollback copy

# 1. BUILD (cross-compile; relay tests green first — see Acceptance Gates)
cd go-relay-server && GOOS=linux GOARCH=amd64 go build -o relay-server-linux-amd64 . && cd ..

# 2. DEPLOY
scp -i se.pem go-relay-server/relay-server-linux-amd64 ubuntu@mknoun.xyz:/tmp/relay-server
ssh -i se.pem ubuntu@mknoun.xyz 'sudo install /tmp/relay-server /usr/local/bin/relay-server \
  && sudo systemctl restart relay-server && systemctl is-active relay-server \
  && /usr/local/bin/relay-server version'
#   expect: active + version 1.6.0 (the bumped const proves the new binary is live)

# 3. HEALTH PROBE
ssh -i se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 60 --no-pager'
ssh -i se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep -E "relay_connections_active|relay_backend_durable"'

# 4. LIVE VERIFICATION GATE (the rule-2 discriminator):
#    run TC-VC01-19 (Execution Environment §3/§4) against the DEPLOYED relay.
#    PASS = the SAME held /p2p-circuit connection observed at CIRCUIT_HOLD_ESTABLISHED is
#    still present at T+150s AND zero CIRCUIT_HOLD_LOST and zero CIRCUIT_HOLD_REHELD
#    events occur in [ESTABLISHED, T+150s].  (The pre-VC01 binary, DefaultLimit ~2min,
#    kills it at ~120s — a kill->re-hold->present sequence is a FAIL, not a pass. A pass
#    is only reachable with the new binary live.) Then run the D2 recovery leg.
#    Save logs to the RESULTS doc. Tolerate + record any holepunch:attempt events (L7).

# 5. ROLLBACK (NEW — explicit; previous binary kept in step 0)
ssh -i se.pem ubuntu@mknoun.xyz 'sudo install /usr/local/bin/relay-server.pre-vc01 /usr/local/bin/relay-server \
  && sudo systemctl restart relay-server && systemctl is-active relay-server && /usr/local/bin/relay-server version'
#   expect: 1.5.1 — and TC-VC01-19 re-run now FAILS at ~120s (mutation-style proof of the deploy itself)
```

Also refresh the committed rollback artifact convention: the freshly built `relay-server-linux-amd64` replaces the stale Jun-22 binary in the commit (de-facto rollback artifact per `production-stack-layer-audit.md:290`).

---

## Metrics & Measurement Runsheet  (owns VC-01's rows of the VC-00 metrics table)

**Row 1 — "Circuit hold rate / duration / churn per active 1:1 session":**
- Vehicles (each with a named test): flow events `CIRCUIT_HOLD_ESTABLISHED/LOST/REHELD/RELEASED{heldMs}` (TC-VC01-13/14/15) + `TransportMetrics` hold counters and median/p95 hold-duration samples surfaced in `baselineReport()` and the debug diagnostics card (TC-VC01-16). Device capture: runsheet step R-4 greps + tees the `[FLOW]` lines (sanitizer applies unconditionally, `flow_event_emitter.dart:202-218`; `FDC_FLOW_LOG=1` force-on for profile builds, `main.dart:325-335` — never write "debug-only").
- Definitions: **hold rate** = ESTABLISHED / REQUESTED per session; **duration** = RELEASED.heldMs distribution (median+p95, never mean); **churn** = LOST+REHELD count per session-hour.
- **Observational for VC-01 — no pass/fail threshold**; the numbers feed the VC-00 graduation decision. An executor must neither invent a threshold nor treat this row as a gate.

**Row 2 — "Battery/data cost of held circuits (graduation gate for flag default-ON)":** runsheet below; results land in `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-01-hold-measurement-RESULTS.md` (freeze table: commit hash, toolchains, device model, `GOTOOLCHAIN=go1.25.0` caveat — FDC-S0 RESULTS conventions). **The flag does not graduate to default-ON until this gate passes review — explicitly NOT part of VC-01 closure.**

Runsheet (USB device; profile builds; two 30-minute A/B sessions, same device, same charge band 40-80%, screen on, one active 1:1 chat open to the emulator peer, cross-network):
- **R-1 Build A (flag OFF):** `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1`; install; `adb shell dumpsys batterystats --reset`; note `adb shell dumpsys netstats detail | grep -A4 <app-uid>` baseline.
- **R-2 Run A:** 30 min foreground chat (scripted: 1 msg/min both directions). Capture: `adb shell dumpsys batterystats --charged com.mknoon.app > vc01-battery-off.txt`; netstats delta → `vc01-data-off.txt`.
- **R-3 Build B (flag ON):** same + `--dart-define=MKNOON_ENABLE_LIVE_CIRCUIT_HOLD=true`; reset stats; repeat.
- **R-4 Run B:** 30 min identical script with `[FLOW]` capture running (Execution Environment §5). Capture battery/netstats as `vc01-battery-on.txt` / `vc01-data-on.txt`; compute hold rate/duration/churn from the FLOW log.
- **R-5 Scorecard:** report Δbattery (mAh and %) and Δdata (rx/tx bytes) flag-on vs flag-off; median of the per-session numbers if repeated. **The graduation threshold is set by the VC-00 follow-up decision — this row records raw deltas only; do NOT rationalize a threshold after seeing the data** (no "acceptable? yes/no" verdict is written here). This answers the recorded "wasteful circuit" rationale (`p2p_service_impl.dart:2666-2670` — qualitative, never measured; VC-00 decision record demands the number).
- **R-6 Flag-off byte-identical sweep (TC-VC01-20):** during Run A, `grep -c 'CIRCUIT_HOLD_' vc01-*-off.log` must be **0**.

---

## Risks And Edge Cases

| Risk / edge | Pinned by / mitigated by |
|---|---|
| Held circuit trimmed at connmgr high-water 100 (the verified zero-Protect gap) | TC-VC01-06 (`IsProtected` + delete-Protect mutation); real-fleet trim behavior additionally observed via churn metrics (R-4). **Stated trust decision:** trim-survival of a protected conn is delegated to upstream connmgr semantics (domain-verified: `BasicConnMgr.getConnsToClose` skips protected peers, go-libp2p v0.39.1 `p2p/net/connmgr/connmgr.go`) — protection is near-absolute, not absolute (emergency memory-pressure trim can still kill protected conns); that residual is covered by the drop→re-hold loop (TC-VC01-13) and watched via R-4 churn |
| Deployed relay kills the hold at 2 min / 128 KiB | TC-VC01-17/18 (limits raised, finite) + TC-VC01-19 live >2 min gate + rollback re-red |
| Battery/data regression (the original Path-3 rationale) | Flag default OFF (rule 3) + measurement runsheet R-1..R-5 as the graduation gate; foreground-only scoping mirrors the keepalive battery design (`active_peer_keepalive_use_case.dart:14-16`) |
| Relay capacity: N held circuits consume relay conns (`MaxReservations=512`, `MaxCircuits=8/peer` kept) | finite limits + `relay_connections_active` watched during live verification; staged rollout (flag) bounds fleet exposure |
| Hold loop re-dial storms on a durably-gone peer | TC-VC01-13 (bounded backoff, 60 s cap, reset-on-success); keepalive drop-latch precedent |
| `warmPeer` and hold racing on the same peer | additive design: hold never routes through warmPeer (TC-VC01-15 discriminator); libp2p coalesces concurrent dials (FDC-S5 note at `p2p_service_impl.dart:2694-2697`) |
| Emergent send-path change: a held circuit makes `liveRelayEligible` true more often (`send_chat_message_use_case.dart:901-903`) — intended benefit, purely observational over `currentState.connections` | existing FDC-02 relay-leg suite stays green (`send_chat_message_use_case_test.dart::circuit-only peer recovers LIVE via the FDC-02 in-race relay leg` — regression floor `1to1`) |
| Native dispatch skew (Dart cmd lands, native case missing → `result.notImplemented()` at runtime, `GoBridge.kt:180` else-branch) | TC-VC01-10 pins Dart routing; TC-VC01-19 exercises the real Android MethodChannel end-to-end; iOS compiled + deferred-not-waived |
| Relay redeploy breaks old clients | limits raise is backward-compatible (pure server-side envelope widening; no wire/protocol change); one-change-per-deploy rule |
| Group peers accidentally held | TC-VC01-12 (`group:` never held) |

---

## Device/Relay Proof Profile

**Requires device + deployed relay for closure** (NOT host-closable): TC-VC01-19 is the PROD-CRITICAL wire leg — host fakes cannot prove a real circuit survives the real relay's limit envelope, connmgr trim pressure, or the gomobile MethodChannel dispatch. Host-green alone is explicitly insufficient (sufficiency-checklist boundary rule).
- Closure scenario: orchestrator `--scenario vc01_live_circuit_hold_2min` covering **both legs — D1 (same-conn survival predicate) then D2 (forced real drop → LOST → REHELD → live again ≤60 s + post-recovery message commit)** (registered; `/sims 1to1 --list` must show the proof file after the classify_path case lands — `/sims` runs it, never registers it).
- Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…` (+ quic-v1 :4002) — against the **redeployed** 1.6.0 binary only.
- Deferred device work → future macOS/iPhone session: iOS hold-side proof (recipe printed by the orchestrator; `GoBridge.swift` dispatch is code-complete + host-compiled here).
- Flag flip to default-ON: only AFTER the R-1..R-5 measurement gate passes (owned by a follow-up decision, not this story).

---

## Working Piece On Close

The demonstrable, self-contained capability when VC-01 closes — something later stories comfortably build on:

- **Flag-ON build** (`--dart-define=MKNOON_ENABLE_LIVE_CIRCUIT_HOLD=true`) on the USB Android device + emulator, cross-network through the **deployed** `mknoun.xyz` relay (v1.6.0): open a 1:1 chat → a live `/p2p-circuit` connection to the peer is dialed and **held > 2 minutes (the SAME connection, zero LOST/REHELD inside the T+150 s window)**, protected from connmgr trim, kept alive by the existing 8 s keepalive pings, re-held with bounded backoff on drop (proven live in the D2 recovery leg), released on chat close/background — all of it visible in `[FLOW] CIRCUIT_HOLD_*` events and `TransportMetrics` hold counters, and a message sent mid-hold commits on the relay-live leg.
- **Flag-OFF build** behaves byte-identically to today (zero hold commands, zero hold events, warmPeer untouched) — the test-locked kill-switch/revert path.
- **Deployed relay** serves signaling-grade per-circuit limits (1 h / 64 MiB, env-tunable), verified live, with a staged rollback binary.
- **Measured**: a battery/data A/B RESULTS doc quantifying the cost of holding (the graduation input the original Path-3 decision never had), plus hold rate/duration/churn numbers.

This is exactly the substrate VC-02 needs (a live held circuit for DCUtR to upgrade) and VC-04 benefits from (live fast path for `call_*` envelopes).

---

## Acceptance Gates  (LITERAL — copy/paste; capture green baseline counts at execution start, never hardcode — VC-00 rule 6)

```bash
# 0. Baselines + dirty-tree snapshot (execution start)
git status --short | tee /tmp/vc01-dirty-tree.txt
./scripts/run_test_gates.sh 1to1                      # capture baseline count
./scripts/run_host_test_gates.sh feature-host-all     # capture
./scripts/run_host_test_gates.sh core-host-all        # capture
./scripts/run_test_gates.sh all                       # capture (includes relay Go via run_relay_all_go_gate)
flutter analyze                                       # record baseline issue count (dirty tree)

# RED — run each line immediately BEFORE its owning slice's implementation (per-slice
# cadence, Step 2; only TC-VC01-01 + the proof file are authored up-front) — each must
# FAIL for its documented reason
flutter test test/core/bridge/p2p_bridge_client_test.dart --plain-name 'pins exactly the 10 canonical keys with intended polarity'
flutter test test/core/services/p2p_service_circuit_hold_flag_test.dart test/core/services/p2p_service_circuit_hold_test.dart
flutter test test/core/services/live_circuit_hold_use_case_test.dart test/core/lifecycle/main_circuit_hold_wiring_test.dart test/core/debug/transport_metrics_circuit_hold_test.dart
flutter test test/core/bridge/go_bridge_client_test.dart --plain-name 'circuit:hold calls circuitHold with payload JSON'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CircuitHold|CircuitRelease|TestFeatureFlags_LiveCircuitHold' -count=1)   # expect compile-RED
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'CircuitHoldBridge' -count=1)                                            # expect compile-RED
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run 'RelayCircuitLimits' -count=1)                                        # expect compile-RED

# Direct GREEN (after implementation)
flutter test test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart
flutter test test/core/services/p2p_service_circuit_hold_flag_test.dart test/core/services/p2p_service_circuit_hold_test.dart \
  test/core/services/live_circuit_hold_use_case_test.dart test/core/lifecycle/main_circuit_hold_wiring_test.dart \
  test/core/debug/transport_metrics_circuit_hold_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CircuitHold|CircuitRelease|FeatureFlag' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'CircuitHoldBridge|PartialFeatureFlags' -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)

# Preservation sentinels (must stay green — collateral-reversal tripwires)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof|TestDefaultFlagsKeepPrivateReachability|TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer_SuccessIsPeerScoped_CoResidentCircuitUntouched|TestHolePunchTracer_DirectDialEvt_IsBreadcrumbOnly_NoUpgrade|TestHolePunchTracer_AlreadyDirect_NoDoubleUpgrade' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./integration -run 'TestDefaultFlagsKeepPrivateReachability_CircuitPublished' -count=1)
flutter test test/core/services/p2p_service_dcutr_flag_test.dart test/core/lifecycle/handle_app_resumed_warm_peer_test.dart \
  test/core/lifecycle/main_keepalive_wiring_test.dart test/core/services/active_peer_keepalive_use_case_test.dart

# Named gates + registration verification (compare to captured baselines + the known new-test delta)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=<usb-serial> ./scripts/run_test_gates.sh transport
./scripts/run_host_test_gates.sh host-all            # must list + run the two NEW Go synthetic paths
./scripts/run_host_test_gates.sh host-all --list | grep -i circuit_hold   # registration proof
./scripts/run_test_gates.sh completeness-check       # every new *_test.dart classifies
./scripts/check_reliability_simulation_discovery.sh  # proof test + orchestrator scenario must list
dart run integration_test/scripts/run_1to1_device_real.dart --scenario all --list-scenarios | grep vc01_live_circuit_hold_2min

# Device proof (rule 1) + live relay gate (rule 2) — after the EC2 redeploy section
adb devices
flutter test integration_test/live_circuit_hold_proof_test.dart -d <usb-serial> \
  --dart-define=MKNOON_ENABLE_LIVE_CIRCUIT_HOLD=true --dart-define=FDC_FLOW_LOG=1
dart run integration_test/scripts/run_1to1_device_real.dart --scenario vc01_live_circuit_hold_2min -d <usb-serial>,<emulator-serial>

# Hygiene
flutter analyze            # 0 new vs the step-0 baseline (do not rewrite the analyzer baseline)
git diff --check
```

---

## Known-Failure Interpretation

- **Expected RED (pre-fix):** every command in the RED block, for the documented reasons (compile-RED for new symbols; 9-vs-10 for TC-VC01-01; `UNKNOWN_COMMAND` for TC-VC01-10; `relay.DefaultLimit()` for TC-VC01-17). `TestMergeFeatureFlags_EveryStructFieldIsMergeable` reds **between** the Go field landing and its merge case — expected mid-step-3 only.
- **Expected migrated delta:** the `1to1`/host gate totals shift by exactly the new-test count + the one re-pointed pin (TC-VC01-01). Diff the named tests, not the raw count.
- **Pre-existing dirty tree:** whatever `/tmp/vc01-dirty-tree.txt` recorded (this branch carries unrelated modified files — see `git status` at plan time). Do not revert, absorb, or reformat it.
- **Environment blockers (NOT product):** no USB device / no emulator → TC-VC01-19 + runsheet blocked (defer, do not fake); no `se.pem` / EC2 unreachable → redeploy blocked (story stays open per rule 2); Go toolchain absent on the dev box → Go gates blocked (environment, not product). A `transport` gate skip on a lone device is fixture-gated, not a failure.
- **Expected + tolerated (epic lock L7):** `holepunch:attempt` and related punch events may legitimately appear during ANY device leg (TC-VC01-19 D1/D2, TC-VC01-20/R-6) — on HEAD `EnableHolePunching` is always on, and a held circuit plus observed public addresses can fire punch attempts before VC-02 lands. Tolerate and RECORD them (RESULTS doc); never fail on them. Punch-outcome assertions belong exclusively to VC-02.
- **Known flake:** pre-existing `groups` flake (durable-media-upload) is not VC-01 — re-run in isolation; VC-01 touches no group code.
- **Scope drift (BLOCKING):** ANY red in PRESERVE-P1..P6 (dcutr polarity, reachability, zero-punch, 188 guards, warm/keepalive suites, relay finite-limit pins) or any diff in `warmPeer`/`node.go:387-403` — stop, revert the offending edit, replan.

---

## Done Criteria

- [ ] `git status --short` snapshot recorded before execution; dirty tree preserved.
- [ ] TC-VC01-01..18, 21 authored RED-first; each failed for its documented reason, then GREEN.
- [ ] Every behavior edit mutation-verified (named revert → named RED: map entry, Go default, merge case, flag gates, `Protect` line, `Unprotect` line, `_cmdMap` entry, move-gate line, isLocal guard, backoff cap, release-on-bg, main.dart wiring, `limits.go` revert, relay rollback re-red for TC-VC01-19).
- [ ] Preservation sentinels + named gates green vs captured baselines; the two flipped pins re-pointed with `// VC-01:` rationale, never deleted.
- [ ] Harness registration done & verified in gate runs: 2 new Go synthetic paths listed by `host-all --list`; 2 files added to `ONE_TO_ONE_TESTS`; classify_path case + orchestrator scenario listed by `check_reliability_simulation_discovery.sh` and `--list-scenarios`; `completeness-check` green; 4 gate docs updated together (rule 6).
- [ ] No migration needed (no schema change) — N/A row, not skipped.
- [ ] EC2 relay redeployed (version 1.6.0 live), health probe green, rollback binary staged (rule 2).
- [ ] **TC-VC01-19 green on the device rig against the DEPLOYED relay** — D1 per the rule-2 predicate (SAME held circuit at T+150 s, zero LOST/REHELD in window; **2 consecutive passes**) AND D2 recovery leg (real drop → LOST → REHELD → live ≤60 s), device↔emulator, cross-network — the PROD-CRITICAL wire leg proven for real, not faked. Punch events tolerated + recorded (L7).
- [ ] Flag-off byte-identical: host locks green + runsheet R-6 zero `CIRCUIT_HOLD_` lines.
- [ ] Measurement runsheet executed; `VC-01-hold-measurement-RESULTS.md` written (battery/data A/B + hold rate/duration/churn); flag remains default-OFF.
- [ ] iOS legs recorded deferred-not-waived (dispatch code compiled; device recipe printed; nothing claimed proven).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

---

## Scope Guard (hard "Do not")

- **Do NOT** flip `enableDcutrUpgrade` (Dart or Go default) or edit `dcutrReachabilityMode` / any reachability option (`node.go:387-403`, `peer_session.go:20-25`) — **VC-02** owns the DCUtR flip and its NO_CIRCUIT-wedge handling (`reachability_default_guard_test.go` / `no_circuit_recovery_test.go` are ITS problem, and they must stay green here).
- **Do NOT** add TURN/STUN anything (`pion/*` promotion, new relay listeners) — **VC-03**.
- **Do NOT** add `call_*` envelope types, router cases, or signaling send paths — **VC-04**.
- **Do NOT** modify `warmPeer` (`p2p_service_impl.dart:2612-2717`), `ActivePeerKeepAliveUseCase`, or the send-path race (`send_chat_message_use_case.dart`) — the hold is strictly additive.
- **Do NOT** ship the flag default-ON, remove the flag, or bypass it anywhere (rule 3; graduation is a separate post-measurement decision).
- **Do NOT** set `resources.Limit = nil` (unlimited) on the relay — finite signaling-grade only (keeps `limits_test.go:204-206` green).
- **Do NOT** touch relay push/inbox/rendezvous/media code paths in go-relay-server (`inbox.go` etc.) — limits + version only.
- **Do NOT** deploy a relay binary carrying any other story's uncommitted relay changes (one landed story per deploy; VC-03 collision).
- **Do NOT** index this plan in `Test-Flight-Improv/00-INDEX.md` (rule 7).

## Accepted Differences / Intentionally Out Of Scope

- **No Go-side hold events** (VC-00 metrics row says "flow events + Go events"): hold lifecycle telemetry is emitted from the Dart loop (which owns the state machine); Go signals via command responses. Adding new Go diagnostic events would require `bridge.dart` allowlist + `go_bridge_client.dart` switch churn for no extra information — deferred until VC-09's quality-metrics pass if fleet-side granularity is needed.
- **No relay Prometheus per-hold metrics** — `relay_connections_active` suffices for VC-01's live verification; per-call/per-circuit relay metrics are **VC-09**.
- **Background holds** — foreground-only by design (battery precedent, `active_peer_keepalive_use_case.dart:14-16`); background reachability remains push + durable inbox. Call-time background behavior is **VC-06/VC-07**.
- **Hold on LAN-local peers** — deliberately excluded (LAN direct is strictly better; mirrors warmPeer's LAN-first design); asymmetry test-locked (TC-VC01-12).
- **`kLiveRelayMaxPayloadBytes`/frame caps unchanged** (96 KiB / 128 KiB) — held circuits are signaling-grade transport; media stays on its own lanes.
- **iOS device proof** — deferred-not-waived (rule 1 rig is Android-only); config/dispatch still test-locked at host tier.

## Dependency Impact

- **VC-02 depends on this** (hard): DCUtR needs a live held circuit to upgrade (the 188 finding). Contract handed over: flag-gated held+`Protect`ed circuit to the active 1:1 peer, observable via `CIRCUIT_HOLD_ESTABLISHED` and `currentState.connections` (`/p2p-circuit` entry). **VC-02 must branch from VC-01's committed tree** — both edit `feature_flags.go`, `p2p_bridge_client.dart` (the flag map + its 10-key pin), and `feature_flags_runtime_test.go` (collision map, VC-00).
- **VC-03 collides** on `go-relay-server/main.go` + the EC2 deploy slot: one redeploy per landed story; second-lander rebases.
- **VC-04 benefits** (soft): held circuits give `call_*` envelopes a live fast path cross-network (`liveRelayEligible` becomes true) — no contract change required from VC-01.
- **Flag-file rebases expected** for every later VC story adding a flag (the 10-key pin becomes 11-key etc.) — the pin's exact-set design makes each addition an explicit, reviewed flip.

---

## Reviewer Findings

Sufficiency checklist run against this draft (all gates):
- Spec-case totality: **Yes** — TC-VC01-01..21 each map to ≥1 named test at a stated tier; no orphan IDs (TC-VC01-20 is a runsheet pass-condition whose test-tier locks are named TC-VC01-05/11/12).
- Every INV has a test: **Yes** (INV-1..8 each cite rows).
- Mutation-verified: **Yes** — each production edit names its revert and the test that re-reds (incl. the deploy itself via the relay rollback re-red).
- No vacuous coverage: **Yes** — every RED has a documented on-HEAD failure reason; shared-result discriminator present (TC-VC01-15 asserts `CIRCUIT_HOLD_ESTABLISHED` AND NOT `P2P_SERVICE_WARM_PEER_DIAL`; TC-VC01-19 discriminates via the >2-min survival that the old relay cannot produce).
- Migration real-DB test: **N/A, justified** — no schema change (stated in Done Criteria).
- Boundaries proven for real: **Yes** — TC-VC01-19 device-proof on real bridge + deployed relay; PROD-CRITICAL marked.
- PROD-CRITICAL leg named: **Yes** (TC-VC01-19).
- Preservation sentinels named with commands: **Yes** (PRESERVE-P1..P6 + regression floors; counts via captured baselines per rule 6).
- Literal gates: **Yes** (copy-paste block incl. analyze + `git diff --check`).
- Registration per new test: **Yes** — zero empty registration cells; manual registrations enumerated (2 Go synthetic paths, ONE_TO_ONE_TESTS ×2, classify_path case, orchestrator scenario, dart-define).
- Known-failure interpretation: **Yes**. Dirty-tree snapshot: **Yes** (step 1 + gates step 0).
- Refuted findings recorded: **Yes** (Root Cause do-NOT-re-introduce list).
- Blind-spot sweep: **Yes** — all four classes have rows or justified N/A.
- Matrix gate: **Yes** — zero empty cells across tier/mutation/gate/registration.

Fixed during self-review (was No → now Yes): (1) initial draft had no wiring-tier mutation for the `main.dart` edit — added TC-VC01-21; (2) TC-VC01-16's mutation was vacuous (recorder-only) — re-pointed at the use-case→metrics feed wire; (3) release path originally asserted only `Unprotect` — added the "never closes the conn" destructive-side-effect assertion (TC-VC01-07) per the blind-spot sweep; (4) the flag addition's pin blast radius was initially copied from the digest's DCUtR-flip list — re-derived for a flag *addition* and verified mechanically (exactly 2 pins flip, others additive-safe); (5) the mandatory "Working Piece On Close" section was missing from the first draft — added.

### /tdd-review verdict (2026-07-13, applied)

Dimension scores: goal-clarity 86 (strong) · compartmentalization 77 (strong) · anti-drift 84 (strong) · define-good 78 (strong) · goal-verification 71 (adequate). Findings: **1 material, 4 moderate, 6 nits** from the assessment, plus 2 source-verified factual corrections and ~6 cite drifts from the fact/domain verifiers (domain verification returned zero material errors — the relay-limit/Protect/ping-over-circuit bet is confirmed against upstream go-libp2p source).

Applied in this revision:
- **Material (goal-verification):** hold-dial seam unified — `HoldPeerCircuit` now routes through the public `DialPeerViaRelay` wrapper (`node.go:1392-1401`) so the `dialPeerViaRelayHook` spy in TC-VC01-05/08 is faithful; TC-VC01-05 additionally asserts `len(h.Network().ConnsToPeer(pid))==0` as a connection-level belt-and-braces (Real Scope item 2, Step 4, catalog entries aligned).
- **Moderate:** single verbatim TC-VC01-19 D1 predicate (SAME connection at T+150 s, zero `CIRCUIT_HOLD_LOST` AND zero `CIRCUIT_HOLD_REHELD` in window — "or re-held" deleted) mirrored in rule 2, the catalog, the EC2 gate comment, matrix, Done Criteria; new **D2 live recovery leg** (forced real drop → LOST → REHELD → live ≤60 s + post-recovery message commit) covering INV-4 on the real path; per-slice RED authoring cadence (steps 2–8 restructured; only TC-VC01-01 + the proof file are authored up-front).
- **Factual corrections (verifier-confirmed):** unknown-command RED is `errorCode: 'UNKNOWN_COMMAND'` (`go_bridge_client.dart:902`, pinned at test `:520`), not "UNHANDLED"; the routing map is `_cmdMap` (`go_bridge_client.dart:97`), not `_commandMap` (all occurrences); native missing-case fallback is `result.notImplemented()` (`GoBridge.kt:180`); Protect-grep evidence line rewritten with `-E` + escaped parens and the vendored `third_party/` pubsub nuance; node_test comment cite `:2873-2874`; cite drifts fixed (`:314`, `:568`, `:76-79`, `:1424-1436`, payloadCmds `:163`).
- **Nits:** TC-VC01-19 repeat/flake policy (2 consecutive D1 passes; one re-run; two failures = product/deploy FAIL); Metrics Row 1 marked observational (no invented threshold); R-5 records raw deltas only (threshold owned by the VC-00 follow-up — no post-hoc verdict row); optional early relay-only live probe after step 8; connmgr trim-survival recorded as a stated trust decision (upstream `getConnsToClose` skips protected peers; emergency-trim residual covered by re-hold + R-4 churn); absolute 1 h deadline note (one guaranteed re-hold cycle/hour).
- **Epic contract locks:** L4 annotated as canonical here (1 h / 64 MiB, `RELAY_CIRCUIT_DURATION_SECONDS`/`RELAY_CIRCUIT_DATA_BYTES`); **L7** punch tolerance added to TC-VC01-19, TC-VC01-20/R-6, and Known-Failure Interpretation (device proofs and flag-off assertions tolerate + RECORD `holepunch:*` events, never fail on them; punch-outcome assertions are VC-02's). L1/L2/L3/L5/L6 do not touch this plan's surfaces (verified: no ring/TTL/TURN/call_* content; no stale DCUtR mechanism text).

## Arbiter Decision

Structural blockers: **none**. | Deferred details: exact relay Limit values (1 h / 64 MiB) are the L4 epic lock — bounded, justified, env-tunable, trivially re-tunable at execution; iOS device evidence deferred-not-waived per rule 1; prod relay env (`RELAY_BACKEND`) unverifiable from repo — on-box inspection step included in redeploy pre-flight; the D2 drop-injection vehicle (relay restart vs airplane-mode toggle) is an execution-time choice, both named. | Accepted differences: as listed above (no Go-side hold events until VC-09; no relay per-hold Prometheus; foreground-only; no LAN-local holds; payload caps unchanged; iOS deferred). Plan is implementation-ready (Status: accepted, post /tdd-review).

## Final Execution Verdict

Verdict: (pending execution) | Files changed: — | Tests run (+counts): — (capture at execution) | Blocking: — | QA verdict: — | Non-blocking follow-ups (owner): flag default-ON graduation decision (post-measurement, VC-00); relay per-circuit Prometheus (VC-09); iOS device proof (macOS/iPhone session).
