# VC-06 — Android ringing + background call  (New Feature)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — grounded by `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md` (story row VC-06, rules 1/2/3/4/5/6, metrics table "Ring latency / answer latency" row)

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | 4 grounding digests (platform-av-push, relay-server-ops, signaling-messaging, harness-conventions) + drift re-verification of every RED-target anchor (inbox.go, background_message_handler.dart, notification_route_target.dart, AndroidManifest.xml, MainActivity.kt, build.gradle.kts, p2p_bridge_client.dart, run_host_test_gates.sh, check_reliability_simulation_discovery.sh, FDC-S1 RESULTS) | all load-bearing anchors re-verified on the dirty `new-orbit` tree; refuted digest claims NOT carried | plan authoring |
| 2026-07-13 | Planner | this file | ring-first/node-on-answer decision recorded with FDC-S1 numbers; `call_push_request` designed as strict-opt-in push (reaction-push template, NOT the fail-open deposit path) | sufficiency review |
| 2026-07-13 | Reviewer (sufficiency) | this file vs sufficiency-checklist.md | all gates pass (see Reviewer Findings) | arbiter |
| 2026-07-13 | /tdd-review (adversarial) | this file vs VC-06 assessment + epic contract locks L1–L7 | 2 material + 6 moderate + 3 nit findings — all applied (per-slice RED slicing; pre-committed latency budgets ring ≤3.0 s p95 / answer ≤5.0 s p95 over 10 trials; E3 ring_timeout; id-helper + payload-encoding pins; L5 orchestrator rename to run_call_device_real.dart) | arbiter |
| 2026-07-13 | Arbiter | this file (post /tdd-review) | accepted (post /tdd-review) — structural blockers: none | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | EC2 redeploy + live push probe | | (journalctl + device ring evidence) | rule-2 gate | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Spec / intent: VC-00 roadmap story row VC-06 + the brief inlined in Exact Problem Statement below.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose). Home gate = `1to1` (bridge/router/push files edited here live in `ONE_TO_ONE_TESTS`); host floors = `feature-host-all` / `core-host-all`.
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (new orchestrator + proof harness MUST classify) and `./scripts/run_test_gates.sh completeness-check` (classify_path at `scripts/run_test_gates.sh:870`).
- Numbering / index: VC plans are NOT indexed in `Test-Flight-Improv/00-INDEX.md` (VC-00 rule 7 — feature subdirectories stay un-indexed; verified zero FDC/LiveKit references).
- Relay ops truth: redeploy procedure of `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md:141-150` + `go-relay-server/README.md:1-39` (unit `relay-server` on `mknoun.xyz` / 13.60.15.36).
- Cold-start truth: `Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-S1-cold-start-timing-RESULTS.md` §3.2.1 — Pixel 6 `node:start` return median **1158 ms / p90 1200 ms**; relay-ready **1364 / 1564 ms**.
- Sibling contracts consumed (cross-referenced by code, both authored in this epic): **VC-04** (`call_offer`/`call_answer`/`call_decline`/`call_busy` envelope types, `callId` idempotency, short TTL, fast-path-only rule) and **VC-05** (`lib/features/call/` feature dir, StartCallUseCase, IncomingCallScreen, `CALL_CONNECTED` flow event, in-call controller).

---

## Session Classification
**implementation-ready** — every seam is verified in source on HEAD; the relay action, push handler branch, notification channel, FGS, and bridge plumbing are all host-testable; the OS-boundary ring/answer legs close on the Android USB-device + emulator rig this project already mandates (VC-00 rule 1). Two external preconditions are stop-ifs, not unknowns: VC-05 must be landed (this story edits its StartCallUseCase/IncomingCallScreen), and the e2e ring gate requires the relay redeployed with `call_push_request` (rule 2 — this plan carries the redeploy).

---

## Exact Problem Statement

A backgrounded or killed Android callee never learns a call is happening. `call_*` envelopes are **fast-path-only by design** (VC-00 rule 5; VC-04): they are never deposited in the relay inbox, so the relay's only push trigger — the deposit→push seam at `go-relay-server/inbox.go:1307-1316` (`extractChatPushMetadata(...).ShouldNotify`) — **never fires for calls**. Even if a call push arrived, the client would drop it: `firebaseMessagingBackgroundHandler` (`lib/features/push/application/background_message_handler.dart:351`) gates on `shouldShowBackgroundPushFallbackNotification` (`:400`), which returns false for any type unknown to `NotificationRouteTarget.fromRemoteMessageData` (`lib/features/push/application/background_push_notification_fallback.dart:63-73`; type switch `lib/core/notifications/notification_route_target.dart:157-263` has no call kind). And the app has no way to *ring*: no `USE_FULL_SCREEN_INTENT` permission, no call notification channel, no receivers, and the only FGS is `MigrationKeepAliveService` (`dataSync`, `AndroidManifest.xml:99-102`) — an in-progress call has nothing keeping mic capture alive when the screen locks or the user leaves the app. Who feels it: every callee whose phone is in a pocket — VC-05's foreground call only works if both users are staring at the app.

**What must improve:** (1) a caller-side `call_push_request` relay action that sends a HIGH-PRIORITY, **data-only** FCM message to the callee's registered token, capability-gated and rate-limited, deployed live to EC2 (rule 2); (2) killed/background Android handling of that push — full-screen-intent ringing notification (ringtone, vibration, Answer/Decline actions) shown *without starting the node*, ring timeout = **min(45 s, TTL remaining from `sent_at_ms`)** → missed-call notification. The 45 s ceiling equals VC-04's signaling TTL (`kCallOfferTtl = 45000` ms, owned by VC-04 — contract lock L1); the ring can never outlive the offer by construction (`min()`), and the 30–60 s ring band itself is a design choice (Signal/Matrix precedent), NOT a repo-derived constraint — do not reopen the constant under execution pressure without a recorded decision; (3) decline sends `call_decline` after a bounded node start; answer cold-launches into VC-05's IncomingCallScreen with the offer payload and connects; (4) an ongoing-call foreground service (`phoneCall|microphone`) so a connected call survives backgrounding/screen-off; (5) ring-latency + answer-latency flow events (VC-00 metrics row) with **pre-committed pass/fail budgets** (see Pre-Committed Latency Budgets below): ring shown ≤ 3.0 s p95, answer-readiness ≤ 5.0 s p95.

**What must stay unchanged → preserved-green sentinels:** existing push routing for all current types (`background_message_handler_test.dart`, `background_push_notification_fallback_test.dart`); unknown-type forward-compat in the router (`incoming_message_router_test.dart::routes unknown types…`); relay push contract (`push_payload_closure_test.go` `TestRelayNotificationClosure_*`, `push_token_registration_test.go`, `protocol_contract_test.go` unknown-action ERROR shape); migration keep-alive FGS untouched; `call_*` stays out of the durable inbox and out of `PendingMessageRetrier` (VC-00 rule 5).

---

## Root Cause (verify → refute confirmed) — missing mechanism, verified absences

New feature: the "root cause" is a set of **verified absences**, each re-read on HEAD (dirty tree, 2026-07-13):
1. Relay: `HandleInboxStream` action switch (`go-relay-server/inbox.go:2066`) has 13 cases, none call-related; unknown action → ERROR (`:2277`). `extractChatPushMetadata` (`:948`) default = silent. No rate limiter exists anywhere in the relay (grep `rate|limiter` over non-test `.go` = 0 mechanism hits).
2. Client push: no `call` kind in `notification_route_target.dart:157-263`; data-only unknown-type push is fully dropped at `background_message_handler.dart:400` (staging `_stagePushEnvelopeIfPresent` runs only after the gate, `:425`).
3. Ring UX: `USE_FULL_SCREEN_INTENT` absent from `AndroidManifest.xml` (permissions block `:2-14`); no receivers; channels are only `mknoon_messages`/`mknoon_messages_silent` (`lib/core/notifications/local_notification_support.dart:3,:10`); `FlutterNotificationService.initialize` wires **no** `onDidReceiveBackgroundNotificationResponse` (`lib/core/notifications/flutter_notification_service.dart:59` — foreground tap only), so a background Decline action has no handler today.
4. FGS: only `dataSync` type declared (`AndroidManifest.xml:14,:99-102`); no `FOREGROUND_SERVICE_PHONE_CALL`/`FOREGROUND_SERVICE_MICROPHONE`.
5. Push capability: token registration carries a capabilities list end-to-end (`go-mknoon/node/inbox.go:39,:793-832`; `go-mknoon/bridge/bridge.go:1354-1390`; Dart default list at `lib/core/bridge/p2p_bridge_client.dart:787-810`) — but no call capability string exists.

**Refuted / do-NOT-re-introduce (from the adversarial digests):**
- Do NOT hook the ring into the inbox deposit→push seam (`inbox.go:1307-1316`) — `call_*` is never inboxed (VC-04/rule 5); the ring trigger must be the new caller-driven `call_push_request` action.
- Do NOT treat a fast-path send `acked=true` as "callee handled it": for any new `call_*` type Go acks **before** emitting to Dart (`go-mknoon/node/node.go:1854-1860`; deferred-ack applies only to the four legacy types, `:1693-1717`). Ring confirmation comes from the callee's `call_answer`/`call_decline`, never from the wire ack.
- Do NOT model the call push on the fail-open ordinary chat push; the correct template is the **strict opt-in** reaction path (`SendReactionNotification`, `inbox.go:178-195`: capability required via `entry.hasCapability` — defined at `go-relay-server/reaction_push.go:47` — never fail-open).
- Do NOT assume `go-relay-server` lacks pion deps (refuted): `pion/turn/v2` is already an indirect dep — irrelevant here, VC-03 owns TURN; VC-06 adds no pion code.
- Do NOT start the Go node in the FCM headless isolate (decision below) and do NOT copy the digest's stale line `:350` for the handler (declaration is `:351`).

---

## Real Scope

**In scope (VC-06):**
- **Relay** (`go-relay-server/`): new `call_push_request` inbox action (named handler func per the FDC-08 named-handler rule, `inbox.go:2027-2032` comment) → `PushService.SendCallInviteNotification` modeled on the strict reaction path: callee token lookup, `call_invite_v1` capability gate, per-(caller→callee) rate limit (3 requests / 30 s sliding window, in-memory), env kill-switch `RELAY_CALL_PUSH_ENABLED` (default on; `SetDirectReactionPushEnabled` pattern, `main.go:102`), data-only high-priority FCM message `{type: call_invite, call_id, caller_id, sent_at_ms, envelope?|offer_omitted}` (encrypted `call_offer` envelope embedded when within the `maxPushDataBytes=4000`/`maxProviderPayloadBytes=3800` budgets, `inbox.go:61-66`; stripped + `offer_omitted:"1"` when not). iOS-platform tokens: counted `call_ios_deferred`, **no send** (VC-07 owns the APNs/PushKit payload — branch exists, marked NEW/deferred). New Prometheus counter `relay_call_push_total{result}` (promauto var in `metrics.go`, conventions at `:194-197`). **EC2 redeploy + live verification** (rule 2, section below).
- **Go client + bridge** (`go-mknoon/`): `node.RelayCallPushRequest(...)` following the `RegisterPushToken`/`presence_set` client patterns (`node/inbox.go:793-832`, `:383-404` — old relay "Unknown action: call_push_request" maps to graceful `unsupported`, NET-REL-07); exported `bridge.RelayCallPushRequest` (okJSON/errJSON shape of `InboxRegisterToken`, `bridge.go:1358+`).
- **Dart caller side**: cmd wiring `'relay:call_push'` in `go_bridge_client.dart` cmd map (`:122-150` region) + `callP2PCallPushRequest` in `p2p_bridge_client.dart`; `P2PServiceImpl.requestCallRingPush(peerId, callId, envelope)` with FIRST-LINE `_allowsAccountNetworkSideEffects('p2p_call_push_request', peerId: …)` (rule 4; pattern `p2p_service_impl.dart:555-572`, call sites `:2339,:2409,:4907`); `callInvitePushCapability = 'call_invite_v1'` added to the default `register_token` capabilities list (`p2p_bridge_client.dart:787-810`); VC-05's StartCallUseCase extended: fire `requestCallRingPush` **in parallel** with the fast-path `call_offer` send, and **re-send `call_offer` every 5 s while ringing** (within VC-04 TTL; idempotent by `callId`) so an `offer_omitted` answerer still converges.
- **Dart callee side (Android ring path)**: early `call_invite` branch in `firebaseMessagingBackgroundHandler` **before** the `:400` fallback gate → new `lib/features/call/application/background_call_ring_use_case.dart`: stale check (`sent_at_ms` + VC-04 TTL `kCallOfferTtl = 45000` ms → straight missed-call, no ring), dedupe (deterministic notification id from `callId` via ONE shared helper: `int callNotificationId(String callId)` in `lib/core/notifications/local_notification_support.dart`, a stable FNV-1a hash of `callId` masked to 31 bits — the ONLY id source for the FCM headless isolate ring-show, the FLN background-response isolate cancel, and the live-offer notifier that E2's push+live dedupe depends on; D5/D6/D7/D9 must all consume this helper), full-screen-intent ring notification on new `mknoon_calls` channel (`Importance.max`, ringtone audio attributes, vibration, `AndroidNotificationCategory.call`, `fullScreenIntent: true`, Answer/Decline actions, `timeoutAfter` = min(45 s, TTL remaining from `sent_at_ms`) per contract lock L1) + scheduled missed-call notification (FLN `zonedSchedule`, `inexactAllowWhileIdle` — no exact-alarm permission) cancelled on answer/decline. **The node is NOT started by the handler** (decision + justification below). `call_invite` kind added to `NotificationRouteTarget` (Dart only — the iOS AppDelegate whitelist is VC-07's). Foreground `onMessage` `call_invite` → no-op (live `call_offer` via router is authoritative, VC-05). New background notification-response entry-point (`@pragma('vm:entry-point')` top-level fn wired via `onDidReceiveBackgroundNotificationResponse`) handling **Decline**: cancel ring + missed-call schedule, bounded node start (≤10 s), send `call_decline` fast-path (VC-04 builder; no repo persist), degrade gracefully if node start fails (caller's TTL expiry covers it). **Answer**: full-screen intent / Answer action (`showsUserInterface: true`) cold-launches MainActivity with the route payload → `main.dart` `_handleNotificationRouteTarget` new case → VC-05 IncomingCallScreen with `{callId, callerId, envelope?}`. **Payload encoding is pinned, not improvised:** the notification action payload is the exact string the existing `NotificationRouteTarget.toPayload()`/`fromPayload()` convention round-trips (`notification_route_target.dart:68,:87` — new `call_invite:` prefix case), with the ciphertext envelope (≤ ~3.8 KB) embedded **verbatim** when it was present in the push; dropping the envelope "to keep the payload small" is a scope violation (it silently degrades every answer to the 5 s re-offer path). Envelope present → decrypt and feed the incoming-offer flow immediately while the node starts; omitted → "connecting" state until the caller's re-offer lands post node-start.
- **Ongoing-call FGS**: manifest `<service .CallForegroundService exported=false foregroundServiceType="phoneCall|microphone"/>` + `FOREGROUND_SERVICE_PHONE_CALL` + `FOREGROUND_SERVICE_MICROPHONE` + `USE_FULL_SCREEN_INTENT` permissions + FLN scheduled receivers (`ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`, `RECEIVE_BOOT_COMPLETED`); Kotlin `CallForegroundService` modeled on `MigrationKeepAliveService.kt:28-58` (own low-importance `mknoon_ongoing_call` channel); MethodChannel `mknoon/call_foreground` in `MainActivity.configureFlutterEngine` (precedent `:39-54`); Dart hold-counted driver `call_foreground_keep_alive.dart` modeled on `MigrationTransferKeepAlive` (`migration_transfer_keep_alive.dart:24-99`, MissingPluginException → no-op); acquired by VC-05's in-call controller on connect **while the activity is foreground** (Android 14 mic-FGS background-start restriction), released on call end. API-level gates: `NotificationManager.canUseFullScreenIntent()` exposed over the same channel; `false` → ring degrades to heads-up (still audible). `targetSdk` is `flutter.targetSdkVersion` (`android/app/build.gradle.kts:81`, not pinned in-repo) — execution step verifies the merged value.
- **Metrics** (VC-00 metrics row owned by VC-06): flow events `CALL_PUSH_REQUESTED{callId,sentAtMs}` (caller), `CALL_RING_SHOWN{callId,ringLatencyMs}` (callee), `CALL_ANSWER_TAPPED{callId}`; answer latency = `CALL_ANSWER_TAPPED`→VC-05 `CALL_CONNECTED` computed by the e2e runsheet; relay `relay_call_push_total{result}`.
- **e2e** (rule 1): emulator caller → USB-device callee, app KILLED (ring full-screen, answer, audio connects per VC-05 assertions), repeated BACKGROUNDED, and a TIMEOUT scenario (no answer → ring gone + missed-call posted, app never launched); orchestrated by the epic's shared call orchestrator `integration_test/scripts/run_call_device_real.dart` (contract lock L5 — VC-06 creates it and contributes the `ring_killed`/`ring_backgrounded`/`ring_timeout` scenarios; VC-08/VC-09 append theirs; `--scenario all --list-scenarios` discovery contract) + caller harness `integration_test/call_ring_caller_proof_test.dart`; **precondition gate**: deployed relay answers `call_push_request` (probe first, abort with a precondition message otherwise).

**Out of scope (owning story):** iOS anything — APNs/PushKit payload, voip background modes, AppDelegate route whitelist (`AppDelegate.swift:666-709`) → **VC-07**; ConnectionService/Telecom framework → deferred, see Accepted Differences; video → **VC-08**; envelope type definitions/TTL/glare → **VC-04** (consumed as contract); in-call UI/audio engine → **VC-05** (consumed; VC-06 edits only its start-call ring loop, screen entry payload, and FGS acquire hooks); TURN → **VC-03**; wake-token gate flip → the FDC-09 successor story (stance recorded in Accepted Differences).

---

## Files To Inspect Next

**Production — relay:** `go-relay-server/inbox.go` (action switch `:2066-2277`, PushService `:78-152`, reaction template `:178-195`, budgets `:61-66`, headers `:496-508`), NEW `go-relay-server/call_push.go`, `metrics.go`, `main.go` (env wiring `:102` pattern), `wake_token_store.go:34` (context only).
**Production — Go client/bridge:** `go-mknoon/node/inbox.go` (`:383-404` presence_set parse pattern, `:793-832` register-token stream pattern), NEW `go-mknoon/node/call_push_request.go`, `go-mknoon/bridge/bridge.go` (`:1358+` handler pattern).
**Production — Dart:** `lib/core/bridge/go_bridge_client.dart` (`:122-150`), `lib/core/bridge/p2p_bridge_client.dart` (`:787-810`), `lib/core/services/p2p_service_impl.dart` (gate `:555-572`; registerPushToken `:4906`), `lib/features/push/application/background_message_handler.dart` (`:351,:400,:425,:442`), `lib/features/push/application/background_push_notification_fallback.dart` (`:63-73` — unchanged, sentinel), `lib/core/notifications/notification_route_target.dart` (`:157-263`), `lib/core/notifications/local_notification_support.dart`, `lib/core/notifications/flutter_notification_service.dart` (`:56-91`), `lib/main.dart` (`:368-370` desktop-guarded registration; `_handleNotificationRouteTarget` ~`:4670`), NEW `lib/features/call/application/{background_call_ring_use_case,call_decline_background_handler,call_foreground_keep_alive}.dart`, VC-05's start-call use case + IncomingCallScreen (in `lib/features/call/`).
**Production — Android:** `android/app/src/main/AndroidManifest.xml` (`:2-14` permissions, `:99-102` FGS precedent), `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` (`:39-54` channel precedent; onNewIntent pin `:105+`), `MigrationKeepAliveService.kt` (template), NEW `CallForegroundService.kt`, `android/app/build.gradle.kts:80-81`.
**Direct tests + integration tests:** `test/features/push/application/background_message_handler_test.dart`, `background_push_notification_fallback_test.dart`, `handle_foreground_remote_message_use_case_test.dart`, `test/core/notifications/{notification_route_contract_matrix_test,local_notification_support_test,flutter_notification_service_test,main_activity_onnewintent_pin_test}.dart`, `test/core/bridge/{go_bridge_client_test,p2p_bridge_client_test}.dart`, `test/features/account_migration/application/migration_transfer_keep_alive_test.dart` (template), `go-relay-server/{push_payload_closure_test,push_token_registration_test,protocol_contract_test,forbidden_field_classifier_test,metrics_test}.go`, NEW test files in the RED catalog.
**Dependency-only context (not edited):** `go-relay-server/reaction_push.go` (`:18` capability const, `:47` hasCapability), `push_token_store.go:22-37`, `lib/features/account_migration/application/migration_transfer_keep_alive.dart`, `integration_test/scripts/run_1to1_device_real.dart` + `run_notification_tap_device_real.dart` (conventions), `send_delivery_receipt_use_case.dart:110` (fast-path precedent), FDC-S1 RESULTS.

---

## Existing Tests Covering This Area

| Test | Covers | Status |
|---|---|---|
| `test/features/push/application/background_message_handler_test.dart` | background push pipeline for existing types | exists — extended (VC-06-D5/D6/D8); existing cases are sentinels |
| `test/features/push/application/background_push_notification_fallback_test.dart` | unknown-type drop gate | exists — sentinel (gate itself unchanged; call branch runs BEFORE it) |
| `test/features/push/application/handle_foreground_remote_message_use_case_test.dart` | foreground remote-message handling | exists — extended (VC-06-D10) |
| `test/core/notifications/notification_route_contract_matrix_test.dart` + `notification_route_target` coverage | route-target parse/dispatch matrix | exists — extended (VC-06-D4/D12) |
| `test/core/notifications/local_notification_support_test.dart` | channels/details | exists — extended (VC-06-D11) |
| `test/core/notifications/flutter_notification_service_test.dart` | plugin init + tap wiring | exists — extended for background-response registration (VC-06-D9 wiring assert) |
| `test/core/bridge/go_bridge_client_test.dart` (`ONE_TO_ONE_TESTS`) | cmd-map pins | exists — extended (VC-06-D2) |
| `test/core/bridge/p2p_bridge_client_test.dart` (`ONE_TO_ONE_TESTS`) | bridge payloads + capability list | exists — extended; **any pin of the exact default capabilities list must be migrated** (additive `call_invite_v1`) (VC-06-D1) |
| `test/core/services/android_build_configuration_test.dart`, `share_intent_android_test.dart`, `main_activity_onnewintent_pin_test.dart` | platform-config pin style | exist — style precedent for VC-06-D14; onNewIntent pin is a sentinel (answer tap relies on it) |
| `go-relay-server/push_payload_closure_test.go` (`TestRelayNotificationClosure_*`), `push_token_registration_test.go`, `protocol_contract_test.go`, `forbidden_field_classifier_test.go`, `metrics_test.go` | relay push/action/metrics contract | exist — sentinels; classifier fixture extended (VC-06-R7) |
| `test/core/services/incoming_message_router_test.dart::routes unknown types…` | old-app forward-compat | exists — sentinel (VC-06 adds no router case; ring is push-driven, live offers are VC-05's) |
| MISSING coverage | everything call-push/ring/FGS-related | the RED catalog below |

Already in curated family arrays? `go_bridge_client_test.dart`, `p2p_bridge_client_test.dart`, `p2p_service_impl_test.dart`, `incoming_message_router_test.dart` are in `ONE_TO_ONE_TESTS` (`scripts/run_test_gates.sh:21`). New host tests auto-glob (below); nothing new is added to curated arrays. **Family lock (L5):** NO new test-family array this epic — any headline host-tier call test that needs curation appends to `ONE_TO_ONE_TESTS`; heavy two-party e2e, if it ever needs direct family registration, goes to `NIGHTLY_ONLY_TESTS` (`run_test_gates.sh:556`); here the caller harness classifies via the existing `*_proof_test.dart` manual device-proof branch (`run_test_gates.sh:1036`) and the orchestrator via discovery, so neither array grows.

---

## Decision Record — ring first, node on answer (required by brief)

The FCM headless handler **never starts the Go node** today (verified: `background_message_handler.dart` reads the encrypted SQLCipher identity DB directly for display eligibility, `:815-859`, precisely to avoid a node start). VC-06 keeps that invariant: **the ring UI is drawn purely from the push payload; the node starts on answer (or bounded, on decline).** Justification:
1. **Latency:** FDC-S1 RESULTS §3.2.1 measured Android (Pixel 6) `node:start` return at **median 1158 ms / p90 1200 ms** (max 1284) and relay-ready at **1364/1564 ms**. The ring must land inside the pre-committed 3.0 s p95 budget (below), and push receipt→intent-post must stay a payload-only fast path; serializing a ~1.2–1.5 s node start before ringing would visibly delay or lose rings. Conversely 1.2–1.5 s fits entirely inside the human answer reaction time — started at answer-tap, the node is ready before or roughly as the callee's `call_answer` flow needs it. **≈1.2–1.5 s is therefore an answer-readiness cost (inside the 5.0 s p95 budget), not a ring-path cost.**
2. **Correctness:** starting the node in the headless isolate races the activity launch's own node start (Go rejects concurrent starts — `libp2p_refactor_contract_test.go::TestStartRejectsConcurrentStartWhileHostCreationInProgress` pins it) and burns background-execution budget while the user hasn't consented to a call.
3. **Consequence:** the killed-callee cannot receive the live `call_offer` (fast-path-only, nothing inboxed). The offer travels **inside the push** (encrypted envelope, ciphertext-only-push precedent `inbox.go:414` `addChatEncryptedPushData`) when it fits the 4000/3800-byte budgets; otherwise `offer_omitted` + the caller's 5 s re-offer cadence converges after node start.

## Pre-Committed Latency Budgets  (pass/fail numbers — fixed BEFORE first measurement)

These are the story's own metric gates (VC-00 metrics row). They are **pre-committed**: revisable only via a recorded decision row in Planning Progress with a stated reason, never by execution-time convenience, and never loosened to match "whatever happened".

| Metric | Definition | Budget | Measured how |
|---|---|---|---|
| Ring latency | caller push send (`CALL_PUSH_REQUESTED.sentAtMs`) → full-screen intent posted (`CALL_RING_SHOWN`) | **≤ 3.0 s p95** on the canonical USB Pixel 6 over **10 trials** (killed scenario; backgrounded recorded alongside) | E1 runsheet, 10 `ring_killed` runs |
| Answer readiness | Answer tap (`CALL_ANSWER_TAPPED`) → ICE connected (VC-05 `CALL_CONNECTED`) | **≤ 5.0 s p95** on the same rig over **10 trials** | same runs, same logcat deltas |
| Orchestrator ring poll | hard upper bound per run | **hard FAIL at 20 s** — an eventually-delivered ring is a FAILED run, not a slow pass | orchestrator constant, all `ring_*` scenarios |

Budget breach (p95 over ceiling, or any single ring-poll hard-fail in the 10-trial set) = **STOP**: file a Known-Failure Interpretation row and investigate FCM priority/Doze demotion before claiming closure — never record-and-pass. First measurements may TIGHTEN these numbers; they never set or loosen them.

---

## RED Test Catalog  (INV-RED-FIRST holds PER SLICE — each row is authored and shown RED before its own slice's production code, per the Step-By-Step slices A–E; do not author the whole catalog up front)

> New-feature RED form: where a seam does not exist on HEAD, the test fails to compile/load or the relay answers `Unknown action` — each row states which. Relay tests are named `TestRelayNotificationClosure_CallPush*` **deliberately**: they ride the pinned `run_relay_notification_go_gate` regex `^TestRelayNotificationClosure_` (`scripts/run_test_gates.sh:862`, wired into the `1to1` and `groups` gates) with zero gate-script change, plus the full `run_relay_all_go_gate`.
> Discriminator note: ring-vs-fallback share a "notification shown" result — every ring assertion discriminates on **channel id `mknoon_calls` + `fullScreenIntent:true` + `CALL_RING_SHOWN` flow event, AND NOT the `mknoon_messages` channel**.

**Relay (new `go-relay-server/call_push_test.go`, real in-process stores + captured-messaging fake per `reaction_push_test.go` conventions):**

1. `call_push_test.go::TestRelayNotificationClosure_CallPushSendsHighPriorityDataOnlyMessage` — Tier: relay Go host. Setup: register android token with `call_invite_v1`; issue `call_push_request{to, call_id, sent_at_ms, envelope(small)}` over the inbox stream. RED on HEAD because: switch default answers `{"status":"ERROR","error":"Unknown action: call_push_request"}` (`inbox.go:2277`). GREEN asserts: reply `OK`; captured message has `Notification == nil` (data-only), `Android.Priority == "high"`, `Data == {type:call_invite, call_id, caller_id:<authenticated stream peer>, sent_at_ms, envelope}`, provider budgets respected; `relay_call_push_total{result="success"}` incremented. Mutation: add a Notification block / drop the Android priority → RED. Discriminator: asserts `caller_id` equals the **stream-authenticated** peer, not a request field (spoof-proof).
2. `call_push_test.go::TestRelayNotificationClosure_CallPushRequiresCallCapability` — relay Go host. Token registered WITHOUT `call_invite_v1`. RED: unknown action on HEAD. GREEN: no send; `result="call_incapable"`; reply still `OK` (caller falls back to live-only ring). Mutation: remove the `hasCapability` gate → send happens → RED.
3. `call_push_test.go::TestRelayNotificationClosure_CallPushRateLimited` — relay Go host. 4 requests same caller→callee within the window. RED: unknown action. GREEN: 3 sends then `result="call_rate_limited"`, no 4th send; a different caller→same callee still sends. Mutation: delete the limiter check → 4 sends → RED.
4. `call_push_test.go::TestRelayNotificationClosure_CallPushOversizedEnvelopeStripped` — relay Go host. Envelope > `maxPushDataBytes`. RED: unknown action. GREEN: push sent WITHOUT `envelope`, `offer_omitted=="1"`, fits `maxProviderPayloadBytes`; `result="success_offer_omitted"`. Mutation: remove the budget check → oversized data map → RED.
5. `call_push_test.go::TestRelayNotificationClosure_CallPushKillSwitch` — relay Go host. `SetCallInvitePushEnabled(false)` (env `RELAY_CALL_PUSH_ENABLED=false` path). RED: unknown action. GREEN: no send, `result="call_disabled"`, reply `OK` (VC-00 rule 3 kill-switch, test-locked both polarities: re-enable → sends). Mutation: ignore the flag → RED.
6. `call_push_test.go::TestRelayNotificationClosure_CallPushIosTokenDeferred` — relay Go host. Token platform `ios`. RED: unknown action. GREEN: no FCM send, `result="call_ios_deferred"` (VC-07 owns the APNs leg). Mutation: send the android-shaped payload to ios → RED.
7. `forbidden_field_classifier_test.go` (extend committed fixture) `::TestForbiddenFieldClassifier_MessagePushesDoNotExposePreviewCanaries` — relay Go host. RED on HEAD because: the new call push data keys (`call_id`,`caller_id`,`sent_at_ms`,`envelope`,`offer_omitted`) are absent from the committed fixture — adding the call push message to the fixture WITHOUT classifier support fails the sweep. GREEN: call data keys classified as non-preview-bearing (envelope is ciphertext — same class as `addChatEncryptedPushData`). Mutation: add a plaintext caller display-name field to the push → classifier trips → RED.

**Go client/bridge (new files; pinned synthetic-path gates — see registration column):**

8. `go-mknoon/node/call_push_request_test.go::TestCallPushRequest_FramesActionAndParsesReplies` — Go host (table test, in-mem stream pair). RED: `RelayCallPushRequest` undefined → compile fail. GREEN: frames `{action:"call_push_request", to, callId, sentAtMs, envelope}`; `OK`→success; `Unknown action`→graceful `unsupported=true` (NET-REL-07); malformed→error, never panic. Mutation: map unknown-action to hard error → RED.
9. `go-mknoon/bridge/call_push_request_bridge_test.go::TestCallPushRequestBridge_ContractShape` — Go host. RED: exported handler undefined → compile fail. GREEN: `InboxRegisterToken`-shaped contract — invalid JSON → `INVALID_INPUT`, nil node → `NOT_INITIALIZED`, panic recovered → `INTERNAL_ERROR`. Mutation: drop the recover → RED.

**Dart host:**

10. `test/core/bridge/p2p_bridge_client_test.dart::VC-06-D1 callP2PCallPushRequest builds relay:call_push payload and register_token advertises call_invite_v1` — unit host. RED: method/constant undefined → compile fail; capability-list pin (if present) still shows the old list. GREEN: `{'cmd':'relay:call_push', to, callId, sentAtMs, envelope}`; default capabilities contain `direct_reaction_v1` AND `call_invite_v1`. Mutation: drop `call_invite_v1` from the default list → RED. Registration: file already in `ONE_TO_ONE_TESTS`.
11. `test/core/bridge/go_bridge_client_test.dart::VC-06-D2 relay:call_push maps to relayCallPushRequest` — unit host (cmd-map pin, `:212` pattern). RED: cmd absent from map. GREEN: pin present. Mutation: rename the native method → RED. Registration: already in `ONE_TO_ONE_TESTS`.
12. `test/core/services/p2p_service_impl_call_push_test.dart::VC-06-D3 requestCallRingPush is move-gated first-line, emits CALL_PUSH_REQUESTED, never throws` — unit host. RED: method undefined. GREEN: gate-denied → no bridge call + `false`; gate-allowed → bridge called once + flow event `CALL_PUSH_REQUESTED{callId,sentAtMs}`; bridge throw → `false`, no exception. Mutation: move the gate below the bridge call → gate-denied test sees a bridge call → RED. Registration: AUTO (`test/core/services/` glob → `core-host-all`; classify_path core branch).
13. `test/core/notifications/notification_route_target_call_test.dart::VC-06-D4 call_invite parses to a callInvite target` — unit host. RED: no `call_invite` case → `fromRemoteMessageData` returns null (`notification_route_target.dart:157-263`). GREEN: kind `callInvite`, `callId`/`callerId` extracted, envelope passthrough; missing `call_id` → null (malformed rejected). Mutation: delete the case → RED. Registration: AUTO (`test/core/notifications/`).
14. `test/features/push/application/background_message_handler_test.dart::VC-06-D5 data-only call_invite rings full-screen without starting the node` — unit host (fake FLN plugin + fake node-start probe, `remote_message_fixtures.dart` style). RED: handler drops the message at the `:400` gate (`fromRemoteMessageData` null) — no notification shown. GREEN: notification on channel `mknoon_calls` with `fullScreenIntent:true`, `category: call`, Answer+Decline actions, deterministic id from `callId`; flow event `CALL_RING_SHOWN{callId, ringLatencyMs}`; **node-start probe never invoked**; and NOT the `mknoon_messages` channel (discriminator). Mutation: move the call branch below the fallback gate → dropped again → RED. Registration: AUTO (`test/features/push/application/`).
15. `…background_message_handler_test.dart::VC-06-D6 duplicate call_invite pushes ring once` — unit host. RED: no dedupe seam exists. GREEN: same `callId` twice → one `show` (deterministic id; second call replaces, no second `CALL_RING_SHOWN` sound re-trigger flag); ALSO asserts the shown id equals `callNotificationId(callId)` — the shared helper, not an inline hash (three isolates must agree; see scope pin). Mutation: randomize the notification id / inline a different hash → two shows or id mismatch → RED. Registration: AUTO.
16. `test/features/call/application/background_call_ring_use_case_test.dart::VC-06-D7 ring arms a missed-call schedule cancelled by answer/decline` — unit host (fake FLN + fake clock). RED: use case does not exist → compile fail. GREEN: ring → `zonedSchedule(missed-call, min(45s, TTL remaining), inexactAllowWhileIdle)` (TTL = VC-04 `kCallOfferTtl` = 45000 ms, lock L1); answer or decline → ring cancelled AND schedule cancelled (destructive-action: asserts what is removed AND that the ongoing-call channel/notification is untouched). Mutation: drop the cancel on answer → schedule survives → RED. Registration: AUTO (`test/features/call/application/`).
17. `…background_call_ring_use_case_test.dart::VC-06-D8 stale push (TTL expired) posts missed-call, never rings` — unit host. RED: no TTL check exists. GREEN: `sent_at_ms` older than VC-04 TTL → NO `mknoon_calls` ring, missed-call notification posted immediately (consistent with VC-04 expiry semantics); no `CALL_RING_SHOWN`. Mutation: drop the stale check → ring shows → RED. Registration: AUTO.
18. `test/features/call/application/call_decline_background_handler_test.dart::VC-06-D9 decline cancels ring, starts node bounded, sends call_decline fast-path, persists nothing` — unit host (fake node/bridge + fake message repo). RED: handler + background-response wiring do not exist (`flutter_notification_service.dart:59` wires foreground only). GREEN: decline action id → ring+schedule cancelled; node start invoked once with a ≤10 s bound; `call_decline` sent via the fast-path seam (`sendMessageWithReply` fake) with the VC-04 envelope; **messageRepo untouched** (fast-path-only invariant, rule 5); node-start failure → still cancelled, no throw, no send. Companion assert in `flutter_notification_service_test.dart`: `initialize` now wires `onDidReceiveBackgroundNotificationResponse` to the entry-point. Mutation: persist the decline through messageRepo → RED. Registration: AUTO.
19. `test/features/push/application/handle_foreground_remote_message_use_case_test.dart::VC-06-D10 foreground call_invite push is a no-op` — unit host. RED: falls into existing generic handling (or new branch absent). GREEN: no notification, no route — the live `call_offer` via the router (VC-05) is authoritative in foreground. Mutation: remove the short-circuit → notification appears → RED. Registration: AUTO.
20. `test/core/notifications/local_notification_support_test.dart::VC-06-D11 mknoon_calls channel is max-importance ringtone` — unit host. RED: channel constant absent. GREEN: `mknoon_calls` created by `ensureMknoonNotificationChannel` with `Importance.max`, ringtone audio-attributes usage, vibration on; existing two channels unchanged (sentinel co-assert). Mutation: downgrade to `Importance.high` → RED. Registration: AUTO.
21. `test/core/notifications/notification_route_contract_matrix_test.dart::VC-06-D12 callInvite tap routes to IncomingCallScreen with payload` — widget/host (route-contract matrix pattern). RED: no `callInvite` route case in `_handleNotificationRouteTarget`. GREEN: cold-launch payload with envelope → IncomingCallScreen receives `{callId, callerId, envelope}`; a dedicated case round-trips the target through `toPayload()`/`fromPayload()` (`notification_route_target.dart:68,:87`) and asserts the envelope string survives **byte-identical** (an executor dropping the envelope from the payload must fail here, not silently degrade to re-offer); `offer_omitted` payload → screen mounts in "connecting" state; `CALL_ANSWER_TAPPED{callId}` flow event emitted. Mutation: route to conversation instead / strip the envelope in toPayload → RED. Registration: AUTO.
22. `test/features/call/application/start_call_ring_loop_test.dart::VC-06-D13 caller fires call_push_request in parallel and re-offers every 5s while ringing` — unit host (fake clock; extends VC-05's StartCallUseCase tests). RED: neither behavior exists in VC-05's use case. GREEN: `requestCallRingPush` fired concurrently with (not after) the first `call_offer` fast-path send (order-independent start, both begun before either completes — fake latching); `call_offer` re-sent at 5 s cadence with the SAME `callId` until answer/decline/TTL; cadence stops on TTL (VC-04) and on `call_answer`. Mutation: serialize push-request after offer ack → latch shows sequential → RED. Registration: AUTO.
23. `test/core/services/call_android_platform_config_test.dart::VC-06-D14 manifest + MainActivity declare the call surfaces` — platform-config pin (file-reading, `share_intent_android_test.dart:9-90` style). RED: none of the strings exist in the manifest/Kotlin. GREEN: manifest has `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE_PHONE_CALL`, `FOREGROUND_SERVICE_MICROPHONE`, `RECEIVE_BOOT_COMPLETED`, `<service .CallForegroundService … foregroundServiceType="phoneCall|microphone" exported=false>`, both FLN scheduled receivers; `MainActivity.kt` registers `mknoon/call_foreground` and exposes `canUseFullScreenIntent`; existing `dataSync` service untouched (sentinel co-assert). Mutation: drop `microphone` from the FGS type → RED. Registration: AUTO (`test/core/services/`).
24. `test/features/call/application/call_foreground_keep_alive_test.dart::VC-06-D15 hold-counted FGS driver acquires once, releases at zero, no-ops without plugin` — unit host (mirrors `migration_transfer_keep_alive` tests). RED: driver absent. GREEN: two acquires → one platform `start`; releases → `stop` only at zero; `MissingPluginException` → silent no-op; release without acquire → no `stop`. Mutation: start on every acquire → RED. Registration: AUTO.

**Device-proof (rule 1; PROD-CRITICAL):**

25. `integration_test/call_ring_caller_proof_test.dart` (`@Tags(['device'])`) + orchestrator scenario `ring_killed` in NEW `integration_test/scripts/run_call_device_real.dart` — Tier: device-proof, **PROD-CRITICAL** (the only end-to-end proof of the push→ring→answer→audio wire leg; host coverage is NOT sufficient on its own). Setup: callee = USB device, app force-stopped; caller = emulator running the proof harness (real GoBridgeClient, deployed relay). RED on HEAD because: the deployed relay answers `Unknown action` and the callee handler drops the type — orchestrator's ring poll (hard FAIL at 20 s, pre-committed) times out. GREEN asserts: `adb logcat` shows `CALL_RING_SHOWN` on the callee within the ring poll; `dumpsys notification` shows the `mknoon_calls` channel + fullScreenIntent; answer is a **real tap on the notification's Answer action via uiautomator as the primary path** (the PendingIntent — flags, mutability, API 34+ payload marshaling — is the seam most likely broken while a replayed intent works); `adb shell am start` intent-replay is the FALLBACK only, and when used, one manual Answer tap on `ring_killed` becomes a REQUIRED runsheet checkbox ("manual Answer tap cold-launched into call: yes/no") before closure; tap cold-launches into IncomingCallScreen; `CALL_CONNECTED` observed in callee logcat; two-way audio is asserted by the CALLER-leg harness (VC-05's in-test audio assertions run under `flutter test` on the emulator; the callee leg, outside `flutter test`, is `CALL_CONNECTED`-only unless VC-05 exposes an audio flow-event marker — resolved at execution against VC-05's landed tree and recorded in the runsheet); FGS visible in `dumpsys activity services` (`CallForegroundService`, type phoneCall|microphone); latency stats per Pre-Committed Latency Budgets: **10 trials**, record min/median/p95 (FDC-S1 RESULTS conventions), pass = ring ≤ 3.0 s p95 AND answer-readiness ≤ 5.0 s p95. Any `holepunch:attempt` events observed are RECORDED, never asserted or failed on (lock L7 — HEAD always has EnableHolePunching on; punch-outcome assertions belong to VC-02 only). Mutation: relay kill-switch off (`RELAY_CALL_PUSH_ENABLED=false` on the box) → device never rings → RED (also live-proves R5).
26. Orchestrator scenario `ring_backgrounded` (same runner/harness) — device-proof. Setup: callee app backgrounded (home key), node had been running. RED: same as above. GREEN: exactly ONE ring (push-ring and any live-offer ring deduped by `callId` — via `callNotificationId`), answer resumes (warm path, no cold start) into the call; audio connects (caller-leg assertion, as E1); same 10-trial latency recording and 20 s ring-poll hard-fail.
27. Orchestrator scenario `ring_timeout` (same runner/harness) — device-proof; the real-device proof of the receiver-based missed-call durability (the fake-FLN D7 cannot prove `zonedSchedule` + manifest receivers survive process death). Setup: callee killed (`am force-stop`), caller rings, NOBODY answers. RED on HEAD: same as E1. GREEN asserts via `dumpsys notification --noredact` after the timeout window: the `mknoon_calls` ring notification is GONE, the missed-call notification is PRESENT, and the app process was never launched (`pidof com.mknoon.app` empty throughout); caller side sees TTL expiry per VC-04. Mutation: drop the manifest `ScheduledNotificationReceiver` → missed-call never posts → RED.

---

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| VC-06-R1 data-only high-priority call push | relay push construction | relay Go host | `go-relay-server/call_push_test.go::TestRelayNotificationClosure_CallPushSendsHighPriorityDataOnlyMessage` | `Unknown action: call_push_request` (inbox.go:2277) | add Notification block / drop priority | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_' -count=1)` | name matches pinned `run_relay_notification_go_gate` regex (run_test_gates.sh:862) + relay-all — verify by running the gate |
| VC-06-R2 capability gate | strict opt-in | relay Go host | `call_push_test.go::…CallPushRequiresCallCapability` | unknown action | remove hasCapability gate | same relay gate cmd | same (regex-pinned) |
| VC-06-R3 rate limit | per-pair abuse bound | relay Go host | `call_push_test.go::…CallPushRateLimited` | unknown action | delete limiter | same relay gate cmd | same |
| VC-06-R4 oversized envelope stripped | budget fallback | relay Go host | `call_push_test.go::…CallPushOversizedEnvelopeStripped` | unknown action | remove budget check | same relay gate cmd | same |
| VC-06-R5 kill-switch | rule-3 flag, both polarities | relay Go host | `call_push_test.go::…CallPushKillSwitch` | unknown action | ignore flag | same relay gate cmd | same |
| VC-06-R6 iOS deferred | VC-07 boundary | relay Go host | `call_push_test.go::…CallPushIosTokenDeferred` | unknown action | send android payload to ios | same relay gate cmd | same |
| VC-06-R7 push-field hygiene | no preview canaries | relay Go host | `forbidden_field_classifier_test.go::…MessagePushesDoNotExposePreviewCanaries` (extended fixture) | call keys absent from fixture/classifier | add plaintext caller name field | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | existing file, relay-all gate |
| VC-06-G1 node client action | frame + reply parse + old-relay skip | Go host | `go-mknoon/node/call_push_request_test.go::TestCallPushRequest_FramesActionAndParsesReplies` | symbol undefined (compile) | unknown-action → hard error | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CallPushRequest' -count=1)` | NEW synthetic path in `run_host_test_gates.sh` (`GO_NODE_CALLPUSH_TEST` + RUN `'CallPushRequest'`, copy :144-184 pattern + print/run branches) — verify via `./scripts/run_host_test_gates.sh host-all --list` |
| VC-06-G2 bridge handler | okJSON/errJSON contract | Go host | `go-mknoon/bridge/call_push_request_bridge_test.go::TestCallPushRequestBridge_ContractShape` | symbol undefined (compile) | drop panic recover | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'CallPushRequestBridge' -count=1)` | NEW synthetic path (`GO_BRIDGE_CALLPUSH_TEST` + RUN `'CallPushRequestBridge'`) — same verification |
| VC-06-D1 Dart bridge payload + capability | wire shape | unit host | `test/core/bridge/p2p_bridge_client_test.dart::VC-06-D1…` | method/constant undefined | drop `call_invite_v1` from defaults | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` array |
| VC-06-D2 cmd-map pin | dispatch | unit host | `test/core/bridge/go_bridge_client_test.dart::VC-06-D2…` | cmd absent from map | rename native method | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS` |
| VC-06-D3 move gate + flow event | rule-4 primitive | unit host | `test/core/services/p2p_service_impl_call_push_test.dart::VC-06-D3…` | method undefined | gate below bridge call | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/services glob; classify_path core branch) |
| VC-06-D4 route-target parse | payload model | unit host | `test/core/notifications/notification_route_target_call_test.dart::VC-06-D4…` | no call_invite case → null | delete case | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/notifications) |
| VC-06-D5 killed-path ring, no node | ring seam + discriminator | unit host | `test/features/push/application/background_message_handler_test.dart::VC-06-D5…` | dropped at fallback gate :400 | move branch below gate | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (feature glob) |
| VC-06-D6 dedupe by callId | idempotency | unit host | `…background_message_handler_test.dart::VC-06-D6…` | no dedupe seam | randomize notification id | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-D7 timeout→missed-call; cancel on answer/decline | destructive-action pair | unit host | `test/features/call/application/background_call_ring_use_case_test.dart::VC-06-D7…` | use case absent (compile) | drop cancel-on-answer | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-D8 stale push never rings | VC-04 TTL consistency | unit host | `…background_call_ring_use_case_test.dart::VC-06-D8…` | no TTL check | drop stale check | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-D9 decline: bounded node start + fast-path call_decline, no persistence | rule-5 invariant | unit host | `test/features/call/application/call_decline_background_handler_test.dart::VC-06-D9…` | handler + background-response wiring absent | persist via messageRepo | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-D10 foreground push no-op | live-offer authority | unit host | `test/features/push/application/handle_foreground_remote_message_use_case_test.dart::VC-06-D10…` | generic handling applies | remove short-circuit | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-D11 mknoon_calls channel | ring audio surface | unit host | `test/core/notifications/local_notification_support_test.dart::VC-06-D11…` | channel constant absent | downgrade importance | `./scripts/run_host_test_gates.sh core-host-all` | AUTO |
| VC-06-D12 answer routing + payload | cold-launch reconstruction | widget host | `test/core/notifications/notification_route_contract_matrix_test.dart::VC-06-D12…` | no callInvite route case | route to conversation | `./scripts/run_host_test_gates.sh core-host-all` | AUTO |
| VC-06-D13 caller parallel push + 5s re-offer | convergence for offer_omitted | unit host | `test/features/call/application/start_call_ring_loop_test.dart::VC-06-D13…` | behaviors absent in VC-05 use case | serialize push after offer | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-D14 platform-config pins | manifest/Kotlin drift lock | platform-pin host | `test/core/services/call_android_platform_config_test.dart::VC-06-D14…` | strings absent from manifest/Kotlin | drop `microphone` from FGS type | `./scripts/run_host_test_gates.sh core-host-all` | AUTO |
| VC-06-D15 FGS Dart driver | hold-count + degrade | unit host | `test/features/call/application/call_foreground_keep_alive_test.dart::VC-06-D15…` | driver absent (compile) | start on every acquire | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO |
| VC-06-E1 killed callee rings + answers into audio (**PROD-CRITICAL**) | OS boundary, real relay+FCM, 2 devices; ring ≤ 3.0 s p95 / answer ≤ 5.0 s p95 over 10 trials (pre-committed); ring poll hard-FAILs at 20 s; primary answer = real uiautomator tap on the Answer action | device-proof | `integration_test/call_ring_caller_proof_test.dart` + `run_call_device_real.dart --scenario ring_killed` | relay unknown action + client drops type → 20 s ring poll hard-fails | box-side kill-switch off → no ring | `dart integration_test/scripts/run_call_device_real.dart --scenario ring_killed -d emulator-5554,21071FDF600CSC` (after redeploy gate; ×10 for the latency stats) | proof harness: auto `*_proof_test.dart` branch (run_test_gates.sh:1036-1039) + NEW `record "1to1" … "test"` case in `check_reliability_simulation_discovery.sh`; orchestrator: NEW `record "1to1" … "runner"` case + `expand_call_device_real` dispatch (`--scenario all --list-scenarios` contract, lock L5 — shared epic orchestrator, no new family array) — verify via `./scripts/check_reliability_simulation_discovery.sh` + `/sims 1to1 --list` slot |
| VC-06-E2 backgrounded callee: exactly one ring, warm answer | dedupe at OS boundary; same budgets/poll bound as E1 | device-proof | same runner `--scenario ring_backgrounded` | same as E1 | disable deterministic-id dedupe → double ring | `dart integration_test/scripts/run_call_device_real.dart --scenario ring_backgrounded -d emulator-5554,21071FDF600CSC` (×10) | same registration as E1 (second listed scenario) |
| VC-06-E3 timeout → missed-call durable across process death | receiver-based schedule on the real OS, app never launched | device-proof | same runner `--scenario ring_timeout` | same as E1 (no ring on HEAD) | drop `ScheduledNotificationReceiver` from manifest → missed-call never posts | `dart integration_test/scripts/run_call_device_real.dart --scenario ring_timeout -d emulator-5554,21071FDF600CSC` | same registration as E1 (third listed scenario, in `--scenario all`) |
| PRESERVE P1 existing push types unaffected | sentinel | unit host | `background_message_handler_test.dart` + `background_push_notification_fallback_test.dart` (existing cases) | n/a (green) | call branch swallowing new_message → existing cases RED | `./scripts/run_host_test_gates.sh feature-host-all` | existing AUTO |
| PRESERVE P2 relay push/action contract | sentinel | relay Go host | `push_payload_closure_test.go` + `push_token_registration_test.go` + `protocol_contract_test.go` (existing) | n/a (green) | n/a | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | existing relay-all gate |
| PRESERVE P3 migration keep-alive FGS untouched | sentinel | unit host | `migration_transfer_keep_alive_test.dart` + D14's dataSync co-assert | n/a (green) | n/a | `./scripts/run_host_test_gates.sh feature-host-all` | existing AUTO |
| PRESERVE P4 router forward-compat + onNewIntent pin | sentinel | unit host | `incoming_message_router_test.dart::routes unknown types…` + `main_activity_onnewintent_pin_test.dart` | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` + `core-host-all` | existing array/AUTO |
| Regression floor | no 1:1/groups/host breakage | gate | (all suites) | n/a | n/a | `./scripts/run_test_gates.sh 1to1` · `groups` · `feature-host-all` · `core-host-all` | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the ringing state lives OUTSIDE the process by construction (posted notification + FLN-scheduled missed-call survive process death; the answer payload reconstructs the call context on a cold mount). Locked by VC-06-D12 (cold-launch payload → screen state, including the degraded `offer_omitted` reconstruction) and VC-06-E1 (real killed-process reconstruction). The scheduled missed-call surviving process death is receiver-based (manifest receivers pinned by D14) and proven for real by the named scenario VC-06-E3 (`ring_timeout` — own matrix row, gate command, and Done Criteria entry).
- **Sibling-surface consistency:** the new capability gate (`call_invite_v1`) parallels `direct_reaction_v1` — both live in the same default list; D1 asserts BOTH present (no regression of the reaction capability). Ring surfaces: killed (D5/E1), backgrounded (E2), foreground (D10 — deliberately silent, live offer rings via VC-05; asymmetry is deliberate AND test-locked). iOS surface deliberately deferred → R6 test-locks the deferral instead of leaving it silent.
- **Destructive-action side-effects:** answer/decline/timeout each assert what is REMOVED (ring notification, missed-call schedule) and what is PRESERVED (ongoing-call notification/channel, other channels, messageRepo untouched) — VC-06-D7/D8/D9. Decline reuses the single cancel path of the ring use case (no divergent copy).
- **Invariant re-verification under new transitions:** answer while the decline background isolate could race a node start → Go single-start invariant already pinned (`TestStartRejectsConcurrentStartWhileHostCreationInProgress`, cited sentinel; D9 additionally asserts exactly one bounded start on the decline path). Post-answer, the fast-path-only invariant is re-verified (D9: no repo rows; E1: `adb` check that no phantom "sending…" chat rows appear). The FGS release-at-zero transition re-verifies hold counting (D15).

---

## Invariants (locked by tests)

- INV-1 **Ring without node:** the killed-path ring never starts the Go node → VC-06-D5 (node-start probe = 0).
- INV-2 **Strict opt-in push:** no `call_invite_v1` capability ⇒ no push; kill-switch off ⇒ no push; never fail-open → VC-06-R2/R5.
- INV-3 **Data-only high-priority:** call pushes carry no Notification block and Android priority high → VC-06-R1.
- INV-4 **Fast-path-only holds under VC-06:** no call push/decline machinery writes messageRepo or the durable inbox → VC-06-D9 (+ E1 device check).
- INV-5 **One ring per callId:** duplicate pushes / push+live overlap ring once, all id computation through the single `callNotificationId` helper → VC-06-D6, E2.
- INV-6 **TTL consistency:** stale invites never ring; timeout always resolves to a missed-call (ring timeout = min(45 s, `kCallOfferTtl` remaining), lock L1) → VC-06-D7/D8, E3 (real-device durability).
- INV-7 **Spoof-proof caller identity:** `caller_id` in the push = stream-authenticated peer → VC-06-R1.
- INV-8 **Old-relay grace:** `call_push_request` against an old relay degrades to a silent skip (live-only ring) → VC-06-G1.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan

0. **Preconditions (stop-ifs).** VC-05 landed and its home gates green (this plan edits its StartCallUseCase, IncomingCallScreen entry, in-call controller); VC-04 types available. Snapshot `git status --short` (preserve the pre-existing dirty tree — do not revert/absorb/reformat it) and capture green baselines: `./scripts/run_test_gates.sh 1to1`, `groups`, `./scripts/run_host_test_gates.sh feature-host-all`, `core-host-all`, `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)`. Verify merged targetSdk: `cd android && ./gradlew :app:processDebugManifest && grep targetSdkVersion app/build/intermediates/merged_manifests/debug/AndroidManifest.xml` — if ≥34, the `canUseFullScreenIntent` degrade path (D5/D14) is mandatory, not optional. Re-verify every cited line anchor before editing (they drift). Stop-if: VC-07 landed a conflicting push-type switch on the relay seam → rebase per the VC-00 collision map before continuing.
0.5 **Feasibility spike (payoff de-risk — NO production code).** The whole callee design (ring from payload, no node) hinges on one external property: a high-priority data-only FCM actually waking the force-stopped debug app on the canonical Pixel 6 under its battery manager. Prove it FIRST: send one high-priority data-only message to the device's existing registered FCM token (Firebase console or `curl` to the FCM v1 API), app force-stopped, and confirm the existing headless handler wakes (temporary logcat marker at the top of `firebaseMessagingBackgroundHandler`, before the fallback gate — removed after the spike). STOP/redesign (e.g. notification-block fallback) if delivery does not wake the isolate within the pre-committed ring budget. Record the observed wake latency in Planning/Execution Progress.
1. **Up-front skeleton + registrations only (not the full RED catalog).** Land the E1–E3 orchestrator skeleton (`run_call_device_real.dart` with `--scenario all --list-scenarios`, lock L5) + caller-harness stub + discovery cases + the two Go synthetic gate paths, so `completeness-check` + discovery are green from the start. Behavior tests are authored per slice below (INV-RED-FIRST holds WITHIN each slice) — do NOT author all 27 REDs up front: the Dart rows encode the relay push-data contract, and a contract revision at the relay slice must not invalidate a dozen pre-authored REDs with no checkpoint in between.
2. **Slice A — relay.** RED: author R1–R7 only; run the relay matrix commands; confirm each fails as documented (unknown action / fixture). GREEN: `go-relay-server/call_push.go`: named handler `handleCallPushRequest` + switch case (thread through `HandleInboxStream(s, inbox, groupInbox, h, presence)` signature, `inbox.go:2033`); `PushService.SendCallInviteNotification` (capability gate, limiter, budgets, data-only builder); `SetCallInvitePushEnabled` + env load in `main.go` (pattern `:102`); `relay_call_push_total` in `metrics.go`; classifier fixture. Gate: full relay suite. **Checkpoint: the push-data contract `{type:call_invite, call_id, caller_id, sent_at_ms, envelope?|offer_omitted}` is now frozen against the real FCM Admin SDK constraints — later slices consume it as pinned.** Stop-if: any existing `TestRelayNotificationClosure_*` regresses → the seam is wrong, replan (do not weaken sentinels).
3. **Slice B — Go client/bridge.** RED: author G1–G2; confirm compile-fail. GREEN: `node/call_push_request.go` (stream to relay, additive-action parse; `unsupported` on unknown action); `bridge.go` exported handler. Gate: the two focused Go commands. Rebuild note: gomobile framework rebuild required before device runs (same deferral convention as presence_set, `go_bridge_client.dart:126-133` comments).
4. **Slice C — Dart caller.** RED: author D1–D3 + D13; confirm each fails as documented. GREEN: cmd map + `callP2PCallPushRequest` + capability constant; `P2PServiceImpl.requestCallRingPush` (gate first-line, flow event, never-throws); StartCallUseCase ring loop (parallel push + 5 s re-offer, TTL-bounded). Gate: `1to1` + `core-host-all` focused runs.
5. **Slice D — Dart callee.** RED: author D4–D12 + D15; confirm each fails as documented (gate drop / compile / missing case). GREEN: route-target kind + `toPayload`/`fromPayload` case; `mknoon_calls` channel + `callNotificationId` helper; early handler branch (desktop exclusion inherited — the registration sits inside `if (!isDesktop)`, `main.dart:366-370`); `background_call_ring_use_case.dart` (stale/dedupe/ring/schedule); background notification-response entry-point + decline handler; foreground no-op; `main.dart` route case → IncomingCallScreen payload entry. Gate: `feature-host-all` + `core-host-all` focused runs.
6. **Slice E — Android platform.** RED: author D14; confirm manifest strings absent. GREEN: manifest permissions/service/receivers; `CallForegroundService.kt`; `mknoon/call_foreground` + `canUseFullScreenIntent` in MainActivity; Dart keep-alive driver; VC-05 in-call controller acquire/release hooks. Stop-if: Robolectric/gradle unit infra fights the new service test → keep the Kotlin behavior companion OPTIONAL-MANUAL (gradlew) and rely on the D14 pin + E1 `dumpsys` proof; do not block the story on gradle plumbing.
7. **Full direct GREEN → preservation → named gates.** Matrix commands, then `1to1`, `groups`, `feature-host-all`, `core-host-all`, `completeness-check`, discovery script. Run every mutation revert listed in the matrix; confirm re-RED.
8. **EC2 redeploy + live verification** (section below; rule 2). One relay change per deploy — do not bundle with VC-03/VC-07 relay work.
9. **Device e2e** (rule 1): `ring_killed` ×10, `ring_backgrounded` ×10, `ring_timeout` ×1; extract ring/answer latency min/median/p95 into `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-06-RESULTS.md` (measurement runsheet, FDC-S1 conventions); apply the Pre-Committed Latency Budgets — p95 breach or any 20 s ring-poll hard-fail = STOP, not record-and-pass.
10. **Gate-doc sync** (rule 6): `run_host_test_gates.sh` gained synthetic paths and discovery gained cases → update `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` together. Refresh arch graph: `./graphify-arch/refresh_arch_graph.sh --incremental`.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| Call push abused as a wake side-channel (spam rings) | R2 (capability), R3 (rate limit), R7 (field hygiene), INV-7 (spoofed caller id) |
| FCM high-priority throttling on repeated pushes (Doze bucket demotion) | R3 caps caller-side volume; E1 runsheet records real delivery latency; caller re-offer cadence is fast-path (not push), so no push storm |
| OEM battery managers delaying data pushes (killed app) | de-risked FIRST by the step-0.5 feasibility spike (one real data-only push must wake the force-stopped app within the ring budget, else STOP/redesign); E1 runs ×10 on the canonical Pixel 6 against the pre-committed p95 budgets; documented in Known-Failure Interpretation |
| Ring shown but offer undeliverable (envelope omitted + caller gone) | D8/D7: TTL-bounded ring always resolves to missed-call; caller TTL expiry (VC-04) symmetric |
| Double ring (push + live offer, backgrounded) | D6 + E2 (deterministic id by callId) |
| Decline isolate racing app-launch node start | Go single-start contract test (cited sentinel) + D9 bounded single start |
| `USE_FULL_SCREEN_INTENT` revoked on API 34+ | D14 pin + `canUseFullScreenIntent` degrade path asserted in D5 variant; E1 dumpsys check |
| FLN scheduled receivers change plugin behavior for existing notifications | P1 sentinels + D11 asserts existing channels unchanged |
| Wake-token gate flips on later and silently blocks call pushes | stance recorded (Accepted Differences): call push is capability-gated, NOT wake-token-gated; a `wakeTokenGateEnforced` flip does not touch the call path (separate seam) — re-check row for that future story |
| Relay redeploy skew (old relay, new client) | G1/INV-8: graceful `unsupported` → live-only ring; additive-action contract (NOTES.md:114-121) |

---

## Device/Relay Proof Profile

**Requires device + deployed relay for closure.** Host tier closes the code contracts; the story's Working Piece is OS-boundary (FCM delivery, full-screen intent, cold launch, FGS) and **cannot** be host-proven. Closure = VC-06-E1 + VC-06-E2 + VC-06-E3 green against the redeployed relay on the canonical rig (E1/E2 with the pre-committed p95 budgets over 10 trials), plus the live push probe in the EC2 section.
Closure scenario: `dart integration_test/scripts/run_call_device_real.dart --scenario all -d emulator-5554,21071FDF600CSC` (listed by `./scripts/check_reliability_simulation_discovery.sh`; visible in the `/sims 1to1 --list` plan — `/sims` runs it, never registers it).
Deferred device work → VC-07 owns all iOS evidence (deferred-not-waived: the orchestrator prints the iOS recipe and exits 0 without claiming proof, per `run_1to1_device_real.dart` conventions).
Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (+ quic-v1 pair, `scripts/run_test_gates.sh:568`).

---

## Execution Environment  (VC-00 rule 1 — restated and binding)

The implementing AI agent runs the full loop end-to-end on a **USB-connected Android device + Android emulator**. iOS simulators/devices are NOT part of this rig (VC-07 owns iOS; deferred-not-waived).

```bash
# 1. Discovery / preflight (canonical pair: caller A = emulator-5554 (AVD mknoon_play_35), callee B = USB Pixel 6 21071FDF600CSC)
adb devices -l
flutter devices --machine
flutter emulators
# unavailable target => "N/A (target unavailable by project policy)" — do not substitute iOS

# 2. Single-device suites (per-file, serial-pinned)
flutter test integration_test/call_ring_caller_proof_test.dart -d emulator-5554 \
  --dart-define=CALLEE_PEER_ID=<peerB> --dart-define=MKNOON_RELAY_ADDRESSES=<default prod pair> \
  --dart-define=FDC_FLOW_LOG=1

# 3. Two-party orchestrator (comma -d list: <callerSerial>,<calleeSerial>)
dart integration_test/scripts/run_call_device_real.dart --list-scenarios
dart integration_test/scripts/run_call_device_real.dart --scenario ring_killed        -d emulator-5554,21071FDF600CSC   # ×10 for latency stats
dart integration_test/scripts/run_call_device_real.dart --scenario ring_backgrounded  -d emulator-5554,21071FDF600CSC   # ×10
dart integration_test/scripts/run_call_device_real.dart --scenario ring_timeout       -d emulator-5554,21071FDF600CSC
```

**Leg placement:** the CALLER leg always runs on the **emulator** (`flutter test --no-pub <harness> -d emulator-5554`, `Process.start('flutter',…)` convention of `run_group_multi_party_device_real.dart:241-253`). The CALLEE leg always runs on the **USB device** — but NOT under `flutter test`: the orchestrator installs the debug APK, registers the push token by launching the app once against the prod relay, then `adb -s 21071FDF600CSC shell am force-stop com.mknoon.app` (killed scenario) or `input keyevent KEYCODE_HOME` (backgrounded), and asserts via `adb logcat` (flow-event markers `CALL_RING_SHOWN`/`CALL_CONNECTED`), `dumpsys notification --noredact` (channel `mknoon_calls`, fullScreenIntent), and `dumpsys activity services com.mknoon.app` (CallForegroundService). Answer path: PRIMARY = a real tap on the notification's Answer action via uiautomator (`adb shell uiautomator` / `input tap` on the resolved action bounds) — this exercises the actual PendingIntent (flags, mutability, API 34+ marshaling), the seam a replayed intent cannot prove; FALLBACK = `adb shell am start` replaying the Answer action's intent extras (payload identical to the notification action), and when the fallback is used, one manual Answer tap on `ring_killed` is a REQUIRED runsheet checkbox before closure (precedent `run_notification_tap_device_real.dart`). Any `holepunch:attempt` events in device logs are recorded in the runsheet, never asserted or failed on (lock L7 — punch-outcome assertions belong to VC-02). Network split where demanded: device on cellular/hotspot, emulator on host WiFi NAT. Push legs REQUIRE the deployed relay — the orchestrator probes `call_push_request` support first and aborts with `PRECONDITION: redeploy relay (VC-06 EC2 section)` if unsupported. iOS-boundary rows: deferred-not-waived pattern (print recipe, exit 0, no proof claimed).

---

## EC2 Redeploy & Live Verification  (VC-00 rule 2 — story is NOT done without this)

Grounded in `142-relay-media-push-payload-too-large-tdd-plan.md:141-150` + `go-relay-server/README.md:1-39`. One relay change per deploy; redeploy is an explicit operator action, never part of a test run (173 plan convention).

```bash
# 0. On-box state inspection (prod env is gitignored — verify before touching; NEW step, no repo runbook)
ssh -i se.pem ubuntu@mknoun.xyz 'systemctl cat relay-server && /usr/local/bin/relay-server version && journalctl -u relay-server -n 20 --no-pager'

# 1. Keep a rollback copy of the running binary (NEW, explicit)
ssh -i se.pem ubuntu@mknoun.xyz 'sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.pre-vc06'

# 2. Cross-compile + ship + restart (canonical 142 procedure)
cd go-relay-server && GOOS=linux GOARCH=amd64 go build -o relay-server-linux-amd64 .
scp -i ../se.pem relay-server-linux-amd64 ubuntu@mknoun.xyz:/tmp/relay-server
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /tmp/relay-server /usr/local/bin/relay-server && sudo systemctl restart relay-server && systemctl is-active relay-server && /usr/local/bin/relay-server version'
# expect: active + the VC-06-bumped version string (bump const version, main.go:25)

# 3. Live probe A — action recognized (no more Unknown action)
#    From the dev host, run the caller proof harness's probe mode against prod (emulator, real bridge):
flutter test integration_test/call_ring_caller_proof_test.dart -d emulator-5554 --dart-define=VC06_PROBE_ONLY=true
#    expect: call_push_request answered OK/call_incapable (NOT "Unknown action")

# 4. Live probe B — real call push to a real device token (the rule-2 gate)
#    USB device: install, launch once (registers FCM token + call_invite_v1 capability against prod), force-stop:
adb -s 21071FDF600CSC shell am force-stop com.mknoon.app
dart integration_test/scripts/run_call_device_real.dart --scenario ring_killed -d emulator-5554,21071FDF600CSC
#    expect: device rings full-screen (logcat CALL_RING_SHOWN)

# 5. Server-side evidence
ssh -i se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 100 --no-pager | grep -i "call_push\|PUSH"'
ssh -i se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep relay_call_push_total'
#    expect: relay_call_push_total{result="success"} >= 1

# 6. Rollback (if any probe fails)
ssh -i se.pem ubuntu@mknoun.xyz 'sudo install /usr/local/bin/relay-server.pre-vc06 /usr/local/bin/relay-server && sudo systemctl restart relay-server && systemctl is-active relay-server'
# emergency soft-disable without redeploy: set RELAY_CALL_PUSH_ENABLED=false in the unit env + restart (kill-switch, R5)
```

Note (verified gap): the wake-token set and presence are memory-only and the documented prod unit sets only `FIREBASE_SERVICE_ACCOUNT` (likely memory backend) — call pushes depend only on the push-token store, which survives under redis if prod ever enables it; a relay restart drops in-memory tokens until clients re-register (existing behavior, unchanged by VC-06).

---

## Working Piece On Close

**A killed Android phone rings like a phone and answers into a live call.** Concretely: with the app force-stopped on a USB-connected Pixel 6, a call started from an emulator makes the device ring full-screen with ringtone + vibration within the pre-committed budget (≤ 3.0 s p95 over 10 trials); tapping Answer cold-launches straight into the VC-05 incoming-call screen and two-way audio connects within ≤ 5.0 s p95 (node cold start ≈1.2–1.5 s hidden inside answer flow); tapping Decline (or min(45 s, TTL-remaining) timeout / TTL expiry — L1) resolves to a missed-call notification and the caller sees decline/expiry per VC-04; a connected call keeps running with the screen off or the app backgrounded under a `phoneCall|microphone` FGS. The relay serving this is live on `mknoun.xyz` with a kill-switch and Prometheus visibility. This is a self-contained capability VC-07 (iOS parity), VC-08 (video) and VC-09 (hardening) build on without rework.

## Metrics Ownership  (VC-00 metrics table — "Ring latency / answer latency → VC-06 → flow events")

| Metric | Named test / runsheet step |
|---|---|
| Ring latency (push sent→ring shown): `CALL_RING_SHOWN.ringLatencyMs` = handler now − `sent_at_ms` | VC-06-D5 asserts the event + computed field; VC-06-E1 runsheet extracts real-device values over **10 `ring_killed` runs (+10 backgrounded)** into VC-06-RESULTS.md as min/median/p95 (FDC-S1 conventions); **pass/fail = p95 ≤ 3000 ms (pre-committed)** |
| Answer latency (tap→ICE connected): `CALL_ANSWER_TAPPED` → VC-05 `CALL_CONNECTED` | VC-06-D12 asserts `CALL_ANSWER_TAPPED`; VC-06-E1 runsheet computes the delta from device logcat over the same 10 runs (flow logging forced via `--dart-define=FDC_FLOW_LOG=1`, `lib/main.dart:320-330` convention); **pass/fail = p95 ≤ 5000 ms (pre-committed)** |
| Relay call-push outcomes | `relay_call_push_total{result}` asserted in R1–R6; live scrape in EC2 probe step 5 |

---

## Acceptance Gates  (LITERAL — copy/paste; VC-00 rule 6: capture green baselines at execution start, never hardcode stale counts)

```bash
# 0. Baselines + dirty-tree snapshot (record outputs in Execution Progress)
git status --short
./scripts/run_test_gates.sh 1to1                         # capture green baseline count at execution start
./scripts/run_test_gates.sh groups                       # capture baseline (floor)
./scripts/run_host_test_gates.sh feature-host-all        # capture baseline
./scripts/run_host_test_gates.sh core-host-all           # capture baseline
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)   # capture baseline

# RED (per slice — each command runs BEFORE that slice's production edits; see Step-By-Step slices A–E) — each must FAIL for its documented reason
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_CallPush' -count=1)  # FAIL: Unknown action
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CallPushRequest' -count=1)                              # FAIL: compile (symbol missing)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'CallPushRequestBridge' -count=1)                      # FAIL: compile
flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'VC-06-D5'          # FAIL: dropped at fallback gate
flutter test test/core/services/call_android_platform_config_test.dart                                             # FAIL: manifest strings absent
# (remaining D-rows: run each new file focused; expect compile-fail or assertion-fail per catalog)

# Direct GREEN (after implementation)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CallPushRequest' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'CallPushRequestBridge' -count=1)
flutter test test/features/call/ test/features/push/application/ test/core/notifications/ \
  test/core/bridge/go_bridge_client_test.dart test/core/bridge/p2p_bridge_client_test.dart \
  test/core/services/p2p_service_impl_call_push_test.dart test/core/services/call_android_platform_config_test.dart

# Preservation sentinels + named gates (compare to captured baselines; delta must equal the named new/migrated tests only)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# Registration verification (rule 6 — no invisible tests)
./scripts/run_test_gates.sh completeness-check
./scripts/check_reliability_simulation_discovery.sh
./scripts/run_host_test_gates.sh host-all --list | grep -i callpush     # both synthetic Go paths present

# EC2 redeploy + live verification gate (section above; MUST pass before device e2e)

# Device-proof closure (rule 1) — ring-poll hard-fails at 20 s; latency pass/fail per Pre-Committed Latency Budgets (p95 over 10 trials)
adb devices -l
dart integration_test/scripts/run_call_device_real.dart --scenario ring_killed        -d emulator-5554,21071FDF600CSC   # ×10
dart integration_test/scripts/run_call_device_real.dart --scenario ring_backgrounded  -d emulator-5554,21071FDF600CSC   # ×10
dart integration_test/scripts/run_call_device_real.dart --scenario ring_timeout       -d emulator-5554,21071FDF600CSC

# Hygiene
flutter analyze            # 0 new vs baseline (scripts/check_flutter_analyze_baseline.sh; do not rewrite the baseline)
git diff --check
```

No migration gate: VC-06 changes no DB schema (nothing persisted client-side; ring state is notification-side by design).

---

## Known-Failure Interpretation

- **Expected RED (pre-implementation):** every catalog row, for the documented reason (unknown action / compile fail / fallback-gate drop / missing manifest strings).
- **Expected migration deltas:** `p2p_bridge_client_test.dart` capability-list pin (additive `call_invite_v1`) and `forbidden_field_classifier_test.go` fixture — named in the catalog; any OTHER existing-test failure is scope drift (BLOCKING).
- **Pre-existing dirty tree:** the branch carries many unrelated modified files (snapshot at step 0) — preserve, never revert/absorb/reformat.
- **Environment blockers (NOT product):** missing USB device/emulator (`adb devices` empty → policy N/A note, not a fake pass); FCM delivery delayed by OEM battery manager on non-canonical hardware; relay not yet redeployed (orchestrator prints the PRECONDITION message — run the EC2 section, don't fake the ring).
- **Latency budget breach (STOP, not record-and-pass):** ring p95 > 3000 ms or answer p95 > 5000 ms over the 10-trial set, or ANY single 20 s ring-poll hard-fail on the canonical rig → STOP; investigate FCM priority/Doze demotion (`adb shell dumpsys deviceidle`, FCM diagnostics) before any closure claim. The budgets are pre-committed and may only be revised via a recorded decision.
- **Holepunch events in device logs:** `holepunch:attempt` may legitimately fire on HEAD (EnableHolePunching is always on — lock L7); RECORD them in the runsheet, never fail a VC-06 scenario on them; punch-outcome assertions are VC-02's alone.
- **Go 1.26 quic-go panic:** any Go invocation without `GOTOOLCHAIN=go1.25.0` is an invalid run, not a product failure (rule 6).
- **Scope drift (BLOCKING):** failures in group/feed/intro suites, iOS pin tests changing (`ios_push_project_config_test.dart` must stay green — VC-06 touches no iOS config), or router tests changing (VC-06 adds no router case).

---

## Done Criteria

- [ ] Feasibility spike (step 0.5) done: data-only high-priority FCM proven to wake the force-stopped app on the canonical device; observed wake latency recorded.
- [ ] RED-first held PER SLICE (slices A–E: R1–R7, G1–G2, D1–D3+D13, D4–D12+D15, D14 — each authored and shown failing for its documented reason before its slice's production code); E1–E3 skeleton + registrations landed up front.
- [ ] Mutation-verified: every matrix mutation revert executed once and shown to re-RED.
- [ ] Direct GREEN + preservation sentinels + named gates green vs captured baselines.
- [ ] Harness registration verified in gate runs: relay tests appear under the pinned `^TestRelayNotificationClosure_` gate; both Go synthetic paths listed by `host-all --list`; `completeness-check` + discovery green; `/sims 1to1 --list` shows the new runner slot.
- [ ] EC2 redeploy done + live probes A/B green + `relay_call_push_total` scraped + rollback binary staged (rule 2).
- [ ] Device-proof E1 (PROD-CRITICAL) + E2 + E3 green on emulator-5554 + 21071FDF600CSC; latency stats over 10 trials per ring scenario recorded in VC-06-RESULTS.md as min/median/p95; **pre-committed budgets met: ring ≤ 3.0 s p95, answer-readiness ≤ 5.0 s p95, zero 20 s ring-poll hard-fails** (breach = STOP, see Known-Failure Interpretation).
- [ ] Answer proven by a real tap on the notification action (uiautomator primary; if intent-replay fallback was used, the manual Answer-tap runsheet checkbox is checked).
- [ ] Kill-switch verified both polarities (R5 host + box-side soft-disable spot check).
- [ ] Gate docs synced (test-gate-definitions.md, test-gates-reference.md, _current-test-map.md) for the new synthetic paths/discovery cases; VC-06 NOT added to 00-INDEX.md (rule 7); `./graphify-arch/refresh_arch_graph.sh --incremental` run once after the coherent change.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

---

## Scope Guard (hard "Do not")

- Do NOT touch iOS: no `Info.plist` background modes, no `AppDelegate.swift` whitelist changes, no PushKit/CallKit, no APNs payload branch beyond the counted `call_ios_deferred` skip — **VC-07** owns all of it.
- Do NOT integrate ConnectionService/Telecom — explicitly deferred (Accepted Differences).
- Do NOT inbox, persist, or retry any `call_*` payload (rule 5); do NOT add call cases to `PendingMessageRetrier`/`retry_unacked_messages_use_case.dart`.
- Do NOT hook the ring into the inbox deposit→push seam (`inbox.go:1307-1316`) or alter `extractChatPushMetadata`'s existing cases.
- Do NOT define or alter `call_*` envelope schemas/TTL/glare — **VC-04** owns them; consume only.
- Do NOT touch the media/ICE engine, in-call UI beyond the entry payload + FGS hooks — **VC-05**; no video — **VC-08**.
- Do NOT modify TURN/limits/rendezvous/media relay code (**VC-03**/**VC-01**) or bundle their relay changes into this deploy (one relay change per deploy).
- Do NOT flip `wakeTokenGateEnforced` or wire call pushes through wake tokens (stance below).
- Do NOT add VC-06 to `00-INDEX.md` (rule 7) or hardcode gate pass counts (rule 6).
- Do NOT start the Go node from the FCM headless handler (Decision Record).

## Accepted Differences / Intentionally Out Of Scope

- **ConnectionService/Telecom deferred:** full-screen intent + FGS is the shippable ring path; Telecom integration (system in-call UI, call audio focus arbitration with cellular calls, Bluetooth answer buttons) is a follow-up hardening item (natural home: VC-09) — rationale: Telecom requires a phoneAccount registration flow and OEM-specific behavior that would block the epic's phase-3 working piece; the full-screen-intent path is the pattern WhatsApp/Signal shipped first.
- **iOS push branch stubbed:** `call_ios_deferred` counted, no send — the current relay has no direct APNs client (FCM Admin only), so a true `apns-push-type: voip` PushKit push needs VC-07's design; test-locked by R6 so the deferral cannot silently rot.
- **Wake-token stance:** call pushes are gated by the `call_invite_v1` capability (explicit recipient opt-in registered with the token) and per-pair rate limits, NOT by the FDC-09 wake-token set (`wakeTokenGateEnforced=false` at rest today, `wake_token_store.go:34`). When a future story enforces wake tokens, the call-push seam is separate and unaffected; that story must add a call-path decision row.
- **Missed-call is local-only:** no `call_missed` envelope back to the caller — the caller derives expiry from VC-04 TTL; avoids a new signaling type outside VC-04's schema ownership.
- **`call_busy` on a busy callee:** handled by the LIVE path (a busy callee has a running node + VC-05 listener answering `call_busy`); the push path deliberately does not attempt busy detection from a dead process (marker files are stale-prone). Consistent with VC-04 semantics; documented, not silent.
- **Ring works without the push too** (same-network live `call_offer` while backgrounded rings via the same notifier) — the push is an additional wake path, so relay downtime degrades to foreground-only ringing, never to broken calls.

## Dependency Impact

- **VC-07 (iOS VoIP)** depends on VC-06's relay seam: it replaces the `call_ios_deferred` branch with the real APNs/PushKit leg and adds the AppDelegate route whitelist entry — collision on the relay push-type switch (VC-00 collision map: whichever lands second rebases; each does its own redeploy + live verification).
- **VC-08 (video)** depends on the FGS: adds `camera` to the foregroundServiceType set and D14's pin must be extended (larger SDP → `offer_omitted` path becomes the common case; the 5 s re-offer cadence from D13 is the contract that keeps answer working).
- **VC-09 (hardening/metrics)** consumes `CALL_PUSH_REQUESTED`/`CALL_RING_SHOWN`/`CALL_ANSWER_TAPPED` flow events and `relay_call_push_total` as inputs to the per-call quality dashboard; Telecom integration lands there.
- **VC-05** is edited in place (StartCallUseCase ring loop, IncomingCallScreen payload entry, in-call controller FGS hooks) — strictly sequential on VC-05's committed tree, never on HEAD.
- Contract exported by VC-06: `call_push_request` action shape `{action,to,callId,sentAtMs,envelope?}` + push data shape `{type:call_invite,call_id,caller_id,sent_at_ms,envelope?|offer_omitted}` + `call_invite_v1` capability string.

## Reviewer Findings

Sufficiency checklist executed against this draft (2026-07-13): spec-case totality — 27 cases (E3 `ring_timeout` added post-review), all with catalog rows + matrix rows, no orphans. Every INV-1..8 names its locking test. Every production edit has a named mutation revert. No vacuous coverage: ring assertions discriminate channel `mknoon_calls` + `CALL_RING_SHOWN` AND NOT `mknoon_messages`; relay results discriminate by `relay_call_push_total{result}` label. No DB change → migration gate N/A (stated). OS-boundary proven on real device+relay (E1/E2/E3), PROD-CRITICAL leg named (E1). Preservation sentinels named with gate commands (baseline-capture pattern per rule 6). Acceptance gates literal. Registration named per test incl. the two manual Go synthetic paths and the discovery runner/test cases. Known-failure interpretation + dirty-tree snapshot planned. Refuted digest claims recorded as do-NOT-re-introduce. Blind-spot sweep: all four classes have rows (no N/A skips). **Findings fixed during review:** (1) initial draft hooked missed-call scheduling to a foreground timer — replaced with FLN scheduled notification + manifest receivers (process-death durable) and D7 re-pointed; (2) initial draft omitted the `offer_omitted` convergence path — added caller 5 s re-offer cadence (D13) and the D12 "connecting" reconstruction; (3) initial draft had no explicit registration for the relay tests — renamed to the `TestRelayNotificationClosure_CallPush*` prefix to ride the pinned gate regex. Verdict: sufficient, awaiting-review.

**/tdd-review verdict (2026-07-13, adversarial audit + epic contract locks):** dimension scores — goal-clarity 80 (strong), compartmentalization 66 (adequate), anti-drift 84 (strong), define-good 66 (adequate), goal-verification 76 (strong). Findings: 2 material, 6 moderate, 3 nit — ALL applied. Material: (1) waterfall RED authoring restructured into per-slice RED→GREEN pairs (slices A–E; skeleton/registrations only up front); (2) latency pass/fail pre-committed instead of deferred to first measurements — ring ≤ 3.0 s p95 (push send → full-screen intent posted) and answer-readiness ≤ 5.0 s p95 (tap → ICE connected) on the USB device over 10 trials, 20 s ring-poll hard-fail, breach = STOP (new Pre-Committed Latency Budgets section). Moderate: step-0.5 FCM wake feasibility spike added; `callNotificationId(String)` single shared id helper pinned (FNV-1a/31-bit, D5/D6/D7/D9 sole source, D6 asserts it); Answer payload encoding pinned to `toPayload()`/`fromPayload()` (`notification_route_target.dart:68,:87`) with byte-identical envelope round-trip case in D12; 10-trial min/median/p95 protocol replaces single-shot latency; E3 `ring_timeout` named scenario + matrix row + Done Criteria (real-device missed-call durability); real uiautomator Answer tap primary with intent-replay fallback + required manual-tap checkbox. Nits: 45 s anchored to VC-04 `kCallOfferTtl = 45000` ms via min() (lock L1, band = design choice, Signal/Matrix precedent); stale `AndroidManifest.xml:90-93` cites corrected to `:99-102` (verified); E1 callee-side audio observable honesty note (caller leg carries audio assertions). Contract locks applied: L1 (TTL/timeout), L2 (`call_push_request` canonical — already so), L5 (orchestrator renamed to the epic-shared `integration_test/scripts/run_call_device_real.dart`, matching VC-08/VC-09; no new family array, `NIGHTLY_ONLY_TESTS`/`ONE_TO_ONE_TESTS` note added), L7 (punch events recorded, never failed on). L3/L4/L6 not touched by this plan.

## Arbiter Decision

Structural blockers: none. | Deferred details: exact VC-05 symbol names (StartCallUseCase/IncomingCallScreen entry points) resolved at execution against VC-05's landed tree; merged targetSdk value verified at step 0; callee-side audio observable (VC-05 marker vs caller-leg-only) resolved at execution and recorded in the runsheet. Latency budgets are NOT deferred — pre-committed (ring ≤ 3.0 s p95, answer ≤ 5.0 s p95, 10 trials, 20 s poll hard-fail), revisable only via a recorded decision. | Accepted differences: as listed (Telecom deferral, iOS stub — relay dispatches by token type per lock L2, APNs voip/PushKit leg is VC-07's; wake-token stance; local-only missed-call; live-path busy; durable-inbox ring deposit REJECTED per lock L2/VC-00 rule 5 — `call_*` is never durably inboxed).

## Final Execution Verdict

Verdict: (pending execution) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner): …
