# 243 - Native Received-Video Picture In Picture

Status: evidence-gated
Type: New Feature
Spec: free-text intent — continue an eligible received video in native picture-in-picture while keeping chat transport and protected-media policy isolated
Classification: evidence-gated
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | architecture graph query/explain, shared full-screen viewer, `video_player` package/platform sources, Android MainActivity/manifest/SDK bounds, iOS AppDelegate/Info.plist/deployment target, native channel tests, official Android/Apple PiP docs | Android can PiP an Activity from API 26, but Mknoon's min SDK is 24 and its one `FlutterActivity` owns the whole app. Apple PiP needs an `AVPlayerLayer` or sample-buffer source and background playback support, while HEAD's Flutter `video_player` controller exposes neither native source. A two-platform ownership spike is required before an honest implementation contract exists. | Resolve D-243-01..05 with throwaway native probes; then select one ownership seam and author the causal RED suite. |

## Problem And Evidence

- Behavior to improve: while an ordinary received video is playing, an eligible user should be able to continue it in the system PiP window and return to the same attachment/time without exposing chat UI or weakening protected-media rules.
- Impact: leaving the app or navigating away always removes the current full-screen playback experience; plan 230 can pause/resume locally but cannot present a native floating player.
- Confirmed current mechanism: `_FullScreenVideoPage` owns a `VideoPlayerController.file` inside Flutter at `lib/shared/widgets/media/full_screen_image_viewer.dart:133`; no native player identity or PiP gateway is exposed.
- Confirmed package boundary: the resolved `video_player` stack exposes speed/seek but no Android/iOS native PiP control; web-only options mention PiP. Reaching into plugin-private player objects would be version-fragile.
- Confirmed Android boundary: `MainActivity` extends the single app-wide `FlutterActivity`; `AndroidManifest.xml` has no `android:supportsPictureInPicture`, and the app's min SDK is 24 while Android PiP begins at API 26.
- Confirmed iOS boundary: deployment target is iOS 13, `Info.plist` background modes contain only fetch and remote notification, and `AppDelegate.swift` has no AVKit/AVFoundation player ownership.
- Official platform constraint: Android PiP pins the supporting Activity and requires irrelevant UI to be hidden; see `https://developer.android.com/develop/ui/views/picture-in-picture`. Apple `AVPictureInPictureController` needs a supported/possible content source such as `AVPlayerLayer` and background media configuration; see `https://developer.apple.com/documentation/AVKit/AVPictureInPictureController`.
- Existing coverage: viewer widget tests preserve image/GIF/video page selection; native channel tests demonstrate repository conventions. No proof can fail for a real PiP window, control handoff, return routing, audio focus, or unsupported-device fallback.
- Missing coverage: selected native playback ownership, one-controller position handoff, Android API/Activity behavior, iOS AVPlayer source/scene restoration, capability gating, protected-media suppression, and two-platform device proof.
- Refuted findings: a Dart-only overlay is not system PiP and must not be labeled as such. Calling `enterPictureInPictureMode` on the current Flutter activity without proving video-only rendering risks shrinking the whole chat UI.
- Unresolved findings (blocking): **D-243-01** reuse/extend `video_player` versus own a dedicated native player; **D-243-02** Android app-wide Activity versus dedicated PiP-capable Activity/route; **D-243-03** iOS `AVPlayerLayer` ownership and Flutter texture handoff; **D-243-04** explicit-only versus automatic background entry and background-audio capability; **D-243-05** supported OS/device matrix and whether Android-only release is acceptable if iOS proof fails.
- Affected files cannot be finalized until the spike. Bounded candidates are the plan-230 playback adapter, a new `PictureInPictureGateway`, Android manifest/MainActivity or a dedicated Activity, iOS AppDelegate/native player component and capabilities, native unit/static pins, and one classified device proof.

## Scope Contract And Guard

In scope after D-243-01..05 are accepted:
- Add `PictureInPictureCapability`, `PictureInPictureRequest`, `PictureInPictureState`, and `PictureInPictureGateway` with unsupported/unavailable/starting/active/restoring/stopped/failed outcomes.
- Use attachment ID plus app-owned resolved video path and a clamped position. Do not pass a message payload, encryption key/nonce, caption, sender, peer/group ID, or transport object to native code.
- Allow PiP only for completed, ordinary, local videos whose lane capability explicitly enables it; private/view-once/expired/quarantined/missing media always fail closed.
- Ensure a single playback owner at a time. Handoff must pause Flutter, start native at the bounded position, update one position source, then restore plan 230's exact item/route or settle stopped without duplicate audio.
- Implement platform availability checks: Android API/feature/Activity state and iOS supported/possible/player-ready state. Unsupported devices hide the control and continue normal viewer playback.
- Preserve audio focus/session and route restoration across start, cancel, system close, app return, interruption, process recreation where the selected platform supports it, and playback completion.

Must preserve:
- Plan 230 page/lifecycle rules and DB-v96 local position semantics -> TC-243-04 and plan 230 sentinels.
- Plan 234/238/242 protected-media restrictions -> TC-243-02; no PiP frame may outlive its authorized viewer state.
- Notifications, inbound share, migration keep-alive, and Flutter engine setup in MainActivity/AppDelegate -> platform pin tests and existing native sentinels.
- Discussion/announcement/direct delivery authorization and encryption remain byte-for-byte outside the PiP seam -> TC-243-06.

Hard `Do not`:
- Do not enter PiP with the whole conversation, caption, sender identity, action menu, or composer visible.
- Do not fork/decrypt/copy media into an arbitrary external path, persist plaintext outside app ownership, or send any bytes over a new endpoint.
- Do not import/call P2P, Bridge, relay, inbox, group publish, announcement send, or `go-mknoon` code.
- Do not enable PiP for view-once/private/protected content merely because a local file exists.
- Do not patch private internals of a resolved Flutter plugin without an explicit maintained fork/upgrade contract and tests.
- Do not add iOS background-audio capability or Android automatic-entry policy until D-243-04 has a recorded product/privacy decision.

Deferred / accepted difference:
- Host playback controls and resume remain plan 230.
- Save/share/forward/download/delete/library behavior remains plans 227–242.
- If one platform cannot meet the ownership/privacy proof, its control remains unavailable; a one-platform release requires an explicit accepted product difference, not silent parity claims.

Dependencies:
- Plan 230 supplies typed viewer identity, capability rendering, playback adapter, and local position callbacks.
- Plans 234, 238, and 242 supply lane-specific protected-media eligibility.
- An accepted D-243 decision artifact containing a minimal two-platform probe result is required before implementation status can become execution-ready.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-243-00 | A bounded probe demonstrates the selected Android and iOS playback ownership can show only video, retain one position, and restore Flutter; unsupported alternatives and plugin-fork cost are recorded. | `Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md` plus disposable Android/iOS probe commands recorded there | evidence spike / one physical Android and iOS device + local MP4 | HEAD evidence RED: no native player/PiP seam -> accepted artifact answers D-243-01..05 with observed start/return traces on each claimed platform | N/A; this is the prerequisite evidence gate, not product code | manual evidence; required before TC-243-01 production/test authoring |
| TC-243-01 | Host gateway maps support/start/stop/restore/error channel events exactly once and rejects stale session IDs. | `test/core/media/picture_in_picture_gateway_test.dart::typed PiP session maps native lifecycle exactly once and ignores stale events` | host unit / mocked method+event channels | after evidence gate, HEAD compile RED: gateway absent -> exact state sequence and terminal result pass | accept an event from the prior attachment/session or complete twice -> TC-243-01 red | `flutter test test/core/media/picture_in_picture_gateway_test.dart`; AUTO (`core-host-all`) |
| TC-243-02 | Eligibility fails closed for private/view-once/expired/quarantined/missing/non-video media and invokes native zero times. | `test/shared/widgets/media/media_picture_in_picture_policy_test.dart::only ordinary completed local video can request PiP` | host unit / cross-lane capability matrix + throwing gateway | HEAD compile RED -> exact allowed row; every protected/ineligible row makes zero call | gate only on file extension or local-path presence -> TC-243-02 red | `flutter test test/shared/widgets/media/media_picture_in_picture_policy_test.dart`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-243-03 | Android claimed matrix enters video-only PiP, supports system close/return, records the accepted process-recreation outcome, hides unsupported API 24/25, and preserves existing MainActivity intent/channel behavior. | `integration_test/received_video_picture_in_picture_proof_test.dart::Android video-only PiP lifecycle` plus `test/core/media/android_picture_in_picture_native_contract_test.dart` | Android device proof / API 26+ physical device and unsupported-capability fake/unit | HEAD device RED: manifest/native handler absent -> observed PiP contains video only and returns exact item/time; the D-243 artifact's process-recreation outcome is observed; API<26 path hidden | remove API/feature check, shrink entire Flutter UI, contradict the accepted recreation outcome, or omit restore event -> proof/pin red | `flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$ANDROID_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=android` plus `flutter test test/core/media/android_picture_in_picture_native_contract_test.dart`; exact `ignored` discovery rule |
| TC-243-04 | iOS claimed matrix starts from a ready supported source, maintains one strong playback/PiP owner, handles delegate failure/stop/restore once, records the accepted process-recreation outcome, and returns exact item/time. | `integration_test/received_video_picture_in_picture_proof_test.dart::iOS video-only PiP lifecycle` plus `test/core/media/ios_picture_in_picture_native_contract_test.dart` | iOS device proof / supported physical iPhone/iPad + unsupported fake | HEAD device RED: no AVKit source/capability -> video-only system window and exact restoration observed; the D-243 artifact's process-recreation outcome is observed; unsupported/not-possible hidden | release controller/source early, background-pause both owners, contradict the accepted recreation outcome, or skip restore completion -> proof/pin red | `flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$IOS_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=ios` plus `flutter test test/core/media/ios_picture_in_picture_native_contract_test.dart`; exact `ignored` discovery rule |
| TC-243-05 | Handoff pauses/disposes exactly one Flutter owner, starts native at clamped position, checkpoints via plan 228, and restores or completes without duplicate audio. | `test/shared/widgets/media/media_picture_in_picture_handoff_test.dart::PiP handoff has one playback owner and one durable position` | widget/application host / fake playback adapter + PiP gateway + fake repository/clock | HEAD compile RED -> ownership/event counts exact through success, cancellation, failure, completion, and return | leave Flutter playing, use path identity, or write unclamped/stale position -> TC-243-05 red | `flutter test test/shared/widgets/media/media_picture_in_picture_handoff_test.dart`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-243-06 | PiP modules remain transport-free and native requests/events contain only session/attachment/path/playback fields approved above. | `test/core/media/picture_in_picture_transport_boundary_test.dart::PiP source and channel schema contain no messaging or secret fields` | shell-contract + host unit / source/schema scan | HEAD compile RED: modules absent -> forbidden imports/field names are absent across Dart/Kotlin/Swift | pass serialized message/media map or import Bridge/P2P -> TC-243-06 red | `flutter test test/core/media/picture_in_picture_transport_boundary_test.dart`; AUTO (`core-host-all`) |
| TC-243-07 | Existing viewer, Android notification-intent, disk-space channel, migration keepalive wiring, and iOS notification delegate pins remain green. | `test/shared/widgets/media/full_screen_image_viewer_test.dart`; `test/core/notifications/main_activity_onnewintent_pin_test.dart::MainActivity.kt overrides onNewIntent and calls setIntent(intent)`; `test/core/device/disk_space_channel_test.dart::speaks the real mknoon/disk_space method channel contract`; `test/core/lifecycle/main_keepalive_wiring_test.dart::TC-183-W4: teardown disposes the keepalive (no Timer leak)`; `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart::AppDelegate pins iOS notification tap diagnostic forwarding` | `GREEN sentinel` / exact existing widget, channel, lifecycle, and native source-pin fixtures | GREEN on HEAD -> all remain GREEN after the selected native seam lands | overwrite channel registration, remove `onNewIntent`, leak keepalive teardown, or replace notification delegate without chaining -> sentinel red | `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart test/core/notifications/main_activity_onnewintent_pin_test.dart test/core/device/disk_space_channel_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`; AUTO (`host-all` for shared viewer, `core-host-all` for core pins) |

### Test Notes

- TC-243-00 must use throwaway probe code or a branch artifact and record exact OS/device/plugin versions; it is not accepted merely because a third-party package advertises PiP.
- Native device proof records only state names, attachment-id prefix, duration/position, and platform version. It must not log paths, captions, sender/group identity, keys, nonces, or video bytes.
- The device proof must exercise explicit entry, system close, return-to-app restoration, interruption, completion, and protected-item absence. Automatic entry is tested only if D-243-04 explicitly accepts it.

## Implementation Steps

1. Run TC-243-00 on one supported Android and iOS physical device; record D-243-01..05 and reject any seam that cannot show video-only content with one playback owner.
2. Change status to execution-ready only after the accepted artifact names exact Dart/native ownership, affected files, supported matrix, and background capability policy.
3. Add TC-243-01/02/05/06 before product code; confirm causal compile/behavior REDs while plan-230 sentinels stay GREEN.
4. Implement the minimal typed gateway and selected native seams, platform capabilities, session fencing, and restoration. Stop-if transport or protected-media code must be weakened.
5. Add the exact device proof classification rule, run Android+iOS closures for every claimed platform, native sentinels, host gates, analyzer, and hygiene.

## Risks And Blind Spots

- Whole chat leaks into Android PiP -> TC-243-00/03 require observed video-only output before selection and closure.
- iOS player/source ownership may fight Flutter `video_player` -> TC-243-00/04/05 prove one owner and exact handoff.
- Protected media could survive outside its viewer -> TC-243-02 and lane-private plans fail closed before native start and stop active sessions on lifecycle expiry.
- Lifecycle / derived-state durability: TC-243-05 reconstructs from persisted attachment ID/position; no path-only restoration.
- Sibling-surface consistency: one shared capability is consumed by all three lanes, with private policy supplied by 234/238/242.
- Destructive-action side effects: none; source video and media rows survive every PiP result.
- Invariant re-verification under new transitions: start/restore re-load current attachment/protection state and reject stale session events in TC-243-01/02/05.

## Acceptance Gates

```bash
# Evidence gate; exact probe commands/results are authored in the artifact after the seam candidates compile
test -s Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md

git status --short

# First causal RED after TC-243-00 acceptance; expect non-zero because the gateway does not exist
flutter test test/core/media/picture_in_picture_gateway_test.dart --plain-name 'typed PiP session maps native lifecycle exactly once and ignores stale events'

# Focused host GREEN
flutter test test/core/media/picture_in_picture_gateway_test.dart
flutter test test/core/media/picture_in_picture_transport_boundary_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_policy_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_handoff_test.dart
flutter test test/core/media/android_picture_in_picture_native_contract_test.dart
flutter test test/core/media/ios_picture_in_picture_native_contract_test.dart

# Explicit discovery classification; expect one ignored/manual native proof record, never unclassified
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^ignored[[:space:]]+ignored[[:space:]]+integration_test/received_video_picture_in_picture_proof_test\.dart[[:space:]]+'

# Repeat with one supported physical id for each claimed platform
flutter devices --machine
test -n "$ANDROID_DEVICE_ID"
test -n "$IOS_DEVICE_ID"
flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$ANDROID_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=android
flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$IOS_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=ios

flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart test/core/device/disk_space_channel_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh host-all --list
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: one supported physical Android device (API 26+, plus fake/unit unsupported rows for API 24/25) and one PiP-capable physical iOS device for each platform claimed by D-243-05.
- Boundary being proven: real system PiP window, video-only presentation, platform capability, audio/playback ownership, system close, app restoration, interruption, and exact position continuity.
- Live availability check: `flutter devices --machine`; export distinct `$ANDROID_DEVICE_ID` and `$IOS_DEVICE_ID`. An absent platform leaves TC-243-00/03/04 environment-blocked and prevents parity claims.
- Required setup: an ordinary completed local MP4 plus a protected/private negative fixture; no relay/network is required.
- Closure role: required for every platform advertised as PiP-capable; host mocks cannot close native UI ownership.
- Registration: add an exact `integration_test/received_video_picture_in_picture_proof_test.dart` `classify_path` case to `scripts/check_reliability_simulation_discovery.sh`, category/kind `ignored`, note `manual Android/iOS received-video PiP proof outside default reliability-sim`; no transport family registration.
- Discovery command: the `--records-tsv | rg ...` command above must select exactly one record and no unclassified record.
- Closure commands: the two platform-specific commands above using their explicit platform selectors, reduced only if D-243-05 explicitly records a one-platform accepted difference.
- Relay profile: N/A; any relay requirement is scope drift.

## Execution Interpretation And Done Criteria

- Expected evidence RED: HEAD cannot provide an iOS AVKit source or proven Android video-only Activity ownership.
- Expected causal RED after evidence: TC-243-01 compile-fails because `PictureInPictureGateway` is absent.
- Green sentinel: current viewer and native notification/channel pins remain GREEN.
- Pre-existing dirty tree / known failure: record at execution start and do not absorb unrelated changes.
- Evidence blocker: unanswered D-243-01..05 keeps this plan evidence-gated; package marketing or host mocks do not resolve it.
- Environment blocker: missing physical devices blocks only the matching evidence/device row, but also blocks advertising that platform.
- Scope drift: any transport, wire, relay, Go, protected-media relaxation, or arbitrary external plaintext persistence blocks the plan.

- [ ] TC-243-00 decision artifact answers D-243-01..05 with observed two-platform evidence or an explicit accepted difference.
- [ ] Every post-decision behavior has a named causal test/proof and representative mutation.
- [ ] Exactly one playback owner, stable attachment identity, bounded position, and protected-media suppression pass.
- [ ] Device proof is explicitly classified and passes on every claimed platform.
- [ ] Existing native lifecycle/channel and shared viewer sentinels pass.
- [ ] Analyzer/diff hygiene and scope guard pass.

## Handoff

- First action: complete `Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md`; production/test implementation is blocked before that evidence.
- First causal RED after acceptance: `flutter test test/core/media/picture_in_picture_gateway_test.dart --plain-name 'typed PiP session maps native lifecycle exactly once and ignores stale events'`.
- Preservation command: `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart && ./scripts/run_host_test_gates.sh core-host-all`.
- Manual registration: exact proof path classified as ignored/manual native proof; no reliability transport-family edit.
- Migration: none; consumes local playback position from DB v96/plan 228.
- Boundary closure: physical Android/iOS device for every claimed platform; no relay.
- Unresolved evidence: native playback ownership, Activity/source design, background policy, and parity matrix D-243-01..05.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | evidence gate | - | - | HEAD has no native PiP ownership | D-243-01..05 unresolved | run bounded platform probes |
