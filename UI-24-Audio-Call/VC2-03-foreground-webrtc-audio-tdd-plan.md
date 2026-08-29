# VC2-03 — Foreground WebRTC Audio Calling TDD Plan

**Status:** Proposed  
**Depends on:** VC2-01 and VC2-02  
**Blocks:** VC2-04, VC2-05, VC2-06  
**Primary outcome:** Two foreground Mknoon peers complete a private audio call over direct ICE or authenticated TURN with deterministic controls and cleanup.

## 1. Scope

### In scope

- Audio-only WebRTC PeerConnection through the frozen CallEngine boundary.
- Offer/answer/fingerprint and trickle-ICE exchange after acceptance.
- Direct-first ICE with TURN gathered concurrently.
- Authenticated TURN/UDP, TURN/TCP/TLS, and relay-only privacy mode.
- Foreground outgoing/incoming call screens.
- Microphone permission, mute, speaker, wired/Bluetooth route handling, interruption, and audio focus/session coordination.
- Two-way audio readiness, connection timing, route diagnostics, reconnect UI, and shared cleanup.
- Real two-peer Android proof plus available iOS foreground build/parity proof.

### Out of scope

- Android killed/background Telecom presentation, iOS PushKit/CallKit, video, recording, call waiting, and external beta.

## 2. Proposed new/changed surfaces

### Infrastructure

- Complete `lib/features/call/infrastructure/flutter_webrtc_call_engine.dart`.
- `lib/features/call/infrastructure/webrtc_peer_connection_facade.dart`.
- `lib/features/call/infrastructure/call_audio_route_adapter.dart`.
- `lib/features/call/infrastructure/call_stats_sampler.dart`.
- Platform-channel seams for route enumeration/selection where the plugin is insufficient.

### Application

- Extend `CallCoordinator` effects for offer, answer, candidates, selected pair, media readiness, ICE restart, and reconnect timeout.
- `lib/features/call/application/call_audio_controller.dart`.
- `lib/features/call/application/call_route_diagnostics.dart`.

### Presentation

- `lib/features/call/presentation/screens/outgoing_call_screen.dart`.
- `lib/features/call/presentation/screens/incoming_call_screen.dart` for foreground-only presentation.
- `lib/features/call/presentation/screens/active_call_screen.dart`.
- `lib/features/call/presentation/widgets/call_controls.dart`.
- Conversation-header call action and unavailable-state explanation.

### Tests

- `test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart`.
- `test/features/call/application/call_negotiation_test.dart`.
- `test/features/call/application/call_audio_controller_test.dart`.
- `test/features/call/application/call_ice_restart_test.dart`.
- `test/features/call/presentation/call_screens_test.dart`.
- `test/features/call/integration/foreground_audio_call_test.dart`.
- Device harness under the repository's established integration/device test structure.

## 3. Media invariants

1. Audio only: no camera permission, video track, video transceiver, or video SDP media section.
2. No SDP/ICE exchange before authenticated `accept`.
3. No microphone capture before local permission and local acceptance.
4. Offer/answer DTLS fingerprints match the signed encrypted signaling fields.
5. Candidates are scoped to one `ice_generation`; old-generation candidates are ignored.
6. Candidate batches and deferred candidates are bounded.
7. TURN and direct candidates gather concurrently in normal mode.
8. **Always relay** filters outbound candidate signaling and selected pairs to relay only.
9. Connected requires selected-pair, ICE/DTLS, native-audio-session, local-sender-track, and negotiated remote-receiver/track readiness—not transport ACK, signaling completion, observed RTP bytes, or non-zero audio energy.
10. One shared cleanup routine owns tracks, PeerConnection, audio route, stats, and credentials.

## 4. CallEngine TDD

### RED

Use a fake WebRTC facade to fail until the adapter proves:

- creates one audio-only PeerConnection;
- rejects a second connection for the same session;
- offer/answer creation and remote/local description order;
- fingerprint extraction and mismatch rejection;
- candidate add before remote description is bounded and then drained;
- old ICE generation candidate rejection;
- ICE restart produces one new generation;
- local audio enable/disable is idempotent;
- close is idempotent after partial initialization and every failure point;
- no raw SDP/candidate reaches logs or diagnostics;
- event stream closes and does not grow unbounded.

### GREEN

Implement the adapter behind CallEngine without allowing plugin types into domain/application tests.

### REFACTOR

Separate pure SDP metadata validation from plugin side effects. Do not parse or rewrite SDP beyond necessary, versioned assertions.

## 5. Negotiation flow

### Caller

1. Recipient `accept` arrives.
2. Obtain current short-lived ICE server configuration.
3. Create audio-only PeerConnection and local audio track after permission.
4. Create offer; bind fingerprint into signed encrypted `offer`.
5. Send bounded candidate batches for generation zero.
6. Apply authenticated answer and candidates.

### Callee

1. Local foreground answer submits `accept`.
2. Obtain ICE configuration and create connection/audio track.
3. Verify/apply authenticated offer.
4. Create and signal answer plus candidates.

### Readiness

Enter `connected` when:

- selected candidate pair is succeeded/nominated;
- DTLS transport is connected;
- native/foreground audio session is active;
- the local sender has the expected live audio track attached, regardless of mute state; and
- the negotiated remote audio receiver/track exists and is live.

A silent caller, muted caller, or WebRTC DTX must still reach `connected`; packet/byte/energy growth is never a setup gate. Missing transport/track readiness remains `connecting` and produces a coarse timeout reason. One-way-audio classification runs only after connection under VC2-06.

## 6. ICE and TURN policy

### Normal mode

- `iceTransportPolicy = all`.
- Direct and TURN servers supplied before gathering.
- Direct candidates retain preference; no serial direct-only timeout.
- Once stable, do not migrate solely to reduce relay cost.

### Always relay mode

- `iceTransportPolicy = relay`.
- Candidate egress adapter rejects host and server-reflexive candidates.
- Tests inspect emitted signal fixtures and selected-pair class.
- If no relay candidate exists, fail explicitly; never fall back to direct.

### Restricted network cases

- Direct addresses blocked → TURN/UDP.
- UDP blocked → TURN/TCP or TURN/TLS.
- Network change → `reconnecting` and one bounded ICE restart.
- A restart requiring TURN installs a staged unexpired credential bundle first; minting failure follows the 15-second reconnect budget and never falls back to static credentials or direct in **Always relay** mode.
- Restart failure after 15 seconds → terminal cleanup.

## 7. Audio session and routing

### Shared

- Request microphone permission in context with a clear explanation.
- Incoming invitation/ringing never captures audio.
- Starting a call pauses or refuses voice-note recording and conflicting playback.
- Cleanup restores only eligible prior playback; it never auto-resumes microphone recording.
- Route changes are event-driven and serialized through CallCoordinator.

### Controls

- Mute toggles local track enabled state and reflects actual state.
- Speaker selects supported output route; unavailable route produces truthful UI.
- Wired/Bluetooth changes update route label without ending the call.
- Audio interruptions move to a defined paused/reconnecting state or end cleanly according to platform result.

Native CallKit/Telecom audio activation replaces foreground-only routing ownership in VC2-04/VC2-05; the Dart contract remains unchanged.

## 8. Foreground UI behavior

### Conversation header

- Show phone action only when one endpoint survives the trusted contact-device roster and current signed relay-capability intersection.
- Disabled state explains unsupported/unavailable device rather than creating a failing session.

### Calling/ringing

- **Calling** immediately after local session creation.
- **Ringing** only after remote application `ringing`.
- Cancel always available.
- No technical route/IP information in normal UI.

### Active call

- Contact name/avatar from local data.
- Duration begins at connected time.
- Mute, speaker, and end controls.
- `Connecting` and `Reconnecting` are distinct.
- Local diagnostics entry may show coarse route and failure reason behind a developer/beta diagnostics control.

### Errors

Permission denied, unavailable endpoint, busy, declined, no answer, TURN unavailable, media failed, and reconnect failed map to stable user text and terminal reasons.

## 9. RED behavior matrix

1. Caller/callee happy path with fake engine.
2. Offer before accept rejected.
3. Fingerprint mismatch ends before media.
4. Candidate before description buffered within bound.
5. Candidate overflow rejected safely.
6. Duplicate offer/answer idempotency.
7. Permission denied creates no local track and no SDP.
8. Mute/speaker rapid taps converge on actual engine state.
9. Direct selected in same-LAN fixture.
10. TURN/UDP selected when direct blocked.
11. TCP/TLS selected when UDP blocked.
12. Always-relay emits/selects no host or server-reflexive candidate.
13. Silent/muted/DTX peer reaches connected without packet/energy growth; missing receiver/track readiness times out.
14. ICE disconnected → reconnecting → recovered.
15. Reconnect timeout → one cleanup/history row.
16. Hangup during negotiation and during reconnect.
17. Voice-note playback/recording conflict and restoration.
18. App shutdown/engine error at every initialization stage.

## 10. Device and network proof

Resolve live targets immediately before testing.

Default topology:

- Peer A: USB-connected physical Android device.
- Peer B: available Android emulator.

Foreground iOS parity uses an available simulator or physical iPhone only when needed; no unavailable version is a gate.

Automated harness must:

- install/start both builds pinned to target IDs;
- provision test contacts/capabilities without user taps where supported;
- place, answer, mute, route, and end;
- assert call states and two-way audio test signals/metrics;
- apply network restrictions for direct and UDP cases;
- collect privacy-safe timing/route/resource evidence;
- clean allocations and app state.

Do not claim two-way audio from UI state alone. Use a controlled known audio signal for two-way media proof, but never make that test signal or ordinary audio-byte growth a product `connected` prerequisite.

## 11. Required gates

### Focused

Run each new call test exactly during RED/GREEN, then all `test/features/call/**` host tests.

### Preservation

- Existing microphone permission tests.
- Existing voice recorder/player and `audio_session` behavior tests.
- Existing conversation header/navigation tests.
- Existing signaling/mailbox/state tests from VC2-02.
- Existing one-to-one chat and notification tests.

### Curated

- `./scripts/run_host_test_gates.sh 1to1`
- `./scripts/run_host_test_gates.sh feature-host-all`
- `core-host-all` only if shared core audio/permission surfaces changed.

### Wave C closure

After focused/curated/native/device proof passes:

- Run full `host-all` once for the completed foundation/control/foreground wave.
- Run Go module suites if any Go signaling/credential code changed after VC2-02.

## 12. Acceptance criteria

- Two foreground peers place, ring, answer, exchange two-way audio, mute, switch supported routes, and end.
- Same-LAN case selects direct.
- Forced direct failure selects authenticated TURN/UDP.
- UDP-blocked case selects TURN/TCP or TURN/TLS.
- Always-relay leaks no host/server-reflexive candidate through signaling or selected-pair stats.
- Accept-to-audio p95 target is measured; failures are truthful rather than hidden.
- Silent/muted/DTX peers reach `connected` from transport/track readiness; one-way-audio detection is separate and does not block setup.
- Microphone never starts before acceptance/permission.
- Fingerprint mismatch, malformed SDP, candidate overflow, and stale ICE generation fail closed.
- Network loss recovers through one bounded ICE restart or ends cleanly.
- Every partial/terminal path closes tracks, connection, timers, stats, credentials, and audio session once.
- Existing voice-note, chat, inbox, push, and lifecycle tests remain green.
- Platform background/terminated flags remain off; this milestone is internal foreground proof only.
