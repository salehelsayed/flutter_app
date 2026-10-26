# Call privacy, process recovery and cleanup: MCP execution packet

Prepared 2026-10-26 against `8c2e4024e39caab00c4528354abbb61996f208c9` for
VC-026, VC-019, VC-025 and VC-027. This is preparation for flutter_app, the
device owner. No call or device proof was executed by Astra. The existing host
and native evidence below has its original scope; this packet adds no app hook,
device harness or boolean-only verdict adapter. The priority Python receipt
checker does not implement these four journeys.

## Execution boundary and existing baseline

Use `docs/testing/TESTING.md` device setup/recovery guidance and
`tool/testing/selection.json` before execution. Only the execution owner resolves
available targets, pins their IDs and acquires ownership. Default shared proof
uses an available USB Android plus Android emulator. An actual iOS lock/lifecycle
claim needs a separate available iOS target. Unavailable hardware is N/A by
project policy; missing setup or observations on an available target are
incomplete. Do not clear identities, modify a personal passcode or reset another
owner's app, audio, network, automation session or fixture.

All actual calls start at or after **08:30 Europe/Berlin**, recorded with a
timezone-aware timestamp. Keep exact source/configuration, artifact digest,
package, private target-role bindings, call identity, attempt and observation
times together. A source/debug fixture does not attest a signed store candidate.
One test process and one automation owner per target; do not start heavy checks
above host one-minute load 80. Preserve the first failure and the original call
deadlines. Review owned cleanup before a new attempt.

Remote test traffic uses Hetzner; an **owned local disposable relay/coturn is
allowed**. Production AWS is reserved for owner pre-publish store-build lanes.
Do not change/deploy either remote relay. The existing audio adapter requires
its local fixture; do not bypass that guard or replace its binding with Hetzner.

Reuse the registered `device-audio` check and its existing adapter:

```sh
# Execution owner only, after setup/selection review and the time gate.
# Set this from the live matrix, physical Android first, emulator second.
export RELIABILITY_MULTI_DEVICE_IDS="$ANDROID_PHYSICAL,$ANDROID_EMULATOR"
dart run integration_test/scripts/run_production_audio_call_sims.dart \
  --mode major --scenario android.production_1to1_audio_call
```

The adapter prepares and executes the attested disposable package and local
fixture. Preserve its typed report and use the existing
`integration_test/support/android_production_audio_call_evidence.dart` validator.
Its campaign owns instrumentation/UI; end the execution owner's Appium MCP
session before launch, then hand ownership back only after campaign cleanup.
The existing `ui_driver_reason` in the selection manifest explains the native
RTP/ownership observations which UI alone cannot establish. Use Appium MCP for
the additional UI cases below; do not build a parallel generic UI driver.

For additional MCP cases needing a live local backend, the adapter already has
`PLAN399_MANUAL_HOLD_FILE`, `PLAN399_MANUAL_HOLD_MINUTES` (1–180) and
`PLAN399_MANUAL_ONLY=1`. In manual-only mode it prepares builds and holds the
fixture; it does **not** execute the device campaign or establish ready accounts.
The execution owner must install/verify that exact prepared disposable artifact
and provision the owned pair through the existing state-preserving setup and
ordinary app UI before taking MCP observations. Wait for
`PLAN399_MANUAL_HOLD_READY`, retain the outer process/fixture identity, and delete
only that attempt's hold file when finished. The bound also releases the hold;
normal adapter teardown follows. A stopped/expired fixture cannot support a new
case. Hold readiness, build success and adapter exit zero in manual-only mode
are setup evidence only. Keep TURN material inside the existing fixture owner.

The normal campaign proves native Answer, bidirectional RTP, one mute/unmute
control path and normal terminal cleanup. Its separate **host-only known-Opus
Pion oracle is not app-microphone content evidence**. Control booleans, RTP
counters, a microphone icon or silent/DTX packets cannot close VC-019. Nor does
normal hangup prove hard process loss, every terminal reason or locked privacy.

Keep raw screenshots, audio/cues, native observations and any private identity
bindings in the owned attempt directory. Send only paths and redacted facts to
Kayan. Each result states the target/artifact/case actually observed, remaining
assertions, and PASS/FAIL/incomplete/N/A scope. No manual checkbox can stand in
for missing native capture or received-content observations.

## VC-026: hard process loss and a usable next call

Existing causal controls:

- `test/features/call/integration/process_loss_recovery_decisions_test.dart:229`
  explicitly supplies native observations to a fresh Dart owner; the real SQL
  reopen and history assertions do not kill a process. Its survivor case at
  line 336 preserves the original 15-second **reconnect episode** deadline.
- `android_call_detached_audio_cleanup_test.dart`,
  `call_coordinator_shutdown_terminate_test.dart` and
  `android_call_lifecycle_adapter_test.dart` under `test/features/call/` cover
  their mocked native/reducer boundaries. Native pending-store/lifecycle tests
  are `android/app/src/test/kotlin/com/mknoon/app/AndroidCallWakeBridgeTest.kt`,
  `ios/RunnerTests/PendingNativeCallStoreTests.swift` and
  `ios/RunnerTests/MknoonCallKitLifecycleTests.swift`.
- `docs/testing/TESTING.md` records prior physical-iOS ringing/active kills and
  next-call recovery under
  `build/wt-iosrecovery/.codex-test-logs/iosrecovery/SUMMARY.md`. Retain that
  tested source/target scope; it is not a current Android or signed-candidate
  result and does not prove every native resource observation below.

MCP/native sequence, using fresh owned calls for each case:

1. Cover caller loss and callee loss while genuinely ringing, then caller loss
   and callee loss during an answered call with a positive actual-media control.
   Record both canonical sessions and owned native call/capture state before
   the cut. No graceful hangup before the cut.
2. Use the existing platform-owned process-loss operation and record its exact
   kind, process absence, cut time and changed process incarnation on relaunch.
   Recents removal/backgrounding is not process death; Android force-stop has
   different wake behavior and must be named explicitly. Never assume an active
   background call should terminate just because its task was swiped away.
3. Inspect the survivor's actual no-answer or media-loss/reconnect progression,
   native capture/call/card release and persisted terminal outcome against the
   already scheduled deadline. The 15 seconds starts at the actual reconnect
   episode, not unconditionally at the kill. Do not replace expiry with a long
   arbitrary wait or inject a fake native terminal to obtain a pass.
4. Relaunch the killed app without clearing data. Inspect old native ownership
   and its durable journal: resources must release or reconcile according to
   the platform contract, with no old re-ring, duplicate terminal history or
   permanent calling-unavailable state. On iOS, retained native-call ownership
   can require exact reconciliation; process absence alone is insufficient.
5. Place and answer a fresh authenticated call. Prove actual media, then normal
   cleanup on both endpoints. Keep old/new call identities distinct and show
   that late old terminal work does not retire the new call. If a native late
   callback cannot be induced with an existing operation, retain host fencing
   proof separately rather than fabricate a callback observation.

Report missing native observability as incomplete for that assertion. Reuse
historical recovery evidence where applicable; do not relabel supplied host
replay, a graceful shutdown or an answered screen as an actual kill/media pass.

## VC-019: microphone content before consent, during mute and after hangup

Reuse
`test/features/call/integration/microphone_command_privacy_test.dart:431` and
`:480`: both directions exercise real coordinator/audio/engine-wrapper commands
and SQL, but native capture, permission, routes and signaling are controlled
fakes. `call_audio_controller_test.dart` and
`blocked_call_media_release_test.dart` under `test/features/call/application/`
preserve mute/release races. These are command/ownership controls.

Before native execution, bind either an existing **received content-sensitive
audio oracle**, or a **signed audible observation plus native capture evidence**
to the actual pair, call, artifact and observation intervals. The latter records
the observer's attestation, private cue/recording paths and exact native capture
observations; a UI mute state alone is insufficient. Use fresh distinct test
cues, retain unmuted positive controls in each direction and distinguish test
audio from ambient/other-app sound. This packet authorizes no new app audio hook.

1. Before answer, present a distinct cue at each endpoint's microphone. Prove
   absence of captured/transmitted pre-consent content through the chosen
   native/content observations. After answering the same call, establish both
   positive directions and check that pre-answer content was not buffered and
   delivered late. An unanswered-call screen is not this proof.
2. Mute A while B remains unmuted. Start A's fresh private cue only after the
   observed mute boundary; prove it is absent at B while B-to-A positive audio
   still works. Unmute A and prove audio returns. Repeat with B muted, then both
   muted, keeping each sender/receiver interval and positive control separate.
   Silence/DTX RTP can continue during a correct mute. An OS microphone
   indicator may remain while a capture owner is retained; neither signal alone
   proves content privacy.
3. While muted, background/resume and exercise an available supported audio
   interruption, then recheck the mute state **and received-content absence**.
   Unmute and re-mute through real controls and verify final privacy. Keep the
   precise pending-native-command race covered by the existing host controls;
   rapid tapping alone does not prove that race was reached.
4. Hang up, then present a new cue and prove old-call content absence plus native
   capture release. A late old-call unmute cannot reacquire capture. Establish
   a fresh call's positive audio separately so a broken receiver cannot make
   all negative observations appear to pass.

If the approved content/observer-plus-native method is unavailable, record
VC-019 native content proof as incomplete. Preserve useful campaign/host results
without converting RTP progress, the separate Pion fixture oracle or UI controls
into a microphone-privacy PASS.

## VC-025: actual locked-call privacy through real unlock

Reuse `test/features/call/presentation/locked_call_projection_test.dart`,
`test/features/call/infrastructure/android_call_lifecycle_adapter_test.dart` and
`android/app/src/test/kotlin/com/mknoon/app/call/MknoonIncomingCallPresentationTest.kt`.
Rendering/JVM tests do not establish real keyguard, WindowManager or touch
exposure. The Android cover's terminal handling intentionally remains opaque
while locked until background/actual unlock
(`MknoonIncomingCallPresentation.kt:165`); do not demand an early removal which
would expose the restored Flutter surface. VC-005 deferred callback admission
is a separate proof.

1. On a secured available target with an already authorized unlock flow, open
   owned test history/contact content behind the app, then actually lock the
   OS. Do not create/change/export a passcode. Record genuine lock state.
2. Deliver a real incoming call and answer through its actual system surface.
   Observe the permitted contact identity and call controls. Until real unlock,
   no conversation history, contact list or private app navigation may be
   exposed visually, through touch or through the accessibility tree.
3. Use Appium MCP to try Back/predictive Back where available, app/call return,
   Home/Recents and the owned call notification. Inspect transitions as well as
   final screens; no private frame or tappable route may appear behind the
   call cover. Available warm/cold app entry states are separate cases. Do not
   require unsupported gestures or an absent OS version.
4. End the call while still locked and inspect the surface retiring to the OS
   without revealing the private app. Perform the real authorized unlock, then
   show that normal private navigation works. Restore only owned test state.

Keep Android and iOS observations separate. A simulator without a genuine
secured keyguard cannot certify a physical locked-device boundary. An available
target's missing unlock/observation access is a setup gap, not a hardware N/A.

## VC-027: each reachable terminal path releases only its call's resources

Reuse `test/features/call/application/call_cleanup_coordinator_test.dart:23`
(bounded hung step), `:74` (concurrent/duplicate cleanup) and `:127` (critical
failure retry/ACK). Also reuse `headless_terminal_call_record_test.dart`,
`blocked_call_media_release_test.dart`,
`test/features/call/integration/call_mic_blocked_end_reason_test.dart`,
`call_readiness_exception_test.dart` in that integration directory, and
`android/app/src/test/kotlin/com/mknoon/app/call/MknoonTelecomCallbackReleaseTest.kt`.
These preserve causal failure/fencing assertions; fake releases are not native
capture observations. Native baseline normal cleanup is validated at
`integration_test/support/android_production_audio_call_evidence.dart:458-485`.

Use one fresh case per real trigger; reverse initiator roles where relevant:

| Trigger | Native observation required |
| --- | --- |
| Local and remote hangup after answer | Positive real media first; both old-call capture/native owners and active card retire. |
| Callee decline / caller cancel while ringing | Actual OS/app action; capture never acquired before consent; pending surfaces retire. |
| No answer / expired incoming descriptor | Preserve the actual admission/ring deadline and cause; inspect terminal cleanup/history without synthesizing an expired row. |
| Busy | Reach the real busy branch with an independently owned available third actor; preserve the already active call's capture and session. Unavailable extra topology is N/A for that leg. |
| Media/setup failure or reconnect expiry | Use an existing owned-emulator or local-fixture fault, retain the failed first attempt and original deadline; no remote service changes. |
| Permission denied / unsupported / policy rejected | Exercise only actual reachable production refusal paths; never fabricate support/policy/history fields. Retain host causal coverage for other branches and name the native scope still untested. |
| App shutdown / hard process loss | Keep graceful shutdown distinct from the four VC-026 kill cases and the platform's actual reconciliation contract. |

For every case, retain the actual canonical terminal reason and existing history
readout, with one logical terminal row and correct old/new call association.
The closed wire grammar is `lib/features/call/domain/call_end_reason.dart`; do
not invent database columns, terminal names or a UI status ladder. Signaling
failure and media failure need their actual causal trigger, not a renamed normal
hangup. A missing fault setup remains incomplete.

Inspect owned native mic/capture, peer connection/audio route ownership, native
call and active notification after termination, then place a fresh call with a
positive media control and clean it up. Release assertions are scoped to the
old call: a newer or unrelated audio owner must remain usable. A history row,
global microphone icon or dismissed Flutter screen alone proves neither exact
release nor successor safety. Preserve failed-release/retry and stale-callback
host evidence when those races cannot be reached natively with existing controls.

Report the terminal rows actually executed and each residual gap. A passing
normal campaign closes its observed normal cleanup only; it cannot certify
all terminal reasons, VC-019 content privacy or a signed distribution artifact.
