# VC-02 — DCUtR upgrade enablement: flag default-ON behind a real kill-switch  (Modification)

Status: accepted (post /tdd-review)
Spec: free-text intent grounded in `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md` (VC-02 story row + DECISION RECORD "Path 3 reversal", 2026-07-13). Path 3 reversal part **2 of 2** — part 1 is VC-01 (live circuit holding). Re-opens **CV-13** and contributes device evidence toward **CV-11/CV-12** (`Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-CONVERGENCE-CHECKLIST.md:52,:66,:89`).

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | circuits-dcutr / metrics-telemetry / harness-conventions grounding digests (adversarially refuted); re-verified on HEAD: `p2p_bridge_client.dart:76-79`, `feature_flags.go:62,80-92,112-137`, `node.go:387-403`, `peer_session.go:20-25`, all 6 guard-test files, `holepunch_feasibility_test.go:104-105`, `holepunch_negative_control_test.go`, `no_circuit_recovery_test.go:176-184`, `run_host_test_gates.sh:144-184,283-295,394-466` | Refuter finding stands on the NO_CIRCUIT leg: a naive ON→ForceReachabilityPublic default flip re-creates the spec-189 wedge → **decouple** (Design Decision below). *[Corrected post-review: the second leg originally recorded here — the feasibility comment's "forced-public hosts do not auto-hole-punch" — is a version-stale mechanism (gate removed in go-libp2p v0.37.0); see Root Cause 3]* | write plan |
| 2026-07-13 | Planner | (this file) | design: flag gates `EnableHolePunching` participation; reachability stays Private under all flag states | sufficiency review |
| 2026-07-13 | Reviewer (sufficiency) | assessment (5 dims) + domain verifier vs go-libp2p v0.39.1 source (`svc.go`, `holepuncher.go`, `basic_host.go`, `options.go`) | #1 bet CONFIRMED (Private+EnableHolePunching punches; kill-switch has mechanical teeth); 2 material corrections applied: version-stale ForcePublic mechanism purged (L6), leg B made may-fail-honest/route-recorded; 4 moderate gaps fixed | apply fixes |
| 2026-07-13 | Arbiter | (this file) | structural blockers: none — accepted post /tdd-review | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | device measurement (runsheet A/B/C) | | logs → RESULTS doc | | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Intent: `VC-00-roadmap.md` — DECISION RECORD (Path 3 reversal), story row VC-02, collision map (VC-02 runs **on VC-01's committed tree**), non-negotiable rules 1/3/6 (restated below).
- Gate definitions: `scripts/run_test_gates.sh` and `scripts/run_host_test_gates.sh` (**script wins over prose**).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (the DCUtR device-proof rows are ALREADY classified at `:393`).
- Numbering / index: VC plans live only in this subdirectory, numbered VC-NN; `Test-Flight-Improv/00-INDEX.md` does NOT index feature subdirectories (VC-00 rule 7).
- Superseded doc invariant: **TC-188-12 "prod-unchanged"** (`Test-Flight-Improv/188-dcutr-1to1-forced-circuit-verification-spec.md:49` — "store-and-forward remains the 1:1 prod transport: no new production code holds a `/p2p-circuit`") is **explicitly overturned** by the VC-00 DECISION RECORD (2026-07-13). VC-01 overturns the circuit half; VC-02 overturns the "flip stays parked" half (CV-13). Each 188-era pin is re-pointed below — never silently deleted.

## Session Classification
**implementation-ready** — the flag flip, the reachability decoupling, and every guard re-point are host-provable (Dart host tests + pinned Go invocations). Real punch payoff is device-tier by physics (a host/sim shares the host's network namespace — no genuine NAT to punch, per `integration_test/dcutr_upgrade_proof_test.dart:3-9`); that half closes via the Measurement Runsheet on the VC-00 rule-1 rig (USB Android device + emulator), with honest per-topology expectations.

---

## Exact Problem Statement

**What's missing.** VC-01 makes active 1:1 cross-network peers hold a live, protected `/p2p-circuit` connection — for the first time DCUtR has something to upgrade. But the upgrade path is still parked: `enableDcutrUpgrade` defaults **false** on the load-bearing Dart side (`lib/core/bridge/p2p_bridge_client.dart:76-79`, `MKNOON_ENABLE_DCUTR_UPGRADE`) and on the Go fallback (`go-mknoon/node/feature_flags.go:89`), and six guard files pin that polarity by design (188 Path 3 / CV-13). Held circuits therefore stay relay-bound forever: every voice/video packet of the VC epic would transit `mknoun.xyz` even for pairs that could punch a direct QUIC path.

**Who feels it.** Every cross-network 1:1 pair once VC-01 lands, and acutely the VC-05 audio-call MVP: relay-bound media pays double latency and consumes relay bandwidth; punchable pairs (~70%±7.1% network-wide per punchr — literature figure, VC-00 honesty note) are leaving a direct path unused.

**What must improve.** Flag default flips ON end-to-end (Dart load-bearing + Go fallback parity); flag-ON builds participate in DCUtR so held circuits upgrade to direct QUIC **where punchable**; punch attempt/success/failure and `transport:upgraded` are observable as flow events and captured per network class in a RESULTS doc.

**What must stay unchanged → preserved-green sentinels.**
- **Autorelay circuit publishing under DEFAULT flags** — the spec-189 NO_CIRCUIT wedge must NOT return (`go-mknoon/integration/no_circuit_recovery_test.go:176-184`, `go-mknoon/node/reachability_default_guard_test.go`). This is the reason for the Design Decision below.
- **188 tracer guards**: peer-scoped upgrade (TC-188-03), DirectDialEvt-is-breadcrumb-only (TC-188-10), exactly-once `transport:upgraded` (TC-188-11) — `go-mknoon/node/holepunch_tracer_test.go:286,:343,:418`.
- **Loopback inertness / no-thrash**: `holepunch_negative_control_test.go:62` (Limited-throughout, zero attempts, stable conn count).
- **Dart consumption**: `transport:upgraded` primes sticky 'direct' (`p2p_service_impl.dart:3722-3737`), `transport:downgraded` clears it (`:3739-3753`) — `test/core/services/p2p_service_transport_upgrade_test.dart`.
- **Un-punchable pairs degrade gracefully** to the VC-01 held circuit — calls/messaging never regress.

---

## Root Cause (verify → refute confirmed)

**Why the flip is not a two-line polarity change (the confirmed mechanism):**

1. **Flag plumbing (confirmed, anchors re-read on HEAD).** Dart builds the full 9-key map (`p2p_bridge_client.dart:41-90`) and sends it wholesale to `node:start`; the Dart value — not the Go fallback — is the production default (load-bearing comment `:62-67`). Go merges present keys over `DefaultFeatureFlags()` (`bridge.go:582-584` → `feature_flags.go:112-137`).
2. **What the flag does today (confirmed subtlety).** `libp2p.EnableHolePunching(holeOpts...)` is **unconditional** (`node.go:403`); the flag ONLY flips reachability: `dcutrReachabilityMode(flags.EnableDcutrUpgrade, forcePublicReachability)` (`peer_session.go:20-25`) selects `ForceReachabilityPrivate()` vs `ForceReachabilityPublic()` at `node.go:393-396`. `node.go:394` is the sole non-test consumer of the flag.
3. **REFUTED — do NOT implement: "flip the default and let reachability flow Public fleet-wide."** Two independently pinned real behaviors kill it:
   - **NO_CIRCUIT wedge (TC-189-41, two guards).** Under `ForceReachabilityPublic` autorelay's relayFinder stops publishing this node's `/p2p-circuit` addresses — the spec-189 production wedge, re-created fleet-wide (`reachability_default_guard_test.go:5-11` comment; `no_circuit_recovery_test.go:170-184` proves circuit-published under default flags against a real local relay). These guards assert a REAL regression and **cannot be polarity-inverted** (grounding-digest correction).
   - **Fleet-Public also never punches — but for the same NO_CIRCUIT reason, not a puncher-construction rule.** With every node forced Public, no node keeps a relay reservation or publishes `/p2p-circuit` addrs, so no node ever receives the **inbound relayed connection** that triggers DCUtR initiation (go-libp2p v0.39.1 `holepuncher.go:266` fires only on `DirInbound` + relay addr) — punch initiation starves fleet-wide while relay messaging itself breaks. **⚠ Version-stale mechanism — never restate it:** the repo's feasibility comments (`holepunch_feasibility_test.go:104,:118,:140,:180` — "forced-public hosts do not auto-hole-punch") describe a puncher-construction gate (`EvtLocalReachabilityChanged==Private`) that go-libp2p **removed in v0.37.0**; on the pinned v0.39.1 (`go.mod:17`) the puncher is constructed on ANY `EnableHolePunching` host once it observes a public address (`svc.go:102-142`), and a forced-public host receiving an inbound relayed conn WOULD auto-initiate. The ForcePublic refutation rests on the TC-189-41/NO_CIRCUIT mechanism **alone**. Do not write the stale mechanism into any re-pointed comment or failure message; Step 3/6 re-points the four feasibility-comment lines to the correct "loopback yields no public addr" reason (mirroring `holepunch_negative_control_test.go:128`).
4. **Corollary (confirmed):** the 188-era "zero punches under Private" narrative is **loopback-scoped evidence** — the negative control's own inline reason is "DCUtR never initiates **without a reachable addr**" (`holepunch_negative_control_test.go:128`), which loopback guarantees. On a real NAT, a host with `EnableHolePunching` + an observed public address + an inbound relayed conn is exactly the auto-punch configuration (the v0.39.1 holepunch package has no reachability requirement at all — verifier-confirmed against `svc.go:102-142`). What actually kept production at zero punches was the **absence of live circuits** (188 root cause wf_b0ea0dc5) — which VC-01 reverses.

### DESIGN DECISION (VC-02 core): decouple punch participation from forced-public reachability

- **Flag ON (new default):** host is built with `libp2p.EnableHolePunching(holeOpts...)` **and `ForceReachabilityPrivate()`** — punching participation on, autorelay circuit publishing untouched. Punch initiation then follows go-libp2p v0.39.1's native rule (observed public addr + inbound relayed conn — the holepunch package imposes no reachability condition; Private is kept purely so autorelay keeps publishing circuits), which is the punchable-real-NAT condition.
- **Flag OFF (kill-switch, `--dart-define=MKNOON_ENABLE_DCUTR_UPGRADE=false`):** host is built **without** `libp2p.EnableHolePunching` — the node neither initiates nor answers `/libp2p/dcutr`. This makes the parked zero-punch invariant **structural** (it was only empirical-on-loopback before) while preserving every test-locked parked observable: Private reachability, published circuit addresses, zero `holepunch:*`/`transport:upgraded` events, circuit stays Limited, no conn thrash. Mixed fleets are safe: an ON peer punching toward an OFF peer fails protocol negotiation and the held circuit simply persists.
- **Test seam unchanged:** `forcePublicReachabilityForTests` (`node.go:117-124,:2155-2160`) still forces Public AND implies punch participation, so `holepunch_feasibility_test.go` keeps working.
- `dcutrReachabilityMode` becomes: `"public"` iff the test seam is set, else `"private"` (the flag no longer selects Public). New sibling helper `dcutrPunchingEnabled(enableDcutrUpgrade, forcePublicForTests) = flag || seam` gates the `EnableHolePunching` option.

**Refuted / do-NOT-re-introduce:**
- Do NOT re-couple flag-ON → `ForceReachabilityPublic` (TC-189-41 guards — the sole refuting mechanism; the feasibility comments' "forced-public hosts do not auto-hole-punch" is version-stale, above).
- Do NOT delete or blanket-invert `reachability_default_guard_test.go` / `no_circuit_recovery_test.go:176` — they guard a real behavior; re-point their *flag-default* assertion only.
- Do NOT treat `holepunch_negative_control_test.go` as a flag-off test after the flip — it runs DEFAULT flags (no explicit `FeatureFlags`), so post-flip it becomes the **flag-ON loopback inertness** sentinel (kept green as-is; the kill-switch gets its own explicit-OFF lock, TC-VC02-07).
- Do NOT cite `p2p_service_impl.dart:2578` / `node.go:1328` from the 188 docs — drifted; current seams are `:2612/:2665-2670` and `:1396/:1403` (digest correction).
- Do NOT hardcode gate pass counts (VC-00 rule 6) — capture green baselines at execution start.

---

## Real Scope

**In scope (VC-02, on VC-01's committed tree):**
- `lib/core/bridge/p2p_bridge_client.dart` — `enableDcutrUpgrade` `defaultValue: false → true` + comment re-point (`:72-79` on HEAD; re-verify on the VC-01 tree).
- `go-mknoon/node/feature_flags.go` — `DefaultFeatureFlags().EnableDcutrUpgrade: false → true` (`:89`) + field/func doc re-points (`:50-62,:75-79`).
- `go-mknoon/node/peer_session.go` — decouple: `dcutrReachabilityMode` returns "public" only for the test seam; add `dcutrPunchingEnabled` (`:20-25`).
- `go-mknoon/node/node.go` — gate `libp2p.EnableHolePunching(holeOpts...)` (`:403`) behind `dcutrPunchingEnabled(flags.EnableDcutrUpgrade, forcePublicReachability)`; reachability block `:393-396` structurally unchanged.
- Re-point EVERY pinned guard (full enumerated blast radius — repo-wide grep for `enableDcutrUpgrade|EnableDcutrUpgrade` is closed by this list): Go `feature_flags_runtime_test.go:46-57`, `reachability_default_guard_test.go:12-20`, `feature_flags_merge_test.go:44-51`, `dcutr_upgrade_flag_test.go:15-67`; Dart `test/core/bridge/p2p_bridge_client_test.dart:293-328` (9-key polarity pin), `test/core/services/p2p_service_dcutr_flag_test.dart:65-102`. Comment-only re-points: `no_circuit_recovery_test.go:170-176`, `holepunch_negative_control_test.go:3-9`, `integration_test/dcutr_upgrade_proof_test.dart:10-17`, `go-mknoon/node/config.go` (flag doc mention), **`holepunch_feasibility_test.go:104,:118,:140,:180`** (replace the version-stale "forced-public hosts do not auto-hole-punch" mechanism with the correct "loopback yields no public addr, so the puncher/handler is never constructed" reason — Root Cause 3; skip semantics unchanged).
- NEW Go test `go-mknoon/node/dcutr_killswitch_gate_test.go` (kill-switch structural lock, TC-VC02-07).
- NEW Go test `go-mknoon/node/holepunch_mixed_fleet_test.go` (mixed ON/OFF fleet inertness sentinel, P7/TC-VC02-09b).
- Harness registration: TWO new synthetic Go paths in `scripts/run_host_test_gates.sh` (the DCUtR/reachability/holepunch suite currently runs in NO gate = invisible coverage) + the rule-6 gate-doc quartet.
- Measurement: runsheet legs A/B/C (device↔emulator) + `VC-02-punch-rate-RESULTS.md` with a punch-rate-by-topology section; telemetry itself already exists end-to-end (`holepunch_tracer.go` → `go_bridge_client.dart` flow-event passthrough → `TransportMetrics` counters) — VC-02 verifies and captures, adds no telemetry code.
- Doc re-points: FDC-CONVERGENCE-CHECKLIST CV-13 (`:52`) + P4.4 DCUtR row (`:89`) annotated "executed by VC-02 under the VC-00 decision record"; TC-188-12 overturn recorded here (the 188 spec itself is a closed artifact — not rewritten).

**Out of scope → owning story:**
- Circuit-holding mechanics, `Protect()`/keepalive, relay `limits.go`, EC2 redeploy → **VC-01** (VC-02 consumes its held circuits and its already-redeployed relay).
- STUN/TURN for the un-punchable remainder (symmetric-CGNAT cellular↔cellular ≈0% punch — design assumption, VC-00 honesty note) → **VC-03**. DCUtR reduces TURN usage; it does not replace it.
- WebRTC/ICE anything → **VC-05+**.
- Any `go-relay-server/` change → **VC-01/VC-03/VC-06/VC-07**.

---

## Files To Inspect Next

**Production (edited):** `lib/core/bridge/p2p_bridge_client.dart` (:41-90 flag map); `go-mknoon/node/feature_flags.go` (:80-92 defaults, :112-137 merge); `go-mknoon/node/peer_session.go` (:9-25 mode fn); `go-mknoon/node/node.go` (:387-407 host opts; :117-124 test seam; :2149-2160 test setters).

**Dependency-only (NOT edited):** `go-mknoon/bridge/bridge.go` (:560,:582-584 flag decode — merge case for the key already exists); `go-mknoon/node/holepunch_tracer.go` (:39-121 emits, :159-179 dedup); `lib/core/bridge/go_bridge_client.dart` (:29-72 passthrough allowlist, :781-796 holepunch/transport cases); `lib/core/bridge/bridge.dart` (:61-81 payload-key allowlist — all five events already listed); `lib/core/services/p2p_service_impl.dart` (:3704-3755 diagnostic handler, :161-168 sticky map); `lib/core/debug/transport_metrics.dart` (:218-227 punch counters, :299-344 baselineReport).

**Direct tests (edited/re-pointed):** the six guard files listed in Real Scope + the new `dcutr_killswitch_gate_test.go`.

**Preservation tests (run, not edited):** `holepunch_negative_control_test.go`, `holepunch_tracer_test.go`, `holepunch_feasibility_test.go` (skip-tolerant), `peer_session_test.go`, `transport_label_test.go`, `test/core/services/p2p_service_transport_upgrade_test.dart`, `test/core/debug/transport_metrics_holepunch_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`.

**Harness:** `scripts/run_host_test_gates.sh` (:144-184 synthetic-path constants, :283-295 host-all plan, :394-466 print/run branches); `scripts/run_test_gates.sh` (ONE_TO_ONE array :67,:117,:118; classify_path :870; completeness :1067-1095); `scripts/check_reliability_simulation_discovery.sh` (:393 proof-test case); `integration_test/scripts/run_1to1_device_real.dart` (scenarios `fdc12_dcutr_relay_to_direct_upgrade`, `fdc12_dcutr_symmetric_cgnat_negative`).

**⚠ VC-01 drift caution (epic-adjudicated):** VC-01 edits the same flag files and adds a 10th flag (its hold-circuit kill-switch), so on the VC-01 committed tree the Dart polarity pin is expected to be a **10-key literal**. At execution start, re-verify every line anchor on the VC-01 committed tree; re-point ONLY the pin's `enableDcutrUpgrade` row (the test's name/key-count and the `hasLength(N)` count stay whatever VC-01 made them — key names, not counts or line numbers, are the stable anchors).

---

## Existing Tests Covering This Area

| Test (file::name) | Exists | Gate today | VC-02 disposition |
|---|---|---|---|
| `feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` (:46) | exists | host-all synthetic `-run 'FeatureFlag'` (`run_host_test_gates.sh:161-162`) | **RE-POINT (TC-VC02-03)** — dcutr assert flips to must-be-TRUE, failure msg cites the VC-00 decision record; LANMedia stays false |
| `reachability_default_guard_test.go::TestDefaultFlagsKeepPrivateReachability` (:12) | exists | **NO GATE (invisible)** | **RE-POINT (TC-VC02-05)** + register via new synthetic path — default flag now true AND mode stays "private" (assertion strengthens) |
| `feature_flags_merge_test.go` omitted-dcutr assert (:46-48) | exists | host-all `-run 'FeatureFlag'` | **RE-POINT (TC-VC02-04)** — omitted key keeps Go default **true** |
| `feature_flags_merge_test.go::TestMergeFeatureFlags_EveryStructFieldIsMergeable` (:61) | exists | host-all `-run 'FeatureFlag'` | stays green unmodified — drives `{key: !default}`, auto-adapts; post-flip it proves **explicit false wins** for dcutr (kill-switch merge leg) |
| `dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches` (:15) / `::TestDcutrFlagOn_SelectsUpgradeReachability` (:39) / `::TestDcutrFlag_PlumbsThroughNodeConfig` (:55) | exists | **NO GATE (invisible)** | **RE-POINT (TC-VC02-06)** + register — new table: mode(on,seamOff)=**private**, mode(off,seamOff)=private, mode(x,seamOn)=public; default assert flips; plumb test re-pointed to nil→true |
| `no_circuit_recovery_test.go::TestDefaultFlagsKeepPrivateReachability_CircuitPublished` (:176) | exists | **NO GATE (invisible)** | **PRESERVE through the flip (TC-VC02-08)** + register — the decoupling's key sentinel; comment-only re-point |
| `holepunch_negative_control_test.go::TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` (:62) | exists | **NO GATE (invisible)** | **PRESERVE (TC-VC02-09)** + register — runs default flags, so post-flip it locks flag-ON loopback inertness (header comment re-point only) |
| `holepunch_tracer_test.go` TC-188-03/:286, TC-188-10/:343, TC-188-11/:418 (+ :47,:115,:161,:244) | exists | **NO GATE (invisible)** | **PRESERVE (TC-VC02-10)** + register — 188 guards survive, never deleted |
| `holepunch_feasibility_test.go` (:78,:144) | exists | **NO GATE** | preserve; skip-tolerant; registered by the same `-run 'TestHolePunch'` sweep |
| `peer_session_test.go::TestPeerSession_RepointsToDirectConn` | exists | **NO GATE** | **PRESERVE** + register (exactly-once dedup partner) |
| `test/core/bridge/p2p_bridge_client_test.dart::pins exactly the 9 canonical keys…` (:294) | exists | 1to1 (`run_test_gates.sh:67`) + host 1to1 (`run_host_test_gates.sh:49`) + core-host-all glob | **RE-POINT (TC-VC02-01)** — `enableDcutrUpgrade: true` in the independent literal |
| `test/core/services/p2p_service_dcutr_flag_test.dart` TC-12-10 (:65) / TC-12-10b (:94) | exists | 1to1 (`run_test_gates.sh:118`) + core-host-all glob | **RE-POINT (TC-VC02-02)** — sent map + producer default assert true |
| `test/core/services/p2p_service_transport_upgrade_test.dart` (:131,:157,:187) | exists | 1to1 (`run_test_gates.sh:117`) + core-host-all | **PRESERVE (TC-VC02-11)** — sticky prime/clear unchanged |
| `test/core/debug/transport_metrics_holepunch_test.dart` + `transport_metrics_privacy_test.dart` | exists | core-host-all glob | **PRESERVE (TC-VC02-12)** — punch counters + privacy redaction unchanged |
| `integration_test/dcutr_upgrade_proof_test.dart` TC-12-12/TC-12-13 (@Tags(['device'])) | exists | classified (`check_reliability_simulation_discovery.sh:393`); orchestrator scenarios exist | **CONSUME (TC-VC02-13)** — the runsheet executes the CV-11 observation where punchable; header comment re-point (flag now default-ON) |

**Gaps this plan closes:** (a) no test anywhere asserts the flag-ON contract (default true end-to-end); (b) the kill-switch has NO mechanical teeth on HEAD (`EnableHolePunching` unconditional) and no lock; (c) the entire Go DCUtR/holepunch suite runs in **no gate** — invisible coverage, fixed by two new synthetic paths.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> "RED on baseline" below = the VC-01 committed tree; VC-01 does not touch this flag's polarity or the reachability seam, so these anchors equal HEAD unless noted. Go commands: `GOTOOLCHAIN=go1.25.0`, always via the pinned invocations (VC-00 rule 6).

1. **`test/core/bridge/p2p_bridge_client_test.dart::pins exactly the 9 canonical keys with intended polarity`** (re-point) — **TC-VC02-01**
   - Tier: unit/application (host).
   - Shape: existing independent literal (`:301-311`) edited: `'enableDcutrUpgrade': true`; reason string cites VC-00 decision record + VC-02.
   - RED on baseline because: `defaultResilienceFeatureFlags()` still returns `false` for the key (`p2p_bridge_client.dart:78`).
   - GREEN after fix asserts: exact key set (9 or VC-01's N) + polarity, dcutr row TRUE — the load-bearing Dart default sent wholesale to `node:start`.
   - Mutation that re-reds: revert `defaultValue: true → false` at `p2p_bridge_client.dart:76-79`.
   - Discriminator: the same test simultaneously pins the *other* 8 keys unchanged — a sibling-flag disturbance also reds here.
2. **`test/core/services/p2p_service_dcutr_flag_test.dart::TC-12-10 / TC-12-10b`** (re-point) — **TC-VC02-02**
   - Tier: unit/application (host; `_PayloadCapturingBridge` captures the literal `node:start` payload).
   - Shape: `:86-90` expect `flags['enableDcutrUpgrade']` **true** ("default-ON under the VC-00 Path-3 reversal; kill-switch: --dart-define=MKNOON_ENABLE_DCUTR_UPGRADE=false"); `:99-101` same for the producer map.
   - RED on baseline because: the sent map is built from the `bool.fromEnvironment` default = false.
   - GREEN asserts: the map **actually handed to the bridge** carries true (wire-level, not producer-only).
   - Mutation: same revert as TC-VC02-01 → both tests red (distinct observable: sent payload vs producer map).
3. **`go-mknoon/node/feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof`** (re-point) — **TC-VC02-03**
   - Tier: unit (Go).
   - Shape: `:51-53` inverted: `if !flags.EnableDcutrUpgrade { t.Fatal("EnableDcutrUpgrade must default TRUE — VC-00 Path-3 reversal decision record (2026-07-13) re-opened CV-13; VC-01 holds live 1:1 circuits, VC-02 flips the upgrade on. Kill-switch: explicit enableDcutrUpgrade=false.") }`; LANDial assert unchanged (true); LANMedia assert unchanged (false — its gate is CV-34, untouched).
   - RED on baseline because: `DefaultFeatureFlags()` returns false (`feature_flags.go:89`).
   - GREEN asserts: Go fallback parity with the Dart default.
   - Mutation: revert `feature_flags.go:89` `true → false`.
4. **`go-mknoon/node/feature_flags_merge_test.go`** omitted-key assert (re-point) — **TC-VC02-04**
   - Tier: unit (Go).
   - Shape: `:46-48` inverted: omitted `enableDcutrUpgrade` must keep Go default **true** (moves from the "omitted default-FALSE keys" block to the default-true block; LANMedia stays in the false block).
   - RED on baseline because: merge starts from `DefaultFeatureFlags()` = false.
   - GREEN asserts: partial-map decode cannot silently darken the newly-graduated flag (the 219 landmine, now protecting dcutr).
   - Mutation: revert `feature_flags.go:89`.
5. **`go-mknoon/node/reachability_default_guard_test.go::TestDefaultFlagsKeepPrivateReachability`** (re-point) — **TC-VC02-05**
   - Tier: unit (Go).
   - Shape: assert (a) `DefaultFeatureFlags().EnableDcutrUpgrade == true` (VC-02) AND (b) `dcutrReachabilityMode(flags.EnableDcutrUpgrade, false) == "private"` — the guard's REAL invariant (autorelay must stay eligible to publish `/p2p-circuit`) now holds **even with the flag ON**.
   - RED on baseline **twice, in sequence**: (a) reds until the Go default flips; then (b) reds until the decoupling lands (`dcutrReachabilityMode(true,false)` is "public" under the 188 coupling).
   - GREEN asserts: default flags → punching-enabled AND Private — the decoupling in one line.
   - Mutation: (a) revert `feature_flags.go:89` → red; (b) restore `enableDcutrUpgrade ||` into the mode function (`peer_session.go:21`) → red.
6. **`go-mknoon/node/dcutr_upgrade_flag_test.go`** (re-point all three) — **TC-VC02-06**
   - Tier: unit (Go).
   - Shape: TC-12-01 → default assert flips to true; mode table: `(off,seamOff)=private` (kept), `(off,seamOn)=public` (kept). TC-12-02 → `(on,seamOff)=`**`private`** ("the flag no longer forces Public; it gates EnableHolePunching — see dcutrPunchingEnabled; ForcePublic remains test-seam-only, TC-189-41"). TC-12-10-Go → nil `FeatureFlags` → `EffectiveFlags().EnableDcutrUpgrade == true`.
   - RED on baseline because: `dcutrReachabilityMode(true, false)` returns "public" (`peer_session.go:21-23`) and the defaults are false.
   - GREEN asserts: the full new function table + default.
   - Mutation: restore the coupling in `peer_session.go` → TC-12-02 red; revert `feature_flags.go:89` → TC-12-01/TC-12-10 red.
7. **`go-mknoon/node/dcutr_killswitch_gate_test.go`** (NEW file) — **TC-VC02-07**
   - Tier: unit + source-shape contract (Go; precedent: `libp2p_refactor_contract_test.go::TestGoLibp2pProductionShapeBudget`).
   - Shape: (a) `TestVC02Dcutr_PunchingEnabledTable` — `dcutrPunchingEnabled(false,false)==false`, `(true,false)==true`, `(false,true)==true`, `(true,true)==true`; (b) `TestVC02Dcutr_HolePunchOptionIsFlagGated` — **AST-level, not substring**: parse `node.go` with `go/parser`+`go/ast`, locate every `*ast.CallExpr` whose `Fun` selector is `EnableHolePunching`, and assert each call's enclosing statement chain contains an `*ast.IfStmt` whose `Cond` source contains `dcutrPunchingEnabled(`; FAIL if any such call sits inside the unconditional `hostOpts` composite/append without an enclosing guarded IfStmt. Mere co-presence of the two tokens in the file must NOT pass.
   - RED on baseline because: (a) fails to compile — `dcutrPunchingEnabled` does not exist (documented compile-RED; the missing symbol is named); (b) once the helper exists but the gate is not wired, the source scan finds `EnableHolePunching` unguarded at `node.go:403`.
   - GREEN asserts: kill-switch OFF structurally removes DCUtR participation (no punch initiation, no `/dcutr` answer); ON/seam restores it.
   - Mutations that re-red (BOTH named, both spot-run): (m1) make `EnableHolePunching` unconditional again (full revert of the `node.go` gate) → (b) red; (m2) **keep the `if dcutrPunchingEnabled(...)` block in place but hoist `libp2p.EnableHolePunching(holeOpts...)` back into the unconditional `hostOpts` list** → (b) must red — this is what the AST walk buys over a substring scan (a moved-call-site variant leaves both tokens present). Behavioral device partner: Runsheet **leg C** (below) proves zero `HOLEPUNCH_*` flow events on a real OFF build.
   - **Stop-if:** if (b) cannot be made to red on the baseline for the documented reason (e.g. VC-01 restructured the host-opts block), STOP and re-anchor the source-shape assertion before writing production code — do not ship a lock that was never red.

### Preserved (must STAY green — locked, not RED)

- **P1 / TC-VC02-08 (PROD-CRITICAL host sentinel):** `go-mknoon/integration/no_circuit_recovery_test.go::TestDefaultFlagsKeepPrivateReachability_CircuitPublished` — green on baseline, green after the flip: under the NEW default (flag ON) the node still publishes a real `/p2p-circuit` address against a live local relay. **This single test is what makes the default flip shippable.** Mutation: re-couple flag→Public → red (autorelay stops publishing). Comment-only re-point.
- **P2 / TC-VC02-09:** `holepunch_negative_control_test.go` — default-flag nodes (now ON) on loopback: zero attempts/successes, Limited circuit throughout, stable conn count, zero `transport:upgraded`. Locks "flag-ON does not thrash un-punchable topologies" (loopback = the un-punchable extreme; no observed public addr → puncher never engages). Header comment re-point only.
- **P3 / TC-VC02-10:** `holepunch_tracer_test.go` :286 (TC-188-03 peer-scoped) / :343 (TC-188-10 DirectDialEvt breadcrumb-only, never upgrades) / :418 (TC-188-11 exactly-once) + `peer_session_test.go::TestPeerSession_RepointsToDirectConn` — the 188 guards survive the reversal untouched.
- **P4 / TC-VC02-11:** `test/core/services/p2p_service_transport_upgrade_test.dart` — `transport:upgraded` primes sticky 'direct' (`p2p_service_impl.dart:3722-3737`); `transport:downgraded` reverts badge + clears sticky (`:3739-3753`).
- **P5 / TC-VC02-12:** `test/core/debug/transport_metrics_holepunch_test.dart` (attempt/success/failure counters + report lines feeding the RESULTS doc) + `transport_metrics_privacy_test.dart` (punch events carry no full peer ID/multiaddr).
- **P6:** `feature_flags_merge_test.go::TestMergeFeatureFlags_EveryStructFieldIsMergeable` — post-flip it drives `enableDcutrUpgrade:false` and asserts the field flips: the kill-switch's explicit-false-wins merge leg, for free.
- **P7 / TC-VC02-09b (NEW — mixed-fleet inertness sentinel):** `go-mknoon/node/holepunch_mixed_fleet_test.go::TestHolePunchMixedFleet_OnOffPair_CircuitStable` — same local-relay fixture as `holepunch_negative_control_test.go`; node1 built with **default flags (ON post-flip)**, node2 with explicit `FeatureFlags{EnableDcutrUpgrade:false}` (the staged-rollout old-build stand-in). Assert over the polled window: circuit stays Limited throughout, node2 emits ZERO `holepunch:*` events, node1's attempt (if any) yields failure-not-crash, conn count stable (±1), messaging over the circuit still delivers. **Honesty note:** on loopback neither side observes a public addr, so this is green-on-baseline by construction (a sentinel, not a RED lock — its structural teeth are TC-VC02-07); its value is locking mixed-fleet stability through the flip and future host-option churn. The ON→OFF protocol-negotiation graceful failure itself is verifier-confirmed against go-libp2p v0.39.1 source (OFF omits the `/dcutr` handler, `basic_host.go:264-284`; the ON initiator's `WithNoDial` stream open fails multistream in a single pass — no retry loop, `holepuncher.go:175-180`). The `-run 'TestHolePunch'` sweep of the new `GO_NODE_DCUTR` synthetic path registers it automatically.

---

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on baseline | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-VC02-01 Dart load-bearing default → true | flag-map polarity, sibling keys pinned | unit | `test/core/bridge/p2p_bridge_client_test.dart::pins exactly the 9 canonical keys…` | producer returns false (`p2p_bridge_client.dart:78`) | revert `:78` true→false | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:67`) + core-host-all AUTO glob |
| TC-VC02-02 sent `node:start` map carries true | wire-level payload | unit/application | `test/core/services/p2p_service_dcutr_flag_test.dart::TC-12-10/10b` | sent map built from false default | same revert | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:118`) + core-host-all AUTO |
| TC-VC02-03 Go fallback default → true | nil-map parity | unit (Go) | `feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` | `DefaultFeatureFlags()` false (`feature_flags.go:89`) | revert `:89` | `./scripts/run_host_test_gates.sh host-all` (synthetic `-run 'FeatureFlag'`) | existing `GO_NODE_FEATUREFLAGS` synthetic path (`run_host_test_gates.sh:161-162`) — name matches, AUTO |
| TC-VC02-04 omitted key keeps Go default true | partial-map decode seam | unit (Go) | `feature_flags_merge_test.go` omitted-dcutr assert | merge starts from false default | revert `:89` | `./scripts/run_host_test_gates.sh host-all` | existing `GO_NODE_FEATUREFLAGS` synthetic path — file IS the registered target |
| TC-VC02-05 default flags stay Private (guard re-point) | reachability policy under defaults | unit (Go) | `reachability_default_guard_test.go::TestDefaultFlagsKeepPrivateReachability` | default false; then mode(true,false)=="public" under 188 coupling | (a) revert `:89`; (b) restore coupling `peer_session.go:21` | `./scripts/run_host_test_gates.sh host-all` (NEW synthetic path) | **ADD `GO_NODE_DCUTR` synthetic path** (Step 7) |
| TC-VC02-06 flag→mode decoupled (function table) | mode(on,seamOff)=private; seam→public kept | unit (Go) | `dcutr_upgrade_flag_test.go` (all three re-pointed) | mode(true,false)=="public" on baseline | restore `enableDcutrUpgrade \|\|` in mode fn | `./scripts/run_host_test_gates.sh host-all` | **`GO_NODE_DCUTR` synthetic path** |
| TC-VC02-07 kill-switch structurally disables punching | OFF ⇒ no `EnableHolePunching` option | unit + source-shape (Go) | `dcutr_killswitch_gate_test.go::TestVC02Dcutr_PunchingEnabledTable` + `::TestVC02Dcutr_HolePunchOptionIsFlagGated` | helper absent (compile-RED); `EnableHolePunching` unconditional (`node.go:403`) | make the option unconditional again | `./scripts/run_host_test_gates.sh host-all` | **`GO_NODE_DCUTR` synthetic path** (`-run 'TestVC02'` covered) |
| TC-VC02-08 circuit publishing preserved under default-ON (**PROD-CRITICAL host sentinel**) | autorelay publishes `/p2p-circuit` vs real local relay | integration (Go, real relay hop) | `integration/no_circuit_recovery_test.go::TestDefaultFlagsKeepPrivateReachability_CircuitPublished` | n/a — preservation (green before AND after; reds under naive Public flip) | re-couple flag→Public → red | `./scripts/run_host_test_gates.sh host-all` (NEW synthetic path) | **ADD `GO_INTEGRATION_CIRCUIT_GUARD` synthetic path** (Step 7) |
| TC-VC02-09 flag-ON loopback inertness / no thrash | zero punches w/o public addr; Limited holds; stable conns | integration (Go, real relay) | `holepunch_negative_control_test.go::TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` | n/a — preservation (runs default flags = ON post-flip) | n/a — sentinel; its red = regression | `./scripts/run_host_test_gates.sh host-all` | **`GO_NODE_DCUTR` synthetic path** (`-run 'TestHolePunch'`) |
| TC-VC02-09b mixed ON/OFF fleet stays stable (staged-rollout shape) | held circuit persists; OFF node emits zero `holepunch:*`; no crash/thrash | integration (Go, real relay) | `holepunch_mixed_fleet_test.go::TestHolePunchMixedFleet_OnOffPair_CircuitStable` (NEW) | n/a — sentinel, green-on-baseline by construction (loopback = no public addr; see P7 honesty note) | n/a — sentinel; structural teeth are TC-VC02-07 | `./scripts/run_host_test_gates.sh host-all` | **`GO_NODE_DCUTR` synthetic path** (`-run 'TestHolePunch'` sweeps the name) |
| TC-VC02-10 188 tracer guards survive | peer-scoped / breadcrumb-only / exactly-once | unit (Go) | `holepunch_tracer_test.go` :286/:343/:418 + `peer_session_test.go::TestPeerSession_RepointsToDirectConn` | n/a — preservation | n/a — sentinels | `./scripts/run_host_test_gates.sh host-all` | **`GO_NODE_DCUTR` synthetic path** (`-run 'TestHolePunch\|TestPeerSession'`) |
| TC-VC02-11 sticky 'direct' primed on upgrade, cleared on downgrade | Dart consumption of upgrade telemetry | unit | `test/core/services/p2p_service_transport_upgrade_test.dart` | n/a — preservation | n/a — sentinel | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:117`) |
| TC-VC02-12 punch counters + privacy redaction | metrics vehicle for the RESULTS doc | unit | `test/core/debug/transport_metrics_holepunch_test.dart` + `transport_metrics_privacy_test.dart` | n/a — preservation | n/a — sentinels | `./scripts/run_host_test_gates.sh core-host-all` | AUTO glob (`test/core/debug/`) |
| TC-VC02-13 device: punch telemetry + upgrade where punchable + graceful fallback (**PROD-CRITICAL wire leg**) | real NAT punch / fallback / kill-switch | device-proof + measurement | Runsheet legs A/B/C (below) + `integration_test/dcutr_upgrade_proof_test.dart::TC-12-12/TC-12-13` | n/a — device tier; host physically cannot punch (no real NAT) | flag off (leg C) must zero the events → proves the switch | Execution Environment cmds + `./scripts/check_reliability_simulation_discovery.sh` | proof test already classified (`check_reliability_simulation_discovery.sh:393`) + orchestrator `--scenario fdc12_dcutr_*` cases exist; RESULTS doc is a measurement artifact (no gate) |
| TC-VC02-14 doc re-points (CV-13/P4.4 executed; TC-188-12 overturned) | epic bookkeeping | doc artifact | FDC-CONVERGENCE-CHECKLIST.md `:52,:89` annotations + this plan's Source Of Truth | n/a — doc | n/a — doc | `grep -n "VC-02" Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-CONVERGENCE-CHECKLIST.md` (non-empty) | n/a — doc |
| Regression floor | no 1:1/transport/baseline breakage | gate | full suites | n/a | n/a | `./scripts/run_test_gates.sh 1to1` + `baseline`; `./scripts/run_host_test_gates.sh host-all` + `core-host-all` | n/a |

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** VC-02 adds **no new derived state**. The sticky `'direct'` cache primed by `transport:upgraded` is pre-existing, RAM-only-by-design with a 10-min TTL (`p2p_service_impl.dart:161-168`), and its prime/clear lifecycle is locked by TC-VC02-11; on process restart the next punch re-primes it (self-healing by construction, no persistence intended). → **TC-VC02-11 + justified N/A for new rows.**
- **Sibling-surface consistency:** the "gate" edited here is the feature-flag map — the parallel surfaces are the *other 8 flags*. The exact-key-set + per-key polarity pin (TC-VC02-01) and the Go merge completeness test (P6) fail if any sibling key is disturbed, dropped, or spuriously flipped. → **TC-VC02-01 / P6.**
- **Destructive-action side-effects:** VC-02 deletes nothing and adds no cleanup path. The nearest analogue — the punched direct leg **dying** — is a transition, covered below. → **justified N/A.**
- **Invariant re-verification under new transitions:** the new transition is *punched-direct-conn appears / dies* on a held circuit. On appear: exactly-once upgrade, peer-scoped, sticky primed (TC-VC02-10/11). On die: `transport:downgraded` reverts the badge AND clears sticky so sends re-probe instead of reusing a dead leg (TC-VC02-11), and the VC-01 held circuit — whose `Protect()` is **peer-scoped**, not conn-scoped — survives as the fallback (runsheet leg A asserts messaging continues over the circuit after a punch failure; TC-188-03 locks that a co-resident circuit is untouched by a success). → **TC-VC02-10/11 + leg A.**

## Invariants (locked by tests)

- INV-VC02-1: default builds participate in DCUtR — Dart default true, sent map true, Go fallback true, omitted-key merge true → TC-VC02-01/02/03/04.
- INV-VC02-2: reachability is Private under ALL flag states (Public is test-seam-only); autorelay circuit publishing survives the flip → TC-VC02-05/06/08.
- INV-VC02-3: kill-switch OFF structurally removes DCUtR participation (no `EnableHolePunching`), and explicit false wins the merge → TC-VC02-07 + P6 + runsheet leg C.
- INV-VC02-4: `transport:upgraded` is exactly-once, peer-scoped; `DirectDialEvt` never upgrades → TC-VC02-10 (188 guards, unchanged).
- INV-VC02-5: upgrade primes sticky 'direct'; downgrade clears it → TC-VC02-11.
- INV-VC02-6: un-punchable topologies stay inert and un-thrashed on the held circuit → TC-VC02-09 (host extreme) + runsheet leg A (device).
- INV-VC02-7: mixed ON/OFF fleets (staged rollout) never disturb a held circuit; the OFF peer neither initiates nor answers `/dcutr` → TC-VC02-09b (sentinel) + TC-VC02-07 (structural).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above (sentinels P1-P7 are locked-green, not RED).

---

## Execution Environment  (VC-00 rule 1 — restated)

The implementing agent runs the full loop end-to-end on a **USB-connected Android device + Android emulator**. iOS simulators/devices are NOT part of this rig; there is no iOS-boundary code in VC-02 (the flag is a cross-platform dart-define), so no iOS deferral row is needed beyond noting that iOS punch-rate field data is future VC-09 material.

```bash
# 0) Rig discovery
adb devices -l                 # e.g. USB device serial 21071FDF600CSC + emulator-5554
flutter devices

# 1) Host gates (dev rig has Go; the GOTOOLCHAIN pin is mandatory — Go 1.26.x quic-go panic)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestDcutrFlag|TestDefaultFlagsKeepPrivateReachability|TestVC02Dcutr|TestHolePunch|TestPeerSession' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./integration -run '^TestDefaultFlagsKeepPrivateReachability_CircuitPublished$' -count=1)

# 2) Single-device proof rows (device tier; run on the USB device, then the emulator)
flutter test integration_test/dcutr_upgrade_proof_test.dart -d <usbSerial> --dart-define=FDC_DCUTR_DEVICE_PROOF=1

# 3) Two-party orchestrator convention (comma-separated -d; scenario ids are discovery-locked)
dart run integration_test/scripts/run_1to1_device_real.dart \
  --scenario fdc12_dcutr_relay_to_direct_upgrade -d <usbSerial>,<emulatorSerial>
dart run integration_test/scripts/run_1to1_device_real.dart --scenario all --list-scenarios   # discovery contract check

# 4) Which party runs where (rule-1 topology):
#    USB device  = cellular/hotspot party (real NAT; the punch-realistic side)
#    emulator    = host-WiFi NAT party (10.0.2.x double NAT; may never punch — that is leg A's point)
```

**Relay for all device legs:** the app-default `mknoun.xyz` pair (`/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…` + `/udp/4002/quic-v1/…`, `run_test_gates.sh:567`), **as redeployed by VC-01** (raised circuit limits). VC-02 must verify VC-01's relay redeploy is live before leg A (a held circuit surviving >2 min is VC-01's live gate).

---

## Step-By-Step Implementation Plan  (RED first)

> **Stop-if (entry blocker):** VC-01 is not merged with its gates green and its EC2 relay redeploy verified → **do not start** (collision map: same flag files, same guard files, strictly sequential). Snapshot `git status --short` and capture green baselines: `./scripts/run_test_gates.sh 1to1`, `./scripts/run_host_test_gates.sh host-all`, `flutter analyze` count — record actual numbers in Execution Progress (never hardcoded here, VC-00 rule 6).

1. **Anchor re-verification on the VC-01 tree.** Re-open every cited file:line (they WILL have drifted — VC-01 edits `node.go:387-403`, `feature_flags.go`, the Dart flag map, and may have grown the polarity pin to 10 keys). Adjust test edits accordingly; the *key names* are the stable anchors.
2. **RED — Dart re-points (TC-VC02-01/02).** Edit the two Dart test files to the flag-ON contract. Run:
   `flutter test test/core/bridge/p2p_bridge_client_test.dart test/core/services/p2p_service_dcutr_flag_test.dart` → both FAIL, each for its documented reason (producer false / sent-map false).
3. **RED — Go re-points (TC-VC02-03/04/05/06).** Edit the four Go guard files to the new contract. Run the pinned node invocation (Execution Environment §1) → FAIL for: default false ×3, mode(true,false)=="public" ×2. **Wording guard (L6):** every re-pointed comment and failure message states the corrected mechanism — "ForcePublic kills autorelay reservations/circuit publishing, so the node never receives the inbound relayed conns that trigger initiation (and relay messaging breaks)" — NEVER the version-stale "forced-public hosts do not auto-hole-punch / puncher only built for Private hosts" (gate removed in go-libp2p v0.37.0; Root Cause 3). Include the comment-only re-point of `holepunch_feasibility_test.go:104,:118,:140,:180` to the "loopback yields no public addr" reason.
4. **RED — new kill-switch lock (TC-VC02-07).** Add `dcutr_killswitch_gate_test.go`. Expect compile-RED naming `dcutrPunchingEnabled`, then (after Step 6a) the AST source-shape RED on the unguarded `EnableHolePunching`. **Stop-if** it cannot red for the documented reason → re-anchor before proceeding.
   4b. **NEW mixed-fleet sentinel (P7/TC-VC02-09b).** Author `holepunch_mixed_fleet_test.go` (green-on-baseline by construction — P7 honesty note); it rides the same `-run 'TestHolePunch'` sweep from Step 7 onward.
5. **GREEN A — default flips.** `p2p_bridge_client.dart` `defaultValue: false → true` + comment re-point (kill-switch knob documented); `feature_flags.go:89` `false → true` + field/`DefaultFeatureFlags` doc re-points. TC-VC02-01/02/03/04 green; TC-VC02-05 half-green. **Slice boundary check:** TC-VC02-05(b)/06/07 must still be RED after GREEN A — if any went green, the flip did more than the polarity change; stop.
6. **GREEN B — decoupling.** (a) `peer_session.go`: `dcutrReachabilityMode` → seam-only "public"; add `dcutrPunchingEnabled`. (b) `node.go`: wrap the `EnableHolePunching(holeOpts...)` option in `if dcutrPunchingEnabled(flags.EnableDcutrUpgrade, forcePublicReachability)`; leave `:393-396` reachability block and `:387-392` tracer wiring intact. TC-VC02-05/06/07 green. **Stop-if:** any preservation sentinel (negative control, tracer trio, CircuitPublished) reds here → the decoupling is wrong; replan, do not hack the sentinel.
7. **Registration (the invisible-coverage fix).** In `scripts/run_host_test_gates.sh`, copy the synthetic-path pattern (`:144-184`): add `GO_NODE_DCUTR_TEST="go-mknoon/node/dcutr_upgrade_flag_test.go"` with `GO_NODE_DCUTR_RUN='TestDcutrFlag|TestDefaultFlagsKeepPrivateReachability|TestVC02Dcutr|TestHolePunch|TestPeerSession'`, and `GO_INTEGRATION_CIRCUIT_GUARD_TEST="go-mknoon/integration/no_circuit_recovery_test.go"` with `GO_INTEGRATION_CIRCUIT_GUARD_RUN='^TestDefaultFlagsKeepPrivateReachability_CircuitPublished$'` (command shape `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./integration -run '<RUN>' -count=1)`); add both to the host-all plan block (`:283-295`), matchers, `print_command_for_path` (`:394`) and `run_path` (`:431`) branches. Verify: `./scripts/run_host_test_gates.sh host-all --list` shows both paths. Rule-6 quartet: update `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` alongside (the named host-all gate changed). Note: `-run 'TestHolePunch'` deliberately sweeps the skip-tolerant feasibility pair (they SKIP, never fail, when loopback doesn't punch) and the ~10s negative control — accepted gate cost for making the 188 guards visible.
8. **Direct → preservation → named gates.** Re-run Step 2/3/4 commands (all green); preservation sentinels (Execution Environment §1 + the two Dart preservation files); then `./scripts/run_test_gates.sh 1to1`, `baseline`, `./scripts/run_host_test_gates.sh host-all`, `core-host-all`, `./scripts/run_test_gates.sh completeness-check`, `./scripts/check_reliability_simulation_discovery.sh`. Run every named mutation and confirm re-RED, then revert the mutations.
9. **Device measurement (runsheet A/B/C below)** → write `VC-02-punch-rate-RESULTS.md`.
10. **Doc re-points (TC-VC02-14).** Annotate FDC-CONVERGENCE-CHECKLIST CV-13 (`:52`) and P4.4 DCUtR row (`:89`): "flip executed by VC-02 under the VC-00 Path-3 reversal decision record (2026-07-13)". Annotate CV-11 (`:66`) with the honesty scope: "leg-B device evidence is LAN-adjacent; real cross-NAT punch SUCCESS not observed on this rig — deferred-not-waived, owner VC-09 field telemetry rollup (holepunch:success by network class) or a two-physical-network runsheet addendum" so CV-11 does not read as device-closed. Tick the VC-00 metrics-table punch row as owned/delivered.

---

## Measurement Runsheet + Metrics ownership

**VC-00 metrics row owned by VC-02:** *"Punch attempt/success/failure by transport & network class — holepunch tracer → flow events; field runsheet results doc."* Vehicles (all existing, verified): Go tracer events `holepunch:attempt|success|failure`, `transport:upgraded {elapsedMs,rttMs}` (`holepunch_tracer.go:49,:57,:66,:87-93,:97,:107`) → Dart flow events `HOLEPUNCH_*` / `TRANSPORT_UPGRADED` (`go_bridge_client.dart:781-796`) → `TransportMetrics` counters + `baselineReport()` punch lines (`transport_metrics.dart:218-227,:299-344`, surfaced in the debug Settings diagnostics card). Flow logging in profile builds: **force-on via `--dart-define=FDC_FLOW_LOG=1`** (`lib/main.dart:320-330` — the gate is the mutable `flowEventLoggingEnabled`, NOT kDebugMode-only).

Format follows FDC-S0 conventions (frozen commit hash, same-vehicle/same-scenario re-measure, median never mean, per-topology rows, deferred-not-waived marks). RESULTS doc: `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-02-punch-rate-RESULTS.md`.

**Build (all legs):** `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1` (+ per-leg defines below). **Cycle protocol: each leg = N≥5 independent cycles** (fresh app start on both parties, new circuit established each cycle); leg tables report attempts / successes / upgrades **out of N**; elapsedMs/rttMs = median across successful punch cycles (FDC-S0: median never mean); leg C = zero events across **all** N cycles. Capture, per party, started BEFORE acting:
`adb -s <serial> logcat -v time | grep -E 'FLOW.*(HOLEPUNCH_ATTEMPT|HOLEPUNCH_SUCCESS|HOLEPUNCH_FAILURE|TRANSPORT_UPGRADED|TRANSPORT_DOWNGRADED|MSG_RECEIVED_TRANSPORT)' | tee vc02-<leg>-<party>.log`

**Honest per-topology expectations (what each leg can and cannot prove):**

| Leg | Topology | Extra defines | Expected / asserted | What it CANNOT prove |
|---|---|---|---|---|
| **A** | USB device on **cellular/hotspot** ↔ emulator on **host WiFi NAT** (10.0.2.x double NAT) | — | VC-01 circuit holds; `HOLEPUNCH_ATTEMPT` fires on ≥1 side once identify observes a public addr; **upgrade may legitimately NEVER land** (emulator NAT is effectively un-punchable) → assert `HOLEPUNCH_FAILURE`/no-upgrade is **graceful**: messaging continues over the held circuit, **≤1 `TRANSPORT_DOWNGRADED` per punch-failure cycle and stable conn count (±1) over a 2-minute observation window per cycle**, badge stays relay | punch SUCCESS (topology-limited) |
| **B** | device + host on the **same WiFi** (LAN-adjacent), emulator party; **LAN lanes disabled** so DCUtR gets the relay conn: `--dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=false`. **Direction note:** warm the circuit so the **emulator holds the inbound relayed conn** (initiator side — it can reach the device's `192.168.x` identify listen addr; the device dialing the emulator's `10.0.2.15` always fails) | LAN-dial off | circuit via relay, then upgrade — **may-fail-honest, route-recorded**: v0.39.1 DCUtR CONNECT exchanges ONLY public addrs, so a literal same-NAT punch toward the shared WAN IP needs router **hairpinning** (many consumer routers refuse); the likelier close is go-libp2p's **direct-dial-first shortcut** (`holepuncher.go:107-128`, dials peerstore addrs incl. private identify addrs). EITHER route ends in `TRANSPORT_UPGRADED` (emitted by `peerSessionNotifiee` on the wasLimited transition) → sticky primed → next send's `MSG_RECEIVED_TRANSPORT:"direct"`. Record WHICH route closed each cycle (direct-dial shows `DirectDialEvt` breadcrumb, TC-188-10; tracer punch elapsedMs/rttMs medians may then be absent — record "n/a (direct-dial route)"). Zero upgrades across all N cycles → Stop-if below | real cross-NAT punch rate (LAN-adjacent is the friendly case; hairpin-dependent) |
| **C** | same as B, **kill-switch build**: `--dart-define=MKNOON_ENABLE_DCUTR_UPGRADE=false` | flag off | ZERO `HOLEPUNCH_*`/`TRANSPORT_UPGRADED` events over the identical choreography; transport stays relay; messaging unaffected — the behavioral kill-switch proof (partner of TC-VC02-07) | n/a (negative leg) |
| — | cellular↔cellular symmetric CGNAT | — | **NOT MEASURED on this rig** — ≈0% punch is a design assumption (VC-00 honesty note); those calls are VC-03 TURN's job. Recorded as a stated assumption row in the RESULTS doc, deferred-not-waived | — |

RESULTS doc punch-rate section: per-leg table of attempts / successes / failures / upgrades **out of N cycles** with the upgrade route per cycle (punch vs direct-dial), success elapsedMs median, plus the diagnostics-card `baselineReport()` punch lines from each party. Add one latency-anchor row: **leg B ping-RTT over the held circuit (pre-upgrade) vs over the direct conn (post-upgrade), median of ≥5 pings each, same session**, via the existing `peer:ping` chain (`go_bridge_client.dart:140`, `p2p_bridge_client.dart:365`) — grounds the "relay pays double latency" motivation. Add one explicit deferred row: **"real cross-NAT punch SUCCESS (device-on-cellular ↔ party on a different physical network): NOT OBSERVED on this rig — deferred-not-waived; owner: VC-09 field telemetry rollup (holepunch:success rate by network class) or a two-physical-network runsheet addendum when a second host is available"** (mirrored into the CV-11 annotation, Step 10).

**Stop-ifs (design escalation — same path for both):**
- **Zero-attempt:** leg B shows zero `HOLEPUNCH_ATTEMPT` on a healthy held circuit across all N cycles → the puncher is not engaging. Investigate **observed-addr plumbing first**: v0.39.1 initiation is gated only on a public addr in `listenAddrs()` (incl. identify `OwnObservedAddrs`) plus an inbound relayed conn — NOT on reachability policy. Do NOT hack `ForceReachabilityPublic` back in (refuted); record the evidence and escalate a reachability-policy decision (e.g. AutoNAT-assisted "auto" mode) to VC-00 before flag graduation ships.
- **Attempts-without-payoff (partial win):** leg B shows ≥1 `HOLEPUNCH_ATTEMPT` but zero `TRANSPORT_UPGRADED` across all N cycles (neither punch nor direct-dial route closes) → STOP, record evidence (incl. hairpin suspicion per the leg-B note), escalate to VC-00 before flag graduation ships. The default flip does NOT ship on "legs executed" alone.

## Working Piece On Close

A flag-ON (now default) build **attempts DCUtR on VC-01's held circuits**. Where the pair is upgradeable (leg B — via a literal punch or go-libp2p's direct-dial shortcut, route recorded), `transport:upgraded` is observed end-to-end — Go tracer/session Notifiee → flow event → sticky 'direct' primed → the next message demonstrably rides direct QUIC (`MSG_RECEIVED_TRANSPORT:"direct"`). Where not punchable (leg A), calls/messaging degrade gracefully to the held circuit with failure telemetry, no thrash. `--dart-define=MKNOON_ENABLE_DCUTR_UPGRADE=false` provably restores parked behavior (structural host lock + device leg C). Punch attempt/success/failure rates per topology are captured in `VC-02-punch-rate-RESULTS.md`. This is the transport floor VC-05's audio calls build on: media follows the same upgraded-or-held path.

## EC2 Redeploy & Live Verification — N/A (consumed, not owned)

VC-02 touches **no `go-relay-server/` file**, so VC-00 rule 2's redeploy gate does not bind here. It **depends on** VC-01's completed redeploy (raised circuit limits on `mknoun.xyz` / 13.60.15.36): the runsheet's precondition step verifies a held circuit survives >2 min against the deployed relay (VC-01's live gate) before any punch leg runs. Rollback of relay behavior is VC-01's runbook; VC-02's own rollback is the kill-switch define + reverting the two default lines.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| Naive Public flip re-creates the spec-189 NO_CIRCUIT wedge fleet-wide | TC-VC02-05/08 (guards re-pointed, not inverted; CircuitPublished stays green through the flip) |
| Fleet-Public starves punch initiation (no reservations → no `/p2p-circuit` addrs → no inbound relayed conns → the `holepuncher.go:266` trigger never fires; NO_CIRCUIT mechanism, NOT a puncher-construction rule) | Design Decision + TC-VC02-06 (mode(on)=private locked) |
| Staged rollout produces mixed ON↔OFF fleets (old builds vs new default) | TC-VC02-09b (loopback inertness sentinel) + verifier-confirmed v0.39.1 source: OFF omits the `/dcutr` handler entirely (`basic_host.go:264-284`); ON-initiated stream open fails multistream negotiation in a single pass, no retry loop, circuit persists |
| Leg B same-NAT upgrade is hairpin/direction-dependent (DCUtR exchanges only public addrs) | leg B honest expectations + route recording (punch vs direct-dial) + partial-win Stop-if |
| Kill-switch is cosmetic (punching continues under OFF) | TC-VC02-07 (structural) + runsheet leg C (behavioral) |
| Partial flag map darkens the newly-graduated flag | TC-VC02-04 + P6 (merge seam) |
| Punched direct leg dies mid-session → stale sticky/badge | TC-VC02-11 (downgrade clears both); VC-01 circuit survives (peer-scoped protect; TC-188-03) |
| Upgrade double-count across tracer + session Notifiee | TC-VC02-10 (TC-188-11 exactly-once, untouched) |
| Flag-ON thrash on un-punchable topologies | TC-VC02-09 (loopback extreme) + leg A (device) |
| Private-reachability puncher never engages on real NAT (observed-addr threshold) | leg B Stop-if → escalation path defined (no ForcePublic hack) |
| VC-01 tree drift invalidates line anchors / 9-key pin shape | Step 1 re-verification (key names are the stable anchors) |
| Gate time/flake from newly-registered loopback-relay Go tests | feasibility tests are skip-tolerant by design; negative control is deterministic (no public addr on loopback); accepted, noted in Step 7 |

## Device/Relay Proof Profile

- **Host-only closure:** flag polarity end-to-end, decoupling, kill-switch structure, all guard re-points, circuit-publishing preservation (TC-VC02-01..12, 14).
- **Requires device (NOT host-closable):** actual punch + upgrade + graceful-fallback behavior — runsheet legs A/B/C on the rule-1 rig (TC-VC02-13, PROD-CRITICAL: **do NOT treat host coverage as sufficient for the wire leg**). `integration_test/dcutr_upgrade_proof_test.dart` rows (TC-12-12/13) are executed-by-observation via the runsheet; the symmetric-CGNAT negative (TC-12-13) remains deferred-not-waived (no CGNAT pair on this rig — VC-03 owns those calls regardless).
- Closure scenario runner: `/sims 1to1 --list` shows the dcutr rows (`--only N`); `/sims` is a runner, never a registrar — registration is already in place (`check_reliability_simulation_discovery.sh:393`).
- Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (+ quic-v1 :4002 sibling).

---

## Acceptance Gates  (LITERAL — copy/paste)

```bash
# 0) Execution-start snapshot + baselines (VC-00 rule 6 — capture, never hardcode)
git status --short | tee /tmp/vc02-dirty-tree.txt
./scripts/run_test_gates.sh 1to1                    # capture green baseline count (VC-01 tree)
./scripts/run_host_test_gates.sh host-all --list    # baseline plan (pre-registration)
flutter analyze                                     # record baseline issue count (dirty tree)

# 1) RED (before production edits) — each must FAIL for its documented reason
flutter test test/core/bridge/p2p_bridge_client_test.dart --plain-name 'pins exactly the 9 canonical keys with intended polarity'
flutter test test/core/services/p2p_service_dcutr_flag_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof|TestMergeFeatureFlags|TestDefaultFlagsKeepPrivateReachability|TestDcutrFlag|TestVC02Dcutr' -count=1)

# 2) Direct GREEN (after Steps 5-6) — same three commands, all pass

# 3) Preservation sentinels (must stay green; zero edits beyond comments)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestHolePunch|TestPeerSession' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./integration -run '^TestDefaultFlagsKeepPrivateReachability_CircuitPublished$' -count=1)
flutter test test/core/services/p2p_service_transport_upgrade_test.dart \
             test/core/debug/transport_metrics_holepunch_test.dart \
             test/core/debug/transport_metrics_privacy_test.dart

# 4) Named gates (counts vs the Step-0 captured baselines; deltas must equal the re-pointed set only)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
./scripts/run_host_test_gates.sh host-all           # now includes the TWO new synthetic Go paths
./scripts/run_host_test_gates.sh core-host-all

# 5) Registration proof (no invisible tests)
./scripts/run_host_test_gates.sh host-all --list | grep -E 'dcutr_upgrade_flag_test|no_circuit_recovery_test'   # both listed
./scripts/run_test_gates.sh completeness-check      # every *_test.dart classifies (no new Dart files expected)
./scripts/check_reliability_simulation_discovery.sh # dcutr proof rows still listed

# 6) Mutation re-RED spot-runs (each then reverted):
#    p2p_bridge_client.dart:78 true→false  → step-1 Dart cmds red
#    feature_flags.go DefaultFeatureFlags dcutr true→false → step-1 Go cmd red
#    peer_session.go re-add `enableDcutrUpgrade ||` to mode fn → TestDcutrFlagOn + reachability guard red
#    node.go EnableHolePunching unconditional → TestVC02Dcutr_HolePunchOptionIsFlagGated red

# 7) Hygiene
flutter analyze            # 0 new vs Step-0 baseline
git diff --check

# 8) Device measurement (rule-1 rig; see Runsheet legs A/B/C) → VC-02-punch-rate-RESULTS.md written
```

## Known-Failure Interpretation

- **Expected RED (pre-fix):** the step-1 commands, each for its catalogued reason. TC-VC02-07(a) is a compile-RED naming `dcutrPunchingEnabled` — expected.
- **Expected count deltas:** 1to1 / host-all totals shift by exactly the re-pointed assertions + the two newly-registered synthetic paths — diff the named tests against the Step-0 baseline, not raw counts.
- **Pre-existing dirty tree:** whatever `/tmp/vc02-dirty-tree.txt` recorded — preserve, never revert/absorb/reformat.
- **Environment blockers (NOT product):** no Go toolchain / no adb devices in a container ≠ failure — run host gates where Flutter+Go exist, device legs on the rig. `holepunch_feasibility_*` SKIPs on loopback are by-design. Leg A producing zero punch **successes** is expected topology physics, not a bug (attempts + graceful fallback are the assertions).
- **Device proof-test disposition:** `integration_test/dcutr_upgrade_proof_test.dart` rows may legitimately SKIP on the un-punchable leg-A topology — expected, record the skip. On the leg-B topology the upgrade row must pass (either route); if it cannot across all N cycles, that IS the leg-B Stop-if, not an ignorable skip.
- **Environment sensitivity of the loopback sentinels (pre-existing, not a VC-02 regression):** on a machine with a genuinely public IP or a working NATPortMap/UPnP mapping, `listenAddrs()` can become non-empty and the exactly-0-attempts assertions (`holepunch_negative_control_test.go:124-131`, P7 mixed-fleet) are environment-sensitive — same exposure exists on HEAD today; interpret a red there against this note before blaming the flip.
- **Scope drift (BLOCKING):** any red outside the enumerated blast radius (13 files reference the flag — closed list in Real Scope), any `go-relay-server/` diff, any `warmPeer`/keepalive/`Protect()` edit (VC-01's), any new `call_*`/WebRTC code (VC-04/05's).

## Done Criteria

- [ ] Step-0 snapshot + baselines recorded in Execution Progress.
- [ ] TC-VC02-01..07 authored RED-first on the VC-01 tree, each red for its documented reason, then green.
- [ ] Every production edit mutation-verified (the four §6 mutations re-red their locks, then reverted).
- [ ] Preservation sentinels green: TC-VC02-08..12 + P6 + P7/TC-VC02-09b (CircuitPublished, negative control, mixed-fleet, 188 tracer trio, peer-session dedup, Dart sticky, metrics/privacy, merge completeness).
- [ ] Both new synthetic Go paths registered and visible in `host-all --list`; rule-6 doc quartet updated; `completeness-check` + discovery script green.
- [ ] Runsheet legs A/B/C executed on the USB-device+emulator rig, **N≥5 cycles each**; logs saved; `VC-02-punch-rate-RESULTS.md` written with the punch-rate-by-topology section, the leg-B relay-vs-direct RTT row, the stated CGNAT assumption row, AND the "real cross-NAT punch success NOT OBSERVED — deferred-not-waived (owner VC-09 / two-network addendum)" row.
- [ ] **Leg B payoff bound:** `TRANSPORT_UPGRADED` observed end-to-end plus next-send `MSG_RECEIVED_TRANSPORT:"direct"` (punch or direct-dial route, route recorded per cycle) — OR a recorded VC-00 escalation per the runsheet Stop-ifs. "Legs executed, RESULTS written" alone does NOT tick this box.
- [ ] Automated device proofs bound in: Execution Environment §2 run on both the USB device and the emulator, and §3 `fdc12_dcutr_relay_to_direct_upgrade` orchestrator run — exit 0 (or documented expected-skip per Known-Failure Interpretation); command outputs attached to `VC-02-punch-rate-RESULTS.md`.
- [ ] Kill-switch proven twice: structural (TC-VC02-07, both mutations m1/m2 spot-run) + behavioral (leg C zero punch events across all N cycles).
- [ ] CV-13 / P4.4 checklist rows annotated; CV-11 annotated with the cross-NAT deferred-not-waived scope; TC-188-12 overturn recorded (Source Of Truth).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")

- Do NOT edit `go-relay-server/` (VC-01 owns limits; VC-03 owns TURN; rule-2 redeploys belong to them).
- Do NOT touch circuit-holding mechanics: `warmPeer`, `active_peer_keepalive_use_case.dart`, `Protect()`/`TagPeer`, `DialPeerViaRelay` internals — **VC-01** owns them.
- Do NOT add WebRTC/ICE/`call_*` anything — **VC-04/VC-05**.
- Do NOT re-couple flag-ON → `ForceReachabilityPublic`, delete the TC-189-41 guards, or invert them wholesale — re-point the flag-default assertion only.
- Do NOT delete any 188-era guard; every pin is re-pointed with a `// VC-02:` rationale.
- Do NOT flip `enableLibp2pLANMedia` or any sibling flag (its gate is CV-34, not this decision record).
- Do NOT hardcode gate pass counts or rewrite the analyzer baseline.
- Do NOT run concurrently with any story editing `feature_flags.go` / `p2p_bridge_client.dart` flag map (VC-00 collision map: flag files are shared state — sequential, small rebases expected).

## Accepted Differences / Intentionally Out Of Scope

- **Flag-ON default host options are intentionally near-identical to HEAD's** (EnableHolePunching + Private): the enablement was latently present; VC-02's real deltas are (a) held circuits to act on (VC-01), (b) a kill-switch with mechanical teeth, (c) re-pointed intent + measurement. Stated openly so reviewers don't hunt for a phantom Go behavior diff on the default path.
- **The flag's SEMANTIC changes** from "force Public reachability" (broken for production, per Root Cause) to "participate in DCUtR" — `dcutrReachabilityMode` keeps its signature (unused first param documented) to minimize the VC-01-tree diff; the FDC-12 doc-comments are re-pointed.
- **Symmetric-CGNAT punch rate is not measured** (no CGNAT pair on the rig) — carried as a stated design assumption (≈0%, VC-00 honesty note); VC-03 TURN owns those calls. Deferred-not-waived in the RESULTS doc.
- **No new relay Prometheus metrics** — punch telemetry is client-side by design here; relay-side call metrics arrive with VC-03/VC-09.
- **`holepunch_negative_control_test.go` changes meaning, not code** (default-flag nodes are now flag-ON): accepted — the kill-switch path gets its own explicit lock (TC-VC02-07) instead of repurposing the control.
- **The plan's original second ForcePublic-refutation leg was version-stale** ("puncher constructed only for Private hosts / a Public host only responds" — true ≤ go-libp2p v0.36.x, gate removed in v0.37.0, false on the pinned v0.39.1): corrected during /tdd-review. The design conclusion is unchanged (decouple; ForcePublic refuted by TC-189-41/NO_CIRCUIT alone); the in-repo feasibility comments carrying the same misattribution get a comment-only re-point (Real Scope).
- **Leg B upgrade may close via go-libp2p's direct-dial shortcut rather than a literal DCUtR punch** (same-NAT punch is hairpin-dependent; DCUtR exchanges only public addrs): accepted — either route proves the end-to-end upgrade chain; the route is recorded per cycle and tracer punch medians are marked n/a on direct-dial cycles.

## Dependency Impact

- **VC-05 (audio call MVP) depends on VC-02:** where punchable, RTP-adjacent traffic and signaling ride the punched direct QUIC path (sticky 'direct' primed); where not, VC-01's held circuit carries it — VC-05 inherits the upgraded-or-held contract without transport code of its own.
- **VC-03 (TURN) is the complement, not a dependent:** VC-02's RESULTS doc quantifies the un-punchable remainder that sizes TURN capacity (VC-00: "DCUtR reduces TURN usage, it does not replace it").
- **VC-09 (quality metrics) consumes** the punch telemetry vocabulary (`holepunch:*`, `transport:upgraded {elapsedMs,rttMs}`) and the RESULTS-doc format for per-call rollups.
- **VC-01 contract consumed:** protected held circuits (peer-scoped `Protect()`), redeployed relay limits, hold-rate metrics. Any VC-01 change to the host-options block (`node.go:387-407`) collides with Step 6b — sequential ordering is mandatory. **Punch-assertion ownership (epic lock L7):** on HEAD/VC-01's tree `EnableHolePunching` is always on, so VC-01's device proofs tolerate-and-record `holepunch:*` events without failing; **only VC-02 owns punch-outcome assertions** (this plan's runsheet + TC-VC02 rows).
- **FDC bookkeeping:** CV-13 flips from parked to executed; CV-11 gains leg-B device evidence (LAN-adjacent only — real cross-NAT punch success stays deferred-not-waived with owner VC-09 / two-network addendum, annotated on CV-11 itself); CV-12 stays deferred-not-waived (CGNAT rig).
- **No migration, no schema change, no l10n, no relay deploy** — the migration real-DB gate is N/A for VC-02 (zero DB surface; the only persisted transport artifact, `messages.transport` from migration 012, is untouched and already covered).

## Reviewer Findings  (/tdd-review, 2026-07-13)

**Dimension scores:** goal-clarity 80 (strong) · compartmentalization 86 (strong) · anti-drift 84 (strong) · define-good 78 (strong) · goal-verification 74 (adequate). **Counts:** 2 material (domain-verifier), 4 moderate, 4 nits — all applied, none declined.

**Domain verification (go-libp2p v0.39.1 source, `go.mod:17` pin):** the plan's #1 bet is CONFIRMED — flag-ON = `EnableHolePunching` + `ForceReachabilityPrivate` does participate in and initiate DCUtR (the holepunch package has no reachability requirement; initiation needs only an observed public addr + an inbound relayed conn, `svc.go:102-142` / `holepuncher.go:261-285`); conditionally omitting `EnableHolePunching` structurally removes both the puncher and the `/dcutr` handler (`basic_host.go:264-284`), so the kill-switch and mixed-fleet-graceful-failure claims hold; loopback inertness (TC-VC02-09) confirmed via the public-addr gate.

**Applied (material):**
1. **L6 stale-mechanism purge** — the original second ForcePublic-refutation leg ("puncher constructed only for Private hosts / a Public host only responds") was version-stale (gate removed in go-libp2p v0.37.0). Purged from Root Cause 3 / corollary / Design Decision / refuted-list / risk table / Planning Progress; the refutation now rests on TC-189-41/NO_CIRCUIT alone, with an explicit never-restate warning and a comment-only re-point of the four in-repo feasibility-comment lines (`holepunch_feasibility_test.go:104,:118,:140,:180`) added to Real Scope and Step 3.
2. **Leg B made may-fail-honest and route-recorded** — same-NAT punch is hairpin-dependent (DCUtR exchanges only public addrs) and may close via the direct-dial shortcut (`holepuncher.go:107-128`, breadcrumb-only in tracer); direction note added (emulator = inbound-relayed-conn/initiator side); recorded as an Accepted Difference.

**Applied (moderate):** partial-win Stop-if (attempts-without-upgrade across N cycles → VC-00 escalation, Done Criteria bound to leg-B payoff or recorded escalation); TC-VC02-07(b) pinned to a go/parser+go/ast mechanism with a second moved-call-site mutation (m2); runsheet N≥5 cycle protocol (medians across cycles, leg C zero-across-all-N); NEW mixed-fleet sentinel P7/TC-VC02-09b (`holepunch_mixed_fleet_test.go`, ON↔OFF pair on the negative-control fixture, auto-registered by the `GO_NODE_DCUTR` `-run 'TestHolePunch'` sweep) + INV-VC02-7; real-cross-NAT-punch-success recorded as an explicit deferred-not-waived row (owner VC-09 / two-network addendum) mirrored into the CV-11 annotation.

**Applied (nits):** leg-B relay-vs-direct ping-RTT row via the existing `peer:ping` chain; leg-A "storm" quantified (≤1 `TRANSPORT_DOWNGRADED` per punch-failure cycle, conn count ±1 over 2-min window); GREEN-A slice-boundary check (05(b)/06/07 must still be red); device proof-test commands bound into Done Criteria with an expected-skip disposition in Known-Failure Interpretation. Cross-plan locks honored: L6 applied exactly; L7 noted (punch-outcome assertions are VC-02-owned); VC-01 10-key polarity-pin re-verification pinned in the drift caution.

## Arbiter Decision

Structural blockers: **none** — plan accepted for execution. | Deferred details: real cross-NAT punch success (owner VC-09 field rollup or two-network runsheet addendum, annotated on CV-11); symmetric-CGNAT punch rate (design assumption ≈0%, VC-03 owns those calls); iOS punch-rate field data (VC-09). | Accepted differences: flag-ON default host options near-identical to HEAD; flag semantics change from "force Public" to "participate in DCUtR"; `holepunch_negative_control_test.go` changes meaning not code; version-stale ForcePublic mechanism corrected in-place (refutation stands on TC-189-41 alone); leg B may close via direct-dial route (route recorded, tracer medians n/a on those cycles).

## Final Execution Verdict

Verdict: (pending) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner):
