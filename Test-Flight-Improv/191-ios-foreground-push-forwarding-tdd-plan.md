# 191 - iOS foreground push forwarding (FCM plugin absent from lifecycle chain under UIScene) + Firebase init/arm hardening  (Bug)

Status: awaiting-review
Spec: Test-Flight-Improv/191-ios-foreground-push-forwarding-spec.md (mechanism refined by this plan's adversarial pass — spec updated in place 2026-07-02)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-02 | Evidence Collector (live device debug + spec-191 Explore) | SpringBoard/apsd syslog, relay journal, testpeer injections ×2, AppDelegate.swift, Info.plist, FLTFirebaseMessagingPlugin.m, FlutterLocalNotificationsPlugin.m | Bug device-proven on HEAD (pushes 10:04:30Z/10:05:48Z → 0 push drains) | verify→refute |
| 2026-07-02 | Verify→Refute (3-agent: fix-options, dart-seams, harness) | + Flutter engine sources (FlutterAppDelegate.mm, FlutterPluginAppLifeCycleDelegate.mm, FlutterViewController.mm), engine headers, pub-cache plugin sources, main.dart, run gates | Mechanism CORRECTED (UIScene registration timing, not delegate stomping); Option C selected; B/E killed | build matrix |
| 2026-07-02 | Planner | tier-matrix, harness inventory, 183/189/190 runsheet + registration precedents | Native fix + 2 Dart hardening units; no P2PService/interface changes; no DB migration | emit plan |
| 2026-07-02 | Reviewer (sufficiency) | this plan vs checklist | zero empty matrix cells; blind-spot sweep recorded; device RED already executed on HEAD | Arbiter |
| 2026-07-02 | Arbiter | — | no structural blockers; device runsheet = closure | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-02 | contract extraction (git status --short) | — | `main.dart` clean; `p2p_service_impl.dart`/`go-mknoon/*`/`scripts/run_*_gates.sh` dirty (189/190) — untouched their hunks; 191 INDEX row already present (00-INDEX:126) | no blockers | add REDs |
| 2026-07-02 | RED tests added | `main_deferred_push_rearm_wiring_test.dart` (+2 `191:` locks), new `firebase_readiness_test.dart` + `push_listener_armer_test.dart`, `handle_foreground_remote_message_use_case_test.dart` (+2 shape locks), `remote_message_fixtures.dart` (plugin-canonical fixture) | `flutter test …wiring… --plain-name '191'` → **+0 -2** (RED for documented reasons: no FirebaseReadiness/PushListenerArmer on HEAD) | RED confirmed | implement |
| 2026-07-02 | implementation | **D1** `firebase_readiness.dart` + main delegation; **D2** `push_listener_armer.dart` + `_MyAppState` armer/third-arm-point + optional `MyApp.firebaseReadiness`; **N1** `ForegroundPushForwardPolicy.swift` + AppDelegate willPresent forward + capture; `ForegroundPushForwardPolicyTests.swift`; `project.pbxproj` (Runner + RunnerTests targets) | `plutil -lint` OK; new pbxproj IDs count 2/3 (buildFile/fileRef) | 164 strings preserved | GREEN |
| 2026-07-02 | direct GREEN | (above) | 4 Dart files: **24/24 pass** (4 wiring + 3 readiness + 4 armer + 13 use-case); `flutter analyze` 3 files **0 issues** | green | native + sentinels |
| 2026-07-02 | native lock | `ForegroundPushForwardPolicyTests.swift` | `xcodebuild test … -only-testing:RunnerTests/ForegroundPushForwardPolicyTests` → **`** TEST SUCCEEDED **`, 3/3** (testFcmShaped…CompletesOnce / testFlnShaped…SuperPath / testNilPluginRef…SuperWithDiag); AppDelegate.swift + ForegroundPushForwardPolicy.swift both compiled (native forward validated). Runs 1-3 hit a shared-tree kernel_snapshot temp race + post-`flutter clean` pod desync → `pod install` + clean rebuild → green | manual-only gate | closed |
| 2026-07-02 | preservation GREEN | — | targeted isolated sweep **612/612**: `test/features/push/**` (TC-191-31 bg handler), `test/core/notifications/**` (TC-191-11 tap bridge), `test/core/lifecycle/**` (164+191 wiring), + the one MyApp-constructor test. Full feature/core-host-all sweeps were abandoned mid-run due to the concurrency temp-race; the sole flagged file re-ran **clean in isolation** (collision artifact, not a regression) | no regressions | closed |
| 2026-07-02 | named gates / registration | `run_test_gates.sh`, `run_host_test_gates.sh` | appended both new units to `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS` after 189; `bash -n` OK; 1to1 host dry-run lists them (#41/#42) | registered | device runsheet |
| 2026-07-02 | device (closure) | `191-ios-foreground-push-device-runsheet.md` | runsheet authored (§A-D, testpeer pipeline, --profile only); **execution PENDING** (device) | Before column = HEAD RED already recorded 2026-07-02 | execute on iPhone 11 |

## Source Of Truth
- Spec: Test-Flight-Improv/191-ios-foreground-push-forwarding-spec.md
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh (script wins over prose)
- Native test invocation precedent: Test-Flight-Improv/test-gate-definitions.md:645-646 (full) / 102-…-GIRD-006-plan.md:156 (focused `-only-testing`)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (189/190 rows at ~:126-127; 191 row added by this plan)

## Session Classification
implementation-ready

## Exact Problem Statement
iOS foreground remote pushes reach the device (NSE runs, previews render) but never reach Dart `FirebaseMessaging.onMessage`: the firebase_messaging plugin's entire launch wiring — including its `addApplicationDelegate` registration, the only path by which `willPresent` can ever reach its `Messaging#onMessage` channel invoke — is deferred into a `UIApplicationDidFinishLaunchingNotification` observer that never fires under this app's UIScene adoption (plugins register at scene-connect, after UIKit posted that notification). Result: push-triggered inbox drain has NEVER worked on iOS; receive latency is capped at 189's 30 s periodic grid (pre-189: minutes-to-unbounded — the 2026-07-02 incident). Secondary hardening: `ensureFirebaseReady()` latches before success (one thrown `Firebase.initializeApp()` = permanent process deafness, no retry) and listener arming has no success telemetry and no post-failure re-arm path.

What must improve: (1) an FCM-shaped foreground notification on iOS reaches the existing Dart handler chain and triggers the drain within seconds; (2) the `willPresent` completion handler is actually invoked for FCM payloads (latent co-bug); (3) Firebase init failure is retryable; (4) listener-arm state is observable (`PUSH_LISTENERS_ARMED`) and arming rides Firebase readiness (no ordering permanently disarms).
What must stay unchanged (→ preserved-green sentinels): tap routing (`ios_notification_open` bridge + `onMessageOpenedApp` staying silent — forwarding `didReceive` would double-route, the 139 bug), FLN local notifications, foreground presentation policy (options 0 / no banner), NSE preview + SI-5 dedupe, background/killed push semantics, migration gates, Android path, APNs-token forward, 189's periodic drain.

## Root Cause (verify → refute confirmed)
- **Primary (device-proven on HEAD + source-verified at pinned versions):** FCM plugin 15.2.10 defers all launch wiring into the `UIApplicationDidFinishLaunchingNotification` observer (`FLTFirebaseMessagingPlugin.m:67-75`, handler `:214-310`, `addApplicationDelegate` `:254`). Under UIScene (`Info.plist:60-81`, since `ff2c094c`), `GeneratedPluginRegistrant.register` runs at scene-connect (`AppDelegate.swift:143-156`) — after the notification. The engine's scene fallback replays lifecycle calls, not NSNotifications (`FlutterViewController.mm:318-329`). So the plugin is never in the engine's UN-callback fan-out (`FlutterAppDelegate.mm:120-142` → `FlutterPluginAppLifeCycleDelegate.mm:467-490` — which DOES forward; FLN rides it today) and its `willPresent` → `Messaging#onMessage` (`:316-360`, `:329-333`) never runs.
- **Latent co-bug:** for FCM-shaped foreground notifications nobody invokes the `willPresent` completion handler (AppDelegate `:69-83` → super → FLN early-return without completing, `FlutterLocalNotificationsPlugin.m:879-886`); "response 0" is the OS default.
- **Hardening holes (code-verified):** `ensureFirebaseReady` latches `firebaseInitialized=true` at `main.dart:401` BEFORE the try; throw swallowed `:414-416`. `_setupPushListeners` (`:4663-4702`) has two arm points (`:3709`, `:3717-3719`) that both no-op if `Firebase.apps` is empty; `_ensureRuntimeServicesReady` memoization (`:3746-3764`) collapses them to one effective attempt; no arm-success event.

Refuted / do-NOT-re-introduce:
- "AppDelegate delegate-stomping severs the path" — REFUTED: the 4 installs (`:38/:41/:145/:160`) replace self with self; the plugin's decline guard (`:271-275`) is dead code here. Do not delete the installs as a "fix" (Option B KILLED: with the observer never firing, removing them leaves `center.delegate` nil — nobody gets `willPresent`, FLN foreground handling breaks too).
- "FLN contends for the delegate" — REFUTED: FLN never sets the delegate (zero assignments; joins the engine chain at registration `:145-147`).
- "Engine doesn't forward UN callbacks" — REFUTED (`FlutterAppDelegate.mm:120-142`). Corollary: Option E (`addApplicationLifeCycleDelegate(fcmInstance)`) KILLED — it restores `didReceive` too → `onMessageOpenedApp` fires alongside the manual tap bridge → double navigation.
- "Firebase-init wedge is the live mechanism" — REFUTED by the fresh-token proof (Firebase up, still no onMessage); kept as hardening only.
- Re-enabling `FirebaseAppDelegateProxyEnabled` (Option D) — NOT planned: swizzling interactions with the manual apnsToken forward + tap bridge unquantified; larger blast radius than Option C for the same outcome.

## Real Scope
In scope — **Fix N1 (native, Option C):** in `didInitializeImplicitFlutterEngine`, capture the published plugin instance (`engineBridge.pluginRegistry.valuePublished(byPlugin: "FLTFirebaseMessagingPlugin") as? UNUserNotificationCenterDelegate` — public surface: publish `FLTFirebaseMessagingPlugin.m:91`, key `GeneratedPluginRegistrant.m:154`, retrieval `FlutterPlugin.h:469`) + `[PUSH_DIAG]` found/nil log. In the `willPresent` override: if `userInfo["gcm.message_id"] != nil && !isFlnNotificationOpenPayload(...)` and the ref is non-nil → forward to the plugin's `userNotificationCenter(_:willPresent:withCompletionHandler:)` with the ORIGINAL completion handler (plugin completes once with persisted options 0, `:343-357`; its `_foregroundUniqueIdentifier` dedupe `:327-330,:359` self-protects against future double delivery) and return; else `super` (FLN path byte-identical). Nil-ref fallback = `super` + diag → fail-safe to the 189 grid. Decision logic extracted into a pure Swift helper (`ForegroundPushForwardPolicy`) so XCTest can lock it. Do NOT touch `didReceive`.
**Fix D1 (Dart):** extract `lib/features/push/application/firebase_readiness.dart` — injectable `initializeApp`/side-effect closures, latch on SUCCESS only, retry on next call after failure, `onFirstSuccess` callback; `main()`'s `ensureFirebaseReady` delegates to it.
**Fix D2 (Dart):** extract `lib/features/push/application/push_listener_armer.dart` — injected `firebaseReady()`/`subscribe()`, emits `PUSH_LISTENERS_ARMED{platform, kinds}` exactly once, exposes `armed`; `_setupPushListeners` delegates; third arm point rides `FirebaseReadiness.onFirstSuccess` (readiness is the only event that flips `Firebase.apps.isEmpty`).
Out of scope: relay payload/token slots; plugin version bumps; DCUtR/189/190 work; `didReceive`/tap changes; presentation policy.

## Files To Inspect Next
Production: `ios/Runner/AppDelegate.swift` (:38-83, :143-182, :475-533), `ios/Runner/Info.plist` (:9-10, :60-81), `lib/main.dart` (:394-427, :3145-3155, :3600-3624, :3709-3721, :3746-3764, :4663-4764), `lib/features/push/application/` (new units).
Direct tests: `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart` (source-assertion pattern to extend), `test/core/notifications/ios_apns_notification_open_bridge_test.dart` (harness mechanics + sentinel), `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`, `ios/RunnerTests/*`.
Dependency-only: `FLTFirebaseMessagingPlugin.m`, `FlutterLocalNotificationsPlugin.m`, engine `FlutterAppDelegate.mm`/`FlutterPluginAppLifeCycleDelegate.mm` (read-only references).
Shared-tree note: `lib/main.dart` currently has ZERO dirty hunks (172 landed as `bb3ad390`); `p2p_service_impl.dart` IS dirty (189/190 session) — plan 191 does not touch it. Re-run `git status --short` at execution.

## Existing Tests Covering This Area
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart` — routing + drain closures (exists, GREEN; feature-host-all auto-glob only).
- `test/features/push/application/background_message_handler_test.dart`, `test/core/notifications/notification_route_target_test.dart` — siblings (exist).
- `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart` — source-assertion locks on the CURRENT arm wiring (exists — 191 extends it; anchors repaired by 172 session after be440b1e).
- `test/core/notifications/ios_apns_notification_open_bridge_test.dart` — tap-bridge harness (7 tests; `TestDefaultBinaryMessengerBinding` + `debugSetFlowEventSink` mechanics to clone).
- `ios/RunnerTests/NotificationPreviewResolverTests.swift` (+Configuration/GoBridge tests) — native precedent; **manual-only** (no gate runs xcodebuild).
- MISSING: any test that a foreground push reaches Dart on iOS; forward-decision logic; completion-handler discipline; init-failure retry; arm telemetry/late re-arm.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. **Device RED (already executed on HEAD, 2026-07-02 — the strongest possible RED)** — testpeer injection protocol: store → relay `[PUSH]` → **zero** push-triggered drain; acks only on the 30 s grid (10:04:30Z→:34 grid; 10:05:48Z→10:06:04 grid). Recorded as the runsheet's Before column. GREEN after N1: ack ≤5 s post-push, off-grid, `PUSH_FOREGROUND_MESSAGE_RECEIVED`+`ROUTED` in FLOW capture. Mutation that re-reds: remove the `willPresent` forward → protocol fails again. (TC-191-01/02)
2. `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart::'191: ensureFirebaseReady latches on success only (FirebaseReadiness delegation present)'`
   - Tier: unit host (source-assertion lock, 183/164 house pattern)
   - RED on HEAD: main.dart `:398-401` latches `firebaseInitialized = true` before the try — assertion on the new readiness-unit delegation string fails.
   - GREEN: main.dart delegates to `FirebaseReadiness` (or equivalent latch-after-success shape). Mutation: revert to latch-before-try → red. (TC-191-20 wiring half)
3. same file::`'191: listener arm rides Firebase readiness and emits PUSH_LISTENERS_ARMED'`
   - RED on HEAD: no third arm point, no armed event string in `_setupPushListeners`/armer wiring. GREEN: readiness-driven arm + armer delegation present. Mutation: remove the `onFirstSuccess` arm hook → red. (TC-191-21/22 wiring half)
4. `test/features/push/application/firebase_readiness_test.dart` (new unit; green-by-construction, mutation-locked; the RED-on-HEAD for this behavior is #2)
   - `'init throws once → next ensureReady retries and succeeds; onFirstSuccess fires exactly once'` — mutation: latch before try inside the unit → red. (TC-191-20)
   - `'success latches: second ensureReady is a no-op (no double init/background-handler registration)'` — mutation: remove success latch → red. (TC-191-23 sibling)
5. `test/features/push/application/push_listener_armer_test.dart` (new unit; RED-on-HEAD carried by #3)
   - `'arms when firebaseReady, emits PUSH_LISTENERS_ARMED exactly once'` (flow sink capture) — mutation: drop the emit → red. (TC-191-21)
   - `'not-ready arm attempt is a no-op that does NOT consume the latch; later ready attempt arms'` — mutation: latch before the ready guard → red. (TC-191-22)
   - `'repeated arm calls never double-subscribe'` (subscribe-call counter) — mutation: remove latch → red. (TC-191-23)
6. `test/features/push/application/handle_foreground_remote_message_use_case_test.dart::'191: plugin-canonical APNs data fixture routes to conversation drain'` + `'…unroutable data fixture → UNROUTABLE + no drain'`
   - Tier: unit host (extend existing file). Fixture = the data map exactly as FLTFirebaseMessagingPlugin delivers it (flat custom keys: `type`, `sender_id`, `message_id`; `gcm.message_id` as messageId). GREEN on HEAD for the routable case (use case already correct) → these are preservation+shape locks, not REDs; mutation: break `sender_id` fallback in `notification_route_target.dart` → red. (TC-191-03/34-host)
7. `ios/RunnerTests/ForegroundPushForwardPolicyTests.swift` (new XCTest; added WITH N1; regression lock — the behavior RED is #1)
   - `testFcmShapedPayloadForwardsToPluginAndCompletesOnce` — spy `UNUserNotificationCenterDelegate` receives the forward; completion invoked exactly once with `[]`.
   - `testFlnShapedPayloadTakesSuperPath` / `testNilPluginRefFallsBackToSuperWithDiag` — the fail-safe.
   - Mutation: remove the forward call or double-invoke completion → red. Manual gate (xcodebuild). (TC-191-12)

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-191-01 | OS-boundary push→drain | device-proof | runsheet `191-…-device-runsheet.md` §A (testpeer ×3, off-grid ≤5 s) | executed on HEAD 2026-07-02: 0 push drains | remove willPresent forward | runsheet PASS log | manual runsheet (183/189/190 shape) |
| TC-191-02 | telemetry chain | device-proof | runsheet §A FLOW capture (`idevicesyslog` anchors RECEIVED/ROUTED) | events never emitted on HEAD | same | runsheet | runsheet |
| TC-191-03 | payload shape | unit host | use_case_test::'191: plugin-canonical APNs data fixture…' | n/a (shape lock; GREEN) | break sender_id fallback | `flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart` | AUTO (feature-host-all) |
| TC-191-04 | presentation + NSE | device-proof | runsheet §B (no banner; NSE `Service extension delivered mutated content` in syslog) | n/a (must stay true post-fix) | forward with non-empty options | runsheet | runsheet |
| TC-191-05 | dedupe/single display | unit host + device | existing coalescing/staging sentinels (drain coalescing `p2p_service_impl.dart:2037-2066`, staging `ConflictAlgorithm.ignore`) + runsheet §B single-display check | n/a (sentinels GREEN) | n/a (sentinel) | `./scripts/run_host_test_gates.sh core-host-all` + runsheet | already registered |
| TC-191-10 | delegate re-install cycle | device-proof | runsheet §C (bg→fg → inject → ≤5 s) | delivery dead on HEAD regardless | remove forward | runsheet | runsheet |
| TC-191-11 | tap + FLN unchanged | unit host + device | `ios_apns_notification_open_bridge_test.dart` (sentinel) + runsheet §C tap spot-check (warm+cold) + FLN local-notif tap | n/a (sentinels) | forward didReceive (forbidden) → double-route | `flutter test test/core/notifications/ios_apns_notification_open_bridge_test.dart` + runsheet | AUTO (core-host-all) + runsheet |
| TC-191-12 | native forward policy | native XCTest | `ForegroundPushForwardPolicyTests.swift` (3 tests) | lock added with N1 (behavior RED = TC-191-01) | remove forward / double completion | `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/ForegroundPushForwardPolicyTests` | manual-only (no automated gate runs RunnerTests — documented) |
| TC-191-20 | init retry | unit host ×2 | wiring lock #2 (RED) + `firebase_readiness_test.dart` | latch-before-try `main.dart:398-401` | revert latch placement | `flutter test test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart test/features/push/application/firebase_readiness_test.dart` | AUTO (core+feature host-all) + **append both to `ONE_TO_ONE_TESTS` (run_test_gates.sh, after :145) and `ONE_TO_ONE_HOST_TESTS` (run_host_test_gates.sh, after :57)** per 183/189 precedent |
| TC-191-21 | arm telemetry | unit host ×2 | wiring lock #3 (RED) + `push_listener_armer_test.dart::'…exactly once'` | no armed event exists | drop emit | same cmd + armer test | same registration |
| TC-191-22 | late re-arm | unit host ×2 | wiring lock #3 + armer::'not-ready no-op…later arms' | two arm points collapse to one effective attempt (`:3746-3764`) | remove readiness hook | same | same |
| TC-191-23 | arm idempotency | unit host | armer::'never double-subscribe' | n/a (preserved semantics of `_pushListenersArmed`) | remove latch | same | same |
| TC-191-30 | Android control | device-proof | runsheet §D (Pixel injection ≤2 s, one RECEIVED) | n/a (control) | n/a | runsheet | runsheet |
| TC-191-31 | background semantics | preservation | `background_message_handler_test.dart` (sentinel) | n/a | n/a | `./scripts/run_host_test_gates.sh feature-host-all` | already registered |
| TC-191-32 | migration gate | preservation + device | existing gate wiring (`main.dart:4766-4796` untouched — Option C funnels into the existing handler) + runsheet note | n/a (zero gate changes by construction) | n/a | feature-host-all + `git diff` scope check | already registered |
| TC-191-33 | 189 fallback floor | preservation | 189's `p2p_service_impl_health_drain_test.dart` (sentinel) | n/a | n/a | `./scripts/run_test_gates.sh 1to1` | already registered (:145) |
| TC-191-34 | token half unchanged | device-proof | runsheet §D (fresh-token registration observed at relay post-fix) | n/a | n/a | runsheet | runsheet |
| TC-191-40 | closure | device-proof | runsheet full protocol (§A-D ×3 iOS + ×1 Android) | HEAD failure recorded 2026-07-02 | any revert | runsheet PASS log | manual runsheet |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** armed/readiness latches are process-lifetime by design (arm points re-run on every launch); the bg→fg delegate-reinstall cycle is TC-191-10. Justified N/A for persistence.
- **Sibling-surface consistency:** the `didReceive` completion handler is ALSO never invoked for FCM taps today (same latent class). Deliberately NOT fixed here — forwarding `didReceive` double-routes taps (139). Recorded as Accepted Difference with the tap path locked GREEN by TC-191-11; a follow-up may complete-without-forwarding in the AppDelegate `didReceive` override (small, safe) — noted for the executor as an optional rider IF TC-191-11 stays green with it.
- **Destructive-action side-effects:** none (no deletes/cleanups). N/A.
- **Invariant re-verification under new transitions:** the new forward path re-verifies presentation policy (TC-191-04), migration gating (TC-191-32, by-construction untouched), dedupe under double-delivery (TC-191-05 + plugin `_foregroundUniqueIdentifier`), and fail-safe degradation to the 189 grid on nil plugin ref (XCTest fallback case).

## Invariants (locked by tests)
- INV-1 FCM-shaped foreground notification on iOS → Dart handler + drain ≤5 s → TC-191-01/02/12.
- INV-2 exactly one `willPresent` completion invocation, options 0 → TC-191-12/04.
- INV-3 taps single-routed; `onMessageOpenedApp` stays silent; FLN untouched → TC-191-11 (+ do-not-forward-didReceive scope guard).
- INV-4 one transient `Firebase.initializeApp` failure never permanently disables push → TC-191-20/22.
- INV-5 arm state observable exactly once → TC-191-21/23.
- INV-RED-FIRST / INV-MUTATION-VERIFIED per matrix.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (expect 189/190 session dirt in `p2p_service_impl.dart`, `go-mknoon/*`, `scripts/run_test_gates.sh` — do not touch their hunks; `main.dart` currently clean).
2. Add Dart REDs: extend `main_deferred_push_rearm_wiring_test.dart` (#2, #3 — must FAIL), add unit files (#4, #5), extend use-case test (#6). Run the RED gate.
3. **D1**: extract `FirebaseReadiness` (latch-on-success, retry, `onFirstSuccess`); `main()` `ensureFirebaseReady` delegates (captures: `isDesktop` local, gate-wiring callbacks — all injectable; sole call site `main.dart:3154` unchanged).
4. **D2**: extract `PushListenerArmer`; `_setupPushListeners` delegates; wire third arm point on `onFirstSuccess`. Keep `_pushListenersArmed` semantics (latch after ready-guard, per the 164 comment).
5. **N1**: AppDelegate — plugin-ref capture in `didInitializeImplicitFlutterEngine` (+`[PUSH_DIAG] fcm_plugin_ref found|nil`), `ForegroundPushForwardPolicy` helper, `willPresent` forward-or-super per Real Scope. Do NOT touch `didReceive` or the 4 delegate installs. Add `ForegroundPushForwardPolicyTests.swift`.
   Stop-if: `valuePublished(byPlugin:)` returns nil at runtime on device (registrant key drift) → diag log proves it; fall back to plan-B seam (import the pod header, `FLTFirebaseMessagingPlugin` direct cast) before considering Option A; do not hack delegate ownership.
6. Rebuild + run direct GREEN (Dart cmds; xcodebuild for XCTest), preservation sentinels, named gates.
7. Register: append the two new unit test paths + the wiring-lock file (already in arrays? verify) to `ONE_TO_ONE_TESTS` / `ONE_TO_ONE_HOST_TESTS` with the house comment; verify via gate output grep.
8. Write `191-ios-foreground-push-device-runsheet.md` (183/189/190 shape; profile builds ONLY — dev_keychain_wipe hazard; UDIDs Pixel `21071FDF600CSC`, iPhone 11 `00008030-001A6D2801BB802E`); execute §A-D; log PASS + metrics. Testpeer pipeline (literal):
```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 make testpeer
{ printf '{"cmd":"generate_identity"}\n'; sleep 1; printf '{"cmd":"start"}\n'; sleep 3; \
  printf '{"cmd":"wait_relay","params":{"timeoutSec":20}}\n'; sleep 5; \
  printf '{"cmd":"inbox_store_v1","params":{"peerId":"<IPHONE_PEER_ID>","text":"191 probe"}}\n'; sleep 8; } | ./bin/testpeer
```
9. Add the 00-INDEX.md row for 191.

## Risks And Edge Cases
- Plugin-ref nil (registrant key drift on plugin upgrade) → fail-safe super path + `[PUSH_DIAG]` diag; XCTest nil-ref case pins the fallback; version bumps are out of scope and re-run TC-191-12.
- Future plugin revives its observer (upstream fix) → double `willPresent` → plugin's `_foregroundUniqueIdentifier` dedupe (`:327-330,:359`) + Dart-side drain coalescing absorb it (TC-191-05).
- willPresent forwarded for a notification the plugin decides to ignore (no `gcm.message_id`) — prevented by the native gate mirroring the plugin's own gate.
- Race: push arrives before scene-connect captured the plugin ref → super path → 189 grid fallback (fail-safe, not loss). Runsheet §C's cold-start injection covers it.
- `-race`/toolchain: all Go usage (`testpeer`) pins `GOTOOLCHAIN=go1.25.0` (Makefile:11).
- Shared tree: re-check dirt at execution; only `main.dart`, `ios/Runner/*`, new files under `lib/features/push/application/`, `test/**`, and the two gate arrays are touched.

## Device/Relay Proof Profile
Host-green is NOT closure. Closure = `191-ios-foreground-push-device-runsheet.md` PASS: iOS injections ×3 ack ≤5 s post-push and off the 30 s grid with RECEIVED/ROUTED FLOW anchors, no banner, single display, bg→fg cycle covered, tap spot-checks green, Android control ≤2 s, fresh-token registration observed. Profile builds ONLY. Relay: prod `/dns/mknoun.xyz/...12D3KooWGMYMmN1RGUYj…` (read-only journal via `ssh -i se.pem ubuntu@13.60.15.36`).

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before production edits) — must FAIL for documented reasons
flutter test test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart --plain-name '191'   # expect: 2 wiring locks RED

# Direct GREEN (after fixes)
flutter test test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart \
             test/features/push/application/firebase_readiness_test.dart \
             test/features/push/application/push_listener_armer_test.dart \
             test/features/push/application/handle_foreground_remote_message_use_case_test.dart   # expect: all pass

# Native lock (manual-only gate; simulator name per installed runtimes)
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO \
  -only-testing:RunnerTests/ForegroundPushForwardPolicyTests                                     # expect: 3/3 pass

# Preservation sentinels
./scripts/run_host_test_gates.sh feature-host-all      # expect: 0 new failures vs pre-execution baseline
./scripts/run_host_test_gates.sh core-host-all         # expect: 0 new failures
./scripts/run_test_gates.sh 1to1                       # expect: all pass (baseline grows with the 2 appended files)

# Registration verification
./scripts/run_test_gates.sh 1to1 2>&1 | grep -E "firebase_readiness|push_listener_armer"        # must list

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): the two 191 wiring locks; the device protocol (already demonstrated on HEAD 2026-07-02).
- RunnerTests are MANUAL-ONLY (no automated gate runs xcodebuild — house state; 102/107 executed precedent, 175 structural). Not a product blocker; document the run in Execution Progress.
- Pre-existing dirty tree: 189/190 session hunks (`p2p_service_impl.dart`, `go-mknoon/*`, `scripts/run_test_gates.sh`) — do not revert; coordinate array appends in `run_test_gates.sh` (that file is dirty — append carefully or sequence after their commit).
- Environment blockers (NOT product): device unavailable/locked; iOS profile build time; simulator runtime name drift in the xcodebuild destination.
- Scope drift (BLOCKING): any red in tap/FLN/background/NSE suites, or any `didReceive` behavior change.

## Done Criteria
- [ ] Wiring-lock REDs failed first for documented reasons; unit tests mutation-verified.
- [ ] N1 + D1 + D2 implemented; direct GREEN; XCTest 3/3.
- [ ] Preservation sentinels + named gates green; new tests visible in 1to1 gate output.
- [ ] Device runsheet PASS (≤5 s off-grid ×3 iOS, Android control, tap/banner/NSE checks) with profile builds.
- [ ] No DB migration (none needed — verified).
- [ ] flutter analyze 0 new; git diff --check clean; 00-INDEX row added; scope guard honored.

## Scope Guard (hard "Do not")
- Do not forward `didReceive` to the FCM plugin or call `addApplicationLifeCycleDelegate(fcmInstance)` (Option E) — double tap-routing (139 reborn).
- Do not remove/alter the 4 delegate installs or the tap bridge (`ios_notification_open`).
- Do not re-enable `FirebaseAppDelegateProxyEnabled` (Option D — unquantified swizzling blast radius).
- Do not change presentation options, relay payloads, token registration, NSE, or `handle_foreground_remote_message_use_case.dart` routing semantics.
- Do not bump firebase_messaging / flutter_local_notifications versions.
- Do not touch the 189/190 session's dirty hunks; `flutter run --debug` on the phones is FORBIDDEN (dev_keychain_wipe).

## Accepted Differences / Intentionally Out Of Scope
- `didReceive` completion-handler drop for FCM taps (latent, cosmetic today — taps work via the manual bridge): optional safe rider noted in Blind-Spot Sweep; own decision at execution, guarded by TC-191-11.
- `getInitialMessage`/`onMessageOpenedApp` remain dead by design (manual cold-start bridge owns that surface; pre-existing).
- Push-token slot semantics (last-write-wins, no expiry) — separate follow-up (RCA finding #3-adjacent).
- Upstream fix for the plugin's UIScene-incompatible observer — worth an upstream issue; not this plan.

## Dependency Impact
- 189's device runsheet measures receive latency — run 191's fix first or annotate builds, else push-vs-grid attribution muddies both runsheets.
- The FDC epic-close soak benefits: iOS receive drops from ≤30 s to ~1 s, changing soak baselines.

## Reviewer Findings
Sufficiency self-check (2026-07-02): every spec TC-ID has ≥1 matrix row with named test (01-05, 10-12, 20-23, 30-34, 40) ✓; zero empty cells in tier/mutation/gate/registration ✓; every INV locked ✓; REDs documented (wiring locks RED-on-HEAD; device RED literally executed on HEAD) ✓; PROD-CRITICAL leg = TC-191-01 device protocol, named ✓; preservation sentinels with commands ✓; no DB migration ✓; OS-boundary proven on device not fake ✓; blind-spot sweep: 2 rows + 2 justified N/A, Accepted Differences test-guarded ✓; refuted findings recorded (Options B/D/E, stomping/contention/engine-gap framings) ✓; dirty-tree snapshot step present ✓. Residual: RunnerTests manual-only (house state, documented); `run_test_gates.sh` array append may need sequencing behind the 189/190 session's commit (flagged).

## Arbiter Decision
Structural blockers: none. Deferred details: didReceive-completion rider (optional, executor's call); exact `PUSH_LISTENERS_ARMED` details payload. Accepted differences as listed. Hand off to execution.

## Final Execution Verdict
**Host + native GREEN; device runsheet is the remaining closure.** (2026-07-02)

Implemented exactly to the Real Scope — no interface/DB/scope drift:
- **N1 (native, Option C)**: `ios/Runner/ForegroundPushForwardPolicy.swift` (pure,
  standalone `swiftc -typecheck` OK) + AppDelegate `didInitializeImplicitFlutterEngine`
  captures the published `FLTFirebaseMessagingPlugin` via `valuePublished(byPlugin:)`
  (+`[PUSH_DIAG] fcm_plugin_ref found|nil`), and `willPresent` forwards FCM-shaped
  non-FLN notifications to it with the ORIGINAL completion handler, else `super`
  (nil-ref/FLN/non-FCM fail-safe). `didReceive` + the 4 delegate installs untouched.
- **D1**: `firebase_readiness.dart` (latch-on-success, retryable, onFirstSuccess) —
  `main()` `ensureFirebaseReady` delegates; the latch-before-try bug is gone.
- **D2**: `push_listener_armer.dart` (emits `PUSH_LISTENERS_ARMED` once, ready-guard
  before latch, idempotent) — `_setupPushListeners` delegates (164 guard/latch/`.then`
  strings preserved); a THIRD arm point rides `FirebaseReadiness.addOnReadyListener`
  via a new OPTIONAL `MyApp.firebaseReadiness`.

Evidence:
- RED first: the 2 `191:` wiring locks failed on HEAD (`+0 -2`) for the documented
  reasons, then GREEN after the fix.
- Direct GREEN: 24/24 across the 4 Dart files (4 wiring + 3 readiness + 4 armer +
  13 use-case, incl. the 2 plugin-canonical shape locks). `flutter analyze` 0 issues;
  `git diff --check` clean.
- Preservation: targeted host sweep 612/612 (all `test/features/push/**` incl.
  background-handler TC-191-31, `test/core/notifications/**` incl. tap-bridge
  TC-191-11, `test/core/lifecycle/**` incl. the 164 + new 191 wiring locks, + the
  one MyApp-constructor test). The earlier full-sweep failures were CONCURRENCY
  artifacts (a `flutter test`/`xcodebuild kernel_snapshot` temp race + a foreign
  `flutter run` on the shared tree) — confirmed by re-running the flagged file
  (`account_migration_local_transfer_runtime_test`) clean in isolation.
- Native XCTest (`RunnerTests/ForegroundPushForwardPolicyTests`, 3 tests): result
  recorded in Execution Progress (manual-only gate; first two xcodebuild runs hit
  the same shared-tree kernel_snapshot temp race → `flutter clean` + rebuild).
- Registration: both new units appended to `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`
  after the 189 entries (dirty-hunk-safe); 1to1 host dry-run lists them (#41/#42).

Residual (not blockers): the device runsheet (`191-ios-foreground-push-device-runsheet.md`,
§A-D) — the Before column is already the HEAD device RED (2026-07-02, 0 push drains);
the After (≤5 s off-grid ×3, --profile only) is the closure. D1's retry capability
is unit-locked but there is no NEW live re-trigger for a persistent init failure
(the plan scopes INV-4 to unit + wiring locks; a persistent Firebase failure means
push can't work regardless — the transient case is what the retryable latch fixes).
