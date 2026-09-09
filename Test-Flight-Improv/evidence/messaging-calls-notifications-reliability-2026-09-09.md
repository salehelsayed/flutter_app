# Messaging, calls, notifications reliability — 2026-09-09

Status: local investigation, fixes and verification complete. Remaining device/provider limits are recorded below. This report is the working checklist and verification record; it does not claim complete application reliability.

## Findings and corrections

| Impact / symptom | Cause and correction | Evidence |
| --- | --- | --- |
| Previously queued direct text repeatedly rejected | Build-113 diagnostics added an outer UUID that protected relay custody rejects. The existing working-tree builder fix already protects new sends. `lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart:213` now atomically repairs the known old scalar-text owner and exact pending parent during the three existing load paths. Ciphertext, identity, incarnation, retry and receipt state are preserved. Unknown fields, changed parents, media and fanout authorities are refused. | Four causal failures before repair; real SQL/transaction, rollback, three loaders, stale completion handles, UUID guards and production drain regressions pass. Relay tests accept the corrected five-key envelope and reject outer metadata. No fabricated delivery. |
| Failed messages could stop retrying without custody | `retry_failed_messages_use_case.dart:1065` treated `transport=inbox` as a receipt. Removed that shortcut: the existing immutable-envelope STORE must accept before the row becomes `inboxed`. | Accepted/refused STORE regressions fail before correction and pass afterward; sender remains short of `delivered`. Related cleanup and strict-media retry tests pass. |
| Stored messages/reactions stalled or negatively acknowledged when notification display failed | Listener/reaction handlers awaited optional display retry after durable commit. `chat_message_listener.dart:460` and `handle_incoming_reaction_use_case.dart:474` now observe that retry asynchronously through the existing durable projection owner. Custody staging failures still prevent acknowledgment. | Nine message cases and nine reaction cases reproduce synchronous, asynchronous and pending display failures through production handlers/listeners; direct ingress, durable rows, one affirmative ACK and reaction UI publication pass. Custody-failure preservation also passes. Headless shutdown still separately settles projection retries before disposal. |
| Calls could retain active audio through an OS interruption during startup | `_onInterruption` ignored events while route discovery/engine startup was pending. `call_audio_controller.dart:355,661` retains startup interruption state, pauses media before readiness publication, and uses existing recovery when the matching end arrives. | Four controlled-order controller regressions; two reproduced the old false-ready state. All 41 controller tests pass. Physical/emulator direct RTP journeys passed twice, but this does not physically exercise the interruption race. |
| Push token refresh could leave an old relay mapping | A refresh joining an in-flight registration was discarded. `push_registration_coordinator.dart:31,141` serializes one follow-up using the latest token generation and preserves the account fence. | Fake-clock regression holds the old registration, emits two refreshes and verifies one latest-token registration. All 17 coordinator tests pass. Provider/device token rotation remains unverified. |
| Optional diagnostics delayed launch and bridge setup | Startup awaited metadata/disk/native diagnostic initialization. `production_app_diagnostics.dart:12` and `production_application_bootstrap.dart:5303` start it concurrently. `app_diagnostics.dart:116` preserves an already attached bridge and account privacy gate. | Controlled pending-metadata launch/frame/error regressions fail before correction and pass afterward. Original launch error propagates unchanged; real GoBridge channel test retains the network gate and uploads. |
| Sender/receiver diagnostic traces stopped joining | After the outer-envelope correction, receive diagnostics still read the removed outer UUID. `handle_incoming_chat_message_use_case.dart:153` obtains the encrypted inner trace using the existing single typed decrypt and passes that outcome into the same handler. | Existing correlation regression, repaired for the removed builder argument, first fails with missing correlated events, then passes: one decrypt, durable commit/actual receipt ordering, privacy canaries and persisted restart correlation. |

Paths without a prefix above are under `lib/features/conversation/application`, except the call, push and bootstrap files under their existing feature/app directories. Exact test commands below identify their regression files.

The task also corrects isolated-package Activity launches in the existing Android call, voice, keepalive and notification campaigns/state restore guard. The voice-message campaign also staged a live contact command and then force-stopped its consumer, losing the command and leaving a stale readiness result. Removing its two redundant post-staging restarts gives a red/green host-order sentinel and a passing real two-device journey on the same APK. The keepalive sibling does not contain that ordering defect. Test-only failure reporting adds finite contact-setup phases and bounded call stats/connection predicates using existing result/FLOW channels. It records no content, keys, tokens, SDP, addresses or unrestricted stacks. A TCP subset selector retains all media/control assertions and cannot return a complete campaign PASS.

The final sibling check corrected ten equivalent component strings in nine configurable-package scripts. `run_intro_accept_notification_android.dart:105` also needed exact native-class recognition in its existing timeout handoff: wrong packages/classes, suffixes and injected error text remain rejected, and its single recovery limit is unchanged. The separate production call campaign enforces `com.mknoon.app`, so its valid relative components were preserved. These are test-driver repairs; only the device journeys below receive runtime credit.

## Diagnostic causality and evidence boundaries

Diagnostics **did contribute** to the documented build-113 protected-envelope rejection and to startup waiting. The earlier [inbox delivery investigation](inbox-delivery-build-113-debug-2026-09-09.md) owns the historical device/relay evidence and pre-existing new-send/UI fixes; they are not newly authored or final-state device results here. This task adds queued-text recovery and restores encrypted receive correlation.

The notification display, token-refresh, failed-inbox retry and call-interruption defects predate these diagnostic edits. Throwing/disabled diagnostic and native-spool tests pass; the canonical device call proof runs without the diagnostic persistence/upload collectors. Its remaining media/fixture failures therefore do not implicate those collectors. There is no full device comparison with collection enabled versus disabled.

Limits remain: a fresh diagnostic sink taking longer than the existing two-second initialization bound can lose startup telemetry; startup diagnostic timing begins at observation readiness and excludes earlier launch work. The pending-metadata regression proves launch isolation using a ready collector, not retention through indefinitely blocked fresh storage. Disk retention limits do not prove bounded executor/DispatchQueue backlog during a permanently blocked native sink. Absence of telemetry is not proof of message/call failure. Native `presentation:pending`, push delegation return, relay custody, recipient commit and visible UI are separate evidence stages.

## Baseline, build provenance and scope

- Branch `feat/ipv6-happy-eyeballs`, starting HEAD `d8b919c5b`. Approximately 415 existing dirty/untracked paths were preserved. Starting binary patch, status and hashes are under `/tmp/mknoon-reliability-starting*`; task-only patches are `/tmp/mknoon-{root,calls,messaging}-task.patch`.
- Current production composition is Flutter/Dart → `GoBridgeClient` → native MethodChannel → Go node/relay code. There is no active JavaScript core or bundled JS asset in the current pubspec. Both gomobile binding fingerprint checks match the current source.
- macOS arm64, Xcode 26.6 (17F113), Flutter 3.47.2/Dart 3.13.2 from `.fvm/flutter_sdk`; PATH Flutter 3.41.4 failed the SDK constraint before tests. Go is explicitly pinned to 1.25.0 for native checks. Android JVM tests use Temurin 17.0.18/Robolectric.
- Live pair: USB Pixel 6 `21071FDF600CSC` (Android 17/API 37), available `Codex_API35` emulator `emulator-5556`. The initially available emulator-5554 stopped responding; no AVD data was wiped. All installed test apps use `com.mknoon.sims.reliability`; personal app packages/identities were not used.
- iOS: disposable iPhone 17 Pro simulator `3DD58077-0559-445D-8D35-AE43DF61C43F`, installed iOS 26.5 runtime. Before the user’s later authorization, existing simulator app containers were preserved. The user then explicitly authorized use/reset of available simulators and requested no clones: existing iPhone 17 Pro `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` and iPhone 16e `DBE8C32E-9F19-4593-860A-B41113791D79` were reset for remaining gates. No new simulator was created after that instruction; the earlier task-owned disposable simulator was deleted after its tests. No physical iOS/APNs/audio claim.
- No commit, push, deployment, production service/configuration mutation, encryption/authentication relaxation, public API/schema replacement, new dependency or architecture redesign. Test messaging used generated identities through existing relay configuration; no real-user messages/calls/pushes. The narrow old-envelope repair is the only wire-persistence compatibility exception.

## Verification checklist and results

| Check | Result / interpretation |
| --- | --- |
| Baseline diagnostic/bootstrap/transaction suite | **64 passed** before root edits. Call baseline **756 passed**; notification baseline **94 passed**; messaging sender baseline **192 passed**, with an already stale incoming builder argument causing compilation failure. |
| Curated `1to1` | **3,667 passed, 4 skipped, 1 failed**. Failure was an existing stale source assertion requiring a fabricated inbox route; corrected to preserve the actual route, with production UI tests retained. |
| Full `host-all` | Exit 1. Dart portion: **16,273 passed, 13 existing skips, 5 failed**. Two retry assertions encoded the removed no-STORE shortcut; one valid architecture guard caught this task's feature-helper import into core; two reviewed bootstrap fingerprints detected the intended concurrent initialization. All corrected without manifest exceptions, disabled assertions or changed ownership. Native/script portion: **15 passed, 1 interrupted**; the app-visibility leg was stopped before installation while simulator-data authorization was unclear. Its unchanged exact rerun subsequently **passed**. The original aggregate retains both the failed Dart batch and interrupted command. |
| Final focused rerun after those corrections | **526 passed, 2 existing default-off media skips**; includes all five failing suites, all changed production regressions, architecture guards and final call harness tests. The two skipped strict retry cases separately passed with their existing flag enabled (**2 passed**). |
| Final contact phase-marker / harness tests | **40 passed** across three intro-runner suites; voice host-order test **1 expected red / 4 existing passes**, then **5 passed** after removing the redundant restarts. |
| Notification campaign launcher regression | **1 expected source-contract failure**, then the full support suite **32 passed**; scoped analyzer **no issues**. Actual APK Activity-class mismatch was already reproduced in the call campaign; live notification campaign remains unrun for the configuration reasons below. |
| Sibling launch and intro timeout preservation | **12 expected failures → 12 passes**; final 11-suite run **470 passed**, zero failures/skips. Nine source-contract checks cover component strings; three deterministic tests execute the actual timeout predicate/recovery, including negative cases. |
| Native Go messaging / relay contract | **35** node/bridge tests and **3** relay top-level tests plus subcases passed using ephemeral local peers/miniredis. This exercises native transport/ACK/custody, not full device UI. |
| Native diagnostic Go / Python | Node/bridge and relay diagnostic tests passed. Python **40 passed**. |
| Android native | Notification/diagnostic **46 passed**; native-call **141 passed**, zero failures/skips. Configured Robolectric API 24/26/30/33/34; no unavailable physical API-band requirement. |
| iOS selective XCTest | **255 passed**, zero failures across nine suites, including notification recovery/preview/NSE, diagnostic spools, CallKit/native bridge and VoIP registry. Runner compiled; simulator/native-boundary evidence only. |
| Final iOS NSE native gate | **Passed** on existing iPhone 16e `DBE8C32E-9F19-4593-860A-B41113791D79`: 21 exact XCTests, three expected mutation failures, restored focused green, exact Go roots/race/preservation checks and artifact/privacy checks. Restored Swift SHA256 `893890da8f9ac0e01e34c8146575a473f3afc84f287b23a58011256c9dbc2a42` matches the source before mutation. Evidence `/tmp/plan373-native.E3pI3x`. |
| Final Android headless recovery native gate | **71 methods passed across 9 classes**; production/test Kotlin and merged-manifest compilation passed. Evidence `/tmp/plan374-native.lk2jXd`. |
| Final app-visibility native rerun | **Passed**, exit 0: two exact JVM tests, Android production/test Kotlin compilation, independent Runner and NotificationService simulator builds, privacy-manifest checks and two exact XCTests on existing iPhone 17 Pro `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. Evidence `/tmp/mknoon-reliability-plan371-final`. No clones; parallel simulator testing disabled. |
| Static analysis | Production/support scope: **15 existing warnings**, no other issues, in unchanged listener/retry statements. Sibling launcher scope: **2 existing warnings** in unchanged group-reaction capture statements. Both are `unawaited_return_in_try_block`; no suppression added. Dedicated voice/notification launcher scopes report no issues. |
| Android builds | Isolated standard/main debug APKs passed. Final phase-instrumented main debug build also passed (30.5 s). Production call-enabled release compilation passed (135.8 s), with normal plugin regeneration and no dependency changes; the APK was not installed or distributed. Initial `--no-pub` release attempt failed because Flutter skips platform tooling regeneration with that option, leaving the debug integration plugin in its registrant; retry uses normal regeneration. |
| Graph/diff | Affected-path checks and final incremental refresh passed. Final scope: 47 task-changed paths including the report and two generated graph files. Comparison found zero missing starting files and zero changes outside recorded task paths; dependency lock and restored native mutation source unchanged. `git diff --check` passed. |
| Repository workflow benchmark | **3/7 passed**, exit 1: telemetry parity (26 canonical / 23 parsed), plan→code query ordering, raw browse gap (12 against limit 10), and branch-first query coverage failed. Refinement, measured fallback and full affected-path coverage passed, with zero pending paths. These workflow failures remain recorded; no navigation-compliance or token-savings claim is made. |

The full suite's original failed result remains recorded even after its five suites pass on correction. No clean full-suite result is inferred from a focused rerun. Existing skips include build-flag alternatives and plugin-registered SQLCipher capability requiring its integration target; no tests were newly skipped. One early parallel Flutter invocation raced native-asset signing; rerun passed without a code workaround.

## Device journeys

| Journey | Observed result |
| --- | --- |
| Direct canonical audio, physical Android ↔ emulator | **2 passed / 1 earlier readiness failure** across three actual direct attempts. Passing legs require both endpoints, bidirectional RTP progress, mute/unmute, route/control checks and hangup/cleanup. Signaling uses production owners with test identities/crypto and opaque local rendezvous; this does not prove production account/push signaling, acoustic intelligibility or microphone/speaker audibility. |
| Full direct + TURN/UDP + TURN/TCP campaign | **No complete pass.** Two runs completed direct then failed TURN/UDP negotiation; one stopped at selected-pair readiness. An earlier launcher failure happened before assertions. No complete artifact emitted. |
| TURN/TCP alone | Initial subset did not establish endpoint-to-fixture reachability and created no call. A local tunnel attempt was also refused before any call: both host and device invocation validators exclude loopback TURN addresses. No gate was weakened to admit it; fixture/mappings were removed. A successful subset remains incomplete/BLOCKED for the full campaign. |
| Text after keepalive drop | **3 failed probes before send**: `latch=true connected=true local=false`. A ping-drop latch is independent of connection entries, including circuits. The harness did not establish its stronger disconnected predicate; no `sendChatMessage` call occurred. No delivery claim and no forced state/timeout change. |
| Healthy plain text in both directions | **2 passed** with production generic-intro actions and repository queries on the final main APK: physical → emulator chose inbox; emulator → physical chose direct. Each endpoint has exactly one matching non-hidden row and delivered state. The first case also matches a sender `DELIVERY_RECEIPT_APPLIED` event to its message. Repeated live contact setup succeeds. This verifies persisted state, not chat-widget rendering or read receipts. |
| Offline recipient, inbox, restart | **Passed**: force-stop only the isolated recipient package; require sender `inboxed` while it is stopped; restart recipient; require the exact recipient row and subsequent sender `delivered`, one non-hidden row each. This exercises explicit app reopening and inbox recovery, not background push after Android force-stop. |
| Healthy voice message | **Passed after the harness race fix**, same final APK. Physical recording 35,520 bytes / 2,069 ms; production voice send/direct signaling and encrypted relay media upload; recipient listener persistence, identical downloaded bytes/SHA, native playback start/progress/completion/stop, retained recipient file and sender temporary-file cleanup. No widget/read-receipt or acoustic audibility claim. Earlier attempts failed contact setup or emulator installation before a message was sent. |
| Notifications | Host/native tests verify cold/warm route retention, duplicates, display/current-chat/mute policy, custody/read reconciliation and permission recovery. Real APNs/FCM provider acceptance → device receipt → processing → visible display → tap remains **not run**. |

Campaign failure summaries sometimes report zero assertions when no complete artifact is returned, even after a direct subjourney validated. Counts above describe observed endpoint validators separately and do not turn an aborted campaign into a pass. Device diagnostics were restricted to isolated package PIDs and allowlisted fields; no personal logcat dump or global log clearing.

The unsigned XCTest host logs a fail-closed Flutter startup error because its shared notification App Group container is unavailable (`client is not entitled`). Native XCTest fixtures still pass using isolated containers. These commands therefore do not establish a successful iOS application cold start; a correctly entitled isolated installation must verify that boundary. No fallback to private storage or permission relaxation was added.

## Exact commands

Run from the repository root unless a directory is specified. Logs use `/tmp/mknoon-reliability-*` and feature handoff paths described above; they are local evidence, not published artifacts.

```sh
PATH="$PWD/.fvm/flutter_sdk/bin:$PATH" ./scripts/run_host_test_gates.sh 1to1 --batch-flutter --concurrency 4 --reporter expanded --continue-on-failure
PATH="$PWD/.fvm/flutter_sdk/bin:$PATH" ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --reporter expanded --continue-on-failure

.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency 4 --reporter expanded \
  test/core/diagnostics \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_delivered_truthfulness_test.dart \
  test/features/conversation/application/retry_failed_messages_media_reupload_test.dart \
  test/features/conversation/application/outgoing_transport_settlement_writers_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  test/features/conversation/application/reaction_listener_test.dart \
  test/features/conversation/application/handle_incoming_reaction_use_case_test.dart \
  test/features/push/application/push_registration_coordinator_test.dart \
  test/features/call/application/call_audio_controller_test.dart \
  test/integration/android_app_state_guard_test.dart \
  test/integration/android_foreground_webrtc_audio_campaign_test.dart \
  test/unit/architecture_boundary_checker_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart

.fvm/flutter_sdk/bin/flutter test --no-pub --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true test/features/conversation/application/retry_failed_messages_media_reupload_test.dart --name 'TC-347-03b|TC-358-02c' --reporter expanded
.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency 4 --reporter expanded test/core/debug/intro_e2e_runner_test.dart test/core/debug/intro_e2e_runner_custody_test.dart test/core/debug/intro_e2e_runner_token_proof_test.dart

(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -run '^(TestSendMessage|TestHandleIncomingMessage|TestConfirmDirectMessage|TestDirectConfirmTimeout|TestR3Deadline|TestDispatchInboxAckCustodyContract|TestInboxStoreMediaExpiryCeilingBridgeContract)' -count=1 -v)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^(TestAckCustodyDiagnosticMetadataMustStayInsideCiphertext|TestRelayNotificationClosure_AckCustodyEligibilityIsNarrow|TestRelayNotificationClosure_DirectMutationCustody)$' -count=1 -v)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'AppDiagnostic|CallDiagnostic' -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run 'AppDiagnostic|CallDiagnostic' -count=1)
(cd docker-ws && python3 -m unittest app_diagnostics_test app_diagnostics_monitor_test call_diagnostics_test monitor_call_diagnostics_test)

(cd android && ./gradlew :app:testDebugUnitTest --console=plain --tests com.mknoon.app.MknoonFirebaseMessagingServiceTest --tests com.mknoon.app.MainActivityOnNewIntentTest --tests com.mknoon.app.MainActivityAppVisibilityTest --tests com.mknoon.app.diagnostics.MknoonAppDiagnosticSpoolTest --tests com.mknoon.app.call.MknoonCallDiagnosticSpoolTest)
(cd android && ./gradlew :app:testDebugUnitTest -PenableAndroidNativeCalls=true --tests com.mknoon.app.call.MknoonCallLifecycleControllerTest --tests com.mknoon.app.call.HeadlessCallAdmissionWorkerTest --tests com.mknoon.app.call.MknoonCallNativeBridgeTest --tests com.mknoon.app.call.MknoonCallForegroundServiceTest --tests com.mknoon.app.call.MknoonCallActionReceiverTest --tests com.mknoon.app.call.MknoonCallAndroidRuntimeTest --tests com.mknoon.app.call.PendingNativeCallStoreTest --tests com.mknoon.app.call.MknoonIncomingCallRingerTest --tests com.mknoon.app.call.MknoonOutgoingCallRingbackTest --tests com.mknoon.app.call.CallPayloadParserTest --tests com.mknoon.app.call.MknoonCallNotificationFactoryTest)

xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=iOS Simulator,id=3DD58077-0559-445D-8D35-AE43DF61C43F' -parallel-testing-enabled NO -derivedDataPath /tmp/mknoon-reliability-ios-derived -resultBundlePath /tmp/mknoon-reliability-ios.xcresult -only-testing:RunnerTests/NotificationPreviewResolverTests -only-testing:RunnerTests/NotificationServiceConfigurationTests -only-testing:RunnerTests/IosNotificationRecoveryTests -only-testing:RunnerTests/IosNseMailboxWakeCoordinatorTests -only-testing:RunnerTests/MknoonAppDiagnosticSpoolTests -only-testing:RunnerTests/MknoonCallDiagnosticSpoolTests -only-testing:RunnerTests/MknoonCallKitLifecycleTests -only-testing:RunnerTests/MknoonCallNativeBridgeTests -only-testing:RunnerTests/MknoonVoipPushRegistryTests CODE_SIGNING_ALLOWED=NO test

./scripts/verify_gomobile_bindings.sh android
./scripts/verify_gomobile_bindings.sh ios
bash scripts/test/run_ios_nse_native_373.sh
bash scripts/test/run_android_headless_recovery_native_374.sh
PLAN371_NATIVE_RESULT_DIR=/tmp/mknoon-reliability-plan371-final PATH="$PWD/.fvm/flutter_sdk/bin:$PATH" bash scripts/test/run_app_visibility_native_371.sh
```

Final Android build commands (the release build is never installed on a personal device):

```sh
ORG_GRADLE_PROJECT_androidApplicationId=com.mknoon.sims.reliability SIMS_APP_ID=com.mknoon.sims.reliability .fvm/flutter_sdk/bin/flutter build apk --debug --no-pub --target-platform=android-arm64 --android-project-arg=simsAndroidAbi=arm64-v8a --android-project-arg=disableGoogleServicesForDisposableProof=true --target=lib/main.dart --dart-define=E2E_TEST_MODE=true --dart-define=SIMS_BUILD_PROFILE_ID=android.e2e.main
.fvm/flutter_sdk/bin/flutter build apk --release --target=lib/main.dart --target-platform=android-arm64 --android-project-arg=simsAndroidAbi=arm64-v8a --android-project-arg=enableAndroidNativeCalls=true --dart-define-from-file=tool/build/voice_call_release_defines.json
```

Final main artifact: `/tmp/mknoon-reliability-main-final.apk`, SHA256 `bb9d23d4554b6f41b3982b256c202ee4afc35b30fdca7c5816cef688534f8ace`. Release artifact: `/tmp/mknoon-reliability-release-final.apk`, SHA256 `b7accf7ed691e6d016cee27b719d01996aa9eae40236d2b8230ce16164bd4289`, package `com.mknoon.app`, version 114, min API 24 / target API 36. Flutter compilation targeted arm64; this is not a device or all-ABI release certification. Final call probe artifact: `/tmp/mknoon-reliability-probe-final.apk`, SHA256 `ac34ac0cfed7acf4b6313980d8ac0d3b952a7dc51782efe6ac6e33176398ff1f`. The probe predates only the equivalent private UUID predicate and contact-test phase marker; no call production source changed afterward. The standard/main E2E builds do not enable the production call UI gate; the release build explicitly supplies the existing call definitions and Android native-call flag.

Scoped analysis command (nonzero for the 15 retained warnings):

```sh
.fvm/flutter_sdk/bin/dart analyze lib/app/bootstrap/production_app_diagnostics.dart lib/app/bootstrap/production_application_bootstrap.dart lib/core/diagnostics lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart lib/core/debug/intro_e2e_runner.dart lib/features/call/application/call_audio_controller.dart lib/features/conversation/application/chat_message_listener.dart lib/features/conversation/application/handle_incoming_chat_message_use_case.dart lib/features/conversation/application/handle_incoming_reaction_use_case.dart lib/features/conversation/application/retry_failed_messages_use_case.dart lib/features/push/application/push_registration_coordinator.dart integration_test/scripts/android_foreground_webrtc_audio_campaign.dart integration_test/scripts/android_keepalive_drop_campaign.dart integration_test/scripts/android_voice_message_device_campaign.dart integration_test/support/android_app_state_guard.dart integration_test/support/android_foreground_webrtc_audio_canonical_stack.dart integration_test/support/android_foreground_webrtc_audio_probe.dart
```

Device commands set both package variables because `ANDROID_APP_PACKAGE` takes precedence. Each run uses a separate `SIMS_PROOF_DIRECTORY`. Call runs additionally require the existing private, transient TURN fixture variables; secrets are not recorded here.

```sh
export ANDROID_APP_PACKAGE=com.mknoon.sims.reliability
export SIMS_APP_ID=com.mknoon.sims.reliability
SIMS_ARTIFACT_PROFILE_ID=android.e2e.main .fvm/flutter_sdk/bin/dart run integration_test/scripts/run_1to1_device_real.dart --scenario android.keepalive_drop_skip_direct --device 21071FDF600CSC,emulator-5556 --artifact /tmp/mknoon-reliability-main.apk
SIMS_ARTIFACT_PROFILE_ID=android.e2e.main .fvm/flutter_sdk/bin/dart run integration_test/scripts/run_1to1_device_real.dart --scenario android.voice_message_e2e --device 21071FDF600CSC,emulator-5556 --artifact /tmp/mknoon-reliability-main.apk
SIMS_ARTIFACT_PROFILE_ID=android.e2e.standard .fvm/flutter_sdk/bin/dart run integration_test/scripts/run_1to1_device_real.dart --scenario android.foreground_webrtc_audio --device 21071FDF600CSC,emulator-5556 --artifact /tmp/mknoon-reliability-probe-final.apk
SIMS_FOREGROUND_WEBRTC_RELAY_PROBE=turnTcp SIMS_ARTIFACT_PROFILE_ID=android.e2e.standard .fvm/flutter_sdk/bin/dart run integration_test/scripts/run_1to1_device_real.dart --scenario android.foreground_webrtc_audio --device 21071FDF600CSC,emulator-5556 --artifact /tmp/mknoon-reliability-probe-final.apk
```

Complete voice-message artifact: `/private/tmp/mknoon-voice-message-proof-run4/android.voice_message_e2e-1788958184043455-22302.json`, SHA256 `f044d1fedba1c33ae6d7e83b42740b230d9b081516fe73cf5236ed68fdc24a1c`. Its final command used `SIMS_PROOF_DIRECTORY=/tmp/mknoon-voice-message-proof-run4`, the voice scenario above, and `--artifact /tmp/mknoon-reliability-main-final.apk`. The existing AVD required a cold restart after an offline/package-manager failure; its userdata was preserved, no replacement AVD was created, and both isolated packages were absent after cleanup.

Plain-text command: `ANDROID_APP_PACKAGE=com.mknoon.sims.reliability SIMS_APP_ID=com.mknoon.sims.reliability .fvm/flutter_sdk/bin/dart --packages=.dart_tool/package_config.json /tmp/mknoon-plaintext-probe.dart` — exit 0, all three cases passed. The temporary entrypoint reuses the voice host helpers unchanged except absolute imports, existing generic-intro send/query actions, and `AndroidAppStateGuard`; it pins the same Android pair and final main APK. Source SHA256 `479e73c61b1dd19b4b1d8145ca8c8840f92abb603ebec86d1cac4e2d9e55ea28`; helper source SHA256 `4c2e0540cfa4ede25330595d95ef63fd576b9414c68305e027a092919c27d71e`. Safe proof `/tmp/mknoon-plaintext-proof.json`, SHA256 `1af5832b4c7c8c377e0830218eb05cd2656c489fa56adf81867354f95cf547f9`; receipt cross-check `/tmp/mknoon-plaintext-receipt-proof.json`; log `/tmp/mknoon-plaintext-probe.log`. These store result/state/transport and identity-match booleans, not message content or keys. Both isolated packages were absent after final cleanup. The harness removed staged configs normally; host staging was independently empty, but the supplemental emulator staging-directory census timed out and remains inconclusive. The observed 28.6/36.5-second healthy-case windows include readiness and emulator host I/O; they are not pure message latency measurements.

Additional final commands:

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub test/integration/android_voice_message_device_campaign_test.dart --reporter expanded
.fvm/flutter_sdk/bin/dart analyze integration_test/scripts/android_voice_message_device_campaign.dart test/integration/android_voice_message_device_campaign_test.dart
.fvm/flutter_sdk/bin/flutter test --no-pub test/integration/android_notification_payload_campaign_support_test.dart --name 'isolated package launch uses the fully qualified native activity' --reporter expanded
.fvm/flutter_sdk/bin/flutter test --no-pub test/integration/android_notification_payload_campaign_support_test.dart --reporter expanded
.fvm/flutter_sdk/bin/dart analyze integration_test/scripts/notification_android_payload_campaign.dart test/integration/android_notification_payload_campaign_support_test.dart

.fvm/flutter_sdk/bin/flutter test --no-pub test/integration/android_app_state_guard_test.dart --name 'isolated package launch contract' --reporter expanded
.fvm/flutter_sdk/bin/flutter test --no-pub \
  test/integration/android_app_state_guard_test.dart \
  test/core/debug/intro_e2e_runner_test.dart \
  test/integration/android_connectivity_restore_campaign_test.dart \
  test/integration/android_push_relay_registration_contract_test.dart \
  test/integration/android_background_crypto_preflight_contract_test.dart \
  test/integration/group_reaction_notification_device_criteria_test.dart \
  test/integration/android_wake_token_directionality_campaign_test.dart \
  test/integration/direct_text_public_relay_contract_test.dart \
  test/integration/reaction_notification_proof_support_test.dart \
  test/features/conversation/integration/android_direct_media_blob_custody_campaign_test.dart \
  test/integration/android_app_package_test.dart --reporter expanded

.fvm/flutter_sdk/bin/dart analyze \
  integration_test/scripts/android_wake_token_directionality_campaign.dart \
  integration_test/scripts/capture_android_push_relay_registration.dart \
  integration_test/scripts/android_direct_media_blob_custody_device_action.dart \
  integration_test/scripts/run_intro_accept_notification_android.dart \
  integration_test/scripts/run_connectivity_restore_sims.dart \
  integration_test/scripts/run_connectivity_restore_media_outbox_sims.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/scripts/capture_1to1_reaction_head_provenance.dart \
  integration_test/scripts/capture_android_background_crypto_preflight.dart \
  test/integration/android_app_state_guard_test.dart

./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py session-stats --session current
python3 graphify-arch/tdd_context.py workflow-benchmark --session current --closure
python3 codex-memory/memory.py stats --session current
```

## Remaining validation

1. Plain-text bidirectional delivery and offline/inbox/restart recovery, plus voice transport/storage/native playback, are verified on the Android pair. Widget rendering, read receipts, local-network selection and message-during-call remain unverified. For the failed keepalive-specific probe, record connection kind/count and terminal warm state, then establish its actual disconnected predicate; a liveness latch alone is insufficient. This probe failure is separate from the passing offline recovery case.
2. Resolve the intermittent selected-pair sample and fixture reachability/UDP negotiation before claiming repeated direct or relay call reliability. Repeat answer/reject/cancel/timeout, reconnect while ending, interruption/permission denial and message-during-call journeys through production account signaling. Physical acoustic audio and iOS/Android parity remain untested.
3. Live push has a confirmed local configuration/isolation gap: the existing `android_payload_campaign` mandates a physical sender and emulator receiver, reinstalling the same APK/package on both. Available Firebase client configuration registers only `com.mknoon.app`; using it would replace the personal physical app. No isolated Firebase package/profile was found in the inspected build inputs. Neither `SIMS_PROVIDER_FCM_CREDENTIAL_PATH` nor `FIREBASE_SERVICE_ACCOUNT` is configured, and this resolver does not autodiscover a path; this does not prove credentials do not exist elsewhere. The default relay key exists, but no staging relay addresses are configured. No provider access was attempted. With an authorized isolated Firebase package, matching APK, configured credential path and staging relay, run the existing campaign below. Separately verify provider acceptance, native receipt, committed row, presentation and exact cold/warm tap; same-chat suppression, another screen, mute, ordinary background, held-registration token refresh and duplicate/early callbacks. iOS additionally needs a correctly entitled isolated installation. Background delivery is not equivalent to Android force-stop or iOS swipe-away: Firebase requires reopening after these states; Apple background pushes can be throttled/coalesced and are not guaranteed. [Firebase receive messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [Apple background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).
4. No historical malformed media/fanout row was found. Shared old envelope construction supports conditional exposure, not proof that such a row exists. Before expanding the scalar repair, reproduce with a legacy-authored isolated database and prove exact blob/manifest/expiry or full sibling-generation authority, stale-handle fencing and recipient media decrypt/download. Those rows are preserved rather than guessed valid.
5. Soak slow/failing native diagnostic sinks and verify fresh-start telemetry separately from functional startup. An unavailable hardware/OS-band leg is **N/A (target unavailable by project policy)**; available-target credentials/fixture or readiness failures above remain explicit unresolved checks, not passes.

Live push command template — **not run**, prerequisites above are missing:

```sh
ANDROID_APP_PACKAGE='<isolated-package>' SIMS_APP_ID='<same-isolated-package>' \
SIMS_PROVIDER_FCM_CREDENTIAL_PATH='<credential-file>' MKNOON_RELAY_ADDRESSES='<staging-multiaddrs>' \
.fvm/flutter_sdk/bin/dart run integration_test/scripts/run_notification_tap_device_real.dart \
  --scenario android_payload_campaign --physical 21071FDF600CSC --emulator emulator-5556 \
  --prebuilt-apk '<production-fcm-apk>' --relay-target '<staging-ssh-target>' \
  --relay-key '<key-file>' --artifact-dir '<proof-directory>'
```
