# Android cold-start notification latency — passive review

The WiFi direct-text case arrived promptly at the Pixel FCM receiver, then spent about **5.1 seconds starting the headless Flutter runtime** and **6.8 seconds in the background handler and publication path**. A second process-absent WiFi group-text case independently takes 5.3 + 6.6 seconds. Both post audible OS notifications before receiver reopen. This establishes cold-client latency in installed **debug build114**, not release performance and not a relay delay.

## Direct-text measured timeline

Case marker LAT-WIFI-DIRECT-260907-1124, message prefix a8c5a11c. Times below are raw Pixel UTC on 2026-09-07; logcat displays UTC+2. Within-device intervals need no clock correction. For comparison with the host, the measured Pixel offset is +0.755957 seconds.

| Stage | Raw UTC | Elapsed after FCM receiver |
|---|---|---|
| Android starts process30659 for app FCM receiver broadcast | 11:24:41.320 | -0.524s |
| FlutterFire broadcast receiver receives message | 11:24:41.844 | 0s |
| Background service queues message because isolate is not running | 11:24:41.857 | 0.013s |
| FlutterEngine creation begins | 11:24:41.979 | 0.135s |
| Dart VM service becomes available | 11:24:42.752 | 0.908s |
| FlutterFire background service reports started | 11:24:46.581 | 4.737s |
| First Dart handler FLOW event | 11:24:46.979045 | 5.135s |
| First identity/contact DB load starts | 11:24:48.660961 | 6.817s |
| First identity/contact/history lookup batch ends | 11:24:49.119413 | 7.275s |
| Second identity/contact/history lookup batch ends | 11:24:49.806823 | 7.963s |
| Background crypto plugin success | 11:24:50.245723 | 8.402s |
| Exact canonical SQL effect authority unavailable; alert fallback retained | 11:24:52.624182 | 10.780s |
| OS RingtonePlayer begins processing notification sound | 11:24:53.553 | 11.709s |
| Background notification shown event, silent=false | 11:24:53.770350 | 11.926s |

The relay acceptance at host11:24:40.493278 precedes corrected FCM receipt11:24:41.088043 by about0.595seconds. The later approximately12seconds is inside the cold client path. The SHOWN event is not the first OS entry: RingtonePlayer begins about217ms earlier, and local post-show bookkeeping occurs between them. No matched app ANR, fatal exception, or storage-deadline failure appears in this bounded window.

The logs distinguish runtime bootstrap from Dart work, but do not time every storage/crypto subphase. The interval before first DB logging includes handler initialization/staging and is not pure SQL duration. The two identity/contact reads are deliberate eligibility and preview policy rechecks in current source, not proof of an accidental duplicate query. Crypto has a success timestamp but no exact start timestamp in this case; no pure cryptography duration is claimed.

## Group cold control

LAT-WIFI-GROUP-260907-1128, message prefix7c010230, starts a new process31169. FCM receiver11:27:18.205; background handler11:27:23.532112; decrypt success11:27:26.520365; missing exact SQL effect authority11:27:29.080295; OS sound processing11:27:30.031; SHOWN11:27:30.101046. FCM-to-handler is5.327seconds and handler-to-SHOWN6.569seconds, total11.896seconds. It reproduces the cold startup shape across direct and group text on the same debug APK.

## Source interpretation and persistence boundary

`MknoonFirebaseMessagingReceiver.kt` delegates ordinary rich payloads to FlutterFire; the native app-owned fixed-wake recovery store is a separate exact payload path in `MknoonFirebaseMessagingService.kt`. This direct text carries rich encrypted data fields and follows the delegated path. Therefore there is no measured app-owned native fixed-wake persistence step to insert into this timeline.

The installed dependency is firebase_messaging15.2.10. Its receiver persists `RemoteMessage` in its notification store only when an actual notification payload is present; for background data messages it parcels the message into the background service. While the isolate is not ready, the service adds the intent to its in-memory queue. The app's `firebaseMessagingBackgroundHandler` then stages the encrypted envelope before eligibility, preview/decrypt and publication (`background_message_handler.dart:914`). `FilePushEnvelopeStagingStore.stage` writes/flushes a temporary file and renames it. There is no successful-stage timestamp in this trace, so its individual runtime duration is not claimed. The relay's independent ACK-or-expiry custody remains the upstream durable owner; this audit does not establish loss during the startup window.

At `background_message_handler.dart:1337`, a missing canonical SQL display-outbox authority deliberately keeps the typed alert fallback. A cold new push need not already have a foreground canonical SQL row. The logged `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` reason here is **exact_sql_authority_unavailable**, not a storage deadline failure or an instruction to wait for reopening. The subsequent actual OS alert verifies that fallback.

## Deadlines and build limitations

Build provenance `../android-reaction-layout-final-provenance.json` identifies app-debug.apk, versionCode114, SHA256f80e83093fb5e711a48fd919834b903162a366def4fbe0f786c7f5f9aceebcec. Raw JDWP/Dart VM service events independently confirm a debug runtime. Root verified the exact build command in `../android-reaction-layout-final-build.log`: its only Dart define source is `--dart-define-from-file=tool/build/voice_call_release_defines.json`, which contains no E2E or TEST keys. Therefore E2E_TEST_MODE defaults to false in this APK; it has no runtime E2E mode.

The normal **8-second aggregate storage deadline and 2-second ordinary phase deadline apply to this build114**, as they do to release/profile and ordinary debug. The separately defined20-second/5-second E2E-debug allowance is not enabled here. The clock starts **inside the Dart handler after initial Firebase initialization**, so the5.1-second native/engine startup lies outside this budget. Do not describe FCM-to-OS latency as globally bounded by8seconds. The direct handler-to-SHOWN6.791seconds fits the normal8-second aggregate, and no timeout is observed; exact per-phase headroom cannot be inferred from this trace. The display-eligibility path separately reserves2seconds for its downstream tail.

Firebase's current Flutter guidance says background work should finish promptly and that tasks over30seconds may cause the OS to terminate the process. This is a warning, not guaranteed execution time: https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages . The observed approximately12-second cold path does not cross that warning threshold, but cannot establish reliable margins on slower devices or under heavier contention. Source comments reference prior profile-AOT timing, which was not independently rerun here; current debug measurements cannot substitute for a release/profile cold-start comparison.

No source changes, builds or device actions were performed in this audit. A justified next performance check is one equivalent process-absent release/profile case with phase timing, if root chooses to pursue a release latency claim; changing generic performance behavior from these debug timings alone is not warranted.

Evidence: `pixel-logcat.log`; `android-wifi-direct-cold-start-events.log`; `android-wifi-group-cold-start-events.log`; `android-cold-start-timing.json`; operator per-case result/process-absence artifacts. Graph context2ee7e7e8db8f4fb4 / cd4edd4b06aa0152 covers the handler branch. Native graph lookup missed the app receiver; measured native fallback464c56c303cb4abb / e1fe8fc8da278a28 was followed by exact filename/source verification and pinned vendor implementation.
