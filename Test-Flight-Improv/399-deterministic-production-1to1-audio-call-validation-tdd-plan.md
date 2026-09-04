# 399 - Deterministic Production 1:1 Audio-Call Validation TDD Plan

## 0. Metadata

| Field | Value |
|---|---|
| Plan | 399 |
| Status | Device-closed for bounded automated Android audio transport (2026-09-03); acoustic audibility remains out of scope |
| Classification | Implementation-ready feature-validation improvement |
| Closure class | Device |
| Created | 2026-09-02 |
| Product scope | UI-24 1:1 foreground audio calls on Android |
| Required device topology | One USB-connected physical Android plus one Android emulator |
| Current pinned tuple | Callee: Pixel 6, 21071FDF600CSC, Android 16/API 36; caller: emulator-5554, Android 17/API 37 |
| Required relay topology | Local production libp2p signaling relay plus local coturn; no EC2 relay fallback |
| Required Go toolchain | GOTOOLCHAIN=go1.25.0 for every Go command and child process |
| Dependencies | VC2-01 through VC2-04 production call stack; existing Sims build cache and Android device runners |
| Follow-on owner | VC2-06 remains responsible for production audio-quality and one-way-audio observability policy |

This plan validates and minimally instruments the existing implementation. It does not replace the current flutter_webrtc call stack, signaling protocol, or native Android lifecycle.

The repository already contains substantial uncommitted UI-24 work. Execution must preserve that work and apply only additive, reviewed changes. No baseline tests were run while authoring this plan.

## 1. Planning Progress

- [x] Confirm the live Android topology and pin explicit target IDs.
- [x] Inspect the existing production call graph, device campaigns, local relay fixture, TURN issuer, native answer path, and gate registration.
- [x] Identify a real behavioral gap rather than assuming the audio stack is absent.
- [x] Select the smallest useful open-source additions.
- [x] Define causal RED tests, meaningful mutation checks, exact gates, and device proof.
- [x] Capture causal REDs for the selected wake-authority, observer-binding, identity, and evidence-validation subset.
- [x] Implement the selected fast-validation subset with focused GREEN tests.
- [x] Complete the full host, container, and physical-device acceptance contract, including production RTP observation and the Pion known-Opus oracle.
- [x] Record the selected device evidence without weakening the deferred RTP assertions.

## 2. Problem and Evidence

### 2.1 User-observed failure

The reproduced failure is asymmetric after the callee presses Answer:

- The Pixel receives the incoming call.
- The Pixel user presses the native Answer action.
- The iPhone/caller transitions as if the call opened.
- The Pixel returns to the ordinary conversation screen instead of retaining the active-call surface.

The default automated reproduction for this plan uses the physical Pixel as callee and the Android emulator as caller. It exercises the same callee-side Answer boundary without making iOS a prerequisite.

### 2.2 What already exists

Current source inspection shows:

- integration_test/scripts/android_foreground_webrtc_audio_campaign.dart already requires two explicit Android targets, orders a physical device before an emulator, pregrants permissions, restores app state, launches peers concurrently, and pins adb commands to a serial.
- integration_test/support/android_foreground_webrtc_audio_probe.dart and android_foreground_webrtc_audio_proof.dart already use flutter_webrtc and verify bidirectional RTP packet and byte movement.
- integration_test/support/android_foreground_webrtc_audio_canonical_stack.dart is deliberately test-scoped. It uses fixed test identities, an in-memory carrier, an accepting presenter, and direct stack place and answer calls.
- scripts/run_vc204_android_call_lifecycle_e2e.sh proves native Telecom and CallStyle lifecycle behavior in a disposable proof application, not the two-user production app journey.
- integration_test/scripts/android_voice_message_device_campaign.dart already demonstrates the desired main-app pattern: one cached lib/main.dart APK, automatic identity/contact setup, app-private result files, two endpoints, and state restoration.
- integration_test/scripts/run_direct_media_blob_custody_sims.dart and go-relay-server/direct_media_blob_custody_device_fixture_test.go already demonstrate a device-reachable local production libp2p relay with ephemeral miniredis and central Sims build ownership.
- go-relay-server/turn_credentials.go and protocol_handlers.go already provide the production coturn REST credential authority and handler registration.
- the production WebRTC snapshot already proves selected-pair, DTLS, audio-session, sender/receiver, and live-track readiness. Product connected readiness intentionally does not depend on silence, mute, RTP counts, or energy.

### 2.3 Confirmed gap

No single registered proof currently binds all of these boundaries:

1. A real lib/main.dart caller opens a real conversation.
2. The caller taps the production voice-call control.
3. Signaling uses only a local production libp2p relay.
4. The callee receives the real Android native incoming-call presentation.
5. The host driver activates the real native Answer action.
6. Both production apps retain the active-call surface and reach canonical media readiness.
7. Both production peer connections demonstrate inbound and outbound audio RTP movement over the forced local TURN route.
8. User-visible mute, route, and hang-up controls converge on both endpoints.
9. The native call notification/service and app call state are cleaned up.

The current device audio proof bypasses items 1, 2, 4, and 5. The VC2-04 native proof bypasses the production two-user app, signaling, and media path.

### 2.4 Deterministic-audio limitation

The existing Android campaign unmutes real microphones and observes RTP movement. It does not inject a known audio waveform. Android Emulator host-microphone support is not a dependable, portable file-injection interface, and the physical Pixel cannot receive a deterministic microphone stream without adding a test-only native audio source.

This plan therefore uses two complementary proofs:

- The real production apps must show bidirectional audio RTP movement and complete media readiness on the physical Pixel and emulator.
- A test-only Pion oracle must send a license-free, known Opus fixture through the same local coturn instance in both directions and verify the received RTP payload sequence and hash.

Together these prove production call wiring, app audio transport movement, TURN correctness, and deterministic encoded-media forwarding. They do not prove speaker loudness, microphone sensitivity, acoustic echo behavior, or human speech intelligibility. Those are explicitly not claimed by this plan.

## 3. Graph Snapshot

The architecture graph was used only to navigate candidate code. Load-bearing conclusions above were verified in current source and exact tests.

| Branch | Query ID | Evidence digest | Anchor and result |
|---|---|---|---|
| Existing Android audio campaign | c971dfc5bf6c4954 | 0c4c55dc37183c4d | wireSummary in android_foreground_webrtc_audio_campaign.dart; the graph did not itself prove the missing production journey |
| Android native Answer lifecycle | fae661fe4fe148d6 | d8195b99368d0300 | wait_for_network_boundary in run_vc204_android_call_lifecycle_e2e.sh; confirmed isolated native proof ownership |
| Production call graph | f88ec99d9f9449cc | 6cff45f11cb39d36 | androidCallLifecycleAdapter in production_call_signaling_graph.dart; connected production composition, lifecycle adapter, and foreground projection candidates |
| TURN authority | 52f06f2ead5545e0 | 0024b34ed8711bfb | Turn credential service and handler candidates in go-relay-server |
| Main-app device harness | 629292bab5474dc1 | 508fa44e57ad2bae | app-private file writer in android_voice_message_device_campaign.dart; confirmed reusable identity/contact and central-build pattern |
| Native Gradle fallback | c2c8251413194e47 | b355cb2d2e8b0620 | full-graph native lookup of android/app/build.gradle.kts; verified the enableAndroidNativeCalls property |

Graph fingerprints changed while other in-progress work modified the repository, and freshness warnings named active call/bootstrap tests. The execution owner must treat this snapshot as navigation provenance, not as a clean-baseline or runtime-pass claim.

## 4. Recommendation and Scope

### 4.1 Adopt

- Keep flutter_webrtc and the canonical UI-24 call state machine.
- Reuse the current Dart Sims and adb orchestration instead of introducing another device-runner framework.
- Run an official coturn container locally, pinned by version and immutable image digest.
- Add a test-only Pion Go module, pinned to github.com/pion/webrtc/v4 v4.2.19, as the deterministic known-Opus TURN oracle.
- Add a dedicated main-app Sims build profile and a registered production call scenario.
- Add only privacy-safe boolean RTP-motion evidence. Raw stats, counters, addresses, identifiers, SDP, ICE candidates, credentials, and audio samples must not leave process memory.

### 4.2 Do not adopt in this plan

- Mobly or Appium: the repository already has two-device selection, concurrent launch, state guarding, target-pinned adb control, central builds, artifact collection, and Sims registration. A second orchestration stack would duplicate those capabilities.
- LiveKit or another managed calling stack: that is an architecture migration, not a repair for the missing end-to-end proof.
- WebTrit callkeep or a second Android call-lifecycle plugin: the app already owns its native Telecom and CallStyle path.
- Pion as an embedded TURN server or as shipped application code: coturn remains the TURN server; Pion is a host-only media oracle.
- An iPhone as the second endpoint: this behavior is not iOS-specific and the required Android pair is currently available.

### 4.3 In scope

- One dedicated, default-off main-app build profile named android.e2e.production_call_local.
- A local fixture adapter that owns libp2p relay, miniredis, coturn, temporary TURN credentials, Pion preflight, central Sims preparation, and teardown.
- Privacy-safe inbound/outbound audio-RTP-observed booleans carried through the call snapshot without changing connected semantics.
- A read-only E2E observer armed through the existing debug file channel.
- A semantic Android UI driver for the production call button and native Answer action.
- A two-device production journey, evidence schema, cleanup contract, failure artifacts, and gate registration.

### 4.4 Out of scope

- Product signaling, crypto, identity, call-state, or native lifecycle redesign.
- EC2 relay validation.
- iOS CallKit or PushKit validation.
- Group calls, video calls, background audio, or PSTN.
- Human acoustic-quality certification.
- Any product behavior that makes connected depend on RTP counts, audio energy, speech, or mute state.
- Changes to messages, voice messages, notifications outside call lifecycle, contacts, or onboarding behavior.

## 5. Target Proof Architecture

    Host Dart fixture adapter
      |
      +-- production libp2p relay + ephemeral miniredis
      |       |
      |       +-- production TURN credential handler
      |
      +-- coturn container, pinned tag and digest
      |       |
      |       +-- Pion peer A <== known Opus in both directions ==> Pion peer B
      |       |
      |       +-- Pixel production app <==== forced TURN ====> emulator production app
      |
      +-- central Sims build cache
      |       |
      |       +-- one lib/main.dart APK installed on both endpoints
      |
      +-- target-pinned adb semantic UI driver
              |
              +-- emulator conversation call button
              +-- Pixel native Answer action
              +-- both active-call surfaces and controls

The Pion branch is an independent fixture oracle. It cannot satisfy or replace the mobile-app device gate.

## 6. Test Contract

Every new test must be committed first, run to an observable RED, and only then receive its minimal implementation. A missing test file is not the recorded RED: the execution log must show the newly added test failing against the pre-change behavior or contract.

| ID | Tier | Exact proof owner | HEAD to GREEN expectation | Required mutation sensitivity |
|---|---|---|---|---|
| TC-399-01 | AUTO host | test/tool/sims/sims_manifest_test.dart: production 1to1 audio call uses one main-app APK on physical Android and emulator | RED because the profile/scenario/resources do not exist; GREEN only with lib/main.dart, both device resources, local fixture dependency, and every required call define | Removing VOICE_CALL_ALWAYS_RELAY_ENABLED, either device resource, or the main-app entrypoint turns it RED |
| TC-399-02 | AUTO host | test/tool/sims/sims_build_cache_test.dart: production call profile cache key includes native call property and call defines | RED because no profile-specific native-call build argument is hashed; GREEN only when enableAndroidNativeCalls=true and all call defines affect the cached artifact identity | Ignoring the native Gradle argument or any call define in the cache key turns it RED |
| TC-399-03 | AUTO feature | test/features/call/infrastructure/call_stats_sampler_test.dart: collapses bidirectional audio RTP observations to booleans without retaining raw stats | RED because current snapshots omit RTP-motion booleans; GREEN with audio-only inbound/outbound observation and no exposed count, ID, address, SDP, candidate, or energy | Counting video, accepting zero packets, or exposing numeric/raw data turns it RED |
| TC-399-04 | AUTO core | test/core/debug/android_production_audio_call_e2e_test.dart: observer is read-only profile-bound privacy-safe and nonce-bound | RED because the observer does not exist; GREEN only when the dedicated E2E profile can arm observation and the default profile constructs no observer | Enabling it by default, giving it place/answer/end authority, or exporting raw call/peer data turns it RED |
| TC-399-05 | REAL host-container | go-relay-server/production_audio_call_device_fixture_test.go: TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown | RED because no combined fixture exists; GREEN with production handler registration, ephemeral miniredis, per-run REST secret, device-reachable TURN URLs, bounded relay ports, readiness, and cleanup | Removing TurnCredentials, reusing a static secret, advertising a remote URL, or leaking the secret turns it RED |
| TC-399-06 | REAL host-container | tool/call_audio_oracle/oracle_test.go: TestKnownOpusBothDirectionsOverRestAuthenticatedCoturn | RED because the module and fixture do not exist; GREEN only when two Pion peers force relay and verify exact bidirectional Opus RTP payload count/order/hash through coturn | Allowing a direct candidate, changing one fixture byte, accepting one direction, or accepting an expired credential turns it RED |
| TC-399-07 | AUTO host | scripts/test/production_audio_call_fixture_adapter_contract_test.sh | RED because the adapter is absent; GREEN only when it pins Go 1.25.0, pins coturn by digest, starts dependencies before Sims, uses unique resources, and tears down in a finally path | Replacing GOTOOLCHAIN=go1.25.0 with ambient Go, using latest, or removing teardown turns it RED |
| TC-399-08 | AUTO host | test/integration/android_production_audio_call_campaign_test.dart: requires one physical Android and one emulator, drives semantic UI, and launches peers concurrently | RED because the production campaign is absent; GREEN only with ordered explicit serials, no coordinate fallback, exact-one accessibility selection, Future.wait peer launch/polling, and caller-emulator/callee-physical roles | Accepting two emulators, omitting a serial, hard-coding coordinates, or serializing independent peer work turns it RED |
| TC-399-09 | AUTO host | test/integration/android_production_audio_call_campaign_test.dart: restores both apps and tears down relay coturn and oracle after every terminal path | RED because no campaign cleanup exists; GREEN after injected caller, callee, UI, and evidence failures all restore/stop exactly once | Removing the outer finally or swallowing teardown failure turns it RED |
| TC-399-10 | AUTO host | test/integration/android_production_audio_call_evidence_test.dart: accepts only nonce-bound boolean production-call evidence and rejects private material | RED because the schema is absent; GREEN with an exact allowlist and cross-peer run/artifact binding | Adding SDP, candidate, address, credential, raw ID, RTP count, or audio content to the allowlist turns it RED |
| TC-399-11 | AUTO host | scripts/test/reliability_simulation_discovery_contract_test.sh | RED after the runner exists but before registration; GREEN only when the scenario, build profile, resources, artifact validator, path classifier, and runner dispatch are discoverable | Removing any one registration site turns it RED |
| TC-399-12 | GREEN preservation | test/features/call/infrastructure/android_call_lifecycle_adapter_test.dart: adopts a pre-start answer but dispatches it only after ringing | Must remain GREEN; proves the native Answer journal reaches canonical accepted state only after ringing is adopted | Dropping the Answer command, native acknowledgement, or accepted dispatch turns it RED |
| TC-399-13 | GREEN preservation | test/features/call/presentation/foreground_call_overlay_test.dart: maps only the canonical foreground call states | Must remain GREEN; protects accepted/connected active surfaces and canonical call-ID action dispatch | Hiding accepted/connected or dispatching a stale displayed call turns it RED |
| TC-399-14 | GREEN preservation | test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart: silent muted media is ready only when every structural gate is ready | Must remain GREEN; new RTP evidence is observational and cannot enter product readiness | Adding packet, energy, unmuted, or speech requirements to isMediaReady turns it RED |
| TC-399-15 | DEVICE | android.production_1to1_audio_call | RED at HEAD because the scenario does not exist; GREEN only for the complete local-relay production journey on the pinned Pixel/emulator pair | Returning success after Answer without both overlays, both RTP directions, forced TURN, terminal convergence, and cleanup turns it RED |
| TC-399-16 | GREEN preservation | test/integration/android_foreground_webrtc_audio_campaign_test.dart | Must remain GREEN; preserves the existing canonical direct/relay audio campaign contract while the new production journey is added | Weakening explicit topology, RTP directionality, or app-state restoration turns it RED |

### 6.1 Exact focused commands

TC-399-01:

    flutter test test/tool/sims/sims_manifest_test.dart --plain-name 'production 1to1 audio call uses one main-app APK on physical Android and emulator'

TC-399-02:

    flutter test test/tool/sims/sims_build_cache_test.dart --plain-name 'production call profile cache key includes native call property and call defines'

TC-399-03:

    flutter test test/features/call/infrastructure/call_stats_sampler_test.dart --plain-name 'collapses bidirectional audio RTP observations to booleans without retaining raw stats'

TC-399-04:

    flutter test test/core/debug/android_production_audio_call_e2e_test.dart --plain-name 'observer is read-only profile-bound privacy-safe and nonce-bound'

TC-399-05:

    cd go-relay-server
    GOTOOLCHAIN=go1.25.0 go test -tags=integration . -run '^TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown$' -count=1 -v -timeout=10m

TC-399-06:

    cd tool/call_audio_oracle
    GOTOOLCHAIN=go1.25.0 go test -tags=integration ./... -run '^TestKnownOpusBothDirectionsOverRestAuthenticatedCoturn$' -count=1 -v -timeout=10m

TC-399-07:

    bash scripts/test/production_audio_call_fixture_adapter_contract_test.sh

TC-399-08:

    flutter test test/integration/android_production_audio_call_campaign_test.dart --plain-name 'requires one physical Android and one emulator, drives semantic UI, and launches peers concurrently'

TC-399-09:

    flutter test test/integration/android_production_audio_call_campaign_test.dart --plain-name 'restores both apps and tears down relay coturn and oracle after every terminal path'

TC-399-10:

    flutter test test/integration/android_production_audio_call_evidence_test.dart --plain-name 'accepts only nonce-bound boolean production-call evidence and rejects private material'

TC-399-11:

    bash scripts/test/reliability_simulation_discovery_contract_test.sh

TC-399-12:

    flutter test test/features/call/infrastructure/android_call_lifecycle_adapter_test.dart --plain-name 'adopts a pre-start answer but dispatches it only after ringing'

TC-399-13:

    flutter test test/features/call/presentation/foreground_call_overlay_test.dart --plain-name 'maps only the canonical foreground call states'

TC-399-14:

    flutter test test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart --plain-name 'silent muted media is ready only when every structural gate is ready'

TC-399-15:

    RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 GOTOOLCHAIN=go1.25.0 dart run integration_test/scripts/run_production_audio_call_sims.dart --mode major --scenario android.production_1to1_audio_call

TC-399-16:

    flutter test test/integration/android_foreground_webrtc_audio_campaign_test.dart

If either Android serial changes, rerun discovery, record the replacement exact physical/emulator IDs in the execution log, and invoke TC-399-15 with those explicit IDs. Do not use an unqualified Flutter or adb target.

## 7. Implementation Steps

### PH-399-00 - Freeze the behavioral contract and capture RED

Files:

- The exact test owners named in TC-399-01 through TC-399-11.
- No production files in this phase.

Actions:

1. Verify the Go command reports go1.25.0.
2. Rediscover Flutter, adb, and available simulator/device targets.
3. Verify Docker client and daemon availability.
4. Add one causal test at a time.
5. Run its exact command and retain a concise RED record that names the missing behavior.
6. Do not accept a typo, missing import unrelated to the designed interface, device ambiguity, or unavailable tool as the behavioral RED.

Exit:

- Every causal TC has a meaningful RED and mutation target.
- Existing preservation tests are identified but not edited to manufacture RED.

### PH-399-01 - Add the dedicated main-app build and scenario contracts

Files:

- tool/sims/critical_features.json
- tool/sims/build_orchestrator.dart
- test/tool/sims/sims_manifest_test.dart
- test/tool/sims/sims_build_cache_test.dart

Required profile:

- Name: android.e2e.production_call_local.
- Entrypoint: lib/main.dart.
- One centrally built arm64 APK reused by both Android endpoints.
- Existing E2E mode enabled.
- VOICE_CALL_CAPABILITY_V1=true.
- VOICE_CALL_OUTGOING_ENABLED=true.
- VOICE_CALL_INCOMING_ENABLED=true.
- VOICE_CALL_TURN_ENABLED=true.
- VOICE_CALL_ANDROID_NATIVE_ENABLED=true.
- VOICE_CALL_ALWAYS_RELAY_ENABLED=true.
- A new exact production-call E2E observer define enabled only in this profile.
- Android project argument enableAndroidNativeCalls=true.

The build-cache identity must include every Dart define and the native-call Gradle property. Default, release, and unrelated E2E profiles must remain unchanged and default-off.

Exit:

- TC-399-01 and TC-399-02 are GREEN.
- A deliberate removal of ALWAYS_RELAY or enableAndroidNativeCalls makes the relevant test RED.

### PH-399-02 - Add privacy-safe production audio-flow observation

Files:

- lib/features/call/infrastructure/call_stats_sampler.dart
- lib/features/call/infrastructure/webrtc_types.dart
- lib/features/call/infrastructure/flutter_webrtc_call_engine.dart
- lib/features/call/domain/call_engine.dart
- test/features/call/infrastructure/call_stats_sampler_test.dart
- test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart

Actions:

1. Parse only audio inbound-rtp and outbound-rtp records.
2. Collapse positive packet observation to two booleans before the snapshot leaves the infrastructure adapter.
3. Do not expose packet/byte values, SSRC, track IDs, report IDs, addresses, candidate details, SDP, audio level, or energy.
4. Carry the booleans through the canonical connection snapshot as diagnostics.
5. Keep isMediaReady byte-for-byte equivalent in meaning: structural connection/media gates only.
6. Treat the booleans as device-proof evidence, never as a product state-transition gate or auto-hangup rule.

Exit:

- TC-399-03 and TC-399-14 are GREEN.
- Mutations for audio/video classification and readiness independence are demonstrated.

### PH-399-03 - Build the local production relay and coturn fixture

Files:

- go-relay-server/production_audio_call_device_fixture_test.go
- integration_test/scripts/production_audio_call_local_fixture.dart
- scripts/test/production_audio_call_fixture_adapter_contract_test.sh
- A coturn image lock file under tool/call_audio_oracle.

Actions:

1. Reuse production registerRelayProtocolHandlers rather than copying call handlers.
2. Start ephemeral miniredis and a device-reachable production libp2p relay.
3. Generate a random per-run coturn REST secret and keep its config in a mode-0600 temporary directory.
4. Start coturn/coturn:4.17.2-r0 by immutable multi-platform image digest, never latest.
5. Map TCP/UDP listener ports and a bounded UDP relay range to the host; advertise only the verified host LAN address.
6. Configure the production TurnCredentialService with local TURN URLs and the same per-run secret.
7. Emit readiness containing only local endpoints needed in process memory plus durable version/digest hashes. Never print the secret or issued password.
8. Verify both explicit Android endpoints can reach the libp2p relay and coturn listener before building or launching apps.
9. On every exit, stop the Go fixture, coturn container, child processes, and delete temporary credential material.
10. Launch every Go process with GOTOOLCHAIN=go1.25.0 in its environment. Do not rely on ambient Go.

Exit:

- TC-399-05 and TC-399-07 are GREEN.
- Process and container inventory before/after the injected-failure test is identical.

### PH-399-04 - Add the deterministic Pion media oracle

Files:

- tool/call_audio_oracle/go.mod
- tool/call_audio_oracle/go.sum
- tool/call_audio_oracle/oracle.go
- tool/call_audio_oracle/oracle_test.go
- tool/call_audio_oracle/DEPENDENCIES.md
- test/shared/fixtures/call/known_signal_48khz_mono.ogg
- test/shared/fixtures/call/known_signal_48khz_mono.provenance.json

Actions:

1. Declare go 1.25.0 and pin github.com/pion/webrtc/v4 v4.2.19.
2. Record Pion and coturn source, version, license, and immutable dependency hashes.
3. Commit a tiny self-generated, license-free, non-speech Opus/Ogg fixture with generation formula, sample properties, license, and SHA-256 provenance.
4. Create two headless Pion peers with relay-only ICE policy.
5. Give each peer a fresh credential issued by the same production TURN authority used by the mobile run.
6. Send the known fixture A to B and B to A.
7. At each receiver, validate audio codec, RTP payload count/order, and aggregate payload SHA-256.
8. Require the selected candidate pair to be relay and match the expected coturn transport class.
9. Close both peers and prove no oracle-owned goroutine/process/resource remains.

The oracle may consume temporary issued credentials through a mode-0600 file or pipe. It must not receive the coturn REST secret and must not write credentials to durable evidence.

Exit:

- TC-399-06 is GREEN.
- Direct-path and single-direction mutations are demonstrated.

### PH-399-05 - Add the read-only production-app E2E observer

Files:

- lib/core/debug/android_production_audio_call_e2e.dart
- lib/core/debug/intro_e2e_runner.dart
- lib/debug/debug_e2e_composition_root.dart
- lib/app/bootstrap/production_application_bootstrap.dart
- test/core/debug/android_production_audio_call_e2e_test.dart

Actions:

1. Reuse the existing app-private E2E command/result channel.
2. Wire the observer to the canonical ForegroundCallCapability and connection snapshot from the production call composition.
3. Permit the host command only to arm, sample, and stop observation.
4. Do not expose or inject place, answer, reject, hang-up, mute, or route actions through the observer.
5. Emit a nonce-bound, privacy-safe state sequence and booleans for:
   - outgoing/ringing/accepted/connected/terminal observations;
   - foreground active-call surface visibility;
   - structural media readiness;
   - relay-only policy and selected relay transport;
   - local-audio enabled state;
   - inbound and outbound audio RTP observed.
6. Bind output to role, run nonce, profile digest, APK digest, and a one-way call-binding hash.
7. Construct nothing when the dedicated profile define is false.

Exit:

- TC-399-04 is GREEN.
- Default build/profile exclusion and read-only authority mutations are demonstrated.

### PH-399-06 - Implement the fully automated production device campaign

Files:

- integration_test/scripts/android_production_audio_call_campaign.dart
- integration_test/scripts/run_production_audio_call_sims.dart
- integration_test/support/android_production_audio_call_evidence.dart
- test/integration/android_production_audio_call_campaign_test.dart
- test/integration/android_production_audio_call_evidence_test.dart

Actions:

1. Mirror the existing voice-message AppStateGuard and main-app identity/contact bootstrap.
2. Require exactly two distinct, explicit adb targets: first physical Android, second emulator.
3. Assign the emulator as caller and physical Pixel as callee.
4. Snapshot app state, clear both app data, install the same centrally built APK, pregrant microphone permission, and provision fresh independent identities.
5. Add each identity as the other peer's contact and open the caller's production conversation.
6. Launch and poll independent peer work with Future.wait. Install/build ownership remains singular.
7. Use adb uiautomator accessibility dumps and package ownership to select exactly one production Start voice call node. Tap its reported bounds.
8. Expand the Pixel notification surface, locate exactly one app-owned localized Answer action, and tap its reported bounds. Never use a fixed coordinate or a debug answer callback.
9. Preserve the uiautomator dump and bounded logcat window before and after Answer, including on failure.
10. Assert both state journeys, both active-call surfaces, structural media readiness, forced TURN selection, and bidirectional RTP-observed booleans.
11. Drive mute, speaker/route, and hang-up through visible production controls using the same exact-one semantic selection rule.
12. Require both peers to reach the same terminal outcome and require the Pixel native call notification/service to disappear.
13. Restore both apps and stop every local fixture in an outer finally block. A cleanup failure makes the scenario fail.

The semantic selector must fail on zero or multiple matching nodes. It may use app-owned localized resources and package/resource identifiers, but never an assumed screen coordinate.

Exit:

- TC-399-08, TC-399-09, and TC-399-10 are GREEN.
- Injected caller, callee, missing-node, ambiguous-node, and evidence-write failures all retain diagnostic logs and clean up.

### PH-399-07 - Register every proof and dependency

Files:

- tool/sims/critical_features.json
- integration_test/scripts/run_1to1_device_real.dart
- scripts/check_reliability_simulation_discovery.sh
- scripts/run_reliability_simulations.sh
- scripts/run_test_gates.sh
- scripts/run_host_test_gates.sh
- tool/sims/artifact_evidence.dart, if the central validator owns this artifact class
- scripts/test/reliability_simulation_discovery_contract_test.sh

Required scenario registration:

- Scenario ID: android.production_1to1_audio_call.
- Build profile: android.e2e.production_call_local.
- Entrypoint: lib/main.dart.
- Resources: device:android-physical, device:android-emulator, local production relay mutation, local coturn, and a unique evidence artifact.
- Dependencies: one central build, local fixture readiness, deterministic Pion oracle, identity/contact bootstrap.
- Runner: run_production_audio_call_sims.dart.
- Artifact validator: exact production-audio-call evidence schema.

Register the new Dart tests in both curated 1to1 arrays. Register the runner/campaign/support paths in reliability discovery and path classification. Do not add a fake call handler to sims_dispatcher.dart: this scenario runs the real main application and uses the existing app-private E2E channel only for setup and observation.

Exit:

- TC-399-11 is GREEN.
- Removing any single profile, scenario, runner, resource, test, classifier, or artifact registration makes discovery RED.

### PH-399-08 - Run gates and capture device closure

Actions:

1. Run all focused GREEN and mutation checks.
2. Run the curated 1to1 gate with Flutter concurrency 4.
3. Run feature-host-all because PH-399-02 changes production call feature code.
4. Run core-host-all because PH-399-05 changes shared debug/bootstrap code.
5. Run Graphify affected analysis over every app-owned changed path before final QA.
6. Refresh the architecture graph once with ./graphify-arch/refresh_arch_graph.sh --incremental.
7. Run analysis and diff hygiene.
8. Run the container fixture/oracle proof.
9. Run the new device scenario exclusively against the pinned Pixel/emulator pair.
10. Keep sanitized evidence and diagnostic logs for both pass and fail.
11. Update this plan's Execution Progress and the index with exact outcomes. Do not mark closed from host tests alone.

Exit:

- Every acceptance gate below passes.
- The device artifact independently validates caller and callee evidence and cleanup.

## 8. Device and Relay Proof Profile

### 8.1 Required live topology

Current discovery on 2026-09-02:

| Role | Kind | ID | OS |
|---|---|---|---|
| Callee | USB physical Pixel 6 | 21071FDF600CSC | Android 16, API 36 |
| Caller | Android Emulator | emulator-5554 | Android 17, API 37 |

Preflight commands:

    flutter devices --machine
    adb devices -l
    GOTOOLCHAIN=go1.25.0 go version
    docker version

The runner must verify that 21071FDF600CSC is not QEMU and emulator-5554 is QEMU. It must reject duplicate, implicit, offline, unauthorized, or wrong-kind targets.

If the current tuple is unavailable, the execution owner may substitute only another currently available explicit physical-Android/emulator pair and must record both exact IDs. An unavailable iPhone is irrelevant to this closure.

### 8.2 Fresh-data and build requirements

- Capture both pre-run app states for restoration.
- Clear all app data on both endpoints before provisioning the test identities.
- Build android.e2e.production_call_local once.
- Install the identical APK SHA-256 on both endpoints.
- Reject stale, independently built, mismatched, or unreported artifacts.
- Never ask the user to create identities, add contacts, open a conversation, answer, or hang up.

### 8.3 Local-only relay requirements

- Override relay configuration to exactly the local fixture multiaddr.
- Advertise TURN URLs that resolve only to the local host fixture.
- Force WebRTC relay-only policy in the dedicated build.
- Require both selected mobile candidate pairs to classify as exact `turn_udp`.
- Store only hashes of the local relay identity, dynamic TURN authority, per-run coturn instance identity, and the pinned coturn image/version in durable evidence.
- Fail if an EC2/remote relay address is configured, observed, or used.

### 8.4 Exact production journey

1. Start the local libp2p/miniredis/coturn fixture.
2. Run the Pion known-Opus oracle through that coturn instance.
3. Prepare one main-app APK centrally.
4. Restore-to-known-state, clear, install, permission, identity, and contact setup on both targets.
5. Launch both apps concurrently.
6. Open the caller emulator's real conversation and tap its voice-call control.
7. Observe the Pixel's native incoming-call presentation.
8. Tap the real native Answer action by semantic node.
9. Require the Pixel to retain an active accepted/connected call instead of returning to an ordinary chat-only state.
10. Require both peers to reach connected plus structural media readiness.
11. Require inbound and outbound audio RTP-observed booleans on both peers.
12. Exercise production mute and route controls and verify canonical projection.
13. Hang up through the production UI and require terminal convergence and native cleanup.
14. Preserve evidence/logs, restore app state, and stop fixtures.

### 8.5 Durable artifact allowlist

The final JSON artifact may contain only:

- schema version;
- scenario ID and status;
- role;
- run/profile/APK digests;
- device-kind and OS-version facts;
- local relay identity, dynamic TURN-authority, and per-run coturn-instance digests;
- coturn version and image digest;
- Pion version and known-fixture digest;
- nonce-bound call-binding hash;
- ordered boolean state/surface/media observations;
- coarse transport class;
- semantic UI action outcomes;
- cleanup outcomes;
- bounded failure category and sanitized reason.

It must reject:

- peer IDs, contact names, public keys, or raw call IDs;
- SDP, ICE candidate text, IP addresses, ports, relay multiaddrs, or signaling envelopes;
- TURN usernames, passwords, REST secrets, or tokens;
- RTP packet/byte counts, SSRCs, track/report IDs, or audio energy;
- audio samples or recordings;
- unbounded logcat or UI XML.

Raw bounded diagnostic logs and UI dumps may remain in the local failure-artifact directory only after a sanitizer rejects the same private classes. They are not part of the durable pass artifact.

## 9. Concurrency Contract

Concurrency is required where it shortens runtime without creating shared-resource races:

- Flutter host files run in one batch with concurrency 4.
- Independent Dart focused tests may run while a Go unit test runs.
- Container integration tests use unique container names, ports, temporary directories, and relay identities before they may run concurrently.
- The local coturn fixture and Pion oracle run before the device journey; the oracle must finish before the apps claim the fixture.
- APK build ownership is singular. Do not launch two Gradle builds.
- Install, launch, permission, setup, and polling operations for the two Android targets use Future.wait where independent.
- Every adb command includes its explicit serial.
- The final device scenario is exclusive: no other test may drive either target or the same local relay/coturn ports concurrently.

Recommended batch gates:

    ./scripts/run_host_test_gates.sh 1to1 --batch-flutter --concurrency 4 --reporter compact
    ./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter compact
    ./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter compact

## 10. Risks and Countermeasures

| Risk | Countermeasure | Stop condition |
|---|---|---|
| Docker Desktop UDP/NAT behavior prevents devices reaching coturn | Explicit port mapping, bounded relay range, advertised LAN address, and reachability preflight from both serials | Classify as environment blocker only if Pion/local fixture diagnostics fail before the product journey |
| Android system UI labels vary by locale or OS | Match the app-owned localized Answer action plus package/resource semantics; require exactly one node | No coordinate fallback and no user tap |
| RTP traffic exists during silence | Call it RTP movement, not audible speech; pair it with exact Pion known-payload proof | Never claim human acoustic fidelity |
| Diagnostic booleans alter product readiness | Separate evidence from isMediaReady and retain the existing muted/silent readiness sentinel | Any packet/energy dependency is a product regression |
| E2E hook becomes a control backdoor | Read-only interface, exact profile gating, default construction census, and authority-negative tests | No hook may place, answer, reject, end, mute, or route a call |
| EC2 relay is accidentally used | Replace relay list rather than append; force TURN; artifact binds local fixture identity | Any remote relay observation fails closure |
| Teardown loses the evidence needed for the Answer failure | Snapshot bounded logs/UI state before teardown, then sanitize and restore in finally | Cleanup still runs; diagnostic retention cannot bypass privacy |
| Dirty in-progress UI-24 tree causes conflicts | Patch narrowly, inspect overlap, preserve unrelated edits, and never reset/revert user work | Stop and request direction only for an unavoidable overlapping semantic conflict |
| Pion or coturn version drifts | Pin Go module version, coturn tag, immutable digest, go.sum, and dependency record | latest, floating digest, or ambient Go is forbidden |

## 11. Acceptance Gates

### AG-399-01 - Focused TDD

- TC-399-01 through TC-399-11 are GREEN.
- Each has a retained initial RED reason.
- Each listed mutation was run or an equivalent single-fault mutation was documented and observed RED.

### AG-399-02 - Preservation

- TC-399-12 through TC-399-14 and TC-399-16 are GREEN.
- Existing android.foreground_webrtc_audio registration remains intact.
- Default call flags and native-call Gradle property remain off outside the dedicated profile.

### AG-399-03 - Open-source fixture boundary

- Pion exists only under tool/call_audio_oracle.
- coturn runs only as a pinned local test container.
- No Pion, coturn, LiveKit, Mobly, or Appium dependency is added to the shipped Flutter application.
- Every Go invocation, including child processes, has GOTOOLCHAIN=go1.25.0.
- Fixture and oracle leave no process, container, port owner, temporary credential file, or reusable secret.

### AG-399-04 - Curated and affected-family gates

    ./scripts/run_host_test_gates.sh 1to1 --batch-flutter --concurrency 4 --reporter compact
    ./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter compact
    ./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter compact
    python3 graphify-arch/tdd_context.py affected lib/features/call/infrastructure/call_stats_sampler.dart lib/features/call/infrastructure/webrtc_types.dart lib/features/call/infrastructure/flutter_webrtc_call_engine.dart lib/features/call/domain/call_engine.dart lib/core/debug/android_production_audio_call_e2e.dart lib/core/debug/intro_e2e_runner.dart lib/debug/debug_e2e_composition_root.dart lib/app/bootstrap/production_application_bootstrap.dart integration_test/scripts/production_audio_call_local_fixture.dart integration_test/scripts/android_production_audio_call_campaign.dart integration_test/scripts/run_production_audio_call_sims.dart integration_test/support/android_production_audio_call_evidence.dart tool/sims/critical_features.json tool/sims/build_orchestrator.dart --budget 600
    ./graphify-arch/refresh_arch_graph.sh --incremental
    flutter analyze
    git diff --check

Full host-all is intentionally not a per-plan gate. It remains required once after the UI-24 dependency wave and again at final voice-call rollout/release closure.

### AG-399-05 - Device closure

Run exactly:

    RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 PLAN399_FIXTURE_HOST_IP=192.168.0.60 GOTOOLCHAIN=go1.25.0 dart run integration_test/scripts/run_production_audio_call_sims.dart --mode major --scenario android.production_1to1_audio_call

Pass requires:

- zero user interaction;
- one centrally built APK and matching SHA-256 on both devices;
- fresh app data and automatic identity/contact setup;
- emulator-originated production call;
- Pixel native incoming-call presentation and real Answer action;
- accepted then connected active-call surfaces on both peers;
- canonical structural media readiness on both peers;
- exact local forced-TURN `turn_udp` route on both peers;
- inbound and outbound audio RTP observed on both peers;
- prior Pion bidirectional known-Opus pass against the same per-run dynamic TURN authority and coturn instance;
- production mute, route, and hang-up actions;
- matching terminal state and no remaining native call surface/service;
- sanitized, nonce-bound evidence from both peers;
- successful app restoration and fixture teardown.

Skipped assertions, partial evidence, one-sided state, user taps, stale artifacts, remote relay fallback, or cleanup warnings are failures, not passes.

## 12. Execution Interpretation

| Observation | Interpretation | Required action |
|---|---|---|
| Pion or coturn cannot establish relay before app launch | Fixture/environment failure, not a product-call result | Preserve diagnostics, clean up, repair fixture/preflight, rerun |
| Fixture oracle passes, caller initiates, but Pixel receives no native call | Production signaling/wake/lifecycle failure | Fail TC-399-15 at the first missing boundary |
| Pixel Answer action is tapped, caller advances, Pixel returns to chat-only UI | Reproduction of the reported callee adoption/projection bug | Preserve pre/post Answer state and logs; fix with a new focused RED under the failing owner |
| Both overlays connect but either peer lacks inbound or outbound RTP observation | Production audio-flow failure | Do not accept structural readiness alone |
| Mobile RTP passes but Pion known payload fails | TURN/fixture determinism is unproven | Do not claim deterministic media forwarding |
| All automated assertions pass | Production two-user call control and bidirectional audio transport are validated on the exact Android tuple through the local relay/coturn fixture | State the bounded claim below |
| A human can or cannot hear speech | Outside automated closure because acoustic playback/capture was not instrumented | Record only as optional manual evidence, never as a replacement gate |

Allowed closure wording:

> On the recorded Pixel/emulator tuple, one fresh production-app build completed an emulator-to-Pixel call through the local production signaling relay and exact forced local-coturn `turn_udp` routes. The Pixel native Answer action converged to an active connected call on both apps, both production peers observed inbound and outbound audio RTP, controls and hang-up converged, and a separate Pion oracle verified the known Opus payload bidirectionally through the same per-run dynamic TURN authority and coturn instance.

Automated evidence validates bidirectional production RTP movement and deterministic known-Opus forwarding; it does not certify acoustic audibility, loudness, speech intelligibility, echo, or microphone/speaker quality.

Forbidden closure wording includes claims that every phone/OS works, that EC2 was tested, or that human speech quality was acoustically certified.

## 13. Handoff

- Implement PH-399-00 through PH-399-08 in order.
- Preserve the current UI-24 worktree; do not reset or rewrite unrelated files.
- Use the test names and scenario ID in this plan verbatim unless a collision is discovered. If renamed, amend this plan and the index before implementation continues.
- Keep test-only dependencies outside the shipped app.
- Reuse production handlers and main-app composition; do not fork a second call implementation for the proof.
- Keep all actions external through the real UI/native surfaces. The app-private hook is setup and observation only.
- On the first real-device failure, stop at the earliest missing boundary and add a focused causal test there before patching.
- Run Graphify affected analysis only after a coherent app-owned code batch; this document-only planning change does not require graph refresh or affected analysis.
- Attach sanitized artifact paths, exact commands, exit codes, APK/coturn/Pion hashes, and target IDs to Execution Progress.

## 14. Execution Progress

| Phase | Status | Evidence |
|---|---|---|
| PH-399-00 RED capture | Complete | Causal REDs covered explicit audio-report parsing, sticky RTP propagation, evidence rejection, combined-fixture credential/instance binding, same-URL/different-coturn replay, and bidirectional Pion codec/count/order/hash mutations before the corresponding GREEN implementations. |
| PH-399-01 build/scenario profile | Complete | Cached profile `android.e2e.production_call_local` builds the production entrypoint with default-off call observation and exact profile/capability locks. |
| PH-399-02 privacy-safe RTP observation | Complete | Production stats parse only explicit audio inbound/outbound reports with positive packet and byte counters, sticky-OR the four endpoint observations, preserve `isMediaReady`, and emit only privacy-safe booleans while rejecting RTP identifiers and values. |
| PH-399-03 local relay/coturn fixture | Complete | One disposable miniredis plus production libp2p relay and pinned coturn `4.17.2-r0` fixture issues fresh REST credentials, forces local TURN, binds evidence to the dynamic authority and actual per-run container identity, and tears down cleanly under Go 1.25.0. |
| PH-399-04 Pion oracle | Complete | Test-only Pion `v4.2.19` forwards the pinned license-free Opus fixture as exactly 33 ordered RTP payloads in each direction through the same `turn_udp` authority/instance and verifies codec, count, order, and payload hash. |
| PH-399-05 read-only app observer | Complete | Default-off app-owned observation has no call-control authority, binds readiness to the exact local recipient device/key epoch, and sticky-retains inbound/outbound RTP observations independently on each endpoint. |
| PH-399-06 production device campaign | Complete | Pixel 6 `21071FDF600CSC` as physical callee and `emulator-5554` as emulator caller passed the zero-touch production call/native-Answer/connected-RTP/control/cleanup campaign on the exact local `turn_udp` fixture. |
| PH-399-07 registration | Complete | Scenario, cached build profile, validators, dispatcher, and host tests are registered. |
| PH-399-08 gates/device closure | Complete | Post-instance-binding focused Flutter owners: 56 passed and 1 intentional live-fixture skip; exact tagged combined fixture, oracle race/vet/module, full relay Go suite, and full `go-mknoon` suite passed with Go 1.25.0. Final `1to1`: 188 paths, 3,180 passed, 4 skipped. Final `core-host-all`: 441 Flutter paths/3,682 passed plus 2 manifest contracts. Final `feature-host-all`: 897 paths/10,004 passed/11 skipped. Device campaign: 27/27 assertions; combined relay/coturn/Pion fixture PASS in 346.91 s. Scoped analysis, format, affected analysis, and diff hygiene passed. |

Historical non-closing structural device evidence (2026-09-02T22:16:11Z):

- Artifact: `build/sims/proofs/android.production_1to1_audio_call/android.production_1to1_audio_call-1788387371467807-44199.json`
- Artifact SHA-256: `f2bef2f91edb82256090dc224bd5da763bfa4c3ce2ce3018feb959f3f0192248`
- APK SHA-256: `57cb6cc8149c4827820717dc4bbcdd9bae3a91c97738580a915e850f2b266589`
- Profile SHA-256: `9ca41d52815afb36657ad02551b493c9c46c986b0f8641d477d7e99da4bfa2dc`
- Relay result: disposable local signaling relay plus local coturn; both endpoints reported relay-only `turn_udp` structural readiness.
- Call result: distinct fresh identities; caller observed outgoing/ringing/accepted/connected/terminal, callee observed ringing/accepted/connected/terminal; native Answer, Mute, Speaker, Hangup, terminal UI dismissal, native-call release, and app-state restoration all passed.
- Bounded claim: `directionalMediaOracle=closure-only` and `productionRtpClaimed=false`. This evidence does not prove bidirectional audible speech or production RTP flow.

Final bounded device-closure evidence (reported 2026-09-02T23:51:51.236452Z / executed 2026-09-03 local time):

- Command: `RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 PLAN399_FIXTURE_HOST_IP=192.168.0.60 GOTOOLCHAIN=go1.25.0 dart run integration_test/scripts/run_production_audio_call_sims.dart --mode major --scenario android.production_1to1_audio_call`; exit 0.
- Artifact: `build/sims/proofs/android.production_1to1_audio_call/android.production_1to1_audio_call-1788393111156113-3954.json`
- Artifact SHA-256: `1620d26f44c7e571bef09ef58a98ddc52dc663aff4ab9a7a799548378e481822`
- APK SHA-256: `2e55709b22e274fedd88cf541f4d3b2fd744bd4a123a3f327f3748b91a097884`; profile SHA-256: `9ca41d52815afb36657ad02551b493c9c46c986b0f8641d477d7e99da4bfa2dc`; `sameApkBothTargets=true`. The combined run built once with no cache hit, then the device phase reused that exact artifact.
- Devices: emulator caller `emulator-5554`, Android 17/API 37; physical callee Pixel 6 `21071FDF600CSC`, Android 16/API 36.
- Safe fixture bindings: local relay identity `25d04ab4911f2bbb4f99a86c64b13e8e65b746088f7f4cf0d09c09c9dd11a733`; dynamic TURN authority `24a31b9c304e6eb4bbda5df2b539afa0c10551aac146e2f40d6e86086d9ce75e`; coturn-instance identity `134dc8f8fc0b2556c8c2df494ad5aa7253dcb41db8648ca53d63a2fb70cdfd9b`.
- Both production endpoints reported `inboundAudioRtpObserved=true`, `outboundAudioRtpObserved=true`, relay-only selection, and exact `turn_udp`. Caller states were outgoing/ringing/accepted/connected/terminal; callee states were ringing/accepted/connected/terminal.
- Native Answer, active-call surfaces, structural media readiness, Mute, Speaker, Hangup, terminal convergence, active-surface dismissal, native-call release, app restoration, and fixture cleanup all passed.
- Pion `v4.2.19` verified both directions of the pinned known-Opus fixture (`429dc0349c60f06f5c062fd237a333c7941e6b98445f33272c0be5185425b9f5`) for exact codec/count/order/hash through the same TURN authority and coturn instance. Coturn was `4.17.2-r0`, image digest `aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e`.
- The registered artifact validator and an independent exact `jq -e` closure check passed. Durable-evidence denylist checks found no raw TURN URL, IP, host/address/port, credentials, container ID, RTP identifiers, or packet values. No Plan 399 coturn container remained after teardown.
- The filtered Sims report correctly remains `releaseEligible=false`; this is Plan 399's bounded Android device closure, not release-wide acceptance.

Current disposition: Plan 399 is device-closed for the recorded Android tuple and local fixture. Automated evidence validates bidirectional production RTP movement and deterministic known-Opus forwarding; it does not certify acoustic audibility, loudness, speech intelligibility, echo, or microphone/speaker quality. VC2-06 retains ownership of that audio-quality observability scope.
