# 178 - Bonsoir suspected-denied gate over-latches + skips the browse  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — found during CV-34 / FDC-S6 device work (2026-06-29)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-29 | Evidence Collector | bonsoir_discovery_service.dart:151-265,305-315,395-460; 175 PATCH.md; device logs | root cause confirmed in source + device-confirmed | hand to Planner |
| 2026-06-29 | Planner | (above) | platform-gate latch to iOS + decouple browse from broadcast gate | emit plan |
| 2026-06-29 | Reviewer / Arbiter | this plan | host RED→GREEN gating; Pixel-discovers-iPhone = device closure | hand off |

## Source Of Truth
- Bug: `lib/core/local_discovery/bonsoir_discovery_service.dart` — `startAdvertising:166-174` (the skip), `_armSuspectedDenialProbe:250-265` (the latch), the clear-on-resolve (`:305-315`), `restartAdvertising` (preserves `_suspectedDeniedUntil`).
- Watchdog rationale: `third_party/bonsoir_darwin/PATCH.md` (plan 175) + memory `project_bonsoir_localnetwork_watchdog_crash_fix`.
- Gate definitions: `scripts/run_test_gates.sh` / `run_host_test_gates.sh`.

## Session Classification
implementation-ready (host RED→GREEN is the gating deliverable; the Pixel-discovers-iPhone two-phone run is the closure).

## Exact Problem Statement
The pure-Dart "suspected-Local-Network-denied" gate in `bonsoir_discovery_service.dart` **over-latches and self-reinforces**, blocking same-WiFi peer discovery on the discoverer side.

`startAdvertising` checks `_suspectedDeniedUntil` (`:166`) and, when latched, **returns early (`:174`) before BOTH** the broadcast start (`:198-200`) **and** the discovery/browse start (`:209-213`). The latch is set by `_armSuspectedDenialProbe` (`:252`) when the probe window lapses with `_peers.isEmpty` (`:254`), and is only cleared when a real peer **resolves** (`:311`) — which requires the **browse to be running**. So once latched, the browse is off → no peer can resolve → the latch can't self-clear → it stays stuck for the full 5-min backoff, and a restart re-latches within ~16 s.

**Device-confirmed (2026-06-29, Pixel 6 ↔ iPhone 11, same flat WiFi):** the Pixel repeatedly emits `LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED{backoffMs:300000}` + `LOCAL_MDNS_START_SKIPPED_SUSPECTED_DENIED` and never discovers the iPhone — even though the iPhone IS advertising (Mac `dns-sd -B _mknoon._tcp` sees both phones' `mknoon-<peerIdTail>` services), the iPhone's browse finds the Pixel fine, and the Pixel granted FINE_LOCATION + NEARBY_WIFI_DEVICES. A false-positive suspected-denial.

**Impact:** blocks the discoverer side of FDC-11 LAN-direct, FDC-15 LAN-media (CV-34 Pixel→iPhone never engaged the local path), and the FDC-S6 soak's i→A clean-LAN certification. The single recurring rig blocker across the FDC LAN campaign.

**What must improve:** the discoverer (esp. Android) must keep browsing and discover same-WiFi peers.
**What must stay unchanged (preserved-green sentinels):** the iOS `0x8BADF00D` watchdog protection (175 stays intact; iOS still gates the *broadcast* on a suspected denial); the iPhone→Pixel direction (the Pixel must keep advertising so iOS keeps finding it); the local_discovery host suite.

## Root Cause (verify → refute confirmed)
Two coupled defects, both confirmed in source:
1. **Skip-the-browse self-reinforcing latch:** the gate (`:166-174`) skips the *whole* `startAdvertising`, killing the browse, but the only un-latch path (`:311`) needs the browse. So a latch is terminal until backoff.
2. **Platform-blind latch:** the gate is the "iOS Local Network watchdog" gate (`:160,449`), but `_armSuspectedDenialProbe:254` latches on **any** platform. On **Android** there is no Local-Network-permission scene-update watchdog (the `0x8BADF00D` class is iOS-only; Android's `b/155595000` SELinux issue is a *different* problem handled by Fix B / `node.go splitHostAddresses`, not the bonsoir browse). And gating the *broadcast* on Android would break the working iPhone→Pixel direction (which needs the Pixel's advert).

**Premise largely obsoleted:** the gate existed to stop the iOS native `BonsoirServiceBroadcast.start()`'s **synchronous main-thread `DNSServiceProcessResult`** from tripping the 10 s watchdog. **Plan 175** moved that off-main (`DispatchSourceRead`), and upstream 5.1.3 already moved the **discovery-resolve** path off-main — so the native start no longer blocks the main thread.

**Refuted / do-NOT-re-introduce:**
- ❌ "Already fixed on HEAD." REFUTED — `:166-174` returns early before discovery; device-reproduced ×many.
- ❌ "It's a genuine Android Local Network permission denial." REFUTED — perms granted; Mac sees both adverts; iPhone finds the Pixel. The browse would work; the gate just never lets it run.
- ❌ "Reintroduce a native permission pre-probe to decide denial." OUT OF SCOPE — 175's refute pass killed the native pre-probe (false-skip regression). Keep the heuristic, fix its blast radius.
- ❌ "Revert 175 / reintroduce the main-thread-block vector." FORBIDDEN.

## Real Scope
**In scope (`bonsoir_discovery_service.dart` only):**
1. **Platform-gate the latch to iOS** — `_armSuspectedDenialProbe` sets `_suspectedDeniedUntil` only when `defaultTargetPlatform == TargetPlatform.iOS` (use `defaultTargetPlatform`, NOT `dart:io Platform`, so host tests can override via `debugDefaultTargetPlatformOverride`). Android never latches.
2. **Decouple the browse from the broadcast gate (iOS):** restructure `startAdvertising` so the suspected-denied skip applies ONLY to the **broadcast** block (`:184-206`); the **discovery/browse** block (`:209-219`) ALWAYS runs (it is off-main-safe). Emit a distinct `LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED` for the gated-broadcast case so the browse-ran-anyway path is observable. This lets a resolved peer (`:311`) self-clear the latch on iOS too.

**Out of scope:** the Go side (Fix B SELinux netlink — unrelated); the 175 vendored bonsoir; Android `b/155595000`; any native permission probe.

## Files To Inspect Next
Production (edit): `bonsoir_discovery_service.dart:151-265` (startAdvertising + probe), `:305-315` (clear), `:449-460` (isLatched).
Test (edit): `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart`.
Dependency-only: `third_party/bonsoir_darwin/PATCH.md` (175 rationale — do NOT change).

## Existing Tests Covering This Area
- `bonsoir_discovery_service_contract_test.dart` (+142 from the 175/watchdog work) — covers the latch/skip/clear with injected `suspectedDenialProbe`/`suspectedDenialBackoff` durations + fake broadcast/discovery. EXISTS.
**Gaps:** no test asserts (a) Android does NOT latch, (b) the browse runs while the broadcast is gated, (c) self-clear works because the browse is running. Add these.
**Curated arrays?:** No — `test/core/**` AUTO-glob (`core-host-all` / local_discovery gate).

## RED Test Catalog  (add BEFORE the production edit — INV-RED-FIRST)
1. `bonsoir_discovery_service_contract_test.dart::'Android never latches the suspected-denied gate'`
   - Tier: unit (host). Setup: `debugDefaultTargetPlatformOverride = TargetPlatform.android`; start with a fake discovery that resolves ZERO peers; advance the injected probe window.
   - RED on HEAD: `_armSuspectedDenialProbe:254` latches regardless of platform → `isLatched`/`LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED` fires.
   - GREEN: on Android the probe does NOT latch (`isLatched == false`, no LATCHED event); the browse stays up.
   - Mutation: revert the platform guard → Android latches → red.
2. `bonsoir_discovery_service_contract_test.dart::'iOS suspected-denied skips the broadcast but KEEPS the browse running'`
   - Tier: unit (host). Setup: `TargetPlatform.iOS`; force a latch (probe window, 0 peers); then `restartAdvertising`.
   - RED on HEAD: the restart returns early at `:174` → NO `LOCAL_MDNS_DISCOVERY_START`.
   - GREEN: `LOCAL_MDNS_DISCOVERY_START` fires (browse runs) AND `LOCAL_MDNS_ADVERTISE_START` does NOT (broadcast gated) AND `LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED` fires.
   - **Distinct-event discriminator:** assert `DISCOVERY_START` present AND `ADVERTISE_START` absent in the same restart (proves "browse runs, broadcast gated", not "both run" or "both skipped").
   - Mutation: revert the decouple → `DISCOVERY_START` absent when latched → red.
3. `bonsoir_discovery_service_contract_test.dart::'iOS latch self-clears when a peer resolves via the still-running browse'`
   - Tier: unit (host). Setup: `TargetPlatform.iOS`; latch; restart (browse now runs); inject a peer resolve.
   - RED on HEAD: browse is off when latched → no resolve → `isLatched` stays true forever.
   - GREEN: the resolve clears `_suspectedDeniedUntil` (`isLatched == false`); the next start re-advertises.
   - Mutation: revert decouple → red (browse never runs to deliver the resolve).
4. (preserve — INV) `bonsoir_discovery_service_contract_test.dart::'iOS still gates the broadcast on suspected denial (watchdog protection)'`
   - Tier: unit. Asserts that on iOS, while latched, the broadcast (re)start is SKIPPED (`ADVERTISE_START` absent, `ADVERTISE_SKIPPED_SUSPECTED_DENIED` present). This is the 175/watchdog protection retained. Mutation: remove the broadcast gate entirely → this red (watchdog vector reopened).

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-78-01 Android no-latch | platform logic | unit | `…::Android never latches` | `:254` latches platform-blind | revert platform guard → red | `flutter test test/core/local_discovery/bonsoir_discovery_service_contract_test.dart` | AUTO (`test/core/**`) |
| TC-78-02 iOS browse-decouple | control flow | unit | `…::iOS … KEEPS the browse running` | `:174` early-return kills browse | revert decouple → no DISCOVERY_START | same | AUTO |
| TC-78-03 iOS self-clear | state transition | unit | `…::iOS latch self-clears …` | browse off → never clears | revert decouple → red | same | AUTO |
| TC-78-04 iOS broadcast still gated (preserve) | watchdog invariant | unit | `…::iOS still gates the broadcast …` | n/a (preserve) | remove broadcast gate → red | same | AUTO |
| TC-78-05 Pixel discovers iPhone | multi-device / OS-boundary | device-proof | two-phone, Pixel-side `P2P_LAN_PEER_FOUND_REQUEST{lanPrivateIp:true}` + `node:lan_dial_ready` | n/a (closure) | revert fix → Pixel latches, no discovery | manual two-phone | reuses CV-08 rig; capture `[FLOW]` both phones |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the latch is in-memory and `restartAdvertising` deliberately PRESERVES `_suspectedDeniedUntil` (`:398-399`). TC-78-02/03 exercise the restart path (the exact lifecycle that re-enters the gate); the fix must keep working across the stop→start the resume/address-update flow does. Covered.
- **Sibling-surface consistency:** the broadcast (advertise) and discovery (browse) are the two legs `startAdvertising` drives — the fix deliberately treats them ASYMMETRICALLY (gate broadcast, keep browse) and TC-78-02's discriminator test-locks that asymmetry. Covered.
- **Destructive-action side-effects:** N/A — no delete/cleanup; the latch is a skip, not a teardown (`:163-164` notes the objects were already torn down by the restart's stopAdvertising).
- **Invariant re-verification under new transitions:** the new "browse runs while broadcast gated" transition must STILL honor the watchdog invariant (broadcast skipped on iOS) — TC-78-04 re-verifies it; TC-78-03's self-clear re-verifies that a clear restores full advertise+browse.

## Invariants (locked by tests)
- INV-1: Android never latches → TC-78-01.
- INV-2: a suspected-denied latch never kills the browse → TC-78-02 (+ self-clear TC-78-03).
- INV-3 (watchdog): on iOS a suspected denial still skips the *broadcast* (the main-thread DNS-SD vector) → TC-78-04. The iPhone shows zero `0x8BADF00D` on device (TC-78-05).
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (pre-existing dirty: `info.plist`, `project.pbxproj`; note any concurrent-session edits to this file).
2. Add TC-78-01/02/03/04 RED; run the focused cmd → confirm they fail for the documented reasons.
3. Edit `_armSuspectedDenialProbe`: latch only when `defaultTargetPlatform == TargetPlatform.iOS`.
4. Edit `startAdvertising`: gate ONLY the broadcast block on `_suspectedDeniedUntil`; always run the discovery block; emit `LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED` on the gated-broadcast path; keep the backoff-lapse re-probe (`:176-177`). **Stop-if** TC-78-04 (broadcast-still-gated) goes red → the decouple removed the watchdog protection; redesign.
5. Rerun direct → preservation (`run_host_test_gates.sh core-host-all`) → `flutter analyze`.
6. Device closure: Pixel discovers the iPhone (capture `[FLOW]` both phones); iPhone 0× `0x8BADF00D`. After landing: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.

## Risks And Edge Cases
- **Removing the iOS broadcast gate by accident** → reopens the `0x8BADF00D` vector → pinned by TC-78-04 + the device-proof zero-crash check.
- **`dart:io Platform` vs `defaultTargetPlatform`** — must use `defaultTargetPlatform` so host tests override the platform; using `Platform.isIOS` makes TC-78-01 un-testable on the host.
- **Genuinely-alone user (0 peers forever)** on iOS still latches the broadcast (correct — no peer to advertise to); the browse keeps running so the instant a peer appears it resolves + clears. Acceptable.
- **Residual:** if the Pixel's NsdManager genuinely cannot resolve the iPhone's advert even with the browse always running, that is a deeper Android-mDNS issue beyond this gate (would surface as TC-78-05 still failing despite the host fix) — flagged, not assumed.

## Device/Relay Proof Profile
Host RED→GREEN is the gating deliverable. **Device closure:** Pixel 6 (`21071FDF600CSC`) + iPhone 11 (`00008030-001A6D2801BB802E`), same flat WiFi, profile build `--dart-define=FDC_FLOW_LOG=1` (LAN-dial default-on). Bring up both apps (tap-launch iPhone to avoid the GPU black screen); confirm the **Pixel** logs `P2P_LAN_PEER_FOUND_REQUEST{lanPrivateIp:true}` + `node:lan_dial_ready` (it now discovers the iPhone) and **no** `LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED`; iPhone shows zero `0x8BADF00D`. This also unblocks CV-34 Pixel→iPhone LAN-media + the FDC-S6 i→A soak direction.

## Acceptance Gates  (literal)
```bash
# RED (before edit) — must FAIL for the documented reason
flutter test test/core/local_discovery/bonsoir_discovery_service_contract_test.dart

# Direct GREEN (after edit)
flutter test test/core/local_discovery/bonsoir_discovery_service_contract_test.dart

# Preservation
flutter test test/core/local_discovery/                       # whole local_discovery dir green
./scripts/run_host_test_gates.sh core-host-all

# Hygiene
flutter analyze            # 0 new
git diff --check

# Device closure (manual two-phone): build profile FDC_FLOW_LOG=1, bring up both,
# confirm Pixel P2P_LAN_PEER_FOUND_REQUEST + lan_dial_ready (no SUSPECTED_DENIED latch); iPhone 0x8BADF00D=0
```

## Known-Failure Interpretation
- Expected RED: TC-78-01/02/03 before the edit.
- Pre-existing dirty (do NOT revert): `info.plist`, `ios/Runner.xcodeproj/project.pbxproj`.
- Environment blocker (NOT product): multi-AP WiFi dropping mDNS multicast; a black iPhone app screen from `devicectl --terminate-existing` (tap-launch instead).
- Scope drift (BLOCKING): any change to the 175 vendored bonsoir, the Go side, or a new native permission probe.

## Done Criteria
- [x] RED added first (TC-78-01/02/03/04), failed for the documented reason (platform-blind latch; `:174` early-return kills browse; browse-off-never-clears; old event name).
- [x] Mutation-verified — forcing `broadcastGated = false` (remove the broadcast gate) re-reds TC-78-04 + TC-78-02 (watchdog vector reopened); TC-78-01/02/03 are RED-on-HEAD (HEAD = the reverted state for the platform-blind + coupled-gate mutations).
- [x] Direct GREEN (23/23) + local_discovery dir (155) + `core-host-all` (264 files) green; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Device: Pixel discovers the iPhone (no latch); iPhone 0× `0x8BADF00D`. — **manual two-phone, NOT runnable in this env; remains the closure step.**
- [x] Post-land: `graphify update .` (full graph) + `./graphify-arch/refresh_arch_graph.sh` (arch graph) — both refreshed ~21:46-21:47 (arch committed as `51f8c216`).

## Scope Guard (hard "Do not")
- Do NOT revert / modify the 175 vendored `third_party/bonsoir_darwin` off-main fix.
- Do NOT remove the iOS broadcast suspected-denied gate (the watchdog vector protection).
- Do NOT add a native Local-Network permission pre-probe (175 refuted it).
- Do NOT touch the Go side or Android `b/155595000` handling.

## Accepted Differences / Intentionally Out Of Scope
- The suspected-denial heuristic (latch on a 0-peer window) is KEPT on iOS as belt-and-suspenders even though 175 made the native start off-main — relaxing it further (shorter backoff, multi-window) is a possible follow-up, not this fix.

## Dependency Impact
- Unblocks: FDC-15 CV-34 Pixel→iPhone LAN-media (the local path can now engage on the Pixel), the FDC-S6 soak i→A clean-LAN certification (Pixel-side discovery records), and general FDC-11 LAN-direct reliability on the discoverer side.

## Reviewer Findings
Sufficiency: 4 host RED rows (each tier+mutation+literal-gate+AUTO-registration) + 1 device-proof closure; the watchdog-regression risk is mutation-locked by TC-78-04 (the single most important guard) + the device zero-crash check; the asymmetric broadcast-vs-browse treatment is discriminator-locked by TC-78-02. Refuted hypotheses recorded. Blind-spot sweep: lifecycle (restart path) + sibling (2 legs) + invariant-re-verify covered; destructive N/A. Evidence: full gate read in source + extensive device repro.

## Arbiter Decision
Structural blockers: none. **implementation-ready.** Device closure is manual two-phone (reuses the CV-08 rig).

## Final Execution Verdict
Verdict: **EXECUTED — host RED→GREEN complete; SHIP-WITH-FOLLOWUPS** (device closure pending, manual). | Files changed: 1 prod (`bonsoir_discovery_service.dart`) + 1 test (`bonsoir_discovery_service_contract_test.dart`) — landed in commit `48c1576f` by a concurrent session on the shared tree (content byte-identical to the tested working tree; no clobber). | Tests run: focused contract 23/23 GREEN (was +19 then +4 new RED-first); `test/core/local_discovery/` 155 GREEN; `core-host-all` 264 files PASS; `flutter analyze` 0 new; `git diff --check` clean. | Blocking: none. | QA verdict: 4-lens adversarial review = SHIP-WITH-FOLLOWUPS — both must-pass invariants HELD (watchdog: `_broadcast.start()` unreachable while latched, TC-78-04; Android-never-latches: only set-to-future of `_suspectedDeniedUntil` is behind the iOS guard, TC-78-01). | Non-blocking follow-ups: (1) on iOS self-clear, the latch ungates the *next* start but does not proactively re-advertise — the alone-then-peer-appears window stays non-advertising until the next resume/port-change (strictly better than HEAD, which also killed the browse; plan-accepted, TC-78-03 codifies "re-advertise on next start"); (2) relax the iOS heuristic further (multi-window/shorter backoff); (3) the manual two-phone device proof (TC-78-05).
