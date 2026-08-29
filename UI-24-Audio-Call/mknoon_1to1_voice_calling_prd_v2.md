# Mknoon 1-to-1 Voice Calling PRD v2.0

**Status:** Proposed implementation contract  
**Product:** Mknoon  
**Tracking:** Multica `SE-11`  
**Supersedes:** `mknoon_1to1_voice_calling_prd_v1.md` and conflicting decisions in `VC-03` through `VC-07`  
**Scope:** Audio-only calls between accepted 1-to-1 contacts on Android and iOS

## 1. Executive decision

Mknoon will implement 1-to-1 voice calling with four separate responsibilities:

1. **Dart call control:** after Flutter attaches, one `CallCoordinator` is the canonical product-state owner for timers, deduplication, WebRTC lifecycle, and cleanup. Before that attachment, native code may hold only the bounded pre-start record defined in section 6.2.
2. **Authenticated signaling transport:** existing libp2p direct/Circuit Relay delivery carries encrypted call-control messages; a dedicated ephemeral relay mailbox covers background and terminated recipients.
3. **WebRTC media:** audio travels through an audio-only WebRTC PeerConnection using direct ICE candidates when possible and coturn when required.
4. **Native mobile lifecycle:** Android Telecom/Core-Telecom and iOS PushKit/CallKit own system incoming-call presentation, actions, audio activation, process-state behavior, and the minimal restart-safe pre-Dart handoff record—not an independent product call state machine.

The existing libp2p Circuit Relay is never treated as a WebRTC media relay. The deployed coturn service must be hardened and proven before any TURN-enabled beta.

## 2. Current-state baseline

Mknoon currently has reusable messaging foundations but no production voice-call implementation.

### Reusable

- Authenticated libp2p direct delivery and Circuit Relay fallback.
- Direct message ACKs, offline inbox custody, bounded drains, retry, deduplication, and resume recovery.
- Per-recipient ML-KEM-768 plus AES-GCM encrypted message envelopes.
- Contact, block, account-peer, and linked-device authority checks.
- Android FCM and iOS APNs notification plumbing.
- Microphone permission, local audio recording, playback, and audio-session dependencies.
- Redis-backed relay persistence and a deployed coturn process.

### Observed infrastructure status — proof pending

The verified 2026-08-29 baseline is Redis-backed relay durability plus coturn `4.6.3`; UDP STUN works on `3478`, and TCP reaches a TURN authentication challenge. Coturn still uses static credentials on `3478`. These observations prove reachability only—not authenticated relay allocation or production TURN readiness. REST-secret issuance and rotation, allocation limits, authenticated relayed media, UDP-blocked TURN/TCP, TURN/TLS on `443`, forced-relay privacy, cleanup, and monitoring remain unproved implementation gates.

The existing chat inbox, ordinary notification path, and any fail-open in-memory token/wake store are not call implementations. Calls may reuse reviewed crypto and transport primitives, but require separate durable call semantics.

### Not implemented

- Call domain model, call state machine, call signaling schema, and call UI.
- Flutter WebRTC dependency or PeerConnection integration.
- Ephemeral call mailbox, call push capability, VoIP-token registration, or TURN credential minting.
- Android Telecom/Core-Telecom integration and microphone/phone-call foreground service.
- iOS PushKit, CallKit, VoIP background mode, and CallKit audio activation.
- Call history model, route diagnostics, call metrics, or call-specific tests.

## 3. Product outcomes

The feature succeeds when accepted contacts can place, receive, answer, decline, and end private audio calls with predictable behavior across normal mobile app states and networks.

Primary outcomes:

- Fast incoming-call presentation without stale or duplicate rings.
- Direct media when practical, with rapid TURN fallback rather than a long direct-only delay.
- End-to-end encrypted signaling and DTLS-SRTP media.
- Correct behavior when foregrounded, backgrounded, terminated, or locked.
- One deterministic call session and one cleanup owner per device.
- Privacy-safe diagnostics and an optional relay-only privacy mode.

## 4. Scope

### MVP includes

- Audio-only calls between accepted 1-to-1 contacts.
- One active Mknoon call per device.
- One selected call endpoint per recipient account; no multi-device ringing fanout.
- Foreground, background, terminated, and locked-device incoming calls.
- Direct-first ICE, TURN/UDP, TURN/TCP, and TURN/TLS fallback.
- Mute, speaker, Bluetooth routing, answer, decline, cancel, and end.
- Busy handling, simultaneous-call glare resolution, ICE restart, and reconnect timeout.
- Local call history shown in the 1-to-1 conversation timeline.
- Opt-in **Always relay calls** privacy setting.
- Feature flag, kill switch, canary rollout, and rollback.

### Explicit non-goals

- Video, screen sharing, group calls, conference servers, recording, voicemail, PSTN, call transfer, hold, and call waiting.
- Ringing every linked device.
- Cross-device call handoff.
- Using libp2p Circuit Relay for RTP/audio media.
- Persisting SDP, ICE candidates, media keys, TURN passwords, or call audio.

## 5. Product decisions

### 5.1 Recipient device selection

MVP uses one preferred call endpoint per account. Endpoint selection is an intersection of application identity authority and relay capability state; a relay record alone never authorizes a device.

- The caller starts from the accepted contact's trusted account-device roster, including current linked-device authority and device-key epoch.
- A call-capable device registers a signed, expiring `voice_call_v1` capability/availability record with the relay.
- The selected device must appear in both the trusted roster and the current relay record with matching account, device, capability version, and key/preference epoch.
- The account may nominate one preferred device, but the preference cannot add a device that is absent from the trusted roster.
- The relay never fans an invitation out to multiple devices and never treats capability registration as contact authorization.
- If the intersection is empty, ambiguous, stale, or mismatched, the caller sees **Calling unavailable on this device** before creating a session.
- Blocking, removing, unlinking, or rotating a device revokes the corresponding call-wake and endpoint authority.

### 5.2 Call history

Each participating device keeps one local `call_history` entry keyed by `call_id`.

- Entries may be `completed`, `missed`, `declined`, `busy`, `cancelled`, or `failed`.
- Duration is stored only for locally connected calls.
- The conversation timeline projects these local entries; no unencrypted server history exists.
- Expired invitations may create a missed-call entry but must never ring.
- Call history does not contain SDP, ICE addresses, keys, TURN credentials, or diagnostic identifiers.

### 5.3 Privacy mode

- Default: `iceTransportPolicy = all` with direct candidates preferred and TURN gathered concurrently.
- **Always relay calls:** `iceTransportPolicy = relay`; only relay candidates may leave the WebRTC signaling adapter.
- The setting is opt-in for MVP and explains the bandwidth/latency tradeoff.
- A forced-relay acceptance test must prove that host and server-reflexive addresses do not appear in outbound SDP/candidate messages or selected-pair statistics.

### 5.4 Release definition

Foreground-only calling may be used internally, but it is not the MVP. External beta availability requires the complete background, terminated, and locked-device acceptance matrix for that platform.

## 6. Architecture and ownership

| Component | Canonical responsibility |
|---|---|
| Dart `CallCoordinator` | Canonical serialized product-state owner after runtime attachment; timers; transition validation; WebRTC lifecycle; cleanup |
| Dart `CallSignalingService` | Envelope construction, encryption, signature, transport race, mailbox fallback, dedupe |
| Existing Go/libp2p node | Authenticated bounded stream transport and relay connectivity; no product call state |
| Relay call mailbox | Separate Redis-backed ephemeral encrypted custody, TTL, capacity, sender attribution, opaque wake, rate limits; no fail-open memory success |
| TURN credential service | Short-lived coturn REST credentials; no static app credential |
| WebRTC adapter | PeerConnection, audio track, SDP, ICE, statistics, route classification |
| Android adapter | Telecom/Core-Telecom, CallStyle, foreground execution, actions, audio focus/routing, bounded pre-Dart record |
| iOS adapter | PushKit, CallKit, distinct durable VoIP token, CallKit actions, audio-session activation, bounded pre-Dart record |
| Call history repository | Local idempotent terminal projection keyed by `call_id` |

### 6.1 Control and media paths

```text
(1) User/native action
        |
        v
(2) Dart CallCoordinator
        |
        +--> (3) encrypted call signal --> Go/libp2p --> peer
        |                                  \-> ephemeral relay mailbox + opaque wake
        |
        +--> (4) WebRTC PeerConnection --> direct ICE or coturn
        |
        +--> (5) Android/iOS system-call adapter
```

After attachment, no component other than `CallCoordinator` may independently advance product call state. Before attachment, native adapters may only present/adopt/end the system call and append the bounded events below; Go and relay components report transport outcomes.

### 6.2 Native pre-start record and Dart reconciliation

Native code may persist at most one protected, versioned, bounded record per pending call containing:

- `call_id`/native UUID mapping, schema version, received time, and expiry;
- opaque descriptor/mailbox reference and opaque local contact handle;
- native presentation status;
- monotonic native event sequence and pending `answer`, `decline`, `end`, audio-activation, or provider-reset event;
- terminal reason and handoff acknowledgement.

It contains no SDP, ICE candidate, TURN credential, media key, readable Peer ID/contact name, or independent retry/state graph.

Reconciliation rules:

1. Native performs bounded payload grammar, expiry, UUID, and duplicate checks before side effects where the platform permits.
2. Native may report/adopt/end the system call before Dart starts and records each action with a monotonic sequence.
3. On attachment, Dart loads one snapshot, verifies the authenticated invitation and device/contact authority, then consumes native events in order exactly once.
4. A native terminal event, provider reset, authenticated remote cancel, or expiry dominates pending answer/presentation events. Dart never revives a terminal or expired record.
5. An answer before Dart attachment is an intent only: no microphone, SDP, ICE, or media starts until Dart validates/adopts the call and native audio activation succeeds.
6. Dart acknowledges adoption or terminal cleanup; native then deletes the record exactly once. Process recreation may replay unacknowledged events but may not create a second call.
7. If Dart cannot attach or validation fails, native ends the system call with an approved coarse reason and clears the record. Native never promotes itself into a second full call state machine.

## 7. Signaling transport decision

MVP reuses the existing authenticated one-to-one transport rather than introducing a second peer-to-peer libp2p protocol.

- Direct call signals use the existing framed message stream with outer type `call_signal` and version `1`.
- Circuit Relay remains a transparent libp2p transport fallback.
- The relay exposes logically separate, versioned call actions backed by separate Redis keys/types and policies—not chat mailbox rules:
  - `call_store_v1`
  - `call_retrieve_v1`
  - `call_ack_v1`
  - `call_cancel_v1`
  - `call_endpoint_set_v1`
  - `call_endpoint_get_v1`
  - `turn_credentials_v1`
- Call messages never enter the durable chat outbox or generic pending-message retrier.
- A required durable call-mailbox, endpoint, wake-handle, or VoIP-token write fails closed when Redis is unavailable; an in-memory write cannot be reported as success.
- A transport ACK means only that the receiving transport accepted bytes. It never means **Ringing**.

## 8. Encrypted call envelope

### 8.1 Outer transport envelope

The outer frame contains only routing and bounded-processing fields:

```json
{
  "type": "call_signal",
  "version": "1",
  "message_id": "128-bit-random",
  "call_handle": "128-bit-random",
  "expires_at_ms": 0,
  "kem": "base64",
  "ciphertext": "base64",
  "nonce": "base64",
  "signature": "base64"
}
```

`call_handle` is a random relay/mailbox correlation value. It is not a Peer ID, conversation ID, or contact identifier.

### 8.2 Encrypted inner envelope

```json
{
  "schema": "mknoon.call_signal.v1",
  "call_id": "128-bit-random",
  "message_id": "128-bit-random",
  "event": "invite",
  "sender_account_peer_id": "peer-id",
  "sender_device_peer_id": "peer-id",
  "recipient_account_peer_id": "peer-id",
  "recipient_device_peer_id": "peer-id",
  "sender_sequence": 1,
  "ice_generation": 0,
  "created_at_ms": 0,
  "expires_at_ms": 0,
  "payload": {}
}
```

Requirements:

- Encrypt independently for the selected recipient device using its current ML-KEM key.
- Sign the versioned envelope with the sender identity key.
- Bind the authenticated transport peer and linked-device authority to the encrypted sender fields.
- Bind every SDP fingerprint to the signed encrypted signal.
- Reject unknown fields in security-critical native/relay readers unless the schema explicitly permits them.
- Reject malformed, oversized, unsupported, expired, replayed, misaddressed, or incorrectly signed frames before SDP parsing.
- Keep a replay tombstone for at least ten minutes after a terminal state.
- Bound one call signal to 96 KiB and one mailbox call to 256 KiB total.

## 9. Call-control events

| Event | Meaning |
|---|---|
| `invite` | Requests a call; contains capabilities and call metadata, not SDP |
| `ringing` | Recipient authenticated and authorized the invitation and successfully presented/adopted OS incoming-call UI; provisional iOS CallKit reporting alone is not this event |
| `accept` | Recipient user accepted; authorizes SDP exchange and microphone preparation |
| `reject` | Recipient cannot accept; reason is `declined`, `busy`, `unsupported`, or generic `unavailable` |
| `offer` | WebRTC offer and authenticated fingerprint after acceptance |
| `answer` | WebRTC answer and authenticated fingerprint |
| `ice` | Bounded trickle candidate batch for one ICE generation |
| `ice_restart` | Starts a new ICE generation after network failure/change |
| `terminate` | Idempotent terminal event with a reason |

Blocked contacts are silent or receive generic `unavailable`; the protocol never reveals block state.

## 10. State machine

### 10.1 States

- `idle`
- `preparing`
- `inviting`
- `incomingValidating`
- `ringing`
- `accepted`
- `negotiating`
- `connected`
- `reconnecting`
- `ending`
- `ended`

### 10.2 Invariants

1. One serialized event queue is the only writer.
2. One active session exists per device.
3. `call_id` and selected participants never change.
4. Microphone capture cannot start before local user acceptance and native audio activation.
5. `ringing` is sent only after authenticated policy validation and system UI presentation/adoption both succeed. A provisional iOS CallKit report is not application `ringing`.
6. A terminal event wins over later non-terminal events.
7. `EndCall` is idempotent and invokes one cleanup routine.
8. Duplicate events produce no second UI, track, timer, history row, or native call.
9. An expired invitation can create history but cannot enter `ringing`.
10. Candidate queues, retries, timers, streams, and statistics buffers are bounded.

### 10.3 Terminal reasons

`declined`, `busy`, `caller_cancelled`, `no_answer`, `remote_hangup`, `local_hangup`, `permission_denied`, `unsupported`, `signaling_failed`, `media_failed`, `reconnect_failed`, `expired`, `app_shutdown`, and `policy_rejected`.

## 11. Call flows

### 11.1 Outgoing

1. Resolve one call-capable recipient device by intersecting the trusted contact-device roster with the current signed relay capability record.
2. Create `CallSession` and random `call_id`/`call_handle`.
3. Store the short-lived encrypted `invite` in the call mailbox and race the direct libp2p path.
4. Relay sends an opaque call wake when recipient presence cannot prove a foreground direct route.
5. Show **Calling**.
6. Show **Ringing** only after an authenticated `ringing` event.
7. On `accept`, exchange `offer`, `answer`, and candidate batches.
8. Start microphone transmission only after local permission and native audio activation.
9. Enter **Connected** after the selected ICE pair and DTLS are connected, native audio is active, the local sender track is attached, and the negotiated remote receiver/track is live. Do not require observed audio bytes, packet growth, or non-zero energy; a silent or DTX-enabled peer must still connect.
10. On any terminal path, run the shared cleanup routine and project one history entry.

### 11.2 Incoming

1. Receive a direct signal or native opaque wake and deduplicate it against the native pre-start record.
2. Perform bounded local grammar, UUID, expiry, and opaque-handle checks before platform side effects where possible.
3. On iOS, report CallKit promptly and complete the PushKit callback from the CallKit report completion without waiting for Flutter, Go, network connection, or mailbox retrieval; start connection/retrieval work in parallel. Android follows its platform presentation rules.
4. Retrieve the encrypted mailbox invitation when required and verify mailbox attribution, signature, recipient, trusted contact-device roster, matching relay capability epoch, block state, size, expiry, replay, and rate limits.
5. Resolve the opaque contact handle locally. After validation, update/adopt native UI and send application `ringing`; on failure, end any provisional native UI promptly without sending `ringing` or starting media.
6. On answer, persist the native intent; after Dart adoption, submit `accept`, activate audio through Telecom/CallKit, and exchange SDP/ICE.
7. On decline, send `reject(declined)` when an authenticated call exists, stop native UI once, and record local history.

### 11.3 Glare and busy

- Simultaneous calls use a canonical bytewise comparison of `(call_id, caller_account_peer_id)`; both devices retain the lower tuple and terminate the other as `caller_cancelled`.
- A second unrelated call while one is active receives `reject(busy)` without creating a second native call.

## 12. Time and retry budgets

| Event | Budget |
|---|---:|
| Foreground invite to native ringing, p95 | <= 2 seconds |
| Background/locked invite to native ringing, p95 | <= 5 seconds |
| Ring duration | 30 seconds |
| Invite/mailbox TTL | 45 seconds |
| Accept to usable two-way audio, p95 | <= 3 seconds |
| Show reconnecting after media loss | <= 3 seconds |
| Reconnect window | 15 seconds |
| TURN credential lifetime | 10 minutes |
| Replay tombstone | >= 10 minutes |

Retries use bounded exponential backoff with jitter and may not extend message expiry.

## 13. TURN and ICE contract

The live coturn deployment is retained and hardened; Mknoon does not embed Pion TURN in `relay-server`.

Required deployment:

- STUN/TURN UDP and TCP on `3478`.
- TURN/TLS on `443` through a dedicated address or SNI-based TCP routing; `5349` may remain an additional listener.
- Explicit relay allocation port range opened in host and cloud firewalls.
- Coturn REST shared-secret authentication.
- Authenticated `turn_credentials_v1` action returns username, password, TTL, and ICE-server URLs.
- Username is expiry-bound and may include a non-identifying account/call hash.
- Credentials are minted only for authenticated, rate-limited call-capable peers and are never logged.
- App contains no static TURN username, password, or shared secret.
- The ten-minute credential TTL is an authentication-material lifetime, not a maximum call duration.
- While a call is active or reconnecting, prefetch and stage a replacement credential bundle before 70% of lifetime for future allocation refresh/recreation or ICE restart; never migrate a stable selected pair only because a credential aged.
- Any new TURN allocation or ICE restart that needs TURN must use an unexpired staged bundle. The implementation must test coturn's behavior for allocation refresh across credential expiry rather than assume an existing allocation survives.
- If minting fails while current media/allocation remains healthy, continue the call and retry within a bounded budget. If a new allocation/restart is required, remain `reconnecting` for at most 15 seconds, then fail cleanly; never use a static credential or silently bypass **Always relay** with a direct route.
- Shared-secret rotation uses a tested overlap, blue/green, or drain procedure. Credentials already issued under the previous secret must either remain valid for their advertised TTL or be replaced before cutover; an uncoordinated secret flip is prohibited.
- The PeerConnection configuration, in-memory bundle replacement, zeroization/release, credential-service outage, long-call, restart, rotation, rollback, and metrics behaviors are automated acceptance cases.
- Allocation quotas, bandwidth limits, stale-allocation cleanup, and abuse alerts are mandatory.

ICE gathers direct and TURN candidates concurrently. Direct candidates have higher priority in normal mode; TURN must not wait behind a long direct-only timeout.

## 14. Push and native wake contract

### 14.1 Shared rules

- Push is a wake/presentation hint, never the call signaling source of truth.
- Relay sends push only for a current mailbox invitation and a valid recipient-issued `call_wake_handle_v1`.
- Call mailbox entries, endpoint records, wake handles, and VoIP tokens use separate durable typed storage and fail closed; they do not reuse chat-mailbox retention or a fail-open in-memory store.
- Payload contains random call handle, expiry, opaque contact handle, schema version, and optional encrypted blob only.
- No readable Peer ID, contact name, conversation ID, SDP, ICE address, or TURN credential.
- Duplicate and delayed pushes converge on the same `call_id` and native UI.

### 14.2 Android

- Register call capability with the standard FCM token.
- High-priority call data message starts only the allowed call presentation/retrieval path.
- Use Android Telecom/Core-Telecom and CallStyle.
- Declare required phone-call and microphone foreground-service permissions/types.
- Do not capture microphone audio in `FirebaseMessagingService`.
- Respect notification/full-screen permissions and show an actionable degraded state when denied.

### 14.3 iOS

- Register a distinct PushKit VoIP token; do not overwrite the ordinary APNs/FCM token.
- Deliver calls through the dedicated APNs VoIP topic and PushKit callback, never an ordinary iOS notification or the Notification Service Extension.
- Use VoIP pushes only for real, non-expired incoming calls.
- Report CallKit promptly with the random call UUID and local opaque-contact lookup, and complete the PushKit callback from the CallKit report completion. Flutter startup and authenticated mailbox retrieval continue in parallel and are never prerequisites for callback completion.
- If contact resolution is not ready, report a generic Mknoon call, then update or end after authenticated retrieval.
- Implement `CXProviderDelegate` answer, decline, end, mute, audio activation, and audio deactivation.
- Add `voip` and `audio` background modes and required entitlements/provisioning.

## 15. Audio and WebRTC requirements

- Audio-only PeerConnection; no video transceivers.
- Opus preferred with WebRTC defaults unless device evidence justifies tuning.
- Echo cancellation, noise suppression, automatic gain control, jitter buffering, and packet-loss concealment enabled where supported.
- Request microphone permission before accepting/placing media, not when merely receiving an invitation.
- Coordinate with current voice-note playback/recording: a call pauses or refuses conflicting sessions and restores eligible playback after cleanup.
- Support receiver, speaker, wired headset, Bluetooth, interruption, route change, and media-services reset.
- Route labels in user diagnostics must be coarse: `direct`, `turn_udp`, or `turn_tcp_tls`.
- Product `connected` readiness is transport/track readiness, not proof that audible samples or RTP byte counters advanced. One-way-audio detection runs after connection as a separate silence-safe diagnostic; controlled test calls may inject a known signal when proving two-way audio.

## 16. Security and privacy

- Accepted contacts only; block/remove revokes call-wake authority.
- Encrypt and sign every call signal; authenticate sender/device binding and recipient targeting.
- Fresh WebRTC DTLS-SRTP keys per call; never derive media keys from message keys.
- Authenticate SDP fingerprints in signed encrypted signaling.
- TURN forwards encrypted packets and has no media key.
- No call audio/video storage.
- Never log peer IDs, contact names, SDP, ICE addresses, ciphertext, call-wake handles, tokens, or credentials.
- Hash or bucket diagnostic correlation locally; do not send stable identifiers.
- Always-relay tests inspect outbound signaling and selected pairs for IP leakage.
- Relay rate limits by authenticated sender, recipient, device, and IP; application applies contact policy.
- Malformed and oversized data is rejected before crypto-expensive or SDP-expensive work where possible.

## 17. Cleanup contract

One cleanup routine executes on decline, cancel, hangup, timeout, failure, duplicate terminal event, app shutdown, native dismissal, and process recovery.

It must:

1. Stop audio capture/playback and remove tracks.
2. Close PeerConnection and call-specific streams.
3. Cancel timers, candidate queues, retries, subscriptions, and statistics polling.
4. End native CallKit/Telecom state and release foreground service, wake lock, audio focus, and audio session.
5. Delete/ack call mailbox entries and endpoint-specific transient state.
6. Release SDP, candidates, media keys, TURN credentials, and native descriptors.
7. Project one idempotent history entry.
8. Remove the active session and return resource counters to the allowed baseline.

## 18. Observability

Allowed metrics:

- Invite-to-ring and accept-to-audio histograms.
- Setup outcome and coarse failure reason.
- Route class: direct, TURN/UDP, TURN/TCP-TLS.
- ICE restart count, reconnect outcome, unexpected drop, and call-duration bucket.
- Push received/retrieved/expired/duplicate outcome.
- Cleanup completion and bounded resource deltas.
- TURN allocations, authentication failures, bandwidth, quota rejection, and stale cleanup.

A local diagnostics screen may show current route, ICE state, audio state, and coarse failure reason. It must not show or copy SDP, IP addresses, credentials, or peer identifiers.

## 19. Feature flags and rollout

Independent remote/local gates:

- `voice_call_capability_v1`
- `voice_call_outgoing_enabled`
- `voice_call_incoming_enabled`
- `voice_call_turn_enabled`
- `voice_call_android_native_enabled`
- `voice_call_ios_native_enabled`
- `voice_call_always_relay_enabled`

Rollout order:

1. Developers and automated local fixtures.
2. Internal foreground Android pair.
3. Internal foreground Android/iOS parity.
4. Android background/terminated canary.
5. iOS PushKit/CallKit physical-device canary.
6. Small opted-in beta cohort.
7. Wider beta only after success, leak, abuse, and rollback evidence.

The kill switch disables new invites without disrupting chat or existing non-call notifications.

## 20. Acceptance criteria

The external beta is ready only when all are true:

1. Accepted contacts can place, ring, answer, decline, cancel, and end one audio call.
2. Foreground, background, terminated, and locked incoming calls pass on each enabled platform.
3. Same-LAN and ordinary NAT calls prefer a direct selected pair.
4. Forced-direct failure succeeds through authenticated TURN/UDP.
5. UDP-blocked calls succeed through authenticated TURN/TCP or TURN/TLS on 443.
6. Always-relay mode emits and selects relay candidates only and reveals no host/server-reflexive address to the peer.
7. Signaling and media remain end-to-end encrypted.
8. Expired, malformed, replayed, blocked, and misaddressed invites never emit application `ringing`, start media, or remain in native incoming-call UI. A provisional iOS CallKit report required before full authenticated retrieval is ended promptly on validation failure.
9. Duplicate direct/mailbox/push delivery produces one session and one native UI.
10. Glare resolves to one shared call; a second unrelated call receives busy.
11. Network transitions recover by ICE restart or end cleanly within the reconnect budget.
12. Every terminal path uses the shared cleanup routine and one history projection.
13. At least 100 repeated mixed direct/TURN calls return PeerConnections, streams, timers, file descriptors, native calls, audio sessions, and TURN allocations to defined baseline deltas.
14. Push and TURN credentials rotate/expire correctly; long calls, ICE restart, minting outage, allocation refresh, and shared-secret rotation pass without a static app credential or privacy downgrade.
15. Native answer/end/cancel/expiry before Dart startup reconciles deterministically with terminal precedence, ordered exactly-once handoff, and exactly-once native cleanup.
16. A silent peer reaches **Connected** from transport and track readiness; one-way-audio diagnostics run separately and do not treat silence as setup failure.
17. Existing chat, inbox, media, push, voice-note, and lifecycle preservation gates remain green, while call custody/tokens remain durably separated from chat and ordinary iOS notifications.

## 21. Required test matrix

| Layer | Required proof |
|---|---|
| Dart/native reconciliation | Every legal/illegal transition; fake clock; duplicate; out-of-order; pre-start answer/end/cancel/expiry; ordered handoff; terminal dominance; exactly-once cleanup |
| Envelope/crypto | Schema, signature, sender/recipient binding, replay, malformed/oversized data, fingerprint authentication |
| Go/libp2p | Direct `call_signal`, deadlines, transport ACK semantics, old-peer compatibility |
| Relay | Separate mailbox TTL/capacity, Redis restart/failure, no in-memory success, roster/capability intersection, wake authorization, token separation, credential mint/expiry |
| WebRTC | Direct, TURN/UDP, TURN/TCP-TLS, relay-only, silent-peer connection readiness, controlled two-way audio proof, one-way diagnostics, route changes, ICE restart |
| Android | Foreground/background/terminated/locked, actions, permissions, CallStyle, Telecom, foreground service |
| iOS | Foreground/background/terminated/locked, PushKit callback completes after CallKit report without waiting for runtime/network, post-report validation failure, CallKit actions, audio activation, duplicate/stale push |
| TURN lifecycle | Calls beyond credential TTL, allocation refresh behavior, staged replacement, restart, minting outage, secret rotation overlap/drain, rollback |
| Security | Unknown/blocked sender, forged signature, wrong device, replay, SDP fuzz, candidate leak, credential abuse |
| Cleanup | Forced failure at every state and 100+ repeated calls with resource baselines |
| Preservation | Existing 1-to-1 messaging, inbox, push, voice-note, and app-lifecycle gates |

Mobile proof uses only targets available at execution time. Generic two-peer behavior defaults to one USB Android device plus an available Android emulator. iOS physical hardware is required only for PushKit/CallKit and platform parity claims.

## 22. Delivery plans

Implementation is split into:

1. `VC2-01-foundation-feasibility-tdd-plan.md`
2. `VC2-02-call-control-signaling-tdd-plan.md`
3. `VC2-03-foreground-webrtc-audio-tdd-plan.md`
4. `VC2-04-android-telecom-lifecycle-tdd-plan.md`
5. `VC2-05-ios-pushkit-callkit-lifecycle-tdd-plan.md`
6. `VC2-06-hardening-observability-rollout-tdd-plan.md`

The sequencing and wave gates are defined in `VC2-00-voice-calling-rollout-roadmap.md`.

## 23. Definition of done

Voice calling is done only when code, relay deployment, TURN configuration, native entitlements, automated tests, real-device evidence, metrics, feature flags, rollback, and operational ownership all satisfy this PRD. A written plan, open port, STUN response, successful build, or foreground demo alone is not completion.
