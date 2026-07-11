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
| 2026-07-10 | Planner refresh | revised plan 228 playback-state contract; plan 230 resume adapter; PiP request/handoff/completion rows; `MediaAttachment.durationMs` | PiP consumes local video-only state: non-video writes reject; unknown-duration videos keep non-negative positions; a later known duration re-clamps; completion resets to zero. Native handoff must not invent a stricter stale-duration contract. | add explicit known/unknown/later-duration/completion tests while keeping the native evidence gate unchanged |

## Problem And Evidence

- Behavior to improve: while an ordinary received video is playing, an eligible user should be able to continue it in the system PiP window and return to the same attachment/time without exposing chat UI or weakening protected-media rules.
- Impact: leaving the app or navigating away always removes the current full-screen playback experience; plan 230 can pause/resume locally but cannot present a native floating player.
- Confirmed current mechanism: `_FullScreenVideoPage` owns a `VideoPlayerController.file` inside Flutter at `lib/shared/widgets/media/full_screen_image_viewer.dart:133`; no native player identity or PiP gateway is exposed.
- Confirmed package boundary: the resolved `video_player` stack exposes speed/seek but no Android/iOS native PiP control; web-only options mention PiP. Reaching into plugin-private player objects would be version-fragile.
- Confirmed Android boundary: `MainActivity` extends the single app-wide `FlutterActivity`; `AndroidManifest.xml` has no `android:supportsPictureInPicture`, and the app's min SDK is 24 while Android PiP begins at API 26.
- Confirmed iOS boundary: deployment target is iOS 13, `Info.plist` background modes contain only fetch and remote notification, and `AppDelegate.swift` has no AVKit/AVFoundation player ownership.
- Confirmed persistence dependency: revised plan 228 TC-228-10 defines video-only playback writes, non-negative storage when duration is unknown, re-clamp when later metadata supplies duration, known-duration clamping, non-video rejection, and completion reset to zero. PiP must consume that contract rather than treating missing duration as zero or unlimited forever.
- Official platform constraint: Android PiP pins the supporting Activity and requires irrelevant UI to be hidden; see `https://developer.android.com/develop/ui/views/picture-in-picture`. Apple `AVPictureInPictureController` needs a supported/possible content source such as `AVPlayerLayer` and background media configuration; see `https://developer.apple.com/documentation/AVKit/AVPictureInPictureController`.
- Existing coverage: viewer widget tests preserve image/GIF/video page selection; native channel tests demonstrate repository conventions. No proof can fail for a real PiP window, control handoff, return routing, audio focus, or unsupported-device fallback.
- Missing coverage: selected native playback ownership, one-controller position handoff, Android API/Activity behavior, iOS AVPlayer source/scene restoration, capability gating, protected-media suppression, and two-platform device proof.
- Refuted findings: a Dart-only overlay is not system PiP and must not be labeled as such. Calling `enterPictureInPictureMode` on the current Flutter activity without proving video-only rendering risks shrinking the whole chat UI.
- Unresolved findings (blocking): **D-243-01** reuse/extend `video_player` versus own a dedicated native player; **D-243-02** Android app-wide Activity versus dedicated PiP-capable Activity/route; **D-243-03** iOS `AVPlayerLayer` ownership and Flutter texture handoff; **D-243-04** explicit-only versus automatic background entry and background-audio capability; **D-243-05** supported OS/device matrix and whether Android-only release is acceptable if iOS proof fails.
- Affected files cannot be finalized until the spike. Bounded candidates are the plan-230 playback adapter, a new `PictureInPictureGateway`, Android manifest/MainActivity or a dedicated Activity, iOS AppDelegate/native player component and capabilities, native unit/static pins, and one classified device proof.

## Scope Contract And Guard

In scope after D-243-01..05 are accepted:
- Add `PictureInPictureCapability`, `PictureInPictureRequest`, `PictureInPictureState`, and `PictureInPictureGateway` with unsupported/unavailable/starting/active/restoring/stopped/failed outcomes.
- Use attachment ID plus app-owned resolved video path, optional known duration, and a normalized start position. Known duration clamps to `0..duration`; unknown duration clamps only below zero, then native-ready/later metadata re-clamps against the discovered duration through plan 228. Do not pass a message payload, encryption key/nonce, caption, sender, peer/group ID, owner lane, or transport object to native code.
- Allow PiP only for completed, ordinary, local videos whose lane capability explicitly enables it; private/view-once/expired/quarantined/missing media always fail closed.
- Ensure a single playback owner at a time. Handoff must pause Flutter, start native at the bounded position, update one position source, then restore plan 230's exact item/route or settle stopped without duplicate audio.
- Persist PiP checkpoints only for video attachments through plan 228. A non-video checkpoint is an error/no native start; unknown-duration checkpoints remain non-negative; duration discovery revalidates stored/current position; playback completion writes zero before restoration/terminal settlement.
- Implement platform availability checks: Android API/feature/Activity state and iOS supported/possible/player-ready state. Unsupported devices hide the control and continue normal viewer playback.
- Preserve audio focus/session and route restoration across start, cancel, system close, app return, interruption, process recreation where the selected platform supports it, and playback completion.

Must preserve:
- Plan 230 page/lifecycle ownership and plan-228 DB-v96 video-only/unknown-duration/later-clamp/completion semantics -> TC-243-05/08 plus plan-228 TC-228-10.
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
- Plan 228 supplies DB v96 local playback state and the exact video-only, known/unknown duration, later re-clamp and completion-reset repository contract.
- Plan 230 supplies typed viewer identity, capability rendering, playback adapter, and local position callbacks.
- Plans 234, 238, and 242 supply lane-specific protected-media eligibility.
- An accepted D-243 decision artifact containing a minimal two-platform probe result is required before implementation status can become execution-ready.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-243-00 | A bounded probe demonstrates the selected Android and iOS playback ownership can show only video, retain one position, and restore Flutter; unsupported alternatives and plugin-fork cost are recorded. | `Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md` plus disposable Android/iOS probe commands recorded there | evidence spike / available supported Android/iOS targets + local MP4; unavailable platform leg N/A | HEAD evidence RED: no native player/PiP seam -> accepted artifact answers D-243-01..05 with observed start/return traces on each available claimed platform | N/A; this is the prerequisite evidence gate, not product code | manual evidence; required before TC-243-01 production/test authoring |
| TC-243-01 | Host gateway maps support/start/stop/restore/error channel events exactly once and rejects stale session IDs. | `test/core/media/picture_in_picture_gateway_test.dart::typed PiP session maps native lifecycle exactly once and ignores stale events` | host unit / mocked method+event channels | after evidence gate, HEAD compile RED: gateway absent -> exact state sequence and terminal result pass | accept an event from the prior attachment/session or complete twice -> TC-243-01 red | exact `flutter test test/core/media/picture_in_picture_gateway_test.dart`; AUTO discovery is supplemental, not the closure gate |
| TC-243-02 | Eligibility fails closed for private/view-once/expired/quarantined/missing/non-video media; non-video rows invoke neither native nor playback-state write. | `test/shared/widgets/media/media_picture_in_picture_policy_test.dart::only ordinary completed local video can request PiP or checkpoint` | host unit / cross-lane image/video capability matrix + throwing gateway/repository | HEAD compile RED -> exact video row allowed; every protected/ineligible/non-video row makes zero native/write call | gate only on file extension/local path or allow image playback state -> TC-243-02 red | exact direct command; `test/shared/widgets/**` is not covered by feature/core globs |
| TC-243-03 | Android claimed matrix enters video-only PiP, supports system close/return, records the accepted process-recreation outcome, hides unsupported API 24/25, and preserves existing MainActivity intent/channel behavior. | `integration_test/received_video_picture_in_picture_proof_test.dart::Android video-only PiP lifecycle` plus `test/core/media/android_picture_in_picture_native_contract_test.dart` | Android device proof / available supported API 26+ target and unsupported-capability fake/unit | HEAD device RED: manifest/native handler absent -> observed PiP contains video only and returns exact item/time; the D-243 artifact's process-recreation outcome is observed; API<26 path hidden | remove API/feature check, shrink entire Flutter UI, contradict the accepted recreation outcome, or omit restore event -> proof/pin red | `flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$ANDROID_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=android` when available, plus `flutter test test/core/media/android_picture_in_picture_native_contract_test.dart`; exact `ignored` discovery rule |
| TC-243-04 | iOS claimed matrix starts from a ready supported source, maintains one strong playback/PiP owner, handles delegate failure/stop/restore once, records the accepted process-recreation outcome, and returns exact item/time. | `integration_test/received_video_picture_in_picture_proof_test.dart::iOS video-only PiP lifecycle` plus `test/core/media/ios_picture_in_picture_native_contract_test.dart` | iOS device proof / available supported iPhone or simulator + unsupported fake | HEAD device RED: no AVKit source/capability -> video-only system window and exact restoration observed; the D-243 artifact's process-recreation outcome is observed; unsupported/not-possible hidden | release controller/source early, background-pause both owners, contradict the accepted recreation outcome, or skip restore completion -> proof/pin red | `flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$IOS_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=ios` when available, plus `flutter test test/core/media/ios_picture_in_picture_native_contract_test.dart`; exact `ignored` discovery rule |
| TC-243-05 | Handoff pauses/disposes exactly one Flutter owner, starts native at the plan-228-normalized position, checkpoints one source, and restores or completes without duplicate audio. | `test/shared/widgets/media/media_picture_in_picture_handoff_test.dart::PiP handoff has one playback owner and one normalized durable position` | widget/application host / fake playback adapter + PiP gateway + repository recorder/clock | HEAD compile RED -> ownership/event counts exact through known/unknown duration start, success, cancellation, failure, completion and return | leave Flutter playing, use path identity, pre-clamp unknown duration to zero, or write from both owners -> TC-243-05 red | exact direct command; `test/shared/widgets/**` is not covered by feature/core globs |
| TC-243-06 | PiP modules remain transport-free and native requests/events contain only session/attachment/path/playback fields approved above. | `test/core/media/picture_in_picture_transport_boundary_test.dart::PiP source and channel schema contain no messaging or secret fields` | shell-contract + host unit / source/schema scan | HEAD compile RED: modules absent -> forbidden imports/field names are absent across Dart/Kotlin/Swift | pass serialized message/media map or import Bridge/P2P -> TC-243-06 red | exact `flutter test test/core/media/picture_in_picture_transport_boundary_test.dart` |
| TC-243-07 | Existing viewer, Android notification-intent, disk-space channel, migration keepalive wiring, and iOS notification delegate pins remain green. | `test/shared/widgets/media/full_screen_image_viewer_test.dart`; `test/core/notifications/main_activity_onnewintent_pin_test.dart::MainActivity.kt overrides onNewIntent and calls setIntent(intent)`; `test/core/device/disk_space_channel_test.dart::speaks the real mknoon/disk_space method channel contract`; `test/core/lifecycle/main_keepalive_wiring_test.dart::TC-183-W4: teardown disposes the keepalive (no Timer leak)`; `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart::AppDelegate pins iOS notification tap diagnostic forwarding` | `GREEN sentinel` / exact existing widget, channel, lifecycle, and native source-pin fixtures | GREEN on HEAD -> all remain GREEN after the selected native seam lands | overwrite channel registration, remove `onNewIntent`, leak keepalive teardown, or replace notification delegate without chaining -> sentinel red | exact combined `flutter test`; shared viewer requires direct invocation because feature/core globs do not cover `test/shared/**` |
| TC-243-08 | PiP persistence consumes plan 228 exactly: video-only writes; unknown duration stores non-negative position; later duration clamps stored/current state; completion resets zero and survives reopen. | `test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart::PiP persistence handles video only unknown later clamp and completion` plus `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::video resume handles unknown duration revalidation and completion` | widget/application + repository sentinel / PiP adapter over production repository with temp DB, image and known/unknown video rows, fresh reopen | HEAD PiP compile RED; after plan 228 the repository sentinel is GREEN -> PiP unknown position survives, later duration clamps both handoff/repository state, completion stores zero, image write rejects | treat null duration as zero/infinite, skip later clamp, retain completed duration, or write image position -> TC-243-08 red | exact two direct commands; shared resume coverage is not delegated to a broad glob |

### Test Notes

- TC-243-00 must use throwaway probe code or a branch artifact and record exact OS/device/plugin versions; it is not accepted merely because a third-party package advertises PiP.
- Native device proof records only state names, attachment-id prefix, duration/position, and platform version. It must not log paths, captions, sender/group identity, keys, nonces, or video bytes.
- The device proof must exercise explicit entry, system close, return-to-app restoration, interruption, completion, and protected-item absence. Automatic entry is tested only if D-243-04 explicitly accepts it.
- TC-243-05/08 use both a video with known duration and one whose duration is initially null then supplied later. “Unknown” means lower-bound normalization only; the later native/player duration must trigger plan-228 re-clamp. Completion must persist zero before a fresh viewer/PiP reopen.

## Implementation Steps

1. Resolve the live matrix and run TC-243-00 on each available supported Android/iOS target; record unavailable legs N/A, answer D-243-01..05 with the available evidence plus native contracts, and reject any seam that cannot show video-only content with one playback owner.
2. Change status to execution-ready only after the accepted artifact names exact Dart/native ownership, affected files, supported matrix, and background capability policy.
3. Add TC-243-01/02/05/06/08 before product code; confirm causal compile/behavior REDs while plan-228/230 sentinels stay GREEN.
4. Implement the minimal typed gateway and selected native seams, platform capabilities, session fencing, restoration, and plan-228 checkpoint adapter. Unknown duration stays non-negative until native readiness/later metadata clamps it; completion writes zero. Stop-if transport/protected-media or video-only persistence rules must be weakened.
5. Add the exact device proof classification rule, run available Android/iOS closures for every claimed platform, exact native/shared sentinels, curated `1to1` and `groups` lane gates, analyzer, and hygiene.

## Risks And Blind Spots

- Whole chat leaks into Android PiP -> TC-243-00/03 require observed video-only output before selection and closure.
- iOS player/source ownership may fight Flutter `video_player` -> TC-243-00/04/05 prove one owner and exact handoff.
- Protected media could survive outside its viewer -> TC-243-02 and lane-private plans fail closed before native start and stop active sessions on lifecycle expiry.
- Lifecycle / derived-state durability: TC-243-05/08 reconstruct from attachment ID/position, later duration and completion state; no path-only restoration.
- Sibling-surface consistency: one shared capability is consumed by all three lanes, with private policy supplied by 234/238/242.
- Destructive-action side effects: none; source video and media rows survive every PiP result.
- Invariant re-verification under new transitions: start/restore re-load current attachment/protection/type/duration state; TC-243-01/02/05/08 reject stale sessions, non-video writes and stale upper bounds.

## Gate Cadence

- Individual plan closure runs TC-243 focused native/shared tests directly, exact existing native/viewer sentinels, the curated `1to1` and `groups` lane gates, and proof on every applicable target in the live available-device matrix.
- The shared `test/shared/**` suites are not covered by feature/core globs and therefore remain explicit commands; do not substitute `host-all`, `feature-host-all`, or `core-host-all` at Plan 243 closure.
- Run full `host-all` once after the 243-245 extension/reporting wave is complete, and once again at final media-rollout closure.

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
flutter test test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart
flutter test test/core/media/android_picture_in_picture_native_contract_test.dart
flutter test test/core/media/ios_picture_in_picture_native_contract_test.dart

# Plan-228 playback contract preservation; expect video-only/unknown/later-clamp/completion reset GREEN
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'video resume handles unknown duration revalidation and completion'

# Explicit discovery classification; checker exits 0 and the exact path has one ignored record, never unclassified
set -e
records_file="$(mktemp)"
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$records_file"
test "$(awk -F '\t' '$1 == "ignored" && $2 == "ignored" && $3 == "integration_test/received_video_picture_in_picture_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 1
test "$(awk -F '\t' '$1 == "unclassified" && $3 == "integration_test/received_video_picture_in_picture_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 0
rm -f "$records_file"

# Resolve the live matrix, then repeat on each available supported target for every claimed platform.
# An unavailable platform leg is recorded N/A by project policy; native/host contracts still cover it.
flutter devices --machine
adb devices
xcrun simctl list devices available
flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$ANDROID_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=android
flutter test integration_test/received_video_picture_in_picture_proof_test.dart -d "$IOS_DEVICE_ID" --dart-define=PIP_PROOF_PLATFORM=ios

flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart test/core/device/disk_space_channel_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: each supported Android device/emulator and iPhone/iOS simulator available at execution time for the platforms claimed by D-243-05; unsupported/unavailable version branches remain host/native-unit covered.
- Boundary being proven: real system PiP window, video-only presentation, platform capability, audio/playback ownership, system close, app restoration, interruption, and exact position continuity.
- Live availability check: `flutter devices --machine`, `adb devices`, and `xcrun simctl list devices available`; export IDs only for matching available targets. An absent platform leg is `N/A (target unavailable by project policy)`, not a blocker.
- Required setup: an ordinary completed local MP4 plus a protected/private negative fixture; no relay/network is required.
- Closure role: required for every platform advertised as PiP-capable; host mocks cannot close native UI ownership.
- Registration: add an exact `integration_test/received_video_picture_in_picture_proof_test.dart` `classify_path` case to `scripts/check_reliability_simulation_discovery.sh`, category/kind `ignored`, note `manual Android/iOS received-video PiP proof outside default reliability-sim`; no transport family registration.
- Discovery command: the literal two-count block above must prove exactly one ignored record and zero unclassified records for the path.
- Closure commands: the two platform-specific commands above using their explicit platform selectors, reduced only if D-243-05 explicitly records a one-platform accepted difference.
- Relay profile: N/A; any relay requirement is scope drift.

## Execution Interpretation And Done Criteria

- Expected evidence RED: HEAD cannot provide an iOS AVKit source or proven Android video-only Activity ownership.
- Expected causal RED after evidence: TC-243-01 compile-fails because `PictureInPictureGateway` is absent.
- Green sentinel: current viewer and native notification/channel pins remain GREEN.
- Pre-existing dirty tree / known failure: record at execution start and do not absorb unrelated changes.
- Evidence blocker: unanswered D-243-01..05 keeps this plan evidence-gated; package marketing or host mocks do not resolve it.
- Environment blocker: none for an unavailable device version/platform leg; record it N/A and retain compile-time/native-unit coverage. Failures on an available selected target remain real blockers.
- Scope drift: any transport, wire, relay, Go, protected-media relaxation, or arbitrary external plaintext persistence blocks the plan.

- [ ] TC-243-00 decision artifact answers D-243-01..05 with observed two-platform evidence or an explicit accepted difference.
- [ ] Every post-decision behavior has a named causal test/proof and representative mutation.
- [ ] Exactly one playback owner, stable attachment identity, video-only writes, known/unknown/later-clamped positions, completion reset, and protected-media suppression pass.
- [ ] Device proof is explicitly classified and passes on every claimed platform.
- [ ] Existing native lifecycle/channel and shared viewer sentinels pass.
- [ ] Analyzer/diff hygiene and scope guard pass.

## Handoff

- First action: complete `Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md`; production/test implementation is blocked before that evidence.
- First causal RED after acceptance: `flutter test test/core/media/picture_in_picture_gateway_test.dart --plain-name 'typed PiP session maps native lifecycle exactly once and ignores stale events'`.
- Preservation command: `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart test/core/notifications/main_activity_onnewintent_pin_test.dart test/core/device/disk_space_channel_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`.
- Manual registration: exact proof path classified as ignored/manual native proof; no reliability transport-family edit.
- Migration: none; consumes DB v96 plan-228 video-only playback state, including unknown-duration storage, later re-clamp and completion reset.
- Boundary closure: every applicable Android/iOS target available at execution time for the claimed platforms; unavailable legs are recorded N/A; no relay.
- Unresolved evidence: native playback ownership, Activity/source design, background policy, and parity matrix D-243-01..05.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | evidence gate | - | - | HEAD has no native PiP ownership | D-243-01..05 unresolved | run bounded platform probes |
