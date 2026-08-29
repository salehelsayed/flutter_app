# Mknoon 1:1 Voice Calling PRD

**Version:** 1.0  
**Status:** Proposed  
**Scope:** 1:1 voice calls only  

> This PRD starts with voice calls because that is the smallest reliable release. The same WebRTC foundation can support 1:1 video later.

## 1. Product decision

Mknoon will use:

- **go-libp2p for call signaling, peer identity, presence, and message delivery.**
- **WebRTC for live audio.**
- **Direct media when possible.**
- **TURN relay as the automatic media fallback.**
- **The existing libp2p Circuit Relay for signaling and libp2p connectivity, not as a replacement for TURN.**
- **PushKit + CallKit on iOS and Android Telecom + CallStyle notifications on Android.**

The user should not need to understand which route is being used. The app should choose the best route automatically.

## 2. Why this design

A call has two different paths:

1. **Signaling path:** sends call invitations, accept, decline, SDP, ICE candidates, hang-up, and reconnect events.
2. **Media path:** carries the live audio packets.

Mknoon already has a good signaling foundation through direct libp2p connections, Circuit Relay, the online inbox, and notifications. WebRTC should handle the media because it already provides low-latency audio, codec negotiation, echo cancellation, congestion control, NAT traversal, encryption, and TURN fallback.

Do not send live audio through a normal reliable libp2p stream for the MVP. Delayed audio packets are usually worse than dropped audio packets, while a reliable stream may wait for lost data and increase delay.

## 3. Goals

1. A user can start a voice call from a 1:1 chat.
2. The recipient can answer or decline from the app, lock screen, or notification.
3. Audio uses a direct peer-to-peer route whenever a good direct route is available.
4. The call automatically uses a relay when a direct route is unavailable.
5. Calls remain end-to-end encrypted on both direct and relayed routes.
6. A user can enable **Always relay calls** to hide their IP address from contacts.
7. Call setup and cleanup are reliable and do not leak streams, goroutines, timers, audio sessions, or keys.

## 4. Non-goals for the MVP

- Group calls
- Video calls
- Screen sharing
- Call recording
- Voicemail
- Call links
- Calling phone numbers
- Call waiting or holding two calls
- Ringing multiple linked devices
- Server-side searchable call history

## 5. User stories

### Place a call

As a user, I can open a 1:1 chat and tap the call button. I immediately see a calling screen with the contact name, avatar, and current state.

### Receive a call

As a user, I can receive an incoming call while the app is open, in the background, terminated, or while the phone is locked.

### Direct route

As a user, my call uses a direct connection when possible so that latency is lower and the relay is not used unnecessarily.

### Automatic fallback

As a user, I do not need to retry manually when a direct connection fails. The app automatically uses the media relay.

### Protect my IP address

As a privacy-conscious user, I can enable **Always relay calls**. My calls then use TURN and do not reveal my network address to the contact.

### Missed call

As a user, I see an encrypted missed-call event in the chat if I did not answer. An expired call must never start ringing later.

## 6. User experience

### 6.1 Call entry point

The 1:1 chat header contains a phone icon.

The button is disabled when:

- The contact is blocked.
- The contact relationship is no longer valid.
- The local device is already in another Mknoon call.
- Calling is not supported by the contact's app version.

### 6.2 Outgoing call screen

Show one of these states:

- Calling
- Ringing
- Connecting
- Connected
- Reconnecting
- Busy
- No answer
- Unavailable
- Call failed
- Call ended

Available controls:

- Mute microphone
- Speaker/audio route
- End call

Bluetooth and wired-headset routing should be managed through the operating system calling framework.

### 6.3 Incoming call screen

Show:

- Contact name and avatar from local data
- Answer
- Decline

The microphone must not start capturing audio until the user accepts the call.

### 6.4 Call history

Store call events locally and, when needed, as encrypted chat events:

- Outgoing call
- Incoming call
- Missed call
- Declined call
- Call duration

Do not upload a readable contact identifier or readable call history to the backend.

## 7. High-level architecture

```text
                         CALL SIGNALING

Caller UI
   |
   v
Go Call Manager
   |
   +--> Existing direct libp2p connection ------------------+
   |                                                        |
   +--> libp2p Circuit Relay -------------------------------+--> Callee Go Call Manager
   |                                                        |
   +--> Short-lived online inbox + opaque push wake-up -----+

                           LIVE AUDIO

Caller WebRTC PeerConnection
   |
   +--> Same-LAN/direct candidate ------------------------------+
   +--> NAT-traversed direct route discovered with STUN --------+--> Callee WebRTC PeerConnection
   +--> TURN over UDP fallback ---------------------------------+
   +--> TURN over TCP/TLS fallback when UDP is blocked ---------+
```

### Component responsibilities

| Component | Responsibility |
|---|---|
| Flutter/native UI | Call screen, permissions, user controls, audio route display |
| iOS CallKit/PushKit | Reliable system incoming-call experience and wake-up |
| Android Telecom/CallStyle | System call lifecycle, audio focus, routing, and incoming-call notification |
| Go Call Manager | Call state machine, authorization, deduplication, timeouts, signaling, cleanup |
| Existing libp2p delivery layer | Direct signaling, Circuit Relay fallback, short-lived inbox delivery |
| WebRTC engine | Audio capture, Opus, DTLS-SRTP, ICE, STUN/TURN, jitter handling, congestion control |
| STUN service | Helps peers discover usable public network mappings |
| TURN service | Relays encrypted WebRTC media when direct media is unavailable or disabled |
| Push service | Wakes a background device using a minimal, opaque call notification |

## 8. Important relay decision

The existing libp2p Circuit Relay and a WebRTC TURN server are different services.

- Circuit Relay carries libp2p traffic and helps peers connect or coordinate a direct upgrade.
- TURN provides relay candidates that a WebRTC PeerConnection can use for live media.

For the MVP, deploy a TURN service such as coturn. It may run beside the current relay initially, but it must be treated as a separate process with separate ports, credentials, limits, monitoring, and scaling.

## 9. Connection selection

### Normal mode

Use WebRTC ICE with direct and TURN candidates gathered at the same time.

Priority:

1. Same-LAN direct path
2. Direct UDP path through NAT traversal
3. TURN over UDP
4. TURN over TCP or TLS, normally through port 443 when required

**Direct-first must not mean direct-only first.** Do not wait through a long direct timeout before starting TURN. Gather all usable candidates in parallel, give direct candidates a higher priority, and allow TURN to win quickly when direct connectivity is not possible.

Suggested WebRTC policy:

```text
Normal mode:       iceTransportPolicy = all
Always relay mode: iceTransportPolicy = relay
```

### Established route

Once a stable call is connected, do not move it merely to save relay bandwidth. Stability is more important than changing routes during a call.

If the network changes, perform an ICE restart. The new negotiation should again prefer direct connectivity in normal mode.

## 10. Signaling delivery

Use the existing encrypted 1:1 delivery abstraction for call signaling.

Suggested protocol identifier:

```text
/mknoon/call/1.0.0
```

A call message may travel through:

1. Existing direct libp2p connection
2. Circuit Relay
3. Short-lived online inbox
4. Push wake-up followed by inbox/direct retrieval

The receiver deduplicates all paths by `call_id` and `message_id`.

### Call envelope

```json
{
  "version": 1,
  "call_id": "128-bit-random-id",
  "message_id": "128-bit-random-id",
  "type": "invite",
  "sender_device_id": "device-id",
  "sequence": 1,
  "created_at_ms": 0,
  "expires_at_ms": 0,
  "payload": {}
}
```

The complete envelope must be authenticated and encrypted through the existing trusted conversation channel.

### Message types

- `invite`
- `ringing`
- `answer`
- `ice_candidate`
- `accept`
- `decline`
- `busy`
- `cancel`
- `hangup`
- `ice_restart`
- `ended`

Messages must be idempotent. Duplicate, late, expired, and out-of-order messages must not create a second call or revive an ended call.

## 11. Call flow

### 11.1 Outgoing call

1. User taps the call button.
2. The app creates one `CallSession` and a new `call_id`.
3. The WebRTC engine creates an offer and starts gathering ICE candidates.
4. The caller sends an encrypted `invite` with the offer and expiry time.
5. The caller also triggers the opaque push wake-up path when needed.
6. The UI shows **Calling** and then **Ringing** after the callee acknowledges the invitation.
7. If the recipient accepts, the caller receives the answer and ICE candidates.
8. ICE selects the best usable route.
9. The UI changes to **Connected** only after two-way audio readiness is confirmed.
10. If the recipient does not answer, the call ends after the ring timeout and an encrypted missed-call event is created.

### 11.2 Incoming call

1. The device receives the invitation directly, through Circuit Relay, or after a push wake-up.
2. The app verifies the sender, contact relationship, expiry, protocol version, and rate limits.
3. The operating system incoming-call UI is shown.
4. The callee may prepare WebRTC and gather candidates while ringing, but must not capture or send microphone audio.
5. On **Answer**, the callee sends the WebRTC answer and candidates.
6. On **Decline**, the callee sends `decline` and ends local ringing.
7. If the invitation is expired, the device records a missed call but does not ring.

### 11.3 Simultaneous calls

If both users call each other at the same time, use a deterministic rule based on the two `call_id` values. Keep one call session and cancel the other. Both devices must choose the same winning call.

### 11.4 Busy behavior

The MVP allows one active Mknoon call per device.

If a new call arrives while a call is active:

- Do not show call waiting.
- Send `busy`.
- Record the attempt as a missed or busy call event.

## 12. Time budgets

| Event | Target |
|---|---:|
| Foreground invitation to ringing, p95 | 2 seconds or less |
| Background/locked invitation to ringing, p95 | 5 seconds or less |
| Ring duration before no-answer | 30 seconds |
| Call invitation and inbox TTL | 45 seconds |
| User accepts to usable audio, p95 | 3 seconds or less |
| Show reconnecting after media loss | 3 seconds |
| Maximum reconnect window | 15 seconds |

The app must not ring from an invitation whose expiry time has passed, even if a delayed push or inbox message arrives later.

## 13. Security and privacy requirements

1. Calls are allowed only between accepted contacts.
2. Blocked contacts cannot ring the device.
3. Call signaling is authenticated and end-to-end encrypted.
4. WebRTC media uses fresh per-call DTLS-SRTP keys.
5. Authenticate the WebRTC fingerprint through the existing encrypted signaling channel to prevent signaling tampering.
6. Do not reuse long-lived message encryption keys as media encryption keys.
7. TURN forwards encrypted packets and must not possess media decryption keys.
8. TURN credentials are short-lived and scoped to a call or a brief time window.
9. Push payloads contain no readable caller Peer ID, contact name, conversation ID, or SDP.
10. The caller name displayed by the operating system comes from local contact data.
11. Direct calls may reveal each user's IP address to the other contact. Explain this clearly in settings.
12. **Always relay calls** prevents the other participant from seeing the direct IP address.
13. No call audio or video is stored.
14. Clear call keys, SDP, ICE candidates, and temporary credentials when a call ends.
15. Reject oversized, malformed, unsupported, replayed, and expired signaling messages before expensive processing.
16. Apply per-contact and per-device call invitation rate limits.

Suggested setting text:

> **Always relay calls**  
> Hides your IP address from people you call by sending call traffic through a relay. Calls may connect more slowly or have slightly lower quality.

## 14. Mobile platform requirements

### iOS

- Use PushKit only for real incoming calls.
- Report incoming calls promptly through CallKit.
- Support answer, decline, end, mute, speaker, Bluetooth, interruption, and lock-screen behavior.
- Do not start the microphone until CallKit activates the audio session and the user has accepted.
- End CallKit state on every terminal path, including expired, canceled, failed, and duplicate invitations.

### Android

- Register calls through the Android Telecom/Core-Telecom APIs.
- Use CallStyle notifications for incoming and ongoing calls.
- Let Telecom manage audio focus and routing where supported.
- Maintain the required foreground execution state during an active call.
- Support answer, decline, end, mute, speaker, Bluetooth, interruption, and lock-screen behavior.

## 15. Concurrency and resource cleanup

The Go implementation must have a single owner for each call's mutable state.

Recommended model:

```text
CallManager
  |
  +-- activeCall atomic reference
  |
  +-- CallSession
        +-- context + cancel
        +-- serialized event loop
        +-- WebRTC handle
        +-- call-control stream handle, if dedicated
        +-- timers
        +-- pending signaling messages
        +-- cleanupOnce
```

Requirements:

1. Only one goroutine or actor loop changes a call's state.
2. Every other callback submits an event to that loop.
3. Every call owns a cancelable context.
4. `EndCall` is idempotent and protected by `sync.Once` or an equivalent mechanism.
5. Every terminal path performs the same cleanup routine.
6. Cancel all timers and pending retries.
7. Stop audio capture and playback.
8. Close the WebRTC PeerConnection.
9. Close only call-specific libp2p streams. Do not close a shared peer connection used by chat.
10. Release foreground services, wake locks, CallKit/Telecom state, and audio focus.
11. Remove the call from the active-session registry.
12. Zero or release ephemeral call secrets and TURN credentials.
13. No unbounded channels, candidate queues, retry loops, or goroutines.
14. Add stream read/write deadlines and a maximum signaling message size.

## 16. Failure behavior

| Failure | User-visible result | System behavior |
|---|---|---|
| Recipient offline | Unavailable or no answer | Invitation expires; missed-call event may be delivered later |
| Recipient declines | Declined | Stop all setup and cleanup immediately |
| Recipient already in call | Busy | Do not create a second active session |
| Direct connection fails | Connecting briefly | TURN takes over automatically |
| TURN UDP blocked | Connecting briefly | Try TURN TCP/TLS |
| Network changes | Reconnecting | Perform ICE restart |
| Reconnect fails | Call ended | Cleanup all resources and record reason |
| Caller cancels while callee answers | Call ended | Terminal event wins; no orphan audio session |
| Duplicate push/invite | No duplicate ring | Deduplicate by call and message IDs |
| Stale invitation | Missed call only | Never ring after expiry |
| Microphone permission denied | Permission required | Do not continue call setup |

## 17. Observability

Record privacy-safe operational measurements without peer IDs, contact names, SDP, ICE addresses, or call contents.

Useful measurements:

- Invitation-to-ring time
- Accept-to-audio time
- Setup success or failure reason
- Route type: direct, TURN/UDP, or TURN/TCP-TLS
- ICE restart count
- Unexpected call drop count
- One-way-audio detection
- Call duration bucket
- Cleanup completion and leaked-resource test counters

The application should have a local diagnostics screen that can show the route and failure reason for testing. Normal users do not need to see technical route details.

## 18. Acceptance criteria

The MVP is complete when all of the following are true:

1. A contact can place, answer, decline, and end a 1:1 voice call.
2. Calls work while the recipient app is foregrounded, backgrounded, terminated, and the device is locked.
3. A same-Wi-Fi call uses a direct route.
4. A call across normal home/mobile networks attempts and prefers a direct route.
5. A call succeeds through TURN when direct connectivity is deliberately blocked.
6. A call succeeds through TURN TCP/TLS when UDP is deliberately blocked.
7. **Always relay calls** never selects a host or server-reflexive candidate.
8. Direct and relayed calls remain end-to-end encrypted.
9. An expired call never rings late.
10. Duplicate invitations and push notifications create only one incoming-call UI.
11. Simultaneous outgoing calls resolve to one shared call.
12. A second incoming call receives `busy` while one call is active.
13. Wi-Fi-to-mobile and mobile-to-Wi-Fi transitions recover through ICE restart or end cleanly.
14. Decline, cancel, hang-up, timeout, failure, and app shutdown all run the same cleanup path.
15. Repeated automated calls do not leak goroutines, streams, PeerConnections, audio sessions, timers, file descriptors, or TURN allocations.

## 19. Required end-to-end test matrix

| Area | Tests |
|---|---|
| Basic flow | Call, ring, answer, two-way audio, mute, speaker, end |
| Direct routing | Same LAN; different NATs; caller public; callee public |
| Relay routing | Symmetric NAT; direct addresses blocked; relay-only privacy mode |
| Restricted networks | UDP blocked; only TCP/TLS 443 allowed |
| App state | Foreground; background; terminated; locked screen |
| Race conditions | Cancel versus answer; decline versus timeout; duplicate hang-up |
| Concurrency | Simultaneous calls; second call while active; repeated rapid calls |
| Network changes | Wi-Fi to mobile; mobile to Wi-Fi; temporary packet loss |
| Notifications | Duplicate push; delayed push; stale push; push without inbox data |
| Permissions | Microphone denied; notification denied; Bluetooth changes |
| Security | Invalid sender; blocked sender; replay; expired invite; malformed SDP; oversized message |
| Cleanup | 100+ repeated calls; forced failures at every state; app process restart |

## 20. Delivery plan

### Phase 1: Call control foundation

- Call state machine
- Signaling schema and protocol
- Direct/relay/inbox delivery
- Deduplication and expiry
- Call UI using simulated media
- Concurrency and cleanup tests

### Phase 2: Foreground voice calls

- WebRTC audio
- STUN
- TURN UDP and TCP/TLS
- Direct-first ICE policy
- Audio controls
- Route diagnostics

### Phase 3: Background reliability

- iOS PushKit and CallKit
- Android Telecom and CallStyle
- Opaque push wake-up
- Locked and terminated app tests

### Phase 4: Privacy and hardening

- Always relay calls
- Temporary TURN credentials
- Rate limiting
- Network-change recovery
- Security, load, and resource-leak tests
- Small beta rollout

## 21. Final recommendation

Build the feature around **libp2p signaling + WebRTC media + TURN fallback**.

This gives Mknoon the direct-first behavior you want without making users wait when direct connectivity is impossible. It also reuses the strongest part of the current app—the authenticated libp2p messaging and relay path—without forcing live audio into a transport that was not designed as a complete mobile calling engine.
