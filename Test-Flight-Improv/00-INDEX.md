# Test-Flight-1 Improvement Reports

Generated: 2026-04-04

**Closure note:** Sessions `1` through `29` are closed execution artifacts.
`session-30-plan.md` is a plan-only narrow reopen artifact and should not be
read as landed work. `session-31-plan.md`, `session-32-plan.md`,
`session-34-plan.md`, `session-35-plan.md`, `session-36-plan.md`, and
`session-37-plan.md` are completed narrow closure sessions, including the
intro-to-Orbit / intro-to-Feed follow-up closure from Session `35`. Sessions
`44` through `47` are completed Report `24` execution/closure artifacts, with
`24-cancel-media-upload-session-breakdown.md` and the stable messaging closure
references carrying the maintenance-time meaning. Sessions `54` and `55` are
completed Report `27` execution/closure artifacts, with
`27-persistent-nav-bar-orbit-session-breakdown.md` carrying the
maintenance-time meaning. Session `56` is the completed Report `28`
execution/closure artifact, with
`28-orbit-intro-badge-session-breakdown.md` carrying the maintenance-time
meaning. Sessions `58` and `59` are the completed Report `29`
execution/closure artifacts, with
`29-batch-parallel-intro-sending-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Sessions `59` and `60` for Report
`30` are the completed Report `30` execution/closure artifacts, with
`30-swipe-nav-feed-orbit-session-breakdown.md` carrying the maintenance-time
meaning. The doc-scoped Session `1` for Report `34` is the completed Report
`34` execution/closure artifact, with
`34-orbit-intros-swipe-delete-missing-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Session `1` for Report `35` is the
completed narrow reopen/closure artifact for the late-boundary 1:1 video
cancel seam, with
`35-cancelled-video-upload-still-sends-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Sessions `1` through `3` for Report
`41` are the completed inbox-recovery and notification-open trust closure
artifacts, with
`41-notification-open-missing-incoming-messages-session-breakdown.md` plus the
refreshed 1:1 closure reference carrying the maintenance-time meaning. The
doc-scoped Session `1` for Report `44` is the completed Feed/Orbit handled
notification sync closure artifact, with
`44-feed-orbit-notification-desync-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Session `1` for Report `45` is the
completed Feed inline-reply viewport reorientation closure artifact, with
`45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
carrying the maintenance-time meaning. The doc-scoped Session `1` for Report
`48` is the
completed automatic 1:1 inbox-drain fallback removal closure artifact, with
`48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md` plus the
refreshed 1:1 closure reference carrying the maintenance-time meaning. The
doc-scoped Sessions `1` through `10` for Report `50` are the completed
two-simulator coverage-refresh artifacts, with
`50-two-simulator-user-journey-tests-todo-session-breakdown.md` plus the
refreshed audit/journey docs carrying the maintenance-time meaning. The
doc-scoped Sessions `1` and `2` for Report `55` are the completed Report `55`
execution/closure artifacts, with
`55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
carrying the maintenance-time meaning. The doc-scoped Session `1` for Report
`76` is the completed outbound 1:1 v2-only privacy closure artifact, with
`76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md` plus the
refreshed 1:1 closure reference carrying the maintenance-time meaning.
The doc-scoped Sessions `1` through `8` for Report `87` are the completed
app-wide light-theme readability closure artifacts, with
`87-app-wide-light-theme-readability-session-breakdown.md` carrying the
maintenance-time verdict `accepted_with_explicit_follow_up` for remaining
device/simulator visual evidence.
Roadmaps `15` and `16` plus the residual reliability/measurement sessions `24`
through `29` remain historical execution artifacts. Reports `01` through `14`
remain the rationale archive. The current closure state lives in Sections `8`,
`9`, and `10` below.

---

## 1. Test Coverage

| Report | Focus |
|--------|-------|
| [01-unit-test-coverage.md](01-unit-test-coverage.md) | Corrected module-by-module unit test picture — broad coverage, narrower remaining gaps |
| [02-integration-test-coverage.md](02-integration-test-coverage.md) | Cross-feature flows, integration quality, and remaining boundary gaps |
| [50-two-simulator-user-journey-tests-coverage-audit.md](50-two-simulator-user-journey-tests-coverage-audit.md) | Refreshed manual-journey coverage matrix plus accepted notification-open contract for the current app |
| [_current-test-map.md](_current-test-map.md) | Compact operator runbook for which tests exist, what they protect, and how to run them now |

**Top finding:** Test coverage is materially stronger than the first pass
suggested. Report `50` is now the folder-local matrix for manual
two/three-simulator journey confidence, `67` is the compact current runbook
for day-to-day test selection, and the old stale Feed-expanded-card
notification-open assumption is retired in favor of the current
conversation/group/intros routing contract.

---

## 2. Smoke Tests

| Report | Focus |
|--------|-------|
| [03-smoke-test-strategy.md](03-smoke-test-strategy.md) | Lean smoke strategy plus change-based regression gates for high-blast-radius subsystems |

**Top finding:** The smallest effective smoke suite is already mostly present in the repo. Reusing existing startup, loading, QR, inbox, posts, and group-smoke tests is better than building a fake-only parallel test app, but smoke alone is not enough for risky shared pipelines such as 1:1 reliability.

---

## 3. Performance

| Report | Focus |
|--------|-------|
| [04-ui-performance.md](04-ui-performance.md) | Profile-gated UI/perf candidates; stale false positives removed |
| [05-database-storage-performance.md](05-database-storage-performance.md) | High-confidence DB/storage cleanups; broad indexing/caching recommendations narrowed |
| [app-smoothness-performance-audit.md](app-smoothness-performance-audit.md) | Release-build (TestFlight/Play) "feels slow/buggy" audit — multi-agent, adversarially verified: per-bubble blur + always-animating ambient bg never let the raster thread rest; chats/feed redo O(N) work per interaction. Quick Wins + High/Medium roadmap |
| [156-app-smoothness-quick-wins-tdd-plan.md](156-app-smoothness-quick-wins-tdd-plan.md) | TDD plan for the 13 Quick Wins (blur removal, RepaintBoundary + reduce-motion, avatar cacheWidth, 2 targeted indices DB v93/v94, ring memo+==, scrub sentinel, media-resolve gate, quote-map O(1), entrance-anim isNew, orbit flags). Host-only closure. IMPLEMENTED host-green |
| [157-app-smoothness-structural-roadmap.md](157-app-smoothness-structural-roadmap.md) | Master roadmap/index for the **structural** (non-quick-win) audit findings: refuted ledger, epic→plan map (158–164), feed_wired collision order, shared infra (coalescing layer, thread-summary pattern, PERF_TARGET harness), Phase-3 ship/defer/drop. Grounded by verify→refute workflow wf_85c86584-4e1 |
| [158-chat-ambient-idle-glow-suppression-tdd-plan.md](158-chat-ambient-idle-glow-suppression-tdd-plan.md) | TDD plan E-A (`critic-2`): stop the 8s ambient glow animating on foregrounded chat/group surfaces for default users (distinct `isChatSurface` _shouldAnimate term) so chrome BackdropFilters become cacheable at rest. Host-only; RED scaffold exists. **First in the 157 build sequence** |
| [159-conversation-list-memoize-coalesce-cap-tdd-plan.md](159-conversation-list-memoize-coalesce-cap-tdd-plan.md) | TDD plan E-B (`main-isolate-blocking-1`/`rebuild-storms-2,3`): memoize `_buildDisplayItems` (1:1 + group), per-frame coalesce the drain setState-storm, cache parsed DateTime, cap the in-memory window. Land the 145/131 preservation lock BEFORE the coalesce. Host-only |
| [160-feed-contact-n1-summary-and-per-event-bound-tdd-plan.md](160-feed-contact-n1-summary-and-per-event-bound-tdd-plan.md) | TDD plan E-C+E-D (`db-persistence-1`/`db-persistence-3`): 1:1 feed N+1 → `getConversationThreadSummaries` + `totalMessageCount` + lazy-on-focus + bounded reaction fan-out; send-merge + paged delete/hide (cap NEWEST-first). feed_wired cluster #1 |
| [161-group-feed-batched-thread-summary-tdd-plan.md](161-group-feed-batched-thread-summary-tdd-plan.md) | TDD plan E-E (`db-persistence-5` query half; index 094 shipped): replace per-group `limit:200` loop with a batched windowed `dbLoadGroupThreadPreviews` (preserve unread/state/preview; no limit-1). Real-DB host tier. feed_wired cluster #2 |
| [162-feed-conversation-media-resolve-sync-and-debounce-tdd-plan.md](162-feed-conversation-media-resolve-sync-and-debounce-tdd-plan.md) | TDD plan E-F (`db-persistence-7`): swap 3 awaited `resolveStoredPath` loops to the existing sync twin + debounce feed reloads. Preserve 127/128 null-cache passthrough. feed_wired cluster #3 |
| [163-feed-orbit-shell-rebuild-and-offscreen-pause-tdd-plan.md](163-feed-orbit-shell-rebuild-and-offscreen-pause-tdd-plan.md) | TDD plan E-G+E-H (`navigation-hangs-2`/`reactive-streams-3`/`animations-repaint-2`): AppShellController notify-kind split (tab vs background side-effects) + per-pane RepaintBoundary + off-screen TickerMode mute + per-handler orbit subscription pause (dirty-flag, not cancel). **REVIEWED 2026-06-24 → minimal scope: active-tab ambient term + AnimatedBuilder child-hoist CUT; anchors corrected for 158 in-tree.** feed_wired cluster #4 |
| [164-cold-start-deferral-and-keychain-mirror-tdd-plan.md](164-cold-start-deferral-and-keychain-mirror-tdd-plan.md) | TDD plan E-I + cold-start-3/5 (`cold-start-1`/`main-isolate-blocking-2`): defer startLiveServices/Firebase off the pre-runApp path, incremental iOS keychain mirror, parallel launch probes. `_setupPushListeners` re-arm = first-class RED; **device-proof is the closure gate** |
| [165-orbit3-arch-overflow-and-avatar-size-tdd-plan.md](165-orbit3-arch-overflow-and-avatar-size-tdd-plan.md) | NEW FEATURE (Orbit3 prototype, visuals-only — NOT performance): replace messy >2-orbit ring-growth with an **arch** above the One Circle holding `+N 👥`; tap → scrollable continuous semi-circle arc panel ("MORE"); + `+/-` avatar-size stepper scaling circle AND panel. Additive `showOverflowNode`/`avatarScale` keep InnerSky/Fisheye byte-identical. Host-only closure; AUTO-glob `feature-host-all` |
| [166-orbit3-arch-anchor-cap-collapse-resize-tdd-plan.md](166-orbit3-arch-anchor-cap-collapse-resize-tdd-plan.md) | MODIFICATION (refines 165): fix arcs OVERLAPPING the inner circle (band bottom ignored the top member's `15·scale` radius) → raise band above the ring; bottom-anchored cap+scroll (reverse ListView, comfortable size, no compression); explicit `orbit3-arch-collapse` button; shrink the oversized `+N` `Orbit3ArchBar` (52→≤38, chip-sized). No-overlap is a geometric INV locked under population AND avatarScale. Host-only; AUTO-glob |
| [167-orbit3-arch-unified-scroll-record.md](167-orbit3-arch-unified-scroll-record.md) | MODIFICATION (refines 166, **workflow-designed** wf_73085ae0-7d0): make the inner circle + ALL arches ONE continuously-scrollable surface ("scroll the entire screen") — single `SingleChildScrollView`+`Column` (arches above, circle last), pinned collapse/stepper/search overlays, `jumpTo(maxScrollExtent)` opens anchored on the circle. Load-bearing INV test: circle avatar + arch avatar resolve to the IDENTICAL `ScrollableState` (RED on HEAD). 51/51 host-green (review-nit fixes); AUTO-glob |
| [168-orbit3-spacing-groups-entrance-100users-tdd-plan.md](168-orbit3-spacing-groups-entrance-100users-tdd-plan.md) | FEATURE BATCH (5 changes, refines 167): C1 second ＋/－ **spacing** stepper (scales orbit-ring radii + arch pitch, orthogonal to avatar size); C2 expanded **group avatars** render with `OrbitalAvatar` parity + stay adjacent; C3 **rise-up fast** entrance (additive `riseUp`/`entranceDelayMs` on shared OrbitalAvatar — bottom-up, not left-right); C4 **no inner-circle re-entrance** on expand (`animateEntrance:false`); C5 **100-user** population. ALL additive (InnerSky/Fisheye/Orbit/Orbit2/feed defaults preserved). Host-only; AUTO-glob |
| [169-orbit3-dimension-persistence-tdd-plan.md](169-orbit3-dimension-persistence-tdd-plan.md) | NEW FEATURE (Orbit3 prototype, **workflow-grounded** wf_2ad5022a): persist the 4 dimension steppers (avatar/spacing/curve/per-arch) across launches + a **Reset-to-default** pill (`orbit3-reset-dimensions`). Mirrors the SecureKeyStore preference pattern (NOT shared_preferences — absent): NEW `Orbit3DimensionPreferences` codec (first NUMERIC pref; clamp-on-decode) + load/save/clear use-cases; optional null-default `SecureKeyStore?` injected at the sole prod mount `feed_wired.dart:2645`. Host-only; AUTO-glob `feature-host-all`. 8 TCs |
| [170-1to1-send-button-frozen-snackbar-overlap-tdd-plan.md](170-1to1-send-button-frozen-snackbar-overlap-tdd-plan.md) | BUG (surfaced during FDC-S4 device testing; **6-agent verify→refute** root-caused): under degraded network the 1:1 composer is unusable for seconds and a red failure **SnackBar covers the Send button**. ONE root cause in `conversation_wired.dart`: the global `_isSending` (set `:2058`, reset only in the `finally` `:2511` after the multi-second awaited send) doubles as the Send-button enable gate (`compose_area.dart:486`) — **S2** frozen button; and floating failure SnackBars (`:2481`/`:3883`, no `margin`) land on the bottom-anchored composer (Scaffold `:4268` has no `bottomNavigationBar`) — **S1**. Fix = optimistic `_isSending` release after the optimistic insert + detached send future; bottom `margin` on failure bars. Host-only; widget-tier; **add to `ONE_TO_ONE_TESTS`**. 5 TCs. Edit/retry/media S2 + inline-banner redesign deferred (siblings). |
| [174-fdc11-lan-dial-advert-libp2p-ports-tdd-plan.md](174-fdc11-lan-dial-advert-libp2p-ports-tdd-plan.md) | BUG (device-verified at CV-08 D1, Pixel↔iPhone11; **7-agent verify→refute** grounded): FDC-11 libp2p LAN-direct never fires on device — the bonsoir advert carries only the wsPort, so discovered peers have empty `libp2pAddresses` and the forwarder skips (`p2p_service_impl.dart:914` — a SYMPTOM, not the cause). Real cause: the FDC-07 cold-start early seam derives **null** libp2p ports (listenAddresses not yet populated), caches them in `local_p2p_service`, and nothing re-derives — `_handleAddressesUpdated:4052` updates state but never re-advertises; the null is **permanent** for the process. Go is CORRECT (resolves `udp/0`→concrete LAN `quic-v1` into `listenAddresses`). Fix = **Dart-only**: new `LocalP2PService.updateLibp2pPorts` (re-advertise on change, no-op unchanged) + `_handleAddressesUpdated` re-derive + numeric `FDC_LAN_ADVERT_PORTS` diagnostic (multiaddrs are redacted in [FLOW]). Host TDD (6 TCs, AUTO `core/**`); CV-08 manual two-phone gate = closure. Do NOT flip the flag (CV-09 owns). |
| [175-bonsoir-broadcast-off-main-thread-tdd-plan.md](175-bonsoir-broadcast-off-main-thread-tdd-plan.md) | BUG (follow-on from 174 CV-08 session-2; **8-agent verify→refute** grounded — CORRECTED the originating premise): iPhone Dart freezes ~1s post-launch → `0x8BADF00D` scene-update watchdog SIGKILL, blocking CV-08 PASS #4 (`MSG_RECEIVED_TRANSPORT:"direct"`) + CV-09. Real cause = the **advertise/broadcast** leg's synchronous `DNSServiceProcessResult(sdRef)` on the iOS **main thread** (`bonsoir_darwin-5.1.3 BonsoirServiceBroadcast.swift:35`, via `bonsoir_discovery_service.dart:166`); the first `startAdvertising` is ungated and a Dart `.timeout()` can't unblock the native run loop. **REFUTED & do-not-re-introduce:** "browse blocks main" (NWBrowser is async), "bump bonsoir 7.x" (broadcast byte-identical), "native pre-probe" (wrong API surface + false-skip regression). Fix = move the broadcast processing **off-main** via `DispatchSourceRead` (mirror the discovery-resolve path) — Approach A vendor+patch `bonsoir_darwin` (recommended) or Approach B app-side `NWListener` advertise. Native XCTest + **device-proof closure** (no host-Dart RED — accepted, OS-watchdog fix). Step-0: symbolicate the `.ips` to confirm the blocking frame. Do NOT flip the flag (CV-09 owns). |
| [176-cv09-libp2p-lan-dial-default-on-tdd-plan.md](176-cv09-libp2p-lan-dial-default-on-tdd-plan.md) | MODIFICATION (flag graduation; **4-agent verify→refute** grounded): graduate `EnableLibp2pLANDial` dark→default-ON now that CV-08 closed (commit `121f0551`). KEY FINDING: the Dart feature-flag map is an **always-sent full override** (`p2p_bridge_client.dart:125` → Go `config.go:207-208` returns `*c.FeatureFlags` wholesale; `json.Unmarshal` never seeds Go defaults), so the LOAD-BEARING flip is the **Dart** `defaultValue:false→true` at `p2p_bridge_client.dart:64` — flipping ONLY the Go default (`feature_flags.go:83`) is a **production no-op** (the trap, locked out by TC-09-02 asserting the SENT `node:start` payload). Go default flipped too, for consistency + guard-test inversion (`feature_flags_runtime_test.go:46`). **REFUTED & do-not-re-introduce:** "Go flip breaks the ~36 nil-flag Go integration tests" (no discovery trigger — only the Dart-fed bridge calls `HandleLANPeerFound`, node runs no libp2p mDNS → flag inert there); "flip-only-Go suffices". NEW Dart guard `test/core/services/p2p_service_lan_dial_flag_test.dart` (mirrors the DCUtR sibling; the Dart default was UNGUARDED — GAP #1). DcutrUpgrade/LANMedia stay dark (CV-13/CV-34). Host RED→GREEN gating (3 host TCs, AUTO-glob + `go test`); two-phone device-proof with NO dart-define = closure. |
| [177-lan-classifier-dns4-local-private-tdd-plan.md](177-lan-classifier-dns4-local-private-tdd-plan.md) | BUG (FDC-S6 instrument; found during the plan-176 CV-09 pilot, **device-confirmed**): `lan_address_classifier.dart` `multiaddrIsPrivateIp` returns FALSE for `/dns4/<host>.local` — it only credits `/ip4`/`/ip6` literals, but **Fix C (plan 175)** builds `/dns4/<host>.local` for iOS-resolved bonsoir peers (`bonsoir_discovery_service.dart:136`; iOS resolves to a `.local` hostname, not an IP). So the `lanPrivateIp` boolean emitted at `p2p_bridge_client.dart:629` is `false` for EVERY iOS-discovered peer → FDC-S6's "clean LAN win" (bonsoir-fed AND lanPrivateIp:true) can never be met when iOS is the discoverer → the soak **under-counts** real LAN wins (cross-platform + iOS↔iOS). Device proof: iPhone 11 `P2P_LAN_PEER_FOUND_REQUEST{addrCount:2, lanPrivateIp:false}` for a genuine `transport:"direct"` LAN conn (same /24, DCUtR off). FIX = `.local`-gated: classify `/dns4|/dns6|/dnsaddr/<host>.local` (RFC 6762 link-local) as private; **non-`.local` `/dns4` (e.g. `example.com`) STAYS false** (over-broaden lock — the existing `:72` test already pins it). Host-only TDD (3 RED in `lan_address_classifier_test.dart`, AUTO `core/**`); device FDC-S6 pilot re-run = closure. Do NOT change the win-criterion / Fix C / Go. |
| [178-bonsoir-suspected-denied-gate-overlatch-tdd-plan.md](178-bonsoir-suspected-denied-gate-overlatch-tdd-plan.md) | BUG (recurring device blocker; found during CV-34 / FDC-S6, **device-confirmed**): the pure-Dart suspected-Local-Network-denied gate in `bonsoir_discovery_service.dart` OVER-LATCHES + self-reinforces. `startAdvertising:166-174` returns early on latch **before BOTH** the broadcast (`:198-200`) AND the browse (`:209-213`), but the only un-latch path (peer-resolve `:311`) NEEDS the browse → terminal until the 5-min backoff. And `_armSuspectedDenialProbe:254` latches **platform-blind** though it's the "iOS watchdog" gate — on Android there's no `0x8BADF00D` vector + gating the broadcast breaks the working iPhone→Pixel direction. Premise largely OBSOLETED by 175 (off-main broadcast) + upstream 5.1.3 (off-main discovery). Symptom: Pixel repeatedly `LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED{300000}` → never discovers the iPhone (Mac `dns-sd` sees BOTH advertising; iPhone finds Pixel fine; perms granted). Blocks FDC-11 discoverer-side, FDC-15 CV-34 Pixel→iPhone, FDC-S6 i→A. FIX (1) platform-gate the latch to iOS (`defaultTargetPlatform`, not `dart:io`); (2) decouple — gate ONLY the broadcast, KEEP the browse running so it self-clears. **PRESERVE** the iOS broadcast gate (watchdog) — TC-78-04 mutation-locks it; do NOT revert 175 / add a native pre-probe. Host TDD (4 RED, AUTO `core/**`); device = Pixel discovers iPhone + iPhone 0×`0x8BADF00D`. |
| [193-orbit-inner-circle-default-view-split-spec.md](193-orbit-inner-circle-default-view-split-spec.md) + [tdd-plan](193-orbit-inner-circle-default-view-split-tdd-plan.md) | FEATURE IMPROVEMENT (product-confirmed; **4-sweep evidence workflow + 10-claim verify→refute, 0 refuted**): split the SHIPPED Orbit screen (`lib/features/orbit/` — orbit2/3 are kDebugMode mock prototypes with NO all-chats surface) into a default **Inner-Circle-only** view vs an alternative classic **all-chats** view, toggled by a NEW top-left button (`ValueKey('orbit-view-toggle')`; plain physical `Positioned(left:16)` — the FAB is physical right and does NOT mirror in RTL). EVERY entry resets to Inner-Circle (no persistence): initState default + rising-edge reset in `_onAppShellChanged` (orbit_wired.dart:466 — the embedded pane is latched-alive so initState alone cannot satisfy re-entry) WITHOUT starving `_replayDirtyOrbitWork` (order-locked). DESIGN LOCK: `initialFilterTab != null` ⇒ all-chats view (carries the intro-notification route, ~24 initialFilterTab tests, and INVITE_ACCEPT_SPINNER). Supersedes 2 locks (feed_wired search-survival :926-989, dual-'Close Friends' color-set :291-346); cold-start sim `_runOrbitSessionAndOpenThreads` gets a pre-assert + toggle preamble (PROD-CRITICAL closure leg, dual-suite 1to1+group); OrbitScreen gains OPTIONAL `viewMode`(default allChats)/`onToggleView` params (4 bare-pump ctor sites must not compile-break; perf harness passes innerCircle explicitly). 3 new l10n keys en/ar/de. 42 TCs, widget-floor everywhere, no DB migration, no device-proof; NEW `orbit_view_split_test.dart` + `test/l10n/orbit_strings_parity_test.dart` → **append both to GROUP_TESTS** (test/l10n is outside the feature-host-all glob) |
| [191-ios-foreground-push-forwarding-spec.md](191-ios-foreground-push-forwarding-spec.md) + [tdd-plan](191-ios-foreground-push-forwarding-tdd-plan.md) | BUG (RCA root #3; device-proven 2026-07-02 via 2 timed testpeer inbox injections → 0 push-triggered drains, acks only on 189's 30s grid; **3-agent verify→refute CORRECTED the mechanism**): iOS foreground push never reaches Dart onMessage — NOT delegate-stomping (4 installs = self-for-self; FLN never contends): the FCM plugin defers ALL launch wiring into a `UIApplicationDidFinishLaunchingNotification` observer that NEVER fires under this app's UIScene adoption (plugins register at scene-connect, after the notification; engine scene-fallback replays lifecycle calls not NSNotifications) → plugin never in the engine UN-callback chain; latent co-bug: nobody invokes willPresent completion for FCM payloads. FIX = **Option C**: AppDelegate willPresent forwards FCM-shaped (`gcm.message_id`, non-FLN) notifications to the PUBLISHED plugin instance (`valuePublished(byPlugin:"FLTFirebaseMessagingPlugin")`) with the original completion handler — zero Dart core-path changes, plugin-canonical shape, iOS-18 dedupe built-in, options-0 preserved; + Dart hardening: `FirebaseReadiness` (latch-on-success retry) + `PushListenerArmer` (`PUSH_LISTENERS_ARMED` + readiness-driven third arm point). KILLED: delegate-removal (B), proxy re-enable (D), `addApplicationLifeCycleDelegate` (E — double tap-routing, 139 reborn); do NOT forward didReceive. Host wiring-lock REDs + 2 new units (**append to `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`**) + native XCTest (manual xcodebuild); closure = device runsheet (testpeer injections ≤5s off-grid ×3, **--profile only** — dev_keychain_wipe hazard). |
| [190-android-netlink-selinux-addr-visibility-spec.md](190-android-netlink-selinux-addr-visibility-spec.md) + [tdd-plan](190-android-netlink-selinux-addr-visibility-tdd-plan.md) | BUG (root-cause #4 of the 2026-07-02 delivery RCA; live-proven on Pixel 6/Android 16; **9-agent ground+refute workflow** — RC survived all 5 alternatives, already-fixed/upgrade/D2/D3 refuted): SELinux denies the Go runtime's netlink route-socket **bind** (b/155595000, targetSdk≥30; stdlib `NetlinkRIB` binds — `syscall/netlink_linux.go:67`) → basichost ERROR every 5s + `h.Addrs()` empty → identify/signed-peer-records/rendezvous carry zero addrs, DCUtR input starved, **observed-addr recording ALSO netlink-dead** (obsaddr→InterfaceListenAddresses), LAN-direct hangs solely on the FDC-11 mDNS lane. FIX (plan) = **fork-and-replace `go-multiaddr` v0.14.0** (`third_party/`, pubsub-fork pattern) routing `InterfaceMultiaddrs` through a race-safe provider seam: `wlynxg/anet` under `//go:build android` (no bind, RTM_GETADDR-only; already linked via pion; Makefile already ships `-checklinkname=0`), stdlib under `!android` — kills the 5s spam AT SOURCE, no log filtering; + mini-fork `go-netroute` (host denial-fixture seam only). 3 spec corrections recorded (node:status NOT empty today — FDC-11 0.0.0.0 shape; TC-190-20 LAN-candidates impossible — upstream public-only filter, re-scoped to input term; 5-min spam window device-only). 10 Go RED + 2 Go sentinels (fork unit + `addr_visibility_denial_test.go` w/ marker-addr discriminators) + 1 Dart port-parity sentinel; new pinned Go target in `run_host_test_gates.sh host-all`; PROD-CRITICAL leg = TC-190-41 mDNS-disabled identify-dial (2-phone); closure = Pixel/iPhone runsheet (**--profile only**). Preserve FDC-11 fallback + filterAddresses policy; 189/188/relay untouched. |
| [189-degraded-relay-drain-starvation-restart-loop-spec.md](189-degraded-relay-drain-starvation-restart-loop-spec.md) + [tdd-plan](189-degraded-relay-drain-starvation-restart-loop-tdd-plan.md) | BUG (live two-phone debug 2026-07-02, Pixel-cellular→iPhone11-WiFi 86–368s+ store→ack, >10-min undelivered repro; **5-agent RCA workflow + 3-agent verify→refute** — all claims survived): (A) `_performHealthCheck` recovery branch `return;` at `p2p_service_impl.dart:3871` precedes the ONLY periodic drain `:3888` → chronically-degraded device never pulls its relay inbox (drains only when its own SEND flips relayState online); (B) permanent 30s full-restart loop — manual `Reserve` succeeds but only autorelay's relayFinder publishes `/p2p-circuit` (v0.39.1) and the 3s/10s waits kill it; bridge NEVER serializes `RecoveryResult.Success` (`bridge.go:821-862`) → false `phase=recovered` + counter reset every cycle; `refreshFailureThreshold:352` dead. FIX = drain-on-every-tick + Go reservation-truth verdict + bridge/Dart truthful bookkeeping + failed-recovery backoff. Host TDD (8 Dart RED in NEW `test/core/services/p2p_service_impl_health_drain_test.dart` — **add to `ONE_TO_ONE_TESTS`**; 3 Go integration RED in `no_circuit_recovery_test.go`, deterministic via `SetForcePublicReachabilityForTests`); PROD-CRITICAL leg = peer-dials-reservation Go test; closure = 2-phone device runsheet (≤35s p95, no 30s relay flap). Siblings out of scope: iOS push→drain, netlink/anet. |

**Top findings:**
- `OrbitWired` already disposes its controllers/subscriptions — that earlier P0 is stale
- The narrow DB/storage fixes worth doing were helper-local schema-capability caching, the small identity cache, the pinned-post single-load reduction, and the reload-after-update cleanup
- Targeted index work remains evidence-only; no broad SQL/index/caching program should be reopened without new profiling
- Blanket index additions, message-order SQL rewrites, and heavy SQL/materialized-view work are still not justified by default

---

## 4. Dead Code

| Report | Focus |
|--------|-------|
| [06-dead-code-lib.md](06-dead-code-lib.md) | Conservative dead-code review — only a small subset looks safely removable now |
| [07-dead-code-deps-config.md](07-dead-code-deps-config.md) | Dependency/config cleanup — confirmed unused package plus low-value optional script cleanup |

**Top finding:** The project is clean, but the earlier “24 files safe to remove” claim is too broad. The one easy confirmed cleanup is `cupertino_icons`; file deletion should be conservative because several candidates are still test- or smoke-backed.

---

## 5. Network Component

| Report | Focus |
|--------|-------|
| [08-network-1to1-messaging.md](08-network-1to1-messaging.md) | 1:1 send/receive/media/voice reliability with corrected durability and read-state findings |
| [09-network-group-messaging.md](09-network-group-messaging.md) | Group/announcement architecture for current scale; stale “missing retry” claims removed |
| [10-network-measurement-strategy.md](10-network-measurement-strategy.md) | Incremental observability plan — local counters/timers first, export stack deferred |

**Top findings:**
- 1:1 durable send-path parity between conversation and feed inline reply is now landed in the current Flutter tree
- Shared 1:1 delivery changes now have a named regression gate plus feed-surface companion direct coverage
- Group media retry/recovery already exists; it is not a missing P0 feature
- Announcement coverage is stronger than earlier reported inside the Flutter tree
- Lean local timing/counter coverage for the highest-value messaging gaps is now landed; exporter/dashboard work remains deferred

---

## 6. Use Case Audits (1:1 / Discussions / Announcements)

| Report | Focus |
|--------|-------|
| [12-1to1-chat-use-case-audit.md](12-1to1-chat-use-case-audit.md) | Core 1:1 flows are tested; remaining gaps are product features and narrow residual edges |
| [11-group-discussion-use-case-audit.md](11-group-discussion-use-case-audit.md) | Core group lifecycle/message/recovery flows are tested; stale gap claims removed |
| [13-announcement-use-case-audit.md](13-announcement-use-case-audit.md) | Announcement enforcement is well covered in Flutter; Go-side writer enforcement remains outside this tree |
| [18-group-discussion-reliability-audit.md](18-group-discussion-reliability-audit.md) | Lean reliability-gap review: what group chat still needs to feel as trustworthy as 1:1 without overengineering |

**Top findings:**
- **1:1 Chat:** Core implemented flows are tested; the earlier feed-inline
  durable-send gap, the sender-visible `reuse` fast-path mismatch, and the
  broader direct-vs-relay transport-truth seam for new Go-backed 1:1 rows are
  now closed. The remaining gaps are mostly product features plus narrower
  residual edge cases such as local-file-missing retry behavior
- **Group Discussions:** Core use cases/listeners are well tested; missing items are mostly intentional product scope, not correctness failures
- **Group Discussion Reliability:** Final acceptance revalidation confirms ordinary-media parent-row durability, ordinary-media failed-send retry parity, and explicit one-thread send serialization are landed; voice publish-failure retry remains only a narrower producer-side residual if reopened later
- **Announcements:** Session `28` revalidated that shared group reliability work did not regress announcement auth/send/recovery/read-only behavior; remaining gaps are now narrower evidence niceties, not a new reliability program
- **QA type:** Still defined in the enum/schema but filtered out of creation UI — placeholder only

---

## 7. Regression Strategy

| Report | Focus |
|--------|-------|
| [14-regression-test-strategy.md](14-regression-test-strategy.md) | Practical regression model: baseline gate, subsystem gates, missing regressions to add, and run rules for new work |

**Top finding:** The repo already has most of the needed tests. The missing piece is a clear run strategy: small baseline on every PR, change-based subsystem gates for risky shared code, explicit file lists per gate, a bulk-classification policy for non-gate tests, and one permanent regression test for every escaped bug.

---

## 8. Session Roadmaps And Closure

| Report | Focus |
|--------|-------|
| [15-session-todo-roadmap.md](15-session-todo-roadmap.md) | Historical execution backlog for Sessions `1` through `11` |
| [16-session-todo-roadmap-2.md](16-session-todo-roadmap-2.md) | Historical follow-on backlog for Sessions `12` through `23`, including profile/evidence-gated and cross-tree work |
| [session-24-plan.md](session-24-plan.md) | Historical residual reliability implementation session |
| [session-25-plan.md](session-25-plan.md) | Historical residual reliability implementation session |
| [session-26-plan.md](session-26-plan.md) | Historical residual reliability implementation session |
| [session-27-plan.md](session-27-plan.md) | Historical residual reliability acceptance session |
| [session-28-plan.md](session-28-plan.md) | Historical announcement acceptance session |
| [session-29-plan.md](session-29-plan.md) | Historical lean local measurement session |
| [session-30-plan.md](session-30-plan.md) | Plan-only narrow residual reopen artifact; not executed closure work |
| [session-31-plan.md](session-31-plan.md) | Historical narrow 1:1 transport-label closure session |
| [session-32-plan.md](session-32-plan.md) | Historical narrow 1:1 transport-truth closure session |
| [session-34-plan.md](session-34-plan.md) | Historical narrow standalone CLI-backed transport residual closure session |
| [session-35-plan.md](session-35-plan.md) | Historical narrow intro-to-Orbit / intro-to-Feed follow-up closure session |
| [session-36-plan.md](session-36-plan.md) | Historical narrow standalone CLI-backed post-verify closure session |
| [session-37-plan.md](session-37-plan.md) | Historical narrow 1:1 failed-send recovery regression-coverage closure session |
| [24-cancel-media-upload-session-breakdown.md](24-cancel-media-upload-session-breakdown.md) | Historical multi-session breakdown and closure-owner artifact for Report `24` |
| [session-44-plan.md](session-44-plan.md) | Historical cancelable-upload retry/delete contract session |
| [session-45-plan.md](session-45-plan.md) | Historical 1:1 cancelable-upload surface session |
| [session-46-plan.md](session-46-plan.md) | Historical group/announcement parity session for cancelable uploads |
| [session-47-plan.md](session-47-plan.md) | Historical acceptance-only closure refresh for cancelable uploads |
| [27-persistent-nav-bar-orbit-session-breakdown.md](27-persistent-nav-bar-orbit-session-breakdown.md) | Historical multi-session breakdown and closure-owner artifact for Report `27` |
| [27-persistent-nav-bar-orbit-session-54-plan.md](27-persistent-nav-bar-orbit-session-54-plan.md) | Historical already-covered in-app Orbit persistent-nav session artifact |
| [27-persistent-nav-bar-orbit-session-55-plan.md](27-persistent-nav-bar-orbit-session-55-plan.md) | Historical intro-notification Orbit parity and closure session |
| [28-orbit-intro-badge-session-breakdown.md](28-orbit-intro-badge-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `28` |
| [28-orbit-intro-badge-session-56-plan.md](28-orbit-intro-badge-session-56-plan.md) | Historical shared Orbit intro badge and freshness-wiring session artifact |
| [29-batch-parallel-intro-sending-session-breakdown.md](29-batch-parallel-intro-sending-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `29` |
| [29-batch-parallel-intro-sending-session-58-plan.md](29-batch-parallel-intro-sending-session-58-plan.md) | Historical capped intro batching and progress-contract session artifact |
| [29-batch-parallel-intro-sending-session-59-plan.md](29-batch-parallel-intro-sending-session-59-plan.md) | Historical picker progress UX and closure session artifact |
| [30-swipe-nav-feed-orbit-session-breakdown.md](30-swipe-nav-feed-orbit-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `30` |
| [30-swipe-nav-feed-orbit-session-59-plan.md](30-swipe-nav-feed-orbit-session-59-plan.md) | Historical shared-host migration and preserved-state session artifact for Report `30` |
| [30-swipe-nav-feed-orbit-session-60-plan.md](30-swipe-nav-feed-orbit-session-60-plan.md) | Historical horizontal swipe / gesture arbitration closure session artifact for Report `30` |
| [34-orbit-intros-swipe-delete-missing-session-breakdown.md](34-orbit-intros-swipe-delete-missing-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `34` |
| [34-orbit-intros-swipe-delete-missing-session-1-plan.md](34-orbit-intros-swipe-delete-missing-session-1-plan.md) | Historical live Orbit intro swipe-delete / closure session artifact for Report `34` |
| [35-cancelled-video-upload-still-sends-session-breakdown.md](35-cancelled-video-upload-still-sends-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `35` |
| [35-cancelled-video-upload-still-sends-session-1-plan.md](35-cancelled-video-upload-still-sends-session-1-plan.md) | Historical late-boundary 1:1 video cancel reopen/closure session artifact for Report `35` |
| [41-notification-open-missing-incoming-messages-session-breakdown.md](41-notification-open-missing-incoming-messages-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `41` |
| [41-notification-open-missing-incoming-messages-session-1-plan.md](41-notification-open-missing-incoming-messages-session-1-plan.md) | Historical two-phase relay inbox retrieve/ack session artifact for Report `41` |
| [41-notification-open-missing-incoming-messages-session-2-plan.md](41-notification-open-missing-incoming-messages-session-2-plan.md) | Historical durable inbox staging/replay and reject-observability session artifact for Report `41` |
| [41-notification-open-missing-incoming-messages-session-3-plan.md](41-notification-open-missing-incoming-messages-session-3-plan.md) | Historical app-root notification parity and closure session artifact for Report `41` |
| [44-feed-orbit-notification-desync-session-breakdown.md](44-feed-orbit-notification-desync-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `44` |
| [44-feed-orbit-notification-desync-session-1-plan.md](44-feed-orbit-notification-desync-session-1-plan.md) | Historical Feed/Orbit handled-notification sync and closure session artifact for Report `44` |
| [45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md](45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `45` |
| [45-feed-stack-card-does-not-reorient-after-inline-reply-session-1-plan.md](45-feed-stack-card-does-not-reorient-after-inline-reply-session-1-plan.md) | Historical Feed inline-reply viewport reorientation and closure session artifact for Report `45` |
| [48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md](48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `48` |
| [48-gap3-remove-destructive-inbox-fallback-plan-session-1-plan.md](48-gap3-remove-destructive-inbox-fallback-plan-session-1-plan.md) | Historical automatic 1:1 inbox-drain fallback removal and closure session artifact for Report `48` |
| [50-two-simulator-user-journey-tests-todo-session-breakdown.md](50-two-simulator-user-journey-tests-todo-session-breakdown.md) | Closed doc-scoped controller for Report `50` manual-journey coverage refresh |
| [50-two-simulator-user-journey-tests-todo-session-10-plan.md](50-two-simulator-user-journey-tests-todo-session-10-plan.md) | Historical closure-only matrix refresh and accepted-difference session artifact for Report `50` |
| [55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md](55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md) | Closed doc-scoped controller for Report `55` iOS share handoff plus multi-recipient picker/batch-send rollout |
| [55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md](55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md) | Historical iOS auto-redirect handoff proof session artifact for Report `55` |
| [55-external-share-skip-post-and-multi-recipient-plan-session-2-plan.md](55-external-share-skip-post-and-multi-recipient-plan-session-2-plan.md) | Historical picker multi-select batch-send and closure session artifact for Report `55` |
| [76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md](76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md) | Closed doc-scoped controller for Report `76` outbound 1:1 v2-only privacy closure |
| [76-remove-legacy-1to1-plaintext-path-plan-session-1-plan.md](76-remove-legacy-1to1-plaintext-path-plan-session-1-plan.md) | Historical outbound/retry legacy plaintext removal and closure session artifact for Report `76` |
| [17-roadmap-closure-audit.md](17-roadmap-closure-audit.md) | Post-execution closure audit and current reading order for the folder |

**Top finding:** The folder has now moved from backlog mode into closure mode.
Roadmaps `15` and `16` served as the main execution backlogs through Session
`23`, Sessions `24` through `29` closed the residual
group/announcement/measurement track, Sessions `31` and `32` closed the narrow
1:1 transport-label and transport-truth seams, Session `35` closed the narrow
intro-to-Orbit / intro-to-Feed stale follow-up seam, Sessions `34` and `36`
closed the reviewed standalone CLI-backed transport and post-verify proof
seams, Session `37` closed the narrow deterministic failed-send recovery
coverage seam, Sessions `44` through `47` closed the Report `24`
cancelable-upload rollout and refreshed the stable messaging closure refs,
Sessions `54` and `55` closed the Report `27` persistent-nav rollout and
refreshed the folder closure docs, Session `56` closed the Report `28` shared
Orbit intro badge truth and freshness wiring seam and refreshed the closure
docs, Sessions `58` and `59` closed the Report `29` ordered intro-batching and
truthful picker-progress rollout, the doc-scoped Sessions `59` and `60`
closed the Report `30` shared-host plus horizontal-swipe Feed/Orbit rollout,
the doc-scoped Session `1` for Report `35` reclosed the narrow late-boundary
1:1 video cancel seam without reopening the broader Report `24`
cancelable-upload program, the doc-scoped Sessions `1` through `3` for Report
`41` closed the staged inbox recovery plus app-root notification-open trust
seam and refreshed the stable 1:1 closure wording, the doc-scoped Session `1`
for Report `44` closed the stale Feed/Orbit handled-notification contradiction
without widening into app-root notification routing or unread architecture
work, the doc-scoped Session `1` for Report `45` closed the stale absolute
scroll-offset seam after successful inline reply without widening into
unread-model redesign or broader Feed/Orbit navigation architecture, the
doc-scoped Session `1` for Report `48` closed the automatic inbox-drain path
from durable `retrieve_pending` back to destructive `inbox:retrieve`,
refreshed the stable 1:1 closure wording without widening into public
inbox-API removal, the doc-scoped Sessions `1` through `10` for Report `50`
closed the manual-journey coverage backlog plus the stale notification-open
assumption, the doc-scoped Sessions `1` and `2` for Report `55` closed the
external-share iOS handoff plus truthful multi-recipient picker/batch-send
rollout without widening into Android entry or composer redesign, the
doc-scoped Session `1` for Report `76` closed ordinary outbound 1:1 legacy
plaintext send/retry by making those paths encrypted v2 or fail-closed, and
Session `30` remains a plan-only residual artifact rather than executed work.
The closure audit now describes what is historical rationale, what remains
open, and what should only be reopened if a real residual gap appears.

---

## 9. Post-Execution State

| Status | Item | Why It Still Matters | Report |
|--------|------|----------------------|--------|
| Maintain | Keep `test-gate-definitions.md` and named gates canonical | Future changes should continue to use the same gate language and command surface | 14 / 15 / 16 |
| Maintain | Keep the lean local messaging measurement events coherent with the current flow-event contract | Future send/retry/media/rejoin work should extend the landed local event layer, not invent a second metrics stack | 10 / 29 |
| Maintain | Use the direct standalone CLI-backed transport command alongside the named transport gate when touching the Sessions `34` / `36` seams | The named transport gate can run `transport_e2e_test.dart` without the CLI fixture/orchestrator path | 19 / 34 / 36 |
| Maintain | Use the direct intro/orbit/feed maintenance suite plus `baseline` when intro follow-up wiring changes | No named gate directly owns this seam; maintenance-time safety sits in `orbit_wired_test.dart`, `orbit_intros_wiring_test.dart`, `feed_wired_test.dart`, and the intro listener/regression/integration suites | 35 / test-gate-definitions |
| Maintain | Use `50-two-simulator-user-journey-tests-todo-session-breakdown.md` plus the refreshed Report `50` audit/journey docs when manual two/three-simulator coverage claims are questioned | Report `50` is now the closure-time controller for this matrix, including the accepted notification-open routing difference and the exact direct suites that closed Sessions `1` through `9` | 50 |
| Maintain | Use the stable 1:1/group closure refs plus `24-cancel-media-upload-session-breakdown.md` and `35-cancelled-video-upload-still-sends-session-breakdown.md` for cancelable-upload maintenance | Session `47` closed the broad rollout and the doc-scoped Session `1` for Report `35` reclosed the narrow late-boundary 1:1 video cancel seam without widening gate definitions or announcement-specific architecture | 19 / 20 / 24 / 35 / 47 |
| Maintain | Use `41-notification-open-missing-incoming-messages-session-breakdown.md`, the direct notification-open suites, `./scripts/run_test_gates.sh 1to1`, and `baseline` when shared 1:1 inbox recovery or app-root notification-open routing changes | The doc-scoped Report `41` sessions closed durable fetched-envelope staging/replay plus prepare-before-route parity for terminated remote, warm remote, terminated local, and warm local notification opens; `transport` becomes required again only if later work broadens into startup/resume/inbox-drain ordering changes | 19 / 41 / test-gate-definitions |
| Maintain | Use `48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`, the direct automatic-drain service/lifecycle suites, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh baseline`, and `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` when shared automatic 1:1 inbox drain or `retrieve_pending` fallback wiring changes | The doc-scoped Session `1` for Report `48` closed the production path from durable automatic drain back to destructive `inbox:retrieve` without widening into public destructive-API removal or malformed-row cleanup architecture | 19 / 41 / 48 / test-gate-definitions |
| Maintain | Use `76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md`, the refreshed 1:1 closure reference, the direct send/delete/retry/voice suites, `./scripts/run_test_gates.sh 1to1`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `./scripts/run_test_gates.sh completeness-check` when ordinary 1:1 outbound encryption or retry wire-envelope replay changes | The doc-scoped Session `1` for Report `76` closed the outbound plaintext leak by requiring encrypted v2 or fail-closed behavior before send, inbox store, new outbound `wireEnvelope` persistence, or voice upload, while preserving inbound v1 compatibility | 19 / 76 / test-gate-definitions |
| Maintain | Use `27-persistent-nav-bar-orbit-session-breakdown.md`, `intro_notification_orbit_route_test.dart`, the direct Orbit/Feed nav suites, and `baseline` when app-root intro-open wiring changes | Session `55` closed the notification-opened Orbit persistent-nav seam without widening into sibling-tab hosting, keep-alive, or swipe navigation scope | 27 / 54 / 55 |
| Maintain | Use `28-orbit-intro-badge-session-breakdown.md`, the direct Feed/Orbit intro badge suites, `intro_notification_orbit_route_test.dart`, and `baseline` when shared Orbit pending-intro badge truth changes | Session `56` closed shared badge coexistence, expiry-aware load, live refresh, route-return freshness, and persistent-nav Orbit parity without widening into a second unread system or root-owned badge controller | 28 / 56 |
| Maintain | Use `29-batch-parallel-intro-sending-session-breakdown.md`, the direct intro application/picker/integration suites, and rerun `baseline` only when broader conversation or banner entry wiring changes | Sessions `58` and `59` closed capped batch intro sending plus truthful picker progress without widening into Go/bridge batch APIs or new named-gate ownership | 29 / 58 / 59 |
| Maintain | Use `55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`, the direct share picker/coordinator/integration suites, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` when shared external-share picker or share fanout wiring changes | The doc-scoped Sessions `1` and `2` for Report `55` closed the iOS share-entry handoff plus truthful multi-recipient picker/batch-send slice without widening into Android entry, composer redesign, or shared 1:1/group send semantics | 55 / test-gate-definitions |
| Maintain | Use `30-swipe-nav-feed-orbit-session-breakdown.md`, the direct Feed/Orbit swipe and local-gesture suites, and `baseline` when the shared Feed/Orbit navigation seam changes | The doc-scoped Sessions `59` and `60` closed the shared-host plus horizontal-swipe rollout without widening into notification-opened Orbit routing parity, a broader app-root tab shell, or unread/badge architecture work | 30 / 59 / 60 |
| Maintain | Use `44-feed-orbit-notification-desync-session-breakdown.md`, the direct `feed_wired_test.dart` and `orbit_wired_test.dart` suites, plus `./scripts/run_test_gates.sh feed`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` when shared Feed/Orbit handled-notification truth changes | The doc-scoped Session `1` for Report `44` closed the mounted Orbit stale-unread contradiction after Feed collapse or successful inline reply without widening into app-root notification routing, group sync, or unread-architecture redesign | 30 / 40 / 44 / test-gate-definitions |
| Maintain | Use `45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`, the direct `feed_wired_test.dart` and `feed_screen_test.dart` suites, plus `./scripts/run_test_gates.sh feed`, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` when Feed inline-reply viewport continuity changes | The doc-scoped Session `1` for Report `45` closed the stale same-card viewport continuity seam after successful inline reply without widening into unread-truth redesign, group parity, or broader Feed/Orbit navigation architecture | 40 / 44 / 45 / test-gate-definitions |
| Maintain | Use `34-orbit-intros-swipe-delete-missing-session-breakdown.md`, `orbit_wired_test.dart`, `orbit_intros_wiring_test.dart`, `orbit_screen_archived_groups_test.dart`, `swipeable_friend_row_test.dart`, and `baseline` when live Orbit intro delete behavior changes | The doc-scoped Session `1` closed the live Orbit intro swipe-delete seam without widening into intro protocol, loader, or broader Feed/Orbit architecture work | 34 / doc-scoped 1 |
| Follow up only if needed | Complete external CI / release owner wiring for Session `12` if the local handoff artifact is still the final state | This is the only clearly externalized closure item | 16 |
| Follow up only if needed | Revalidate Session `30` before any execution | The plan file alone should not reopen the already-closed broader program | 17 / 30 |
| Residual only | Reopen group reliability only if voice publish-failure retry becomes a real escaped bug or a clearly justified trust gap | The broader discussion reliability program is closed | 18 / 24 / 25 / 26 / 27 |
| Residual only | Reopen intro follow-up work only if a real regression makes `mutualAccepted` contacts reappear under `Intros`, hides the Feed connection card, or breaks the blocked-accept listener contract | Session `35` closed the UI-state race without reopening listener or protocol work | 35 |
| Residual only | Reopen Orbit intro badge work only if pending-intro badge truth regresses on cold load, live intro updates, route return from Orbit accept/pass, or persistent-nav Orbit parity | Session `56` closed the report; later work should reopen only on real badge-truth regressions, not to invent a new root-level badge architecture | 28 / 56 |
| Residual only | Reopen live Orbit intro delete work only if swipe-delete affordance, confirmation, grouped-row cleanup, empty-state truth, or pending-intro badge truth regresses after delete | The doc-scoped Session `1` for Report `34` closed the local Orbit intro delete seam; later work should reopen only on real UI/count regressions, not to invent P2P delete sync or widened intro-status scope | 34 / doc-scoped 1 |
| Residual only | Reopen 1:1 transport-label/truth work only if new outgoing or incoming 1:1 rows regress to misleading transport labels | Sessions `31` and `32` closed new-row reuse fast-path labeling and Go/libp2p direct-vs-relay truth; old `reuse` rows remain legacy-only fallback | 19 / 31 / 32 |
| Residual only | Reopen 1:1 failed-send recovery coverage only if the deterministic foreground online-transition or lock-after-failure resume regressions stop proving exact-once healing | Session `37` closed the missing matrix cell for visible failure during network switch followed by later foreground or resume recovery | 19 / 33 / 37 |
| Residual only | Reopen the late-boundary 1:1 video cancel seam only if accepted cancel again falls through into the ordinary upload-failure UX or the later final-send path for that same attempt | The doc-scoped Session `1` for Report `35` reclosed that narrow seam without reopening group parity, retry ownership, or status-model scope | 19 / 24 / 35 |
| Residual only | Reopen standalone CLI-backed transport work only if a current direct run reintroduces the previously closed transport-truth or post-verify proof seams | Sessions `34` and `36` closed the reviewed `A1` / `A4` / `A2` / `A5` / `D4` / `A7` / `A8` / `A8b` / `C3` / `B8` / `G6` / `E8` / `RECV-A1` / `RECV-A4` / `RECV-A6` seams; the direct command remains required maintenance proof alongside the named gate | 19 / 34 / 36 |
| Residual only | Reopen a roadmap item only if a real regression, failed gate, or newly proven gap appears | Avoids restarting broad cleanup work without evidence | 17 |
| Intentionally deferred | Product-scope items such as read receipts, typing indicators, search, exporter/dashboard work | These were deferred by design, not missed correctness work | 08 / 09 / 10 |
| Do not reopen by default | Broad SQL/index/caching work, mass dead-code cleanup, or exporter architecture | These remain unjustified without new evidence | 05 / 06 / 10 |

---

## 10. Closure References

| Report | Focus |
|--------|-------|
| [19-1to1-message-reliability-closure-reference.md](19-1to1-message-reliability-closure-reference.md) | Stable closure bar for trustworthy 1:1 text/media/voice messaging |
| [20-group-discussion-reliability-closure-reference.md](20-group-discussion-reliability-closure-reference.md) | Stable closure bar for trustworthy group discussions under current receipt-less group architecture |
| [21-announcement-reliability-closure-reference.md](21-announcement-reliability-closure-reference.md) | Stable closure bar for trustworthy announcements on top of shared group reliability and admin-only enforcement |

**Top finding:** These three docs are the canonical "stop here unless a real regression appears" references for messaging reliability after the roadmap work. They are intentionally narrower than full feature backlogs and should be used to avoid reopening product-scope or protocol-scope debates by accident.

---

## 11. Feature Specs (New Work)

| Report | Focus |
|--------|-------|
| [22-media-transfer-size-limit.md](22-media-transfer-size-limit.md) | Raise media transfer cap from 100 MB to 5 GB with attach-time warning, compression enforcement, wake lock, and progress UX |
| [24-cancel-media-upload.md](24-cancel-media-upload.md) | Cancel in-progress uploads, delete/retry failed messages, prevent unwanted auto-retries |
| [25-delete-intro-swipe.md](25-delete-intro-swipe.md) | Swipe-to-delete introductions in Orbit Intros tab with DB removal and re-introduction support |
| [26-long-press-message-context-menu.md](26-long-press-message-context-menu.md) | Signal-like long-press overlay with emoji bar, blurred background, and Reply/Copy context menu on messages |
| [27-persistent-nav-bar-orbit.md](27-persistent-nav-bar-orbit.md) | Bottom nav bar disappears when navigating to Orbit; should persist with active tab indicator |
| [28-orbit-intro-badge.md](28-orbit-intro-badge.md) | Badge/dot on Orbit nav button when pending introductions exist |
| [29-batch-parallel-intro-sending.md](29-batch-parallel-intro-sending.md) | Ordered batched introduction sending with concurrency cap of 10 and truthful picker progress |
| [30-swipe-nav-feed-orbit.md](30-swipe-nav-feed-orbit.md) | Horizontal swipe navigation between Feed and Orbit screens |
| [31-edit-last-sent-message.md](31-edit-last-sent-message.md) | Edit last sent message via long-press context menu with P2P sync |
| [32-notification-card-interactions.md](32-notification-card-interactions.md) | Profile picture tap and collapse bar non-responsive on notification-opened feed cards |
| [33-delete-message-for-me-everyone.md](33-delete-message-for-me-everyone.md) | Delete messages with "Delete for Me" and "Delete for Everyone" via long-press context menu |
| [34-orbit-intros-swipe-delete-missing.md](34-orbit-intros-swipe-delete-missing.md) | Live Orbit intros are missing the existing swipe-to-delete affordance and confirmation flow |
| [35-cancelled-video-upload-still-sends.md](35-cancelled-video-upload-still-sends.md) | Accepted cancel on a 1:1 video upload can still fall through into failure/send; cancel should stop delivery for that attempt |
| [55-external-share-skip-post-and-multi-recipient-plan.md](55-external-share-skip-post-and-multi-recipient-plan.md) | Skip the extra native iOS Post screen on external share and support truthful multi-recipient share delivery from the picker |
| [76-remove-legacy-1to1-plaintext-path-plan.md](76-remove-legacy-1to1-plaintext-path-plan.md) | Remove ordinary outbound 1:1 legacy plaintext send/retry paths while preserving inbound v1 compatibility |

**Context:** These specs address user-facing gaps discovered during TestFlight
usage. Report `24` directly relates to the upload reliability path covered by
reports `08`, `19`, and `22`, and its landed maintenance-time meaning now
lives in `24-cancel-media-upload-session-breakdown.md` plus the refreshed
closure references rather than in the proposal alone. Report `27` directly
relates to the intro/orbit/feed navigation seam first narrowed by Session
`35`, and its landed maintenance-time meaning now lives in
`27-persistent-nav-bar-orbit-session-breakdown.md` plus the refreshed closure
docs rather than in the proposal alone. Report `28` directly relates to that
same intro/orbit/feed seam, and its landed maintenance-time meaning now lives
in `28-orbit-intro-badge-session-breakdown.md` plus the refreshed closure docs
rather than in the proposal alone. Report `29` directly relates to the same
intro sending seam, and its landed maintenance-time meaning now lives in
`29-batch-parallel-intro-sending-session-breakdown.md` plus the refreshed
closure docs rather than in the proposal alone. Report `30` directly relates to
that same Feed/Orbit navigation seam, and its landed maintenance-time meaning
now lives in `30-swipe-nav-feed-orbit-session-breakdown.md` plus the refreshed
closure docs rather than in the proposal alone. Report `34` directly relates to
the same intro/orbit/feed seam, and its landed maintenance-time meaning now
lives in `34-orbit-intros-swipe-delete-missing-session-breakdown.md` plus the
refreshed closure docs rather than in the proposal alone. Report `35` directly
relates to the Report `24` 1:1 cancel seam, and its landed maintenance-time
meaning now lives in
`35-cancelled-video-upload-still-sends-session-breakdown.md` plus the
refreshed 1:1 closure docs rather than in the proposal alone. Report `55`
directly relates to the external-share entry and delivery seam, and its landed
maintenance-time meaning now lives in
`55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
rather than in the proposal alone. Report `76` directly relates to the 1:1
privacy and retry closure bar, and its landed maintenance-time meaning now
lives in
`76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md` plus the
refreshed 1:1 closure reference rather than in the proposal alone.
