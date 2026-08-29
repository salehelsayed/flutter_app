# VC2-05 — iOS PushKit and CallKit Lifecycle TDD Plan

**Status:** Proposed  
**Depends on:** VC2-03  
**May run parallel with:** VC2-04  
**Primary outcome:** iOS receives real VoIP pushes and presents/operates one CallKit call correctly in foreground, background, terminated, and locked states.

## 1. Current baseline

iOS currently has:

- Standard APNs/Firebase registration and notification callbacks in `AppDelegate.swift`.
- Notification Service Extension and notification recovery plumbing.
- RunnerTests for notification, app visibility, bridge, privacy, and recovery behavior.
- Microphone usage text.

It does not have PushKit registration, a VoIP token model, CallKit provider/controller, VoIP/audio background modes for calling, CallKit audio activation, or a real incoming-call push service.

## 2. Scope

### In scope

- Distinct PushKit VoIP token registration, refresh, relay storage, invalidation, and revocation.
- Direct APNs VoIP push provider path at the relay.
- Strict opaque VoIP payload and local contact-handle resolution.
- `CXProvider`, `CXCallController`, actions, updates, end reasons, and audio activation/deactivation.
- Foreground, background, terminated, and locked-device behavior.
- Cold Flutter/Go runtime handoff with one pending native descriptor.
- iOS entitlements, background modes, provisioning requirements, RunnerTests, simulator host tests, and physical-iPhone proof.

### Out of scope

- Android, video, system Contacts exposure, PSTN, Siri intents, Call Directory, call waiting, and multi-device ringing.

## 3. Proposed native and relay surfaces

### iOS

- `ios/Runner/MknoonVoipPushRegistry.swift`
- `ios/Runner/MknoonCallKitController.swift`
- `ios/Runner/MknoonCallNativeBridge.swift`
- `ios/Runner/PendingNativeCallStore.swift`
- `ios/Runner/OpaqueCallContactResolver.swift`
- `ios/Runner/VoipPayloadParser.swift`
- Focused tests in `ios/RunnerTests/`.

Existing files likely changed:

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- Runner entitlements and Xcode project membership.
- Dart bootstrap/platform-channel composition.

### Relay

- `go-relay-server/apns_voip_push.go`
- `go-relay-server/apns_voip_push_test.go`
- VoIP-token typed storage/Redis tests, invalid-token cleanup, capability and rate-limit handling.

Do not route VoIP pushes through the Notification Service Extension. It is not the CallKit/PushKit entry point.

## 4. Token and push contract

### Separate token authority

- PushKit VoIP token is a distinct typed record from ordinary APNs/FCM token.
- It is bound to authenticated account/device identity, app environment, bundle VoIP topic, capability version, and expiry/refresh epoch.
- Updating/removing a VoIP token cannot overwrite or delete the standard notification token.
- App logout/account migration/device replacement revokes the token.
- APNs invalid-token responses remove only the exact stale VoIP token generation.
- VoIP token and call-wake state are durable typed Redis records; required writes/revocations fail closed and never report in-memory-only success.
- Ordinary iOS notifications and the Notification Service Extension are never fallback call-delivery mechanisms.

### APNs VoIP provider

- Uses approved APNs authentication and `.voip` topic.
- Sends only for a committed, current call-mailbox invite and valid wake handle.
- Uses appropriate VoIP push type/priority/expiration.
- Never logs token, payload secret, Peer ID, contact name, SDP, ICE, or TURN credential.
- Retries only retryable provider outcomes within invite expiry; stale pushes are dropped.
- Provider response is measured with coarse status categories.

No APNs key, certificate private key, team credential, or token is committed to the repository or evidence.

## 5. Opaque VoIP payload

Strict versioned payload contains only:

- schema/version;
- random call UUID/handle;
- expiry;
- opaque contact handle;
- mailbox retrieval reference or encrypted blob reference;
- no readable Peer ID, name, conversation ID, SDP, ICE address, or TURN credential.

### Native local lookup

- App maintains a protected local mapping from recipient-issued opaque contact handle to current local contact display data.
- Mapping is updated only after accepted-contact verification.
- Block/remove revokes mapping and relay authorization.
- Native may report a generic **Mknoon call** immediately if lookup is unavailable, then update CallKit after authenticated mailbox retrieval.
- Invalid/unknown/expired data ends any provisionally reported call promptly, never emits application `ringing`, and never starts media.

## 6. CallKit ownership contract

- One `CXProvider` for the process.
- One random `UUID` maps to one call handle, pending descriptor, and Dart session.
- Native reports incoming call promptly in the PushKit callback and completes the callback within the OS budget.
- Dart CallCoordinator remains canonical product-state owner after runtime attachment.
- Before attachment, native persists only one protected, versioned, bounded record containing call UUID/handle, expiry, opaque references, presentation status, monotonic event sequence, pending action/terminal reason, and handoff acknowledgement.
- CallKit actions persist as bounded native events and deliver in order exactly once after Flutter attachment.
- Native and Dart terminal requests converge on one CallKit end and one shared cleanup.

Terminal/provider-reset/authenticated-cancel/expiry events dominate pending answer or presentation. A pre-start answer is intent only: no SDP, ICE, microphone, or media starts until Dart validates/adopts the call and CallKit activates audio. Dart acknowledges the highest consumed native sequence plus adoption/terminal cleanup; native deletes the record exactly once and replays only unacknowledged events after process recreation.

Supported actions:

- answer;
- end/decline;
- mute;
- audio activated;
- audio deactivated;
- provider reset;
- route/interruption notification;
- remote cancel/update.

## 7. PushKit and payload RED tests

Host-testable tests fail until:

1. VoIP token registration sends a typed token record distinct from standard token.
2. Duplicate token update is idempotent.
3. Token rotation revokes only the old generation.
4. Exact payload grammar accepts a valid fixture.
5. Unknown/duplicate keys, malformed UUID, stale expiry, oversized value, or missing handle rejects.
6. Payload never exposes readable sender/contact/SDP fields.
7. Duplicate VoIP push maps to one pending descriptor/CallKit UUID.
8. Canceled/acked mailbox invite suppresses or promptly ends presentation.
9. Blocked/unknown sender after retrieval cannot remain ringing.
10. AppDelegate standard notification handling remains unchanged.
11. Notification Service Extension never claims the VoIP call path.
12. Logs/errors redact payload and token values.
13. CallKit report completion invokes the PushKit completion handler before delayed Flutter startup or mailbox retrieval finishes.
14. Post-report authentication failure ends CallKit promptly without application `ringing` or media.
15. Durable VoIP-token/wake persistence failure cannot succeed in memory or fall back to ordinary notification delivery.

Relay Go tests cover APNs request headers/topic, payload bound, expiration, retry classification, invalid-token cleanup, rate limits, token separation, Redis restart, and redaction.

## 8. CallKit lifecycle TDD

RunnerTests fail before production wiring for:

1. Report one incoming call and return successful presentation event.
2. Duplicate report adopts existing UUID.
3. Answer action persists before Flutter startup and delivers once afterward.
4. Decline/end action ends CallKit once and submits one terminal event.
5. Remote cancel before answer ends ringing and clears descriptor.
6. Dart end and CallKit end race converge.
7. Provider reset ends every native descriptor and tells Dart once.
8. Expired descriptor on cold launch never restores a call.
9. Busy second call is rejected without a second CallKit call.
10. Contact-name update uses only local opaque mapping.
11. Audio does not start before `provider(_:didActivate:)` and user answer.
12. Audio deactivation/interruption serializes into CallCoordinator.
13. Process recreation adopts one pending descriptor.
14. Every terminal path clears pending store and native references.
15. Existing AppDelegate, app-visibility, notification-recovery, and Go-bridge tests remain green.
16. Answer then remote cancel/expiry before Flutter attachment resolves terminally and is not revived.
17. Dart adoption consumes ordered native events once, acknowledges the highest sequence, and deletes the descriptor exactly once.

## 9. Audio-session contract

- CallKit controls activation/deactivation timing.
- Configure play-and-record/voice-chat mode only for an accepted active call.
- WebRTC audio starts after CallKit activation and microphone permission.
- Mute action reconciles with actual local track state.
- Support receiver, speaker, wired, Bluetooth, interruption, media-services reset, and route change.
- Do not configure a permanent call audio session during app startup or ringing.
- Cleanup deactivates/releases call audio without breaking ordinary notification sounds or later voice notes.

## 10. App lifecycle and cold runtime

### Push callback

1. Parse strict bounded payload.
2. Verify expiry and local opaque-handle shape.
3. Persist minimal protected native descriptor.
4. Report CallKit with random UUID promptly.
5. Invoke the PushKit completion handler from the `reportNewIncomingCall` completion. Do not wait for Flutter, Go, network connection, or mailbox retrieval.
6. In parallel with CallKit processing, start/adopt Flutter/Go runtime through the established single-runtime ownership seam and retrieve/decrypt/validate the mailbox invite.
7. Intersect authenticated contact-device authority with the matching relay capability epoch. On success, update local caller name, adopt the native record, and submit application `incomingPresented`; otherwise end CallKit promptly with an approved reason and no media.

This ordering follows Apple's [Responding to VoIP Notifications from PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit) guidance: report the incoming call while connection work continues in parallel.

### Answer from terminated state

- Persist answer intent first.
- Start/adopt runtime once.
- Deliver action to CallCoordinator once.
- Obtain credentials, exchange SDP/ICE, and start WebRTC only after CallKit audio activation.
- If setup fails, end CallKit and cleanup; never leave a phantom system call.

## 11. Entitlements and provisioning

Required review/proof:

- Push Notifications entitlement.
- Background modes include `voip` and `audio` in addition to any existing modes.
- Correct VoIP APNs topic/environment.
- Keychain/App Group access for the minimal opaque-contact/native descriptor data if used.
- Runner and test targets retain correct entitlements without granting the Notification Service Extension unnecessary VoIP authority.
- Release/profile archive resolves capabilities and provisioning.

Source assertions alone are insufficient; inspect built entitlements/profile where possible without exposing signing material.

## 12. Physical-device matrix

A physical iPhone is required for PushKit/CallKit delivery claims. Resolve available targets immediately before execution and pin exact IDs.

Automated or tightly scripted cases:

1. Foreground incoming/outgoing.
2. Background app.
3. Process terminated but app remains eligible for VoIP delivery.
4. Locked device.
5. Duplicate and delayed VoIP push.
6. Remote cancel before answer.
7. Answer/decline/end from lock screen.
8. Microphone permission denied.
9. Bluetooth/wired/speaker route changes.
10. Network transition during call.
11. App/runtime crash during ringing and active call.
12. APNs invalid-token cleanup on controlled fixture.
13. Repeated calls and provider resets.

A simulator may prove CallKit host behavior but cannot replace real PushKit delivery evidence.

## 13. Required gates

### iOS host

Use the established serial RunnerTests command on an available simulator, focusing first on new call test classes, then `RunnerTests`.

Preserve:

- `IosNotificationRecoveryTests`
- `IosNseMailboxWakeCoordinatorTests`
- `NotificationServiceConfigurationTests`
- `IosReceiverBootstrapHandoffTests`
- `IosAppVisibilitySnapshotTests`
- `GoBridgeCriticalTaskTests`

### Dart

- Exact iOS platform-channel/call adapter tests.
- All VC2-02/VC2-03 signaling, state, media, and cleanup tests.
- `./scripts/run_host_test_gates.sh 1to1`
- `./scripts/run_host_test_gates.sh feature-host-all`
- `core-host-all` only if shared core/notification surfaces changed.

### Relay

- Exact APNs VoIP provider/token tests.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in `go-relay-server`.

### Device

Physical-iPhone PushKit/CallKit matrix with redacted evidence. Do not claim completion from simulator-only success.

## 14. Security and App Store policy gates

- VoIP pushes correspond only to real current call invitations.
- Every VoIP push results in prompt CallKit report or documented immediate invalid termination.
- No use of PushKit for ordinary messages or silent maintenance.
- No readable caller identity or SDP in APNs payload.
- Provider credentials and device tokens never enter logs/artifacts.
- Revoked/blocked wake handles cannot trigger a lasting ring.
- App privacy disclosure and App Store capability justification are updated before beta submission.

## 15. Acceptance criteria

- Distinct VoIP token registration, rotation, revocation, Redis durability, and APNs invalidation work without affecting standard notifications.
- Real VoIP push presents one CallKit call in foreground, background, terminated, and locked states on an available physical iPhone.
- Duplicate/stale/canceled pushes cannot create duplicate or late ringing.
- PushKit callback completion never waits for Flutter, Go, network connection, or mailbox retrieval; post-report validation failure ends provisional CallKit promptly.
- Answer, decline, end, mute, route change, remote cancel, provider reset, and process recreation converge once.
- Pre-start answer/end/cancel/expiry reconciles through ordered native events, terminal precedence, Dart acknowledgement, and exactly-once descriptor/CallKit cleanup.
- Local contact display comes from protected opaque-handle mapping; push exposes no readable identity/SDP.
- WebRTC audio starts only after answer, permission, and CallKit audio activation.
- Every terminal path ends CallKit and clears native/Dart/media resources.
- Existing standard APNs/FCM, Notification Service Extension, app visibility, and recovery tests remain green.
- iOS call feature remains separately kill-switchable.
