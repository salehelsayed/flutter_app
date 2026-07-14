# VC-08 — Video Calls: video-from-start + mid-call audio→video upgrade  (Feature Improvement)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — VC-00 story map row VC-08 (`Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md:73`) + the VC-08 story brief (video-from-start offers, mid-call SDP re-negotiation upgrade, RTCVideoView UI, camera permission flow, 1:1-only video enforcement, bandwidth defaults, getStats frame metrics, device↔emulator e2e).

**Baseline tree:** VC-08 executes on the **committed VC-05 tree** (which itself sits on VC-04 + VC-03). Every "RED on HEAD" below means *RED on that VC-05-committed baseline* — VC-05 delivers the audio-only call feature (`lib/features/call/`, flutter_webrtc dependency, call orchestrator); on today's `new-orbit` HEAD none of that exists yet (verified: no `lib/features/call/` dir, `grep webrtc pubspec.yaml` = 0 hits). **Stop-if:** if VC-05 has not landed and re-greened its gates, do not start VC-08.

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | platform-av-push / harness-conventions / signaling-messaging grounding digests; AndroidManifest.xml; ios/Runner/Info.plist; ios/Podfile; lib/core/permissions/mic_permission_gateway.dart; scripts/run_test_gates.sh classify_path | anchors re-verified in source (CAMERA :5, NSCameraUsageDescription :46-47, PERMISSION_MICROPHONE-only :107, core/permissions auto-glob :975) | hand to Planner |
| 2026-07-13 | Planner | VC-00-roadmap.md; FDC-03 exemplar | reuse `call_offer` (same callId, higher seq) for re-negotiation — no new envelope type; Dart-side kill-switch; no Go/relay edits | draft catalog + matrix |
| 2026-07-13 | Reviewer (sufficiency) | this plan vs sufficiency-checklist.md | all gates pass (see Reviewer Findings) | Arbiter |
| 2026-07-13 | Arbiter | — | no structural blockers; VC-05-contract file names are stop-if-guarded, not assumed | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth

- Spec / intent: VC-00 roadmap (`VC-00-roadmap.md` — decision record, story map row VC-08, cross-session rules 1/3/4/5/6/7, metrics table) + the VC-08 story brief inline above.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose; classify_path at `:870`, completeness-check at `:1067`/`:1219`).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (case-branch registration, hard-FAIL on unclassified — harness digest).
- Numbering / index: VC plans live ONLY in this feature dir, numbered VC-NN; `Test-Flight-Improv/00-INDEX.md` does **not** index feature subdirectories (VC-00 rule 7).
- Upstream contracts consumed (stop-if any differs on the committed VC-05 tree — re-anchor, never fork a parallel call dir):
  - **VC-04 envelope contract:** `call_offer` / `call_answer` / `call_ice_candidates` / `call_end` / `call_decline` / `call_busy` envelopes (six types — VC-04 plan Exact Problem Statement) carry `{callId, seq, ttlMs, …}`, are **fast-path-only** (never durable-inboxed, never swept by retriers), idempotent on `(callId, seq)`, glare-resolved deterministically, and forward-compatible (unknown types → `unknownMessageStream` silent no-op, `lib/core/services/incoming_message_router.dart:264-270` — verified on HEAD).
  - **VC-05 call feature contract:** `lib/features/call/{application,domain,presentation}` exists with a test-injectable WebRTC seam (fakeable peer-connection/media factory — VC-05's equivalent of the `AudioRecorder` seam at `lib/core/media/record_audio_recorder_service.dart:23-26`), an in-call screen, ICE via VC-03 TURN creds, and a device orchestrator `integration_test/scripts/run_call_device_real.dart` registered in `check_reliability_simulation_discovery.sh`.
- Roadmap rules restated where this plan touches them: **rule 1** (USB-device+emulator execution rig — see Execution Environment), **rule 3** (kill-switch: `CALL_VIDEO_ENABLED` dart-define, OFF ≡ exact VC-05 behavior, test-locked), **rule 4** (Move-feature gate: VC-08 adds **no new network primitive** — re-negotiation rides VC-04's already-gated call-signaling sender; camera capture is not a network side-effect), **rule 5** (signaling semantics: re-offers are fast-path-only, TTL'd, `(callId,seq)`-idempotent, and Go **acks-first-then-emits** for `call_*` types — `go-mknoon/node/node.go:1854-1860` — so `acked=true` on a re-offer proves node receipt only, never callee consent; consent is only the `call_answer`), **rule 6** (gate hygiene: every new `*_test.dart` classifies; curated-array additions update the 4 gate docs together; counts are baseline-captured, never hardcoded).

---

## Session Classification

**implementation-ready** — Dart-only production change inside `lib/features/call/` + two small permission files in `lib/core/permissions/` + one line in `ios/Podfile`. No Go edits, no relay edits (**VC-00 rule 2 does not fire — no EC2 redeploy section is required for this story**), no DB migration, no schema change. Host tier closes the contract; device↔emulator e2e closes the story (rule 1).

---

## Exact Problem Statement

VC-05 ships a working 1:1 **audio** call (device↔emulator, ICE via VC-03, signaling via VC-04). Users cannot make video calls at all: the `call_offer` envelope has no media descriptor, the WebRTC session never requests a camera track, the in-call screen has no video surfaces, and there is no camera-permission UX in the call flow (the app's only camera uses today are profile photo / QR scan — `ios/Runner/Info.plist:46-47`). There is also no mid-call escalation: two people on an audio call who want to show something must hang up and… still can't.

Additionally, VC-05's 1:1-only enforcement (this epic never ships group calls) must be **extended to video**: an SDP carrying more than one video m-line (a multi-party/simulcast-topology smuggle) must be rejected exactly like multi-audio topologies, or the "1:1-only" invariant silently erodes the moment video lands.

**What must improve:** (a) video-from-start calls — the offer flags video, both sides render local preview + remote video, speaker routes ON, camera front/back switchable; (b) mid-call audio→video upgrade via SDP re-negotiation over VC-04 signaling, consented on **both** sides (callee explicitly accepts/declines camera; decline keeps the audio call alive); (c) camera permission flow modeled on the existing mic gateway; (d) mobile-sane bandwidth defaults; (e) video frame/resolution metrics in call flow events; (f) 1:1-only guard covers video m-lines.

**What must stay unchanged → preserved-green sentinels:** VC-05's audio-call behavior byte-for-byte when video is not engaged or the kill-switch is OFF (VC-05's call suites); the router's forward-compat unknown-type no-op (`incoming_message_router_test.dart::routes unknown types to unknownMessageStream`); the 1:1 messaging gate (`./scripts/run_test_gates.sh 1to1`); VC-04's glare/idempotency behavior for fresh offers; no durable-inbox writes for any `call_*` traffic (rule 5).

---

## Root Cause (verify → refute confirmed)

Not a bug — a scoped feature gap. Mechanism on the baseline tree (verified on today's HEAD; re-verify on the VC-05-committed tree before editing — lines drift):

1. **No media descriptor in the envelope:** VC-04's `call_offer` payload (per its contract) carries SDP + `{callId,seq,ttlMs}` but no `media` field; VC-05 builds offers with `offerToReceiveVideo`-equivalent OFF. Video cannot be signaled.
2. **No renegotiation path:** VC-05's session controller creates one offer/answer exchange at call start; nothing sends a second `call_offer` on an active `callId`, and the incoming-offer handler has no active-call branch that applies a re-offer instead of ringing.
3. **No camera permission plumbing:** `permission_handler` compiles in **only** `PERMISSION_MICROPHONE=1` on iOS (`ios/Podfile:96-111`, macro at `:107`) — a camera request on an iOS device would return `notDetermined` forever (the Podfile comment documents exactly this failure mode). Android `CAMERA` **is** already declared (`android/app/src/main/AndroidManifest.xml:5` — verified) and iOS `NSCameraUsageDescription` **exists** (`ios/Runner/Info.plist:46-47` — verified; wording covers profile photo/QR, acceptable for camera use generally). There is no `CameraPermissionGateway` (only `lib/core/permissions/mic_permission_gateway.dart:21-33` + prompt at `mic_permission_prompt.dart:17`).
4. **1:1 guard is audio-scoped:** VC-05's SDP topology guard (its 1:1-only enforcement) does not count video m-lines.

**Refuted / do-NOT-re-introduce:**
- Do **not** invent a `call_renegotiate` envelope type — refuted by design decision below (reuse `call_offer` with same `callId` + higher `seq`). A new type duplicates VC-04's idempotency/glare machinery, adds a router case + TTL audit surface (rule 5), and its old-build behavior (silent unknown-type no-op) is *identical* to a stale re-offer being ignored — all cost, no benefit.
- Do **not** treat a wire `acked=true` on the upgrade re-offer as consent — refuted by the ack-first-then-emit ordering for non-deferred types (`node.go:1854-1860`, signaling digest correction). Only a `call_answer` with matching `(callId, seq)` commits the upgrade.
- Do **not** request camera permission via a widened mic gateway — the tri-state gateway pattern is deliberately per-permission (const-injectable, `mic_permission_gateway.dart:36-53`); a sibling `CameraPermissionGateway` is the established shape.
- Do **not** add a Go feature flag for video — no Go code changes; adding one would drag in `feature_flags.go` + `p2p_bridge_client.dart` polarity-pin rebases (VC-00 collision map) for a purely Dart-side capability. The kill-switch is a Dart dart-define.

---

## DECISION — mid-call upgrade signaling: reuse `call_offer`, same `callId`, higher `seq`

**Decision:** an audio→video upgrade is signaled by sending another **`call_offer`** envelope with the **same `callId`**, **`seq` = current+1**, `media: 'video'`, and the renegotiated SDP. No new envelope type.

**Justification:**
1. **Machinery reuse:** VC-04's idempotency (`(callId, seq)` dedupe) and glare resolution are keyed exactly on these fields — renegotiation inherits both verbatim instead of duplicating them for a second type.
2. **Rule-5 surface:** one fewer cleartext `type`, one fewer router case, one fewer TTL/forward-compat audit item.
3. **Precedent:** Signal/Matrix-style call signaling treats renegotiation as "another offer within the session" — the pattern VC-00's signaling-plane decision already adopted.
4. **Version skew is safe and testable:** an older build (VC-05-era) receiving a `call_offer` whose `callId` is already active treats it per VC-04's stale/duplicate rules (not a fresh ring); it never answers the re-offer, the upgrader's answer-timeout fires, and the call **continues as audio** (locked by VC-08-06). A brand-new type would produce the same downgrade with zero telemetry.
5. **Discriminator obligation:** a re-offer must never re-ring. Locked by VC-08-05's assertion `NO CALL_INCOMING_RING emitted` for an active-callId offer.

**Glare tie-break (pinned):** same-callId re-offer glare reuses VC-04's deterministic comparator — lexicographically **lower peerId** wins (VC-04 plan: glare policy `localPeerId.compareTo(remotePeerId) < 0`, its Step D + envelope rules) — the lower peerId's re-offer is applied; the loser abandons its own re-offer and answers the winner's. Stop-if the committed VC-04 comparator is not peerId-keyed: re-anchor to its actual rule, never invent a second comparator.

**Upgrade answer timeout (locked L1):** the timeout the rollback (VC-08-06) fires on is VC-04's `kCallOfferTtl = 45000 ms` — the same TTL stamped on the re-offer (`ttlMs`), i.e. min(45 s, TTL remaining from `sentAtMs`). The 30–60 s band is a design choice (Signal/Matrix precedent), NOT a repo-derived constraint. Do not invent a separate video-upgrade constant.

**Consent model (both directions):** upgrade requester turns their camera on only after local permission + explicit user action; the receiving side gets an in-call consent prompt — **accept** → camera permission flow → `call_answer` (same `callId`, matching `seq`) with video SDP; **decline** → `call_answer` with video refused (video m-line rejected/inactive), audio call continues, requester's camera stays sendable-but-unreciprocated or is torn down per their own choice (default: keep sending one-way video is NOT done — on decline the requester rolls back to audio; simpler, symmetric, test-locked by VC-08-03).

---

## Real Scope

**In scope (VC-08):**
- `media` field (`'audio'|'video'`) on the call-offer/answer domain models + envelope round-trip (Dart only; Go is content-agnostic).
- `startCall(video: true)` — video-from-start offer (1 audio + 1 video m-line), camera permission + capture, bandwidth caps applied.
- `requestVideoUpgrade()` / consent-prompt / accept / decline / timeout-rollback state machine in the VC-05 session controller, over `call_offer` re-offers (decision above).
- `CameraPermissionGateway` + `camera_permission_prompt.dart` (sibling of the mic pair); `ios/Podfile` gains `'PERMISSION_CAMERA=1'` (the **only** platform-file edit); pin tests for Podfile macro, `NSCameraUsageDescription`, manifest `CAMERA`.
- In-call UI: local `RTCVideoView` preview (mirrored when front camera) + remote `RTCVideoView`, camera-switch (front/back), upgrade affordance, orientation-change survival; speaker default ON for video (audio calls keep VC-05 routing).
- 1:1-only extension: SDP topology guard rejects >1 **video** m-line (offer and answer, initial and renegotiation).
- Bandwidth defaults — **640×480 @ 30 fps capture constraints, sender encoding `maxBitrate` 800 kbps / `maxFramerate` 30**. Justification: VGA@30 is the mobile-interop sweet spot (fits a single TURN-relayed leg on LTE with headroom, keeps emulator software-encode real-time, and matches the conservative end of mobile messenger defaults); anything higher belongs to VC-09's adaptive ladder. Applied at video start AND after upgrade.
- Metrics: `CALL_VIDEO_STATS` flow event sampling `framesEncoded/framesDecoded/frameWidth/frameHeight/framesPerSecond` from `getStats()` — VC-08's row of the VC-00 metrics table.
- Kill-switch (rule 3): `CALL_VIDEO_ENABLED` dart-define (Dart-side flag object in the call feature), default ON at story close (device evidence is in-scope here, unlike VC-01/02 whose graduation gates are separate); OFF ≡ exact VC-05 behavior, test-locked. **Naming note (justified deviation from rule 3's `MKNOON_*` examples):** the `MKNOON_*` namespace is for dart-defines merged over Go's `DefaultFeatureFlags()` (`VC-00-roadmap.md:146`); `CALL_VIDEO_ENABLED` is Dart-only and never crosses the bridge, so it deliberately sits outside that namespace — do NOT "correct" the name mid-execution (it is test-locked in TC-08-14 and the gate docs).
- Device↔emulator e2e (rule 1): video-from-start, camera-switch survival, audio→video upgrade — getStats frame counters both sides.

**Out of scope (owning story):**
- ICE restart / network-switch survival, adaptive degradation ladder, per-call quality metrics beyond frame counters, "always relay" toggle → **VC-09**.
- Ring/push payload changes ("incoming **video** call" label in the FCM push, full-screen intent) → **VC-06** (contract note in Dependency Impact).
- iOS voip/audio background modes, CallKit video flag → **VC-07**.
- Group/multi-party calls → **never** (epic decision); screen share → not in epic.
- Any `go-relay-server/` or `go-mknoon/` edit → none needed; rule 2 does not fire.

---

## Files To Inspect Next

**Production (all on the VC-05-committed tree; re-verify names/lines — stop-if the VC-05 layout differs, re-anchor):**
- `lib/features/call/domain/models/` — call offer/answer models (+ new `media` field, `CallMedia` enum).
- `lib/features/call/application/call_session_controller.dart` (VC-05's session state machine) — video start, upgrade state machine, topology guard call sites, stats sampler hook.
- `lib/features/call/application/` WebRTC seam (VC-05's fakeable peer-connection/media factory) — camera track acquisition, `switchCamera`, sender-parameter caps, `getStats`.
- `lib/features/call/domain/sdp_topology_guard.dart` (VC-05's 1:1 guard; name may differ) — video m-line counting.
- `lib/features/call/presentation/screens/call_screen…` — video surfaces, consent prompt, camera-switch/upgrade affordances, speaker routing.
- **NEW:** `lib/core/permissions/camera_permission_gateway.dart`, `lib/core/permissions/camera_permission_prompt.dart` (clone the mic pair: `mic_permission_gateway.dart:21-53`, `mic_permission_prompt.dart:17`).
- `ios/Podfile:96-111` — add `'PERMISSION_CAMERA=1'` beside `'PERMISSION_MICROPHONE=1'` (`:107`).

**Direct tests + integration tests:**
- NEW `test/features/call/application/call_session_video_test.dart`, `call_video_upgrade_test.dart`, `call_video_flags_test.dart`; NEW `test/features/call/domain/sdp_video_topology_guard_test.dart`; NEW `test/features/call/presentation/call_screen_video_test.dart`; NEW `test/core/permissions/camera_permission_gateway_test.dart` (+ prompt cases); NEW `test/core/services/ios_call_video_config_test.dart` (platform pins, style of `test/features/push/application/ios_push_project_config_test.dart`); NEW `integration_test/call_video_device_proof_test.dart` (@Tags(['device'])).
- Existing sentinels: VC-05's call suites; `test/core/services/incoming_message_router_test.dart` (:256 unknown-type, :179 chat_message); `test/core/permissions/mic_permission_prompt_test.dart` (pattern + must stay green).

**Dependency-only context (not edited):** `lib/core/services/incoming_message_router.dart` (VC-04 owns the `call_*` cases); `lib/core/services/p2p_service_impl.dart` move-gate seam (`:555-572`) — VC-04's signaling sender already gates; `android/app/src/main/AndroidManifest.xml:5`; `ios/Runner/Info.plist:46-47`.

---

## Existing Tests Covering This Area

| Test | Covers | Status |
|---|---|---|
| VC-05 call suites (`test/features/call/**` per VC-05 plan) | audio call state machine, offer/answer, ICE wiring, in-call UI | exists on baseline — **preserved-green sentinels** |
| `test/core/services/incoming_message_router_test.dart::routes unknown types to unknownMessageStream` (:256) | forward-compat no-op that the upgrade-downgrade path leans on | exists — preserved |
| `test/core/permissions/mic_permission_prompt_test.dart` | the gateway/prompt pattern being cloned | exists — preserved |
| `test/features/push/application/ios_push_project_config_test.dart` | plist pin-test style | exists — preserved |
| Video anything | — | **MISSING — this plan** |

Missing coverage gaps: everything video (offer flag, upgrade, consent, decline, timeout rollback, topology guard for video, camera permission, caps, speaker routing, camera switch, orientation, stats, kill-switch, camera teardown, device e2e).
Already in curated family arrays?: VC-05's headline call host suites per VC-05's registration decision; nothing video-related is registered anywhere yet (verified: `grep -i 'video\|call_' scripts/run_test_gates.sh` = no call-feature entries on HEAD).

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> All host tests drive the VC-05 fakes (fake peer-connection/media seam, `FakeP2PService`, `captureFlowEvents`). "RED on HEAD" = RED on the VC-05-committed baseline. New-file tests that reference not-yet-existing APIs are RED as compile errors — document the expected error; convert to behavioral RED where the API exists.

1. `test/features/call/application/call_session_video_test.dart::VC-08-01 startCall(video:true) sends call_offer with media=video and exactly one audio + one video m-line`
   - Tier: unit/application · Shape: fake media seam returns a camera track; capture the envelope handed to the signaling sender.
   - RED on HEAD because: `startCall` has no `video` parameter and the offer model has no `media` field (compile error → behavioral RED once the field exists but is never set).
   - GREEN asserts: envelope `type=='call_offer'`, `media=='video'`, SDP contains exactly one `m=audio` and one `m=video`; camera track requested; zero `messageRepo` writes.
   - Mutation that re-reds: drop the `media` field from the built envelope → RED.
2. `call_session_video_test.dart::VC-08-02 incoming video offer surfaces consent and accept answers with video after camera permission`
   - Tier: unit/application · Shape: inject incoming `call_offer{media:'video'}`; fake `CameraPermissionGateway` returns granted; user-accept.
   - RED on HEAD because: the incoming-offer handler ignores/lacks `media`; no consent state exists.
   - GREEN asserts: session exposes a `videoConsentPending` state; on accept, gateway `request()` called exactly once, `call_answer` carries `media=='video'`, local camera track live.
   - Mutation: answer with video without consulting the gateway → the "request called once" assertion REDs.
3. `call_session_video_test.dart::VC-08-03 declining camera keeps the audio call alive and answers audio-only`
   - Tier: unit/application · Shape: incoming video offer; user-decline.
   - RED on HEAD because: no decline path exists.
   - GREEN asserts: `call_answer` has `media=='audio'` (video refused), call state stays `connected(audio)`, camera gateway **never** called, no camera track created, call NOT hung up.
   - Mutation: make decline hang up → RED.
   - Distinct-event discriminator: asserts `CALL_VIDEO_CONSENT_DECLINED` AND NOT `CALL_HANGUP`.
4. `test/features/call/application/call_video_upgrade_test.dart::VC-08-04 requestVideoUpgrade sends call_offer with same callId, seq+1, media=video, fast-path-only`
   - Tier: unit/application · Shape: established fake audio call (callId `C`, seq `1`); call `requestVideoUpgrade()`.
   - RED on HEAD because: no `requestVideoUpgrade` API exists.
   - GREEN asserts: sent envelope `type=='call_offer'`, `callId=='C'`, `seq==2`, `media=='video'`, carries `ttlMs`; sent via the VC-04 signaling sender (fast path); **zero `messageRepo.saveMessage` calls** (rule 5 — outside retry machinery, locked here); acked wire result does NOT transition state to video (only `call_answer` does — rule 5 ack-first-then-emit).
   - Mutation: persist the re-offer via messageRepo → the zero-writes assertion REDs; or bump state on ack → the ack assertion REDs.
5. `call_video_upgrade_test.dart::VC-08-05 re-offer idempotency and glare: duplicate/stale seq ignored, active-callId re-offer never re-rings, simultaneous upgrades resolve deterministically`
   - Tier: unit/application · Shape: active call; inject duplicate re-offer (same `(callId,seq)`), stale re-offer (`seq` ≤ current), and a glare pair (both sides upgrade concurrently over a fake duplex net).
   - RED on HEAD because: no renegotiation seq guard exists.
   - GREEN asserts: duplicate/stale → no state change, no second consent prompt; **`CALL_INCOMING_RING` NOT emitted** for an active-callId offer (the reuse-decision discriminator); glare resolves via VC-04's tie-break (lower peerId wins — pinned in the DECISION block) to exactly one applied renegotiation (assert final `seq` consistent both sides).
   - Mutation: remove the seq guard → duplicate re-prompts → RED.
6. `call_video_upgrade_test.dart::VC-08-06 unanswered upgrade times out and rolls back to a fully-consistent audio call (old-peer forward-compat)`
   - Tier: unit/application · Shape: `requestVideoUpgrade()`; peer never answers (models an old VC-05-era build ignoring the re-offer); advance fake clock past the upgrade answer timeout — **locked L1: VC-04's `kCallOfferTtl = 45000 ms`**, the same `ttlMs` stamped on the re-offer (fire at min(45 s, TTL remaining from `sentAtMs`); no separate video constant).
   - RED on HEAD because: no timeout/rollback exists.
   - GREEN asserts (FULL post-transition state — invariant re-verification): state back to `connected(audio)`; local camera track stopped AND disposed; sender caps/params restored; `CALL_VIDEO_UPGRADE_TIMEOUT` emitted; audio still flowing (fake track live); **a subsequent `requestVideoUpgrade()` succeeds with `seq+2`** (seq state not corrupted).
   - Mutation: skip camera teardown on rollback → RED.
7. `test/features/call/domain/sdp_video_topology_guard_test.dart::VC-08-07 SDP with more than one video m-line is rejected (1:1-only)`
   - Tier: unit/domain (pure SDP text) + application (guard wired: session refuses to apply the remote description and emits rejection).
   - RED on HEAD because: VC-05's guard counts audio m-lines only (or the video branch is absent).
   - GREEN asserts: guard flags 2× `m=video` SDP (offer AND answer, initial AND renegotiation paths); session emits `CALL_SDP_TOPOLOGY_REJECTED` with reason `multi_video`, does not apply the SDP, and (initial-offer case) rejects the call / (renegotiation case) keeps audio alive.
   - Mutation: revert the video m-line count → RED.
8. `call_session_video_test.dart::VC-08-08 bandwidth defaults: 640x480@30 capture constraints and 800kbps/30fps sender caps applied at video start and after upgrade`
   - Tier: unit/application · Shape: fake media seam records constraints; fake sender records `setParameters`.
   - RED on HEAD because: no video capture path, hence no caps.
   - GREEN asserts: `getUserMedia` video constraints width 640 / height 480 / frameRate 30; sender encoding `maxBitrate==800000`, `maxFramerate==30`; asserted on BOTH the video-from-start path and the post-upgrade path.
   - Mutation: remove the `setParameters` call → RED.
9. `test/core/permissions/camera_permission_gateway_test.dart::VC-08-09 tri-state camera gateway + denied/permanentlyDenied prompts gate video`
   - Tier: unit (gateway mapping) + application (session refuses camera without grant).
   - RED on HEAD because: `camera_permission_gateway.dart` does not exist (compile RED).
   - GREEN asserts: granted/limited→granted, permanentlyDenied/restricted→permanentlyDenied, else denied (mirror of `mic_permission_gateway.dart:44-51`); `denied` → video start blocked + re-promptable; `permanentlyDenied` → settings deep-link prompt shown (fake gateway spy), **no camera track ever created without granted**.
   - Mutation: create the track before the gateway resolves → RED.
10. `call_session_video_test.dart::VC-08-10 speaker defaults ON for video, earpiece routing preserved for audio-only, upgrade flips to speaker`
    - Tier: unit/application · Shape: fake audio-route seam records route changes.
    - RED on HEAD because: no video-aware routing exists.
    - GREEN asserts: video-from-start connect → speakerphone ON; audio-only call → VC-05 route untouched (discriminator: assert route-change call absent, not merely "speaker false"); accept-upgrade → speaker ON.
    - Mutation: drop the upgrade→speaker flip → RED.
11. `call_session_video_test.dart::VC-08-11 switchCamera toggles front/back, keeps the track live, flips the preview mirror`
    - Tier: unit/application · Shape: fake media seam with a `switchCamera` spy.
    - RED on HEAD because: no switch API.
    - GREEN asserts: seam invoked once per toggle; facing state front↔back; local track still live (not re-created); mirror flag true(front)/false(back).
    - Mutation: re-acquire a new track instead of switching → the "same track live" assertion REDs.
12. `test/features/call/presentation/call_screen_video_test.dart::VC-08-12 video call screen renders local preview + remote view, affordances, and survives orientation change`
    - Tier: widget (`WidgetTester`, fakes; SYNC teardown for any IO per tier-matrix).
    - RED on HEAD because: VC-05 call screen has no video surfaces.
    - GREEN asserts: video mode shows a mirrored local `RTCVideoView` + remote `RTCVideoView`, camera-switch + upgrade affordances; portrait→landscape rebuild (surface-size change) keeps both renderers attached to their tracks (fresh-mount reconstruction — blind-spot row 1); audio-only mode shows neither surface, upgrade affordance visible only when kill-switch ON.
    - Mutation: dispose renderers on orientation rebuild → RED.
13. `call_session_video_test.dart::VC-08-13 CALL_VIDEO_STATS flow event samples frame counters and resolution from getStats`
    - Tier: unit/application · Shape: fake peer connection returns canned outbound-rtp/inbound-rtp stats; `captureFlowEvents`.
    - RED on HEAD because: no such event exists.
    - GREEN asserts: periodic `CALL_VIDEO_STATS` with `framesEncoded`, `framesDecoded`, `frameWidth`, `frameHeight`, `framesPerSecond` and the `callId`; sampling stops on hangup.
    - Mutation: remove the sampler wiring → RED.
14. `test/features/call/application/call_video_flags_test.dart::VC-08-14 CALL_VIDEO_ENABLED=false is exactly VC-05 behavior (kill-switch, rule 3)`
    - Tier: unit/application + widget assertion (affordance hidden).
    - RED on HEAD because: the flag does not exist.
    - GREEN asserts: flag OFF → `startCall(video:true)` refused (falls back to audio offer with `media=='audio'`), upgrade affordance hidden; **incoming OFF-path split into two explicit cases:** (a) **initial** `call_offer{media:'video'}` with flag OFF → **rings normally** (assert `CALL_INCOMING_RING` emitted, identical to VC-05 — never auto-answered without ring) and user-answer produces a `media=='audio'` answer, call connects audio (asymmetric-peer safety); (b) **upgrade re-offer** (active callId) with flag OFF → auto-declined via `call_answer` with video refused, **no consent prompt shown**, audio call continues. Flag ON → video paths available. Default resolves ON.
    - **OFF-equivalence sweep (INV-6 is 'exact', not spot-checked):** parameterize the injected flag object (`CallVideoFlags(enabled: false)` — host-tier injection, no dart-define rebuild) and re-run VC-05's headline call-session suite group under OFF, asserting event sequences identical to the ON-with-no-video-engaged baseline; name VC-05's suite files at Step 0 re-anchor and record them in Execution Progress.
    - Mutation: leave the upgrade affordance visible when OFF → RED; auto-answer a flag-OFF initial video offer without `CALL_INCOMING_RING` → case (a) REDs.
15. `test/core/services/ios_call_video_config_test.dart::VC-08-15 Podfile compiles PERMISSION_CAMERA=1 (+ preserved platform pins)`
    - Tier: unit (file-reading pin test, style of `ios_push_project_config_test.dart`).
    - RED on HEAD because: `ios/Podfile` GCC_PREPROCESSOR_DEFINITIONS contains only `PERMISSION_MICROPHONE=1` (`:107` — verified).
    - GREEN asserts: Podfile contains BOTH `'PERMISSION_MICROPHONE=1'` and `'PERMISSION_CAMERA=1'`; sibling green-on-day-one pins in the same file: `NSCameraUsageDescription` present in `ios/Runner/Info.plist` (:46-47) and `android.permission.CAMERA` in `AndroidManifest.xml` (:5) (preservation locks — see P-rows).
    - Mutation: revert the Podfile line → RED.
16. `call_session_video_test.dart::VC-08-16 hangup and decline tear the camera down; decline preserves audio (destructive-action sweep)`
    - Tier: unit/application.
    - RED on HEAD because: no video teardown path exists.
    - GREEN asserts: hangup during video → video track `stop()`+dispose, renderers disposed, stats sampler cancelled, audio track also released (full teardown); upgrade-decline (requester side) → video track stopped+disposed but audio track UNTOUCHED and call still `connected(audio)` (removed vs preserved both asserted).
    - Mutation: leak the camera track on decline → RED.
17. `integration_test/call_video_device_proof_test.dart::VC-08-17 device↔emulator video-from-start call encodes and decodes frames on BOTH sides` — **PROD-CRITICAL**
    - Tier: device-proof (`@Tags(['device'])`, two Android parties, real flutter_webrtc, real VC-03 TURN, real VC-04 signaling over mknoun.xyz relay).
    - RED on HEAD because: the proof file does not exist; on the baseline tree the video APIs it drives do not exist.
    - GREEN asserts: after connect, `getStats()` on each side shows `framesEncoded > 0` (outbound) AND `framesDecoded > 0` (inbound) increasing across two samples ≥5 s apart, **with a pre-committed floor: `framesDecoded` delta ≥ 25 over the ≥5 s window on EACH side (≈5 fps — well under the 30 fps cap, above slideshow)**. **STOP condition (not a soft pass): if either side is below the floor, keep the kill-switch default OFF, record the deltas, and escalate/replan caps or encoder approach — do not close the story.** **Emulator leg uses the virtual camera's rendered test pattern — assert frame counters only, never image content.**
    - Mutation: point the callee at an audio-only answer → `framesDecoded` stays 0 on the caller → RED.
18. `call_video_device_proof_test.dart::VC-08-18 camera switch mid-call survives (device leg)`
    - Tier: device-proof.
    - RED on HEAD because: file/API absent.
    - GREEN asserts: on the USB-device leg, trigger `switchCamera` mid-call; sample `framesEncoded` before and ≥5 s after — the counter keeps advancing and the peer's `framesDecoded` keeps advancing (no frozen stream), both deltas ≥ 25 over the ≥5 s window (same floor/protocol as TC-08-17).
    - Mutation: break track survival on switch → deltas go 0 → RED.
19. `call_video_device_proof_test.dart::VC-08-19 audio-only call upgrades to video live (device↔emulator)`
    - Tier: device-proof.
    - RED on HEAD because: file/API absent.
    - GREEN asserts: call connects audio (VC-05 flow, `framesEncoded` video == 0 both sides); device leg requests upgrade, emulator leg auto-accepts (test hook); both sides then show video `framesEncoded>0` and `framesDecoded>0` with post-upgrade `framesDecoded` deltas ≥ 25 per ≥5 s window each side (TC-08-17 floor); audio never drops (connection state stays connected throughout). **Hook constraint: the auto-accept hook drives the same `acceptVideoUpgrade()` entry the consent dialog calls — assert the consent-accepted flow event (`CALL_VIDEO_CONSENT_ACCEPTED`) is emitted on the emulator leg BEFORE the answer; the hook may skip the dialog, never the consent state machine.**
    - Mutation: revert the renegotiation apply → counters stay 0 → RED.

**Preserved (green-on-baseline, locked, not RED):**
- **VC-08-P1** VC-05 audio-call suites stay green unmodified (`flutter test test/features/call/` on the baseline set) — video change must not touch audio-only behavior.
- **VC-08-P2** `incoming_message_router_test.dart::routes unknown types to unknownMessageStream` (:256) — forward-compat no-op that the downgrade path leans on.
- **VC-08-P3** `NSCameraUsageDescription` + manifest `CAMERA` pins (inside VC-08-15's file) — green day one, guard against regression.
- **VC-08-P4** `mic_permission_prompt_test.dart` + VC-05 mic-in-call flow — camera gateway addition must not disturb mic plumbing.

---

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD (=VC-05 baseline) | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-08-01 video-from-start offer | envelope+SDP build | unit/app | `call_session_video_test.dart::VC-08-01` | no `video` param / `media` field | drop media field | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (feature glob, run_test_gates.sh:1025) + add file to `ONE_TO_ONE_TESTS` (headline 1:1 flow) |
| TC-08-02 callee consent accept | consent state + permission | unit/app | `call_session_video_test.dart::VC-08-02` | media ignored, no consent state | answer w/o gateway | `./scripts/run_test_gates.sh 1to1` | same file (array + AUTO) |
| TC-08-03 callee decline keeps audio | decline path | unit/app | `call_session_video_test.dart::VC-08-03` | no decline path | decline→hangup | `./scripts/run_test_gates.sh 1to1` | same file |
| TC-08-04 upgrade re-offer wire shape | fast-path signaling | unit/app | `call_video_upgrade_test.dart::VC-08-04` | no upgrade API | persist via messageRepo | `./scripts/run_test_gates.sh 1to1` | AUTO + add to `ONE_TO_ONE_TESTS` |
| TC-08-05 idempotency/glare/no-re-ring | (callId,seq) guard | unit/app | `call_video_upgrade_test.dart::VC-08-05` | no renegotiation seq guard | remove seq guard | `./scripts/run_test_gates.sh 1to1` | same file |
| TC-08-06 timeout rollback (fwd-compat) | rollback + invariant re-verify | unit/app | `call_video_upgrade_test.dart::VC-08-06` | no timeout/rollback | skip camera teardown | `./scripts/run_test_gates.sh 1to1` | same file |
| TC-08-07 1:1-only video m-line guard | pure SDP + wiring | unit/domain+app | `sdp_video_topology_guard_test.dart::VC-08-07` | guard audio-scoped | revert m-line count | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (feature glob) |
| TC-08-08 bandwidth caps | constraints + setParameters | unit/app | `call_session_video_test.dart::VC-08-08` | no video capture path | remove setParameters | `./scripts/run_host_test_gates.sh feature-host-all` | same file as TC-01 |
| TC-08-09 camera permission flow | tri-state + prompts | unit+app | `camera_permission_gateway_test.dart::VC-08-09` | gateway file absent | track before grant | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (`test/core/permissions/**`, run_test_gates.sh:975) |
| TC-08-10 speaker routing | route seam | unit/app | `call_session_video_test.dart::VC-08-10` | no video-aware routing | drop upgrade flip | `./scripts/run_host_test_gates.sh feature-host-all` | same file as TC-01 |
| TC-08-11 camera switch (host) | seam toggle, track survival | unit/app | `call_session_video_test.dart::VC-08-11` | no switch API | re-acquire track | `./scripts/run_host_test_gates.sh feature-host-all` | same file |
| TC-08-12 video UI + orientation | widget render/rebuild | widget | `call_screen_video_test.dart::VC-08-12` | no video surfaces | dispose on rebuild | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (presentation glob) |
| TC-08-13 getStats frame metrics | flow event | unit/app | `call_session_video_test.dart::VC-08-13` | event absent | remove sampler | `./scripts/run_host_test_gates.sh feature-host-all` | same file |
| TC-08-14 kill-switch OFF ≡ VC-05 | rule-3 flag | unit/app+widget | `call_video_flags_test.dart::VC-08-14` | flag absent | affordance visible when OFF | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (feature glob) |
| TC-08-15 iOS PERMISSION_CAMERA pin | platform pin | unit (file pin) | `ios_call_video_config_test.dart::VC-08-15` | Podfile mic-only (:107) | revert Podfile line | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (`test/core/services/**`) |
| TC-08-16 teardown on hangup/decline | destructive-action sweep | unit/app | `call_session_video_test.dart::VC-08-16` | no teardown path | leak track on decline | `./scripts/run_test_gates.sh 1to1` | same file as TC-01 |
| TC-08-17 e2e video frames both sides (**PROD-CRITICAL**) | real webrtc/TURN/signaling; frame floor ≥25/5s each side | device-proof | `call_video_device_proof_test.dart::VC-08-17` | proof + APIs absent | audio-only answer → decoded 0 | `dart integration_test/scripts/run_call_device_real.dart --scenario video_call_e2e -d <usbSerial>,<emulatorSerial>` — **first run at Step 4b (early payoff STOP/GO gate), re-run at §5 close** | classify_path case in check_reliability_simulation_discovery.sh (`record "1to1" … "test"`) + orchestrator `--scenario video_call_e2e`; run_test_gates classify auto-matches `*_proof_test.dart` (:1036-1039) |
| TC-08-18 e2e camera-switch survival | device camera boundary | device-proof | `call_video_device_proof_test.dart::VC-08-18` | same | break switch survival | `…run_call_device_real.dart --scenario video_camera_switch -d <usb>,<emu>` | orchestrator `--scenario video_camera_switch` (same classify_path case) |
| TC-08-19 e2e audio→video upgrade | renegotiation over real wire | device-proof | `call_video_device_proof_test.dart::VC-08-19` | same | revert renegotiation apply | `…run_call_device_real.dart --scenario video_upgrade -d <usb>,<emu>` | orchestrator `--scenario video_upgrade` (same classify_path case) |
| P1 audio suites unchanged | preservation | unit/app/widget | VC-05 call suites (baseline set) | n/a (green) | n/a (sentinel) | `flutter test test/features/call/` + `./scripts/run_test_gates.sh 1to1` | already registered by VC-05 |
| P2 unknown-type no-op | preservation | unit | `incoming_message_router_test.dart::routes unknown types…` (:256) | n/a (green) | n/a (sentinel) | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (existing) |
| P3 plist/manifest camera pins | preservation | unit (file pin) | `ios_call_video_config_test.dart` P-cases | n/a (green day one) | delete NSCameraUsageDescription → RED | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (same file as TC-15) |
| P4 mic plumbing untouched | preservation | unit | `mic_permission_prompt_test.dart` + VC-05 mic flow | n/a (green) | n/a (sentinel) | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (existing) |
| Regression floor | full gates | gate | all suites | n/a | n/a | `1to1`, `baseline`, `groups`, `feature-host-all`, `core-host-all` (baseline-captured counts) | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** call state is deliberately **ephemeral** (rule 5: `call_*` never persisted; a process restart has no call to reconstruct — justified N/A for process-restart). The real derived-state hazards are **widget re-mount / orientation change** (renderers must re-attach: **TC-08-12**) and **upgrade rollback** (full state reconstruction to audio: **TC-08-06**). Covered.
- **Sibling-surface consistency:** the new capability gates are symmetric and test-locked — camera consent gates BOTH directions (caller TC-08-01/09, callee TC-08-02/03); the kill-switch gates outgoing video, the upgrade affordance, AND incoming video offers (TC-08-14); camera-switch affordance exists only while video is live (TC-08-12). Mute/hangup audio affordances are untouched (P1). Covered.
- **Destructive-action side-effects:** **TC-08-16** asserts what is removed (video track stopped+disposed, renderers disposed, sampler cancelled) AND what is preserved (audio track on decline); hangup reuses VC-05's teardown path extended, not a divergent copy (Step 6 names the seam). Covered.
- **Invariant re-verification under new transitions:** the upgrade-timeout rollback (a brand-new transition) re-verifies the audio-call invariants post-transition — audio flowing, camera off, caps restored, seq usable for a later retry (**TC-08-06** asserts the FULL post-rollback state). The topology-reject-during-renegotiation path likewise must keep the audio call intact (**TC-08-07** renegotiation case). Covered.

---

## Invariants (locked by tests)

- INV-1 **1:1-only:** no SDP with >1 video m-line is ever applied (offer/answer, initial/renegotiation) → VC-08-07.
- INV-2 **Signaling stays fast-path-only:** no call/video envelope ever produces a messageRepo row or retrier pickup → VC-08-04 (zero-writes assertion).
- INV-3 **`(callId, seq)` idempotency extends to renegotiation; a re-offer never re-rings** → VC-08-05.
- INV-4 **Camera never live without granted permission + explicit user consent, both directions** → VC-08-02/03/09.
- INV-5 **Caps always applied when video starts (either path)** → VC-08-08.
- INV-6 **Kill-switch OFF ≡ exact VC-05 behavior** (rule 3 revert path test-locked) → VC-08-14: spot assertions (start refused, affordance hidden, ring-then-audio-answer, re-offer auto-decline) PLUS the parameterized OFF re-run of VC-05's headline call-session suites (injected `CallVideoFlags(enabled:false)`).
- INV-7 **Camera released on every terminal/rollback transition** → VC-08-06/16.
- INV-8 **A wire ack on a re-offer is not consent** (rule 5) → VC-08-04.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan

0. **Preflight:** confirm VC-05 committed + its gates green; snapshot `git status --short` (preserve pre-existing dirty tree — do not revert/absorb it); capture green baselines: `./scripts/run_test_gates.sh 1to1`, `baseline`, `groups`, `./scripts/run_host_test_gates.sh feature-host-all`, `core-host-all`, `flutter analyze` count. Re-verify every VC-05-contract file name/line cited above; record VC-04's `kCallOfferTtl` constant name AND value (locked L1: 45000 ms) plus the names of VC-05's headline call-session suites (needed for TC-08-14's OFF-equivalence re-run) in Execution Progress before authoring VC-08-06/14. **Stop-if** VC-05's WebRTC seam is not fakeable for camera tracks / sender parameters / getStats / **audio output routing** (TC-08-10's route seam) → extend the seam FIRST as a test-only widening (no behavior change), do not reach around it.
1. **RED (batched per slice — INV-RED-FIRST holds per slice, not per plan):** batch A before steps 2–4: author VC-08-01/07/08/09/10/15 + the TC-08-17 device-proof skeleton; batch B before steps 5–7: author VC-08-02/03/04/05/06/11/12/13/14/16 + the 18/19 proof skeletons. Run the focused commands (Acceptance Gates §RED) per batch and record each failure reason (compile error vs assertion) in Execution Progress — keeps intermediate direct-GREEN runs free of expected-red noise from later slices.
2. **Envelope/domain:** add `CallMedia` (`audio|video`) to the call offer/answer models + JSON round-trip; default `audio` when absent (old-peer envelopes parse unchanged). Greens parts of 01/02.
3. **Permission seam:** create `camera_permission_gateway.dart` + `camera_permission_prompt.dart` (clone mic pair); add `'PERMISSION_CAMERA=1'` to `ios/Podfile` (:105-108 block); write nothing else platform-side. Greens 09/15.
4. **Session controller — video-from-start:** `startCall(video:)` behind `CallVideoFlags` (dart-define `CALL_VIDEO_ENABLED`); camera acquisition via gateway→seam with 640×480@30 constraints; sender caps via `setParameters`; speaker-ON routing; topology guard extended to video m-lines and enforced on both descriptions. Greens 01/07/08/10, parts of 14.
4b. **Early payoff device gate — TC-08-17, PROD-CRITICAL (STOP/GO):** the video-from-start device leg depends only on steps 0–4 (no upgrade machinery, no stats/UI polish), so it runs NOW, not at the end. Finish the TC-08-17 proof body, add the `--scenario video_call_e2e` case to `run_call_device_real.dart` (remaining registration hygiene stays at step 8), then run `dart integration_test/scripts/run_call_device_real.dart --scenario video_call_e2e -d 21071FDF600CSC,emulator-5554` (single-leg pre-smoke if useful: `flutter test integration_test/call_video_device_proof_test.dart -d emulator-5554`). **GO** = frame floor met both sides (framesDecoded delta ≥ 25 per ≥5 s window). **STOP** = counters frozen or below floor (the plan's own top risk: emulator virtual camera / software-encode can't sustain real-time VGA) → replan caps/encoder approach and keep the kill-switch default OFF before building steps 5–7 on top. Record the run + deltas in Execution Progress either way.
5. **Upgrade state machine:** `requestVideoUpgrade()` → re-offer (same callId, seq+1, media video, VC-04 TTL) via the VC-04 signaling sender (already move-gated — rule 4: no new network primitive); incoming re-offer branch (active callId: consent prompt, never ring); accept/decline answers; answer-timeout rollback restoring full audio state. Greens 02/03/04/05/06.
6. **Teardown + camera switch + stats:** extend VC-05's teardown seam (do NOT fork a parallel cleanup path) for video tracks/renderers/sampler; `switchCamera` via seam; `CALL_VIDEO_STATS` sampler on the flow-event bus. Greens 11/13/16.
7. **UI:** call screen video mode (local mirrored preview, remote view, switch + upgrade affordances, consent dialog, orientation-safe renderer lifecycle). Greens 12, rest of 14.
   *Stop-if at any step:* a VC-04/VC-05 contract mismatch (e.g. no `seq` on offers) → replan with the owning story, do not hack a parallel field.
8. **Registration (rule 6, resolved by lock L5 — NO new family array this epic):** add the two headline files (`call_session_video_test.dart`, `call_video_upgrade_test.dart`) to `ONE_TO_ONE_TESTS` (`scripts/run_test_gates.sh:21`); any heavy two-party host-runnable e2e (none planned) would go to `NIGHTLY_ONLY_TESTS` (`:556`), never a new array; the device proofs stay `*_proof_test.dart` manual device-proofs (auto-classified `:1036-1039`) run via `run_call_device_real.dart`, which honors the `--scenario all` / `--list-scenarios` discovery contract; update `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` together; add the `call_video_device_proof_test.dart` case branch in `check_reliability_simulation_discovery.sh` classify_path (`record "1to1" "$path" "test" "1:1 video call device proof"`); add `--scenario video_call_e2e|video_camera_switch|video_upgrade` cases to `run_call_device_real.dart` (ids appear in `--list-scenarios` output → discovery auto-expands). Verify: `./scripts/run_test_gates.sh completeness-check` + `./scripts/check_reliability_simulation_discovery.sh` + `/sims 1to1 --list` dry-run shows the new slots.
9. **Rerun** direct → preservation → named gates; run every mutation from the catalog and confirm re-RED; then the remaining device legs — TC-08-18/19 plus the TC-08-17 close re-run and the gate-blocking TURN-relayed evidence run (Execution Environment below).

---

## Risks And Edge Cases

- **Emulator camera realism:** the emulator's virtual camera emits a synthetic pattern; encode/decode is real but optics/rotation quirks are not → device leg holds the real camera (rule 1 split); pinned by TC-08-17/18 asserting counters, never content.
- **Renegotiation glare** (both upgrade at once) → TC-08-05 (VC-04 tie-break reused).
- **Ack ≠ consent** (Go acks `call_*` before Dart emit, node.go:1854-1860) → TC-08-04; timeout rollback TC-08-06.
- **Camera leak on rollback/decline/hangup** (battery/privacy) → TC-08-06/16.
- **Old-build peer receives a video offer / re-offer** → initial offer: `media` defaults audio on parse (step 2) so an old callee simply answers audio (TC-08-03 shape); re-offer: ignored → timeout rollback (TC-08-06).
- **Multi-video-m-line smuggle vs 1:1-only** → TC-08-07.
- **Orientation change drops renderers** → TC-08-12.
- **Uncapped video melts a TURN-relayed leg** → TC-08-08; adaptive behavior deliberately deferred to VC-09.
- **Speaker flip fighting VC-05 routing** → TC-08-10 discriminator (audio-only path asserts NO route call).

---

## Execution Environment  (VC-00 rule 1 — restated)

The implementing agent runs the full loop end-to-end on a **USB-connected Android device + Android emulator**. iOS simulators/devices are NOT part of this rig.

```bash
# Discovery / preflight (canonical pair per 256-plan convention)
adb devices -l            # expect USB device (e.g. 21071FDF600CSC) + emulator (e.g. emulator-5554, AVD mknoon_play_35)
flutter devices --machine
# Emulator must expose the virtual camera (renders a test pattern):
#   emulator -avd mknoon_play_35 -camera-back emulated -camera-front emulated
# If a target is unavailable: record "N/A (target unavailable by project policy)" — do not fake the leg.

# Host suites (no device)
flutter test test/features/call/ test/core/permissions/camera_permission_gateway_test.dart \
             test/core/services/ios_call_video_config_test.dart

# Single-leg device sanity (per-device suite form)
flutter test integration_test/call_video_device_proof_test.dart -d emulator-5554        # callee-side smoke
flutter test integration_test/call_video_device_proof_test.dart -d 21071FDF600CSC      # caller-side smoke

# Two-party legs (orchestrator conventions: comma list to -d; Android roles run
# `flutter test --no-pub <harness> -d <serial>` under the hood)
dart integration_test/scripts/run_call_device_real.dart --scenario video_call_e2e     -d 21071FDF600CSC,emulator-5554
dart integration_test/scripts/run_call_device_real.dart --scenario video_camera_switch -d 21071FDF600CSC,emulator-5554
dart integration_test/scripts/run_call_device_real.dart --scenario video_upgrade      -d 21071FDF600CSC,emulator-5554
# Leg assignment: USB device = caller/real camera + camera-switch actor; emulator = callee/virtual camera.
# TURN-relayed evidence (GATE-BLOCKING, run once): re-run video_call_e2e in the cross-network
# setup (device on cellular hotspot, emulator on host WiFi NAT) OR with forced-relay ICE config;
# getStats selected-candidate-pair must show candidateType == relay on at least one side WHILE
# frame deltas stay >= the TC-08-17 floor. This is the production topology the bandwidth caps
# were justified against — same-LAN direct ICE alone does not prove it.
# If the rig cannot force relay: record the justified N/A in Execution Progress and hand
# 'TURN-video unproven' to VC-09 BY NAME — never silently drop it.

# Relay/TURN env (defaults resolve to mknoun.xyz pair if unset)
export MKNOON_RELAY_ADDRESSES="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
```

**iOS boundary — deferred-not-waived:** the orchestrator's iOS role prints the device recipe and exits 0 without claiming proof (VC-00 rule 1 pattern). iOS *config* is still test-locked at host tier here (TC-08-15 Podfile/plist pins); the iOS video device-proof is owned by the macOS/iPhone session alongside VC-07.

---

## Device/Relay Proof Profile

- **Host-only for closure of the code contract:** TC-08-01..16 (state machine, guard, permission, caps, routing, UI, flags, teardown, metrics event).
- **Requires device for closure of the story (PROD-CRITICAL leg):** TC-08-17 (`video_call_e2e`) is the single path proving the real wire/media leg end-to-end — real camera → encoder → DTLS-SRTP (TURN when relayed) → decoder → renderer, both directions. It runs EARLY (Step 4b STOP/GO, before the upgrade machinery is built) and again at close. **Do NOT treat unit coverage as sufficient on its own**; host fakes cannot prove a single real frame moved. TC-08-18/19 close camera-switch and renegotiation on the real boundary. The TURN-relayed run (candidateType==relay, frame deltas ≥ floor) is gate-blocking evidence for the production NAT topology (justified-N/A escape hands 'TURN-video unproven' to VC-09 by name).
- Closure scenarios: `/sims 1to1 --list` → note the new `--only N` slots → run via the orchestrator commands above (`/sims` is a runner, never a registrar).
- Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…` (see /sims).
- **No relay/Go changes → VC-00 rule 2 (EC2 redeploy) does not fire.** The live TURN dependency is VC-03's deployed artifact, consumed read-only.

---

## Working Piece On Close

A demoable 1:1 **video call** between a USB Android device and an Android emulator: start as video (both previews live, speaker on), switch the device camera front↔back mid-call without freezing, or start as audio and upgrade to video mid-call with an explicit consent prompt on the other side — decline keeps talking, accept shows video. Frame/resolution telemetry flows into call flow events for VC-09 to build the quality loop on. Kill-switch flips it all back to exactly the VC-05 audio product.

## Metrics (VC-08's rows of the VC-00 metrics table)

| Metric | Named test / runsheet step |
|---|---|
| Video frame counters + resolution from `getStats` in call flow events (`framesEncoded/framesDecoded/frameWidth/frameHeight/framesPerSecond`) | TC-08-13 (host, event shape) + TC-08-17 runsheet step: capture both legs' `CALL_VIDEO_STATS` (`--dart-define=FDC_FLOW_LOG=1` force-on, `lib/main.dart:320-330`) and record two samples per side in the Execution Progress table |
| (Consumed, not owned) call setup / ICE pair type / loss / RTT / jitter / drop cause | VC-05 baseline + **VC-09** closes; VC-08 only appends the video fields to the same event stream |

---

## Acceptance Gates  (LITERAL — copy/paste; counts are baseline-captured at execution start, never hardcoded — VC-00 rule 6)

```bash
# 0) Baselines on the committed VC-05 tree (record in Execution Progress)
git status --short
./scripts/run_test_gates.sh 1to1              # capture green baseline count
./scripts/run_test_gates.sh baseline          # capture
./scripts/run_test_gates.sh groups            # capture (untouched — must not regress)
./scripts/run_host_test_gates.sh feature-host-all   # capture
./scripts/run_host_test_gates.sh core-host-all      # capture
flutter analyze                                # record baseline issue count (dirty tree)

# 1) RED (before production edits) — each must FAIL for its documented reason
flutter test test/features/call/application/call_session_video_test.dart
flutter test test/features/call/application/call_video_upgrade_test.dart
flutter test test/features/call/domain/sdp_video_topology_guard_test.dart
flutter test test/features/call/application/call_video_flags_test.dart
flutter test test/features/call/presentation/call_screen_video_test.dart
flutter test test/core/permissions/camera_permission_gateway_test.dart
flutter test test/core/services/ios_call_video_config_test.dart --plain-name 'VC-08-15'

# 2) Direct GREEN (after implementation)
flutter test test/features/call/ test/core/permissions/camera_permission_gateway_test.dart \
             test/core/services/ios_call_video_config_test.dart

# 3) Preservation sentinels + named gates (compare to §0 baselines; delta must be exactly the new tests)
./scripts/run_test_gates.sh 1to1              # includes the ONE_TO_ONE_TESTS additions + relay-notification Go gate (GOTOOLCHAIN=go1.25.0, pinned invocation — no new Go tests in VC-08)
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# 4) Registration hygiene (rule 6)
./scripts/run_test_gates.sh completeness-check          # every new *_test.dart classifies
./scripts/check_reliability_simulation_discovery.sh     # proof file + new orchestrator scenarios list
./scripts/run_test_gates.sh reliability-sim 1to1 --list # dry-run shows the video slots (--only N)

# 5) Device closure (rule 1) — see Execution Environment for env/serials.
#    NOTE: video_call_e2e FIRST runs at Step 4b as the early payoff STOP/GO gate; this is the close re-run.
#    All legs enforce the frame floor: framesDecoded delta >= 25 per >=5 s window, each side.
dart integration_test/scripts/run_call_device_real.dart --scenario video_call_e2e      -d 21071FDF600CSC,emulator-5554
dart integration_test/scripts/run_call_device_real.dart --scenario video_camera_switch -d 21071FDF600CSC,emulator-5554
dart integration_test/scripts/run_call_device_real.dart --scenario video_upgrade       -d 21071FDF600CSC,emulator-5554
# TURN-relayed evidence (gate-blocking, once): cross-network or forced-relay video_call_e2e run;
# record getStats selected-candidate-pair candidateType==relay + frame deltas >= floor.
# Rig cannot force relay -> justified N/A recorded + 'TURN-video unproven' handed to VC-09 by name.

# 6) Hygiene
flutter analyze            # 0 new vs §0 baseline
git diff --check
```

## Known-Failure Interpretation

- **Expected RED:** every §1 command before implementation (VC-08-01..16 as compile errors or documented assertions; VC-08-15 as the missing Podfile macro).
- **Pre-existing dirty:** whatever `git status --short` shows at §0 — preserve, never revert/absorb/reformat (harness convention, plans 254/256/257).
- **Environment blocker (NOT product):** missing USB device or emulator, emulator without virtual camera, unreachable mknoun.xyz TURN — record `N/A (target unavailable by project policy)` and stop; do not substitute a host fake for the PROD-CRITICAL leg.
- **Below-floor frame deltas on a device leg (NOT a pass):** counters advancing but framesDecoded delta < 25 per ≥5 s window — the Step 4b/TC-08-17 STOP condition; keep the kill-switch default OFF, record the deltas, replan caps/encoder approach. Never close the story on a slideshow.
- **Expected-delta:** §3 counts differ from §0 by exactly the new VC-08 tests — diff named tests, not raw counts.
- **Scope drift (BLOCKING):** any failure in `groups`/`baseline`/non-call `1to1` suites, any Go test change, anything under `go-relay-server/` — outside the Scope Guard, stop and replan.
- **A VC-08 RED passing on the baseline** means VC-05 already shipped that surface — re-verify against the VC-05 diff before assuming a stale plan.

## Done Criteria

- [ ] RED added first (VC-08-01..16 host + 17..19 proof), each failing on the VC-05 baseline for its documented reason.
- [ ] Mutation-verified: every production edit has its named revert re-REDing a named test (catalog per-case).
- [ ] Direct GREEN + preservation sentinels (P1..P4) + named gates pass at baseline-or-expected-delta counts.
- [ ] No migration (none needed — no schema change; rule-5 ephemerality preserved).
- [ ] OS-boundary/media legs proven on the device rig, not a fake: TC-08-17 green at Step 4b (early payoff gate) AND at close, TC-08-18/19 green device↔emulator — all legs meeting the frame floor (framesDecoded delta ≥ 25 per ≥5 s window, each side; below floor = STOP, kill-switch stays default OFF); iOS deferred-not-waived recipe printed.
- [ ] TURN-relayed evidence recorded (gate-blocking): one video_call_e2e run with selected-candidate-pair `candidateType==relay` and frame deltas ≥ floor — or the justified N/A recorded with 'TURN-video unproven' handed to VC-09 by name.
- [ ] Every new test's harness registration done AND verified: completeness-check green, discovery script green, `/sims 1to1 --list` shows the video slots, `1to1` gate runs the two array additions; 4 gate docs updated together.
- [ ] Kill-switch OFF path proven ≡ VC-05 (TC-08-14) — rule 3 revert path locked.
- [ ] `CALL_VIDEO_STATS` captured from both device legs and recorded (metrics contract).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")

- Do not touch `go-relay-server/` or `go-mknoon/` (no Go edits in VC-08; rule 2 stays un-fired; no `feature_flags.go`/bridge-flag-map/polarity-pin churn).
- Do not implement ICE restart, network-switch handling, degradation ladder, quality-metrics aggregation, or the "always relay" toggle — **VC-09** owns them.
- Do not touch push payloads, FCM handler types, `NotificationRouteTarget`, full-screen intent, or FGS types — **VC-06** owns ringing.
- Do not touch `UIBackgroundModes`, CallKit/PushKit, or any iOS capability beyond the single Podfile `PERMISSION_CAMERA=1` line — **VC-07** owns iOS VoIP.
- Do not add a new `call_*` envelope type or a new `IncomingMessageRouter` case (reuse decision; VC-04 owns the router surface).
- Do not add group/multi-party or screen-share paths (never in epic); do not weaken the 1:1 topology guard.
- Do not persist any call/video envelope via `messageRepo` or let it enter retrier sweeps (rule 5).
- Do not add a new network primitive to `P2PServiceImpl`; if one becomes unavoidable, it must first-line `_allowsAccountNetworkSideEffects(...)` (rule 4) and be re-reviewed.
- Do not edit VC-05 audio behavior except through the named seams (session controller video branches, teardown extension).

## Accepted Differences / Intentionally Out Of Scope

- Fixed VGA@30/800kbps caps with **no adaptation** — deliberately static; VC-09 owns the ladder off the very stats events VC-08 adds.
- On upgrade-decline the requester rolls back to audio (no one-way video) — simpler symmetric model; one-way video could be a later product call, VC-09+/product owns it.
- `NSCameraUsageDescription` wording (profile/QR) is not rewritten for calls — copy change, deferrable; the pin locks presence, not prose.
- Emulator leg proves encode/decode with a synthetic pattern, not real-optics quality — accepted per rule 1 rig; content assertions are explicitly forbidden in the proof.
- Video-call ring UX (callee sees "video call" pre-answer) ships with **VC-06**; until then an incoming video call rings like audio and consent happens at answer time.

## Dependency Impact

- **Depends on:** VC-05 (call feature, WebRTC seam, orchestrator — hard prerequisite tree), VC-04 (envelope `(callId,seq,ttlMs)` + glare machinery the re-offer reuses), VC-03 (deployed TURN for the relayed device leg).
- **VC-09 depends on VC-08 because:** the degradation ladder manipulates the sender caps VC-08 installs (TC-08-08 seam) and consumes `CALL_VIDEO_STATS` (TC-08-13 event contract) — do not rename either without VC-09 coordination.
- **VC-06 depends on VC-08's `media` field because:** the call-invite push should label video calls; contract = `call_offer.media` round-trips the envelope (TC-08-01). VC-06 reads, never writes, this field.
- **VC-07 (iOS)** inherits the Podfile `PERMISSION_CAMERA=1` + plist pins when the iOS device session runs video proofs.
- **Collision surfaces:** `lib/features/call/**` (VC-05/VC-08/VC-09 — strictly sequential per VC-00 collision map); `scripts/run_test_gates.sh` `ONE_TO_ONE_TESTS` + the 4 gate docs (small rebases expected with any parallel story doing the same).

## Reviewer Findings

/tdd-review verdict (2026-07-13, assessment + cross-plan locks; no salvaged verifier findings for this plan). Dimension scores: goal-clarity 85 (strong), compartmentalization 66 (adequate), anti-drift 80 (strong), define-good 78 (strong), goal-verification 72 (adequate). Counts: 1 material, 4 moderate, 6 nits — all applied. Applied: (1) MATERIAL — PROD-CRITICAL device leg TC-08-17 pulled forward to new Step 4b as an early payoff STOP/GO gate (it depends only on steps 0–4; emulator/software-encode feasibility is now validated before the upgrade/consent/UI stack is built); (2) MODERATE — TC-08-14 flag-OFF incoming path split into explicit cases (initial video offer rings normally with `CALL_INCOMING_RING`, user-answer → audio; upgrade re-offer auto-declined, no prompt) closing the auto-answer-without-ring loophole; (3) MODERATE — frame floor pinned on all device legs (framesDecoded delta ≥ 25 per ≥5 s window each side) with an explicit STOP-keep-kill-switch-OFF condition (also closes the goal-clarity partial-win nit); (4) MODERATE — TURN-relayed run promoted to gate-blocking evidence (candidateType==relay + floor, justified-N/A escape handing 'TURN-video unproven' to VC-09 by name); (5) MODERATE — INV-6 'exact' OFF-equivalence now executed, not asserted: parameterized `CallVideoFlags(enabled:false)` re-run of VC-05's headline suites inside TC-08-14; (6) nits — `CALL_VIDEO_ENABLED` naming deviation from `MKNOON_*` justified inline (Dart-only, never crosses the Go flag merge); RED authoring batched per slice; glare tie-break pinned to VC-04's lower-peerId comparator (verified against VC-04 plan Step D) with stop-if; Step 0 seam stop-if extended to audio output routing; TC-08-19 auto-accept hook constrained to drive `acceptVideoUpgrade()` through the consent state machine with a consent-accepted event assertion. Locks applied: L1 (upgrade answer timeout = VC-04 `kCallOfferTtl` = 45000 ms, min(45 s, TTL remaining from `sentAtMs`); 30–60 s band noted as design choice) and L5 (no new family array — ONE_TO_ONE_TESTS for headline, NIGHTLY_ONLY_TESTS for any heavy host e2e, `run_call_device_real.dart` honoring `--scenario all`/`--list-scenarios`; step 8's 'dedicated call family array' conditional resolved away). Source-verified correction: the VC-04 envelope type list in Source Of Truth fixed to the six actual types (`call_offer/call_answer/call_ice_candidates/call_end/call_decline/call_busy` — the plan previously cited nonexistent `call_reject`/`call_hangup`).

## Arbiter Decision

Structural blockers: none. | Deferred details: exact VC-05 seam names and headline-suite file names (stop-if-guarded re-anchor in Step 0; the answer-timeout constant is no longer deferred — locked L1 at 45000 ms). | Accepted differences: as listed above, plus the 'TTL-d wake deposit' ring alternative is globally REJECTED per lock L2 (call_* is never durable-inboxed — this plan never proposed it; ringing remains VC-06's `call_push_request` mechanism, out of VC-08 scope). Hand off to execution once VC-05 is committed and green.

## Final Execution Verdict

Verdict: (pending execution) | Files changed: — | Tests run (+counts): — | Blocking: — | QA verdict: — | Non-blocking follow-ups (owner): —
