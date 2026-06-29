# 176 - CV-09: graduate EnableLibp2pLANDial to default-ON for everyone  (Modification)

Status: CLOSED — device-proven 2026-06-29 (Pixel 6 ↔ iPhone 11, DEFAULT flag / no dart-define: `MSG_RECEIVED_TRANSPORT:"direct"` both ways, iPhone 0× `0x8BADF00D`) on top of host RED→GREEN + full preservation + 4-lens review clean
Spec: free-text intent (no formal spec) — chains off CV-08 closure (commit `121f0551`, plans 174 + 175)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-29 | Evidence Collector | feature_flags.go, feature_flags_runtime.go, feature_flags_runtime_test.go, p2p_bridge_client.dart, config.go, bridge.go, node.go, lan_dial.go, bridge_lan.go, relay_session_test.go, p2p_service_dcutr_flag_test.dart | Grounded the full flag chain; 4-agent verify→refute | hand matrix to Planner |
| 2026-06-29 | Planner | (above) | Dart flip is load-bearing; Go flip inert for nil-flag tests; Dart default unguarded | emit plan |
| 2026-06-29 | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| 2026-06-29 | Arbiter | this plan | implementation-ready, host RED→GREEN gating, device-proof = closure | hand off to execution (on user go-ahead) |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-29 | contract extraction (git status --short) | — | pre-existing dirty = graphify-arch/*, info.plist, project.pbxproj, 00-INDEX.md, plan file | scope confirmed (none mine) | RED first |
| 2026-06-29 | RED tests added | feature_flags_runtime_test.go (inverted 1 assert + comment); NEW p2p_service_lan_dial_flag_test.dart (TC-09-02/03) | Go: `--- FAIL` @:47 "must default TRUE"; Dart: 2× `Expected:<true> Actual:<false>` | all 3 RED for documented reason (real FAIL lines, not toolchain panic) | flip flags |
| 2026-06-29 | implementation | p2p_bridge_client.dart (LOAD-BEARING `defaultValue:true` +comment); feature_flags.go (`EnableLibp2pLANDial:true` + struct/field/func docs) | siblings DcutrUpgrade+LANMedia left `false`; dart-define + 'p2p_lan_dial' gate untouched | scoped files only; sentinels verified intact post-edit (multi-session guard) | direct GREEN |
| 2026-06-29 | direct GREEN | — | Go `go test ./node/ -run TestFeatureFlags` ok 0.5s; Dart flag test 2/2; gofmt clean both Go files | reds now green; RED→GREEN = bidirectional mutation proof (false→RED, true→GREEN) | preservation |
| 2026-06-29 | preservation GREEN | — | Go `./node` ok 441.5s + `./bridge` ok 197.0s; `./integration` tagged `-tags integration` ok 93.9s (untagged = pre-existing `//go:build integration` setup-skip, NOT CV-09); core-host-all PASS (264 files); siblings DCUtR/LANMedia/bridge 66 tests green | sentinels green; Go flip inert for nil-flag tests confirmed | analyze/hygiene |
| 2026-06-29 | hygiene + review | — | `flutter analyze` 0-new (removed 1 unused import); `git diff --check` clean; 4-lens adversarial review CLEAN (1 nit = deliberate test-name retention) | no blockers, no scope violations | device-proof |
| 2026-06-29 | device-proof (closure) — **CLOSED** | Pixel 6 ↔ iPhone 11, **NO** dart-define | `node:lan_dial_ready` (Go gate `lan_dial.go:142` fires only when flag==true) + `MSG_RECEIVED_TRANSPORT:"direct"` BOTH ways (acked, hasReply) + 174 `FDC_LAN_ADVERT_PORTS` + Fix C `.local`→`/dns4` + iPhone 0× `0x8BADF00D`; evidence `scratchpad/cv09/CV09_DEVICE_PROOF.md` | CV-09 device-proven on the DEFAULT flag | committed this session |

## Source Of Truth
- Intent: graduate the FDC-11 LAN-direct transport flag from dark→default now that CV-08 (D1 two-phone proof) closed at `121f0551`.
- Flag chain ground truth: `go-mknoon/node/config.go:206-210` (EffectiveFlags), `go-mknoon/bridge/bridge.go:572-592`, `lib/core/bridge/p2p_bridge_client.dart:62-65,125`.
- Gate definitions: `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`.

## Session Classification
implementation-ready (host RED→GREEN is the gating deliverable; two-phone device-proof is the closure gate).

## Exact Problem Statement
FDC-11 libp2p LAN-direct dial shipped DARK behind `EnableLibp2pLANDial` (default false), exercised on device only via `--dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=true`. CV-08 (the D1 two-phone gate) is now **device-proven and closed** (commit `121f0551`: real Pixel 6 ↔ iPhone 11 same-WiFi reached `MSG_RECEIVED_TRANSPORT:"direct"` both directions, `connections:2` both; iPhone 11 ran 16+ min with zero `0x8BADF00D`). Per the FDC-16 staged-flip discipline, CV-09 graduates the flag so **every** install gets LAN-direct by default with **no dart-define**.

**What must improve:** a profile/release build with NO `--dart-define` for the flag must dial LAN-direct (the value actually serialized to the Go node at `node:start` must be `true`).

**What must stay unchanged (preserved-green sentinels):**
- The OTHER two FDC transport flags stay dark: `EnableDcutrUpgrade` (CV-13) and `EnableLibp2pLANMedia` (CV-34) keep defaulting false.
- All explicit-flag behavior tests (`lan_dial_test.go` T1–T10) stay green.
- The ~36 Go integration tests that start nodes with nil/default flags stay green.
- The `'p2p_lan_dial'` account-migration runtime gate (`p2p_service_impl.dart:927-938`) is untouched.

## Root Cause (verify → refute confirmed)
Not a bug — a deliberate flag graduation. The **mechanism that decides runtime behavior** (verified, survived refute):

- The Dart feature-flag map is an **always-sent FULL override**: `p2p_bridge_client.dart:125` unconditionally puts `defaultResilienceFeatureFlags()` into the `node:start` payload; the sole production caller `p2p_service_impl.dart:609-618` passes no override, so the full default map is always sent.
- Go applies it **wholesale**: `bridge.go:572` unmarshals the whole object into `*node.FeatureFlags`; `bridge.go:592` hands it to `NodeConfig`; `node.go:270-271` calls `cfg.EffectiveFlags()`; `config.go:207-208` returns `*c.FeatureFlags` **in its entirety** when non-nil. `json.Unmarshal` never seeds Go defaults, so `DefaultFeatureFlags()` (`feature_flags.go:83`) is reached **only** when the whole `featureFlags` object is absent (pointer nil) — which the production Dart path never does.
- **Therefore the load-bearing default is the Dart `defaultValue` at `p2p_bridge_client.dart:64`.** The Go `feature_flags.go:83` default is the nil-fallback only; flipping it alone is a **production no-op**.

**Refuted / do-NOT-re-introduce:**
- ❌ "Flipping only the Go default (`feature_flags.go:83`) makes the feature default-on." REFUTED — the Dart override always wins (`config.go:207-208`); Go's `true` would never be visible. This is the trap CV-09 must lock out with a test (TC-09-02).
- ❌ "Flipping the default will break the ~36 nil-flag Go integration tests by spontaneously LAN-dialing." REFUTED — the flag is read **only** at `lan_dial.go:142` inside `lanDialHandler.handle()`, reached only via `HandleLANPeerFound`, whose **only** non-test caller is the Dart-fed gomobile bridge (`bridge_lan.go:53`). `lan_dial.go:5` confirms the Go node runs **no** libp2p mDNS. Pure-Go tests never trigger a dial → the Go flip is behaviorally inert for them (confirmed by the preservation gate).
- ❌ "LAN-dial on by default could trigger unexpected dials during account migration." NON-ISSUE — the `'p2p_lan_dial'` migration gate (`p2p_service_impl.dart:938`) is independent of the feature flag and unchanged by CV-09.

## Real Scope
**In scope (two edits + their comments):**
1. `lib/core/bridge/p2p_bridge_client.dart:64` — `defaultValue: false` → `true` (LOAD-BEARING) + update comment 58-61 to record CV-08 closure.
2. `go-mknoon/node/feature_flags.go:83` — `EnableLibp2pLANDial: false` → `true` (consistency + guard-test) + update field doc 36-43 and `DefaultFeatureFlags()` doc 72-74.
3. `go-mknoon/node/feature_flags_runtime_test.go` — invert the one LANDial assertion to require `true`; update comment block 34-43.
4. NEW `test/core/services/p2p_service_lan_dial_flag_test.dart` — the Dart guard (mirrors `p2p_service_dcutr_flag_test.dart`).

**Out of scope (owned elsewhere):**
- `EnableDcutrUpgrade` flip → **FDC-12 / CV-13**. `EnableLibp2pLANMedia` flip → **FDC-15 / CV-34**.
- The `'p2p_lan_dial'` account-migration runtime gate (`p2p_service_impl.dart:927-938`) — separate concern.
- Removing the `MKNOON_ENABLE_LIBP2P_LAN_DIAL` dart-define — KEEP it (it now acts as an explicit override knob; `=false` forces-off for A/B/rollback).

## Files To Inspect Next
- Production (edit): `go-mknoon/node/feature_flags.go:83`; `lib/core/bridge/p2p_bridge_client.dart:62-65`.
- Test (edit + new): `go-mknoon/node/feature_flags_runtime_test.go:44-55`; NEW `test/core/services/p2p_service_lan_dial_flag_test.dart`.
- Dependency-only context (DO NOT edit): `config.go:206-210`, `bridge.go:572-592`, `node.go:270-271`, `lan_dial.go:142`, `bridge_lan.go:53`.
- Template to mirror: `test/core/services/p2p_service_dcutr_flag_test.dart` (whole file).

## Existing Tests Covering This Area
- `feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` — pins all 3 FDC flags default-false (CV-09 inverts the LANDial assertion). EXISTS.
- `lan_dial_test.go` T1–T10 — set the flag explicitly (on/off); UNAFFECTED by a default flip. EXISTS.
- `relay_session_test.go::TestFeatureFlags_DefaultAllTrue` (:1077) / `::TestFeatureFlags_NilDefaultsToAllEnabled` (:1120) — assert ONLY relay flags, never LANDial → unaffected. EXISTS.
- `p2p_service_dcutr_flag_test.dart` — the SIBLING guard (enableDcutrUpgrade==false) — template for the new test. EXISTS.
- `p2p_bridge_client_test.dart:138` — checks `payload['featureFlags'] == defaultResilienceFeatureFlags()`; **self-referential** (both sides move together) → does NOT pin the literal value. EXISTS but NOT real coverage.

**Missing coverage gaps:** the Dart `enableLibp2pLANDial` default value is **guarded by NO test** (GAP #1). CV-09 closes it with TC-09-02/03.
**Already in curated family arrays?:** No — these are `test/core/**` (AUTO-glob, `core-host-all`) and `go test ./node/`. Not in any `run_test_gates.sh` family array.

## RED Test Catalog  (add BEFORE any production edit — INV-RED-FIRST)
1. `go-mknoon/node/feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof`
   - Tier: unit (Go host).
   - Shape/setup: invert the LANDial block from `if flags.EnableLibp2pLANDial { t.Fatal("must default false…") }` to `if !flags.EnableLibp2pLANDial { t.Fatal("EnableLibp2pLANDial must default TRUE after FDC-11 D1 device-proof closed (CV-08 → CV-09)") }`. Update comment 34-43. **Leave the EnableDcutrUpgrade + EnableLibp2pLANMedia assertions UNCHANGED (still false).**
   - RED on HEAD because: the inverted assertion requires `true`, but `DefaultFeatureFlags()` is still `false` on HEAD.
   - GREEN after fix asserts: `DefaultFeatureFlags().EnableLibp2pLANDial == true`, while the other two FDC flags remain false.
   - Mutation that re-reds: revert `feature_flags.go:83` to `false` → this test red.
2. `test/core/services/p2p_service_lan_dial_flag_test.dart::'enableLibp2pLANDial defaults true in the feature-flags map handed to node:start'`  **(LOAD-BEARING — the anti-trap test)**
   - Tier: integration/host (real `P2PServiceImpl` + a `_PayloadCapturingBridge` that captures the `node:start` payload — copy the class from `p2p_service_dcutr_flag_test.dart`).
   - Shape/setup: `service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer')`; read `bridge.lastNodeStartPayload!['featureFlags']['enableLibp2pLANDial']`.
   - RED on HEAD because: the Dart `defaultValue:false` (`p2p_bridge_client.dart:64`) puts `false` in the sent map (no `--dart-define` in the host test env → `const bool.fromEnvironment` resolves to its defaultValue).
   - GREEN after fix asserts: the value SENT to the bridge is `true` (proves the *runtime* default, not just the Go fallback).
   - Mutation that re-reds: revert `p2p_bridge_client.dart:64` to `false` → red. **This is the mutation that catches the "flip-only-Go" trap.**
3. `test/core/services/p2p_service_lan_dial_flag_test.dart::'defaultResilienceFeatureFlags includes enableLibp2pLANDial:true'`
   - Tier: unit (Dart host).
   - Shape/setup: `expect(defaultResilienceFeatureFlags()['enableLibp2pLANDial'], isTrue)` (+ `containsKey` guard), mirroring DCUtR TC-12-10b.
   - RED on HEAD because: function returns `false` for that key on HEAD.
   - GREEN after fix asserts: the function returns `true`.
   - Mutation that re-reds: revert `p2p_bridge_client.dart:64` → red.
4. (closure, not a host RED) two-phone device-proof — see Device/Relay Proof Profile.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-09-01 Go default = true + others stay dark | pure config default | unit (Go) | `feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` | inverted assert needs true; Go default false on HEAD | revert `feature_flags.go:83` → red | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof)` | AUTO (go test) |
| TC-09-02 value SENT to bridge = true (anti-trap) | wiring / payload | integration host | `p2p_service_lan_dial_flag_test.dart::…node:start` | Dart `defaultValue:false` → map sends false | revert `p2p_bridge_client.dart:64` → red | `flutter test test/core/services/p2p_service_lan_dial_flag_test.dart` | AUTO (`test/core/**`, core-host-all) |
| TC-09-03 Dart map default = true | pure logic | unit (Dart) | `p2p_service_lan_dial_flag_test.dart::defaultResilienceFeatureFlags…true` | function returns false on HEAD | revert `p2p_bridge_client.dart:64` → red | `flutter test test/core/services/p2p_service_lan_dial_flag_test.dart` | AUTO (`test/core/**`) |
| TC-09-04 default-on dials on real pair (no dart-define) | multi-device / OS-boundary | device-proof | two-phone reuse of `run_1to1_device_real.dart` `fdc11_lan_direct_d1`, BUILT WITHOUT the flag dart-define | n/a (closure gate) | revert `p2p_bridge_client.dart:64` → device falls back to WS/relay, no `MSG_RECEIVED_TRANSPORT:"direct"` | manual two-phone (see Proof Profile) | reuses CV-08 scenario; OMIT `--dart-define` |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** N/A — CV-09 adds no in-memory derived state; the flag is re-sent fresh in the `node:start` map on every (re)start, so a process restart re-applies the new default by construction. No reopen test needed.
- **Sibling-surface consistency:** the sibling gates are the parallel FDC transport flags. CV-09 graduates ONLY LANDial and deliberately LEAVES `EnableDcutrUpgrade` + `EnableLibp2pLANMedia` dark — the asymmetry is **deliberate AND test-locked** by the UNCHANGED assertions in TC-09-01 (same guard test still pins both at false). Covered.
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel path touched.
- **Invariant re-verification under new transitions:** N/A — no new state transition (no self-heal/reset/release added). The flag flip is additive (LAN-direct is layered over the existing WS-LAN + relay legs, which remain the fallback); fallback preservation is covered by the Go `./integration` suite + existing 1to1 device proofs, not regressed here.

## Invariants (locked by tests)
- INV-1: exactly one FDC transport flag graduates; DcutrUpgrade + LANMedia stay dark → TC-09-01 (unchanged sibling assertions).
- INV-2 (anti-trap): the value actually serialized to the Go node at `node:start` is `true`, not merely the Go fallback default → TC-09-02.
- INV-3: Go and Dart defaults agree (both true), no split-brain → TC-09-01 (Go) + TC-09-03 (Dart).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (record pre-existing dirty: `graphify-arch/*`, `info.plist`, `project.pbxproj` — do NOT revert).
2. Add RED tests first: invert TC-09-01; create `p2p_service_lan_dial_flag_test.dart` (TC-09-02/03, copy `_PayloadCapturingBridge` from the DCUtR file). Run the focused cmds → confirm all three FAIL for the documented reasons.
3. Edit `lib/core/bridge/p2p_bridge_client.dart:64` `defaultValue: false → true` (+comment). **Stop-if** TC-09-02 stays red after this → the runtime override path is not what we modeled; replan, do not hack.
4. Edit `go-mknoon/node/feature_flags.go:83` `false → true` (+field/Default doc).
5. Rerun direct GREEN → preservation (full Go `./node ./bridge ./integration` + `core-host-all`) → `flutter analyze`.
6. On green: hand to the two-phone device-proof (closure). After landing code: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (deferred until now — see Risks).

## Risks And Edge Cases
- **The flip-only-Go trap** (most likely human error): pinned by TC-09-02 (asserts the SENT value, not the Go fallback).
- **Go-test toolchain panic:** all `go test` MUST run under `GOTOOLCHAIN=go1.25.0` (quic-go vs Go 1.26.x `crypto/tls` session-ticket panic). A run that FAILs with zero `--- FAIL:` lines = the toolchain panic, not a CV-09 regression.
- **graphify refresh deferred:** the 174/175 bundle (`121f0551`) has not had `graphify update`/`refresh_arch_graph.sh` run yet; the arch graph is stale w.r.t. lib/go. Batch the refresh with this CV-09 landing once the tree settles.
- **`p2p_bridge_client_test.dart:138` is self-referential** → stays green through the flip without proving anything; TC-09-02/03 supply the real value pin. No refactor of :138 required.

## Device/Relay Proof Profile
**Requires two-phone device for closure** (host RED→GREEN is the gating deliverable).
Closure scenario: Pixel 6 (`21071FDF600CSC`) + iPhone 11 (`00008030-001A6D2801BB802E`), flat single-AP WiFi, `flutter build --profile` with `--dart-define=FDC_FLOW_LOG=1` and **NO** `--dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL` (the new default must carry it). Install iOS **in-place** (no uninstall — Keychain migration-authority brick risk). Confirm `node:lan_peer_found` + `lan_dial_ready` fire and `MSG_RECEIVED_TRANSPORT:"direct"` both directions — proving the default-on path works without the override.
Differs from CV-08: CV-08 forced the flag via dart-define; CV-09 proves the **default** carries it. Reuses the `fdc11_lan_direct_d1` KEYSTONE scenario, override omitted.
Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (see `p2p_bridge_client.dart:9`).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# --- RED (before production edits) — must FAIL for the documented reason ---
( cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof )   # FAIL: needs true, default false
flutter test test/core/services/p2p_service_lan_dial_flag_test.dart   # FAIL: sent map has enableLibp2pLANDial:false

# --- Direct GREEN (after both flips) ---
( cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run 'TestFeatureFlags' )
flutter test test/core/services/p2p_service_lan_dial_flag_test.dart   # expect: 2/2 pass

# --- Preservation sentinels (must stay green) ---
( cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ ./bridge/ ./integration/ )   # full Go: all pass (proves Go flip inert for nil-flag tests)
flutter test test/core/services/p2p_service_dcutr_flag_test.dart test/core/services/p2p_service_impl_lan_media_test.dart test/core/bridge/p2p_bridge_client_test.dart   # siblings stay green
./scripts/run_host_test_gates.sh core-host-all   # Dart host all green

# --- Hygiene ---
flutter analyze            # 0 new issues
git diff --check

# --- Device-proof (closure) — manual two-phone, NO flag dart-define ---
# flutter build apk --profile  --dart-define=FDC_FLOW_LOG=1
# flutter build ios --profile  --dart-define=FDC_FLOW_LOG=1
# install both; QR-pair on flat WiFi; grep [FLOW] for MSG_RECEIVED_TRANSPORT:"direct" both ways
```

## Known-Failure Interpretation
- Expected RED: TC-09-01/02/03 before the two flips.
- Pre-existing dirty (do NOT revert): `graphify-arch/*`, `info.plist`, `ios/Runner.xcodeproj/project.pbxproj` (Go-inputPaths churn).
- Environment blocker (NOT product): a Go suite FAIL with zero `--- FAIL:` lines = go1.26 toolchain panic → rerun under `GOTOOLCHAIN=go1.25.0`. A device-proof blocked by mDNS multicast on a multi-AP network = rig issue, not code.
- Scope drift (BLOCKING): any change to `EnableDcutrUpgrade`, `EnableLibp2pLANMedia`, or the `'p2p_lan_dial'` migration gate; any new RED outside the four TC rows.

## Done Criteria
- [ ] RED added first (TC-09-01/02/03), failed for the expected reason.
- [ ] Mutation-verified: revert `feature_flags.go:83` → TC-09-01 red; revert `p2p_bridge_client.dart:64` → TC-09-02 & TC-09-03 red.
- [ ] Direct GREEN + full Go (`./node ./bridge ./integration`) + `core-host-all` + sibling DCUtR/LANMedia/bridge tests pass.
- [ ] Two-phone device-proof: `MSG_RECEIVED_TRANSPORT:"direct"` both ways with NO flag dart-define.
- [ ] Every new test auto-globbed & confirmed in a gate run.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.
- [ ] Post-land: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.

## Scope Guard (hard "Do not")
- Do NOT flip `EnableDcutrUpgrade` (FDC-12 / CV-13) or `EnableLibp2pLANMedia` (FDC-15 / CV-34) — leave their guard assertions FALSE.
- Do NOT touch the `'p2p_lan_dial'` account-migration runtime gate (`p2p_service_impl.dart:927-938`).
- Do NOT remove the `MKNOON_ENABLE_LIBP2P_LAN_DIAL` dart-define plumbing — it remains an explicit override knob.
- Do NOT flip ONLY the Go default (production no-op) — the Dart flip is mandatory and load-bearing.

## Accepted Differences / Intentionally Out Of Scope
- The Go `feature_flags.go:83` flip is behaviorally **inert in production** (the Dart override always wins) — we flip it anyway for Go/Dart consistency and to satisfy the guard test. Documented + test-locked by TC-09-01.
- `p2p_bridge_client_test.dart:138` stays self-referential (does not pin the literal value); TC-09-02/03 add the real value pin, so no refactor of :138.

## Dependency Impact
- FDC-S6 (libp2p-LAN soak / WS-retirement win-rate verdict) is hard-gated on FDC-11 D1; CV-09 default-on is the production baseline that soak measures against.
- CV-13 (DCUtR) and CV-34 (LAN-media) follow the SAME graduate pattern — this plan is their template (flip Dart load-bearing default + invert the one guard assertion + add the sibling Dart guard test).

## Reviewer Findings
Sufficiency: every TC row has tier + mutation + literal gate + registration (no empty cells). The load-bearing edit (`p2p_bridge_client.dart:64`) is mutation-locked by TC-09-02 specifically to catch the flip-only-Go trap that a naive "flip feature_flags.go:83" would fall into. The two refuted hypotheses (flip-only-Go-suffices; default-on-breaks-nil-flag-tests) are recorded as do-NOT-re-introduce with file:line evidence. Blind-spot sweep: 1 deliberate test-locked asymmetry (sibling flags), 3 justified N/A. Thin evidence: none — full chain read in source. One judgment call surfaced for the user: whether to flip the Go default at all (it is inert in prod) vs flip only Dart — plan recommends flipping BOTH for consistency + guard-test truth.

## Arbiter Decision
Structural blockers: none. Deferred details: graphify refresh batched post-land; device-proof is manual two-phone (no host integration_test file — fail-closed per the FDC pattern). Accepted differences: Go flip inert-but-consistent. **implementation-ready** on user go-ahead.

## Final Execution Verdict
Verdict: **CLOSED — host RED→GREEN COMPLETE + two-phone device-proof PASSED** (device-proven on the DEFAULT flag, committed this session). | Files changed: 2 prod (`p2p_bridge_client.dart` LOAD-BEARING `defaultValue:true`; `feature_flags.go` `EnableLibp2pLANDial:true` + docs) + 1 test edit (`feature_flags_runtime_test.go` 1 assertion inverted, siblings left false) + 1 new test (`p2p_service_lan_dial_flag_test.dart`, TC-09-02 anti-trap + TC-09-03). | Tests run (+counts): RED confirmed for all 3 (Go `--- FAIL`@:47; Dart 2× `Expected:<true> Actual:<false>`) → after flips: Go `TestFeatureFlags` ok; Dart flag test 2/2; **mutation proof = the RED→GREEN transition is bidirectional** (literals at false ⇒ RED, at true ⇒ GREEN). Preservation: Go `./node` ok 441.5s, `./bridge` ok 197.0s, `./integration` (tagged) ok 93.9s; `core-host-all` PASS 264 files; sibling DCUtR/LANMedia/bridge 66 tests green; `flutter analyze` 0-new; gofmt clean; `git diff --check` clean. | Blocking: none. | QA verdict: 4-lens adversarial review CLEAN (scope-guard / anti-trap / preservation / doc-accuracy) — sole finding a `nit` (guard-test name kept verbatim by design, gate references it; doc comment already reframes). Scope guard held: DcutrUpgrade + LANMedia stay dark, `'p2p_lan_dial'` migration gate untouched, dart-define override knob retained. | Non-blocking follow-ups: (1) ✅ DONE — two-phone device-proof CLOSED 2026-06-29 (DEFAULT flag, `MSG_RECEIVED_TRANSPORT:"direct"` both ways, 0× `0x8BADF00D`); (2) graphify refresh (174/175 + CV-09) run post-commit this session; (3) ✅ committed this session.
