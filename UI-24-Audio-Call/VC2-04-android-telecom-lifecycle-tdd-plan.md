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

## 13. Execution and verification (2026-08-31)

### Outcome and scope

VC2-04 is implemented in the cumulative VC2-01 through VC2-03 worktree. The
Android production boundary uses AndroidX Core-Telecom
`androidx.core:core-telecom:1.1.0-beta01`, a real Telecom call, a CallStyle
foreground notification, a non-exported internal action receiver, a bounded
protected durable pre-start store, and a versioned platform bridge. The
Android capability remains independently default-off through
`ENABLE_ANDROID_NATIVE_CALLS`; the disposable proof enables it only with an
explicit Gradle property and a distinct application ID.

Dart `CallCoordinator` remains the canonical product-state owner after
attachment. Native state is limited to one pre-start descriptor plus ordered
idempotent events. Answer before attachment remains intent only; signaling,
ICE, microphone capture, and media remain behind authenticated Dart adoption,
permission, native audio activation, and the existing VC2-03 engine path.

The host and emulator evidence below is green. Full VC2-04 acceptance is not
claimed because the physical Android campaign could not complete after its
secure keyguard became locked. VC2-05 and VC2-06 were not implemented or
edited, and no commit or push was made.

### Android host and manifest verification

The exact VC2-04 JVM/Robolectric classes plus the required preservation
classes were run with:

```sh
cd android
./gradlew :app:testDebugUnitTest \
  --tests com.mknoon.app.call.MknoonCallLifecycleControllerTest \
  --tests com.mknoon.app.call.MknoonCallAndroidRuntimeTest \
  --tests com.mknoon.app.call.MknoonCallForegroundServiceTest \
  --tests com.mknoon.app.call.MknoonCallNotificationFactoryTest \
  --tests com.mknoon.app.call.MknoonCallActionReceiverTest \
  --tests com.mknoon.app.call.MknoonCallNativeBridgeTest \
  --tests com.mknoon.app.call.MknoonCallManifestContractTest \
  --tests com.mknoon.app.MknoonFirebaseMessagingServiceTest \
  --tests com.mknoon.app.call.CallPayloadParserTest \
  --tests com.mknoon.app.call.PendingNativeCallStoreTest \
  --tests com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest \
  --tests com.mknoon.app.MainActivityOnNewIntentTest \
  --tests com.mknoon.app.MainActivityAppVisibilityTest \
  --tests com.mknoon.app.AppVisibilitySnapshotStoreTest \
  --tests com.mknoon.app.NativeRuntimeOwnershipSourceTest \
  --console=plain
```

Result: 110/110 tests passed, with zero failures, errors, or skips. The ten
VC2-04 classes contributed 85 tests; the five preservation classes contributed
25. After the final build-harness hardening, the debug manifest/build contract
was rerun separately and passed 4/4.

Debug and release Kotlin compilation passed with:

```sh
cd android
./gradlew :app:compileDebugKotlin :app:compileReleaseKotlin --console=plain
```

The ordinary release unit-test task reaches a pre-existing generated Flutter
registrant error because the dev-only `integration_test` plugin is absent from
the normal release classpath. The exact failure was
`dev.flutter.plugins.integration_test.IntegrationTestPlugin` not found. The
repository's existing disposable release-test configuration supplies that
test-only dependency; the VC2-04 release contract passed 4/4 with:

```sh
cd android
./gradlew :app:testReleaseUnitTest \
  --tests com.mknoon.app.call.MknoonCallManifestContractTest \
  -PenableGroupExitReleaseDiagnosticsProof=true \
  -PandroidApplicationId=com.mknoon.app.pb266proof \
  -PdisableGoogleServicesForDisposableProof=true \
  -PallowDebugSigningInRelease=true \
  --console=plain
```

The default manifests were then restored and regenerated with:

```sh
cd android
./gradlew :app:processDebugManifest :app:processReleaseManifest --console=plain
```

Both merged manifests use `com.mknoon.app`, contain the uncapped
`MANAGE_OWN_CALLS`, phone-call foreground-service, and microphone
foreground-service permissions, declare the call service non-exported with
`phoneCall|microphone`, declare the internal receiver non-exported, and exclude
the disposable proof Activity.

### Dart, Go, and curated host gates

The complete call feature and VC2-03 foreground WebRTC preservation campaign
passed 409/409:

```sh
flutter test --no-pub \
  test/features/call \
  test/integration/android_foreground_webrtc_audio_campaign_test.dart
```

The final adapter/composition/layering sentinel passed 58/58:

```sh
flutter test --no-pub \
  test/features/call/infrastructure/android_call_lifecycle_adapter_test.dart \
  test/core/bootstrap/call_signaling_composition_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart
```

Focused analysis of the adapter, composition, coordinator, cleanup, and
call-scoped media-owner production/test pairs reported no issues across ten
files. Formatting checked 101 call/bootstrap/proof files with zero changes.

The required curated lanes completed as follows:

- `./scripts/run_host_test_gates.sh 1to1`: 182 paths, 2,956 passed, 3 skipped.
- `./scripts/run_host_test_gates.sh feature-host-all`: 887 paths, 9,797 passed,
  11 skipped. One earlier attempt exited nonzero at 9,796 passed and 11 skipped;
  its exact failing assertion was not retained, and the complete rerun did not
  reproduce the failure.
- `./scripts/run_host_test_gates.sh core-host-all`: 436 Dart paths, 3,609
  passed, plus the renderer and dropped-push manifest scripts passed. This lane
  was justified because VC2-04 changes the shared Android FCM boundary.
- `bash scripts/check_reliability_simulation_discovery.sh`: passed and
  discovered the VC2-04 target-pinned lifecycle runner.

The relay and bridge host suites passed:

```sh
cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... -count=1
```

The relay sender contract verifies an opaque data-only Android call wake and
the Android parser/FCM tests reject unknown, duplicate, oversized, malformed,
or stale call payloads before presentation while preserving ordinary FCM and
recovery routing.

Full `host-all` was not run, in accordance with the wave-level cadence after
both enabled native platform plans.

### Live device matrix and disposable build boundary

The matrix was re-resolved using all three required commands:

```sh
flutter devices --machine
adb devices
xcrun simctl list devices available
```

The Android targets used were:

- physical Pixel 6, `21071FDF600CSC`, Android 16 / API 36;
- Android emulator, `emulator-5554`, Android 17 / API 37.

Available iOS devices and simulators were not used because no iOS-specific
claim was required for VC2-04.

The final disposable proof APK pair was built once from a new empty artifact
directory with:

```sh
scripts/run_vc204_android_call_lifecycle_e2e.sh \
  --build-only \
  --artifact-dir /tmp/vc204-proof-final4.0URk2n
```

The proof build is isolated under a sentinel-protected
`vc204-proof-gradle-build` leaf, rejects unsafe or nonempty build roots, removes
the entire isolated Gradle build tree after copying and hashing the APKs, and
does not share output state with the normal app. `apkanalyzer` confirmed the
normal APK as `com.mknoon.app` and the proof APK as
`com.mknoon.app.vc204proof`; the normal APK hash was unchanged across the proof
build. A causal unsafe-root check and a nonempty-artifact refusal check both
passed.

### Emulator device campaign

The final emulator command was:

```sh
scripts/run_vc204_android_call_lifecycle_e2e.sh \
  --device-id emulator-5554 \
  --artifact-dir /tmp/vc204-proof-final4.0URk2n \
  --result-dir /tmp/vc204-proof-final4.0URk2n/results-emulator \
  --scenario vc204_android_call_lifecycle
```

Result: 13/13 timed phases passed, zero instrumentation skips, and zero policy
N/A cases. The campaign exercised actual Core-Telecom presentation and the
CallStyle foreground service in foreground/background and locked states;
duplicate and delayed ingress; pre-answer remote cancel; ringing and
acknowledged-active process death/reconciliation; notification/full-screen
denial; microphone deny/grant; speaker endpoint selection; a live network
loss/restore transition; and repeated cleanup.

On API 37, notification/full-screen denial produced the truthful
`platform-rejected-clean` result: a durable `NATIVE_FAILURE`, no notification,
no audio ownership, and terminal acknowledgement. Android's `am kill` was a
no-op while Telecom protected the provider in both process-death legs, so the
debuggable proof used the bounded same-UID `SIGKILL` fallback. Both deaths and
reconciliations passed; neither is labeled force-stop. Android force-stop
delivery remains `NOT_PROVEN_POLICY_LIMITATION` because the OS suppresses
delivery until explicit relaunch.

The harness restored captured screen/keyguard/network state, uninstalled both
disposable packages, verified their absence across Android users, and retained
only coarse state/timing artifacts. The final artifact privacy scan passed.
Foreground task/HOME state is explicitly not captured or claimed.

The normal Flutter integration APK was then exercised independently on the
same explicit emulator:

```sh
flutter test --no-pub -d emulator-5554 \
  integration_test/call_control_signaling_e2e_test.dart \
  integration_test/audio_peer_connection_proof_test.dart
```

Result: 3/3 passed. An earlier run made after a shared proof build was discarded
because the normal Flutter command reused the proof application ID. The final
sentinel-protected isolated build eliminated that collision; no evidence from
the discarded run is counted.

### Physical Android evidence and open limitations

The physical command used the pinned API 36 target:

```sh
scripts/run_vc204_android_call_lifecycle_e2e.sh \
  --device-id 21071FDF600CSC \
  --artifact-dir /tmp/vc204-proof.DTD3Ve \
  --result-dir /tmp/vc204-proof.DTD3Ve/results23-physical \
  --scenario vc204_android_call_lifecycle
```

Before the secure-keyguard restoration failure, the physical device passed five
timed phases: foreground/background presentation, duplicate/delayed ingress and
pre-answer cancel, ringing seed, ringing process-death reconciliation, and
locked presentation. The ringing death required the same bounded same-UID
`SIGKILL` fallback after `am kill` was a no-op. The remaining notification
denial, microphone, route, network, acknowledged-active process-death, repeated
cleanup, and normal Flutter integration phases were not executed on the
physical device and are not claimed.

Both disposable packages were subsequently removed and their absence was
verified. A final read-only probe reported the physical device interactive but
still securely keyguard-locked. The harness does not inspect, change, or bypass
credentials; the phone must be unlocked normally before the complete physical
campaign can be rerun. This is the remaining VC2-04 acceptance blocker.

No connected Bluetooth endpoint was available, so speaker route selection is
proven but Bluetooth connect/disconnect is N/A for the available matrix and is
not claimed. Real network-delivered FCM transport was also not used by the
device harness: adversarial wakes entered through the production runtime
payload seam, while the data-only sender grammar and FCM separation are covered
by Go/JVM contracts. Android/Play policy declarations for full-screen and
foreground-call use remain a beta/release follow-up.
