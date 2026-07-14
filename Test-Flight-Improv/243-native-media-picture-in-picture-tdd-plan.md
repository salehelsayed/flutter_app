# 243 - Native Received-Video Picture In Picture

Status: accepted/closed — Android Path 3 proven; segmented Wave-3 and final host coverage accepted
Type: New Feature
Spec: free-text intent — continue an eligible received video in native picture-in-picture while keeping chat transport and protected-media policy isolated
Classification: Android production authorized; iOS/other platforms fail-closed
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | architecture graph query/explain, shared full-screen viewer, `video_player` package/platform sources, Android MainActivity/manifest/SDK bounds, iOS AppDelegate/Info.plist/deployment target, native channel tests, official Android/Apple PiP docs | Android can PiP an Activity from API 26, but Mknoon's min SDK is 24 and its one `FlutterActivity` owns the whole app. Apple PiP needs an `AVPlayerLayer` or sample-buffer source and background playback support, while HEAD's Flutter `video_player` controller exposes neither native source. A two-platform ownership spike is required before an honest implementation contract exists. | Resolve D-243-01..05 with throwaway native probes; then select one ownership seam and author the causal RED suite. |
| 2026-07-10 | Planner refresh | revised plan 228 playback-state contract; plan 230 resume adapter; PiP request/handoff/completion rows; `MediaAttachment.durationMs` | PiP consumes local video-only state: non-video writes reject; unknown-duration videos keep non-negative positions; a later known duration re-clamps; completion resets to zero. Native handoff must not invent a stricter stale-duration contract. | add explicit known/unknown/later-duration/completion tests while keeping the native evidence gate unchanged |
| 2026-07-13 | Product decision | `243-proof-artifacts/pip-ownership-decision.md`, retained Android/iOS probe history, rejected v3-v6 wrapper lineage | Canonical Path 3 selected: Android API 26+ PiP may proceed to production implementation/closure; iOS and every other platform expose no PiP control, report unsupported, and perform no native handoff. Physical-iPhone close is historical and no longer a gate. | Execute the causal RED/GREEN plan for Android plus the exact iOS fail-closed negative contract. |
| 2026-07-14 | Execution reconciliation | production-source Dart/Android seams, typed repository revocation sources, paged libraries, six-scenario Pixel-6 proof, focused/curated/analyzer/Graphify evidence | Plan 243 implementation and its available-device proof are closed. The proof used disposable debug ID `com.mknoon.app.pipproof`, not a production-ID or release-signed APK. iOS remains host/static fail-closed and its device leg is N/A. | Completed: Wave-3 and final-rollout coverage are accepted under the user's explicit segmented-resume semantics, then closure documents were frozen in one-way dependency order. |

## Problem And Evidence

- Behavior to improve: while an ordinary received video is playing, an eligible user should be able to continue it in the system PiP window and return to the same attachment/time without exposing chat UI or weakening protected-media rules.
- Historical preimplementation impact: leaving the app or navigating away removed the current full-screen playback experience; plan 230 could pause/resume locally but could not present a native floating player.
- Historical planning baseline: `_FullScreenVideoPage` owned a `VideoPlayerController.file` inside Flutter and exposed no native player identity or PiP gateway. The implemented typed viewer now performs the fenced owner transfer described below.
- Confirmed package boundary: the resolved `video_player` stack exposes speed/seek but no Android/iOS native PiP control; web-only options mention PiP. Reaching into plugin-private player objects would be version-fragile.
- Historical preimplementation Android baseline: `MainActivity` extended the single app-wide `FlutterActivity`, `AndroidManifest.xml` had no `android:supportsPictureInPicture`, and the app's min SDK was 24 while Android PiP begins at API 26. The implemented current boundary instead uses the dedicated non-exported PiP Activity recorded below.
- Confirmed iOS boundary: deployment target is iOS 13, `Info.plist` background modes contain only fetch and remote notification, and `AppDelegate.swift` has no AVKit/AVFoundation player ownership.
- Confirmed persistence dependency: revised plan 228 TC-228-10 defines video-only playback writes, non-negative storage when duration is unknown, re-clamp when later metadata supplies duration, known-duration clamping, non-video rejection, and completion reset to zero. PiP must consume that contract rather than treating missing duration as zero or unlimited forever.
- Official platform constraint: Android PiP pins the supporting Activity and requires irrelevant UI to be hidden; see `https://developer.android.com/develop/ui/views/picture-in-picture`. Apple `AVPictureInPictureController` needs a supported/possible content source such as `AVPlayerLayer` and background media configuration; see `https://developer.apple.com/documentation/AVKit/AVPictureInPictureController`.
- Historical preimplementation coverage baseline: viewer widget tests preserved image/GIF/video page selection and native channel tests demonstrated repository conventions, but no proof then exercised a real PiP window, control handoff, return routing, audio focus, or unsupported-device fallback.
- Historical preimplementation gap inventory, now closed by the evidence below: Android native playback ownership, one-controller position handoff, Android API/Activity behavior, platform capability gating, protected-media suppression, the iOS/other-platform negative contract, and Android production-device proof.
- Refuted findings: a Dart-only overlay is not system PiP and must not be labeled as such. Calling `enterPictureInPictureMode` on the current Flutter activity without proving video-only rendering risks shrinking the whole chat UI.
- Resolved findings: **D-243-01** uses a dedicated app-owned Android player; **D-243-02** uses a dedicated non-exported PiP Activity rather than MainActivity; **D-243-03** selects no iOS PiP source/coordinator; **D-243-04** allows explicit entry only on Android and forbids a PiP iOS background-audio capability; **D-243-05** selects Path 3, Android API 26+/feature-present only, with iOS/other platforms always unsupported.
- The affected manifest is finalized by the decision artifact: shared Dart policy/gateway/controller, the Android handler/Activity/manifest/MainActivity seam, Android proof tooling, and host/static iOS fail-closed pins. No Plan 243 AppDelegate, Info.plist, Xcode-project, RunnerUITests, or iOS native-owner change is authorized.

## Scope Contract And Guard

In scope under accepted Path 3:
- Add `PictureInPictureCapability`, `PictureInPictureRequest`, `PictureInPictureState`, and `PictureInPictureGateway` with unsupported/unavailable/starting/active/restoring/stopped/failed outcomes.
- Use attachment ID plus app-owned resolved video path, optional known duration, and a normalized start position. Known duration clamps to `0..duration`; unknown duration clamps only below zero, then native-ready/later metadata re-clamps against the discovered duration through plan 228. Do not pass a message payload, encryption key/nonce, caption, sender, peer/group ID, owner lane, or transport object to native code.
- Allow PiP only for completed, ordinary, local videos whose lane capability explicitly enables it; private/view-once/expired/quarantined/missing media always fail closed.
- Ensure a single playback owner at a time. Handoff must pause Flutter, start native at the bounded position, update one position source, then restore plan 230's exact item/route or settle stopped without duplicate audio.
- Persist PiP checkpoints only for video attachments through plan 228. A non-video checkpoint is an error/no native start; unknown-duration checkpoints remain non-negative; duration discovery revalidates stored/current position; playback completion writes zero before restoration/terminal settlement.
- Implement platform availability checks: only Android API 26+ with the PiP feature may report supported. iOS and every other platform always report unsupported, omit the control/accessibility node, reject direct start before handoff, and continue normal viewer playback.
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
- Do not add an iOS PiP channel/owner, AVKit/AVPlayerLayer coordinator,
  RunnerUITests PiP source, or PiP `UIBackgroundModes=audio`. Do not add Android
  automatic-entry policy.

Deferred / accepted difference:
- Host playback controls and resume remain plan 230.
- Save/share/forward/download/delete/library behavior remains plans 227–242.
- Path 3 is the explicit accepted product difference: Android is the only PiP
  release surface; iOS/other platforms remain unavailable with no parity claim.

Dependencies:
- Plan 228 supplies DB v96 local playback state and the exact video-only, known/unknown duration, later re-clamp and completion-reset repository contract.
- Plan 230 supplies typed viewer identity, capability rendering, playback adapter, and local position callbacks.
- Plans 234, 238, and 242 supply lane-specific protected-media eligibility.
- The accepted D-243 Path 3 decision artifact is the implementation authority.

### Exact platform acceptance matrix

| Surface | Control and capability | Start/native behavior | Closure |
|---|---|---|---|
| Android API 26+, PiP feature present, eligible current ordinary video | Control visible/enabled; `supported=true` | One explicit request may hand off to the dedicated video-only Activity; session-fenced return/close/interruption/completion | Focused host/native tests and production-source integration proof on a rediscovered available physical Android device; emulator supplemental |
| Android API <26, feature absent, or unavailable Activity state | Control absent; `supported=false` | Deterministic unsupported, zero Activity start/handoff/checkpoint; Flutter playback unchanged | Host/native negative; unavailable version-specific hardware is N/A |
| Any platform with protected/stale/missing/non-video/integrity-failed media or revoked authority | Control absent; active Android session stops once on revocation | Reject before handoff; zero unauthorized frame/path/checkpoint | Policy, revocation, transport, and persistence negatives |
| iOS, web, desktop, and every non-Android platform | Control and accessibility node absent; `supported=false` | Deterministic `unsupported_platform`; zero PiP channel/owner/handoff/background-audio change; Flutter playback unchanged | Host/widget/static negative only; no physical-iPhone/simulator PiP gate and no cross-platform claim |

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-243-00 | The ownership decision selects Path 3: the Android dedicated-owner seam is accepted, while iOS/other platforms are explicitly unavailable and physical-iPhone close is not a gate. | `Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md` | accepted decision / retained Android ownership evidence and historical iOS diagnostics | GREEN decision authority: D-243-01..05 and the exact platform matrix are resolved without claiming iOS parity | change the artifact back to cross-platform/decision-required or promote an iOS trace -> decision red | document authority; complete before TC-243-01 production/test authoring |
| TC-243-01 | Host gateway maps support/start/stop/restore/error channel events exactly once and rejects stale session IDs. | `test/core/media/picture_in_picture_gateway_test.dart::typed PiP session maps native lifecycle exactly once and ignores stale events` | host unit / mocked method+event channels | after evidence gate, HEAD compile RED: gateway absent -> exact state sequence and terminal result pass | accept an event from the prior attachment/session or complete twice -> TC-243-01 red | exact `flutter test test/core/media/picture_in_picture_gateway_test.dart`; AUTO discovery is supplemental, not the closure gate |
| TC-243-02 | Eligibility fails closed for private/view-once/expired/quarantined/missing/non-video media; non-video rows invoke neither native nor playback-state write. | `test/shared/widgets/media/media_picture_in_picture_policy_test.dart::only ordinary completed local video can request PiP or checkpoint` | host unit / cross-lane image/video capability matrix + throwing gateway/repository | HEAD compile RED -> exact video row allowed; every protected/ineligible/non-video row makes zero native/write call | gate only on file extension/local path or allow image playback state -> TC-243-02 red | exact direct command; `test/shared/widgets/**` is not covered by feature/core globs |
| TC-243-03 | Android claimed matrix enters video-only PiP, supports system close/return, process recreation, completion, engine detach, and external audio-focus interruption while preserving MainActivity behavior. | `integration_test/received_video_picture_in_picture_proof_test.dart` plus `test/core/media/android_picture_in_picture_native_contract_test.dart` and causal host validators | Android device proof / physical Pixel 6 API 36 plus unsupported-capability host/native cases | Six production-source integration scenarios pass with exact one-owner settlement; API<26/feature-absent stays hidden by host/native coverage | remove API/feature check, shrink entire Flutter UI, replay process state, duplicate terminal ownership, or omit restoration -> proof/pin red | exact six-scenario `run_received_video_picture_in_picture_proof.sh` commands on explicit target; proof APK uses disposable debug ID and is not release-signed |
| TC-243-04 | iOS and every non-Android platform fail closed: no PiP control/accessibility node, capability false, direct start rejected before player handoff, and no iOS native owner/channel/project/background-audio addition. | `test/core/media/ios_picture_in_picture_fail_closed_contract_test.dart::Path 3 keeps iOS PiP hidden unsupported and native-owner free` plus platform cases in `media_picture_in_picture_policy_test.dart` | host/widget/static / iOS platform override, throwing playback adapter, source/project/Info.plist pins | HEAD policy RED until shared platform gating exists -> exact negative contract passes without a device | render the control, return supported, pause Flutter, register an AVKit channel/coordinator, add RunnerUITests PiP source, or add PiP audio background mode -> TC-243-04 red | exact direct host command; physical-iPhone/simulator PiP proof is N/A and must not be registered |
| TC-243-05 | Handoff pauses/disposes exactly one Flutter owner, starts native at the plan-228-normalized position, checkpoints one source, and restores or completes without duplicate audio. | `test/shared/widgets/media/media_picture_in_picture_handoff_test.dart::PiP handoff has one playback owner and one normalized durable position` | widget/application host / fake playback adapter + PiP gateway + repository recorder/clock | HEAD compile RED -> ownership/event counts exact through known/unknown duration start, success, cancellation, failure, completion and return | leave Flutter playing, use path identity, pre-clamp unknown duration to zero, or write from both owners -> TC-243-05 red | exact direct command; `test/shared/widgets/**` is not covered by feature/core globs |
| TC-243-06 | PiP modules remain transport-free and Android native requests/events contain only approved session/attachment/path/playback fields; no iOS native schema exists. | `test/core/media/picture_in_picture_transport_boundary_test.dart::PiP source and channel schema contain no messaging or secret fields` | shell-contract + host unit / Dart/Kotlin source/schema scan plus iOS absence pins | HEAD compile RED: modules absent -> forbidden imports/field names are absent across Dart/Kotlin and iOS stays native-owner free | pass serialized message/media map, import Bridge/P2P, or add a Swift PiP channel -> TC-243-06 red | exact `flutter test test/core/media/picture_in_picture_transport_boundary_test.dart` |
| TC-243-07 | Existing viewer, Android notification-intent, disk-space channel, migration keepalive wiring, and iOS notification delegate pins remain green. | `test/shared/widgets/media/full_screen_image_viewer_test.dart`; `test/core/notifications/main_activity_onnewintent_pin_test.dart::MainActivity.kt overrides onNewIntent and calls setIntent(intent)`; `test/core/device/disk_space_channel_test.dart::speaks the real mknoon/disk_space method channel contract`; `test/core/lifecycle/main_keepalive_wiring_test.dart::TC-183-W4: teardown disposes the keepalive (no Timer leak)`; `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart::AppDelegate pins iOS notification tap diagnostic forwarding` | `GREEN sentinel` / exact existing widget, channel, lifecycle, and native source-pin fixtures | GREEN on HEAD -> all remain GREEN after the selected native seam lands | overwrite channel registration, remove `onNewIntent`, leak keepalive teardown, or replace notification delegate without chaining -> sentinel red | exact combined `flutter test`; shared viewer requires direct invocation because feature/core globs do not cover `test/shared/**` |
| TC-243-08 | PiP persistence consumes plan 228 exactly: video-only writes; unknown duration stores non-negative position; later duration clamps stored/current state; completion resets zero and survives reopen. | `test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart::PiP persistence handles video only unknown later clamp and completion` plus `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::video resume handles unknown duration revalidation and completion` | widget/application + repository sentinel / PiP adapter over production repository with temp DB, image and known/unknown video rows, fresh reopen | HEAD PiP compile RED; after plan 228 the repository sentinel is GREEN -> PiP unknown position survives, later duration clamps both handoff/repository state, completion stores zero, image write rejects | treat null duration as zero/infinite, skip later clamp, retain completed duration, or write image position -> TC-243-08 red | exact two direct commands; shared resume coverage is not delegated to a broad glob |

### Test Notes

- TC-243-00 is closed by the accepted Path 3 decision and retained disposable
  ownership evidence. Do not rerun either platform ownership probe.
- Android production-source device proof records only state names, attachment-id
  prefix, duration/position, and platform version. It must not log paths,
  captions, sender/group identity, keys, nonces, or video bytes.
- The Android device proof must exercise explicit entry, system close,
  return-to-app restoration, interruption, completion, and protected-item
  absence. Automatic entry is not accepted.
- TC-243-05/08 use both a video with known duration and one whose duration is initially null then supplied later. “Unknown” means lower-bound normalization only; the later native/player duration must trigger plan-228 re-clamp. Completion must persist zero before a fresh viewer/PiP reopen.

## Implemented Sequence

1. Treat the accepted Path 3 decision and matrix as TC-243-00 authority; do not run another ownership probe or any iOS PiP device leg.
2. Add TC-243-01/02/04/05/06/08 before product code; confirm causal compile/behavior REDs while Plan-228/230 and existing iOS sentinels stay GREEN.
3. Implement the minimal typed gateway, Android handler/dedicated Activity, Android capability checks, session fencing/restoration, and Plan-228 checkpoint adapter. Add the non-Android unsupported branch before any playback handoff. Unknown duration stays non-negative until native readiness/later metadata clamps it; completion writes zero.
4. Do not modify an iOS PiP native/project surface. Stop if the Android path would require transport/protected-media weakening, a whole-Flutter-Activity PiP surface, or an iOS parity claim.
5. Add the exact Android device-proof classification, run focused/static/preservation gates and production-source proof on a rediscovered available physical Android target, then curated `1to1`/`groups`, analyzer, and hygiene.

## Risks And Blind Spots

- Whole chat leaks into Android PiP -> TC-243-00/03 require observed video-only output before selection and closure.
- An accidental iOS parity path could pause Flutter or add native/background capability despite Path 3 -> TC-243-04/06 require zero iOS control, channel, owner, handoff, and PiP background-audio change.
- Protected media could survive outside its viewer -> TC-243-02 and lane-private plans fail closed before native start and stop active sessions on lifecycle expiry.
- Lifecycle / derived-state durability: TC-243-05/08 reconstruct from attachment ID/position, later duration and completion state; no path-only restoration.
- Sibling-surface consistency: one shared capability is consumed by all three lanes, with private policy supplied by 234/238/242.
- Destructive-action side effects: none; source video and media rows survive every PiP result.
- Invariant re-verification under new transitions: start/restore re-load current attachment/protection/type/duration state; TC-243-01/02/05/08 reject stale sessions, non-video writes and stale upper bounds.

## Gate Cadence

- Individual plan closure runs TC-243 focused native/shared tests directly, exact existing native/viewer sentinels, the curated `1to1` and `groups` lane gates, and proof on every applicable target in the live available-device matrix.
- The shared `test/shared/**` suites are not covered by feature/core globs and therefore remain explicit commands; do not substitute `host-all`, `feature-host-all`, or `core-host-all` at Plan 243 closure.
- Run full `host-all` once after the 243-245 extension/reporting wave is complete, and once again at final media-rollout closure.

## Acceptance / Reproduction Gates

```bash
# Accepted Path 3 decision authority
test -s Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md

git status --short

# Historical causal RED command; it failed before implementation and is GREEN now
flutter test test/core/media/picture_in_picture_gateway_test.dart --plain-name 'typed PiP session maps native lifecycle exactly once and ignores stale events'

# Focused host GREEN
flutter test test/core/media/picture_in_picture_gateway_test.dart
flutter test test/core/media/picture_in_picture_transport_boundary_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_policy_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_handoff_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart
flutter test test/core/media/android_picture_in_picture_native_contract_test.dart
flutter test test/core/media/ios_picture_in_picture_fail_closed_contract_test.dart

# Plan-228 playback contract preservation; expect video-only/unknown/later-clamp/completion reset GREEN
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'video resume handles unknown duration revalidation and completion'

# Explicit discovery classification; checker exits 0 and the exact path has one ignored record, never unclassified
set -e
records_file="$(mktemp)"
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$records_file"
test "$(awk -F '\t' '$1 == "ignored" && $2 == "ignored" && $3 == "integration_test/received_video_picture_in_picture_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 1
test "$(awk -F '\t' '$1 == "unclassified" && $3 == "integration_test/received_video_picture_in_picture_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 0
rm -f "$records_file"

# Resolve the live Android matrix and pin the production proof to an available target.
# An unavailable Android version/device is recorded N/A by project policy; no iOS leg substitutes for it.
flutter devices --machine
adb devices
./scripts/run_received_video_picture_in_picture_proof.sh --platform android --scenario return --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh --platform android --scenario close --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh --platform android --scenario process-recreation --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh --platform android --scenario completion --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh --platform android --scenario engine-detach --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh --platform android --scenario interruption --device "$ANDROID_DEVICE_ID"

flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart test/core/device/disk_space_channel_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Canonical full analysis is an accepted non-green repository baseline:
# expected EXIT 1 with 1,610 issues (0 errors / 115 warnings / 1,495 infos).
set +e
flutter analyze
full_analyze_exit=$?
set -e
test "$full_analyze_exit" -eq 1

# Separate bounded result: expected EXIT 0 only with --no-fatal-infos,
# retaining 6 infos across the frozen 35-path manifest.
xargs flutter analyze --no-fatal-infos < \
  build/Plan243/final-focused/final-analyze-post-host-fixes/final-changed-dart-paths.txt
git diff --check
```

## Device/Relay Proof Profile

- Profile: an available physical Android API 26+ PiP-capable device is primary; an available Android emulator is supplemental. Unsupported/unavailable Android branches remain host/native-unit covered. No iOS target is in scope.
- Boundary being proven: real system PiP window, video-only presentation, platform capability, audio/playback ownership, system close, app restoration, interruption, and exact position continuity.
- Live availability check: `flutter devices --machine` and `adb devices`; export only a matching available Android ID. An absent version-specific target is `N/A (target unavailable by project policy)`, not a blocker.
- Required setup: an ordinary completed local MP4 plus a protected/private negative fixture; no relay/network is required.
- Closure role: required for the sole advertised PiP platform, Android; host mocks cannot close native UI ownership. The accepted physical build uses production sources under disposable debug ID `com.mknoon.app.pipproof`; it is neither the production application ID nor a release-signed APK. The iOS negative contract is host/widget/static and has no device leg.
- Registration: add an exact `integration_test/received_video_picture_in_picture_proof_test.dart` `classify_path` case to `scripts/check_reliability_simulation_discovery.sh`, category/kind `ignored`, note `manual Android received-video PiP proof outside default reliability-sim`; no transport family or iOS proof registration.
- Discovery command: the literal two-count block above must prove exactly one ignored record and zero unclassified records for the path.
- Closure command: the six explicit-target Android scenario commands above. Path 3 is already the accepted one-platform difference.
- Relay profile: N/A; any relay requirement is scope drift.

## Execution Interpretation And Done Criteria

The historical RED/implementation commands above remain the reproducible TDD
contract. The current implementation state is:

- [x] TC-243-00 decision artifact answers D-243-01..05 with the explicit accepted Path 3 difference.
- [x] Every post-decision behavior has a named causal test/proof and representative mutation.
- [x] Exactly one playback owner, stable attachment identity, video-only writes, known/unknown/later-clamped positions, completion reset, and protected-media suppression pass.
- [x] Typed direct/group repository revocation streams, fail-closed stream errors, priority stop fencing, paged-library requalification/eviction, and localized start-failure UX pass.
- [x] Android proof is explicitly classified and all six scenarios pass on physical Pixel 6 `21071FDF600CSC`, API 36; iOS proof remains absent/N/A.
- [x] Existing native lifecycle/channel and shared viewer sentinels pass.
- [x] Canonical full `flutter analyze` exits 1 and is non-green; it is accepted
  only as the repository baseline of 1,610 issues (0 errors, 115 warnings,
  1,495 infos). Separately, scoped `flutter analyze --no-fatal-infos` exits 0
  across 35 final Dart paths with 0 errors, 0 warnings, and 6 retained infos
  across 2 paths; it is not zero-diagnostic. Full stdout SHA-256 is
  `87ebe26dc473e21fa8d3b8f048d806e1d0af9afa69954de6e0bd01ad00bddf9e`;
  scoped stdout SHA-256 is
  `841834cffeae2d41d29d5127db8ef86de181e918da1c69a9b337df39b306468e`.
  Frozen analyzer bundle manifest SHA-256 is
  `74df203b77cbe46d1fb6d57708736a9bc6833dbbd0bf199a3a0988eda2b9942f`;
  result-summary SHA-256 is
  `20eeff49fbdefef4f40fe89fc2ff76570e21192c5edb5f54dc3507d68eea7f56`.
  `git diff --check` and 1,255/1,255 discovery completeness pass.
- [x] Exactly one incremental Graphify refresh passed and current architecture queries anchor.
- [x] Wave-3 aggregate coverage meets user-directed segmented-resume semantics:
  preserved items 1–416 plus exact resumed items 417–1,173; the resumed suffix
  passed 8,291 Flutter tests across 749 paths and all 8 Go legs. This is not a
  single uninterrupted invocation.
- [x] Final rollout aggregate coverage meets user-directed segmented-resume
  semantics: preserved items 1–1,114 plus exact resumed items 1,115–1,173; the
  concurrency-1 suffix passed 1,063 Flutter tests across 51 paths and all 8 Go
  legs. Full indexed coverage is 1,165 Flutter paths plus 8 Go legs, not a
  single uninterrupted invocation.

The physical proof is a production-source integration proof under disposable
debug ID `com.mknoon.app.pipproof`. It is not a production-ID or release-signed
APK. The protected physical negative is composite; focused host tests isolate
each protection state. Engine detach physically proves the shared cleanup seam
with `realCleanupCallback=false`; source/static/JVM/build-boundary tests prove
the real callback wiring and proof-receiver default absence.

## Execution Evidence

Evidence root:
`build/received-video-pip-proof/final-coherent-20260714T072110Z`.

| Scenario | Result | Host SHA-256 | Flutter SHA-256 |
|---|---|---|---|
| return | PASS — real SystemUI expand/return and exact playing owner restoration | `05be517116834debc5bdb0fc6640718d0a5d09e6b62201a850256ea4451db939` | `66fc9795bc4532bd228858d053e115084063927cfe51b40869af535b0c42162c` |
| close | PASS — real SystemUI close and paused owner restoration | `e4abe5f7d43769a4a4796c59e0504c430850930d05b90c0fa3c97d32dac65811` | `f525d71e4bb086d0931dbb7c3d2e29ca1ef218b22d194aaa883e9a9f47bd19c6` |
| process recreation | PASS — empty relaunch, no native replay | `1195ec3e47c82ca0ba580663ee0947a474ec1e95f802f0b3d7607777fd1a6f4d` | `0f964a68657cd34ba44935caafb08689988094f7a61d42a49b60a4519d605a5b` |
| completion | PASS — completed terminal and position reset to zero | `42049d74bbc3375a648b11ef05bfd07db462c2dca600d2ed37032bf6ddd7db6c` | `64856001a03170d2df74d8b25916ac3c14bc939fe1d7499bdc40fdce7903300f` |
| engine detach | PASS at shared seam, `realCleanupCallback=false` | `0364a9445f23860a08d9ecef71301f6df16c8361a05263e9dc3166071a04c2f9` | `419aa95af7bdf7f3d823ce7721cba18190c66dffccda2ff6e81715f974250c7f` |
| interruption | PASS — distinct-UID focus owner and exactly one interrupted terminal | `d4a7f663c6cd40c3b565985b5a738b8df3bee0a1e9609d87588d14e3c86c6757` | `43b02026a0ec6b11dd2d4564d8bdfb0f6339e90371d799f1b6226d3ce903c05c` |

Focused acceptance is pinned by `dart-pip-focused.log` (67 tests, SHA-256
`4296629119a80680c5677e9caa66793e890d6a253d5dda5b8784f87a777f80f0`),
`core-static-selector-10.log` (54 tests, SHA-256
`ac4d4e4c9168a406993f6b0e6cb64c8804b4aab21e0e9219209a320c27d1cfbe`),
and `route-composition-7.log` (362 tests, SHA-256
`f852150c5a112366810b3f6312ec2ef9d6963e15575dbdacf9acd1c294a4b4d3`).
Curated `1to1` and `groups` passed; the retained group result is the post-
barrier 2172-test log, not the earlier `+2171 -1` diagnostic. Plan 246 is
accepted/intentionally not applicable and its focused closure remains green.

Aggregate closure is explicitly segmented. The Wave-3 acceptance record
(`build/Plan243/final-host-gates/wave-host-all-composite/acceptance-record.md`,
SHA-256
`3140017c5cca80b8712c9d5c480908b64bc7652e5825391f6925723123851198`)
joins the user-preserved prefix 1–416 to the successful exact resume
417–1,173. The resume passed 8,291 tests across 749 Flutter paths and all 8 Go
legs. The final-release record
(`build/Plan243/final-host-gates/final-release-host-all-composite/composite-acceptance.md`,
SHA-256
`6df609df4f270c345c059bb53e9a9ee9ecab94f67ec6aaddd80dc8cf7fbfd6b1`)
joins retained prefix 1–1,114 to exact concurrency-1 resume 1,115–1,173. That
suffix passed 1,063 tests across 51 Flutter paths and all 8 Go legs, covering
the current full inventory of 1,165 Flutter paths plus 8 Go legs. Neither
record claims one uninterrupted `host-all` invocation, and overlapping
concurrent Flutter aggregates are never arithmetically summed.

All unsuccessful histories remain failure or diagnostic evidence:

- The first batched wave attempt planned 1,163 Flutter paths plus 8 Go legs;
  the nested completeness check exposed `gate_args[@]: unbound variable`, and
  it was manually interrupted with exit 130 before Go.
- The corrected first authoritative wave attempt planned 1,164 Flutter paths
  plus 8 Go legs and reached `+3886`, `~1`, `-1`. The tone-tracker case in
  `chat_message_listener_test.dart:1925` expected two notifications and
  observed one. It was manually interrupted with exit 141 before Go. Its host
  log SHA-256 is
  `92a9b5ee9de07efbdba3bbebc3884eb336cd2fee3833fc659e206808674a5cae`.
- A later Wave-3 batch failed first at planned item 417,
  `link_incoming_lan_media_test.dart`, at `+3430`, `~1`, `-1`, and was
  manually interrupted. Later reporter output and partial Go activity are not
  accepted. The interrupted pass-3 and older SIGTERM/143 runs are diagnostic
  only.
- The initial final-release concurrency-4 batch failed at planned item 1,115,
  `android_push_relay_registration_contract_test.dart`, when a child Dart
  process hit a host native-assets race while `install_name_tool` renamed
  `.dart_tool/lib/libsqlite3.arm64.macos.dylib`. Its exit 1, `+11709`, `~1`,
  `-1`, and 0/8 Go legs are failure evidence. Re-running the exact suffix at
  concurrency 1 is the accepted operational fix, not a product-code change.

The current isolation fixes are part of the accepted 1,173-item manifest.
Notification integration tests directly await `processIncomingMessage(...)`
and assert exact process state instead of relying on delayed stream scheduling.
`FakeMediaFileManager` uses process-and-isolate-specific temporary roots, and
the four-test `fake_media_file_manager_isolation_test.dart` proves same-isolate
sharing, cross-isolate separation, and teardown isolation. The added test path
accounts for the inventory change from 1,164 to 1,165 Flutter paths.

## Final Handoff

- Do not rerun iOS PiP or reinterpret its historical close failure. iOS remains
  hidden/unsupported with no AVKit PiP owner/channel/background-audio change.
- Do not call the custom-ID debug integration APK a production-ID, release, or
  store-signed artifact.
- Do not call the engine-detach leg a real Flutter callback invocation or the
  composite physical negative exhaustive protected-media proof.
- Preserve both aggregate records as user-directed segmented-resume coverage;
  do not relabel either as a single uninterrupted pass or reclassify any
  failed/interrupted predecessor.
- Frozen decision dependency: `243-proof-artifacts/pip-ownership-decision.md`,
  SHA-256
  `7a9ae073f90d4efe6b40051f2cb2ccf72573779704c184a00e6e49dbcea5b196`.

## Execution Progress

| Time | Phase | Last command/result | Current evidence | Remaining |
|---|---|---|---|---|
| 2026-07-13 | Path 3 decision | accepted | Android-only/fail-closed-iOS matrix selected | implementation |
| 2026-07-14 | implementation and focused closure | focused/static/route/native/preservation/curated PASS; canonical full analyzer captured as EXIT 1/non-green accepted repository baseline; scoped 35-path `--no-fatal-infos` analyzer and hygiene EXIT 0 | production and tests reconciled; scoped analyzer has 0 errors, 0 warnings, and 6 retained infos | complete |
| 2026-07-14 | physical closure | six Pixel-6/API-36 scenarios PASS | production-source custom-ID integration proof; iOS N/A | complete |
| 2026-07-14 | Graphify | one incremental refresh exit 0 | graph current; wrapper post-success `status` error retained without rerun | complete |
| 2026-07-14 | aggregate closure | Wave resume 417: `+8291`, 749 Flutter paths, 8/8 Go; final resume 1,115: `+1063`, 51 Flutter paths, 8/8 Go | full current inventory 1,165 Flutter paths plus 8 Go legs covered under explicit segmented-resume authority; neither composite is uninterrupted | complete |
