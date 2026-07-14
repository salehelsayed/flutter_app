# VC-07 — iOS VoIP prerequisites: voip/audio background modes + PushKit/CallKit  (New Feature)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — VC-00 roadmap story row VC-07 (`Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md:72`) + the VC epic ring-plane decision (VC-00 "Ring plane": iOS **adds the missing `voip`/`audio` UIBackgroundModes** + PushKit/CallKit).

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | grounding digests platform-av-push / relay-server-ops / harness-conventions (all anchors re-verified in source: `ios/Runner/Info.plist:85-88`, `ios/Podfile:96-111`, `ios/Runner/Runner.entitlements:5-6`, `test/features/push/application/ios_push_project_config_test.dart:28-45`, `go-relay-server/inbox.go:85-90,404,506-507,745,948,2152`, `go-relay-server/push_token_store.go:22-37`, `go-relay-server/reaction_push.go:18,47`, `go-mknoon/bridge/bridge.go:1358-1396`, `go-mknoon/node/inbox.go:28-51,796-863`, `lib/core/bridge/p2p_bridge_client.dart:790-825`, `lib/core/services/p2p_service_impl.dart:4905-4908`, `lib/features/push/application/register_push_token_use_case.dart:37-85`, `integration_test/scripts/run_1to1_device_real.dart:1-60`) | voip/audio modes absent; zero PushKit/CallKit code anywhere; relay has no voip push path; FCM cannot carry a PushKit voip push (digest gap) → direct APNs leg | draft plan |
| 2026-07-13 | Planner | (this file) | scoped to iOS config lock + PushKit token registry + relay voip leg + CallKit host-tier wiring; iOS device evidence deferred-not-waived | sufficiency review |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | GREEN A (config lock) | | (VC-07-01 cmd + result) | scoped files only | |
| | GREEN B (go-mknoon frame) | | (VC-07-17 cmd + result) | | |
| | GREEN C (relay registry + voip leg) | | (VC-07-09/09b..16 cmds + results) | | |
| | GREEN D (Dart plumbing) | | (VC-07-07/08 cmds + results) | | |
| | GREEN E (Dart CallKit surface) | | (VC-07-05/06 cmds + results; resolved flag name recorded BEFORE this row) | | |
| | GREEN F (native iOS pins) | | (VC-07-03/04 cmds + results) | | |
| | GREEN G (orchestrator entry) | | (discovery cmd + result) | | |
| | direct GREEN (aggregate) | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | EC2 redeploy + live probe | | (ssh/journalctl/curl evidence) | relay live-verified | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Spec / intent: `VC-00-roadmap.md` (story map row VC-07, ring-plane decision, non-negotiable rules 1–7, metrics table) + this plan.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose); `scripts/run_host_test_gates.sh`.
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (`expand_1to1_device_real` parses `--list-scenarios`; DR1's orchestrator `run_call_device_real.dart` gets its own runner case — lock L5).
- Numbering / index: VC plans live ONLY in this feature subdirectory, numbered VC-NN; `Test-Flight-Improv/00-INDEX.md` does **not** index feature subdirectories (VC-00 rule 7).
- Grounding digests (verified file:line evidence, adversarially refuted): `vc-grounding/platform-av-push.md`, `vc-grounding/relay-server-ops.md`, `vc-grounding/harness-conventions.md`. Line numbers re-verified against the working tree on 2026-07-13; they drift — re-verify before editing.
- External OS rule (not citable as repo file:line — platform contract): Apple `PKPushRegistryDelegate.pushRegistry(_:didReceiveIncomingPushWith:for:completion:)` — on iOS 13+, **every** VoIP push MUST be reported to CallKit (`CXProvider.reportNewIncomingCall`) before the completion handler runs; failing to report terminates the app, and repeated failures make the system stop delivering VoIP pushes entirely. This rule shapes VC-07-03's ordering pin.

---

## Session Classification
**implementation-ready** — every closure-bearing behavior is host-observable: iOS *config* is test-locked by file-reading pin tests (established precedent: `test/features/push/application/ios_push_project_config_test.dart:28-45`, `test/core/notifications/main_activity_onnewintent_pin_test.dart`), the Dart CallKit bridge is unit-testable via `TestDefaultBinaryMessengerBinding` (precedent: `migration_transfer_keep_alive.dart` channel seam), and the relay voip leg is Go-host-testable with an injected sender plus a real-sender TLS HTTP/2 round-trip against an in-test server (VC-07-09b). The relay half additionally requires the VC-00 rule-2 EC2 redeploy + live probe (operator gate inside this story). The on-iPhone PushKit/CallKit receipt is **deferred-not-waived** (VC-00 rule 1: no iOS device in the Android-only rig) with a written macOS/iPhone recipe registered as an orchestrator scenario.

---

## Exact Problem Statement

iOS today cannot ring for an incoming call and cannot keep call audio alive in the background. Verified on HEAD: `ios/Runner/Info.plist:85-88` declares `UIBackgroundModes` = `fetch` + `remote-notification` **only** — no `voip`, no `audio`. There is zero PushKit/CallKit/voip code anywhere in `ios/Runner`, `ios/NotificationService`, or `project.pbxproj` (grep = 0 hits, digest claim 5), and zero voip push capability in the relay: all five production APNS header sites send `apns-priority: 10` + `apns-push-type: "alert"` (`go-relay-server/inbox.go:506-507,581-582,711-712`, `reaction_push.go:479-480,568-569`; grep `voip|pushkit` over go-relay-server = 0 hits). A killed or backgrounded iOS callee therefore can never receive a call: there is no wake vehicle (VoIP pushes are the only push class that reliably launches a terminated iOS app into a ringing state) and no OS call UI integration.

Who experiences it: every iOS callee for the VC epic — VC-05's foreground audio call works only while the app is open on screen; without VC-07 the iOS half of "phone rings like a phone" (VC-06's Android counterpart) does not exist, and an in-progress call dies the moment the app is backgrounded (no `audio` mode).

Why now: this is the USER REQUIREMENT for this story — iOS currently has NO voip/audio UIBackgroundModes; this story MAKES THEM EXIST, **test-locked** so the requirement can never silently regress, and lays the PushKit token → relay voip push → CallKit report pipeline the ring plane needs.

**What must improve:**
1. `UIBackgroundModes` gains `voip` + `audio`, locked by a host pin test that fails if either is ever removed.
2. The relay can address an iOS callee's **PushKit voip token** (distinct from the APNs alert token FCM holds) and emit a spec-correct voip push: `apns-push-type: voip`, topic `com.mknoon.app.voip`, priority 10, over a **direct APNs HTTP/2 leg** — Go-test-proven shape, deployed to EC2. Trigger (lock L2 — ONE ring mechanism): the caller-side relay action `call_push_request` (VC-06 owns the action + the Android FCM branch; exported shape `{action,to,callId,sentAtMs,envelope?}`); the relay dispatches by the callee's registered token type — `VoipToken` present → this story's APNs voip leg. `call_*` is never durable-inboxed (VC-00 rule 5), so no inbox-deposit seam is involved.
3. Native iOS registers PushKit, forwards the voip token to Dart for relay registration, and reports **every** voip push to CallKit before completing (OS rule above); answer/decline/mute CallKit actions bridge to VC-05's CallEngine over a new `mknoon/callkit` MethodChannel; CallKit's `didActivate audioSession` is forwarded so WebRTC audio starts at the CallKit-sanctioned moment.

**What must stay unchanged → preserved-green sentinels:**
- Existing iOS push config pins: `ios_push_project_config_test.dart::'Info.plist includes fetch and remote-notification background modes'` (:28-36 — additive modes keep it green) and `::'Runner.entitlements keeps production aps-environment'` (:38-45 — voip push needs NO entitlement beyond the existing `aps-environment` at `Runner.entitlements:5-6`; PushKit rides the same push entitlement).
- The FCM alert push contract: `go-relay-server/push_payload_closure_test.go` (all `TestRelayNotificationClosure_*`), `protocol_contract_test.go` (register_token legacy frame stays byte-compatible), `push_token_registration_test.go`, `forbidden_field_classifier_test.go` — VC-07 adds **no** new FCM data fields (the voip payload is a separate APNs body, not FCM `data`).
- Podfile permission macros: `PERMISSION_MICROPHONE=1` stays the ONLY permission_handler macro (`ios/Podfile:103-108`); `PERMISSION_CAMERA` arrives with VC-08 only.
- Durable inbox deposits NEVER trigger voip pushes — `call_*` is never durable-inboxed (VC-00 rule 5 / lock L2), and a stray `call_invite` deposit behaves exactly as HEAD (silently stored, no push; VC-07-11's deposit cases lock this). A `call_push_request` for a callee **without** a voip token is VC-06's FCM branch — VC-07's voip branch stays silent for it.

---

## Root Cause (verify → refute confirmed)

New-feature framing: the "root cause" is a verified **absence chain**, each link re-read in source on the working tree:

1. **No background modes:** `ios/Runner/Info.plist:85-88` — `UIBackgroundModes` array = `fetch`, `remote-notification`. `voip`/`audio` absent.
2. **No native voip surface:** grep `pushkit|callkit|voip` over `ios/Runner`, `ios/NotificationService`, `project.pbxproj` = 0 hits (digest claim 5, re-confirmed). `AppDelegate.swift` has `FirebaseAppDelegateProxyEnabled=false` + a UIScene FCM-delegate workaround (`AppDelegate.swift:90,148-165`) that any PushKit delegate wiring must coexist with (digest gap — named risk below).
3. **No relay voip leg:** all APNS pushes are `apns-push-type: "alert"` via the FCM Admin SDK (`inbox.go:506-507` in `buildPushMessage:404`); the push token store holds ONE token per peer (`tokenEntry` `inbox.go:85-90`; `push_token_store.go:22-37` map overwrite) — a PushKit token registered through the existing action would **clobber** the FCM token.
4. **FCM cannot carry a voip push** (relay-server-ops digest, Gaps): the relay's only APNs path is `messaging.APNSConfig` through Firebase, which addresses the app's *standard* APNs token. A PushKit voip token is a **different token** on the `<bundleId>.voip` topic and requires a direct APNs HTTP/2 request. → design decision: **new direct APNs leg** in the relay (stdlib `net/http` HTTP/2 + ES256 JWT via `crypto/ecdsa`; no new third-party dependency), credential-gated by env, disabled-by-default when credentials are absent (mirrors the FCM "push disabled" degrade at `inbox.go:108-117`).

**Refuted / do-NOT-re-introduce:**
- Do NOT plan voip pushes through the FCM Admin SDK `APNSConfig` path — refuted by mechanism (link 4). The FCM path stays the *alert* path only.
- Do NOT treat "no config-assert test precedent exists" as true — the digest **verified** file-reading pin tests exist (`ios_push_project_config_test.dart`, `share_intent_android_test.dart:9-90`, `main_activity_onnewintent_pin_test.dart`); VC-07 *extends* the established pattern rather than inventing one.
- Do NOT register the voip token via a bare second `register_token` call — refuted: the memory store overwrites the whole `tokenEntry` (`push_token_store.go:29-36`), which would destroy the FCM alert token. The voip token must be an **additive field** on the same entry (precedent: `Capabilities`, additive per plan 256, `go-mknoon/node/inbox.go:37-39`).
- Do NOT add a `pion`/APNs third-party module claim without checking `go.mod` — the relay-server-ops digest's refutation pass showed `go.mod` already carries indirect deps the scout missed; VC-07's APNs client is stdlib-only precisely to avoid that class of drift.

---

## Real Scope

**In scope (VC-07):**
1. `ios/Runner/Info.plist` — `UIBackgroundModes` += `voip`, `audio` (insert into the array at `:86-89`).
2. New host pin tests locking (1) + PushKit/CallKit wiring + Podfile mic/camera asymmetry (files under `test/core/services/`, auto-globbed).
3. Native iOS (Swift, `ios/Runner/`): `PKPushRegistry(desiredPushTypes: [.voIP])`, voip-token forward + incoming-push → `CXProvider.reportNewIncomingCall(...)` **before** `completion()` (OS rule), `CXAnswerCallAction`/`CXEndCallAction`/`CXSetMutedCallAction` handlers, `provider(_:didActivate/didDeactivate audioSession:)` forwarding — all over a new `mknoon/callkit` MethodChannel (repo convention: bespoke channels, precedents `mknoon/migration_keepalive` `AppDelegate.swift:509-573`, `mknoon/ios_notification_open` `:61`).
4. Dart: `lib/features/call/infrastructure/ios_callkit_channel.dart` (channel wrapper, `MissingPluginException` → no-op degrade like `migration_transfer_keep_alive.dart:59`); `lib/features/call/application/callkit_call_coordinator.dart` (CallKit actions ↔ VC-05 `CallEngine`; flow events for ring/answer metrics); voip-token plumbing through the existing gated registration path: `register_push_token_use_case.dart` gains a voip-token source, `P2PService.registerPushToken` gains optional `voipToken`, `callP2PInboxRegisterToken` (`p2p_bridge_client.dart:790`) adds `voipToken` to the payload only when present.
5. go-mknoon: `bridge.InboxRegisterToken` params += `voipToken` (`bridge.go:1372-1376` struct), `node.InboxRegisterToken` threads it, `inboxRequest` += `VoipToken string \`json:"voipToken,omitempty"\`` (`node/inbox.go:28-51` — byte-compatible when empty, exactly the `WakeToken`/`Capabilities` NET-REL-07 pattern).
6. go-relay-server: `tokenEntry` += `VoipToken` (+ backend methods, memory `push_token_store.go` + redis `backend_redis.go`); `register_token` action (`inbox.go:2152`) stores it, preserves it on voip-less re-registration, `unregister_token` (`inbox.go:2171-2174`) clears it; new `voip_push.go` — env-configured direct APNs client (`APNS_AUTH_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_VOIP_TOPIC` default `com.mknoon.app.voip`, `APNS_HOST` default `api.push.apple.com`), `buildVoipPushRequest` pure builder (testable without network), injectable sender seam (pattern: `PushService.sender` `inbox.go:81`); voip dispatch branch inside the `call_push_request` **named handler** (lock L2 — the ONE ring mechanism; action owned by VC-06, request shape `{action,to,callId,sentAtMs,envelope?}`, caller identity = the stream-authenticated peer, never a request field; named-handler rule per the `HandleInboxStream` nolint note `inbox.go:2027-2032`; on HEAD the action hits the `Unknown action` default arm `inbox.go:2277`): callee entry `VoipToken` present → voip send with `callId`/`sentAtMs` read from the action request fields (missing `callId` → no send + `result="missing_call_id"`) and `fromPeerId` = the authenticated caller; **no VoipToken → VC-07's branch stays silent (VC-06's FCM branch owns that case)**; when `wakeTokenGateEnforced` (same condition as `inbox.go:1307-1316`, via an additive `wakeToken,omitempty` request field checked against the callee's registered set — exported as a VC-06 interface note) an unauthorized caller gets no voip send; at the shipped default (gate OFF) the send proceeds with no wake token; the `InboxStore.Store` deposit path gains NO voip behavior (rule 5 — deposits never ring). Landing-order contract: if VC-06 has not landed yet, VC-07 creates the minimal named handler (request parse + per-peer rate-limit seam + the voip token-type branch only) and VC-06 rebases its FCM branch beside it (mirror of VC-06's `call_ios_deferred` stub for the reverse order). New `relay_voip_push_sent_total{result}` metric (`metrics.go` promauto pattern).
7. EC2 redeploy of the relay + live verification (rule 2) — see the dedicated section.
8. Orchestrator scenario `vc07_ios_voip_pushkit_callkit_receipt` in `integration_test/scripts/run_call_device_real.dart` — the epic's call device orchestrator (lock L5; VC-05 creates it honoring `--scenario all --list-scenarios`; if absent when VC-07 executes, create it to that contract) — as a deferred-not-waived recipe printer (pattern precedent `run_1to1_device_real.dart:14-19`), plus its runner case in `scripts/check_reliability_simulation_discovery.sh` (sibling of the `run_1to1_device_real.dart` branch at `:247`).
9. Kill-switch (rule 3): relay leg is OFF unless APNs credentials are provisioned (env-gated, boot-logged); client-side PushKit/CallKit init + voip registration are gated behind VC-05's call feature flag (bind to the flag VC-05 landed; if VC-05 shipped no Dart-side flag, gate on a `MKNOON_CALLS` dart-define read — Dart-only, no `feature_flags.go` edit, avoiding the shared-flag-file collision).

**Out of scope (owning story):**
- Android ringing, full-screen intent, FGS types, Android manifest additions + their pin tests, the FCM call-invite push (fields, priority, fallback whitelist) → **VC-06**. VC-07 locks iOS config only — no Android manifest pin here (avoids double-locking; VC-06's plan owns its own manifest pin test — recorded in Dependency Impact).
- Video, camera permission macro (`PERMISSION_CAMERA=1`), camera Info.plist additions → **VC-08**.
- The `call_*` envelope grammar, TTL, glare, `callId` idempotency → **VC-04**. VC-07 consumes the `call_invite` type string only.
- CallEngine internals, flutter_webrtc dependency, in-call UI → **VC-05**.
- ICE restart, quality metrics closure, "always relay" toggle → **VC-09**.
- App Store review narrative for voip/audio modes → explicitly excluded by the brief.

---

## Execution Environment  (VC-00 rule 1 — restated)

The implementing agent runs the full loop end-to-end on a **USB-connected Android device + Android emulator(s)**; iOS simulators/devices are NOT part of this rig.

```bash
# Device discovery (run first; record output in Execution Progress)
adb devices -l
flutter devices --machine
# Canonical pair (plan-256 convention): emulator-5554 (AVD mknoon_play_35) + USB Pixel 6 21071FDF600CSC

# VC-07 closure legs and where they run:
#  - ALL Dart RED/GREEN tests: HOST (no device) — flutter test <file>
#  - ALL Go tests: HOST — GOTOOLCHAIN=go1.25.0 pinned invocations (rule 6)
#  - Android device/emulator: NOT required for VC-07 closure (no Android production
#    code changes). Optional regression convenience only, e.g.:
flutter test integration_test/transport_e2e_test.dart -d emulator-5554   # only if transport gate re-run is desired
#  - Call device orchestrator convention (lock L5 — used by the deferred recipe entry, listing only):
dart run integration_test/scripts/run_call_device_real.dart --scenario all --list-scenarios
dart run integration_test/scripts/run_call_device_real.dart --scenario vc07_ios_voip_pushkit_callkit_receipt -d <iosUdid,androidSerial>
#    → prints the macOS/iPhone recipe and exits 0 WITHOUT claiming proof (deferred-not-waived pattern,
#      run_1to1_device_real.dart:14-19). Unavailable target = "N/A (target unavailable by project policy)".
```

**iOS-boundary legs (PushKit receipt, CallKit ring, audio-session activation on hardware) are deferred-not-waived:** the orchestrator scenario prints the recipe below (Device/Relay Proof Profile) and a macOS/iPhone session owns the evidence. iOS *config* is still test-locked at host tier in this story — that is the point of VC-07-01..04.

---

## Files To Inspect Next

**Production (entry/use-case, models, helpers):**
- `ios/Runner/Info.plist:85-88` (UIBackgroundModes array — the edit site), `ios/Runner/AppDelegate.swift` (PushKit/CallKit wiring site; mind the UIScene/FCM workaround at `:90,148-165` and channel precedent `:509-573`), `ios/Podfile:96-111` (mic macro), `ios/Runner/Runner.entitlements:5-6` (no edit — voip needs no extra entitlement).
- `lib/features/push/application/register_push_token_use_case.dart:37-85` (gated registration seam; `accountMigrationNetworkGate` at `:66`), `lib/features/push/application/push_registration_coordinator.dart` (retry loop the voip token re-triggers).
- `lib/core/services/p2p_service.dart:290` + `lib/core/services/p2p_service_impl.dart:4905-4908` (`registerPushToken`, already behind `_allowsAccountNetworkSideEffects('p2p_register_push_token')` — VC-00 rule 4 satisfied by routing voip registration through this exact method; **no new ungated network primitive**).
- `lib/core/bridge/p2p_bridge_client.dart:790-825` (`callP2PInboxRegisterToken` payload).
- `go-mknoon/bridge/bridge.go:1351-1396` (`InboxRegisterToken`), `go-mknoon/node/inbox.go:28-51` (`inboxRequest`), `:796-863` (`Node.InboxRegisterToken` frame build at `:829-834`).
- `go-relay-server/inbox.go:85-90` (tokenEntry), `:139-150` (RegisterToken), `:2152-2168` (`register_token` case), `:2171-2174` (`unregister_token` clears wake tokens — extend to voip), `:2265-2278` (action switch tail — the `call_push_request` named-handler branch lands beside `handlePresenceSet`; `Unknown action` default at `:2277`), `:2027-2032` (named-handler rule), `:1307-1316` (wake-token-gate condition, read-only template; `wake_token_store.go:34`), `:404,506-507` (alert header contrast), `:745-772` (strict fallback — NOT edited), `push_token_store.go:22-37`, `backend_redis.go` token store (`:85-86` wiring; entry serialization — verify at execution), `metrics.go:194-197` (counter pattern), `main.go:82-88` (push init/boot log site).

**Direct tests + integration tests:**
- `test/features/push/application/ios_push_project_config_test.dart` (preserved sentinels + style template), `test/features/push/application/register_push_token_use_case_test.dart` (extend), `test/core/bridge/p2p_bridge_client_test.dart` (extend; already in `ONE_TO_ONE_TESTS`, `run_test_gates.sh:21` array), `test/core/notifications/main_activity_onnewintent_pin_test.dart` (regex-pin style), `test/shared/fakes/fake_p2p_service_integration.dart:268` (implements `registerPushToken` — signature ripple).
- `go-relay-server/push_token_registration_test.go`, `push_payload_closure_test.go`, `protocol_contract_test.go`, `metrics_test.go`, `backend_redis_test.go`, `wake_token_store_test.go:59-66` (gate ships-off pin).
- `integration_test/scripts/run_call_device_real.dart` (L5 call orchestrator — scenario table + deferred-not-waived printer; create-if-absent to the `--scenario all --list-scenarios` contract), `integration_test/scripts/run_1to1_device_real.dart:14-19` (printer pattern precedent), `scripts/check_reliability_simulation_discovery.sh:238-256` (runner case region).

**Dependency-only context (not edited):** `lib/features/account_migration/application/migration_transfer_keep_alive.dart:25-99` (channel degrade pattern), `go-relay-server/reaction_push.go:18,47` (capability/opt-in template), VC-05's landed `lib/features/call/` CallEngine surface (bind at execution).

---

## Existing Tests Covering This Area

| Test | Covers | Status |
|---|---|---|
| `ios_push_project_config_test.dart::'Info.plist includes fetch and remote-notification background modes'` (:28-36) | existing background modes (contains-style) | exists — **stays green** (additive) |
| `ios_push_project_config_test.dart::'Runner.entitlements keeps production aps-environment'` (:38-45) | push entitlement | exists — stays green (voip needs nothing more) |
| `go-relay-server/push_token_registration_test.go` | `register_token` action + capability persistence | exists — stays green; extended by VC-07-10/14 |
| `go-relay-server/protocol_contract_test.go` | inbox action wire contract incl. unknown-action ERROR | exists — stays green (`voipToken` is `omitempty`-additive) |
| `go-relay-server/push_payload_closure_test.go` (`TestRelayNotificationClosure_*`) | FCM payload budgets/shapes | exists — stays green (no FCM shape change) |
| `go-relay-server/forbidden_field_classifier_test.go` | FCM push `data` field whitelist | exists — stays green (voip payload is not FCM `data`); audit after implementation |
| `go-relay-server/wake_token_store_test.go:59-66` | wake-token gate ships OFF | exists — stays green; VC-07-13 reuses its force-on seam |
| `test/core/bridge/p2p_bridge_client_test.dart` | bridge call contract (incl. `register_token` frame) | exists — extended by VC-07-08 (already in `ONE_TO_ONE_TESTS`) |
| `test/features/push/application/register_push_token_use_case_test.dart` | registration flow + migration gate | exists — extended by VC-07-07 |

**Missing coverage gaps (the RED catalog):** no test asserts voip/audio background modes; no test pins any PushKit/CallKit wiring; no Dart CallKit channel/coordinator exists; no Go test asserts a voip push shape, voip token storage/preservation/clearing, voip dispatch discrimination, credential degrade, wake-gate compliance, or the voip metric; no go-mknoon test asserts the additive `voipToken` frame.
**Already in curated family arrays?** Only `p2p_bridge_client_test.dart` (`ONE_TO_ONE_TESTS`, `run_test_gates.sh:21`). Everything else registers per the matrix below.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Go RED convention: new-symbol tests fail to **compile** on HEAD — that is the documented RED (the capability is absent; grep-verified 0 hits). Each entry still names the behavioral mutation that re-reds it after GREEN.

1. **VC-07-01** `test/core/services/ios_voip_background_modes_test.dart::'UIBackgroundModes array declares voip and audio'`
   - Tier: unit/application (host file-reading pin, precedent `ios_push_project_config_test.dart`).
   - Shape/setup: read `ios/Runner/Info.plist`; slice the region between `<key>UIBackgroundModes</key>` and its closing `</array>`; assert the region contains `<string>voip</string>` AND `<string>audio</string>` (region-scoped so a stray string elsewhere in the plist cannot vacuously pass).
   - RED on HEAD because: the array at `Info.plist:86-89` contains only `fetch` + `remote-notification` (verified).
   - GREEN after fix asserts: both modes present inside the array.
   - Mutation that re-reds: delete `<string>voip</string>` (or `audio`) from the array → RED.
2. **VC-07-02** `test/core/services/ios_voip_background_modes_test.dart::'Podfile compiles PERMISSION_MICROPHONE only (camera deferred to VC-08)'`  *(preserved-green lock, not RED)*
   - Tier: unit/application (host pin).
   - Shape/setup: read `ios/Podfile`; assert contains `'PERMISSION_MICROPHONE=1'` AND does NOT contain `PERMISSION_CAMERA` (comment in test: `// VC-08 flips the camera half deliberately`).
   - RED on HEAD because: n/a — green sentinel locking the deliberate mic/camera asymmetry (`Podfile:103-108` verified).
   - GREEN asserts: same (stays green through VC-07).
   - Mutation that re-reds: add `PERMISSION_CAMERA=1` to the Podfile (scope-drift canary) → RED.
3. **VC-07-03** `test/core/services/ios_pushkit_callkit_pin_test.dart::'AppDelegate registers PushKit voip and reports every voip push to CallKit before completing'`
   - Tier: unit/application (host regex pin, precedent `main_activity_onnewintent_pin_test.dart:22-62`).
   - Shape/setup: read the concatenation of `ios/Runner/AppDelegate.swift` plus an explicit ALLOWLIST of new call files named in the test (e.g. `ios/Runner/CallKitBridge.swift` — name the actual files at execution; NEVER glob `ios/Runner/*.swift`, which would reintroduce the vacuous-pass risk); strip `//` line comments and `/* */` blocks from the Swift text before asserting (3-line preprocessing helper — commented-out wiring must not pass); assert contains `import PushKit`, `import CallKit`, `PKPushRegistry`, regex `desiredPushTypes\s*=\s*\[\s*\.voIP\s*\]`, `reportNewIncomingCall`; then extract the `didReceiveIncomingPushWith` function body and assert `indexOf(reportNewIncomingCall) < indexOf(completion()` **within that body** (ordering pin = the iOS-13 OS rule; ordering-pin precedent: `ios_push_project_config_test.dart:182-202`).
   - RED on HEAD because: grep `pushkit|callkit` over `ios/` = 0 hits — every `contains` fails.
   - GREEN asserts: all pins + ordering hold.
   - Mutation that re-reds: move `completion()` before `reportNewIncomingCall` (or drop the report) → ordering assertion RED; comment out `reportNewIncomingCall` → RED (comment-strip guard).
4. **VC-07-04** `test/core/services/ios_pushkit_callkit_pin_test.dart::'AppDelegate forwards voip token, CallKit actions, and audio-session activation over mknoon/callkit'`
   - Tier: unit/application (host regex pin).
   - Shape/setup: same file(s); assert contains `"mknoon/callkit"`, `didUpdate pushCredentials` (voip-token delegate), `CXAnswerCallAction`, `CXEndCallAction`, `CXSetMutedCallAction`, and `didActivate` + `audioSession` (provider audio-session delegate → the WebRTC-audio-start seam, the #1 flutter_webrtc/CallKit pain point).
   - RED on HEAD because: none of these symbols exist in `ios/` (grep = 0).
   - GREEN asserts: all pins present.
   - Mutation that re-reds: remove the `didActivate audioSession` forward (the classic silent-audio regression) → RED.
5. **VC-07-05** `test/features/call/infrastructure/ios_callkit_channel_test.dart::'voip token event invokes the registration callback'` / `::'answer, decline and mute events dispatch to handlers'` / `::'missing plugin degrades to no-op'` / `::'unknown native method is ignored without killing the channel'`
   - Tier: unit/application (host; `TestDefaultBinaryMessengerBinding` mock channel — precedent: the `mknoon/migration_keepalive` Dart seam tests).
   - Shape/setup: instantiate `IosCallKitChannel`; simulate native→Dart method calls (`voipTokenUpdated`, `incomingCallReported`, `answer`, `decline`, `setMuted`, `audioSessionActivated`); assert callbacks receive the payloads; simulate `MissingPluginException` on a Dart→native call → completes without throwing (Android/desktop degrade, pattern `migration_transfer_keep_alive.dart:59`); simulate an unrecognized native→Dart method name (native/Dart version skew) → handler returns null/logs without throwing AND subsequent known methods still dispatch.
   - RED on HEAD because: `lib/features/call/infrastructure/ios_callkit_channel.dart` does not exist — compile failure (documented RED: the capability is absent).
   - GREEN asserts: dispatch + degrade + skew-tolerance behaviors.
   - Mutation that re-reds: drop the `setMuted` dispatch case → assertion (b) RED; rethrow on unknown method → skew case RED.
6. **VC-07-06** `test/features/call/application/callkit_call_coordinator_test.dart::'CallKit answer/decline/mute drive the CallEngine and engine end reports back'` / `::'ring and answer flow events are emitted with callId'`
   - Tier: unit/application (host; `FakeCallEngine` implementing VC-05's landed engine seam + fake channel).
   - Shape/setup: coordinator wired to fakes; fire `incomingCallReported`→ assert flow event `CALLKIT_INCOMING_REPORTED` (with `callId`); fire `answer` → engine accept called + `CALLKIT_ANSWERED` emitted; `decline` → engine reject; `setMuted(true/false)` → engine mute toggles; engine emits call-ended → coordinator calls `channel.reportCallEnded(callId)` (CallKit UI must dismiss).
   - RED on HEAD because: coordinator file absent — compile failure.
   - GREEN asserts: full mapping + both flow events (the VC-00 metrics hooks: ring latency / answer latency, see Metrics Ownership).
   - Mutation that re-reds: remove the `reportCallEnded` back-call → engine-ended assertion RED.
   - Stop-if: VC-05's landed CallEngine surface differs from the assumed accept/reject/mute seam → adapt the **coordinator** (and this test's fake) to the landed surface; never edit the engine (VC-05 owns it). Replan if no compatible seam exists.
7. **VC-07-07** `test/features/push/application/register_push_token_use_case_test.dart::'registration passes the cached PushKit voip token through'` / `::'no voip token → legacy call shape'` / `::'voip-token-triggered re-registration is blocked under account migration'`
   - Tier: unit/application (host; existing test file's fake seams — `getTokenFn`, `getPlatformFn`, `accountMigrationNetworkGate`).
   - Shape/setup: inject a `getVoipTokenFn` returning a token → assert the captured `p2pService.registerPushToken` invocation carries `voipToken:` with that value; returning null → invocation carries no voip token (legacy shape); with `accountMigrationNetworkGate` returning false → result `accountMigrationBlocked`, zero service calls (rule 4: the voip path inherits the Move-feature gate because it flows through the SAME gated `registerPushToken`, `p2p_service_impl.dart:4905-4908`).
   - RED on HEAD because: `registerPushToken` has no voip parameter/plumbing — compile failure on the named-arg capture.
   - GREEN asserts: all three behaviors.
   - Mutation that re-reds: bypass the gate for the voip-triggered path (call the bridge directly) → blocked-case assertion RED.
8. **VC-07-08** `test/core/bridge/p2p_bridge_client_test.dart::'callP2PInboxRegisterToken includes voipToken only when provided'`
   - Tier: unit/application (host; existing FakeBridge JSON capture in that file).
   - Shape/setup: call with `voipToken: 'pk-tok'` → decoded request payload contains `'voipToken': 'pk-tok'`; call without → payload map **does not contain the key** (frame byte-compat discriminator: same OK result both ways, so the assertion is on the frame, not the result).
   - RED on HEAD because: no `voipToken` parameter exists (`p2p_bridge_client.dart:790-812`) — compile failure.
   - GREEN asserts: presence/absence contract.
   - Mutation that re-reds: always emit the key (empty string) → absence assertion RED.
9. **VC-07-09** `go-relay-server/voip_push_test.go::TestRelayNotificationClosure_VoipPushRequestShape`
   - Tier: Go host (relay).
   - Shape/setup: construct the voip client with a generated P-256 test key (in-test `ecdsa.GenerateKey`), call `buildVoipPushRequest(token, callInvitePayload)`; assert: method POST; URL path `/3/device/<token>`; headers `apns-push-type: voip`, `apns-topic: com.mknoon.app.voip`, `apns-priority: 10`, `apns-expiration` within `[now+25s, now+35s]` and derived from a named const `voipPushExpirySeconds = 30` asserted by value (deliberately ≤ `kCallOfferTtl` = 45 000 ms, VC-04 / lock L1 — a queued push must never outlive the offer); `authorization: bearer <jwt>` where the JWT header decodes to `alg=ES256, kid=<APNS_KEY_ID>` and claims `iss=<APNS_TEAM_ID>`; body JSON = `{"type":"call_invite","callId":...,"fromPeerId":...,"sentAtMs":...}` (`callId`/`sentAtMs` sourced from the `call_push_request` request fields; `fromPeerId` = the stream-authenticated caller — lock L2 seam); body size ≤ voip budget const (4096).
   - RED on HEAD because: `buildVoipPushRequest`/`voip_push.go` do not exist (grep `voip` = 0 hits) — compile failure.
   - GREEN asserts: full wire shape.
   - Mutation that re-reds: change `apns-push-type` to `alert` → header assertion RED.
9b. **VC-07-09b** `go-relay-server/voip_push_test.go::TestVoipPushSenderRoundTripAndStatusMapping`
   - Tier: Go host (relay; the REAL sender against an in-test TLS HTTP/2 server — closes the builder-only blind spot).
   - Shape/setup: `httptest.NewUnstartedServer` + `srv.EnableHTTP2 = true` + `srv.StartTLS()` (stdlib-only — no new dependency; `golang.org/x/net` is indirect-only in `go.mod` and stays that way); inject the server's cert/base URL into the voip client via a test-only seam; send through the real sender (not the recording fake); assert (a) the request arrives over HTTP/2 (`r.ProtoMajor == 2`) with the voip headers of VC-07-09 intact, (b) a 200 response increments `relay_voip_push_sent_total{result="success"}`, (c) 403 and 410 responses increment `result="error"` and log the APNs `reason` field from the response body.
   - RED on HEAD because: sender absent — compile failure.
   - GREEN asserts: the HTTP/2 leg itself + status→result mapping (a sender that builds perfect requests but fails against Apple — h2 not negotiated, non-200 mapped to success — can no longer be all-green).
   - Mutation that re-reds: map non-200 to `result="success"` → RED.
10. **VC-07-10** `go-relay-server/voip_push_test.go::TestRelayNotificationClosure_VoipTokenRegistrationAndPreservation`
    - Tier: Go host (relay; in-process `HandleInboxStream` or store-level, matching `push_token_registration_test.go` style).
    - Shape/setup: `register_token` with `token=fcm1, platform=ios, voipToken=vp1` → entry holds both; re-register `token=fcm2` WITHOUT voipToken (FCM refresh) → `Token==fcm2` AND `VoipToken==vp1` **preserved**; legacy frame (no field at all) on a fresh peer → entry has empty VoipToken and status OK (HEAD contract intact).
    - RED on HEAD because: `tokenEntry` has no `VoipToken` field (`inbox.go:85-90`) — compile failure.
    - GREEN asserts: store + preserve + legacy behaviors.
    - Mutation that re-reds: make re-registration overwrite the whole entry (drop the preserve logic) → preservation assertion RED. *(Invariant-re-verification blind-spot row: the token-refresh transition must not destroy voip state.)*
11. **VC-07-11** `go-relay-server/voip_push_test.go::TestRelayNotificationClosure_CallInviteVoipDispatch`
    - Tier: Go host (relay; injected recording voip sender + recording FCM `sender` seam `inbox.go:81`; requests issued over an in-process `HandleInboxStream` stream, `push_token_registration_test.go` style).
    - Shape/setup (lock L2 — the action, not the deposit, is the ring seam): callee A has `VoipToken` registered; issue `call_push_request{to: A, callId, sentAtMs}` with the wake gate at its shipped default (OFF) → recorded voip request count == 1 with `apns-push-type: voip` AND FCM sender call count == 0 (**distinct-path discriminator** — both paths would otherwise "push"; the header + which-sender-fired discriminate); callee B has NO VoipToken; `call_push_request` for B → voip count 0 (VC-06's FCM branch owns B — `// VC-06:` note in-test; before VC-06 lands the minimal handler answers without any send); `call_push_request` missing `callId` → voip count 0 + `result="missing_call_id"`; a durable `chat_message` deposit AND a stray `call_invite` deposit via `InboxStore.Store` for A → voip count 0 both (deposits never ring — VC-00 rule 5; HEAD stores call_invite silently, `extractChatPushMetadata` default `inbox.go:1055-1057`, and that stays true).
    - RED on HEAD because: `call_push_request` answers `{"status":"ERROR","error":"Unknown action: call_push_request"}` (default arm `inbox.go:2277`); voip symbols absent — compile failure on the seam.
    - GREEN asserts: all dispatch outcomes above.
    - Mutation that re-reds: also fire the voip send from the `InboxStore.Store` deposit path → deposit-case count assertion RED (one-ring-mechanism guard); route the action through the FCM sender too → FCM-count-0 assertion RED (double-push guard).
12. **VC-07-12** `go-relay-server/voip_push_test.go::TestVoipPushDisabledWithoutCredentials`
    - Tier: Go host (relay).
    - Shape/setup: construct the push service with APNs env unset → voip leg reports disabled; issue `call_push_request` for a voip-token callee → no send attempt; asserts `relay_voip_push_sent_total{result="voip_disabled"}` increments (COMMITTED observable — the metric, not a log grep; the boot log line is checked only by redeploy probe 5).
    - RED on HEAD because: symbols absent — compile failure.
    - GREEN asserts: credential-gated degrade (mirrors FCM `inbox.go:108-117` "push disabled" pattern; this IS the kill-switch resting state, rule 3).
    - Mutation that re-reds: send anyway when disabled (nil-client deref path) → RED.
13. **VC-07-13** `go-relay-server/voip_push_test.go::TestVoipPushRespectsWakeTokenGate`
    - Tier: Go host (relay; force `wakeTokenGateEnforced=true` via the test seam used by `wake_token_store_test.go:59-66`).
    - Shape/setup: gate forced ON; callee has a registered wake-token set; `call_push_request` carrying an unauthorized `wakeToken` (additive `omitempty` request field — exported as a VC-06 interface note, Dependency Impact) → voip send count 0; with the authorized token → count 1. (The shipped default — gate OFF, no wake token, send proceeds — is VC-07-11's first case; this test owns only the forced-ON pair.)
    - RED on HEAD because: no voip dispatch exists — compile failure; the decision this test locks (calls obey the same "only contacts can wake you" gate as ordinary pushes — digest claim-4 nuance A demands the plan state this) has no code on HEAD.
    - GREEN asserts: gate parity with the ordinary push condition (`inbox.go:1307-1316`).
    - Mutation that re-reds: exempt the voip branch from the gate condition → unauthorized-case RED.
14. **VC-07-14** `go-relay-server/voip_push_test.go::TestRelayNotificationClosure_UnregisterClearsVoipToken`
    - Tier: Go host (relay).
    - Shape/setup: register fcm+voip; `unregister_token` action → subsequent lookup finds NO entry (and specifically no lingering voip token); issue `call_push_request` → zero voip sends. Asserts what is REMOVED (voip token, alert token, wake tokens per `inbox.go:2171-2174`) and what is PRESERVED (other peers' entries).
    - RED on HEAD because: `VoipToken` field absent — compile failure.
    - GREEN asserts: destructive action clears the voip addressability (blind-spot: destructive-action side-effects).
    - Mutation that re-reds: make unregister clear only the FCM token → post-unregister dispatch RED.
15. **VC-07-15** `go-relay-server/metrics_test.go::TestVoipPushMetricRegistered` (extend existing file)
    - Tier: Go host (relay).
    - Shape/setup: assert `relay_voip_push_sent_total` is registered with a `result` label and increments on the success/disabled paths (existing `metrics_test.go` name/label style).
    - RED on HEAD because: metric absent — compile/lookup failure.
    - GREEN asserts: metric name + labels (`success`, `error`, `voip_disabled`, `missing_token` minimum).
    - Mutation that re-reds: remove the increment on the send path → counter-value assertion RED.
16. **VC-07-16** `go-relay-server/backend_redis_test.go::TestRedisTokenStoreRoundTripsVoipToken` (extend existing file, existing redis-test harness)
    - Tier: Go host (relay, redis backend serialization).
    - Shape/setup: register entry with VoipToken through the redis token store → read back → VoipToken intact; entry written by an old binary (no field) → reads back with empty VoipToken, no error (forward-compat).
    - RED on HEAD because: field absent — compile failure.
    - GREEN asserts: durable round-trip both directions.
    - Mutation that re-reds: drop the field's serialization tag → round-trip RED.
17. **VC-07-17** `go-mknoon/node/inbox_voip_token_test.go::TestVoipTokenFrameAdditive` + `go-mknoon/bridge/bridge_test.go::TestInboxRegisterTokenVoipTokenPassthrough`
    - Tier: Go host (go-mknoon).
    - Shape/setup: (node) marshal the `register_token` `inboxRequest` with empty VoipToken → JSON contains NO `voipToken` key (byte-compatible legacy frame, NET-REL-07 — the exact `WakeToken` `omitempty` pattern `inbox.go:44-51`); with a value → key present. (bridge) `InboxRegisterToken(paramsJSON)` with `voipToken` set parses and threads it to the node call (assert via the bridge test file's existing node-seam style).
    - RED on HEAD because: `inboxRequest` has no VoipToken field; bridge params struct (`bridge.go:1372-1376`) has none — compile failure.
    - GREEN asserts: additive-frame contract at both layers.
    - Mutation that re-reds: drop `omitempty` → empty-frame assertion RED.
18. **VC-07-DR1** `integration_test/scripts/run_call_device_real.dart::vc07_ios_voip_pushkit_callkit_receipt` *(deferred-not-waived scenario entry — not a Dart test)*
    - Tier: device-proof (iOS; DEFERRED, macOS/iPhone session owns it).
    - Shape/setup: new scenario entry `vc07_ios_voip_pushkit_callkit_receipt` in the L5 call orchestrator `run_call_device_real.dart` (VC-05 creates it; create-if-absent honoring `--scenario all --list-scenarios`) whose dispatch prints the full recipe (Device/Relay Proof Profile below) and exits 0 without claiming proof (printer pattern: `run_1to1_device_real.dart:14-19`); plus the orchestrator's runner case in `check_reliability_simulation_discovery.sh` (sibling of the `run_1to1_device_real.dart` branch at `:247`).
    - RED on HEAD because: `--list-scenarios` does not print the id (verifiable: run the command — file absent or id missing, same RED).
    - GREEN asserts: id listed; `/sims 1to1 --list` shows the new slot.
    - Mutation that re-reds: remove the scenario entry → id absent from `--list-scenarios`.

**Preserved-green sentinels (locked, must stay green):**
- **P1** `ios_push_project_config_test.dart::'Info.plist includes fetch and remote-notification background modes'` — additive modes keep it green.
- **P2** `ios_push_project_config_test.dart::'Runner.entitlements keeps production aps-environment'` — no entitlement change.
- **P3** relay suites `push_payload_closure_test.go` / `protocol_contract_test.go` / `push_token_registration_test.go` / `forbidden_field_classifier_test.go` — no FCM shape/field change.
- **P4** = VC-07-02 (Podfile asymmetry lock).

---

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| VC-07-01 voip+audio modes exist (USER REQUIREMENT) | platform config pin | unit/app host | `test/core/services/ios_voip_background_modes_test.dart::'UIBackgroundModes array declares voip and audio'` | array at `Info.plist:86-89` lacks both | delete `<string>voip</string>` | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (classify_path core subdir, `run_test_gates.sh:870`; verify via `completeness-check`) |
| VC-07-02 mic-only Podfile asymmetry | config pin (green sentinel) | unit/app host | same file::'Podfile compiles PERMISSION_MICROPHONE only…' | n/a — green lock of deliberate asymmetry | add `PERMISSION_CAMERA=1` → RED | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core subdir) |
| VC-07-03 PushKit registered; every voip push reported to CallKit BEFORE completion (OS rule) | native wiring + ordering pin | unit/app host | `test/core/services/ios_pushkit_callkit_pin_test.dart::'AppDelegate registers PushKit…before completing'` | grep pushkit/callkit in ios/ = 0 | reorder completion before report | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core subdir) |
| VC-07-04 token/action/audio-session forwarding pinned | native wiring pin | unit/app host | same file::'AppDelegate forwards voip token, CallKit actions, and audio-session activation…' | symbols absent | remove `didActivate audioSession` forward | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core subdir) |
| VC-07-05 Dart channel dispatch + no-op degrade + unknown-method skew tolerance | channel wrapper logic | unit/app host | `test/features/call/infrastructure/ios_callkit_channel_test.dart::…` (4 tests) | class absent (compile) | drop setMuted dispatch case; rethrow on unknown method | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (features subdir glob) |
| VC-07-06 CallKit actions ↔ CallEngine + flow events | coordinator logic + metrics hooks | unit/app host | `test/features/call/application/callkit_call_coordinator_test.dart::…` (2 tests) | class absent (compile) | remove reportCallEnded back-call | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (features subdir glob) |
| VC-07-07 voip token rides the gated registration (rule 4) | use-case plumbing + Move gate | unit/app host | `test/features/push/application/register_push_token_use_case_test.dart::…` (3 cases) | no voip plumbing (compile) | bypass gate for voip path | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (features subdir glob) |
| VC-07-08 bridge frame carries voipToken only when present | frame byte-compat discriminator | unit/app host | `test/core/bridge/p2p_bridge_client_test.dart::'callP2PInboxRegisterToken includes voipToken only when provided'` | no param (compile) | always emit key | `./scripts/run_test_gates.sh 1to1` | file already in `ONE_TO_ONE_TESTS` array (`run_test_gates.sh:21`) — no action |
| VC-07-09 voip push wire shape (headers/topic/JWT/payload) | APNs request builder | Go host (relay) | `voip_push_test.go::TestRelayNotificationClosure_VoipPushRequestShape` | symbols absent (compile; grep voip=0) | apns-push-type→alert | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | AUTO in `run_relay_all_go_gate` (`run_test_gates.sh:865-868`, `all` gate); `TestRelayNotificationClosure_` name also runs it in the pinned `run_relay_notification_go_gate` regex (`:862`) inside `1to1`+`groups` gates |
| VC-07-09b real sender: HTTP/2 round-trip + status→result mapping | APNs sender leg (TLS/h2 + non-200 handling) | Go host (relay) | `voip_push_test.go::TestVoipPushSenderRoundTripAndStatusMapping` | sender absent (compile) | map non-200 to `result="success"` | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | AUTO in `run_relay_all_go_gate` (`all` gate) |
| VC-07-10 voip token stored; FCM refresh preserves it; legacy frame unchanged | token registry extension | Go host (relay) | `voip_push_test.go::TestRelayNotificationClosure_VoipTokenRegistrationAndPreservation` | `tokenEntry` lacks field (compile) | overwrite entry on refresh | same relay gate cmds | same (Closure-named → notification gate too) |
| VC-07-11 call_push_request + VoipToken → voip send, NOT FCM (L2 token-type dispatch); no token → silent here (VC-06's branch); deposits never ring (rule 5) | dispatch discriminator | Go host (relay) | `voip_push_test.go::TestRelayNotificationClosure_CallInviteVoipDispatch` | `Unknown action: call_push_request` (`inbox.go:2277`) + voip symbols absent (compile) | fire voip from the deposit path / also route through FCM → double-mechanism/double-push | same relay gate cmds | same (Closure-named) |
| VC-07-12 credentials absent → leg disabled (kill-switch rest state, rule 3) | env degrade | Go host (relay) | `voip_push_test.go::TestVoipPushDisabledWithoutCredentials` | symbols absent (compile) | send despite disabled | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | AUTO in `run_relay_all_go_gate` (`all` gate) |
| VC-07-13 voip push obeys wake-token gate when enforced | gate parity | Go host (relay) | `voip_push_test.go::TestVoipPushRespectsWakeTokenGate` | no voip dispatch (compile) | exempt voip branch from gate | same | AUTO in `run_relay_all_go_gate` |
| VC-07-14 unregister clears voip token (destructive side-effects) | token lifecycle | Go host (relay) | `voip_push_test.go::TestRelayNotificationClosure_UnregisterClearsVoipToken` | field absent (compile) | clear FCM only | same relay gate cmds | same (Closure-named) |
| VC-07-15 `relay_voip_push_sent_total{result}` metric | observability | Go host (relay) | `metrics_test.go::TestVoipPushMetricRegistered` | metric absent | remove increment | same | AUTO in `run_relay_all_go_gate` |
| VC-07-16 redis round-trip of VoipToken (+old-entry forward-compat) | durable backend | Go host (relay) | `backend_redis_test.go::TestRedisTokenStoreRoundTripsVoipToken` | field absent (compile) | drop serialization | same | AUTO in `run_relay_all_go_gate` |
| VC-07-17 additive voipToken frame through go-mknoon | client frame byte-compat | Go host (go-mknoon) | `node/inbox_voip_token_test.go::TestVoipTokenFrameAdditive` + `bridge/bridge_test.go::TestInboxRegisterTokenVoipTokenPassthrough` | no field/param (compile) | drop `omitempty` | `./scripts/run_host_test_gates.sh host-all` (new synthetic path: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -run 'VoipToken' -count=1)`) | **MANUAL**: add readonly `GO_CALL_VOIP_TOKEN_TEST` synthetic path + matcher + `print_command_for_path`/`run_path` branches in `run_host_test_gates.sh` (copy pattern `:144-184`, branches `:394`/`:431`); update the 4 gate docs (rule 6) |
| VC-07-DR1 on-iPhone PushKit→CallKit receipt (deferred-not-waived) | OS boundary, iOS | device-proof (DEFERRED) | `run_call_device_real.dart --scenario vc07_ios_voip_pushkit_callkit_receipt` (L5 call orchestrator) | id absent from `--list-scenarios` (file absent pre-VC-05 = same RED) | remove the scenario entry | `./scripts/check_reliability_simulation_discovery.sh` + `/sims 1to1 --list` shows slot | **MANUAL**: scenario entry in `run_call_device_real.dart` (create-if-absent to the L5 `--list-scenarios` contract) + runner case in `check_reliability_simulation_discovery.sh` (sibling of the `run_1to1_device_real.dart` branch at `:247`) |
| P1/P2 existing iOS config pins stay green | preservation | unit/app host | `ios_push_project_config_test.dart` (:28-45) | n/a (green) | remove fetch mode / entitlement | `./scripts/run_host_test_gates.sh feature-host-all` | already AUTO (features/push) |
| P3 FCM contract untouched | preservation | Go host (relay) | `push_payload_closure_test.go` + `protocol_contract_test.go` + `push_token_registration_test.go` + `forbidden_field_classifier_test.go` | n/a (green) | n/a (sentinel) | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | already AUTO (relay gates) |
| Regression floor | full suites | gate | existing suites | n/a | n/a | `./scripts/run_test_gates.sh 1to1` · `groups` · `baseline`; `./scripts/run_host_test_gates.sh feature-host-all` · `core-host-all` (capture green baselines at execution start — rule 6) | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the voip token is derived state on both ends. Client: PushKit re-delivers credentials on every launch registration and the `PushRegistrationCoordinator` re-registers — VC-07-07 asserts the cached voip token rides every (re-)registration, and VC-07-10 asserts a later FCM-refresh re-registration does not destroy the stored voip token. Relay restart: memory backend loses ALL push tokens today (pre-existing FDC-10 hazard, `server_bootstrap.go` durability scope) — voip tokens inherit it identically; redis durability locked by VC-07-16. No new client-side persistent state is introduced (the token cache is rebuilt by PushKit at launch by OS contract).
- **Sibling-surface consistency:** the token registry's parallel surfaces are `register_token` / `unregister_token` / redis-vs-memory backends. All three get rows (VC-07-10/14/16). The push-emission siblings (chat/reaction/group FCM paths, and the whole `InboxStore.Store` deposit seam) deliberately do NOT gain voip behavior — VC-07-11's deposit cases (`chat_message` AND stray `call_invite` → voip count 0) test-lock that asymmetry (deposits never ring — rule 5 / lock L2). The mic-vs-camera Podfile asymmetry is deliberate and test-locked (VC-07-02, VC-08 migrates).
- **Destructive-action side-effects:** `unregister_token` — VC-07-14 asserts what is removed (voip token → no more voip dispatch; alert token; wake tokens per the existing `inbox.go:2171-2174` behavior) and what is preserved (other peers' entries). Reuses the existing unregister path rather than adding a voip-specific one (no divergent copy).
- **Invariant re-verification under new transitions:** the new transition is *token refresh* (FCM rotates while a voip token exists) — VC-07-10's preservation assertion re-verifies voip addressability post-transition, and its mutation (whole-entry overwrite) is exactly the regression that would silently kill iOS ringing weeks later. Second new transition: *credentials appear/disappear on the relay* — VC-07-12 locks the disabled rest state; the enabled state is proven by VC-07-09/11 (injected sender) + the live-verification probe.

---

## Invariants (locked by tests)

- INV-1: `UIBackgroundModes` contains `voip` AND `audio` from this story forward → VC-07-01.
- INV-2: every voip push handler reports to CallKit before completing (OS rule) → VC-07-03 ordering pin (host proxy) + DR1 (device truth).
- INV-3: relay voip pushes carry `apns-push-type: voip`, topic `com.mknoon.app.voip`, priority 10, ES256 JWT auth → VC-07-09.
- INV-4: one peer, two addressable tokens — voip registration never clobbers the FCM alert token and vice versa → VC-07-10 (+ VC-07-16 durable form).
- INV-5: voip dispatch fires ONLY from `call_push_request` (lock L2 — the ONE ring mechanism) × VoipToken-present × (wake-gate satisfied when enforced; shipped default OFF sends); durable inbox deposits never ring (rule 5); never double-pushes via FCM; absent token = silent here (VC-06's FCM branch) → VC-07-11/13.
- INV-6: the voip leg is credential-gated OFF by default (kill-switch rest state) → VC-07-12.
- INV-7: legacy `register_token` frames (Dart→Go→relay) stay byte-compatible when no voip token exists → VC-07-08/17 + relay legacy case in VC-07-10.
- INV-8: voip registration honors `_allowsAccountNetworkSideEffects` (Move-feature gate, rule 4) → VC-07-07 blocked case.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan

0. **Preflight.** Snapshot `git status --short` (preserve the pre-existing dirty tree — do not revert/absorb/reformat it). Capture green baselines: `./scripts/run_test_gates.sh 1to1`, `groups`, `baseline`, `./scripts/run_host_test_gates.sh feature-host-all`, `core-host-all`, `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1)` — record counts (rule 6: never trust stale prose counts). Record `flutter analyze` baseline. **Collision check (VC-00 collision map):** confirm whether VC-06 has landed on this tree; if yes, rebase this plan's relay dispatch onto VC-06's call-push seam (VC-07 adds only the voip branch beside VC-06's FCM branch and migrates VC-07-11's no-token case to expect VC-06's FCM push). Verify VC-05's landed CallEngine seam + call feature-flag name, and RECORD the resolved flag name (VC-05's flag, else the `MKNOON_CALLS` dart-define fallback) in an Execution Progress row before step 6 — VC-07-05/06 setups must reference the resolved name. Confirm whether VC-05 created `run_call_device_real.dart` (lock L5) — if not, step 8 creates it. Re-verify every file:line anchor cited above (they drift).
1. **RED.** Author VC-07-01..17 (incl. 09b) + DR1 + P-locks exactly as cataloged. Seam-drift rule: if any GREEN slice invalidates a not-yet-green RED test's assumed seam (e.g. VC-05's CallEngine surface or the redis entry serialization differs from the plan's assumption), rewrite that RED test BEFORE its slice and record the delta in Execution Progress — never adapt production code to a stale RED. Run the RED commands (Acceptance Gates block) and record each failure reason against its "RED on HEAD because". Run `./scripts/run_test_gates.sh completeness-check` — the two new `test/core/services/` files and two new `test/features/call/` files must auto-classify (if `test/features/call/` is somehow unmatched by the generic feature-subdir glob at `run_test_gates.sh:1025-1030`, add the classify_path case — verify, don't assume).
2. **GREEN A — config lock.** Edit `ios/Runner/Info.plist` array (`:86-89`): add `<string>voip</string>`, `<string>audio</string>`. VC-07-01 green; P1 stays green.
3. **GREEN B — go-mknoon frame.** `node/inbox.go`: `inboxRequest` += `VoipToken` (omitempty, with a `// VC-07:` comment mirroring the WakeToken note); `Node.InboxRegisterToken` gains the voip param (internal signature — bridge is the only caller) and sets it in the frame (`:829-834`). `bridge.go` `InboxRegisterToken` params struct += `VoipToken` + threading. VC-07-17 green. Stop-if: any OTHER caller of `Node.InboxRegisterToken` exists (grep) → widen the audit before changing the signature.
4. **GREEN C — relay registry + voip leg.** `tokenEntry` += `VoipToken` with preserve-on-refresh logic in `RegisterToken` (explicit read-modify-write in both backends); `unregister_token` clears it; new `voip_push.go` (env config, ES256 JWT via stdlib `crypto/ecdsa` + `x509.ParsePKCS8PrivateKey`, `buildVoipPushRequest`, injectable sender, disabled-without-credentials state + boot log line `[PUSH] voip push: enabled|disabled (…)` next to `main.go:82-88`); voip dispatch branch in the `call_push_request` named handler (lock L2 — Real Scope item 6: the action hits the default arm `inbox.go:2277` on HEAD; create the minimal named handler if VC-06 hasn't landed, else add the voip token-type branch beside VC-06's FCM branch), applying the same wake-gate condition as `:1307-1316` when enforced, and NO voip behavior anywhere on the `InboxStore.Store` deposit path (rule 5); `metrics.go` += `relay_voip_push_sent_total{result}`. VC-07-09/09b..16 green. Stop-if: `HandleInboxStream`'s named-handler rule (nolint note `inbox.go:2027-2032`) — new logic in named funcs, not inline switch arms.
5. **GREEN D — Dart plumbing.** `callP2PInboxRegisterToken` += optional `voipToken`; `P2PService.registerPushToken` += optional named `voipToken` (update implementers: `p2p_service_impl.dart:4906` — inside the existing `_allowsAccountNetworkSideEffects` gate, no new gate call needed — and `test/shared/fakes/fake_p2p_service_integration.dart:268` + any other implementer the compiler surfaces); `register_push_token_use_case.dart` += injectable voip-token source wired to the CallKit channel's cached token. VC-07-07/08 green.
6. **GREEN E — Dart CallKit surface.** `ios_callkit_channel.dart` + `callkit_call_coordinator.dart` (bind to VC-05's CallEngine seam; emit `CALLKIT_INCOMING_REPORTED` / `CALLKIT_ANSWERED` flow events with `callId`). Gate init behind VC-05's call flag (step-0 finding). VC-07-05/06 green.
7. **GREEN F — native iOS.** PushKit + CXProvider wiring in `ios/Runner/` per the pin catalog (VC-07-03/04 green). AVAudioSession strategy (decision + justification): **custom platform channel, NOT callkeep** — flutter_callkeep-family packages are thinly maintained, assume AppDelegate ownership that collides with this repo's UIScene `FlutterSceneDelegate` (`Info.plist:75-76`) + `FirebaseAppDelegateProxyEnabled=false` FCM workaround (`AppDelegate.swift:90,148-165`), and the repo convention is bespoke MethodChannels. The known risk we accept: we own the CallKit/AVAudioSession state machine ourselves — specifically, WebRTC audio must start only inside `provider(_:didActivate audioSession:)` (starting earlier is the #1 flutter_webrtc+CallKit silent-audio failure). Mitigation: the `didActivate` forward is pin-locked (VC-07-04), the coordinator exposes it to VC-05's engine, and DR1's recipe includes an explicit two-way-audio-after-background-answer check. Note: native compile of the new Swift cannot be verified in the Android-only rig (no macOS toolchain) — `flutter build ios` is step 1 of the DR1 recipe; the pins keep the wiring from silently vanishing meanwhile.
8. **GREEN G — orchestrator entry.** Add the DR1 scenario + recipe printer to `run_call_device_real.dart` (create the orchestrator to the L5 `--scenario all --list-scenarios` contract if VC-05 hasn't landed it — step-0 finding) + its runner case in `check_reliability_simulation_discovery.sh` (sibling of `:247`). Run `./scripts/check_reliability_simulation_discovery.sh` (must list it; zero-expansion = FAIL) and `/sims 1to1 --list` (slot visible).
9. **Registration hardening.** Add the `run_host_test_gates.sh` synthetic Go path for the go-mknoon voip-token tests (pattern `:144-184`; branches at `:394`/`:431`; `GOTOOLCHAIN=go1.25.0`); update `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` together (rule 6's 4-doc rule). Verify: `./scripts/run_host_test_gates.sh host-all --list | grep -i voip`.
10. **Mutation verification.** Apply each cataloged mutation, observe the named test re-RED, revert.
11. **Gates + hygiene.** Full Acceptance Gates block; `flutter analyze` (0 new vs step-0 baseline); `git diff --check`.
12. **EC2 redeploy + live verification** (next section). Stop-if: another VC story's relay change is un-deployed on this tree → coordinate one-story-per-deploy (rule 2 / collision map); never ship a combined untested binary.

---

## Risks And Edge Cases

| Hazard | Pinned by |
|---|---|
| PushKit delegate wiring collides with the UIScene/FCM-proxy-disabled AppDelegate workarounds (digest gap) | VC-07-03/04 pins keep both surfaces present; DR1 recipe step asserts FCM alert pushes still arrive after PushKit wiring (regression check on P1's runtime behavior) |
| Silent audio on background answer (WebRTC started outside CallKit's `didActivate`) | VC-07-04 pin + DR1 recipe step 5 (two-way audio after lock-screen answer) |
| voip token clobbers FCM token (or vice versa) on refresh | VC-07-10 (+16 durable) |
| Double push (voip + FCM) for one call_invite | VC-07-11 FCM-count-0 discriminator |
| Calls wake non-contacts once the wake-token gate flips on | VC-07-13 gate parity |
| Relay memory backend loses voip tokens on bounce | pre-existing FDC-10 hazard, inherited knowingly; redis path locked by VC-07-16; noted for VC-09's reliability pass |
| APNs credential handling (p8 on EC2) is a new secret | env-file pattern mirrors `FIREBASE_SERVICE_ACCOUNT` (README unit); provisioning marked NEW in the redeploy section; leg is fail-closed without it (VC-07-12) |
| Ring-trigger seam ambiguity (wake deposit vs dedicated action) | RESOLVED by lock L2: the ONE ring mechanism is the caller-side `call_push_request` action with token-type dispatch; `call_*` is never durable-inboxed (rule 5) — the "TTL'd wake deposit via inbox" alternative is REJECTED (recorded in Accepted Differences). VC-07-11 pins both halves: action → voip send; deposits → never ring |
| Go 1.26 quic-go panic | every Go invocation pinned `GOTOOLCHAIN=go1.25.0` (rule 6) |
| VC-05's CallEngine surface drift | VC-07-06 stop-if: adapt coordinator, never the engine |

---

## Device/Relay Proof Profile

**Host-only closes:** the config locks, Dart channel/coordinator, frame plumbing, and the relay voip contract (VC-07-01..17) — plus the rule-2 live relay verification below.
**Requires device (deferred-not-waived — VC-00 rule 1, no iOS hardware in this rig):** the on-iPhone PushKit receipt, CallKit ring UI, lock-screen answer, and audio-session activation.

**PROD-CRITICAL leg:** the end-to-end wire leg — *deployed relay emits a voip push that a real iPhone receives, reports to CallKit, and answers into VC-05 audio* — is **VC-07-DR1**. Do NOT treat the host/Go unit coverage as sufficient on its own for the ring plane; host-green closes this story's code, DR1 closes the OS boundary.

Closure scenario command (recipe printer, exits 0): `dart run integration_test/scripts/run_call_device_real.dart --scenario vc07_ios_voip_pushkit_callkit_receipt -d <iosUdid,androidSerial>` (L5 call orchestrator; also visible via `/sims 1to1 --list`).

**Deferred device recipe (the macOS/iPhone session executes; printed verbatim by DR1):**
1. macOS with Xcode + this branch; `cd ios && pod install`; `flutter build ios` (first native compile proof of the Swift added here); run on a physical iPhone (PushKit voip pushes do NOT work on simulators) signed with a provisioning profile carrying the push entitlement (`aps-environment` — already in `Runner.entitlements:5-6`; no voip-specific entitlement exists).
2. Launch once; verify `[CALLKIT_DIAG]` logs the PushKit token and the app registers it with the deployed relay (relay `journalctl` shows the register_token with voipToken; flow event `P2P_INBOX_REGISTER_TOKEN_REQUEST`).
3. From the Android USB device (adb serial via `adb devices -l`), place a call (VC-05 flow) to the iPhone account while the iPhone app is **terminated**.
4. EXPECT: iPhone shows the CallKit incoming-call UI from the terminated state (voip push receipt + `reportNewIncomingCall`). Record `relay_voip_push_sent_total{result="success"}` increment + the send-timestamp log line.
5. Answer from the lock screen → two-way audio (audio-session activation path) → mute/unmute via the CallKit UI → hang up (CallKit UI dismisses via `reportCallEnded`).
6. Measurement runsheet (Metrics Ownership): repeat the terminated-state call **5 times**; per run compute **ring latency** = CallKit-report device timestamp − relay voip-send log timestamp, and **answer→two-way-audio latency** = first two-way audio − `CALLKIT_ANSWERED`. A run is invalid (replace it) if the push was throttled/downgraded — check `apns-priority` in the relay send log. Record all samples + medians in a RESULTS doc in this directory. **Pass/fail (committed here — the VC-00 metrics-table row has no repo-derived number, so this plan owns the threshold):** median ring latency ≤ 5 s AND median answer→two-way-audio ≤ 2 s; exceeding either = DR1 **FAIL** — file a VC-09 blocker, do not close. The raw `CALLKIT_ANSWERED` − `CALLKIT_INCOMING_REPORTED` interval includes human reaction time — record it unthresholded for VC-09 aggregation.
7. Regression: send an ordinary 1:1 message to the iPhone → FCM alert notification still arrives (PushKit wiring did not break the alert path).

Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (see `/sims`).

---

## EC2 Redeploy & Live Verification  (VC-00 rule 2 — restated: this story touches go-relay-server and is NOT done until the rebuilt relay is redeployed to `mknoun.xyz` / 13.60.15.36 and a live verification gate passes)

Canonical procedure (grounded: `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md:141-150`; systemd unit `relay-server`, `go-relay-server/README.md:1-39`). One landed story per deploy (collision map — coordinate with VC-01/VC-03/VC-06 relay changes; whichever lands second rebases).

```bash
# 0) Pre-deploy: full relay suite green + version bump (main.go:25) recorded
cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1

# 1) Cross-compile
cd go-relay-server && GOOS=linux GOARCH=amd64 go build -o relay-server-linux-amd64 .

# 2) Keep a rollback artifact ON the box BEFORE installing (NEW — explicit rollback step)
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo cp /usr/local/bin/relay-server /tmp/relay-server.rollback'

# 3) Ship + install + restart
scp -i ../se.pem relay-server-linux-amd64 ubuntu@mknoun.xyz:/tmp/relay-server
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /tmp/relay-server /usr/local/bin/relay-server && sudo systemctl restart relay-server && systemctl is-active relay-server && /usr/local/bin/relay-server version'
#    → expect: active + the bumped version string

# 4) APNs credential provisioning (NEW — operator step, undocumented in repo; requires Apple Developer access)
#    Obtain an APNs auth key (.p8, VoIP-capable), place it on the box, and set the env in a systemd drop-in:
#      sudo mkdir -p /etc/mknoon/apns && sudo cp AuthKey_<KEYID>.p8 /etc/mknoon/apns/ && sudo chmod 600 /etc/mknoon/apns/AuthKey_<KEYID>.p8
#      sudo systemctl edit relay-server   # add:
#        [Service]
#        Environment=APNS_AUTH_KEY_PATH=/etc/mknoon/apns/AuthKey_<KEYID>.p8
#        Environment=APNS_KEY_ID=<KEYID>
#        Environment=APNS_TEAM_ID=<TEAMID>
#      sudo systemctl restart relay-server
#    If credentials are NOT yet obtainable, the deploy still lands with the leg fail-closed (VC-07-12);
#    the credential step transfers to the DR1 macOS/iPhone session's prep list. Deferred, not waived.

# 5) Live verification probes (honestly scoped: Go-test-level + deployed-state observability;
#    a real voip push to a real iPhone is DR1's step 4 — no iOS device in this rig, rule 1)
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 120 --no-pager | grep -iE "PUSH|VOIP"'
#    → expect the new boot line: "[PUSH] voip push: enabled (topic com.mknoon.app.voip)"  (or "disabled (no APNs credentials)" pre-step-4)
ssh -i ../se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep relay_voip_push_sent_total'
#    → expect the metric family registered on the deployed binary
#    Register-path liveness: relaunch the app on the Android USB device (adb devices -l → serial) so it
#    re-registers its push token against the live relay, then:
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 60 --no-pager | grep -i "register"'
#    → expect register_token accepted (legacy frame — proves NET-REL-07 back-compat of the additive field live)

# 6) Rollback (if any probe fails)
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /tmp/relay-server.rollback /usr/local/bin/relay-server && sudo systemctl restart relay-server && /usr/local/bin/relay-server version'
#    (committed ~51MB linux binaries in go-relay-server/ are the deeper rollback artifacts)
```

On-box inspection caveat (digest gap): actual prod env (RELAY_BACKEND, TLS terminator, security groups) is unverifiable from the repo — record `systemctl cat relay-server` output in Execution Progress before editing anything on the box.

---

## Metrics Ownership  (VC-00 metrics table — VC-07's share of the "Ring latency (push sent→ring shown), answer latency" row, iOS half)

| Metric | Instrument | Locked/measured by |
|---|---|---|
| voip push sent (count by result + send timestamp) | `relay_voip_push_sent_total{result}` + `[PUSH]` voip send log line | VC-07-15 (named test) + redeploy probe 5 |
| ring shown (iOS) | native `[CALLKIT_DIAG] reportNewIncomingCall` log + Dart flow event `CALLKIT_INCOMING_REPORTED{callId}` | VC-07-06 (named test asserts emission); device timestamp captured in DR1 step 6 (measurement-runsheet step) |
| answer latency (iOS) | `CALLKIT_ANSWERED{callId}` − `CALLKIT_INCOMING_REPORTED{callId}` flow events (force-on via `--dart-define=FDC_FLOW_LOG=1`, `lib/main.dart:320-330`) | VC-07-06 (emission test); DR1 step 6 computes the number |
| ring latency end-to-end (push sent→ring shown) | relay send log timestamp → device report timestamp | DR1 step 6 (measurement-runsheet step; macOS/iPhone session records into a RESULTS doc here) |

Committed thresholds (DR1 pass/fail — decided in this plan; no repo-derived number exists in the VC-00 metrics table): over DR1 step 6's 5-run runsheet, median ring latency (relay voip-send → CallKit report) ≤ 5 s AND median answer→two-way-audio ≤ 2 s; a breach fails DR1 and files a VC-09 blocker.

Android-half ring metrics belong to VC-06; VC-09 closes the aggregation loop.

---

## Working Piece On Close

A self-contained, buildable-on capability: (1) the app's iOS target declares `voip`+`audio` background modes, **test-locked** so no future change can silently drop the user requirement; (2) the deployed EC2 relay understands dual-token peers and emits spec-correct `apns-push-type: voip` pushes on the `com.mknoon.app.voip` topic — Go-test-proven shape/dispatch/degrade, live-verified deployed state (version, boot log, metric family, live register back-compat); (3) the full PushKit→CallKit→CallEngine wiring exists end-to-end in code — native pins locked, Dart channel + coordinator unit-tested green at host tier, voip token riding the existing gated registration path; (4) a machine-discoverable deferred-not-waived recipe (`/sims 1to1` slot) hands the final iPhone evidence to a macOS session with concrete pass criteria and the ring/answer-latency measurement runsheet. VC-08 (video) and VC-09 (reliability/metrics closure) can build directly on this without reopening any VC-07 surface.

---

## Acceptance Gates  (LITERAL — copy/paste; rule 6: capture green baselines at execution start, never trust stale counts)

```bash
# RED (before production edits) — each must FAIL for the documented reason
flutter test test/core/services/ios_voip_background_modes_test.dart            # FAIL: voip/audio absent from UIBackgroundModes
flutter test test/core/services/ios_pushkit_callkit_pin_test.dart              # FAIL: no PushKit/CallKit symbols in ios/
flutter test test/features/call/infrastructure/ios_callkit_channel_test.dart   # FAIL: class absent (compile)
flutter test test/features/call/application/callkit_call_coordinator_test.dart # FAIL: class absent (compile)
flutter test test/features/push/application/register_push_token_use_case_test.dart --plain-name 'voip'   # FAIL: no voip plumbing
flutter test test/core/bridge/p2p_bridge_client_test.dart --plain-name 'voipToken'                        # FAIL: no param
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run 'Voip' -count=1)          # FAIL: symbols absent (compile)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -run 'VoipToken' -count=1) # FAIL: fields absent (compile)
dart run integration_test/scripts/run_call_device_real.dart --scenario all --list-scenarios | grep vc07  # empty on HEAD (file absent pre-VC-05 = same RED)

# Direct GREEN (after implementation) — same commands, all pass; plus:
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)             # full relay suite, 0 fail
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1)         # 0 fail

# Preservation sentinels (expected counts = the step-0 captured baselines)
./scripts/run_test_gates.sh 1to1        # baseline captured at execution start (00-INDEX plan-253 row cites ~1,672 — verify, don't trust)
./scripts/run_test_gates.sh groups      # baseline captured at execution start
./scripts/run_test_gates.sh baseline    # baseline captured at execution start
./scripts/run_host_test_gates.sh feature-host-all   # 0 fail
./scripts/run_host_test_gates.sh core-host-all      # 0 fail
flutter test test/features/push/application/ios_push_project_config_test.dart  # P1/P2 stay green

# Harness-registration verification (no invisible tests)
./scripts/run_test_gates.sh completeness-check                    # new *_test.dart files all classify
./scripts/check_reliability_simulation_discovery.sh               # DR1 scenario listed, non-zero expansion
./scripts/run_host_test_gates.sh host-all --list | grep -i voip   # new synthetic Go path present
dart run integration_test/scripts/run_call_device_real.dart --scenario all --list-scenarios | grep vc07_ios_voip_pushkit_callkit_receipt

# EC2 live verification (rule 2 — see the dedicated section for the full block)
ssh -i se.pem ubuntu@mknoun.xyz '/usr/local/bin/relay-server version && journalctl -u relay-server -n 120 --no-pager | grep -iE "PUSH|VOIP" && curl -s localhost:2112/metrics | grep relay_voip_push_sent_total'

# Hygiene
flutter analyze            # 0 new vs step-0 baseline (scripts/check_flutter_analyze_baseline.sh)
git diff --check
```

---

## Known-Failure Interpretation

- **Expected RED:** every command in the RED block above, for the documented reasons (config absence, symbol absence/compile failure, missing scenario id). A compile-failure RED is the documented RED for new-symbol tests.
- **Pre-existing dirty tree:** the step-0 `git status --short` snapshot (this branch already carries many unrelated modifications, incl. `go-mknoon/node/inbox.go` and relay test files) — preserve, never revert/absorb.
- **Environment blockers (NOT product):** no macOS/Xcode → `flutter build ios` and all DR1 steps deferred (recipe owns them); no iOS device (rule 1) → DR1 deferred-not-waived; APNs credentials not yet provisioned → relay leg correctly reports disabled (VC-07-12 locks that as the designed rest state); no live redis → VC-07-16 runs against the repo's existing redis-test harness only (`redis_failover_integration_test.go`'s `-tags integration` live half stays out of scope).
- **Scope drift (BLOCKING):** any failure in Android manifest/gradle tests, FCM payload-closure tests, `forbidden_field_classifier_test.go`, or group/feed suites — VC-07 must not change FCM shapes, Android config, or any envelope grammar. Investigate before proceeding.
- If VC-07-11's no-voip-token case observes an FCM call push: VC-06's FCM branch landed first — expected (collision map / lock L2 token-type dispatch); keep the voip-count-0 assertion, migrate the FCM expectation with a `// VC-06:` note per step 0.

---

## Done Criteria

- [ ] RED catalog authored first; every test failed on HEAD for its documented reason (recorded in Execution Progress).
- [ ] Mutation-verified: each cataloged mutation applied → named test re-RED → reverted.
- [ ] Direct GREEN + preservation sentinels + named gates pass at the step-0 baselines; P1–P4 green.
- [ ] `UIBackgroundModes` contains voip+audio and VC-07-01 locks it (the USER REQUIREMENT is test-locked).
- [ ] Harness registration verified in gate runs: completeness-check green; discovery script lists DR1; synthetic Go path visible in `host-all --list`; 4 gate docs updated together (rule 6).
- [ ] EC2 relay rebuilt, redeployed, live-verified (version + voip boot log + metric family + live legacy register), rollback artifact staged; one-story-per-deploy honored.
- [ ] DR1 deferred-not-waived recipe registered and printed; macOS/iPhone session handoff recorded (owner + prep list incl. APNs credential step if still pending).
- [ ] OS-boundary honesty: no claim of on-device PushKit/CallKit proof anywhere; host pins clearly labeled proxies.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations; dirty tree preserved.
- [ ] No migration (no DB change in this story) — N/A recorded, not skipped.

---

## Scope Guard (hard "Do not")

- Do NOT touch `android/` — manifest permissions, FGS types, full-screen intent, and their pin tests belong to **VC-06**.
- Do NOT add `PERMISSION_CAMERA=1` or any camera/video surface — **VC-08** (VC-07-02 is the canary).
- Do NOT define or alter `call_*` envelope grammar, TTL, glare, or idempotency — **VC-04**; VC-07 consumes the `"call_invite"` type string only.
- Do NOT edit CallEngine internals or `flutter_webrtc` wiring — **VC-05**; the coordinator adapts to the landed seam.
- Do NOT change FCM payload construction (`buildPushMessage`), the strict-fallback whitelist (`inbox.go:745-772`), `extractChatPushMetadata`, or any FCM `data` fields — the FCM call push is **VC-06**'s; VC-07's voip dispatch lives in the `call_push_request` named handler (lock L2), never on the deposit path.
- Do NOT touch `go-mknoon/node/feature_flags.go` / the `p2p_bridge_client.dart` flag map / their polarity pins (VC-01/VC-02 collision files) — VC-07's client gating rides VC-05's flag or a Dart-only dart-define.
- Do NOT register the plan in `Test-Flight-Improv/00-INDEX.md` (rule 7 — feature subdirs are not indexed).
- Do NOT deploy a relay binary carrying another story's unlanded relay changes (rule 2 / collision map).
- Do NOT claim device proof from host pins; do NOT flip any call feature flag default ON in this story.

---

## Accepted Differences / Intentionally Out Of Scope

- **"TTL'd wake deposit via inbox" ring alternative REJECTED** (lock L2 / VC-00 rule 5): `call_*` is never durable-inboxed; the ONE ring mechanism is the caller-side `call_push_request` action with token-type dispatch (FCM high-priority data push for Android — VC-06; APNs voip push for iOS PushKit tokens — this story). An earlier draft of this plan hung the voip dispatch off the inbox-deposit seam; that trigger is rejected and test-locked out by VC-07-11's deposit cases.
- **`call_push_request` for a callee without a voip token stays silent in this story** — VC-06 owns the FCM call push that covers Android and voip-less iOS clients; deliberate, test-locked by VC-07-11's zero-send assertion with a `// VC-06:` migration note.
- **No new entitlement** — voip pushes require only the existing push entitlement (`aps-environment`, `Runner.entitlements:5-6`); asserted by keeping P2 green rather than adding a new entitlement pin.
- **Native Swift behavior is pin-locked, not host-executed** — the rig has no macOS toolchain; text/regex pins (the repo's established platform-config drift pattern) + DR1 carry it. Accepted as the strongest honest host-tier lock available.
- **APNs client is stdlib-only** (no `sideshow/apns2`-style dep) — smaller supply-chain surface; cost: we own ~100 lines of JWT/HTTP2 code, fully covered by VC-07-09/12.
- **App Store review narrative** for the new background modes — excluded by the brief; flag for the release owner.
- **Wake-token durability for voip tokens under the memory backend** — inherited FDC-10 hazard, not fixed here.

---

## Dependency Impact

- **Depends on VC-05 (must land first):** the CallEngine seam VC-07-06 binds to, the `lib/features/call/` feature dir, the flutter_webrtc pod (whose `RTCAudioSession` symbols the native audio-session forwarding compiles against), and the call feature flag gating client init.
- **VC-06 (sibling, phase 3):** owns the `call_push_request` action (lock L2; exported shape `{action,to,callId,sentAtMs,envelope?}`, caller = stream-authenticated peer), its per-peer rate limit, and the Android FCM branch; VC-07 owns the voip token-type branch in the same named handler — whichever lands second rebases (VC-06 stubs `call_ios_deferred` for iOS; VC-07 stubs the minimal handler for the reverse order). Interface notes exported to VC-06: the additive `wakeToken,omitempty` request field (VC-07-13) and the `result="missing_call_id"` no-send behavior (VC-07-11). Each story ends with its OWN relay redeploy + live verification. VC-06 also owns the Android manifest pin tests (VC-07 deliberately does not double-lock Android config) and migrates VC-07-11's no-voip-token silence into an FCM call push.
- **VC-04:** owns the call envelope grammar, `kCallOfferTtl` = 45 000 ms (lock L1 — VC-07's `voipPushExpirySeconds = 30` deliberately sits under it so a queued push never outlives the offer), and the rule-5 fast-path-only semantics. The former open question ("TTL'd wake deposit vs dedicated call-wake action") is CLOSED by lock L2: `call_push_request` is the one ring mechanism; VC-07's registry/sender/CallKit surfaces are trigger-agnostic and its dispatch branch lives in that action's handler.
- **VC-08 (depends on this):** flips the Podfile camera macro (migrates VC-07-02) and reuses the CallKit surface for video calls.
- **VC-09 (depends on this):** consumes `CALLKIT_*` flow events + `relay_voip_push_sent_total` for the quality-metrics closure; owns the aggregation loop.
- **Relay deploy train:** VC-01 (limits) / VC-03 (TURN) share `main.go` wiring — one landed story per redeploy.
- No migration, no schema change, no l10n.

---

## Reviewer Findings
/tdd-review 2026-07-13 — dimension scores: goal-clarity 84 (strong), compartmentalization 78 (strong), anti-drift 82 (strong), define-good 80 (strong), goal-verification 75 (strong). 0 material, 5 moderate, 8 nit findings; all 13 applied (no declines):
- **Moderate applied:** (1) DR1 latency measurement upgraded to a 5-run runsheet with medians and COMMITTED pass/fail thresholds (ring ≤ 5 s, answer→two-way-audio ≤ 2 s; breach = DR1 FAIL + VC-09 blocker); (2) step-1 seam-drift rule added (rewrite stale RED tests before their slice, never bend production code to a stale RED); (3) the voip payload's `callId`/`sentAtMs` source pinned — the `call_push_request` request fields, `fromPeerId` = stream-authenticated caller, `result="missing_call_id"` on absence (adapted from the original stored-envelope wording to the L2 action seam); (4) DR1/define-good single-shot smell closed by the same 5-run runsheet; (5) NEW VC-07-09b real-sender test (stdlib `httptest` TLS HTTP/2 round-trip + status→result mapping) closes the builder-only APNs blind spot.
- **Nits applied:** step-0 records the resolved call-flag name before slice E; Execution Progress gains per-slice GREEN A–G rows; VC-07-12's observable committed to the metric (not log grep); VC-07-03/04 pin an explicit Swift file allowlist (never glob) + comment-stripping preprocessing + comment-out mutation; `apns-expiration` tolerance pinned (`[now+25s, now+35s]`, named const `voipPushExpirySeconds = 30` ≤ `kCallOfferTtl` per lock L1); VC-07-11 gains the shipped-default (gate OFF → send) case; VC-07-05 gains the unknown-native-method skew-tolerance case.
- **Cross-plan contract locks applied:** L2 — the voip push rides the caller-side `call_push_request` action with token-type dispatch (VC-06 owns the action + FCM branch; VC-07 owns the voip branch); ALL former `InboxStore.Store` deposit-trigger wording reworked (Real Scope 6, VC-07-11/12/13/14, invariants, risks, scope guard); the wake-deposit alternative recorded as REJECTED in Accepted Differences. L1 — voip push expiry tied under `kCallOfferTtl` = 45 000 ms. L5 — DR1 re-homed from `run_1to1_device_real.dart` to the epic call orchestrator `integration_test/scripts/run_call_device_real.dart` (create-if-absent to the `--scenario all --list-scenarios` contract) + discovery runner case at `check_reliability_simulation_discovery.sh:247` sibling. New anchors source-verified: `inbox.go:2277` (Unknown action default), `:2027-2032` (named-handler rule), `:1307-1316` (wake gate), `golang.org/x/net` indirect-only in `go-relay-server/go.mod` (hence stdlib `httptest.EnableHTTP2`), discovery runner case region `:238-256`.

## Arbiter Decision
Structural blockers: none. | Deferred details: on-iPhone PushKit/CallKit receipt, lock-screen answer, audio-session activation, and the 5-run latency runsheet remain deferred-not-waived to the macOS/iPhone DR1 session (VC-00 rule 1 — no iOS hardware in this rig); APNs credential provisioning remains an operator step (leg fail-closed until then, VC-07-12); native Swift compile deferred to DR1 step 1 (`flutter build ios`). | Accepted differences: "TTL'd wake deposit via inbox" ring trigger REJECTED per lock L2 (recorded above); voip-less callees stay silent here (VC-06's FCM branch); native Swift behavior pin-locked not host-executed; stdlib-only APNs client; App Store narrative excluded; memory-backend token loss inherited (FDC-10).

## Final Execution Verdict
Verdict: (pending) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner):
