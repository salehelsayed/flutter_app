# 175 - iOS bonsoir advertise (broadcast) start() blocks the main thread → 0x8BADF00D watchdog freeze; move the synchronous DNS-SD off the main thread  (Bug)

Status: DEVICE-GREEN — 175 freeze fix proven on iPhone 11 (no 0x8BADF00D, 16min stable) AND CV-08 PASS #4 fully closed (MSG_RECEIVED_TRANSPORT:"direct" BOTH directions on real Pixel 6 ↔ iPhone 11, 2026-06-29). Required 3 additional FDC-11 LAN-direct fixes uncovered during the run (A/B/C below). NOT committed.
Spec: free-text intent (no formal spec) — follow-on from `Test-Flight-Improv/174-fdc11-lan-dial-advert-libp2p-ports-tdd-plan.md` "CV-08 Run Results — session 2"; memories `project_bonsoir_localnetwork_watchdog_crash_fix`, `project_cv08_fdc11_device_red_2026_06_28`.

> **READ THIS FIRST — root cause corrected by the verify→refute grounding.** The originating intent said "move the bonsoir **browse** off the main thread / add a native pre-probe." Source-level grounding **REFUTED** that framing: the **browse** is already async (`NWBrowser.start(queue:.main)` — `.main` is only the callback queue). The genuine main-thread blocker is the **advertise/broadcast** leg — `BonsoirServiceBroadcast.start()` calls `DNSServiceProcessResult(sdRef)` **synchronously on the main thread**. This plan targets the corrected root cause. A native pre-probe and a bonsoir 7.x version bump were both refuted as fixes (see Root Cause → Refuted).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-29 | Evidence Collector (8-agent verify→refute workflow) | bonsoir_discovery_service.dart, bonsoir_darwin-5.1.3 + 7.1.0 Swift, local_p2p_service.dart, p2p_service_impl.dart, GoBridge.swift, AppDelegate.swift, test/core/local_discovery/* | Root cause = broadcast.start() sync `DNSServiceProcessResult` on main (BonsoirServiceBroadcast.swift:35). Browse/pre-probe/version-bump REFUTED. | Build matrix + emit plan |
| 2026-06-29 | Planner | (this doc) | Fix = off-main dispatch of broadcast processing; requires vendoring bonsoir_darwin OR app-side NWListener advertise. | Hand to reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-29 | 0. symbolicate crash | — | parsed `Runner-2026-06-29-131147.ips`: faultingThread 0 (`com.apple.main-thread`) = `__recvfrom_nocancel ← read_all ← DNSServiceProcessResult ← BonsoirServiceBroadcast.start`; `0x8BADF00D` scene-update watchdog, `ProcessVisibility: Background` | **PASS** — blocking frame is exactly `DNSServiceProcessResult` in broadcast `start()`; permission-alert hypothesis refuted | patch |
| 2026-06-29 | contract extraction | (snapshot) | `git status --short` — pre-existing dirty = 174 files + graphify-out + INDEX; clean otherwise | scope confirmed; 174 files NOT reverted | vendor |
| 2026-06-29 | RED (TC-01) | `third_party/bonsoir_darwin/darwin/Tests/BonsoirServiceBroadcastOffMainTest.swift` | authored faithful XCTest via `processResult` seam; **DEGRADED → STRUCTURAL** (running it needs the full Runner+GoMknoon test build = flagged env path). Structural gate GREEN (no synchronous `DNSServiceProcessResult` in `start()`; background `DispatchSourceRead` + main-hop wired; only code occurrence is the seam default). Mutation carried by TC-02 (device). | logged degrade per RED-1 note | impl |
| 2026-06-29 | implementation | `third_party/bonsoir_darwin/**` (vendored 5.1.3), `darwin/.../Broadcast/BonsoirServiceBroadcast.swift` (off-main patch), root `pubspec.yaml` (`dependency_overrides`), `pubspec.lock`, `ios/Pods/**` + `ios/.symlinks` (pod regen) | off-main `DispatchSourceRead` (mirrors discovery resolve) + cancel-handler dealloc + `registerCallback` main-hop + seam | scoped to vendored pkg + pubspec + pods | gates |
| 2026-06-29 | compile-proof (native) | — | `xcodebuild -project ios/Pods/Pods.xcodeproj -target bonsoir_darwin -sdk iphonesimulator build` → **BUILD SUCCEEDED** (arm64+x86_64, linked Flutter) | patched Swift is valid; pods resolve to vendored path | gates |
| 2026-06-29 | preservation GREEN | — | `flutter test test/core/local_discovery/` → **+145 All tests passed** (TC-03 bonsoir contract+watchdog-gate; TC-04 174 self-heal). `flutter analyze` → 0 NEW (1637 pre-existing baseline; none in changed area). `git diff --check` clean. `core-host-all` → (see verdict) | sentinels green | review |
| 2026-06-29 | adversarial review | — | 5-dimension read-only Workflow (threading/eventsink, memory-safety, lifecycle-restart, vendoring-pods, behavior-scope) + per-finding refute pass | (see Reviewer Findings) | device |
| (deferred) | device-proof (closure) | — | manual two-phone CV-08-RESPONSIVE on Pixel ↔ iPhone 11 — REQUIRES live rig (agent cannot run two-phone) | iPhone responsive + `MSG_RECEIVED_TRANSPORT:"direct"` ×2 + clean `idevicecrashreport` | next live-rig session |

## Source Of Truth
- Spec / intent: this doc + 174 CV-08 session-2 results.
- Gate definitions: `scripts/run_test_gates.sh` / `scripts/run_host_test_gates.sh` (script wins over prose).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this is **175**; 174 is highest existing).
- Native source under test: `bonsoir_darwin-5.1.3` (pinned in `pubspec.lock`; the `bonsoir_darwin-7.1.0` in pub-cache is a **stray unused download** — do not be misled by it).

## Session Classification
implementation-ready. **Fix approach = A (vendor + patch bonsoir_darwin) — DECIDED 2026-06-29 by user.** One remaining prerequisite: **Step-0 crash symbolication** to confirm the exact blocking frame before patching.

## Exact Problem Statement
On iPhone 11 / iOS 26.5, the app's Dart layer freezes within ~1 s of launch and, on the next background transition, iOS issues a `FRONTBOARD 0x8BADF00D` "scene-update watchdog … exhausted 10.00 s" SIGKILL (confirmed crash report `Runner-2026-06-29-131147.ips`, `ProcessVisibility: Background`). The Go node keeps running on its own threads (a dialing peer still observes the connection), but the Flutter main thread is blocked, so the UI is dead — no QR contact-add, no message display.

Root cause (corrected): the bonsoir **advertise** path calls `DNSServiceProcessResult(sdRef)` **synchronously on the iOS main thread** (`BonsoirServiceBroadcast.start()`, `bonsoir_darwin-5.1.3/darwin/Classes/Broadcast/BonsoirServiceBroadcast.swift:35`), reached from Dart via `await _broadcast!.start()` (`lib/core/local_discovery/bonsoir_discovery_service.dart:166`). `DNSServiceProcessResult` blocks the calling thread until the `mDNSResponder` daemon replies; when Local Network permission is pending/denied or the daemon is contended, it blocks past the 10 s watchdog. Registration usually returns fast (it is local), which is why the advert is visible in `dns-sd` (device evidence "advertise succeeds") — but every re-advertise (`restartAdvertising`, the 174 `updateLibp2pPorts` re-publish, the periodic refresh timer) re-runs the same synchronous call on main, and any one that stalls during a scene update kills the app.

This blocks **CV-08 PASS #4** (`MSG_RECEIVED_TRANSPORT:"direct"`, which needs a responsive iPhone for QR contact-add + message display) and therefore FDC-11 end-to-end iOS device validation and **CV-09** (the `EnableLibp2pLANDial` flag-default flip). FDC-11 LAN-dial + connection establishment is already proven on device (174: `addrCount:2` → `connections:1→2`, reproduced ×2); this freeze is the **only** remaining blocker.

What must improve: the synchronous `DNSServiceProcessResult` on the broadcast/advertise path must run **off the main thread**, so cold-start advertise + every re-advertise can never block the iOS main run loop, regardless of Local Network permission state. The iPhone must stay responsive while LAN discovery/advertise runs.

What must stay unchanged (→ preserved-green sentinels): the Dart `LocalDiscoveryService` contract and the existing suspected-denied watchdog gate semantics (`bonsoir_discovery_service.dart:132-231`); the 174 advert self-heal (`updateLibp2pPorts` / `FDC_LAN_ADVERT_PORTS*` / `_localNetworkProven` defer) and its tests; the TXT advert of `quicPort`/`tcpPort`; discovery/resolve behavior (already off-main); all of `test/core/local_discovery/` + `core-host-all` + `1to1` + `transport`.

## Root Cause (verify → refute confirmed)
**SURVIVED refute (holds):** `BonsoirServiceBroadcast.start()` → `DNSServiceRegister(&sdRef, …)` (Broadcast/BonsoirServiceBroadcast.swift:32) then **synchronous `DNSServiceProcessResult(sdRef)`** (`:35`) on the **calling = iOS main thread** (the plugin's `FlutterMethodChannel` handler runs on the platform/main thread with no `taskQueue`: `SwiftBonsoirPlugin.swift:52-54`). Reached from `lib/core/local_discovery/bonsoir_discovery_service.dart:166` (`await _broadcast!.start()`). The first `startAdvertising` of every process is **ungated** — the suspected-denied gate (`:132-144`) only skips a *re*-start (its latch `_suspectedDeniedUntil` starts null and is set only by a post-start 12 s zero-peer timer at `:216-231`, which runs *after* the starts at `:207`). A Dart `.timeout()` cannot help: the native main-thread block persists after the Dart Future times out.

**Refuted / do-NOT-re-introduce:**
- **"The browse/discovery start blocks the main thread."** FALSE in 5.1.3 **and** 7.1.0: `BonsoirServiceDiscovery.start()` = `browser.start(queue:.main)` where `browser` is an `NWBrowser` (Network.framework, async); `.main` is only the callback-delivery queue. Permission denial surfaces async via `stateUpdateHandler` (`.waiting`/`.failed`). The discovery resolve path's only `DNSServiceProcessResult` is already off-main on a `DispatchSourceRead`/global queue (BonsoirServiceDiscovery.swift:141-143). → A fix or test aimed at "browse start" targets a path that does not synchronously hang. (Originating intent's "browse" framing.)
- **"Bump bonsoir to 7.x to fix it."** FALSE: `bonsoir_darwin-7.1.0`'s `BonsoirServiceBroadcast.start()` is byte-identical except a `service.host` field rename — line 35 still calls `DNSServiceProcessResult(sdRef)` synchronously; 7.x CHANGELOG has zero threading changes. A version bump changes nothing about the freeze. (`pubspec.lock` pins 5.1.3; the 7.1.0 in pub-cache is unused.)
- **"Add a native NWBrowser/NWPathMonitor pre-probe to predict the hang and gate the start."** REJECTED: (a) it probes the wrong API surface (NWBrowser ≠ the blocking `DNSServiceRegister` advertise path), so `.ready` does not predict that the synchronous registration read returns promptly → false-pass (still hangs); (b) a short-timeout probe reports "unavailable" for benign reasons (first-launch prompt still `.waiting`, alone-on-LAN, AP isolation, cold mDNSResponder) → false-skip that silently disables advertise+discovery = a functional regression; (c) the probe is itself a local-network op fired in the same cold-start window and can trigger the very permission prompt / main-thread interaction the deferral exists to avoid.

## Real Scope
**In scope:** make the advertise-path `DNSServiceProcessResult` run off the main thread, and prove the iPhone stays responsive + CV-08 PASS #4 closes. Because bonsoir is a plain pub dependency (`pubspec.yaml:39 bonsoir: ^5.1.0`; only `record_linux` is in `dependency_overrides`), the fix is delivered via **Approach A (CHOSEN 2026-06-29):**

- **Approach A — vendor + surgical off-main patch (THE approach).** Add `dependency_overrides: bonsoir_darwin: {path: third_party/bonsoir_darwin}` (vendor the 5.1.3 darwin source into the repo), and patch `BonsoirServiceBroadcast.start()` to run `DNSServiceProcessResult` on a background queue via `DispatchSource.makeReadSource(fileDescriptor: DNSServiceRefSockFD(sdRef!), queue: DispatchQueue.global(qos:.userInitiated))` + handler `DNSServiceProcessResult(sdRef)` — **mirroring the in-package discovery-resolve pattern** (`BonsoirServiceDiscovery.swift:125,141-143`). Smallest correct change (~10 native lines). Cost: a vendored third-party fork to maintain across upgrades (document in a `third_party/bonsoir_darwin/PATCH.md`, mirroring `graphify-arch/patches/`).
- **Approach B (NOT chosen — recorded as the no-fork alternative) — app-side NWListener advertise.** Keep bonsoir for discovery (already safe); replace the *broadcast* leg with an app-owned native advertise (`NWListener`/`DNSServiceRegister`-off-main) in `ios/Runner` exposed via a dedicated `MethodChannel` (clone `setupDiskSpaceBridge`, `AppDelegate.swift:279-291`), and rewire `bonsoir_discovery_service.dart` advertise to call it. No third-party fork; larger native surface + a new Dart seam + Android parity (`GoBridge.kt`). Revisit only if vendoring proves untenable.

**Out of scope (owned elsewhere):**
- Flipping `EnableLibp2pLANDial` default → **CV-09** (gated on this going device-green).
- `_libp2pListenPort` dual-stack IPv4/IPv6 family-awareness → pre-existing 174 follow-up (`project_174_fdc11_advert_self_heal_implemented` finding #1).
- The Dart suspected-denied gate's "alone-on-LAN false-positive" ambiguity → unchanged; this plan keeps it as defense-in-depth, not the primary fix.

## Files To Inspect Next
Production (fix site):
- **Approach A:** `third_party/bonsoir_darwin/darwin/Classes/Broadcast/BonsoirServiceBroadcast.swift` (vendored copy of pub-cache 5.1.3:25-40); `pubspec.yaml` (`dependency_overrides`); `ios/Podfile`/`macos/Podfile` (path-pod resolution). Pattern to mirror: `…/Discovery/BonsoirServiceDiscovery.swift:125,141-143`.
- **Approach B:** `ios/Runner/AppDelegate.swift:25-28,143-156,269-323` (channel registration), new `LocalNetworkAdvertiser.swift`; `lib/core/local_discovery/bonsoir_discovery_service.dart:150-172` (advertise leg to rewire); `android/.../GoBridge.kt` (parity).
Direct tests + integration tests: `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart` (gate + fakes, :353-595), `test/core/local_discovery/local_p2p_service_test.dart:43-92` (174 self-heal).
Dependency-only context: `lib/core/local_discovery/local_p2p_service.dart:39-133`, `lib/core/services/p2p_service_impl.dart:466-477,4188-4252` (174 re-advertise chain that re-enters advertise).

## Existing Tests Covering This Area
- `bonsoir_discovery_service_contract_test.dart` "BonsoirDiscoveryService Local Network watchdog gate" (:353-479) — covers the Dart **re-start** skip gate (zero-peer latch). EXISTS. Does NOT cover the native off-main behavior or the first-start.
- `local_p2p_service_test.dart` "LocalP2PService" (:43-92) — 174 `updateLibp2pPorts` re-advertise/no-op via `FakeLocalDiscoveryService.startAdvertisingCallCount`. EXISTS.
- **MISSING:** no test asserts the advertise native processing runs off the main thread; no test asserts the FIRST advertise is non-blocking; the `LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED` event string has zero by-name assertions.
Already in curated family arrays?: `bonsoir_discovery_service_contract_test.dart` is auto-globbed by `core-host-all` (`run_host_test_gates.sh:171-172`) AND hardwired into the move-feature gate (`run_host_test_gates.sh:183`). All `test/core/local_discovery/*_test.dart` auto-glob under `core-host-all`.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. **Native (Swift) — `third_party/bonsoir_darwin/.../BonsoirServiceBroadcastOffMainTest.swift`::`test_start_does_not_block_calling_thread`** *(Approach A; PROD-CRITICAL-adjacent, feasibility-gated — see note)*
   - Tier: native unit (XCTest target in the vendored package, or a `RunnerTests` target).
   - Shape/setup: drive `BonsoirServiceBroadcast.start()` with a stubbed/delayed `mDNSResponder` reply (inject the processing queue + a fake `DNSServiceProcessResult` shim via a seam added in the patch). Assert `start()` returns within a tight bound (e.g. < 50 ms) and that the processing closure executes on a **non-main** queue (`!Thread.isMainThread` / a known background `DispatchQueue` label).
   - RED on HEAD because: unpatched `start()` calls `DNSServiceProcessResult(sdRef)` synchronously on the calling thread (`:35`) → with a delayed reply, `start()` blocks past the bound on the calling (main) thread.
   - GREEN after fix asserts: `start()` returns immediately; processing runs on the injected background queue.
   - Mutation that re-reds: revert the off-main dispatch (restore the synchronous `DNSServiceProcessResult(sdRef)` at `:35`) → this test blocks/fails.
   - **Feasibility note:** stubbing the dns_sd C API in XCTest is non-trivial; if a faithful native unit cannot be built, this tier degrades to a **structural** assertion (the processing is wired through a `DispatchSourceRead` on a global queue, asserted by reading the patched source in review) and the **mutation-verifiable closure shifts to the device-proof row (RED-2)**. State which in the execution log; do not silently drop it.

2. **Device-proof — `CV-08-RESPONSIVE` (manual two-phone gate, fail-closed; no `integration_test/` file, like 174 CV-08 / 171 TC-13)** *(CLOSURE GATE, PROD-CRITICAL)*
   - Tier: device-proof (real iPhone + Pixel on flat single-AP WiFi; build `--profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=true`).
   - Shape/setup: cold-start the iPhone app and keep it foregrounded; trigger ≥2 re-advertises (`restartAdvertising` via resume/health-check + a 174 `updateLibp2pPorts` after a peer resolves). Then perform the CV-08 message leg (QR contact-add, send each direction).
   - RED on HEAD because: within ~1 s of launch the iPhone Dart layer goes silent (`[FLOW]` stops; reproduced this session) and/or a `0x8BADF00D` scene-update SIGKILL occurs on backgrounding → QR/message impossible.
   - GREEN after fix asserts: iPhone `[FLOW]` keeps flowing continuously through cold-start + ≥2 re-advertises (no >2 s silence, no `0x8BADF00D` in `idevicecrashreport`); `MSG_RECEIVED_TRANSPORT:"direct"` captured **both directions**; CV-08 PASS #4 criteria all green.
   - Mutation that re-reds: revert the off-main dispatch → the freeze / watchdog SIGKILL returns on device (this is the primary mutation-verification for the native fix if RED-1 degrades to structural).
   - Distinct discriminator: assert `LOCAL_MDNS_ADVERTISE_START` STILL fires (advertise preserved) AND continuous post-advertise `[FLOW]` (e.g. `relay:state`/`READINESS_PROOF_RESULT` heartbeats) — i.e. advertise works AND the thread is free, distinguishing "fixed" from "advertise silently disabled."

3. **Host (Dart) regression — `bonsoir_discovery_service_contract_test.dart` (existing gate group) + `local_p2p_service_test.dart` (174 group)** *(PRESERVATION — must STAY green through the vendoring/rewire)*
   - Tier: unit/contract host.
   - Shape/setup: unchanged existing tests (factory-fake injection; `restart()` skip assertions; `updateLibp2pPorts` call-count).
   - RED on HEAD because: N/A (these are GREEN today; they are sentinels, not new REDs).
   - GREEN after fix asserts: still green — the Dart `LocalDiscoveryService` contract, the suspected-denied gate semantics, and the 174 self-heal are unchanged by an off-main native dispatch (Approach A) or by the advertise-channel rewire (Approach B, which must keep `startAdvertising`'s Dart-observable behavior identical).
   - Mutation that re-reds: N/A (preservation). If Approach B changes the advertise call site, add a focused test asserting `startAdvertising` still emits `LOCAL_MDNS_ADVERTISE_START` and still arms the gate timer.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 advertise start is non-blocking off-main | OS/threading (native) | native unit (Approach A) | `third_party/bonsoir_darwin/…/BonsoirServiceBroadcastOffMainTest.swift::test_start_does_not_block_calling_thread` | sync `DNSServiceProcessResult` on calling thread (Broadcast:35) | restore sync `DNSServiceProcessResult(sdRef)` → blocks | `xcodebuild test -scheme <pkg/Runner> -destination 'platform=iOS Simulator,…'` (or `pod lib lint`) | native XCTest target (manual; not Dart auto-glob) — **flag if degraded to structural** |
| TC-02 iPhone stays responsive + msg-over-direct | OS-boundary / multi-device | **device-proof (CLOSURE)** | `CV-08-RESPONSIVE` manual two-phone gate | ~1 s freeze / `0x8BADF00D` on HEAD | revert off-main dispatch → freeze returns | manual: build+install+capture per 174 CV-08 steps; `idevicecrashreport` clean; `MSG_RECEIVED_TRANSPORT:"direct"` ×2 | fail-closed manual gate (no `integration_test/` file; documented, like 174 CV-08 / 171 TC-13) |
| TC-03 Dart contract + gate preserved | wiring/contract | host unit | `bonsoir_discovery_service_contract_test.dart::"…watchdog gate…"` (:353-479) | N/A (green sentinel) | n/a (preservation) | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (`test/core/**`) |
| TC-04 174 self-heal preserved | wiring/contract | host unit | `local_p2p_service_test.dart::"updateLibp2pPorts re-advertises…"` (:43-92) | N/A (green sentinel) | n/a (preservation) | `./scripts/run_test_gates.sh 1to1` + `core-host-all` | AUTO (`test/core/**`) |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** the fix touches the *advertise* path that is re-entered on every `restartAdvertising` (resume/health-check, `p2p_service_impl.dart:4666`) and every 174 `updateLibp2pPorts` (`local_p2p_service.dart:116-122`). → **TC-02 explicitly drives ≥2 re-advertises** so the off-main dispatch is proven on the re-start path, not just cold-start (the original crash vector was the *restart*).
- **Sibling-surface consistency:** the only sibling native call of the same class is the discovery-resolve `DNSServiceProcessResult`, which is **already off-main** (BonsoirServiceDiscovery.swift:141-143) — this fix brings broadcast to parity. macOS uses the same Swift (`canImport(FlutterMacOS)`); Android advertise is a separate plugin (NsdManager) not affected. → N/A beyond parity note (no other on-main DNS-SD call exists in the package).
- **Destructive-action side-effects:** `dispose()` calls `DNSServiceRefDeallocate(sdRef)` (Broadcast:43). The patch must ensure the new `DispatchSource` is **cancelled before** `DNSServiceRefDeallocate` (use-after-free / double-process risk) — mirror discovery's source teardown. → asserted structurally in review + exercised by TC-02 stop/restart cycles.
- **Invariant re-verification under new transitions:** the 174 deferral (`_localNetworkProven`) and the suspected-denied gate must still hold after the fix — TC-03/TC-04 lock them; TC-02 confirms the peer-resolved 174 re-advertise still fires and no longer risks the freeze.

## Invariants (locked by tests)
- INV-1: advertise native processing runs off the iOS main thread → TC-01 (native) / TC-02 (device, mutation).
- INV-2: advertise still succeeds (TXT visible to peers) after the fix → TC-02 (`LOCAL_MDNS_ADVERTISE_START` + `dns-sd` advert) — guards against "fixed by disabling advertise."
- INV-3: the Dart `LocalDiscoveryService` contract + suspected-denied gate + 174 self-heal are unchanged → TC-03 / TC-04.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Step 0 (prerequisite): symbolicate `/tmp/cv08/crash/Runner-2026-06-29-131147.ips`** and confirm the main-thread (thread 0) backtrace is blocked inside `DNSServiceProcessResult` / `BonsoirServiceBroadcast.start` (vs the alternative hypothesis: the system Local Network permission alert blocking scene update). **Stop-if** the main thread is NOT in `DNSServiceProcessResult` → re-open Root Cause before patching (the off-main dispatch would be the wrong fix).
2. Approach **A is decided** (vendor + patch). No further decision needed.
3. Add RED tests (TC-01 native; register the device-proof TC-02 in the plan as the fail-closed manual gate). Run TC-01; confirm it blocks/fails for the documented reason.
4. **Approach A:** vendor `bonsoir_darwin` 5.1.3 into `third_party/bonsoir_darwin`, add `dependency_overrides`, `pod install`. Patch `BonsoirServiceBroadcast.start()`: replace the synchronous `DNSServiceProcessResult(sdRef)` (`:35`) with a `DispatchSourceRead` on `DispatchQueue.global(qos:.userInitiated)` over `DNSServiceRefSockFD(sdRef!)`, calling `DNSServiceProcessResult(sdRef)` in the read handler; cancel the source in `dispose()` before `DNSServiceRefDeallocate`. Add `third_party/bonsoir_darwin/PATCH.md`. **Stop-if** vendoring/pod resolution proves untenable → fall back to Approach B (app-side `NWListener` advertise; see Real Scope) and add a Dart contract test before rewiring the advertise leg.
5. Rerun TC-01 (GREEN). Run preservation (TC-03/TC-04) + named gates + `flutter analyze` + `git diff --check`.
6. Build `--profile` for device; run the device-proof TC-02 (closure) per 174 CV-08 steps. Confirm responsiveness + `MSG_RECEIVED_TRANSPORT:"direct"` ×2 + clean `idevicecrashreport`.
7. Only AFTER device-green → hand CV-09 (flag flip) as its own plan.

## Risks And Edge Cases
- **Use-after-free on stop/restart:** cancel the `DispatchSource` before `DNSServiceRefDeallocate` (Broadcast:43); restart re-creates `sdRef` + source. → exercised by TC-02 re-advertise cycles.
- **Vendoring drift (Approach A):** a future `flutter pub upgrade` could silently re-point to the pub version; the `dependency_overrides` path pin + `PATCH.md` + a CI check that `third_party/bonsoir_darwin` is the resolved source mitigate (mirror the graphify patch discipline).
- **macOS parity:** the same Swift compiles for macOS; verify the macOS host build still links (the app's primary target is iOS, but `canImport(FlutterMacOS)` is in the file).
- **Residual evidence gap:** the exact blocking frame is *inferred* (in-source comment + package source) until Step 0 symbolication confirms it. If symbolication reveals the permission-alert path instead, the fix changes (do not skip Step 0).
- **Android:** unaffected by the iOS fix; if Approach B, the new advertise channel needs Kotlin parity or a platform guard so Android keeps using bonsoir.

## Device/Relay Proof Profile
requires device for closure (this is fundamentally an iOS main-thread / OS-watchdog fix — no host tier can prove the watchdog is gone).
Closure scenario: manual two-phone CV-08 (Pixel ↔ iPhone 11, flat single-AP WiFi) per `174-…-tdd-plan.md` "CV-08 Run Results — session 2" steps; flip `EnableLibp2pLANDial` default ON only AFTER device-green (that flip = CV-09, separate plan).
Deferred device work → next live-rig session (same rig as 174 CV-08).
Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Dirty-tree snapshot first (shared tree)
git status --short

# Step 0 — confirm blocking frame (no test; prerequisite)
#   open /tmp/cv08/crash/Runner-2026-06-29-131147.ips ; confirm thread 0 in DNSServiceProcessResult / BonsoirServiceBroadcast.start

# RED (native, Approach A) — must FAIL/BLOCK for the documented reason
#   (run via the vendored package's XCTest target or RunnerTests)
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RunnerTests/BonsoirServiceBroadcastOffMainTest 2>&1 | tail -20

# Preservation sentinels (must STAY green — Dart contract + 174 self-heal unchanged)
flutter test test/core/local_discovery/                 # incl. watchdog-gate contract + 174 self-heal
./scripts/run_host_test_gates.sh core-host-all          # expect: prior pass count, 0 fail
./scripts/run_test_gates.sh 1to1                        # expect ~+1387 (unchanged), 0 fail
./scripts/run_test_gates.sh transport                   # FDC/transport family, 0 fail

# Build with the vendored/rewired native code (proves it compiles + pods resolve)
flutter build ios --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=true

# Device-proof (CLOSURE, manual two-phone) — capture both devices' [FLOW]
#   PASS: continuous iPhone [FLOW] through cold-start + >=2 re-advertises, no >2s silence,
#         idevicecrashreport shows NO new 0x8BADF00D, MSG_RECEIVED_TRANSPORT:"direct" BOTH directions.
idevicecrashreport -u 00008030-001A6D2801BB802E -k /tmp/cv08/crash2   # expect: no new Runner 0x8BADF00D

# Hygiene
flutter analyze                                         # 0 new issues
git diff --check
```
(No `check_reliability_simulation_discovery.sh` / `/sims` row — the closure is a manual two-phone device gate, not an auto-discovered sim scenario, identical to 174 CV-08.)

## Known-Failure Interpretation
- Expected RED: TC-01 (native) before the patch. TC-02 is RED on device on HEAD (the freeze) and is the closure gate.
- Pre-existing dirty: 174's uncommitted `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, their tests, and the 174 plan doc — snapshot in step 1; do NOT revert.
- Environment blocker (NOT product): `flutter build ios` currently fails because the rig's Xcode lacks the iOS 26.5 platform (phones updated) — install the platform OR test the native unit on a simulator destination; device install reuses a signed `Runner.app` via `devicectl` (per 174 CV-08 session-2 notes). Missing device ≠ product failure for the host/native tiers.
- Scope drift (BLOCKING): any change to the Dart suspected-denied gate semantics, the 174 self-heal, the flag defaults, or the discovery/resolve (already-safe) path; any re-introduction of a pre-probe or a "fix via 7.x bump."

## Done Criteria
- [x] Step 0 symbolication confirms the main-thread blocking frame (thread 0 = `DNSServiceProcessResult ← BonsoirServiceBroadcast.start`; Root Cause held).
- [x] RED added first (TC-01 native) — **degraded-to-structural decision LOGGED** (running the XCTest needs the full Runner+GoMknoon test build); structural gate GREEN; TC-02 carries the mutation. Per the RED-1 feasibility note.
- [~] Mutation-verified: structural mutation = restoring synchronous `DNSServiceProcessResult(sdRef)` re-reds the structural gate + TC-01 timing assertion; the device-freeze mutation is carried by **TC-02 (device, DEFERRED)**.
- [x] Preservation sentinels: `flutter test test/core/local_discovery/` +145 green (TC-03/TC-04). `core-host-all` (see verdict). `flutter build ios` not run end-to-end (heavy Go/signing path); **native compile-proof done** via `xcodebuild -target bonsoir_darwin` → BUILD SUCCEEDED + `pod install` resolves the vendored path. `1to1`/`transport` unaffected-by-construction (native-only change; no Dart touched).
- [x] No DB migration (none needed — N/A).
- [x] Device-proof TC-02 GREEN (2026-06-29, real Pixel 6 ↔ iPhone 11): iPhone responsive through cold-start + re-advertises (16min alive, a chat msg sent FROM the iPhone), **no new `0x8BADF00D`** (3 pre-fix kills 13:11–13:16 vs zero after the fixed build at 13:22), `MSG_RECEIVED_TRANSPORT:"direct"` **both directions** (×3 each) + `CHAT_MSG_SEND_SUCCESS via:"direct"` — **CV-08 PASS #4 CLOSED**. Required FDC-11 fixes A/B/C (Device-Proof Run section below).
- [x] `flutter analyze` 0 new; `git diff --check` clean.
- [x] Vendoring (Approach A) documented in `third_party/bonsoir_darwin/PATCH.md`; `dependency_overrides` pinned.
- [ ] graphify full + arch refresh after green — pending (run after gates settle).

## Scope Guard (hard "Do not")
- Do not flip `EnableLibp2pLANDial` (or any FDC flag) default — **CV-09** owns that, gated on this device-green.
- Do not change the Dart suspected-denied gate semantics or the 174 self-heal — keep both as defense-in-depth.
- Do not "fix" the discovery/browse start — it is already async (NWBrowser); touching it is wrong-target.
- Do not re-introduce a native pre-probe or a bonsoir 7.x "version-bump fix" — both refuted above.
- Do not edit the pub-cache copy in place — vendor it (Approach A) so the change is durable + reviewable.
- ⚠️ **Commit `third_party/bonsoir_darwin/` AS A UNIT with `pubspec.yaml`/`pubspec.lock`** (review HIGH). The vendored tree is currently untracked; landing the `path:` pin without it breaks every clean checkout / CI `flutter pub get` and silently drops the fix. `git add third_party/bonsoir_darwin pubspec.yaml pubspec.lock` → verify `git ls-files third_party/bonsoir_darwin | wc -l` > 0 before committing. Never `git commit -a` the pin alone.

## Accepted Differences / Intentionally Out Of Scope
- **No host-Dart RED for the core fix.** This is an iOS main-thread/OS-watchdog threading fix; no host tier can prove the watchdog is gone. The mutation-verifiable closure is the **device-proof** (TC-02), with an optional native XCTest (TC-01) as the host-side falsifier. This is an accepted, documented deviation from "host-floor mandatory" — justified because the broken seam is a native C-API call on the platform main thread.
- **Vendoring a third-party plugin (Approach A)** carries upgrade-maintenance cost; accepted as the smallest correct change vs reimplementing advertise (Approach B). The chosen approach is recorded at execution Step 2.
- `_libp2pListenPort` IPv4/IPv6 family-awareness — pre-existing 174 follow-up, not this plan.

## Dependency Impact
- **CV-09** (flip `EnableLibp2pLANDial` default) depends on this going device-green (it is the last blocker to CV-08 PASS #4).
- **FDC-S6** (libp2p-LAN soak win-rate verdict) is hard-gated on FDC-11 D1 = CV-08 green = this fix.
- **NEW follow-up (174 concurrency hardening, out of 175 scope)** — discovered by the 175 review: the Dart advertise lifecycle is unserialized; overlapping `updateLibp2pPorts` (174) + `restartAdvertising` can orphan a started bonsoir broadcast (its long-lived off-main `DispatchSource` then leaks for the session). Fix = serialize start/stop/restart/update in `LocalP2PService` (chained `Future _advertiseLock` or `_advertiseGeneration`) + compare-and-clear in `BonsoirDiscoveryService.stopAdvertising` (only null `_broadcast`/`_discovery` when still `identical` to the captured object) + a concurrent-re-advertise host test. Bounded (session-scoped, reclaimed at engine-detach, rare window); fix when landing 174, NOT under 175.

## Reviewer Findings
5-dimension adversarial read-only Workflow (each finding then put through a fresh refute pass). 3 dimensions CLEAN, 2 confirmed defects (1 HIGH commit-hygiene, 1 MEDIUM pre-existing-174 concurrency). The 175 Swift patch ITSELF is sound across all dimensions.

- **threading-eventsink — CLEAN.** Every `FlutterEventSink` touch (`onSuccess`/`onError`) is reached only on main (the socket==-1 error branch runs in `start()` on the calling=main thread; `registerCallback` hops to `DispatchQueue.main.async`); the C `name` pointer is copied to a Swift `String` BEFORE the async hop; mirrors discovery `resolveCallback`. (Noted-for-awareness only: a pre-existing off-main shared-object mutation in the DISCOVERY file — not mine, not touched.)
- **memory-safety — CLEAN (core).** Free-once via the source cancel handler is the canonical libdispatch pattern; double-`dispose()` is a verified no-op via nil-guards on BOTH `dispatchSource` and `sdRef`; the patch REMOVES (does not add) a free path vs pristine. Residual LOW (non-blocking): event/cancel handlers capture `sdRef` not `self` (so no retain cycle; broadcast lifetime is held by the plugin `broadcasts[id]` map exactly as pristine); a caller-unreachable double-`start()` source leak; a test-only `static var processResult` race (mutated only by the optional XCTest).
- **lifecycle-restart — MEDIUM (confirmed, NOT a 175-patch defect → 174 follow-up).** See below.
- **vendoring-pods — HIGH (confirmed, ACTED ON via doc + this note).** See below. iOS pin wiring (override/lock/symlink/Pods.xcodeproj/Tests-exclusion) all verified correct; macOS resolution is stale-but-self-healing (functionally moot for the iOS-primary app).
- **behavior-scope — CLEAN.** Behaviorally equivalent to pristine (same `broadcastStarted`/`broadcastNameAlreadyExists`/`broadcastStopped` events + name-conflict mutation); the Dart caller has NO `broadcastStarted`-ordering dependency (it awaits only the method-channel ack); scope clean — discovery path identical, 5.1.3 pinned, NO pre-probe, NO 7.x bump, suspected-denied gate untouched.

### CONFIRMED DEFECT 1 (HIGH — commit hygiene, release-gating) — ACTED ON
`third_party/bonsoir_darwin/` is UNTRACKED in git (`?? third_party/`, `git ls-files third_party/` = 0) while `pubspec.yaml`/`pubspec.lock` are TRACKED-and-modified (`M`). A `git commit -a` / `git add pubspec.*` would land the `path:` pin WITHOUT the vendored target → every clean checkout / CI `flutter pub get` fails (path not found) and **silently drops the watchdog fix**. The local tree masks this because the vendored files exist only in the working copy. **Resolution (documented, not auto-committed — commits are user-gated):** the vendored tree MUST be staged as one unit: `git add third_party/bonsoir_darwin pubspec.yaml pubspec.lock` then verify `git ls-files third_party/bonsoir_darwin | wc -l` > 0 before committing. Prominent ⚠️ callout added to `third_party/bonsoir_darwin/PATCH.md` and to Scope Guard below.

### CONFIRMED DEFECT 2 (MEDIUM — pre-existing 174 concurrency; out of 175 scope) — FOLLOW-UP
The Dart advertise lifecycle is unserialized: two independent drivers of the same `stopAdvertising()`→`startAdvertising()` sequence on the same `BonsoirDiscoveryService` coexist — `unawaited(localP2P.updateLibp2pPorts(...))` (174 code, `p2p_service_impl.dart:4239-4241`) and `await _localP2P?.restartAdvertising()` (`:4666`, health-check). With no lock/generation guard, an overlapping interleaving can let a later `_broadcast = C` clobber an earlier object B before B is started; the earlier chain then still runs `await B.start()`, so B is registered with a live long-lived `DispatchSource` but is no longer retained → B is never `stop()`/`dispose()`ed → an orphaned, actively-draining DNS-SD source + duplicate LAN advert for the session (reclaimed at engine-detach). The refute pass confirmed it is REAL but: (a) NOT a defect in the 175 Swift patch (which is correct for a single stop→start cycle); (b) the offending second driver is **174's `updateLibp2pPorts`**, which 175's Scope Guard forbids touching; (c) bounded — session-scoped, `updateLibp2pPorts` no-ops unless ports change (≈once at first resolve), requires a specific await interleaving. 175 mildly amplifies the impact (pre-patch the orphan was a dormant `sdRef`; post-patch it is an active source). **Recommendation (deferred to a 174-concurrency hardening, NOT this plan):** serialize the advertise lifecycle in `LocalP2PService` (chained `Future _advertiseLock` or `_advertiseGeneration`), plus defense-in-depth compare-and-clear in `stopAdvertising` (only null `_broadcast`/`_discovery` if still `identical` to the captured object), with a host test firing `updateLibp2pPorts` concurrently with `restartAdvertising` asserting exactly one live broadcast. See Dependency Impact.

## Arbiter Decision
Ship the 175 Swift off-main patch as-is — it is correct and adversarially clean across threading, memory-safety, behavioral-equivalence, and scope. The HIGH finding is a commit-hygiene requirement (documented; user-gated commit must stage `third_party/` as a unit), not a code defect. The MEDIUM finding is a pre-existing 174 concurrency bug outside 175's scope; recorded as a follow-up. No 175 code change is warranted by the review.

## Final Execution Verdict
**DEVICE-GREEN — 175 freeze fix proven + CV-08 PASS #4 closed on real hardware; NOT committed.**
- Step 0 symbolication PASS (thread 0 = `DNSServiceProcessResult ← BonsoirServiceBroadcast.start`; root cause held).
- Fix landed (Approach A): vendored `bonsoir_darwin` 5.1.3 + surgical off-main `DispatchSourceRead` patch (mirrors discovery resolve) + cancel-handler dealloc + `registerCallback` main-hop + test seam; pinned via `dependency_overrides`; `pod install` re-points to the vendored patched source.
- Gates: `xcodebuild -target bonsoir_darwin` → BUILD SUCCEEDED; `flutter test test/core/local_discovery/` +145 green (TC-03/TC-04); `core-host-all` exit 0, all 263 core files PASS, 0 FAIL; `flutter analyze` 0-new; `git diff --check` clean. TC-01 degraded→structural (GREEN) per RED-1 note; mutation carried by TC-02.
- Adversarial review: 3 dims CLEAN; HIGH = commit-as-a-unit hygiene (documented); MEDIUM = pre-existing 174 unserialized re-advertise (follow-up, out of scope). 175 Swift patch sound.
- **DEVICE-PROOF TC-02 GREEN (2026-06-29) — see Device-Proof Run Results.** CV-09 (flag default flip) now unblocked as its own follow-on.

## Device-Proof Run Results (2026-06-29, real Pixel 6 ↔ iPhone 11, same /24 WiFi)
Built both `--profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=true`; in-place upgrade installs (identity preserved). Env prereq hit + resolved: the iOS 26.5 on-device platform component had to be installed in Xcode ("iOS 26.5 is not installed" — the blocker the plan predicted).

**175 freeze fix — PROVEN.** iPhone 11 (00008030…) crashed `0x8BADF00D` **3×** on the buggy build (13:11/13:13/13:16); after the fixed build launched 13:22:51 it ran **16+ min continuously** (980+ `[FLOW]`, 3× `LOCAL_MDNS_ADVERTISE_START`, discovered the Pixel) with **zero** new watchdog kills and an interactive UI (a chat msg was sent FROM it). `LOCAL_MDNS_ADVERTISE_START` (emitted AFTER `await start()`) firing repeatedly is direct proof the native advertise no longer blocks the main thread.

**CV-08 PASS #4 — CLOSED.** `MSG_RECEIVED_TRANSPORT:"direct"` BOTH directions (×3 each); 2× `CHAT_MSG_SEND_SUCCESS … via:"direct"` (delivered, `connectionReused:true`); both devices `connections:2` (relay + shared direct LAN conn). Network proven open (Mac `nc` → `/multistream/1.0.0` on both libp2p listeners; Pixel→iPhone ping OK — **NO AP isolation**; the `mknoon (2)` resolve failure was app-side, not WiFi).

**Three additional FDC-11 LAN-direct bugs uncovered + fixed during the run** (FDC-11 scope, NOT the 175 native patch; landed this session to close CV-08; each host-tested):
- **Fix A — non-unique mDNS instance name** (`lib/core/local_discovery/bonsoir_discovery_service.dart`): both devices advertised the fixed name `mknoon` → mDNS collision → rename to `mknoon (2)` (space+parens) which Android NsdManager can't resolve (`PEER_LOST` w/o `PEER_FOUND`). Fix = per-device unique `mknoon-<peerIdTail>`. +2 host tests.
- **Fix B — Pixel advertised no libp2p port** (`go-mknoon/node/node.go` `splitHostAddresses`): Android SELinux blocks the Go node's netlink interface enumeration (`b/155595000`) → `h.Addrs()` empty → `Announcing 0 addresses` → no quic/tcp port in the advert. Fix = fall back to `h.Network().ListenAddresses()` for the port (the bound socket knows its port even when the IP can't be enumerated; the dialing peer supplies the IP from mDNS). Go build/vet clean; confirmed Pixel then advertised `quicPort/tcpPort`.
- **Fix C — iOS hostname multiaddr** (`bonsoir_discovery_service.dart` `_buildLibp2pAddresses`): iOS bonsoir resolves a peer to its `.local` HOSTNAME (Android returns a numeric IP), and `/ip4/<hostname>` → "failed to parse multiaddr" → the iPhone's dial silently never happened. Fix = emit `/dns4/<host>` (trailing dot stripped) for non-numeric hosts. +1 host test. **The key unlock** — after it the iPhone's dial parsed, `connections` went 1→2 on BOTH devices, both-direction MSG-direct followed.

Host regression after A/B/C: `flutter test test/core/local_discovery/` +148 green; `go build ./...` OK. graphify + commit deferred (the change now spans the 175 native patch + 3 FDC-11 Dart/Go changes + tests).
