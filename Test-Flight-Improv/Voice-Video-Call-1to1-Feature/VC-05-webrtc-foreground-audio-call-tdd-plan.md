# VC-05 — flutter_webrtc foreground 1:1 audio call  (New Feature)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — VC-00 story-map row VC-05 (`Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md:70`), grounded in the VC epic decision record (media plane = flutter_webrtc, signaling = VC-04 `call_*` envelopes, NAT = VC-03 STUN/TURN).

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | 4 grounding digests (platform-av-push, signaling-messaging, relay-server-ops, harness-conventions) + re-verified anchors: `pubspec.yaml:48-63`, `incoming_message_router.dart:171-286`, `p2p_service_impl.dart:555,2404`, `mic_permission_gateway.dart:20-53`, `mic_permission_prompt.dart:17`, `record_audio_recorder_service.dart:20-26`, `flow_event_emitter.dart:6,10,202-218`, `send_chat_message_use_case_test.dart:655`, `run_test_gates.sh:21,870,1036,1218`, `check_reliability_simulation_discovery.sh:236-256`, `run_1to1_device_real.dart:1-30`, `android/app/build.gradle.kts` (no minify/proguard in release) | anchors verified on `new-orbit`; flutter_webrtc confirmed ABSENT from pubspec | plan authoring |
| 2026-07-13 | Planner | (this file) | VC-05 runs on VC-03 + VC-04 **committed trees** — their contract names below are re-verified at execution start | reviewer |
| 2026-07-13 | Reviewer (sufficiency) | plan + gap JSON + cross-plan locks L1/L3/L5/L7 + `run_test_gates.sh:21,556,568`, `flow_event_emitter.dart:6`, `main.dart:320-330`, VC-00-roadmap.md:123 | 1 material (mute/speaker fake-only) + 3 moderate + 8 nit gaps — all applied; locks L1/L3/L5/L7 applied (orchestrator renamed to `run_call_device_real.dart`, family-array appends adopted) | arbiter |
| 2026-07-13 | Arbiter | (this file) | structural blockers: none — accepted post /tdd-review | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | snapshot + preserve dirty tree; re-verify VC-03/VC-04 contract names on their committed trees | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | device proof (rule 1) | | orchestrator run + getStats evidence + metrics values | both directions bytes flowing | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Intent: VC-00 roadmap (`VC-00-roadmap.md`) — story row VC-05, decision record, collision map, the 7 non-negotiable rules. This plan restates and complies with **rule 1** (USB-Android + emulator execution environment), **rule 2** (not triggered — no `go-relay-server/` edits here; a live-TURN *precondition* gate replaces it, see "Relay Precondition"), **rule 3** (kill-switch: VC-05 consumes VC-04's call-signaling kill-switch for the UI entry point; it defines no new Go flag), **rule 4** (Move-feature gate: no new `P2PServiceImpl` network primitive is added; all network sends route through VC-03/VC-04 primitives that already call `_allowsAccountNetworkSideEffects` first-line, `lib/core/services/p2p_service_impl.dart:555-572`), **rule 6** (gate hygiene: every new `*_test.dart` classifies; counts are baseline-captured, never hardcoded).
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`.
- Numbering / index: VC plans live ONLY in this feature dir (VC-00 rule 7 — `00-INDEX.md` does not index feature subdirectories).
- **Dependency contracts (re-verify at execution start on the committed trees; the *capabilities* are fixed by those plans, the *identifier names* below are this plan's working names):**
  - **VC-03:** deployed relay serves STUN/TURN with ephemeral HMAC creds; app-side cred fetch primitive — **locked canonical names (cross-plan lock L3, VC-03 canonical, verbatim):** relay action `turn_credentials_get`, gomobile bridge command `turn:credentials` → `{urls, username, credential, ttlSeconds}` — gated per rule 4; a committed **live TURN allocation probe** gate exists in VC-03's Acceptance Gates.
  - **VC-04:** `call_*` envelope types (`call_invite/call_answer/call_candidate/call_hangup/call_busy`), fast-path-only (never durable-inboxed, never swept by the retrier — `PendingMessageRetrier` sweeps only messageRepo rows, `lib/core/services/pending_message_retrier.dart:279-299`), `callId` idempotency + offer TTL (**locked, cross-plan lock L1:** `kCallOfferTtl = 45000 ms`, VC-04-owned; the 30-60 s band is a design choice per Signal/Matrix precedent, NOT a repo-derived constraint), glare resolution, a `CallSession`/signaling stream surface in `lib/features/call/application/`, and a **busy seam** (a hook VC-05 supplies the "am I in an active call" answer to, so VC-04 replies `call_busy`). Ack semantics: `call_*` types take Go's **ack-first-then-emit** immediate-ack path (`go-mknoon/node/node.go:1854-1860`) — an in-stream ack proves delivery to the peer's Go node, NOT answer-side handling (VC-00 rule 5; VC-04 owns this contract, VC-05 must not treat `acked` as "callee saw it").

---

## Session Classification
**implementation-ready** — the CallEngine, guards, permission flow, UI, and metric emission are all host-testable behind injected seams (fake peer-connection factory, `FakeMicPermissionGateway`, fake signaling, flow-event capture). The wire/media leg closes ONLY via the two-party device proof (rule 1) — named PROD-CRITICAL below, on the rig this repo already uses (USB Android + Android emulator).

---

## Exact Problem Statement
mknoon has no voice calling. The VC epic's MVP cut is VC-03 → VC-04 → VC-05: after VC-03 (deployed STUN/TURN + ephemeral creds) and VC-04 (encrypted `call_*` signaling with glare/TTL/busy), the app still has **no media plane and no call UI** — nothing creates an `RTCPeerConnection`, nothing renders an incoming call, nothing captures microphone audio for a call. The JSON MethodChannel bridge cannot carry 50 pkt/s media and go-libp2p's WebRTC transport is datachannels-only (VC-00 decision record), so the media plane must be `flutter_webrtc`, which is verifiably absent from the dependency set (grep `webrtc` over `pubspec.yaml`+`pubspec.lock` = 0 hits; digest-verified).

Who experiences it: any two users wanting a real-time conversation; today their only option is voice *notes* (`RecordAudioRecorderService`, store-and-forward). Why now: VC-05 is the epic MVP closer — a real, demoable foreground audio call device↔emulator.

**What must improve:** a caller can start a 1:1 audio call; the foreground callee sees an incoming-call screen and can accept/decline; on accept, audio flows both directions through the deployed relay+TURN when direct paths fail; mute/speaker/hangup work; setup-time and ICE-pair-type metrics are captured; teardown leaks nothing.

**What must stay unchanged (→ preserved-green sentinels):** the 1:1 messaging pipeline (`./scripts/run_test_gates.sh 1to1` incl. the Go relay-notification gate), the unknown-type forward-compat contract of `IncomingMessageRouter` (`test/core/services/incoming_message_router_test.dart::routes unknown types to unknownMessageStream`), the voice-note recorder + mic-permission surfaces (`test/features/**` around `RecordAudioRecorderService`/`MicPermissionGateway`), the platform-config pin tests (`test/features/push/application/ios_push_project_config_test.dart` — VC-05 must NOT touch `UIBackgroundModes`; that is VC-07), and `test/core/services/android_build_configuration_test.dart` (no gradle edits).

---

## Root Cause (verify → refute confirmed)
New-feature "root cause" = verified absence of the capability, with the mechanism of each gap:
1. **No media stack:** `flutter_webrtc` absent (`pubspec.yaml`/`pubspec.lock` grep = 0; `lib/` grep = 0). pion webrtc bits in `go-mknoon/go.mod:105-126` are *indirect* libp2p deps — datachannel-only, not a media plane.
2. **No call feature dir pre-VC-04:** `lib/features/` has no `call/` on the pre-epic tree (digest claim 13); VC-04 creates `lib/features/call/{application,domain}` for signaling. VC-05 adds the engine + presentation on top.
3. **No mic-capture-for-RTC:** the only mic capture is `RecordAudioRecorderService` (`lib/core/media/record_audio_recorder_service.dart:20-26`, file-recording via `record` pkg) — unusable for live RTC; its **permission flow** (`MicPermissionGateway` `lib/core/permissions/mic_permission_gateway.dart:20`, tri-state `PermissionHandlerMicGateway` :36-53, shared `showMicPermissionDeniedPrompt` `lib/core/permissions/mic_permission_prompt.dart:17`, injected as const default into chat screens `conversation_wired.dart:270,:353`) is the reuse template.
4. **Manifest/permissions already sufficient for foreground audio:** `RECORD_AUDIO` declared (`AndroidManifest.xml:7`), `NSMicrophoneUsageDescription` present (`ios/Runner/Info.plist:56-57`), Podfile compiles `PERMISSION_MICROPHONE=1` (`ios/Podfile:96-111`). No FGS/full-screen-intent needed for *foreground-only* calls (those are VC-06).

**Refuted / do-NOT-re-introduce:**
- Do NOT resurrect the dormant LiveKit plans (`Voice-Video-Call-LiveKit-Feature/01+02`) — superseded for 1:1 scope by the VC-00 decision record; they also misspell the prod domain (`mknoon.xyz`; it is `mknoun.xyz`, `go-relay-server/server_config.go:61`) and predate the gate-registration cookbook (zero Acceptance Gates — harness digest).
- Do NOT treat a `call_*` send's `acked=true` as callee-side handling — refuted ordering claim: immediate-ack types ack **before** the Dart emit (`node.go:1854-1860`); ringing/answer state advances only on VC-04's answer envelope.
- Do NOT route call media or signaling through the durable inbox / retrier — VC-00 rule 5; the fast-path-only seam is `P2PService.sendMessageWithReply` (`p2p_service_impl.dart:2404`), which VC-04 already uses.
- Do NOT plan TURN as optional because DCUtR exists — VC-00 decision record: DCUtR reduces TURN usage, it does not replace it.

---

## Real Scope
**In scope (VC-05):**
1. `pubspec.yaml`: add `flutter_webrtc` (working pin `^1.5.0` — pub.dev-verified and floors re-checked as step 2's FIRST action; record the resolved version) with a rationale comment (house convention: caret pins + numbered comment, cf. `record: ^5.1.0` :59, `permission_handler: ^11.3.1` :60). Consequences owned here: APK/AAB grows by the bundled per-ABI libwebrtc native libs (record the debug-APK size delta at execution — measurement step 12); release build currently has **no minify/proguard** (`android/app/build.gradle.kts` `buildTypes.release` sets only signing — verified), so no proguard edits are needed now; note for the future that flutter_webrtc ships consumer rules if minify is ever enabled. iOS: adds the WebRTC pod on `pod install` (deployment target 13.0 satisfies the plugin floor) — noted only; all iOS device work is **VC-07**. `minSdk=24` ≥ plugin floor. Merged-manifest check for `MODIFY_AUDIO_SETTINGS` (speakerphone) at execution — if the plugin manifest does not merge it, add it to the app manifest + a sibling file-reading pin test (precedent: `test/core/services/share_intent_android_test.dart:9-90`).
2. **CallEngine** (`lib/features/call/application/call_engine.dart`, new): RTCPeerConnection lifecycle wired to VC-04's `CallSession` + signaling streams; ICE servers from VC-03's cred fetch via an injected `IceServerProvider` seam; `iceCandidatePoolSize: 1` (pre-gathers one candidate to cut setup latency while never parking >1 unused TURN allocation per call — pooled candidates hold TURN allocations); `iceTransportPolicy` param (`all` default; `relay` for the forced-TURN proof); audio-only SDP (single audio m-line, Opus is the WebRTC audio default — asserted via m-line kind, not codec string matching); mute/unmute (local track `enabled`); speaker/earpiece via an injected `CallAudioRouting` seam (prod impl wraps `flutter_webrtc` `Helper.setSpeakerphoneOn`); **teardown order** (known flutter_webrtc leak class): stop local tracks → dispose local `MediaStream` → `close()` then `dispose()` the `RTCPeerConnection` → null out event handlers; idempotent.
3. **1:1-only guard:** engine reports busy to VC-04's busy seam while a call is active (incoming offer while active → `call_busy`, no second PC); outgoing start while active → rejected locally; assert single remote audio track — an unexpected second track or video track terminates the call with a protocol-violation event.
4. **Foreground in-call UI** (`lib/features/call/presentation/screens/`): `incoming_call_screen.dart` (caller identity, accept/decline — foreground only; ring/push is VC-06/07) and `active_call_screen.dart` (duration ticker, mute, speaker, hangup). CallKit/ConnectionService explicitly ABSENT (Scope Guard). Outgoing-call entry point honors VC-04's signaling kill-switch via an injected `callFeatureEnabled` provider (rule 3). The kill-switch also covers the INCOMING direction: an invite arriving while `callFeatureEnabled=false` renders no incoming screen and is declined via the busy/decline path (host-locked inside TC-VC05-03's group) — the incoming screen must subscribe through the engine, never directly to the signaling stream.
5. **Mic permission:** reuse `MicPermissionGateway` + `showMicPermissionDeniedPrompt` exactly as the voice-note precedent (`conversation_wired.dart:3620,:3639`); denied ⇒ call not answered/started, decline signaled, prompt shown; `test/shared/fakes/fake_mic_permission_gateway.dart` reused in tests.
6. **Metrics (VC-00 metrics-table rows owned here — the VC-05 share of "Call setup time (invite→connected), ICE pair type"):** flow events via `emitFlowEvent` (`lib/core/utils/flow_event_emitter.dart:202`): `CALL_INVITE_SENT`, `CALL_ICE_CONNECTED` (carries `setupMs` = invite→ICE-connected), `CALL_SELECTED_CANDIDATE_PAIR` (`{local, remote}` candidate types from `getStats()` selected pair). Loss/RTT/jitter/drop-cause rows are **VC-09**.
7. **e2e device proof (rule 1, PROD-CRITICAL):** `integration_test/call_audio_e2e_proof_test.dart` + orchestrator `integration_test/scripts/run_call_device_real.dart` — USB Android ↔ Android emulator full call through the DEPLOYED relay+TURN, `getStats` asserts ICE connected + audio bytes flowing BOTH directions + pair type recorded; clean teardown both sides; plus a forced-relay scenario (`iceTransportPolicy: relay`) proving media transits the VC-03 TURN server. Registered via classify_path + orchestrator `--scenario` per cookbook.

**Out of scope (owning story):** video (**VC-08**); background/killed ringing, push wake, FGS types, full-screen intent, CallKit/ConnectionService (**VC-06/VC-07**); ICE restart / network-switch survival, loss/RTT/jitter metrics, "always relay" privacy toggle (**VC-09**); TURN server internals, cred primitive, relay redeploy (**VC-03**); `call_*` envelope semantics, router cases, glare, TTL (**VC-04**); Bluetooth-headset audio routing (Accepted Differences).

---

## Files To Inspect Next
**Production (new unless marked):**
- `pubspec.yaml` (edit — dependency block :48-63 conventions)
- `lib/features/call/domain/models/call_state.dart` — call phase enum (`idle/dialing/ringing/connecting/active/ended`) + `ActiveCallInfo`
- `lib/features/call/application/call_engine.dart` — the engine; injectable seams: `PeerConnectionFactory` typedef (host tests inject a fake; prod = `createPeerConnection` from flutter_webrtc), `IceServerProvider` (VC-03 creds), `CallAudioRouting`, `MicPermissionGateway`, VC-04 signaling surface, `clock` for setup-ms
- `lib/features/call/application/call_audio_routing.dart` — speaker/earpiece seam (prod wraps `Helper.setSpeakerphoneOn`)
- `lib/features/call/presentation/screens/incoming_call_screen.dart`, `active_call_screen.dart`
- `lib/features/call/presentation/widgets/call_entry_button.dart` — kill-switch-gated outgoing-call affordance (conversation screen embeds it with a one-line diff)
- `lib/main.dart` (edit, minimal) — construct CallEngine near the router wiring (`main.dart:2597` area); collision-sensitive, keep the diff tiny

**VC-03/VC-04-owned, consumed not edited (re-verify names at execution start):** VC-04's `lib/features/call/application/` signaling/`CallSession` + busy seam; VC-03's cred fetch primitive.

**Dependency-only context (not edited):** `lib/core/permissions/mic_permission_gateway.dart:20-53`, `mic_permission_prompt.dart:17`, `lib/core/utils/flow_event_emitter.dart:6,10,202-218`, `lib/core/services/p2p_service_impl.dart:555-572,2404` (gate + fast-path seam), `lib/core/services/incoming_message_router.dart:171-286` (VC-04's cases; default→unknown at :264-270).

**Direct tests (new):** `test/features/call/application/call_engine_test.dart`, `test/features/call/application/call_metrics_test.dart`, `test/features/call/presentation/incoming_call_screen_test.dart`, `test/features/call/presentation/active_call_screen_test.dart`, `test/features/call/presentation/call_entry_button_test.dart`; device: `integration_test/call_audio_e2e_proof_test.dart`, `integration_test/scripts/run_call_device_real.dart`.

**Harness files (edit):** `scripts/check_reliability_simulation_discovery.sh` (two new classify_path cases + runner-expander dispatch); `scripts/run_test_gates.sh` (L5 appends only: `call_engine_test.dart` → `ONE_TO_ONE_TESTS` :21, `call_audio_e2e_proof_test.dart` → `NIGHTLY_ONLY_TESTS` :556) + the matching gate-doc trio (`test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md`).

---

## Existing Tests Covering This Area
- Calls are greenfield: **zero** existing call/webrtc tests (`grep -i 'webrtc|call_invite' test/ integration_test/` = 0 relevant hits; harness digest: `grep -i 'voip|call|webrtc|livekit' scripts/run_test_gates.sh` = only "callsite").
- `test/core/services/incoming_message_router_test.dart::routes unknown types to unknownMessageStream` (:256) — exists; preserved sentinel (VC-04 owns the call routing cases).
- Mic-permission precedent tests around `MicPermissionGateway`/`fake_mic_permission_gateway.dart` — exist; preserved (VC-05 reuses, does not edit).
- `test/features/push/application/ios_push_project_config_test.dart` (Info.plist background modes) + `test/core/services/android_build_configuration_test.dart` (gradle pins) — exist; preserved (VC-05 touches neither surface).
- Missing coverage gaps: everything in the RED catalog below (engine lifecycle, guards, teardown, permission-denied, metrics, UI, device media proof).
- Already in curated family arrays?: none yet — new `test/features/call/**` files auto-glob into `feature-host-all` and auto-classify in `run_test_gates.sh` classify_path (feature-subdir glob). **Cross-plan lock L5 (resolves the "CALL_TESTS family?" question — do not re-litigate):** NO new family array this epic; the headline call host suite (`test/features/call/application/call_engine_test.dart`) is APPENDED to `ONE_TO_ONE_TESTS` (`run_test_gates.sh:21`), and the heavy two-party e2e (`integration_test/call_audio_e2e_proof_test.dart`) is APPENDED to `NIGHTLY_ONLY_TESTS` (`run_test_gates.sh:556`); the device orchestrator is `integration_test/scripts/run_call_device_real.dart` honoring the `--scenario all` / `--list-scenarios` discovery contract (VC-08/VC-09 add their scenarios to this same script).

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> "HEAD" below = the tree with VC-03 and VC-04 **committed** (this plan's Stop-if). All application-tier tests drive `CallEngine` through a `FakePeerConnection`/`FakePeerConnectionFactory` (records ordered calls: `createOffer/setLocalDescription/addTrack/close/dispose/...`; exposes `onTrack/onIceCandidate/onIceConnectionState` injectors) + a fake VC-04 signaling surface + `FakeMicPermissionGateway`. Flow events captured with the local `captureFlowEvents` pattern (`send_chat_message_use_case_test.dart:655` precedent; sink seam `flow_event_emitter.dart:10,215`).

1. `test/features/call/application/call_engine_test.dart::TC-VC05-01 outgoing call: PC created with VC-03 ICE servers, pool size 1, offer sent, answer+ICE-connected reaches active`
   - Tier: unit/application
   - Shape/setup: `IceServerProvider` fake returns STUN+TURN uris + ephemeral creds; engine.startCall(peer); fake signaling loops back an answer; fire `onIceConnectionState(connected)`.
   - RED on HEAD because: `CallEngine` does not exist — the test file fails to load (`lib/features/call/application/call_engine.dart` missing).
   - GREEN after fix asserts: factory received `iceServers` == provider output AND `iceCandidatePoolSize == 1`; exactly one offer sent via signaling; state sequence `dialing→connecting→active`.
   - Mutation that re-reds: drop the `IceServerProvider` wiring (hardcode `[]`) → iceServers assertion RED; set pool size 0 → RED.
2. `call_engine_test.dart::TC-VC05-02 audio-only SDP: offer has exactly one m-line and it is audio; remote SDP with video m-line is rejected`
   - Tier: unit/application
   - Shape/setup: fake PC returns a canned SDP for `createOffer` per constraints; feed a remote description containing `m=video`.
   - RED on HEAD because: no engine → load failure; post-skeleton, no m-line guard exists.
   - GREEN asserts: offer constraints request audio only (no video track added, `offerToReceiveVideo` false/absent); remote video m-line ⇒ call terminated with `CALL_PROTOCOL_VIOLATION` flow event + teardown ran.
   - Mutation that re-reds: remove the m-line inspection → violation event absent → RED.
3. `call_engine_test.dart::TC-VC05-03 1:1 busy guard: incoming offer while active answers busy (no second PC); outgoing start while active rejected`
   - Tier: unit/application
   - Shape/setup: establish an active call; deliver a second incoming invite through the fake signaling; then attempt `startCall` to a third peer.
   - RED on HEAD because: no engine/busy wiring — VC-04's busy seam has no active-call answer source on HEAD.
   - GREEN asserts: busy seam invoked with the second invite's `callId` (VC-04 sends `call_busy`); `factory.createCount == 1`; `startCall` returns a busy/failed result without touching the active call's state.
   - Mutation that re-reds: remove the active-call check before answering the seam → `createCount == 2` → RED.
   - Distinct-event discriminator: asserts `CALL_BUSY_REJECT` fired AND NOT `CALL_INVITE_ACCEPTED` for the second `callId`.
   - Kill-switch-off case (same group, rule 3 incoming direction): with `callFeatureEnabled=false` and NO active call, an incoming invite surfaces NO incoming-call state (engine never enters `ringing`, no incoming-screen event emitted), is declined via the decline path, and creates no PC (`createCount == 0`). Mutation that re-reds: wire the incoming-screen trigger directly to the signaling stream (bypassing the engine gate) → ringing state observed while off → RED.
4. `call_engine_test.dart::TC-VC05-04 single-remote-track guard: unexpected second remote track terminates with protocol violation`
   - Tier: unit/application
   - Shape/setup: active call; fire `onTrack` a second time (audio) and separately with kind video.
   - RED on HEAD because: no guard exists.
   - GREEN asserts: call ends, `CALL_PROTOCOL_VIOLATION` event with `reason` distinguishing `extra_track` vs `video_track`; teardown ran once.
   - Mutation that re-reds: drop the remote-track counter → no termination → RED.
5. `call_engine_test.dart::TC-VC05-05 mute/unmute toggles the local audio track enabled flag; speaker toggle routes through CallAudioRouting`
   - Tier: unit/application
   - Shape/setup: active call with a fake local track; call `setMuted(true/false)`, `setSpeaker(true/false)`.
   - RED on HEAD because: methods absent.
   - GREEN asserts: `track.enabled` flips false/true; routing seam received ordered `[speakerOn, speakerOff]`; `CALL_MUTE_TOGGLED`/`CALL_SPEAKER_TOGGLED` events carry the new state.
   - Mutation that re-reds: invert the enabled polarity → RED; bypass the routing seam → RED.
6. `call_engine_test.dart::TC-VC05-06 teardown order: tracks stopped → local stream disposed → PC closed → PC disposed; hangup is idempotent; hangup signaled once`
   - Tier: unit/application
   - Shape/setup: active call; `hangUp()` twice; fake PC/stream record an ordered op log.
   - RED on HEAD because: no teardown exists.
   - GREEN asserts: ordered log exactly `[trackStop, streamDispose, pcClose, pcDispose]` (the known flutter_webrtc leak class is dispose-before-close / dangling tracks); second `hangUp` is a no-op (log unchanged, no second `call_hangup` signal); exactly one `call_hangup` sent; state `ended` then `idle`.
   - Mutation that re-reds: swap `pcDispose` before `pcClose` → order assertion RED; remove the idempotency latch → double `call_hangup` → RED.
7. `call_engine_test.dart::TC-VC05-07 post-hangup re-entry: busy latch cleared; a new incoming call is accepted end-to-end`
   - Tier: unit/application
   - Shape/setup: complete call #1 incl. hangup; deliver a fresh invite; accept.
   - RED on HEAD because: no engine; (post-skeleton this is the classic stale-busy-latch bug lock).
   - GREEN asserts: full post-transition state re-verified — busy seam NOT invoked for call #2, new PC created (`createCount == 2`), mic re-requested, state reaches `active`, mute defaults to false and speaker to earpiece (no state bleed from call #1).
   - Mutation that re-reds: skip clearing the active-call ref in teardown → call #2 answered busy → RED.
8. `call_engine_test.dart::TC-VC05-08 mic permission denied: accept does not create a PC, decline is signaled, deniedPermanently surfaces the settings prompt path`
   - Tier: unit/application
   - Shape/setup: `FakeMicPermissionGateway` (existing fake, `test/shared/fakes/fake_mic_permission_gateway.dart`) returns `denied` then `permanentlyDenied`; incoming invite; `accept()`; then (second case in the same group) `startCall()` outgoing under `denied`.
   - RED on HEAD because: no permission wiring.
   - GREEN asserts: accept path — `createCount == 0`, `call_hangup`/decline signaled for the invite's `callId`, engine reports a `micPermissionDenied` result the UI maps to `showMicPermissionDeniedPrompt` (widget-tier TC-VC05-12 locks the prompt itself); outgoing path — `startCall` under `denied` sends NO `call_invite`, creates no PC, returns the same `micPermissionDenied` result (sibling-surface parity: the gate guards both directions).
   - Mutation that re-reds: create the PC before the permission gate → `createCount == 1` on denied → RED.
9. `test/features/call/application/call_metrics_test.dart::TC-VC05-09 metrics: CALL_ICE_CONNECTED carries setupMs (invite→connected) and CALL_SELECTED_CANDIDATE_PAIR carries pair types from getStats`
   - Tier: unit/application
   - Shape/setup: `captureFlowEvents` wrapper; fake `clock` advances 1234ms between invite-send and ICE-connected; fake PC `getStats` returns a selected `candidate-pair` (local `relay`, remote `srflx`).
   - RED on HEAD because: events do not exist anywhere (`grep CALL_ICE_CONNECTED lib/` = 0).
   - GREEN asserts: `CALL_ICE_CONNECTED.details['setupMs'] == 1234`; `CALL_SELECTED_CANDIDATE_PAIR.details == {local:'relay', remote:'srflx'}`; both carry the truncated `callId` (flow-event id-hygiene convention).
   - Mutation that re-reds: stop calling `getStats` on connected → pair event absent → RED.
   - Distinct-event discriminator: asserts `CALL_ICE_CONNECTED` AND NOT `CALL_SETUP_FAILED` for the same `callId`.
10. `test/features/call/presentation/incoming_call_screen_test.dart::TC-VC05-10 incoming screen: renders caller, accept requests mic then answers, decline signals hangup and pops`
    - Tier: widget
    - Shape/setup: `WidgetTester` + `MaterialApp` wrap; fake engine records `accept/decline` calls; SYNC teardown for any IO.
    - RED on HEAD because: screen file absent.
    - GREEN asserts: caller name/id visible; accept → engine.accept invoked exactly once; decline → engine.decline + `Navigator.pop`.
    - Mutation that re-reds: wire decline to accept → RED.
11. `test/features/call/presentation/active_call_screen_test.dart::TC-VC05-11 active screen: duration ticks, mute/speaker toggle engine state, hangup ends and pops`
    - Tier: widget
    - Shape/setup: fake engine exposing state + a controllable duration stream; tap mute/speaker/hangup.
    - RED on HEAD because: screen absent.
    - GREEN asserts: duration text advances with pumped time; mute button reflects + toggles engine mute; speaker likewise; hangup calls `engine.hangUp` once and pops.
    - Mutation that re-reds: render duration from a widget-local stopwatch instead of engine state → controllable-stream assertion RED.
12. `test/features/call/presentation/incoming_call_screen_test.dart::TC-VC05-12 permanentlyDenied mic on accept shows the shared showMicPermissionDeniedPrompt (settings deep-link)`
    - Tier: widget
    - Shape/setup: fake engine returns `micPermissionPermanentlyDenied`; injected `FakeMicPermissionGateway` records `openAppSettings`.
    - RED on HEAD because: screen absent; no prompt wiring.
    - GREEN asserts: the shared dialog (`mic_permission_prompt.dart:17` helper — same one the chat screens use) appears; "Open Settings" hits `gateway.openAppSettings`; call is not answered.
    - Mutation that re-reds: replace the shared helper with a local toast → dialog finder RED (locks the "one helper, no drift" invariant the prompt file documents).
13. `test/features/call/presentation/call_entry_button_test.dart::TC-VC05-15 outgoing-call entry point hidden when the call feature gate is off`
    - Tier: widget
    - Shape/setup: `CallEntryButton` (new self-contained widget, `lib/features/call/presentation/widgets/call_entry_button.dart`, embedded by the conversation screen with a one-line diff — keeps flutter_webrtc-adjacent code inside `lib/features/call/`); injectable `callFeatureEnabled` provider (defaulting, in prod wiring, to VC-04's signaling kill-switch — name re-verified at execution start) set false/true.
    - RED on HEAD because: entry point absent.
    - GREEN asserts: gate off ⇒ no call affordance rendered; gate on ⇒ affordance present and routes to `engine.startCall`.
    - Mutation that re-reds: drop the gate check → affordance rendered when off → RED. (Rule 3 compliance lock.)
14. `call_engine_test.dart::TC-VC05-14 dispose() during an active call performs full teardown and signals hangup (app-lifecycle exit)`
    - Tier: unit/application
    - Shape/setup: active call; call `engine.dispose()` (the DI teardown path).
    - RED on HEAD because: no engine.
    - GREEN asserts: same ordered teardown as TC-VC05-06; one `call_hangup` sent; subsequent stream events are ignored (no post-dispose throw).
    - Mutation that re-reds: skip teardown in dispose → op log empty → RED.
15. `integration_test/call_audio_e2e_proof_test.dart::TC-VC05-13 [PROD-CRITICAL] two-party foreground audio call device↔emulator over deployed relay+TURN: ICE connected, audio bytes both directions, real-mic audio energy, mute plateau, speaker toggle, pair type recorded, clean teardown`
    - Tier: device-proof (`@Tags(['device'])`, real Go bridge, real relay `mknoun.xyz`, real VC-03 TURN)
    - Shape/setup: role via `--dart-define=CALL_E2E_ROLE=caller|callee`; peers pair through the real relay exactly as existing two-party device journeys do (copy `integration_test/scripts/run_direct_private_media_device_local_journey.dart` conventions — the repo's automated physical-Android + emulator precedent); caller invites, callee auto-accepts.
    - **Pinned measurement protocol (pass/fail is NOT executor-improvised):** poll `getStats` every 1 s; FAIL the scenario if ICE does not reach `connected/completed` within **90 s of invite-send** (callee auto-accepts immediately, so the VC-04 `kCallOfferTtl` 45 s unanswered-offer expiry never fires here; `setupMs` itself is recorded-only — VC-09 owns pass/fail latency thresholds). After connect, require `outbound-rtp` audio `bytesSent` AND `inbound-rtp` audio `bytesReceived` to increase across **≥3 consecutive 1 s samples spanning ≥5 s on BOTH parties** (emulator note: the emulator has a virtual mic loopback — assert bytes/packets, never audible sound). Selected-candidate-pair types captured into `CALL_SELECTED_CANDIDATE_PAIR` (recorded, NOT asserted, in this natural-path scenario — see the L7 punch-tolerance note in Risks).
    - **Real-audio discriminator (USB leg has a real microphone):** on the callee, additionally assert the inbound `track`/`media-source` stat `totalAudioEnergy` increases (or `audioLevel > 0` sampled at least once) during the media window for the stream originating from the USB device — a silence-capturing regression cannot pass on encoder byte counters alone.
    - **Mute window (device-tier proof that mute works on the real path):** after the bidirectional-bytes window, caller calls `setMuted(true)` → assert callee's `inbound-rtp` audio bytes plateau (delta ≈ 0, allowing comfort-noise/RTP-header slack) across ≥3 consecutive samples spanning ≥3 s, then resume strictly increasing after `setMuted(false)`.
    - **Speaker toggle (real `CallAudioRouting` impl executed on-device):** on the USB leg toggle `setSpeaker(true)` then `setSpeaker(false)` — assert no platform exception and `CALL_SPEAKER_TOGGLED` (both states) present in the run log; capture an `adb shell dumpsys audio` route snapshot into the run log as evidence (recorded, not asserted — audible-route assertion is not machine-checkable on this rig; see Accepted Differences).
    - Then caller hangs up; both sides assert state `ended→idle` and PC disposed (no dangling `RTCPeerConnection` — re-accepting a fresh call on the same process succeeds, reusing the TC-VC05-07 invariant on-device).
    - RED on HEAD because: the proof file does not exist; the capability does not exist. (Run RED once post-registration to prove the harness executes and fails for "no CallEngine", not for wiring.)
    - GREEN asserts: all of the above + prints `setupMs` and pair type (the metrics runsheet reads them from the run log — the test's own print is the primary source).
    - Mutation that re-reds: revert the teardown-order fix (dispose before close) → callee-side re-accept leg fails / stats keep flowing after hangup → RED on device; invert the mute polarity → callee inbound bytes keep increasing during the mute window → RED on device.
16. `integration_test/call_audio_e2e_proof_test.dart::TC-VC05-16 forced-TURN scenario: iceTransportPolicy relay ⇒ call still connects and the selected pair is relay/relay (media proven through VC-03's TURN)`
    - Tier: device-proof (same file; scenario selected via `--dart-define=CALL_E2E_FORCE_RELAY=true`, orchestrator scenario `vc05_forced_turn_relay_audio_call`)
    - RED on HEAD because: file/capability absent.
    - GREEN asserts: ICE connected with **both** local and remote selected candidates of type `relay`; audio bytes both directions under the same pinned measurement protocol as TC-VC05-13 (1 s polls, 90 s connect-or-FAIL, ≥3 consecutive increasing samples spanning ≥5 s on both parties); this is the live re-verification that VC-03's deployed TURN actually relays media, complementing the precondition probe.
    - Mutation that re-reds: point the `IceServerProvider` at a bogus TURN uri under forced-relay → connection fails → RED (proves the test cannot pass without the real TURN server).

---

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-VC05-01 engine lifecycle + ICE config | pure logic via factory seam | unit/app | `test/features/call/application/call_engine_test.dart::TC-VC05-01` | CallEngine absent (load failure) | hardcode empty iceServers / pool 0 | `./scripts/run_host_test_gates.sh feature-host-all` · `./scripts/run_test_gates.sh 1to1` | AUTO (glob `test/features/call/application/`) + auto-classifies in `run_test_gates.sh` classify_path (:870 feature-subdir) + **MANUAL: headline file appended to `ONE_TO_ONE_TESTS` (`run_test_gates.sh:21`) per cross-plan lock L5** |
| TC-VC05-02 audio-only SDP + m-line guard | SDP shape logic | unit/app | `…::TC-VC05-02` | no m-line guard exists | remove m-line inspection | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-03 busy guard both directions + kill-switch-off incoming decline | state guard + VC-04 seam + rule-3 incoming gate | unit/app | `…::TC-VC05-03` | no active-call answer source | drop active-call check → 2nd PC; bypass the engine gate for incoming-screen trigger | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-04 single-remote-track guard | protocol invariant | unit/app | `…::TC-VC05-04` | no track counter | drop counter | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-05 mute + speaker routing | track flag + routing seam | unit/app | `…::TC-VC05-05` | methods absent | invert polarity / bypass seam | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-06 teardown order + idempotent hangup | dispose-order invariant (leak class) | unit/app | `…::TC-VC05-06` | no teardown exists | swap close/dispose order; drop latch | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-07 post-hangup re-entry | latch-clear re-verification | unit/app | `…::TC-VC05-07` | no engine | skip clearing active-call ref | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-08 mic denied path | permission gate ordering | unit/app | `…::TC-VC05-08` | no permission wiring | create PC before gate | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-09 setup-ms + pair-type flow events | metrics emission | unit/app | `test/features/call/application/call_metrics_test.dart::TC-VC05-09` | events nonexistent (grep=0) | stop calling getStats on connected | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-10 incoming screen | UI wiring | widget | `test/features/call/presentation/incoming_call_screen_test.dart::TC-VC05-10` | screen absent | wire decline→accept | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob `presentation/`) |
| TC-VC05-11 active screen | UI wiring | widget | `test/features/call/presentation/active_call_screen_test.dart::TC-VC05-11` | screen absent | widget-local stopwatch | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-12 denied prompt reuse | shared-dialog invariant | widget | `incoming_call_screen_test.dart::TC-VC05-12` | no prompt wiring | replace shared helper with toast | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-15 entry-point kill-switch (rule 3) | flag gate | widget | `test/features/call/presentation/call_entry_button_test.dart::TC-VC05-15` | entry point absent | drop gate check | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-14 dispose-during-call lifecycle | lifecycle teardown | unit/app | `call_engine_test.dart::TC-VC05-14` | no engine | skip teardown in dispose | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-VC05-13 **PROD-CRITICAL** two-party audio call e2e (incl. mute plateau + speaker toggle + real-mic audio energy) | OS boundary + real media + multi-device + deployed relay/TURN | device-proof | `integration_test/call_audio_e2e_proof_test.dart::TC-VC05-13` | capability absent | revert teardown-order fix; invert mute polarity | `dart run integration_test/scripts/run_call_device_real.dart --scenario vc05_foreground_audio_call -d <usbSerial>,<emulatorSerial>` | **MANUAL ×4:** (a) classify_path case in `check_reliability_simulation_discovery.sh` → `record "1to1" … "test"`; (b) `run_test_gates.sh` classify_path auto-matches `*_proof_test.dart` (:1036, 'manual device-proof suite') + `@Tags(['device'])`; (c) orchestrator `--scenario` case + `--list-scenarios` contract + dart-define role dispatch; (d) file appended to `NIGHTLY_ONLY_TESTS` (`run_test_gates.sh:556`) per cross-plan lock L5 |
| TC-VC05-16 forced-TURN relay pair | real TURN media proof | device-proof | `integration_test/call_audio_e2e_proof_test.dart::TC-VC05-16` | capability absent | bogus TURN uri under forced relay | `dart run integration_test/scripts/run_call_device_real.dart --scenario vc05_forced_turn_relay_audio_call -d <usbSerial>,<emulatorSerial>` | same registration; second `--scenario` id + `CALL_E2E_FORCE_RELAY` dart-define case in the orchestrator |
| PRESERVE messaging + router forward-compat + platform pins | regression floor | gate | existing suites | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` · `baseline` · `./scripts/run_host_test_gates.sh feature-host-all` · `core-host-all` | already registered |
| PRESERVE registration hygiene (rule 6) | harness completeness | gate | n/a | n/a | n/a | `./scripts/run_test_gates.sh completeness-check` · `./scripts/check_reliability_simulation_discovery.sh` | the two new integration_test entries + orchestrator MUST classify or these FAIL |

No empty cells.

---

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** call state is deliberately in-memory only — no DB row, nothing to reconstruct on reopen (a killed app ends the call; background survival is VC-06). The lifecycle exit path is test-locked by **TC-VC05-14** (dispose-during-call ⇒ teardown + hangup signal) and re-entry by **TC-VC05-07**. Persisted-call-history rows: N/A by design (deferred; no VC story currently persists call logs — recorded in Accepted Differences).
- **Sibling-surface consistency:** the busy gate applies to BOTH directions (incoming-offer-while-active AND outgoing-start-while-active) — locked in **TC-VC05-03**. Mute/speaker exist only on the active-call screen; the incoming screen deliberately has neither (nothing to mute pre-answer) — deliberate asymmetry, noted here. The mic-permission gate applies to both accept (TC-VC05-08) and outgoing start (asserted inside TC-VC05-08's outgoing variant expectations in the same group).
- **Destructive-action side-effects:** hangup/teardown asserts **what is removed** (local tracks stopped, local stream disposed, PC closed+disposed, active-call ref cleared) AND **what is preserved** (signaling listeners stay alive for the next call — TC-VC05-07; conversation history untouched — no messageRepo interaction exists in the engine by construction, Scope Guard). **TC-VC05-06 + TC-VC05-14.**
- **Invariant re-verification under new transitions:** post-hangup re-entry re-verifies the full pre-call invariant set (busy latch cleared, fresh PC, mic re-requested, mute/speaker defaults reset) — **TC-VC05-07**; on-device re-accept leg inside **TC-VC05-13** re-verifies it with a real PC.

---

## Invariants (locked by tests)
- INV-1: ICE config always comes from the VC-03 provider (STUN+TURN + ephemeral creds), pool size 1 → TC-VC05-01.
- INV-2: exactly one audio m-line; any video/extra remote track terminates the call → TC-VC05-02/04.
- INV-3: at most one active call; concurrent invite answered busy via VC-04's seam → TC-VC05-03.
- INV-4: teardown order `trackStop → streamDispose → pcClose → pcDispose`, idempotent, exactly one `call_hangup` → TC-VC05-06/14.
- INV-5: no PC exists before mic permission is granted → TC-VC05-08.
- INV-6: setup-ms and selected-pair-type are observable flow events on every connected call → TC-VC05-09 (host) + TC-VC05-13/16 (real values).
- INV-7: the call entry point is kill-switch gated (rule 3) → TC-VC05-15.
- INV-8: the media leg is proven on real devices through the deployed relay+TURN, both directions, under the pinned measurement protocol (90 s connect-or-fail, ≥3 increasing samples over ≥5 s) → TC-VC05-13/16 (PROD-CRITICAL — unit coverage is NOT sufficient on its own).
- INV-9: mute verifiably stops remote inbound audio flow on the REAL path (callee inbound-rtp plateau) and the real `CallAudioRouting` impl executes on-device without error → TC-VC05-13 mute/speaker windows (host fakes alone never close these goal components).
- INV-10: the kill-switch gates BOTH directions — outgoing entry point hidden (TC-VC05-15) and incoming invite declined with no UI while off (TC-VC05-03 kill-switch-off case).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan
> **Stop-if (blocker):** VC-03 and VC-04 are **not both committed with green home gates**, or the Relay Precondition probe (below) fails, or VC-04's committed contract names differ so much that the busy/stream seams don't exist → replan against the real contracts; do not stub around a missing dependency. VC-04↔VC-05 collide on `lib/features/call/` and conversation routing (VC-00 collision map) — strictly sequential, VC-05 on VC-04's committed tree.

1. **Snapshot + contracts.** `git status --short` (preserve dirty tree); capture green baselines: `./scripts/run_test_gates.sh 1to1`, `baseline`, `./scripts/run_host_test_gates.sh feature-host-all`, `core-host-all`, `flutter analyze` count (rule 6: record counts now, never reuse stale ones). Read VC-03/VC-04 committed plans + code; record the real names of: cred-fetch primitive, signaling send/streams, busy seam, kill-switch flag. Run the Relay Precondition probes.
2. **Dependency.** FIRST verify the current stable `flutter_webrtc` version against pub.dev (`dart pub add flutter_webrtc --dry-run`, or tentative add + `dart pub outdated`): the `^1.5.0` pin below is a repo-unverified working value — pin whatever verifies, re-check that version's documented minSdk/iOS floors against minSdk 24 / iOS 13.0, and record the resolved version in Execution Progress. Then add `flutter_webrtc: ^<verified>` to `pubspec.yaml` (rationale comment per house style); `flutter pub get`; commit-scope includes `pubspec.lock`. Sanity: `flutter build apk --debug` succeeds; record APK size delta (step 12); check merged manifest for `MODIFY_AUDIO_SETTINGS` with the LITERAL command: `"$ANDROID_HOME"/build-tools/*/aapt dump permissions build/app/outputs/flutter-apk/app-debug.apk | grep -F android.permission.MODIFY_AUDIO_SETTINGS` (fallback: `aapt2 dump badging` same apk; never grep raw binary AXML via `unzip -p`) — if absent, add to `android/app/src/main/AndroidManifest.xml` + a sibling pin test (share_intent_android_test pattern). Stop-if: pub solver conflicts with the locked tree → resolve minimally, never downgrade existing pins.
   2b. **Feasibility spike (throwaway, NOT registered).** Before any host-test authoring: a scratch integration test or `flutter run` snippet on BOTH targets (emulator-5554 AND the USB device) that calls `getUserMedia({audio})` and connects a local loopback `RTCPeerConnection` pair, asserting nonzero outbound audio bytes via `getStats` on each target. Delete the spike afterwards (it must not classify). Stop-if it fails (plugin init, emulator virtual-mic loopback yields no frames on API 35, permission flow) → replan (emulator audio config / plugin version) BEFORE steps 3-10 — this front-loads the epic's biggest feasibility unknown instead of discovering it at step 11.
3. **RED.** Author TC-VC05-01..12, 14, 15 (host) exactly as catalogued, with `FakePeerConnection(Factory)`, fake signaling, `FakeMicPermissionGateway`, `captureFlowEvents`. Run `flutter test test/features/call/` → ALL fail for the documented reasons (load failure → then behavior-shaped once skeletons exist; re-run after each skeleton lands to keep reasons honest — record ONE re-run per implementation slice (steps 4-8) in Execution Progress showing that slice's tests fail for their documented BEHAVIORAL reason, not load failure, BEFORE writing that slice's production code). Also author the device-proof file + orchestrator SKELETONS (they must classify) — run `./scripts/run_test_gates.sh completeness-check` + `./scripts/check_reliability_simulation_discovery.sh` and make BOTH pass with the new classify_path cases in place (registration is part of RED, not an afterthought).
4. **Domain + engine skeleton.** `call_state.dart`; `call_engine.dart` with the injected seams (`PeerConnectionFactory`, `IceServerProvider`, `CallAudioRouting`, `MicPermissionGateway`, signaling surface, `clock`). Seam names are the exact ones the tests import. Make TC-VC05-01/02 green.
5. **Guards.** Busy both-directions + single-remote-track (TC-VC05-03/04 green). Wire the active-call answer into VC-04's busy seam.
6. **Controls + teardown.** Mute/speaker (TC-VC05-05), ordered idempotent teardown + dispose path (TC-VC05-06/14), re-entry (TC-VC05-07).
7. **Permission + metrics.** Mic gate ordering (TC-VC05-08); `CALL_*` flow events + getStats sampling on connected (TC-VC05-09).
8. **Presentation.** `incoming_call_screen.dart` + `active_call_screen.dart` + entry-point gate (TC-VC05-10/11/12/15 green). Minimal `main.dart` DI wiring (construct engine near `main.dart:2597` router area; smallest possible diff — collision-sensitive file).
9. **Device-proof implementation.** Fill `call_audio_e2e_proof_test.dart` (roles, relay pairing per `run_direct_private_media_device_local_journey.dart` conventions, the PINNED measurement protocol from TC-VC05-13 — 1 s getStats polls, 90 s connect-or-FAIL, ≥3 consecutive increasing samples spanning ≥5 s, mute plateau window, speaker toggle, totalAudioEnergy discriminator — both scenarios) + `run_call_device_real.dart` (locked L5 name; usage `--scenario all|vc05_foreground_audio_call|vc05_forced_turn_relay_audio_call -d <serialA,serialB> [--list-scenarios]`; `--list-scenarios` prints bare ids one per line — the discovery-expander contract; Android legs launched as `flutter test --no-pub integration_test/call_audio_e2e_proof_test.dart -d <serial>` + dart-defines, `Process.start('flutter', …)` per `run_group_multi_party_device_real.dart:241-253` conventions; `MKNOON_RELAY_ADDRESSES` default = app-default mknoun.xyz pair, `run_test_gates.sh:568`). Flow-log dependency (explicit): device legs run DEBUG builds, so `flowEventLoggingEnabled = kDebugMode` is on (`flow_event_emitter.dart:6`); if a profile-build variant is ever used, pass `--dart-define=FDC_FLOW_LOG=1` (`main.dart:320-330`) or the run log comes back empty.
10. **Registration verification (rule 6).** `./scripts/run_test_gates.sh completeness-check` green; `./scripts/check_reliability_simulation_discovery.sh` green and lists the orchestrator with 2 expanded scenarios; `/sims 1to1 --list` dry-run shows the new `--only N` slots. **Named-array appends (cross-plan lock L5):** `call_engine_test.dart` → `ONE_TO_ONE_TESTS` (`run_test_gates.sh:21`) and `call_audio_e2e_proof_test.dart` → `NIGHTLY_ONLY_TESTS` (:556) — these edit `readonly` arrays, so update the gate docs together with the append (`test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` — the same doc set VC-08 step 8 names for its own ONE_TO_ONE_TESTS append); no gate is renamed/removed and no new family is created.
11. **Device proof run (rule 1).** Per Execution Environment below: both scenarios green on USB device + emulator against the deployed relay+TURN. Record getStats evidence + `setupMs` + pair types in Execution Progress.
12. **Metrics runsheet.** From the two device-proof run logs record: setup ms (natural + forced-relay), selected pair types, debug-APK size delta from step 2 → append a "VC-05 measured values" note to this plan's Execution Progress (these are the VC-05-owned rows of VC-00's metrics table; VC-09 aggregates). The proof test's own printed `setupMs`/pair-type lines are the PRIMARY source (flow-event log lines are debug-build-gated, step 9 note). Sanity envelope: `setupMs` must be < the 90 s connect timeout for both scenarios; pair types non-empty, and `relay/relay` for the forced scenario — garbage values do not tick the metrics checkbox.
13. **Full gate set + hygiene + mutation re-verification.** Rerun direct → preservation → named gates (Acceptance Gates); re-apply each catalogued mutation and confirm re-RED; `flutter analyze` 0-new vs step-1 baseline; `git diff --check`.

---

## Execution Environment  (VC-00 rule 1 — the implementing agent runs this loop itself)

```bash
# 1. Discover the rig (canonical pair per repo policy: USB Pixel 6 21071FDF600CSC + AVD mknoon_play_35 at emulator-5554;
#    if unavailable, substitute the serials adb reports — record the substitution)
flutter devices --machine
adb devices -l          # expect: one USB serial (device), one emulator-5554 (emulator)
flutter emulators       # boot if needed: flutter emulators --launch mknoon_play_35

# 2. Host suites (no device)
flutter test test/features/call/

# 3. Single-leg device run (debugging a role in isolation)
flutter test --no-pub integration_test/call_audio_e2e_proof_test.dart -d 21071FDF600CSC \
  --dart-define=CALL_E2E_ROLE=caller --dart-define=MKNOON_RELAY_ADDRESSES="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

# 4. Two-party orchestrated proof (comma-separated -d, first id = caller leg on the USB device, second = callee on the emulator)
#    Caller on the USB device (real mic hardware + real radio path), callee on the emulator (virtual mic loopback —
#    the proof asserts bytes/packets via getStats, NEVER audible sound). For a different-network variant put the
#    USB device on cellular/hotspot (WiFi off) while the emulator NATs through the host — the forced-relay scenario
#    covers the relay pair type deterministically either way.
dart run integration_test/scripts/run_call_device_real.dart --list-scenarios
dart run integration_test/scripts/run_call_device_real.dart \
  --scenario vc05_foreground_audio_call -d 21071FDF600CSC,emulator-5554
dart run integration_test/scripts/run_call_device_real.dart \
  --scenario vc05_forced_turn_relay_audio_call -d 21071FDF600CSC,emulator-5554

# 5. /sims slots (runner, never a registrar)
./scripts/run_test_gates.sh reliability-sim 1to1 --list   # note the new --only N slots
```

iOS boundary: **none in VC-05** (iOS device work is VC-07). No deferred-not-waived rows needed here beyond noting that `pod install` consequences of the new pod are compile-verified in VC-07's rig, not this one.

---

## Risks And Edge Cases
- **flutter_webrtc teardown leak class** (dispose-before-close / dangling tracks keeps native threads alive) → pinned by TC-VC05-06/14 (ordered op log) + the on-device re-accept leg of TC-VC05-13.
- **Glare** (both sides dial simultaneously) → VC-04 owns resolution; VC-05's engine must only honor the resolved winner — covered by the busy/idle state machine tests; a dedicated glare e2e is VC-04's.
- **TURN cred expiry mid-setup** (ephemeral HMAC TTL) → engine fetches creds per call at `startCall`/`accept` (never caches across calls) — asserted inside TC-VC05-01/07 (provider called per call). Mid-call expiry does not break an established allocation (TURN semantics); ICE-restart-after-expiry is VC-09.
- **Emulator audio is a virtual loopback** → all audio assertions are getStats byte/packet counters, never audible checks (stated in TC-VC05-13; VC-00 rule 1 note).
- **Signaling ack ≠ callee handling** (immediate-ack types ack before Dart emit, `node.go:1854-1860`) → engine treats invite-send success as "sent", advances to ringing ONLY on VC-04's answer/ringing envelope → state-machine tests TC-VC05-01/03.
- **`main.dart` collision churn** (shared DI file across VC stories) → smallest-possible wiring diff; rebase expected (VC-00 collision map).
- **Speakerphone permission** (`MODIFY_AUDIO_SETTINGS`) may not merge from the plugin manifest → step-2 merged-manifest check + conditional pin test.
- **Device rig unavailability** → environment blocker, not product blocker (Known-Failure Interpretation); "N/A (target unavailable by project policy)" convention from plan 256 applies, but VC-05 CANNOT close without the device proof (PROD-CRITICAL) — it blocks closure, unlike optional targets.
- **HEAD punch tolerance (cross-plan lock L7):** on HEAD, `EnableHolePunching` is always on, and a held circuit plus observed public addresses can legitimately fire `holepunch:attempt` during the device proofs even before VC-02 lands. TC-VC05-13's natural-path scenario therefore RECORDS whatever selected pair type / punch events it observes and never fails on them — only VC-02 owns punch-outcome assertions; only the forced-relay scenario (TC-VC05-16) asserts pair type (`relay/relay`, which `iceTransportPolicy: relay` makes deterministic regardless of punching).

---

## Device/Relay Proof Profile
**Requires device for closure.** Host tiers close the engine/UI/permission/metrics contracts; the story closes ONLY when `vc05_foreground_audio_call` AND `vc05_forced_turn_relay_audio_call` pass on the USB-device + emulator rig against the deployed relay+TURN (rule 1). No fake stands in for the media leg (tier-matrix: OS-boundary/multi-device ⇒ device-proof is the closure gate, not optional).
Closure scenario: `/sims 1to1 --list` → note the new orchestrator slots → run via the orchestrator commands above (or `/sims 1to1 --only N`).
Deferred device work → **VC-07** owns all iOS device evidence (CallKit/PushKit rig).
Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (+ quic-v1 pair — both on the single `APP_DEFAULT_RELAY_ADDRESSES` line, `run_test_gates.sh:568`).

---

## Relay Precondition — Live TURN Verification (NO redeploy; VC-00 rule 2 not triggered)
VC-05 edits **zero** `go-relay-server/` files, so rule 2's rebuild/redeploy obligation does not apply. Instead VC-05 carries a **precondition gate**: VC-03's deployed TURN must be live before the device proofs run.

```bash
# P-1 (exists — ops conventions from the 142-plan redeploy runbook + relay README; ssh key ../se.pem, user ubuntu):
ssh -i se.pem ubuntu@mknoun.xyz 'systemctl is-active relay-server && /usr/local/bin/relay-server version'
#   expect: active + the version VC-03 deployed (record it)

# P-2 (NEW — written here because the repo has no TURN-probe runbook yet; grounded in metrics-on-:2112, main.go:229-236):
ssh -i se.pem ubuntu@mknoun.xyz "curl -s localhost:2112/metrics | grep -i turn | head -20"
#   expect: VC-03's TURN Prometheus metrics present (allocation counters); names per VC-03's committed plan

# P-3: re-run VC-03's committed live TURN allocation probe EXACTLY as written in VC-03's Acceptance Gates
#   (its literal command is owned by VC-03; copy it into Execution Progress when run). TC-VC05-16 (forced-relay
#   call) is this plan's own end-to-end re-verification through the same server.
```
Rollback note: none needed (no deploy from this story). If P-1..P-3 fail → VC-05 is **blocked on VC-03**; do NOT redeploy the relay from this session (one landed story per redeploy — VC-00 collision rule; redeploy is an explicit operator action, `173-…-tdd-plan.md:160` convention).

---

## Acceptance Gates  (LITERAL — copy/paste; counts: capture green baseline at execution start, never reuse stale numbers — VC-00 rule 6)
```bash
# 0. Baselines + preconditions (execution start)
git status --short                                   # snapshot; preserve dirty tree
./scripts/run_test_gates.sh 1to1                     # capture green baseline count (includes the GOTOOLCHAIN=go1.25.0-pinned relay-notification Go gate — no Go edits in VC-05, preservation only)
./scripts/run_test_gates.sh baseline                 # capture green baseline count
./scripts/run_host_test_gates.sh feature-host-all    # capture green baseline count
./scripts/run_host_test_gates.sh core-host-all       # capture green baseline count
flutter analyze                                      # record baseline issue count (dirty tree)
ssh -i se.pem ubuntu@mknoun.xyz 'systemctl is-active relay-server && /usr/local/bin/relay-server version'   # P-1

# 1. RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/call/                     # expect: ALL new tests FAIL (CallEngine/screens absent)

# 2. Direct GREEN (after implementation)
flutter test test/features/call/                     # expect: all TC-VC05 host tests pass

# 3. Preservation sentinels (must match step-0 baselines)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# 4. Registration hygiene (rule 6) — both must PASS with the new files present
./scripts/run_test_gates.sh completeness-check
./scripts/check_reliability_simulation_discovery.sh  # orchestrator listed, 2 scenarios expanded

# 5. Device proof (rule 1) — closure gate, PROD-CRITICAL
adb devices -l
dart run integration_test/scripts/run_call_device_real.dart --list-scenarios   # prints 2 bare ids
dart run integration_test/scripts/run_call_device_real.dart --scenario vc05_foreground_audio_call -d 21071FDF600CSC,emulator-5554
dart run integration_test/scripts/run_call_device_real.dart --scenario vc05_forced_turn_relay_audio_call -d 21071FDF600CSC,emulator-5554
#   expect (pinned protocol): ICE connected/completed within 90s of invite-send or the scenario FAILS
#   (setupMs recorded-only — VC-09 owns latency thresholds); 1s getStats polls; audio bytesSent/bytesReceived
#   increasing across >=3 consecutive samples spanning >=5s BOTH directions on BOTH parties; callee inbound
#   totalAudioEnergy increasing (real USB mic); mute window: callee inbound bytes plateau >=3s then resume;
#   speaker toggled on/off on the USB leg (no platform exception, CALL_SPEAKER_TOGGLED x2 in log, dumpsys
#   audio route snapshot recorded); pair types recorded (forced scenario asserts relay/relay; natural scenario
#   records only — holepunch events tolerated+recorded per lock L7, never a failure); clean teardown +
#   re-accept leg green; setupMs printed

# 6. Hygiene
flutter analyze            # 0 new vs step-0 baseline
git diff --check
```

---

## Known-Failure Interpretation
- Expected RED: every `test/features/call/**` test and the device proof before implementation (documented reasons in the catalog).
- Pre-existing dirty: the large `new-orbit` dirty tree snapshotted at step 0 — preserve, never revert/absorb/reformat (repo convention, plan 257 :751-756); analyzer baseline drift handled via `check_flutter_analyze_baseline.sh` comparison, baseline NOT rewritten.
- Environment blocker (NOT product): missing USB device/emulator, dead ssh key, VC-03 probe failure (blocks closure but is a dependency/ops blocker → escalate to VC-03, don't patch here).
- Expected-different: `completeness-check`/discovery FAIL between adding the new test files and adding their classify_path cases — close within step 3.
- Scope drift (BLOCKING): any failure in groups/feed/intro suites, any diff in `go-mknoon/`, `go-relay-server/`, `ios/Runner/Info.plist`, `AndroidManifest.xml` (beyond the conditional `MODIFY_AUDIO_SETTINGS` line), or `IncomingMessageRouter`.

---

## Working Piece On Close
A real, demoable **foreground 1:1 audio call** — the epic MVP: on the USB Android phone, tap the (kill-switch-gated) call button in a 1:1 conversation; the emulator's foregrounded app shows the incoming-call screen; accept → live audio flows both directions (proven via getStats byte counters plus a real-mic `totalAudioEnergy` discriminator, incl. a forced-TURN run through the deployed `mknoun.xyz` server); duration ticks; mute works and is device-proven (remote inbound audio verifiably plateaus while muted); hangup works; speaker/earpiece toggling executes the real routing impl on-device without error (with the audio route snapshot recorded — audible-route assertion is the one honest residual, see Accepted Differences); both sides tear down cleanly and can immediately place the next call. Setup-time and ICE-pair-type metrics are emitted as flow events and their first real measured values are recorded in this plan. VC-06 (ringing), VC-07 (iOS), VC-08 (video), and VC-09 (hardening/quality) all build directly on this engine + UI without rework.

---

## Done Criteria
- [ ] RED added first (incl. registered device-proof skeletons), each failed for the documented reason.
- [ ] Mutation-verified: every catalogued mutation re-applied once and shown to re-RED its test.
- [ ] Direct GREEN + preservation sentinels match step-0 baselines + registration gates pass.
- [ ] No migration (no schema change — checklist gate N/A, no `DB v##`).
- [ ] Step-2b feasibility spike ran green on BOTH targets before host-test authoring (spike deleted afterwards, never registered).
- [ ] Media/OS-boundary/multi-device path proven on the real rig (TC-VC05-13 + TC-VC05-16) under the pinned measurement protocol, not a fake; getStats evidence + measured `setupMs` + pair types recorded in Execution Progress. Metrics sanity envelope: `setupMs` < 90 s for both scenarios; pair types non-empty and `relay/relay` for the forced scenario — otherwise the metrics rows are NOT delivered.
- [ ] Mute plateau + speaker-toggle + `totalAudioEnergy` device evidence recorded (TC-VC05-13 windows) — "mute/speaker work" is closed by device evidence, not host fakes.
- [ ] Every new test's harness registration verified in a gate run (completeness-check, discovery, /sims dry-run slots).
- [ ] Relay Precondition P-1..P-3 recorded green before the device proofs.
- [ ] APK size delta recorded; merged-manifest `MODIFY_AUDIO_SETTINGS` verified via the literal `aapt dump permissions` command from step 2 (pin test added iff app-manifest line was needed); resolved `flutter_webrtc` version recorded (pub.dev-verified, floors re-checked).
- [ ] L5 array appends landed with their doc updates (`ONE_TO_ONE_TESTS` + `NIGHTLY_ONLY_TESTS` + test-gate-definitions.md / test-gates-reference.md / _current-test-map.md).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

---

## Scope Guard (hard "Do not")
- Do not add video capture/rendering, camera permissions, or `PERMISSION_CAMERA=1` (VC-08).
- Do not add CallKit/ConnectionService/PushKit, `UIBackgroundModes` entries, FGS types, full-screen intents, or any push/ring path (VC-06/VC-07) — the iOS/Android config pin tests must stay byte-identically green.
- Do not implement ICE restart, network-switch handling, loss/RTT/jitter sampling, or the always-relay privacy toggle (VC-09).
- Do not touch `go-relay-server/` or `go-mknoon/` (VC-03 owns TURN; VC-04 owns any Go-side envelope concerns) — zero Go diffs in this story.
- Do not edit `IncomingMessageRouter`, `call_*` envelope schemas, glare/TTL/busy *semantics*, or the fast-path sender (VC-04) — VC-05 only consumes VC-04's committed surface.
- Do not persist call state, write messageRepo rows for calls, or let anything call-related enter the durable inbox/retrier (VC-00 rule 5).
- Do not add a new `P2PServiceImpl` network primitive; if one becomes unavoidable, it calls `_allowsAccountNetworkSideEffects` first-line (rule 4) and this plan gets re-reviewed.
- Do not add `flutter_webrtc` usage outside `lib/features/call/` (keeps the dependency surface auditable for VC-08/09).
- Do not enable gradle minify/shrink or edit signing/gradle config (android_build_configuration_test pins).
- Do not run concurrently with any story editing `lib/features/call/` or `main.dart` DI (VC-04, VC-06+) — sequential per collision map.

## Accepted Differences / Intentionally Out Of Scope
- **No call-history persistence** (no DB rows, no missed-call log) — nothing in the MVP cut requires it; a future story owns it; consequence: reopen shows no trace of a past call (deliberate; blind-spot sweep row).
- **No Bluetooth-headset routing** — speaker/earpiece only via `CallAudioRouting`; BT (incl. `BLUETOOTH_CONNECT` permission) deferred to VC-09-or-later hardening.
- **Speaker audible-route assertion (deferred-not-waived)** — TC-VC05-13 executes the real `CallAudioRouting` impl on-device (no exception + `CALL_SPEAKER_TOGGLED` events + `dumpsys audio` route snapshot recorded), but asserting the OS audio-manager routing state machine-checkably (or audible output) is not feasible on this rig; a hard route-state assertion is deferred to VC-09's device hardening. The plan's close wording claims exactly what is proven, no more.
- **Opus asserted structurally, not by codec-string** — the audio m-line invariant is what's test-locked; codec preference munging is deliberately avoided (fragile SDP string surgery).
- **Emulator callee instead of second physical device** — per rule 1's rig definition; the forced-TURN scenario compensates for the NAT-topology simplicity of the emulator path.
- **No new curated gate family (cross-plan lock L5, adjudicated)** — no `CALL_TESTS` array this epic; the headline call host suite rides `ONE_TO_ONE_TESTS`, the heavy two-party e2e rides `NIGHTLY_ONLY_TESTS`, and everything else auto-globs into `feature-host-all`; the shared device orchestrator is `run_call_device_real.dart` (VC-08/VC-09 extend its `--scenario` set).

## Dependency Impact
- **Depends on VC-03 (committed + deployed):** ICE servers/ephemeral TURN creds primitive + the live TURN server this plan's precondition gate and TC-VC05-16 verify against. Contract consumed: cred fetch → `{urls, username, credential, ttlSeconds}`.
- **Depends on VC-04 (committed):** `call_*` signaling streams, `CallSession`/glare/TTL/`callId` idempotency, busy seam, signaling kill-switch. VC-05 runs on VC-04's committed tree (collision: `lib/features/call/`, conversation routing, `main.dart`).
- **VC-06 depends on this** — background/killed ring answers INTO this engine + active-call screen; it extends, never forks, the accept path.
- **VC-07 depends on this** — iOS CallKit answers into the same engine; the pod added here is its compile base.
- **VC-08 depends on this** — video = second m-line + renderers on this engine; the single-m-line guard (TC-VC05-02) is the pin VC-08 deliberately flips (re-pointed, never silently deleted — VC-00 flipped-pin convention).
- **VC-09 depends on this** — extends the getStats sampling seam (TC-VC05-09's event surface) with loss/RTT/jitter/drop-cause and ICE restart.

## Reviewer Findings
Dimension scores (assessment): goal-clarity 88 strong · compartmentalization 78 strong · anti-drift 78 strong · define-good 80 strong · goal-verification 68 adequate. Gap counts: 1 material, 3 moderate, 8 nit — ALL applied:
- **Material (goal-verification):** mute + speaker were goal components verified only against fakes → TC-VC05-13 now carries a device-tier mute window (callee inbound-rtp bytes plateau ≥3 s, resume after unmute; polarity-inversion mutation re-reds on device) and an on-device speaker toggle of the real `CallAudioRouting` impl (no exception + `CALL_SPEAKER_TOGGLED` ×2 + `dumpsys audio` route snapshot recorded); audible-route assertion recorded as an honest deferred-not-waived Accepted Difference; Working Piece / Done Criteria / INV-9 re-worded to claim exactly what is proven.
- **Moderate ×3:** (1) pinned device-proof measurement protocol (1 s getStats polls, 90 s connect-or-FAIL from invite-send, ≥3 consecutive increasing samples spanning ≥5 s on both parties) into TC-VC05-13/16, step 9, and gate step 5; (2) feasibility spike step 2b (throwaway getUserMedia + loopback PC on both targets, Stop-if before host authoring); (3) literal `aapt dump permissions` command for the `MODIFY_AUDIO_SETTINGS` merged-manifest check (binary-AXML grep trap removed).
- **Nits applied:** 90 s connect bound (setupMs recorded-only, VC-09 owns thresholds); real-mic `totalAudioEnergy`/`audioLevel` discriminator on the callee; per-slice RED re-run records in step 3; pub.dev verification of the `flutter_webrtc` pin as step 2's first action; kill-switch-off INCOMING invite case added to TC-VC05-03 + Real Scope item 4 + INV-10; Done-Criteria metrics sanity envelope; flow-log debug-build dependency made explicit (`flowEventLoggingEnabled = kDebugMode`, `flow_event_emitter.dart:6`; `FDC_FLOW_LOG` override `main.dart:320-330`); relay-address cite corrected :567→:568.
- **Cross-plan locks applied:** L1 (`kCallOfferTtl = 45000 ms`, VC-04-owned, 30-60 s band = design choice, noted in the dependency contract and the 90 s protocol note), L3 (`turn_credentials_get` / `turn:credentials` verbatim canonical, no longer "working names"), L5 (orchestrator renamed `run_call_device_real.dart` everywhere; headline `call_engine_test.dart` → `ONE_TO_ONE_TESTS` :21; `call_audio_e2e_proof_test.dart` → `NIGHTLY_ONLY_TESTS` :556; NO new family; step-10 gate-doc trio update replaces the old "no readonly-array edits" claim), L7 (natural-path scenario records — never asserts — pair type/punch events; only TC-VC05-16 asserts `relay/relay`; punch-outcome assertions belong to VC-02). L2/L4/L6 not touched by this plan (no ring-push mechanism, no circuit limits, no reachability wording present).
No gates weakened; no test rows dropped; USB-device+emulator e2e, relay precondition gates, and kill-switch requirements preserved and tightened.

## Arbiter Decision
Structural blockers: none. Deferred details: exact VC-03/VC-04 committed identifier spellings re-verified at execution start (capabilities locked; TURN names canonical per L3); VC-03's literal TURN allocation probe command copied at run time (P-3); resolved `flutter_webrtc` version pinned at step 2 (pub.dev-verified). Accepted differences: speaker audible-route hard assertion deferred-not-waived to VC-09 (device toggle + route snapshot recorded here); no call-history persistence; no BT routing; emulator callee per rule-1 rig; structural (not codec-string) Opus assertion; no new gate family per lock L5.

## Final Execution Verdict
Verdict: (pending) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner):
