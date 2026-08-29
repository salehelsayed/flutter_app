# VC2-04 — Android Telecom and Call Lifecycle TDD Plan

**Status:** Proposed  
**Depends on:** VC2-03  
**May run parallel with:** VC2-05  
**Primary outcome:** Android incoming and active calls use Telecom/Core-Telecom and CallStyle correctly in foreground, background, terminated, and locked states.

## 1. Current baseline

Android currently has:

- `MknoonFirebaseMessagingService` with strict standard wake/recovery handling.
- Notification permission and general foreground/background infrastructure.
- Microphone permission used by voice notes.
- JVM/Robolectric native tests under `android/app/src/test`.

It does not have Telecom/Core-Telecom registration, CallStyle call notifications, a phone-call/microphone foreground service, native answer/decline/end actions, or killed-process call recovery.

## 2. Scope

### In scope

- AndroidX Core-Telecom/Telecom call registration.
- High-priority opaque call wake dispatch from the existing FCM service.
- Incoming/ongoing CallStyle notifications and full-screen behavior where allowed.
- Foreground service and required runtime/manifest permissions.
- Native answer, decline, end, mute, route, and audio-focus lifecycle.
- Headless/terminated startup handoff into one Dart CallCoordinator.
- Duplicate, stale, canceled, blocked, denied-permission, process-death, and locked-device behavior.
- Android host tests and automated physical-device/emulator proof.

### Out of scope

- iOS, video, system dialer/PSTN integration, call waiting, and multi-device ringing.

## 3. Proposed native surfaces

- `android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallLifecycleController.kt`
- `android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallForegroundService.kt`
- `android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNotificationFactory.kt`
- `android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallActionReceiver.kt`
- `android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNativeBridge.kt`
- `android/app/src/main/kotlin/com/mknoon/app/call/PendingNativeCallStore.kt`
- `android/app/src/main/kotlin/com/mknoon/app/call/CallPayloadParser.kt`
- Focused JVM tests under matching `android/app/src/test/.../call/`.
- A dedicated instrumentation source set only for device-required lifecycle proof.

Existing files likely changed:

- `android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingService.kt`
- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- Platform-channel/bootstrap Dart composition.

Names are proposed new files, not statements that they already exist.

## 4. Ownership contract

- Telecom/Core-Telecom owns the Android system call and audio endpoint lifecycle.
- Native controller owns only Android registration, notification, actions, and restart-safe descriptor handoff.
- Dart CallCoordinator remains the canonical product-state owner after runtime attachment.
- Before attachment, native owns only one protected, versioned, bounded pre-start record containing call UUID/handle, expiry, opaque references, presentation status, monotonic event sequence, pending action/terminal reason, and handoff acknowledgement.
- FCM service parses a strict opaque call-wake grammar, durably stores that descriptor, and requests call presentation/retrieval. It never decrypts SDP, starts microphone capture, or reports success from fail-open process memory.
- One call UUID maps to one native call, one pending descriptor, and one Dart session.

### Reconciliation

- Answer, decline, end, remote cancel, expiry, provider removal, and audio activation before Flutter attachment append ordered idempotent events.
- Terminal/provider-reset/expiry events dominate answer/presentation. Dart never adopts or revives a terminal descriptor.
- On attachment, Dart authenticates the invitation and trusted-roster/relay-capability endpoint binding, consumes events in order exactly once, and acknowledges adoption or cleanup.
- Native deletes the acknowledged record exactly once; process recreation may replay only unacknowledged events.
- A pre-start answer is intent only. No SDP, ICE, microphone, or media starts before Dart adoption, permission, and native audio activation.

## 5. Manifest and platform contract

Add only permissions and declarations required by the selected Core-Telecom implementation and supported API bands. Expected review includes:

- `RECORD_AUDIO`
- `POST_NOTIFICATIONS`
- `USE_FULL_SCREEN_INTENT` where applicable
- `MANAGE_OWN_CALLS` when required by self-managed Telecom
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_PHONE_CALL`
- `FOREGROUND_SERVICE_MICROPHONE`
- Bluetooth permission already required by the app/API band
- Foreground service with explicit `phoneCall|microphone` types where supported
- Non-exported internal action receiver/service unless an Android framework contract requires otherwise

Tests must inspect the merged manifest for debug and release. Do not rely only on source manifest text.

API behavior must be explicit for every supported Android band:

- notification permission denied;
- full-screen intent unavailable/denied;
- locked versus unlocked device;
- background-start restrictions;
- microphone foreground-service restrictions;
- Bluetooth route permission and availability.

A degraded heads-up/notification flow is acceptable only when Android policy prevents full-screen presentation; it must remain actionable and truthful.

## 6. Opaque FCM call wake

### Grammar

Define a separate exact call payload version, for example:

- schema/version;
- random call handle/UUID;
- expiry;
- opaque contact handle;
- mailbox retrieval token or encrypted blob reference;
- no readable Peer ID, contact name, conversation ID, SDP, ICE address, or TURN credential.

Do not overload the existing fixed ordinary-message wake grammar.

Pending descriptors, endpoint/wake state, and call capability use separate durable typed storage. Required persistence failure suppresses presentation; it never falls back to a successful in-memory-only call path.

### RED tests

- Valid non-expired call wake routes exactly once to the call controller.
- Ordinary message wake retains current behavior.
- Rich ordinary notification is never interpreted as a call.
- Unknown keys, duplicate keys, malformed UUID, oversized data, missing expiry, and stale payload reject before side effects.
- Duplicate push creates one pending descriptor and one native call.
- Canceled/acked mailbox invite suppresses presentation.
- Blocked/unknown contact after authenticated retrieval ends without ringing.
- FCM service never calls microphone, WebRTC, or chat notification APIs.
- Sensitive values never appear in logs, notification extras exposed to other apps, or crash strings.

## 7. Native call lifecycle TDD

### JVM/Robolectric RED cases

1. Register one incoming call from one validated descriptor.
2. Duplicate registration returns/adopts existing UUID.
3. Answer action persists before Flutter attachment and delivers once after attachment.
4. Decline sends one terminal action and removes notification/service state.
5. End from Dart ends Telecom and notification exactly once.
6. End from Telecom submits one Dart terminal event exactly once.
7. Process recreation adopts pending native state without duplicate ringing.
8. Expired descriptor at startup never registers a call.
9. Remote cancel while locked ends ringing promptly.
10. Busy second call returns busy without a second native call.
11. Notification/full-screen permission denial produces approved degraded behavior.
12. Foreground service starts only on an allowed call path and stops on every terminal path.
13. Microphone service/type begins only after answer and permission.
14. Audio focus/route callbacks serialize through one controller.
15. Malformed platform-channel events reject without crashing.
16. Standard push/recovery tests remain unchanged and green.
17. Pre-start answer then remote cancel/expiry converges to terminal without Dart revival.
18. Dart adoption acknowledges and deletes one native record; process recreation replays only unacknowledged event sequences.
19. Durable-store failure creates no native call and does not disturb ordinary FCM recovery.

### Native-to-Dart event contract

Events are versioned and idempotent:

- incoming presented;
- answer requested;
- decline requested;
- end requested;
- mute changed;
- audio route changed;
- audio activated/deactivated;
- native failure;
- native call removed.

Every event includes the random call UUID, monotonic native event sequence, and stable event ID, not Peer ID/contact name. Dart returns the highest consumed sequence plus adoption/terminal acknowledgement so native can delete exactly once.

## 8. Audio and service behavior

- Register call with Telecom before advertising `ringing`.
- Answer action causes Dart `accept`; microphone starts only after permission, native audio activation, and WebRTC setup.
- Telecom/Core-Telecom manages supported endpoints; Dart receives coarse route state.
- Ongoing call has one non-dismissible CallStyle/foreground notification as required.
- Mute state is reconciled with the actual WebRTC track.
- Bluetooth/wired route loss selects a valid fallback and updates UI.
- Interruption by cellular/emergency/system policy follows supported Telecom behavior and ends or pauses cleanly.
- Every terminal path stops foreground service, notification, audio focus, route listeners, pending descriptor, and wake locks.

## 9. Instrumented device matrix

Resolve live targets before execution.

Default:

- Peer A: USB-connected physical Android device.
- Peer B: available Android emulator.

Pin every `flutter run`, install, `adb`, and test command to the discovered IDs.

Automated scenarios:

1. Foreground incoming and outgoing.
2. App backgrounded.
3. App force-stopped only where Android delivery policy permits a meaningful claim; otherwise record the exact OS limitation.
4. Process terminated but app not force-stopped.
5. Device locked.
6. Duplicate and delayed FCM wake.
7. Invite canceled before answer.
8. Notification permission denied.
9. Full-screen intent unavailable.
10. Microphone denied then later granted.
11. Bluetooth connect/disconnect and speaker toggle.
12. Network transition during active call.
13. Process killed during ringing and active call.
14. Repeated call cleanup.

Do not require an unavailable Android API version. Preserve older/newer branches with host/native tests and available AVDs.

## 10. Required gates

### Android host

Run exact new JVM/Robolectric tests plus existing:

- `MknoonFirebaseMessagingServiceTest`
- `HeadlessCanonicalRecoveryWorkerTest`
- `MainActivityOnNewIntentTest`
- App visibility and native-runtime ownership tests
- Merged-manifest contract tests

Use the project's Gradle test task/configuration that already runs `android/app/src/test`.

### Dart

- Exact Android adapter/platform-channel call tests.
- All VC2-02/VC2-03 state, signaling, media, and cleanup tests.
- `./scripts/run_host_test_gates.sh 1to1`
- `./scripts/run_host_test_gates.sh feature-host-all`
- `core-host-all` only if shared core/notification surfaces changed.

### Device

Run the dedicated instrumentation/harness cases on explicitly pinned physical/emulator IDs. Capture coarse states/timings, not identities, tokens, SDP, or addresses.

No full `host-all` is required until both enabled native platform plans reach their wave closure.

## 11. Security and policy gates

- Strict FCM payload parser and size bound.
- Opaque local contact handle; no readable sender metadata in push.
- Pending native descriptor encrypted/protected at rest or minimized to non-sensitive random handles.
- Components default non-exported; PendingIntents use explicit package/component and correct mutability.
- No logcat token, contact, Peer ID, SDP, candidate, credential, or call-wake handle.
- Bounded local payload checks occur before presentation; authenticated contact/device policy uses the trusted-roster/relay-capability intersection before application `ringing` or media.
- Block/remove revocation suppresses future call wake.
- Android policy and Play Store declarations for full-screen/foreground call use are documented before beta.

## 12. Acceptance criteria

- Android call arrives and is actionable in foreground, background, process-terminated, and locked states allowed by platform policy.
- Core-Telecom/Telecom and CallStyle own the system experience; no custom notification-only substitute is claimed as completion.
- Answer, decline, end, mute, speaker/Bluetooth, and remote cancel work once each.
- Duplicate/stale pushes and process recreation cannot create duplicate calls.
- Pre-start answer/end/cancel/expiry and Dart attachment obey ordered handoff, terminal precedence, acknowledgement, and exactly-once cleanup.
- Microphone never starts in FCM service or before answer, permission, and audio activation.
- Foreground service and all native resources stop on every terminal path.
- Permission/policy denial has approved truthful fallback.
- Physical Android plus emulator automated matrix passes.
- Existing ordinary FCM, notification recovery, app visibility, and native runtime tests remain green.
- Android call feature remains separately kill-switchable.
