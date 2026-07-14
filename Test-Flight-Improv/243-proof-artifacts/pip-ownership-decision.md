# Plan 243 TC-243-00 — Native received-video PiP ownership decision

Status: path_3_android_track_3_wave_3_closed_with_segmented_host_acceptance
Decision date: 2026-07-13
Execution reconciliation date: 2026-07-14
Canonical release claim: Android API 26+ with
`FEATURE_PICTURE_IN_PICTURE`, runtime capability checks, and the Android
  production-source acceptance gates below. iOS and every other platform make no PiP
claim and must remain hidden/disabled/fail-closed.
Controlling decision: the user explicitly selected canonical Path 3. Android
PiP production implementation and release closure are authorized within this
artifact's Android-only scope. Physical-iPhone SystemUI close remains
historically FAIL/unproved but is no longer a closure gate. No iOS or
cross-platform PiP claim is authorized.

## Review boundary

This remains the factual record of the final user-authorized Xcode
provisioning, device UI Automation, Release-mode, native-mode-bridge, and
long-fixture run. The physical-iPhone SystemUI return selector passed. The
physical-iPhone SystemUI close selector then failed terminally because the
previously enumerated SpringBoard `Close Picture in Picture` element
disappeared before XCTest could synthesize `button.tap()`. No close terminal
event was emitted. TC-243-00 iOS close therefore did not pass and is not
reclassified. Path 3 resolves the product decision by excluding iOS PiP from
the claimed release surface; it does not convert that historical failure into
a pass.

The user previously selected the bounded-manual-close path only. Its first
authorized attempt failed before `USER_TAP_NOW` because of a host-wrapper
output-root defect, so no user tap or system-close action occurred. The
user then separately reauthorized exactly one corrected attempt and replied
`READY`. That corrected authority was consumed by a second pre-prompt host-
parser failure: the real AUT configure marker used Apple's
`Runner(Foundation)[21174]` process token, which the consumed wrapper did not
parse. The wrapper stopped xcodebuild fail-closed before `USER_TAP_NOW`; no
manual tap or system-close action occurred. The user later separately
authorized one third bounded-manual-close attempt and replied `READY`. That
authority was consumed by a pre-prompt XCTest lookup failure after the exact
close control had been visibly and programmatically observed, but before
`USER_TAP_NOW`; again no human tap or system-close action occurred. A separately
authorized fourth attempt then used the frozen v3 package. It reached one native
`DidStart`, but XCTest rejected the unsupported `hittable` predicate key before
`USER_TAP_NOW`; again no human tap or system-close action occurred. All four
authorities are consumed, with no retry or future live attempt authorized. The
historical Path 1 selection and consumed attempts are not implementation or
production authorization, and no wording in this artifact may be interpreted
as a TC-243-00 iOS-close pass. The later explicit Path 3 selection supersedes
Path 1 for product scope and authorizes only the Android production path.

Subsequent offline-only work did not query or drive a physical device. Runner
v5 passed independent byte, source-boundary, build, signing, and profile
review, but wrapper v5 was causally rejected after independent counterexamples
proved that its auditor could return PASS without a host confirmation, with an
empty raw device syslog, and with absent or zero terminal-line hashes in the
ledger. Structural package sealing is not causal acceptance. No fifth live
attempt occurred, no prompt or tap occurred, and no execution,
implementation, production, retry, or future live authority was created.

An unfinished, unsealed wrapper-v6 staging lineage was subsequently reviewed
offline. It is rejected for decision and release purposes, retained only as
offline diagnostic work, and grants no live-device, retry, proof, iOS, or
production authority. Path 3 requires no successor manual-close wrapper and no
additional physical-iPhone close attempt.

No production/shared/native source was changed by the historical final iOS
proof run. The
disposable probe lived outside the repository at `/tmp/mknoon_pip_probe`; the
final evidence archive is
`/tmp/pip243_unique_runner_release_longfixture_20260713_1`. The user-authorized
environmental prerequisites did change relative to the earlier blocked audit:
the user signed in to Xcode, Xcode created a managed wildcard development
profile for the UI-test runner, and UI Automation was enabled on the iPhone 11.
Those environmental actions are evidence prerequisites, not production
authorization. After the final run, both disposable bundles and all target
processes were absent, the two signing identities and seven-profile inventory
were unchanged from the final-run preflight, and every frozen Release artifact
remained byte-identical.

## Canonical Path 3 release boundary

Path 3 is the final D-243-05 product decision. Its authorization is narrow:

- Android PiP may be implemented and released only for an eligible ordinary
  received video on API 26+ when the device advertises
  `FEATURE_PICTURE_IN_PICTURE` and every focused, preservation, and Android
  production-source physical-device gate in the canonical Plan 243 passes.
- iOS PiP is intentionally unavailable on every iPhone, iPad, simulator, and
  iOS version. The PiP control is absent, capability is false, a direct start
  request fails deterministically without handing off playback, and ordinary
  Flutter playback continues unchanged.
- iOS must not register an AVKit PiP channel or owner, add an
  `AVPictureInPictureController`/`AVPlayerLayer` coordinator for Plan 243, or add
  `UIBackgroundModes=audio` for PiP. Existing non-PiP AppDelegate,
  notification, share, background-fetch, and remote-notification behavior is
  preservation-only.
- No iOS, Apple-platform, or cross-platform PiP claim may be inferred from the
  retained return PASS, the historical owner/process traces, an available
  simulator, or any rejected wrapper lineage.

The exact acceptance matrix is:

| Runtime surface | PiP control | Gateway capability/start | Native effect | Required closure |
|---|---|---|---|---|
| Android API 26+, PiP feature present, ordinary completed integrity-verified local video, current authorization valid | Visible and enabled | `supported=true`; one explicit start may enter the dedicated video-only Activity | One session-fenced Android owner; no automatic entry; exact return/close/interrupt/completion settlement | Focused host/native tests plus a production-source integration proof on an explicitly rediscovered available physical Android target; emulator is supplemental |
| Android API <26 or PiP feature absent | Hidden, not merely visually disabled | `supported=false`; start returns deterministic unsupported | Zero Activity start, owner, checkpoint, or playback handoff; Flutter playback continues | Host/native capability negatives; unavailable version-specific hardware is N/A by project policy |
| Android media ineligible, protected, stale, missing, non-video, integrity-unverified, or authorization revoked | Hidden; an active session is stopped once on revocation | Start rejected before native handoff | Zero unauthorized frame/path exposure; no protected-media checkpoint | Exact policy, revocation, transport-boundary, and persistence negatives |
| iOS on every device, simulator, OS, and API-capability result | Hidden and absent from accessibility semantics | `supported=false`; start returns deterministic `unsupported_platform` | Zero AVKit PiP owner/channel/start, zero PiP audio-background capability, zero playback handoff; Flutter playback continues | Host/widget/static fail-closed tests only; physical-iPhone return/close/process proof is N/A and not a closure gate |
| Web, desktop, and any other platform | Hidden | `supported=false`; deterministic unsupported | Zero native handoff | Host capability negative; no release claim |

“Android production authorized” authorized implementation and the bounded
Android release gates. The implementation and production-source physical proof
now exist and are reconciled below. The physical APK intentionally used the
disposable debug application ID `com.mknoon.app.pipproof`; it is not the
production application ID, a release-signed APK, or store-distribution proof.

## Outcome

The only claimed platform is Android. On an eligible explicit Android request,
the dedicated native playback owner starts only after the typed Flutter viewer
has paused, durably flushed its Plan-228 position through fresh exact-current
authorization, and disposed its `video_player` controller.

- Android uses a dedicated, non-exported, video-only Activity. MainActivity
  remains a separate fullscreen Flutter task and is never made PiP-capable.
- iOS has no Plan 243 native playback/PiP owner. Its control stays hidden and
  its gateway returns unsupported without pausing or disposing Flutter
  playback.
- Automatic background entry is disabled. Android PiP is entered only from an
  explicit ordinary-media viewer action.
- At most one audio/video owner exists. Terminal native state is fenced by an
  opaque session ID and exact attachment ID. Flutter can persist or recreate
  only after reauthorizing the exact current row and canonical path.
- Private, view-once, expired, quarantined, missing, incomplete, integrity-
  unverified, non-video, or otherwise protected media never expose PiP and
  immediately terminate an already-active session if authority is lost.
- Android process recreation is fail-closed. Native state, source paths, and grants are
  memory-only and are never reconstructed from an Intent, Bundle, saved state,
  or a path alone. iOS never creates this native state.

The probe found two real ownership bugs before production work:

1. Android SystemUI close can tear down VideoView before the terminal callback,
   making currentPosition report zero. A session-fenced 100 ms native
   checkpoint corrected the device trace. The production contract tightens
   this to monotonic max(previous, observed), cancels it before player release,
   and permits Dart persistence only after fresh exact-current authorization.
2. AVPlayer.seek followed immediately by play started iOS at zero. Awaiting the
   exact asynchronous seek before play produced requestedMs=3944 and
   observedMs=3944 on the physical iPhone.

It also found and rejected one proof-oracle defect. The first iOS
process-relaunch oracle expressed playback as `player?.rate != 0`; Swift makes
that optional comparison true when `player` is nil. The negative trace was
retained, the oracle was corrected to `player.map { $0.rate != 0 } ?? false`,
and the complete active-PiP SIGKILL/relaunch leg was rerun from a versioned
test marker. The accepted rerun reports every native replay field false/null.

The earlier no-account, automation-mode, Debug-launch, remote-Accessibility,
12-second EOF, and compile-time-mode outcomes below are retained as causal
history, not as the controlling result. The final Release return run did drive
SpringBoard's real `Restore full screen` control and passed every declared
mode, lifecycle, ownership, fixture, monotonic-position, and EOF-headroom
assertion. The subsequent clean close run reached active PiP and enumerated the
real close control, but XCTest lost the element before the tap and produced one
test failure with zero close terminal events. Return evidence cannot substitute
for that missing close proof.

## D-243 decisions

| Decision | Candidate answer | Evidence and production consequence |
|---|---|---|
| D-243-01 — playback owner | Own a dedicated native player on Android only; never reach into `video_player` internals. | The repo resolves `video_player` 2.11.1 and exposes no maintained native PiP source. Android transfers to the dedicated app-owned owner after a fenced handoff. iOS retains its Flutter owner because PiP is unavailable there. |
| D-243-02 — Android Activity | Add a dedicated ReceivedVideoPictureInPictureActivity; never PiP MainActivity. | Physical Android dumpsys showed a pinned video Activity task over a distinct fullscreen Flutter MainActivity task. The Activity is exported=false, has no intent filter, accepts no external URI, and reads only the in-process session registry. |
| D-243-03 — iOS source | Select no iOS PiP source or coordinator. | Earlier physical-iPhone owner/completion/process and return evidence is retained as historical diagnostics only. The failed close leg is not rerun and is no longer a gate because iOS makes no PiP claim. |
| D-243-04 — entry/background policy | Explicit user entry only on eligible Android; no automatic entry and no iOS PiP background-audio capability. | Android leaves automatic entry disabled. iOS must not add `UIBackgroundModes=audio` or activate an AVAudioSession for Plan 243 PiP. |
| D-243-05 — supported matrix | Canonical Path 3: Android requires SDK >= 26 and `FEATURE_PICTURE_IN_PICTURE`; every iOS/other-platform result is unsupported and hidden. | Pixel 6 API 36 passed both the frozen ownership decision and the later six-scenario production-source integration proof. Android API 24/25 and feature-absent devices remain capability-hidden and native-unit covered. All physical-iPhone and simulator PiP proof legs are N/A for release closure. |

### TC243-00 rejected alternatives and plugin-fork cost

- Forking or patching `video_player_android` and
  `video_player_avfoundation` to expose private player/layer/controller handles
  is rejected. It would pin Plan 243 to plugin-private APIs, require two native
  forks, duplicate lifecycle/security review, carry merge work on every
  `video_player` upgrade, and make upstream bug/security uptake conditional on
  a recurring fork rebase. That permanent maintenance cost is not justified
  when a small app-owned dedicated owner passed both physical platforms.
- Passing a Flutter texture ID or relying on an undocumented plugin registrar
  handle is rejected. Neither is a supported ownership transfer contract, and
  plugin disposal may invalidate the underlying player while native PiP still
  references it.
- Making `MainActivity` PiP-capable is rejected. It would place the whole chat,
  navigation, notification-intent, disk, migration, share, and permission
  surface into PiP instead of a video-only surface.
- Keeping the Flutter player alive under a second native player is rejected
  because it creates overlapping audio/video owners and ambiguous checkpoint
  authority.
- Treating simulator marketing/API presence or retained physical-iPhone traces
  as an iOS release claim is rejected. Android-only/fail-closed-iOS Path 3 is
  selected.
- Automatic background entry is rejected as a privacy risk. Entry remains an
  explicit ordinary-media viewer action.
- Persisting native session, path, URI grant, player, controller, or playback
  state for process replay is rejected. Only the already-authorized Plan-228
  numeric checkpoint may survive process death.

## Selected native seams

### Android

ReceivedVideoPictureInPictureActivity owns only the native video surface and
audio player. PictureInPictureHandler owns MethodChannel/EventChannel
registration and a single in-process session registry.

- Manifest: exported=false, supportsPictureInPicture=true,
  resizeableActivity=true, no intent filter, no URI/data declaration, and no
  PiP attribute on MainActivity.
- Start: Dart places a fully validated request in the process registry, then
  starts the Activity with no path or media payload in the Intent.
- Recreation: savedInstanceState != null, missing registry state, mismatched
  session, or process restart immediately finishes without playback.
- Exit: system expand/return, system close, explicit stop, authorization loss,
  interruption, completion, Activity destruction, Flutter-engine detach, and
  host destruction all settle once and release the player/audio focus.
- Position: a session-fenced main-thread sampler records at most every 100 ms,
  stores max(previous, observed), never writes durable app state, and is
  canceled before stopPlayback/release. A zero terminal observation falls back
  to that monotonic value.

### iOS fail-closed non-seam

No iOS PiP native seam is selected. Plan 243 must not add a coordinator,
AVPlayer/AVPlayerLayer/AVPictureInPictureController ownership, PiP method/event
channel registration, PiP restoration state, or PiP audio-session/background
mode. The shared Dart capability reports unsupported before any player
handoff, the viewer omits the PiP control and accessibility node, and the
existing Flutter player continues under its unchanged lifecycle.

## Android lifecycle and platform fail-closed contract

1. FullScreenTypedMediaViewer is the only Flutter viewer changed.
   full_screen_image_viewer.dart is preservation-only.
2. The visible control additionally requires an Android runtime, API 26+, and
   the PiP feature. iOS and all other platforms short-circuit to unsupported
   before authorization, persistence, or playback-owner handoff.
3. On Android the visible control requires ordinary incoming media, a trusted owner lane,
   exact current parent/message/attachment identity, video type, completed and
   integrity-verified local storage, canEnterPictureInPicture=true, and no
   private/view-once/expired/quarantined/terminal state.
4. Immediately before handoff, the lane-specific authorizer reloads the exact
   current identity and issues a short-lived authorization lease containing the
   opaque session, attachment, generation, normalized position, and canonical
   app-owned path.
5. Flutter writes the handoff position through the Plan-228 adapter only while
   that lease is current, pauses, disposes the real video_player controller, and
   waits long enough only for platform release completion—not a timing guess.
6. Native accepts only one matching in-memory session. It canonicalizes the
   file again and rejects missing, symlink-escaped, stale, or malformed input.
7. nativeReady does not itself grant playback. Dart reauthorizes the exact
   current row/path again, then acknowledges activation. A rejected
   acknowledgement stops native immediately.
8. While active, the controller subscribes to the lane's real message/removal/
   expiry/library-change signal. That subscription is the primary revocation
   mechanism and calls native stop synchronously on the first relevant signal.
   A bounded poll no slower than 250 ms is only a missed-signal backstop.
9. Native checkpoint events update only session memory. Before every durable
   write, Dart reloads exact current authority and verifies session,
   attachment, generation, media type, protection state, and canonical path.
   A stale or unauthorized checkpoint is discarded and native is stopped.
10. System expand/return may recreate one Flutter owner at the returned
   normalized position. System close may recreate it paused if the typed route
   still exists, but never auto-resumes. Authorization loss, route disposal,
   engine detach, and process death do not recreate. Completion writes zero and
   settles without a second owner.
11. Unknown duration follows Plan 228 lower-bound-only normalization. A later
    discovered duration reclamps both in-memory and durable position.
    Completion persists zero before a fresh viewer/PiP reopen.

## Exact-current authority and path rule

MediaLibraryStateRepository.updatePlaybackPosition is a persistence seam, not
authorization. No generic attachment lookup, cached viewer item, or
MediaFileManager.resolveStoredPathSync result is authority.

Each composition supplies an exact-current reloader:

- direct conversation and direct library: MessageRepositoryChangeSource plus
  ReceivedMediaActionController reload the current peer/message/attachment;
- group conversation, group library, and announcement: the current group row,
  message/removal stream, and _loadCurrentOrdinaryGroupMediaIdentity reload the
  current group/message/attachment;
- library ChangeNotifier updates and private/expiry events are bridged into the
  same revocation subscription.

The shared app-owned path authority is extracted from the existing egress
checks and reused by egress and PiP without changing egress outcomes:

1. Resolve the candidate and root with symlinks/canonical realpath.
2. Allow only a regular file under an exact literal app container root named
   media, local_media, or post_media.
3. Accept root equality or root + platform separator prefix only; reject
   substring matches, parent traversal, nonexistent files, root replacement,
   and symlink escape.
4. Recheck that the canonical path belongs to the exact current attachment at
   start, nativeReady, every checkpoint write, restore, and completion.
5. Never infer current parent or attachment authority from the path.

## Native request/event schema and session fence

Allowed request fields:

- session: cryptographically opaque per-attempt ID;
- attachment: exact attachment ID;
- path: canonical app-owned local path;
- positionMs: Plan-228-normalized non-negative position;
- durationMs: nullable/known duration.

Allowed event fields:

- session and attachment;
- state;
- bounded positionMs and discovered durationMs;
- platform capability/terminal reason from a closed enum.

Forbidden fields include owner lane, message ID, peer/group ID, sender,
caption, serialized message/media maps, transport objects, encryption
key/nonce, URI grants, media bytes, Bridge/P2P/relay data, and secrets.

Dart and native each accept one active session. A mismatched attachment,
generation, late event, duplicate terminal, or event after cleanup is ignored.
Native logs omit paths and user content.

## Disposable probe fixture

- Flutter 3.41.4; Dart 3.11.1; video_player 2.11.1.
- Android build: JDK 17.0.18.
- iOS build: Xcode 26.6, build 17F113.
- The controlling final iOS fixture is exactly 72.000 seconds and 2,463,571
  bytes. Its video stream is H.264 High, yuv420p, 320x180 at 30 fps with a
  1/90000 time base. Its audio stream is AAC LC, 48 kHz, mono with a 1/48000
  time base. Both streams and the container report exactly 72.000000 seconds.
- Fixture SHA-256:
  `d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5`.
- Dart, native Swift, XCTest, the source asset, the embedded Release asset, and
  the copied on-device asset all use that exact duration and hash contract.
  Playback is non-looping. Every non-completion terminal assertion requires at
  least 30,000 ms of EOF headroom, and an unexpected non-completion EOF is a
  terminal failure rather than a loop.
- The earlier 12-second fixture and digest
  `fff7ec5eb2f93815a39b72e1dffd924aac17bcf53ee04beeec3f98ee1a184c6e`
  are retained only for historical Android/causal iOS traces. They are not the
  fixture contract for the controlling final iOS return/close run.

Final contract verification:

~~~bash
ffprobe -v error \
  -show_entries \
  'format=duration,size:stream=index,codec_name,codec_type,profile,pix_fmt,sample_rate,channels,duration' \
  -of json /tmp/mknoon_pip_probe/assets/probe.mp4
shasum -a 256 /tmp/mknoon_pip_probe/assets/probe.mp4
sh /tmp/pip243_unique_runner_release_longfixture_20260713_1/evidence/verify_fixture_contract.sh \
  /tmp/mknoon_pip_probe
~~~

## Historical ownership-decision device matrix

Resolved immediately before the final platform work with:

~~~bash
flutter devices --machine
adb devices -l
xcrun simctl list devices available
xcrun devicectl list devices
~~~

### Flutter/ADB targets

- Pixel 6, 21071FDF600CSC, physical USB, Android 16/API 36.
- sdk gphone16k arm64, emulator-5554, emulator, Android 17/API 37.
- iPhone 13, 00008110-00184D622289801E, physical wired, iOS 26.5
  build 23F77; paired, developer mode enabled, DDI services available,
  unlocked, display active. This was the iOS proof target.
- iPhone 11, 00008030-001A6D2801BB802E, physical wired, iOS 26.5
  build 23F77; paired, developer mode enabled, DDI services available,
  unlocked.
- iPhone 17 Pro Max, 00008150-001C3C6A3684401C, physical paired network,
  iOS 26.5.1 build 23F81; developer mode enabled, but DDI unavailable in the
  resolved run.
- macOS 26.5.2 and Chrome 149 were visible to Flutter but are not PiP proof
  targets for this mobile plan.

devicectl also listed one unavailable iPhone13,2
(4556ED36-DFF3-5E44-B6F0-A3F8E2B5296A); it is N/A by project policy.

### Available iOS simulators

All were shutdown at resolution time on iOS 26.5:

- cv08-A 82CE652C-8489-4B74-8BCA-8DB556C1388A;
- cv08-B D18969E3-9C11-42BC-B3A1-C23BC29F584F;
- iPhone 17 Pro 674DFFF6-5F38-4235-93F6-AF7FBF86AE65;
- UP004 Alice iPhone 17 Pro 00088271-FED9-48FC-97C9-191E27014A09;
- iPhone Air 6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76;
- UP004 Bob iPhone Air B052B0F1-1DB8-470A-B114-D3294FA0668B;
- iPhone 17 8E31AD68-4DBF-4336-AEBF-18148DC9FA07;
- UP004 Charlie iPhone 17 EE2981F4-54E5-423D-B7FA-64DDBD4EEEDC;
- Gap Closure Dana iPhone 16e B631406C-C039-4AE3-8CC7-EBCB28FD03C7;
- iPhone 16e DBE8C32E-9F19-4593-860A-B41113791D79.

The iPhone 17 Pro simulator was the fail-closed negative:
AVPictureInPictureController.isPictureInPictureSupported returned false.
The physical iPhone result, not simulator marketing or API presence, supports
the iOS claim.

## Historical Android ownership-spike physical evidence

The host-controlled runner used the real video_player controller before and
after native ownership, Android SystemUI PiP controls, ActivityManager,
SurfaceFlinger/screenshots, and AudioService. Its disposable source is
/tmp/mknoon_pip_probe/run_android_probe.sh.

### System expand/return

- Flutter owner: checkpoint 3926 ms; sole active AudioTrack piid 3383.
- Native owner: dedicated pinned task #780 above fullscreen Flutter task #779;
  sole active MediaPlayer piid 3391.
- Actual Android SystemUI expand control caused system_pip_exit exactly once.
- Native stopped/restoring at 5911 ms.
- Dart durably wrote 5911 only after the matching terminal event, recreated a
  real Flutter player at 6140 ms (229 ms delta), and progressed to 9138 ms.
- Restored Flutter was the sole active AudioTrack piid 3407.
- The pinned task was absent after return.

### System close and zero-position regression

- Flutter owner: 3910 ms, sole AudioTrack piid 3447.
- Native owner: sole MediaPlayer piid 3455.
- The host opened the actual PiP menu for bounds
  [232,1617]-[910,2295] and tapped SystemUI close at [846,1681].
- The initial design observed currentPosition=0 after SystemUI tore down
  VideoView. This was rejected.
- The corrective device run used the session-local 100 ms fallback and returned
  6139 ms exactly once instead of zero.
- Flutter restored at 6315 ms, sole AudioTrack piid 3471, and progressed to
  9397 ms; no pinned task remained.
- The production contract further requires monotonic max(previous, observed),
  session fencing, cancellation before release, and reauthorization before
  persistence. Native and handoff tests below pin that exact correction.

### Flutter engine detach

While native PiP was the sole owner, the host BACK action destroyed only the
fullscreen Flutter task. cleanUpFlutterEngine synchronously:

- captured 5220 ms;
- emitted stopped/restoring once with reason flutter_engine_detached;
- stopped native with stoppedNative=true;
- removed the pinned task and released all app audio;
- left the onDestroy fallback with stoppedNative=false, proving no duplicate
  terminal cleanup.

### Process death

- Real Flutter video_player ran, durably flushed 4014 ms, and disposed.
- Native dedicated PiP became the sole MediaPlayer owner.
- adb force-stop killed process, pinned task, and audio.
- Relaunch with app data retained reported
  active=false, session=null, attachment=null, checkpointMs=4014.
- No path, player, audio, task, or native session replayed.

Representative commands:

~~~bash
cd /tmp/mknoon_pip_probe
flutter analyze
flutter build apk --debug
./run_android_probe.sh 21071FDF600CSC system_expand
./run_android_probe.sh 21071FDF600CSC system_close

adb -s 21071FDF600CSC shell dumpsys activity activities
adb -s 21071FDF600CSC shell dumpsys window windows
adb -s 21071FDF600CSC shell dumpsys SurfaceFlinger --list
adb -s 21071FDF600CSC shell dumpsys audio
adb -s 21071FDF600CSC shell am force-stop \
  com.mknoon.probe.mknoon_pip_probe
~~~

## iOS physical evidence

The earlier iPhone 13 owner/completion/process work below remains historical
support. The controlling SystemUI disposition is the later clean iPhone 11
Release run.

### Final authorized provisioning and runner prerequisites

Before user sign-in, the normal unique UI-runner topology stopped with
`No Accounts` and no profile for
`com.mknoon.app.RunnerUITests.xctrunner`. After the user signed in to Xcode,
that no-account/runner-profile blocker was gone. A separate post-sign-in
diagnostic stopped because the disposable `RunnerTests` target lacked a
development team; it did not invalidate the normal `Runner` scheme.

Xcode created the managed wildcard development profile
`iOS Team Provisioning Profile: *`, UUID
`f5f34d01-1ccd-403e-8cee-a74a79e0e9d1`, SHA-256
`fa0b48332f3342488596a878b00ae038e9d9b44a4d3220f44fd08240703de0ce`.
It has application identifier `397R9Q4WMX.*`, contains both physical proof
device UDIDs, was created 2026-07-13 09:06:58Z, and expires 2027-07-13
09:06:58Z. The final Release build used the existing app-specific profile
`4e7c6235-6461-4278-912c-ba0154d14a98` for `com.mknoon.app` and the wildcard
profile for the UI-test runner/test bundle, all under development identity
`07FA8F9289DC55BEA840509024A7BD32CCD4A9FE`. It required no further
`-allowProvisioningUpdates`; the final two-identity/seven-profile inventory was
unchanged before and after the proof.

Both initial unique-runner device attempts stopped before their test method
with `Timed out while enabling automation mode`. Device UI Automation was
therefore a user-controlled prerequisite, not something the harness could
silently bypass. After the user enabled UI Automation on the iPhone 11, XCTest
entered the selected method and all later device actions were harness-driven.

That first method-entering build was Debug and exposed Flutter's iOS 14+ guard:
debug apps may be launched only from Flutter tooling, a Flutter-aware IDE, or
Xcode; detached XCTest launch must use profile or release. The UI hierarchy
contained that exact guard text, so the failed PiP wait was not a PiP product
failure. All controlling runs consequently used Release. `Flutter.framework`
reported `BuildMode=release`, and the AUT contained none of `_dartVmService`,
`NSBonjourServices`, or `NSLocalNetworkUsageDescription`.

The first Release pair then diagnosed a scenario-routing defect: the close
selector set launch environment `PIP_PROBE_MODE=system_close`, but Dart AOT
used a previously compiled `PROBE_MODE=system_return` fallback. The disposable
native mode bridge corrected this by validating `PIP_PROBE_MODE` through
`ProcessInfo`, returning it from the capability call, and rejecting missing or
unsupported values; Dart already selected the native capability mode first.
The final xctestrun was built with exactly six Flutter metadata `DART_DEFINES`
and zero scenario defines, so one Release artifact could execute either
selector without a baked mode. This bridge was disposable proof code and is
not production authorization.

### Earlier completion and owner-lifecycle proof

Corrective commands:

~~~bash
cd /tmp/mknoon_pip_probe
flutter build ios --profile --dart-define=PROBE_MODE=completion
xcrun devicectl device install app \
  --device 00008110-00184D622289801E \
  build/ios/iphoneos/Runner.app
xcrun devicectl device process launch \
  --device 00008110-00184D622289801E \
  --terminate-existing --activate --console com.mknoon.app
xcrun devicectl device copy from \
  --device 00008110-00184D622289801E \
  --domain-type appDataContainer \
  --domain-identifier com.mknoon.app \
  --source Library/Caches/pip_native_probe.log \
  --destination proof-output/ios_physical/pip_native_probe_seek_fixed.log
~~~

Observed final trace:

- capability: simulator=false, supported=true, applicationState=active,
  foregroundActive scene, one visible key window;
- real Flutter owner played, flushed 3944 ms, paused, and disposed;
- native AVAudioSession activated only after Flutter disposal;
- exact AVPlayer seek: requestedMs=3944, observedMs=3944;
- AVPictureInPictureController source was possible=true at position 3944;
- nativeReady once, DidStart once, and active once with videoOnly=true;
- completion once after about 7.56 seconds of remaining fixture playback;
- completion position zero was durably flushed;
- restoreUserInterfaceForPictureInPictureStop once with the foreground scene;
- DidStop once, native audio inactive once, cleanup once;
- no PROBE_FAILED entry;
- the completion Runner process was terminated and no player, controller, or
  audio owner remained.

The earlier zero-seek trace is retained only as causal failure evidence. The
final claim depends on the seek-fixed trace above.

### Active-PiP process termination and relaunch

The independently host-controlled process leg was run with
`PROBE_MODE=process`. Its ordering was observed and copied before the host
issued the kill:

1. The real Flutter owner played, wrote 3944 ms, paused, and disposed.
2. Exact-current attachment/path generation 1 was reauthorized.
3. Native AVPlayer exact-seek completed 3944 -> 3944, nativeReady emitted, and
   AVPictureInPictureController `DidStart` emitted for `process-session`.
4. The Flutter trace emitted `PROBE_PROCESS_ACTIVE kill-now`; CoreDevice also
   identified live Runner PID 6041.
5. Only then did the host send SIGKILL/9 to PID 6041. The launch console
   reported `App terminated due to signal 9`, and the post-kill process query
   was empty.
6. With the data container retained, the host relaunched Runner as PID 6042.

The new launch queried a newly constructed coordinator before any start call.
The exact snapshot was:

~~~text
active=false
session=null
attachment=null
sourcePathRetained=false
grantRetained=false
playerRetained=false
playerLayerRetained=false
controllerRetained=false
audioSessionActive=false
playbackActive=false
~~~

Dart accepted `replayedKeys=[]`, reauthorized only the canonical fixture row
for inspection of the retained numeric checkpoint, and emitted
`authorizedCheckpointOnly=true`. The checkpoint file was 3944 before SIGKILL,
after SIGKILL, and after relaunch, with the same SHA-256 each time. No native
session/source/path/grant/player/layer/controller/audio/playback state replayed.

The first attempt is retained as a negative oracle-regression trace. It had the
same correct empty coordinator state, but the optional-comparison bug reported
`playbackActive=true`; Dart rejected it with `PROBE_FAILED`. The accepted v2
trace was collected only after correcting that test-only oracle and versioning
the disposable phase marker.

### Controlling physical-iPhone SystemUI closure disposition

The final authorized run used the wired iPhone 11
`00008030-001A6D2801BB802E`, iOS 26.5 (`23F77`), a Release-only build, and a
non-looping 72,000 ms fixture. The fixture is 2,463,571 bytes, H.264 High
320x180 at 30 fps with AAC LC 48 kHz mono, and has SHA-256
`d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5`.
Its duration left at least 30 seconds of required headroom for every asserted
terminal path, and unexpected noncompletion EOF was terminal.

The return selector ran once and passed. XCTest actuated SpringBoard's real
`Restore full screen` control. The selector, XCUI launch environment, Flutter
capability result, and native coordinator all agreed on return mode. Positions
were monotonic across handoff 3927 ms, native active 4410 ms, returned 10934
ms, restored actual 11144 ms, and final Flutter position 14245 ms. Final
headroom was 57,755 ms. The result had one lifecycle settlement, one occurrence
of each of the four reauthorization phases, no owner overlap, a playing sole
Flutter owner, native owner false, native audio false, and no failure,
completion, or unexpected EOF event.

The independently clean close selector then ran once with no retry and failed:
it reached active native PiP at 4456 ms after a 3923 ms handoff with 67,544 ms
of fixture headroom, and XCTest enumerated SpringBoard's real
`Close Picture in Picture` button, but the element disappeared immediately
before `button.tap()`. XCTest reported `No matches found for Descendants
matching type Button` at `ReceivedVideoPictureInPictureUITests.swift:77`.
There was no synthesized close tap and zero terminal events: no restore UI
request, `DidStop`, terminal checkpoint, audio deactivation, cleanup, Flutter
return/restoration, or native-owner release. This is a close failure, not a
passed or waived close leg.

The final evidence archive is
`/tmp/pip243_unique_runner_release_longfixture_20260713_1`; its manifest has
SHA-256 `9f85c145a36d61e46fa2ee81d13a0c1762e0508e0da22ab6d6b2a92da6f7cb25`.
The final Release artifacts passed deep and strict signature verification,
contained no `_dartVmService`, Bonjour, or Local Network metadata, and used
zero compile-time scenario defines. After both selectors, the AUT and XCTest
runner were absent, no target process remained, and all frozen artifacts were
byte-identical to preflight.

### Selected bounded manual close: four consumed pre-prompt failures

The user selected bounded manual close only. The first authorized live attempt
is preserved at
`/tmp/pip243-manual-close-device-run-20260713T122044Z`; its evidence manifest
has SHA-256
`22889e9c0913adaaca9754ec59213114e1603035d1eed0ed41e69bfe9f8c11a9`.
The host wrapper passed CoreDevice JSON/log paths below a
`device-preconditions` output directory it had not created, then failed before
`idevicesyslog`, `xcodebuild`, `USER_TAP_NOW`, or any manual tap. Consequently
there was no SpringBoard close action, native `DidStop`, terminal checkpoint,
or other terminal proof. Unconditional cleanup passed, both target bundle IDs
and their processes were absent, and the archive is explicitly a
`preprompt_wrapper_failure`: it is non-product evidence and not a Plan 243
close result.

The first corrected offline wrapper remained outside the repository at
`/tmp/pip243_manual_close_wrapper_v2`. Its then-reviewed package-manifest,
wrapper-source, and unit-test-source SHA-256 values were respectively
`17a72617b3b70fc3df502ceaa5e153cfc9d9aed5f39f63099a6472f7762d3028`,
`c2014c6abe453ddb01c3dfae944dae584e5fb1656715a24e813efc3cc439d30b`,
and `e4a61f0122fb36876fa348421260dbddde8065c9d24f2d338b2a59dec068f6ce`.
Its offline review passed 24 of 24 unit tests, the causal auditor's one
positive and 18 negative cases, and all 8 manifest checks. The reviewer
approved that package offline. The user then separately reauthorized exactly
one corrected bounded-manual-close attempt and replied `READY`.

That separately authorized attempt is preserved unchanged at
`/tmp/pip243-manual-close-corrected-device-run-20260713T124934Z`. Its
`evidence-hashes.json` contains 73 of 73 entries and has SHA-256
`f36fce038f29780039ec86a4cfacd9a0274b491da517abf7c576ae07da6184ad`.
Device context, clean preflight, frozen pre/post validation, app-cache
collection, and unconditional final cleanup passed. The interrupted xcresult
was retained, but its summary, tests, activities, and attachment exports each
failed closed with return code 64; no XCTest result was accepted. The frozen
v2 runner, Release AUT, App.framework, and 72-second fixture remained
byte-identical to the values recorded below.

The live AUT emitted this real unified-log configure marker:

~~~text
Runner(Foundation)[21174] <Notice>: PROBE_IOS_CONFIGURE launch=22BE2F3B-44A0-4407-877D-7DE8CEA75027 applicationState=background scenes=[unattached:windows=0:visible=0:key=false]
~~~

The consumed wrapper source
`c2014c6abe453ddb01c3dfae944dae584e5fb1656715a24e813efc3cc439d30b`
did not accept Apple's `Runner(subsystem)[pid]` process-token form. It
therefore classified the configure marker as lacking a parseable AUT PID/run
and sent fail-closed SIGTERM to xcodebuild 112.079 ms after the marker.
xcodebuild exited `-15` and retained `** BUILD INTERRUPTED **`.

The attempt stopped before `USER_TAP_NOW`. There was no manual tap, synthesized
tap, SpringBoard system-close action, native `DidStart`, native `DidStop`,
terminal checkpoint, or product close proof. Cleanup passed, both target apps
were absent, and no target process remained. This attempt is classified
`preprompt_host_parser_failure`: it is non-product evidence and not a Plan 243
close result. Its one-run authority is consumed and there is no retry.

The parser was hardened offline only after the consumed attempt. A first
post-failure package candidate identified by review prefix `3b56d…` was
rejected because payload and suffixed-process counterexamples could be
misclassified. The final offline-only candidate has these SHA-256 values:

- package manifest: `76606d1e6c6b08dcae4b3c156eae8a4abdb790179c9613973abeaa3638d9db49`;
- wrapper: `d5839e36978cd4046be7531f831c1ca8d0e6ff700187a69c84c12f6aa594e7e1`;
- unit tests: `5e272350e88fc7b44e1c807aa0ed2eadef50bdc061f94466612ec057d86e3368`;
- causal auditor: `4abc6077272862a966670e444d63e67a2d693d549b04a55841fda14544796d86`.

That candidate passed 27 of 27 unit tests, the causal auditor's one positive
and 19 negative cases, an independent matrix of 8 valid and 24 invalid process
tokens, all package-manifest checks, and its before-query self-pin/revalidation
contract. It was offline-approved only and did not itself grant another live
attempt. The user subsequently issued a separate third one-run authorization
and replied `READY`.

That third authorized attempt is preserved unchanged at
`/tmp/pip243-manual-close-authorized-device-run-20260713T132700Z`. Its
`evidence-hashes.json` has SHA-256
`e6b782f1ed8b2402bbb15ca92138551e306c997c149e61a1e9d5547876d10d9a`
and accounts for all 127 of 127 non-manifest archive files with no missing or
extra file. The invocation pinned and verified package manifest
`76606d1e6c6b08dcae4b3c156eae8a4abdb790179c9613973abeaa3638d9db49`
and wrapper source
`d5839e36978cd4046be7531f831c1ca8d0e6ff700187a69c84c12f6aa594e7e1`.
Clean preflight, frozen pre/post validation, app-cache collection, and
unconditional cleanup passed; both target apps and all target processes were
absent afterward, and the frozen inputs remained byte-identical.

The live native owner emitted one `PROBE_IOS_PIP_DID_START` for
`system_close-session`. The exported `system_close-controls-visible` image
visibly contains the real close X, and XCTest's initial exact enumeration found
one visible/hittable `Close Picture in Picture` button. The frozen v2 XCTest
source
`ef24a8959f273fa0941ec0727fbf519ff0936ae454e212309cc562c5e69a199b`
then retained the transient `XCUIElement` and queried `closeControl.label` while
formatting its proof marker. After the controls auto-hid, that post-proof
property lookup re-resolved SpringBoard and failed with `No matches found for
Descendants matching type Button`. xcodebuild exited naturally with code 65
and retained `** TEST EXECUTE FAILED **`.

The attempt never emitted `USER_TAP_NOW`; there was no human tap, synthesized
terminal tap, system-close action, native `DidStop`, post-prompt terminal
checkpoint, restoration, or scenario PASS. The durable checkpoint value 3830
is the pre-action native-handoff checkpoint and is not a terminal checkpoint.
The xcresult was partially collected but remained overall `FAIL`: summary and
tests passed collection, all 12 attachments passed export, and only activities
failed with return code 64 because the v2 collector omitted the required
`--test-id`. This consumed attempt is classified
`preprompt_xcui_postproof_lookup_failure`; it is non-product evidence, not a
Plan 243 close result, and its one-run authority has no retry.

Remediation after that failure was prepared offline. The reviewed runner v3 at
`/tmp/pip243_bounded_manual_close_runner_20260713_3` converts one exact
SpringBoard observation into an immutable scalar descriptor, performs no
post-proof SpringBoard lookup, binds generation 1 and a 0...250 ms
sample-to-prompt age, permits only the exact allowlisted nonterminal
`PIP-SBInteractionPassThroughView` reveal, and contains zero terminal
automation. Its frozen SHA-256 values are:

- package contract: `1bb39f0bb2f17e04e16ed217c401501bc02b606dc3ea2aec09fb7a719412c7b0`;
- artifact manifest: `6151c27c0a1d0c598a482be37897de70d9757fc551d63646aedba8f8a34064bf`;
- bundle-manifest file: `7335115e5ec871149f8fd6ea94e8896b231095f08e2d6a01db37a96c32b3cf16`;
- xctestrun: `dcc8abbc805a42f7473254453e7bc129fde0e50278a3da8c72ce16745579205a`;
- reviewed source: `c472a38377e673506904e0847e449a67047f5c56d5f9d7e3d6ef1e351a067c8f`;
- runner executable: `b9e1c885cffd9d2b0cdfeda235175c1c0cbc4dd286c538e43efb19eda16b02ce`;
- nested xctest: `c6991d8065416206ead5fcfea5a237016771ae689e9535cd4ff99ec1af186c24`;
- 42-file runner tree: `8fffdd24aff8f6108f383af8f9aff01085fb891417e41dc889f09537a8b79be9`;
- 42-file reviewed manifest: `150ce9d287f586c85a4580b0cb8274707efc869b324df0a1c60d6bc0b5495e2a`.

The first wrapper-v3 candidate package-manifest pin
`eb223726d26bfea4e2190bc9acd904603489d457fc7e002da5ad31d5f2282431`
was rejected for a prompt-contract mismatch and an open package manifest. The
next package-manifest pin
`b6cbd583ddfbf467dcb5c2bb6adac59164f10b64e8f46ae4b8f10a28c0c02d3b`
was rejected for same-line duplicate-marker acceptance and a configuration
TOCTOU. The final offline-approved wrapper at
`/tmp/pip243_manual_close_wrapper_v3` has these SHA-256 values:

- package manifest: `1e70473cd0ae85e8a465578dce3834609f63727200868eb58cf71695085266fe`;
- frozen config: `6f2b47ca90507a044196b0922ad75c57e642bb775e0a804c8b887d0d9ce0e230`;
- wrapper: `9b5b5c82834b6f892a5ea9c395aedeee48107513e153f31a8851e9176b4235f4`;
- sealed launcher: `33318051794d86c31dd6e3cdefff526b1dba44550b8f4b2a89d1e6a6fbd60485`;
- unit tests: `8e3458f2ba8f92bf588a985375c8d856deaf8973a5033f72304e54db22994d09`;
- causal auditor: `eead0b1c069e3171abbd16a4856647aebfdb30d4d69ef0a4930374b78ebe65ea`.

That final package passed 41 of 41 unit tests, the causal auditor's one positive
and 35 negative cases, and the independent attack matrix. It is sealed and
closed-world, eliminates the config TOCTOU, and fixes xcresult activities
collection by supplying the exact test identifier.

The user then separately authorized exactly one fourth bounded-manual-close
attempt using those frozen v3 inputs. That attempt is preserved unchanged at
`/tmp/pip243-manual-close-authorized-v3-device-run-20260713T152000Z`. Its
`evidence-hashes.json` has SHA-256
`3e82b7dc4160ec09439a15d3e98ead3589bb0e21caf214b92adef7504db1ffc1`
and accounts for all 131 of 131 non-manifest files with no missing or extra
file. Independent synchronization review rehashed every entry and checked every
recorded byte size with zero mismatch.

The live native owner emitted one `PROBE_IOS_PIP_DID_START` for
`system_close-session`. The sole synthesized SystemUI interaction was the exact
allowlisted nonterminal `PIP-SBInteractionPassThroughView` control reveal. The
frozen v3 XCTest source then called `proveManualCloseControl` at line 90; its
line-342 predicate was:

~~~swift
NSPredicate(format: "label == %@ AND hittable == true", exactLabel)
~~~

XCTest rejected `hittable` as an invalid predicate key with
`XCTElementQueryInvalidPredicate`, and xcodebuild exited naturally with code 65.
The attempt never emitted `USER_TAP_NOW`; there was no human close tap,
synthesized terminal tap, SpringBoard system-close action, native `DidStop`,
terminal checkpoint, restoration, or scenario PASS. This is a pre-prompt
XCUITest invalid-predicate failure, not product close evidence.

Clean preflight, frozen pre/post validation, app-cache collection, and
unconditional cleanup passed. xcresult summary, tests, activities using the
exact `--test-id`, and all seven exported attachments collected successfully.
Both target apps and all target processes were absent afterward, and the frozen
inputs remained byte-identical. Runner v3 is therefore byte-trusted but
runtime-rejected; it must not be run or mutated again. Its fourth one-run
authority is consumed with no retry or future live attempt authorized. The
prior return PASS archive is unchanged. At that historical point,
physical-iPhone close remained FAIL/unproved, production remained unauthorized,
and the status was `decision_required`; the later Path 3 decision above
supersedes only that product disposition.

#### Offline corrective package audit v4 — rejected without live execution

A subsequent versioned, read-only audit evaluated the v4 corrective packages
offline. No physical device was queried or driven, no prompt was surfaced, no
tap or other live action occurred, and no fifth live attempt was made. This
audit created no execution, retry, rollout, or production authority.

The simulator-only XCTest predicate-grammar proof at
`/tmp/pip243_xcui_predicate_grammar_probe_20260713_2` passed with one test
passed, zero failed, and zero skipped. Its exact eight-file evidence-manifest
SHA-256 is
`93e123d01d56d0b6570da6f50b92b4648bb98ba9f2f7ea05a13e967f0a3310e7`;
the result bundle contained exactly 32 reviewed files and exercised all six
required predicate forms. This proves only the predicate grammar and does not
prove a physical-iPhone prompt, control, tap, postcondition, or close.

The runner-v4 package at
`/tmp/pip243_bounded_manual_close_runner_20260713_4` passed its offline
byte-integrity review: all 48 full-package files and all 42 runner-app files
were present, with no symlinks or unreviewed extras. The reviewed integrity
anchors were:

| Runner-v4 artifact | SHA-256 |
|---|---|
| `PACKAGE_CONTRACT.md` | `4fcbe0cd042b032c130d4b8278062e184c4d102d1c0de63cc7d9c38396145a42` |
| `ARTIFACT_MANIFEST.sha256` | `55cc62507fa61e7418ab49354da019a4aa423667ba7997d09c5f98c2341320b9` |
| `PACKAGE_BUNDLE_MANIFEST.sha256` | `00173156b42245034fdc21a6f41b86af9767d35ac604806a42d420b2d64ba34a` |
| `.xctestrun` | `82336020ffdc1e1dd379a119b8d21adb1b2d3122d45195b3ed61b6edf74be5ad` |
| `Products/Release-iphoneos/RunnerUITests-Runner.app/ProofSources/ReceivedVideoPictureInPictureUITests.swift` | `9a6670d4cc3bf4f6fdd1fdd8b37bebbe34df3fd6fc1151b043f29707b0b28d59` |
| runner executable | `d5bb65cb44f9673fa8da34e980d2167a938032bb47911a7be06da4b2594e475d` |
| nested `XCTest` binary | `adcf0c6df2d263de7fc5e2649125088da987f7faa01f9a545414b7c5344e5de1` |
| 42-file runner-tree digest | `5c827c6995e422aab6c597902d88cbadee3b7058d656240521600712e24a7024` |
| 42-file reviewed absolute-path manifest | `5fd9b079b1e09b46a8b978fa0c9b36e8154c75daa495943170eade1e725aabc1` |
| 48-file audit-manifest file | `82ec61dc4f81fbaac439dde64ee873c7c839c0cd5653612d47e43241d7b96111` |
| build log | `5a7875ddb41b315e3677aab0afe5676f048986c3b0f3ca5dcf3dbf037988f7eb` |

That byte integrity does not make runner v4 acceptable. Its source performs
the bounded reveal and exact scalar proof, but after that proof returns it
resumes AUT XCUI access: `waitForStatus` at lines 131-138 and 163-177,
additional `descendants`/`matching`/`firstMatch` queries and
`label`/`value`/`app.state` reads at lines 192-225, and `app?.terminate()`
during teardown at lines 44-46. Those operations violate the governing
zero-post-proof-XCUI boundary. Runner v4 is therefore rejected offline and has
no live-use authority.

The wrapper-v4 package at `/tmp/pip243_manual_close_wrapper_v4` is also
rejected as unsealed. Its `PACKAGE_MANIFEST.sha256` retains the v3 manifest
file SHA-256
`1e70473cd0ae85e8a465578dce3834609f63727200868eb58cf71695085266fe`,
while five protected files have changed:

| Mismatching wrapper-v4 file | Manifest SHA-256 | Actual SHA-256 |
|---|---|---|
| `causal_auditor.py` | `eead0b1c069e3171abbd16a4856647aebfdb30d4d69ef0a4930374b78ebe65ea` | `a5a348a4be62381029b28a7eec4190bc181b44bbc2b5e1dcbdd65461a647710c` |
| `contract.py` | `6b31c95f283817de60f4734ae78742bead10ad64e7a5f595608272d5ae21e02a` | `ad6f7de5bd8b2a0eddf18a152305fba9f37e6f99daf6925aff936315229220be` |
| `fixtures/retained_real_results.json` | `bd6d7f9b5f4a677762798814721786afcb5e77674c1e3768c9915192ed0144e5` | `b55c5ce0511853fd09ff61f6c3d2cf904db1569c0877f1ef7c31bd77888c29dc` |
| `frozen_config.json` | `6f2b47ca90507a044196b0922ad75c57e642bb775e0a804c8b887d0d9ce0e230` | `237596f04d5d3e9bcbb077528d0500b9cc0b0c251ce7795b795667018a9c0cac` |
| `manual_close_wrapper.py` | `9b5b5c82834b6f892a5ea9c395aedeee48107513e153f31a8851e9176b4235f4` | `783878ed7933e828ab28606e971328237b50835a69df7c6f45acd3d7eaa7a20b` |

The sealed launcher consequently aborts before imports with
`SEALED_LAUNCHER_FAIL package hash changed: causal_auditor.py`, and the wrapper
unit suite cannot import through that seal. Syntax and `tabnanny` checks
passed, and the auditor self-test passed its one positive and 35 negative
fixtures, but those isolated checks do not repair the seal or establish
package acceptance. The v4 README is byte-identical to the stale v3 README
(SHA-256
`205e5aaf1b194d8dbfc79fd8fc6962103e4a5fa23c47eb1af47ea45bb0583558`)
and still documents v3 paths and commands rather than the reviewed v4 package.

The offline/adversarial audit output contains only nine inventory/manifest
artifacts and no consolidated final acceptance report. Accordingly, the
grammar proof passed, runner-v4 byte integrity passed, and limited auditor
checks passed, but combined v4 acceptance remains incomplete and the runner
and wrapper are rejected for the independent defects above.

The retained v3 baselines and the reviewed v4 packages remain immutable
rejected lineage; immutability is not acceptance and neither lineage may be
repaired in place or executed. There was no fifth live attempt, no new user
act, no prompt/tap/close proof, and no remaining authority. At that historical
point TC-243-00 remained `decision_required`, and production remained frozen
and unauthorized; the later Path 3 decision does not reclassify these facts.

#### Offline corrective package audit v5 — runner accepted, wrapper causally rejected

The next versioned audit was also offline only. It did not resolve, query, or
drive a physical device; launch an AUT; start `idevicesyslog` or `xcodebuild`;
surface `USER_TAP_NOW`; or perform a tap or other live action. It therefore was
not a fifth live attempt and created no execution, retry, implementation,
rollout, or production authority.

Runner v5 is frozen at
`/tmp/pip243_bounded_manual_close_runner_20260713_5`. Independent rehash and
source/signing review passed its closed package of 52 regular single-link files
and 22,893,343 bytes, its 42-file/22,556,726-byte runner-app tree, reviewed and
embedded Swift source, xctestrun, executables, build provenance, code-signing
identities/CDHashes, and embedded provisioning profile. Its manual-close method
puts all UI work in `collectPreBoundaryEvidence()`. After the unique
`guard let evidence = collectPreBoundaryEvidence() else { return }` boundary,
the source performs no XCUI query, property read, action, reacquisition,
screenshot, state inspection, or teardown access. It emits only the four
scalar markers in this order:
`PROBE_XCUI_MANUAL_CLOSE_CONTROL`, `PROBE_XCUI_MODE_AGREEMENT`,
`USER_TAP_NOW`, and `PROBE_XCUI_HOST_NATIVE_TERMINAL_REQUIRED`, then holds one
inverted XCTest expectation. It contains no terminal automation or runner-
authored causal, settlement, or scenario-PASS claim; XCTest completion remains
harness transport only.

The accepted offline runner-v5 pins are:

| Runner-v5 artifact | SHA-256 / immutable value |
|---|---|
| full 52-file package tree | `e8f49cfc5dc0bd827459783f14b42656549a02bbabb323f8f374cc0c7c1b9b47` |
| full-package relative manifest digest | `7b23e13abb684eeb75c4ffd7469d7b74f04e124618d59f1179cfc82232ecb7aa` |
| `PACKAGE_CONTRACT.md` | `33f24fbf9ab3b2398eba82ab71c76cc5976d35080890e6ca6398fda665ea2755` |
| `RUNNER_ARTIFACT_MANIFEST.json` | `5cd37704d5476d24b93290887837eb4b7ac9c33611222d9531f955d833ea8c34` |
| `RUNNER_BUNDLE_MANIFEST.sha256` | `22303adeef86dbd307cae927d8e94279679aaeaf518b3ed247920cd9778c62c5` |
| `RUNNER_REVIEWED_MANIFEST.sha256` | `91de1b378453f45d976d209edc07f5126b410060bcf2943924fb92092bac3955` |
| `RUNNER_TREE_MANIFEST.json` | `f24a90f77bc14e7a8514ce1119eac1eacf60a01a0b320aca0ddf467de4a034a0` |
| `ReceivedVideoPictureInPictureUITests.swift` | `cb78752cda2d4c78e79d18efbc8d4aebe539eb72ab2c503da0d01f085d374e7a` |
| bounded-manual-close xctestrun | `636fc6c776ba304f691553e4b945189317b4a5618447add3e4e03ca1229e974c` |
| 42-file runner-app tree | `6bfe106cdc28e8b8e0df275ca693fa2f01bd0577581a0048d5741c03f1473a73` |
| runner executable | `70c4b89d4044b883392fd6b21b82eb5c797e7f925080d02d7426f6e16586dbfd` |
| nested XCTest executable | `a9906efb4def2d95175fbac6502f83843384c761fb07b7f1b194a2fb89127dc5` |
| manually compiled XCTest object | `1ce2c1b891aac86e73362429789634e8b865cf787122c1b162282ae60f0071e2` |
| unsigned manually linked XCTest | `9db12a168b8848f6d7ded00876e1a134c4ddd82650c20d93233412c5391de6af` |
| runner dSYM DWARF | `99611884a0d3fe2a82b4c062fa7c3c08be519d502fb63353bac28698be3fd6bc` |
| runner binary/dSYM UUID | `7E4A46BC-967A-3716-9B39-8D3B7FE11FDA` |
| runner / XCTest CDHash | `f8addf0aa649fbb250f714a83bbf4b7ff5f24081` / `6b072a4f89f27d1c3b1a22ed5e4cd02c46a688e2` |
| runner embedded profile / UUID | `fa0b48332f3342488596a878b00ae038e9d9b44a4d3220f44fd08240703de0ce` / `f5f34d01-1ccd-403e-8cee-a74a79e0e9d1` |
| `STATIC_AUDIT.json` | `b2984456d4fbfa477119f12708b08e5155e219a1434dff56f638993d743c2998` |
| `LINEAGE_PRESERVATION.json` | `44c48e06268cd66c873fae8af4f09c8f5bcc1189bcef650d73d54a6122f2c5f2` |
| final clean generic-iOS Release build log | `9cf836ae4c86836dfe88a69bdc5a17329565bb7478154c4030ea2042b624f54a` |
| predicate-grammar evidence manifest | `93e123d01d56d0b6570da6f50b92b4648bb98ba9f2f7ea05a13e967f0a3310e7` |

The runner still binds the exact 72-second fixture
`d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5`,
Release AUT executable
`6f2dc51e43ad4f64be603954f300f02c2e7a818e1b3efe4014be7da916bd5bb5`,
and App.framework executable
`1c10a52ff4b63e2b26dcac9f3a134070f99be759377b7296f88456631575e5a9`.
This byte/source/signing PASS accepts runner v5 only as a frozen offline input;
it does not establish a prompt, tap, terminal event, system close, or live-use
authority.

Wrapper v5 is frozen separately at
`/tmp/pip243_manual_close_wrapper_v5_20260713_1`. Its structural seal passed:
the manifest contains nine sorted entries and excludes itself, the sealed
launcher enforces the externally published manifest hash and Python `-I -B`,
and the closed-world checks reject unmanifested files/directories, symlinks,
hard links, bytecode, and changed snapshot metadata. Syntax and `tabnanny`
passed; the package-reported causal self-test completed one positive and 41
negative fixtures; and all 42 unit tests passed. The exact wrapper-v5 pins are:

| Wrapper-v5 artifact | SHA-256 |
|---|---|
| `PACKAGE_MANIFEST.sha256` | `61e25c00cc631d45a317acc0d9aa353701be65fb54bcaaf0e48c680bd6514d74` |
| `README.md` | `316074e807750a2dfb8f0d771e4d3519a61f644c49502fd55b3c1835b7b9026f` |
| `causal_auditor.py` | `1399a69450fe88c4ddec915cb292dd283d24026bb58cf56abcfa041517216256` |
| `confirm_manual_tap.py` | `1d7676f1bc80f4627c4a4921f22fcdd467c09d333ed21bdc5a5dd72a729d8bf5` |
| `contract.py` | `5fe8a7ce7c9371362bab0276593f205e79e14a90f6ad604c0f2683f5788fc1a9` |
| `fixtures/retained_real_results.json` | `b87ab5600469ac78009564b318396f56694bb0a88c119878ef751985358e4140` |
| `frozen_config.json` | `490024e73aab801caa00bc2037203750a42c234eb098d6a3ddff5b7747713776` |
| `manual_close_wrapper.py` | `66a5ec11aba63934ed57548a22ba485625ae5253471d422e7e594c1c4becd81b` |
| `sealed_launcher.py` | `33318051794d86c31dd6e3cdefff526b1dba44550b8f4b2a89d1e6a6fbd60485` |
| `tests/test_manual_close.py` | `c210638b7b900fd474299a493355bc523d876eed710da06e78fe89b03eab3215` |

Those structural results do not make wrapper v5 causally acceptable.
Independent counterexample review confirmed false PASS results when the
otherwise passing evidence had `host_confirmation=None`, when the raw
`device-syslog.log` content was empty, and when the native-DidStop and terminal-
checkpoint ledger `line_sha256` values were absent or zero. The auditor treats
host confirmation as optional, does not positively require or parse the raw
syslog as the source of the terminal pair, and does not require the two ledger
line hashes or resolve them back to raw syslog bytes. Its own synthetic positive
fixture omits both terminal line hashes. Cached native/Flutter settlement logs
plus unbound ledger fields can therefore satisfy its claimed host-owned causal
proof without the required host-stream evidence.

Wrapper v5 is consequently **causally rejected** despite its structural seal.
Its frozen config explicitly retains `live_execution_authorized=false` and
pins the pre-v5 decision SHA
`ff926b04099a9535487e980cf3723c34d16017d25a87fdde299a49be7594ad08`;
neither the structural tests nor the rejected causal self-test can change that
state, and this synchronized decision no longer matches that old pin. Runner
v5 remains independently accepted and frozen only at its offline
byte/source/signing boundary; wrapper v5 remains frozen and rejected. All v3,
v4, and v5 artifacts are immutable, no corrective successor is claimed here,
and none of this offline work is a fifth live attempt or a new authority.
TC-243-00 iOS close remains unproved. At that historical point the decision was
`decision_required` and Plan 243 production was frozen; the later Path 3
selection authorizes only the Android production scope.

The following iPhone 13, remote-Accessibility, and pre-final XCTest accounts
are retained as historical diagnostics only. They are superseded for the
controlling result by the final authorized Release run above.

#### Earlier iPhone 13 retained-prompt diagnosis

The first Profile probe build caused iOS to retain a Local Network permission
sheet for `com.mknoon.app`. The sheet persisted through uninstall and a clean
install of the verified Release probe even though its effective `Info.plist`
contained none of `NSBonjourServices`, `NSLocalNetworkUsageDescription`, or
the `_dartVmService` keys. Remote Accessibility enumerated the exact sheet as:

- label: `Allow “Mknoon Pip Probe” to find devices on local networks?`;
- button index 5: `Don’t Allow`;
- button index 6: `Allow`.

The least-privilege exact `Don’t Allow` ActionTap returned
`action_tap_sent`, but the sheet remained. One isolated launch of the Release
AUT as PID 6098 then established the causal disposition from syslog:

- CoreLocation's
  `com.apple.corelocation.CoreLocationMapLNPromptPlugin`, PID 1990, remained
  `running-active-Visible`;
- SpringBoard retained its focus lock and `SpringBoardOnly` selection policy;
- the AUT itself was `running-active-Visible`, registered its scene, obtained
  the external foreground handle and key window, and had Foreground
  visibility;
- despite that OS visibility, Flutter remained
  `applicationState=inactive`/`foregroundInactive` for all 60 attempts over
  15 seconds, so the probe failed closed before any handoff;
- a transient app-switcher deactivation assertion was removed at
  09:54:05.794930 and was not the cause;
- no player, native handoff, PiP session, or PiP AX element was created in
  this diagnostic.

An isolated go-ios userspace tunnel also connected an Instruments app-state
listener, launched the exact AUT once, and received zero app-state
notifications. That route was typed `no_app_state_notification`; the listener
and tunnel were stopped and their host ports were gone. The retained system
sheet, not app-owned foreground or PiP logic, therefore made this phone
unsuitable for the final SystemUI actuation audit. It is a diagnostic
disposition, not a product return/close result.

#### Earlier clean iPhone 11 target and exact probe sequence

The second target was the wired physical iPhone 11 at UDID
`00008030-001A6D2801BB802E` and CoreDevice ID
`5763A494-757C-5B37-AC70-3AA2775FBEFF`: model `iPhone12,1`, iOS 26.5
(`23F77`). It was booted, paired, tunnel-connected, Developer Mode enabled,
unlocked since boot with `passcodeRequired=false`, display active, and had a
usable Developer Disk Image. An exact pre-install query for `com.mknoon.app`
returned an empty list.

The already-existing embedded development profile was inspected before use:

- profile SHA-256
  `89a38df7d60edf7384055626064ae5adf56b063146ca3457a0a2d28a3ecffcdb`;
- UUID `4e7c6235-6461-4278-912c-ba0154d14a98`;
- application ID `397R9Q4WMX.com.mknoon.app`;
- `ProvisionedDevices` exactly
  `[00008110-00184D622289801E, 00008030-001A6D2801BB802E]`.

Deep and strict code-sign verification passed for identifier
`com.mknoon.app` and team `397R9Q4WMX`. `Flutter.framework` reported
`BuildMode=release`. The effective `Info.plist` contained no Bonjour, Local
Network, or `_dartVmService` key or value. Executable hashes were:

- `Runner`:
  `bb38c72b8cb33e9cb3008acd4cdf6f870998bc84f89403e6a6f846a2007318ad`;
- `App.framework/App`:
  `d08edd3f0c33b950c34cc6191f074eff7e159545a896d21ea3fddb57403a0cdc`;
- `Flutter.framework/Flutter`:
  `d12b597975a9d7f1408c20ef6b14a39085471fc93f2bbfa3a529b420b3c3c9d2`.

One exact install and one non-console activation produced no permission prompt.
The app-owned trace reached `PROBE_FOREGROUND_ACTIVE attempt=0` with an active
foreground scene and one visible key window. The real Flutter owner handed off
at 3894 ms; native AVPlayer exact-seek observed 3894 ms, emitted nativeReady
and DidStart, and settled at `awaiting system_return`. This clean launch is the
starting state for every remote-Accessibility conclusion below.

#### Earlier remote Accessibility helper chronology

Every helper used pinned go-ios v1.2.0 at commit
`bd51cfbe6f8d00bce04464e12f14e969b2046669` with Go 1.26.4. The original
pre-v2 constructor/selector attempt exposed no remote selector and hung. v2
made the retained iPhone 13 prompt visible. v3 corrected the helper to use
`accessibility.New` with a notifier and guaranteed `TurnOff` before `Close`.
These corrections changed only disposable proof tooling outside the repo.

The first delayed v3 iPhone 11 enumeration began 22.8 seconds after DidStart,
returned no elements, and timed out on its first move. It sent no action and
ran its cleanup. The first automated wrapper then had a host-monitor defect:
`idevicesyslog --process Runner` was started before Runner existed and captured
zero lines. The copied device-owned traces nevertheless proved foreground,
DidStart, and `awaiting system_return`; no AX session or action had begun. The
wrapper was corrected to monitor content rather than a not-yet-existing
process.

The corrected immediate v3 run started AX 0.507 ms after its marker and
completed one enumeration generation. It exposed exactly two elements:

1. `PIPUIView`, label `Video`, spoken hint
   `Video, Starts Media Session, Double tap to toggle controls`;
2. the Flutter status element.

No exact return button was present. The runner sent stop, performed no action,
and completed `TurnOff`-then-`Close` cleanup.

v4 made the intended dependency explicit and passed offline unit, vet, and
race checks. Generation 1 required the sole exact `PIPUIView`/`Video`/spoken-
hint match and tapped only that fresh live token. After a fixed 150 ms delay, a
fresh generation exposed the same two elements in reverse order and no exact
return control. The terminal selector rejected the generation, sent no
terminal action, and cleaned up. Thus the toggle ActionTap was an input event,
not proof that SystemUI exposed or completed return.

v5 added an exact one-action invariant, bounded polling, fresh-token and stale-
token rejection, and ambiguity ordering. Its Go tests, vet, race check, Python
compile, and runner self-test passed before the device run. Stage 1 issued
exactly one ActionTap against the sole live PiP video token. The helper then
polled all processes (`targetPID=0`) at approximately 100 ms intervals for no
more than three seconds. A PerformAction response or element callback was not
treated as completion.

The terminal poll ran 28 fresh generations, generations 2 through 29, over
exactly 3.002 seconds. Attempts 1 through 27 repeatedly exposed only the PiP
video element and Flutter status element; attempt 28 reached the deadline with
a first-move failure. No exact return or expand control ever appeared. The
machine-readable result was:

~~~text
stage1ActionTapCount=1
terminalActionTapCount=0
failure=terminal_control_poll_timeout
cleanup=turn_off_then_close
~~~

The runner therefore failed closed and issued no terminal ActionTap. The close
leg was not run because its required return-control dependency had not been
proved. v3, v4, and v5 source, test, binary, runner, trace, action-rejection,
timeout, and cleanup hashes are pinned in `Proof artifact hashes` below.

#### Earlier XCTest and provisioning/account disposition

This subsection records the pre-sign-in infrastructure boundary only. It does
not describe the final authorized run: the user subsequently signed in to
Xcode, Xcode created the managed wildcard runner profile recorded above, and
the user enabled UI Automation on the iPhone 11.

The first route used one disposable XCTest runner as the signed application
itself because the exact existing `com.mknoon.app` profile was the only
available development profile. Xcode generated the no-AUT xctestrun contract
with `UseUITargetAppProvidedByTests=true` and no `UITargetAppPath`; the sole
test constructed only `XCUIApplication(bundleIdentifier:
"com.apple.springboard")`. The runner linked the real Flutter engine and
video-player plugin, passed deep/strict code-sign verification, installed as
`PiPProof-Runner` with bundle ID `com.mknoon.app`, and launched as PID 6060.
Testmanager then stopped before the test method after 64.444 seconds:

~~~text
Failed to initialize for UI testing
Timed out while enabling automation mode
~~~

The xcresult contains one system failure, zero passed tests, and no executed
scenario method. There was no retry. The runner was uninstalled and an exact
post-uninstall app query is empty.

The second route restored the normal AUT plus unique UI-runner topology. The
disposable target's missing `PRODUCT_NAME` prerequisite was corrected, runtime
mode selection was confined to the test AUT launch environment, and an
unsigned `build-for-testing` compiled exactly these two tests successfully:

- `testSystemReturnRestoresPlayingFlutterOwner`;
- `testSystemCloseRestoresPausedWithoutAutoResume`.

The single authorized automatic-provisioning invocation used
`-allowProvisioningUpdates` but no device-registration flag. Xcode identified
the exact runner application ID as
`com.mknoon.app.RunnerUITests.xctrunner` and the embedded test bundle as
`com.mknoon.app.RunnerUITests`, then stopped in provisioning input resolution:

~~~text
No Accounts: Add a new account in Accounts settings.
No profiles for 'com.mknoon.app.RunnerUITests.xctrunner' were found.
~~~

A secondary disposable-scheme diagnostic also reported that `RunnerTests`
had no development team. It did not supersede the decisive no-account/no-
runner-profile failure. The build, install, and tests never started;
`totalTestCount=0`. No login, 2FA, account, certificate, device-registration,
or production-signing action was attempted. Before and after inventories have
the same six profile paths, UUIDs, application IDs, expirations, and SHA-256
hashes; the profile diff is empty and both code-signing identities are
unchanged. No runner profile was created or downloaded, so no local profile
removal was necessary. Both `com.mknoon.app` and the unique runner bundle are
absent from the device.

The XCTest outcomes are typed infrastructure dispositions, not SystemUI
evidence. The completed remote Accessibility audit is likewise only a bounded
host-control capability result: it proved one exact toggle action and proved
the absence of an addressable return/expand control in its bounded poll; it did
not execute or prove return or close.

#### Final device and artifact cleanup

After the final return and close selectors, exact queries found neither the AUT
nor the XCTest runner on the iPhone 11 and found no target process. The frozen
xctestrun, AUT executable, XCTest runner executable, XCTest bundle executable,
bundle-file manifest, and fixture remained byte-identical after both legs. The
two signing identities and seven provisioning profiles were unchanged from the
final preflight. No production, native, shared, test, discovery, fixture,
localization, or project file was changed by this evidence run.

The available final evidence is complete at this boundary. Return passed;
close failed before actuation. The bounded-manual-close path was selected, but
all four separately authorized one-run attempts were consumed by pre-prompt
host/XCTest failures. None produced a human tap, system-close action, or product
close evidence, no retry or future attempt is authorized, and the exhausted
path is not permission to reinterpret the failed close leg as passed.

## Selected user-authority path and execution closure

The user selected **Path 3 — Android-only, fail-closed iOS**. It supersedes the
earlier exhausted Path 1 for product scope:

1. **Bounded manual close — historical and exhausted.** All four one-run
   authorities were consumed by the recorded pre-prompt failures. No retry or
   future live iPhone attempt is authorized or required, and TC-243-00 iOS close
   remains FAIL/unproved history.
2. **Explicit implementation-only deferral — not selected.** No deferred iOS
   claim or later physical-iPhone release gate remains.
3. **Android-only, fail-closed iOS — selected.** Android implementation and
   production closure are authorized under the exact matrix above. iOS PiP is
   intentionally unavailable and must pass its negative host/widget/static
   contract. This grants no cross-platform, iOS, or Apple-platform PiP claim.

The v3/v4/v5 runner and wrapper results remain immutable historical evidence.
Runner v5 retains only its independent offline byte/source/signing acceptance;
wrapper v5 remains causally rejected. The unfinished unsealed wrapper-v6
staging lineage is also rejected and offline-only. None grants live authority,
and none is needed for Path 3. Android implementation, focused and preservation
gates, iOS fail-closed negatives, the production-source Android physical proof,
and the separately owned Wave-3/final-rollout `host-all` coverage are now
closed below. Both aggregate closures use the user's explicit segmented-resume
authority; neither is represented as a single uninterrupted invocation.

## Android implementation and physical closure — 2026-07-14

This section is the execution authority for Plan 243 and supersedes predictive
wording such as “proposed”, “absent”, or “future production-app proof” in the
historical planning record below. The selected product contract remains Path 3:
Android-only PiP, with iOS and other platforms hidden and fail-closed.

### Reconciled implementation behavior

- The typed viewer owns capability visibility, localized start-failure UX, the
  current video playback adapter, and exact-item restoration. An authorization
  reload error hides the control and touches neither playback nor native code.
- Direct revocation authority is the merged typed stream of current-message
  changes, `DirectMessageRemoval`, and
  `MediaAttachmentAuthorizationChange`. Group/announcement authority merges
  listener changes, `GroupMessageAuthorizationChange`, and the same typed
  attachment stream. Stream errors fail closed; a 250 ms poll remains only a
  backstop.
- Direct and group Shared Media continuation pages are re-qualified before
  becoming viewer pages. A failed current-row reload removes the stale parent;
  continuation paging cannot inherit authority from an earlier page.
- `MediaPictureInPictureController` serializes start, native events, terminal
  settlement, and checkpoint coalescing. Authorization loss advances a fence
  and issues a priority once-only stop, so an already queued enter or checkpoint
  cannot regain authority. Dispose waits for the operation barrier and priority
  stops before disposing the gateway.
- Android owns one non-exported, video-only
  `ReceivedVideoPictureInPictureActivity`; `MainActivity` remains non-PiP.
  Engine cleanup is routed through
  `PictureInPictureEngineCleanupCoordinator`, and process recreation has no
  path/session replay.

### Final coherent physical matrix

Evidence root:
`build/received-video-pip-proof/final-coherent-20260714T072110Z`.

The explicitly pinned target was physical Pixel 6/oriole
`21071FDF600CSC`, Android SDK 36, with
`FEATURE_PICTURE_IN_PICTURE=true`. Every scenario used the reviewed 72-second,
2,463,571-byte fixture with SHA-256
`d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5`.
The build used disposable debug ID `com.mknoon.app.pipproof` and signer
SHA-256
`8a6186ce9e753686790f1dc8df3fb50f51f3fbbf39ac2b7b114d6bfff29ffd20`.
It compiled the production viewer, gateway, handler, Activity, and
`MainActivity` seams, but it was not a production-ID or release-signed APK.

| Scenario | Result | Host log SHA-256 | Flutter log SHA-256 | Installed app APK SHA-256 |
|---|---|---|---|---|
| return | PASS — task `871`; real Pixel-6/API-36 SystemUI expand; `restoring/systemReturn` at `11728` ms; exact Flutter owner restored playing at displayed `11000` ms; native/pinned/audio owners settled | `05be517116834debc5bdb0fc6640718d0a5d09e6b62201a850256ea4451db939` | `66fc9795bc4532bd228858d053e115084063927cfe51b40869af535b0c42162c` | `9fe6b3752121fb929af31f1082355d1ee8f06bd5db57ecd3ea4ae2d0739d1d34` |
| close | PASS — task `873`; real SystemUI close; `stopped/systemClose` at `12041` ms; restored Flutter owner paused; all audio/native/pinned owners settled | `e4abe5f7d43769a4a4796c59e0504c430850930d05b90c0fa3c97d32dac65811` | `f525d71e4bb086d0931dbb7c3d2e29ca1ef218b22d194aaa883e9a9f47bd19c6` | `85f270880d5261451c5aa8b3e4cffaf430c9dd07fe5a6b5fb408f4b09b3e708c` |
| process recreation | PASS — original PID `17168`, relaunch PID `17554`; empty relaunch and no native replay | `1195ec3e47c82ca0ba580663ee0947a474ec1e95f802f0b3d7607777fd1a6f4d` | `0f964a68657cd34ba44935caafb08689988094f7a61d42a49b60a4519d605a5b` | `ac28453adade6aad0f2a510d9a0ac25b2d7c5f8c7370446d60049b127ad392bc` |
| completion | PASS — one `completed/completed` terminal with position reset to `0`; all owners settled | `42049d74bbc3375a648b11ef05bfd07db462c2dca600d2ed37032bf6ddd7db6c` | `64856001a03170d2df74d8b25916ac3c14bc939fe1d7499bdc40fdce7903300f` | `2a3d0f5eb9e03386f33f817d33c7eae077e10bce1211b53f35bb677dcf0aedbd` |
| engine detach | PASS at the shared cleanup seam — `stopped/flutterEngineDetached` at `6367` ms; `flutterHostExit=0`, `proofControl=true`, `nativeTerminal=true`, `dartTerminal=true`, owner released | `0364a9445f23860a08d9ecef71301f6df16c8361a05263e9dc3166071a04c2f9` | `419aa95af7bdf7f3d823ce7721cba18190c66dffccda2ff6e81715f974250c7f` | `02eaeb2b1386380cffb117a3a5a3245285384b44d08e3590ebf9dc20673f7122` |
| interruption | PASS — distinct-UID helper package `.pipproof.test` obtained audio-focus gain; exactly one `stopped/interrupted` terminal at `9283` ms; cleanup focus owners `0` | `d4a7f663c6cd40c3b565985b5a738b8df3bee0a1e9609d87588d14e3c86c6757` | `43b02026a0ec6b11dd2d4564d8bdfb0f6339e90371d799f1b6226d3ce903c05c` | app `80a8c29c1a5956d794501f5ca316556e82adcedacab81981f3d158924ca3f355`; helper `85f0b579e71d935ffb28dc5a90bf05ea671699a43095ca791837b6a0d6aceec3` |

The engine-detach physical leg deliberately reports
`realCleanupCallback=false`: it proves the same shared cleanup seam used by
the real callback, not that the test process invoked Flutter's real engine
callback. Static source pins, JVM tests, and the build-boundary check prove the
real callback wiring and prove the receiver is absent from an ordinary APK.

Each physical scenario also records
`PROTECTED_NEGATIVE control=absent gatewayStart=false nativeOwner=false`.
That is a composite protected-like/unowned physical negative, not a complete
isolation of every protection state. Focused host policy/viewer tests separately
isolate private, view-once, expired, quarantined, incomplete, integrity-failed,
non-video, missing-path, and lane-denied behavior.

### Focused, curated, analyzer, and graph evidence

| Gate | Result | Evidence |
|---|---|---|
| Focused Dart PiP/native proof contract | PASS, 67 tests | `build/Plan243/final-focused/dart-pip-focused.log`; SHA-256 `4296629119a80680c5677e9caa66793e890d6a253d5dda5b8784f87a777f80f0` |
| Core/static selector set | PASS, 54 tests | `build/Plan243/final-focused/core-static-selector-10.log`; SHA-256 `ac4d4e4c9168a406993f6b0e6cb64c8804b4aab21e0e9219209a320c27d1cfbe` |
| Seven route-composition files | PASS, 362 tests | `build/Plan243/final-focused/route-composition-7.log`; SHA-256 `f852150c5a112366810b3f6312ec2ef9d6963e15575dbdacf9acd1c294a4b4d3` |
| Localization / private / preservation / Plan-228 sentinel | PASS: 3 / 20 / 45 / 1 tests, plus 4 image-viewer tests | Logs under `build/Plan243/final-focused/` |
| Android JVM | PASS, `BUILD SUCCESSFUL in 14s` | `native-jvm-pip.log`; SHA-256 `250b88b1f2557607994b8f6f389174ed13a89fe9da5134c844a658c2b31a4afa` |
| Engine/interruption build boundaries | PASS — proof components absent by default, present only in their proof variants, production ID refused | `engine-detach-build-boundary.log` and `interruption-build-boundary.log` |
| Curated `1to1` | PASS, 2064 Flutter tests plus relay Go | log SHA-256 `4a2c50618414e529d32fd0859d0c2fd4e931293cd6e0d8789c14d8d107c705fa` |
| Curated `groups` | PASS, 2172 Flutter tests plus both bridge Go, node Go, and relay Go legs | retained post-barrier log SHA-256 `bba872a1dcdd08728fec22fb3403632b68f2b8a4c7eaed4e9a820973bb24c1b3`; the earlier `+2171 -1` log is diagnostic only |
| Curated evidence inventory | PASS | `build/Plan243/closure-20260713-core-gates/evidence-inventory.txt`; SHA-256 `ed46425924ba7066c9b415747bfa40ee6cf612134ef96f75dc693360dd2adea7` |
| Plan 246 disposition | PASS: 19/19 Flutter invocations covering 21 cases, 2 Go cases, 2 structural scans, hygiene clean | `/tmp/plan246_reporting_closure_focused_20260713.log`; SHA-256 `cc938bbd96870aaf177c442e29f65c11401a03262b4345baba90a2223df0ba0b` |
| Discovery | PASS: exact ignored proof entry, zero unclassified | rerun log SHA-256 `7ba9efee5e267ba98410b146ca419e1ff5699919f9a9beaedd85687c8573d686` |
| Analyzer | ACCEPTED REPOSITORY BASELINE, NON-GREEN — canonical full `flutter analyze` exited 1 with 1,610 issues: 0 errors, 115 warnings, and 1,495 infos. Separately, scoped `flutter analyze --no-fatal-infos` exited 0 across 35 final Dart paths with 0 errors, 0 warnings, and 6 retained infos across 2 paths; that scoped result is not zero-diagnostic | `build/Plan243/final-focused/final-analyze-post-host-fixes/`; bundle manifest SHA-256 `74df203b77cbe46d1fb6d57708736a9bc6833dbbd0bf199a3a0988eda2b9942f`; canonical/scoped metadata SHA-256 `6b534b27bc0ef9fe1f3debb5e53c7ad16f039c1e948d4c268304334fdb56d76b` / `fa1ed7abfa9bc2d3f6dd676c6531002609143f411bf2ef89b32d37212f58e590`; full/scoped stdout SHA-256 `87ebe26dc473e21fa8d3b8f048d806e1d0af9afa69954de6e0bd01ad00bddf9e` / `841834cffeae2d41d29d5127db8ef86de181e918da1c69a9b337df39b306468e`; intersection SHA-256 `536d026b9393cfa139bd3b989b99f6e838846d4c148132bd0e4a14d71c5fb557` |
| Diff/discovery hygiene | PASS — `git diff --check` exit 0; 24 tracked plus 11 untracked final paths have zero whitespace/temporary-diagnostic/conflict-marker findings; 1,255/1,255 test files classified | completeness stdout SHA-256 `fb86e1bbcc46bf4b4120156913f192db0879479d0009503a6806afe032bcb965`; empty diff stdout/stderr SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Graphify | PASS — exactly one incremental refresh; refresh-time anchored architecture query fingerprint `5e41fa2ec48b2bdc` | frozen refresh-time `graph.json` evidence digest `f87295727ce4d38a073f5eeacc910d631d300f067e099cd442e7fc4d96292da8`; frozen refresh-time overlay evidence digest `f82cf1de58b1dd80435764ebf00e61d9c305ae44e9cc6bb7a9d009466841a191`. Both are scoped only to that refresh because compact queries may regenerate the live graph and overlay as query-side artifacts |
| Wave-3 aggregate `host-all` | PASS under user-directed segmented-resume semantics — preserved items 1–416 plus exact resumed items 417–1,173; resumed suffix: 749 Flutter paths, `+8291`, 0 failed, and 8/8 Go legs | `build/Plan243/final-host-gates/wave-host-all-composite/acceptance-record.md`; SHA-256 `3140017c5cca80b8712c9d5c480908b64bc7652e5825391f6925723123851198` |
| Final rollout `host-all` | PASS under user-directed segmented-resume semantics — preserved items 1–1,114 plus exact resumed items 1,115–1,173; resumed suffix: 51 Flutter paths, `+1063`, 0 skipped/failed, and 8/8 Go legs; full indexed coverage: 1,165 Flutter paths plus 8 Go legs | `build/Plan243/final-host-gates/final-release-host-all-composite/composite-acceptance.md`; SHA-256 `6df609df4f270c345c059bb53e9a9ee9ecab94f67ec6aaddd80dc8cf7fbfd6b1` |

The Graphify refresh itself exited `0` after 45.29 seconds (`34` changed,
`2611` unchanged, `0` deleted; `53542` nodes / `81763` edges; refresh-time
overlay `1354` files / `13106` tests / `988` targets). The `f8729572...`
`graph.json` digest, overlay count, and `f82cf1de...` overlay digest are frozen
refresh-time evidence only. Query-side regeneration has since produced live
`graph.json` hash `81a428e3...`; neither that live graph nor regenerated overlay
bytes are asserted as closure topology. The surrounding evidence wrapper then
hit zsh's read-only `status` parameter. That wrapper failure occurred after the
successful refresh; the graph was not refreshed a second time.

The accepted aggregate rows are composites authorized by the user's explicit
resume instruction. They are not single uninterrupted passes, and none of the
following failed or interrupted executions is reclassified as a pass:

- The first batched wave attempt planned 1,163 Flutter paths plus 8 Go legs.
  The nested completeness check exposed
  `scripts/run_test_gates.sh: line 1119: gate_args[@]: unbound variable`; the
  run was manually interrupted with exit `130`, and no Go leg ran.
- The corrected first authoritative wave attempt planned 1,164 Flutter paths
  plus 8 Go legs and reached `+3886`, `~1`, `-1`. The tone-tracker case in
  `test/features/conversation/application/chat_message_listener_test.dart:1925`
  expected two notifications and observed one. It was manually interrupted
  with exit `141`; no Go leg ran. Its host log SHA-256 is
  `92a9b5ee9de07efbdba3bbebc3884eb336cd2fee3833fc659e206808674a5cae`.
- The later Wave-3 batch used the then-current 1,172-item manifest and first
  failed at planned item 417,
  `test/features/conversation/application/link_incoming_lan_media_test.dart`,
  with `+3430`, `~1`, `-1`. It was manually interrupted; its later reporter
  state and partial Go activity are non-acceptance evidence. The interrupted
  pass-3 diagnostic likewise contributes no accepted test result; its dry run
  is used only to bind the current manifest. The still older SIGTERM/143 run is
  diagnostic only.
- The initial final-release run used concurrency 4 over the current 1,173-item
  manifest and failed at planned item 1,115,
  `test/integration/android_push_relay_registration_contract_test.dart`.
  The child `dart run` lost a shared
  `.dart_tool/lib/libsqlite3.arm64.macos.dylib` during
  `install_name_tool`, a host native-assets/cache race. Exit `1`, aggregate
  `+11709`, `~1`, `-1`, and 0/8 Go legs make that execution failure evidence,
  not a pass.

Two current test-isolation corrections are included in the accepted manifest.
The notification integration tests now await
`processIncomingMessage(...)` directly and assert its exact process state,
removing the timer/scheduling race behind the tone-tracker failure.
`FakeMediaFileManager` now keys its default temporary root by process and Dart
test isolate; four tests in
`test/shared/fakes/fake_media_file_manager_isolation_test.dart` prove layout,
same-isolate sharing, cross-isolate separation, and teardown isolation. That
new path changes the canonical inventory from 1,164 to 1,165 Flutter paths;
with the 8 Go legs, both current aggregate manifests contain 1,173 items.

Wave acceptance preserves items 1–416 and accepts the exact current suffix
417–1,173 from the successful resume (`+8291`, 749 Flutter paths, 8/8 Go).
Final-release acceptance preserves items 1–1,114 and accepts exact suffix
1,115–1,173 from the concurrency-1 resume (`+1063`, 51 Flutter paths, 8/8
Go). Concurrency 1 is the operational qualification for the native-assets
race; it changes no product behavior. The two Flutter aggregates are not added
together because concurrent scheduling overlaps the resumed suffix. The wave
resume's outer wrapper later hit zsh's read-only `status` variable only after
the gate emitted its terminal PASS; that bookkeeping error is not a failed
test gate.

## Historical iOS proof artifact hashes

The following hashes identify the controlling final authorized iOS Release
evidence run for the retained history. They are not Path-3 Android release
gates and do not override the 2026-07-14 execution section above.

| Controlling final artifact | SHA-256 |
|---|---|
| evidence manifest | 9f85c145a36d61e46fa2ee81d13a0c1762e0508e0da22ab6d6b2a92da6f7cb25 |
| 72-second fixture | d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5 |
| Release xctestrun | 849c413773339a096ac255f533811302363fc4fd1aca4bcd5913a0de53f6c8c4 |
| Release AUT executable | 6f2dc51e43ad4f64be603954f300f02c2e7a818e1b3efe4014be7da916bd5bb5 |
| Release XCTest runner executable | 860ec993186b9de276a87815a9cca54188f6916559c3d3db87ec5105334c424f |
| Release XCTest bundle executable | ca8c05c49eec91ada590ed39a576ae65a5f0bde5c406f4f6d7fe955ffd0ab2db |
| Release bundle-file manifest content | e1cf1f44a7b9d770bc1edaecf1c6e8e0ef2317b60169e783353daa2541450b3d |
| managed wildcard runner profile | fa0b48332f3342488596a878b00ae038e9d9b44a4d3220f44fd08240703de0ce |
| return xcresult summary | ec669d7bb3f743d7963a3b025d77848075538898ae03efcd02f69365cbaf96d6 |
| return xcresult tests | bdd50df902ca9cbf1b188be53c4958ede4df8fdd59cb12c18f6d899cd4391de0 |
| return action log | b307753ab5083eb90f49c61b8c605cf710c0eb5d5b9b2b1eb1000b912ad06915 |
| close xcresult summary | d0033d57274daf29c21abf309242967ce6d5aabbb1d98d1001dcdc27b5bda333 |
| close xcresult tests | c3a2eed28d0da52aa0e8ece6b472d8dfc60c277f0dd89a1bb65d961731d53d44 |
| close action log | 191b7be7a46275d052617fcc4e8e00dde708cddeefeb0929a47a45ca5903bea9 |

The following rows identify all four consumed bounded-manual-close attempts and
the packages used by the failed attempts. They do not replace the controlling
return archive or constitute close proof:

| Bounded-manual-close artifact | SHA-256 |
|---|---|
| first failed pre-prompt attempt evidence manifest | 22889e9c0913adaaca9754ec59213114e1603035d1eed0ed41e69bfe9f8c11a9 |
| corrected failed pre-prompt attempt evidence manifest, 73/73 entries | f36fce038f29780039ec86a4cfacd9a0274b491da517abf7c576ae07da6184ad |
| third failed pre-prompt attempt evidence manifest, 127/127 entries and no extras | e6b782f1ed8b2402bbb15ca92138551e306c997c149e61a1e9d5547876d10d9a |
| fourth failed pre-prompt attempt evidence manifest, 131/131 entries and no extras | 3e82b7dc4160ec09439a15d3e98ead3589bb0e21caf214b92adef7504db1ffc1 |
| consumed corrected wrapper package manifest | 17a72617b3b70fc3df502ceaa5e153cfc9d9aed5f39f63099a6472f7762d3028 |
| consumed corrected wrapper source | c2014c6abe453ddb01c3dfae944dae584e5fb1656715a24e813efc3cc439d30b |
| consumed corrected wrapper unit-test source | e4a61f0122fb36876fa348421260dbddde8065c9d24f2d338b2a59dec068f6ce |
| third-attempt invocation package manifest | 76606d1e6c6b08dcae4b3c156eae8a4abdb790179c9613973abeaa3638d9db49 |
| third-attempt invocation wrapper | d5839e36978cd4046be7531f831c1ca8d0e6ff700187a69c84c12f6aa594e7e1 |
| v2 parser-remediation unit tests | 5e272350e88fc7b44e1c807aa0ed2eadef50bdc061f94466612ec057d86e3368 |
| v2 parser-remediation causal auditor | 4abc6077272862a966670e444d63e67a2d693d549b04a55841fda14544796d86 |
| frozen v2 runner package contract | 641ee495b33b2ece4c126d4cd61dc14fed704314ca2399cf0f40209843870e73 |
| frozen v2 xctestrun | 31f7f7c48205ec3b73233b7bd8d7f63b8afefbb9c2b07b689839a7cf6b074afc |
| frozen v2 reviewed XCTest source | ef24a8959f273fa0941ec0727fbf519ff0936ae454e212309cc562c5e69a199b |
| frozen v2 runner executable | 5a2038de68ff8a93fec53bd7d10d5482f532a1a3cb84d454267432d6cadb86f1 |
| frozen v2 nested xctest executable | f145c449cf1baddb7b405022792a40e5998437a07f592d8739bfd4c088e1f148 |
| frozen v2 reviewed bundle manifest | 38399a6db8d3bde0f355c124b32b9455203df961d46b48ac93cb6587de8d70e4 |
| frozen Release AUT-only file manifest | 42c82cef02786500df30cfc06bf1f7509bda0f6cfd49d13ee91134726135b993 |
| frozen Release AUT executable | 6f2dc51e43ad4f64be603954f300f02c2e7a818e1b3efe4014be7da916bd5bb5 |
| frozen Release App.framework | 1c10a52ff4b63e2b26dcac9f3a134070f99be759377b7296f88456631575e5a9 |
| frozen 72-second fixture | d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5 |
| fourth-attempt v3 runner package contract | 1bb39f0bb2f17e04e16ed217c401501bc02b606dc3ea2aec09fb7a719412c7b0 |
| fourth-attempt v3 runner artifact manifest | 6151c27c0a1d0c598a482be37897de70d9757fc551d63646aedba8f8a34064bf |
| fourth-attempt v3 runner bundle-manifest file | 7335115e5ec871149f8fd6ea94e8896b231095f08e2d6a01db37a96c32b3cf16 |
| fourth-attempt v3 xctestrun | dcc8abbc805a42f7473254453e7bc129fde0e50278a3da8c72ce16745579205a |
| fourth-attempt v3 reviewed XCTest source | c472a38377e673506904e0847e449a67047f5c56d5f9d7e3d6ef1e351a067c8f |
| fourth-attempt v3 runner executable | b9e1c885cffd9d2b0cdfeda235175c1c0cbc4dd286c538e43efb19eda16b02ce |
| fourth-attempt v3 nested xctest | c6991d8065416206ead5fcfea5a237016771ae689e9535cd4ff99ec1af186c24 |
| fourth-attempt v3 42-file runner tree | 8fffdd24aff8f6108f383af8f9aff01085fb891417e41dc889f09537a8b79be9 |
| fourth-attempt v3 42-file reviewed manifest | 150ce9d287f586c85a4580b0cb8274707efc869b324df0a1c60d6bc0b5495e2a |
| fourth-attempt wrapper-v3 package manifest | 1e70473cd0ae85e8a465578dce3834609f63727200868eb58cf71695085266fe |
| fourth-attempt wrapper-v3 frozen config | 6f2b47ca90507a044196b0922ad75c57e642bb775e0a804c8b887d0d9ce0e230 |
| fourth-attempt wrapper-v3 source | 9b5b5c82834b6f892a5ea9c395aedeee48107513e153f31a8851e9176b4235f4 |
| fourth-attempt wrapper-v3 sealed launcher | 33318051794d86c31dd6e3cdefff526b1dba44550b8f4b2a89d1e6a6fbd60485 |
| fourth-attempt wrapper-v3 unit tests | 8e3458f2ba8f92bf588a985375c8d856deaf8973a5033f72304e54db22994d09 |
| fourth-attempt wrapper-v3 causal auditor | eead0b1c069e3171abbd16a4856647aebfdb30d4d69ef0a4930374b78ebe65ea |

All entries below identify earlier disposable `/tmp` evidence retained as
causal history. Hashes make the reviewed traces identifiable. Descriptive
audit labels identify the evidence role and are not repository paths or
production assets.

| Artifact | SHA-256 |
|---|---|
| assets/probe.mp4 | fff7ec5eb2f93815a39b72e1dffd924aac17bcf53ee04beeec3f98ee1a184c6e |
| run_android_probe.sh | d06644f341341c67085d95f19299d5b5340b80b35ceed78d178843bbf402af94 |
| system_expand/probe-log.txt | 5ae7e486a528823a15420d755bfb26cee6b41f91d82a3148f40bb9afd0a539ca |
| system_expand/native-owner-activities.txt | bfde9ab14cfe1f15719f118dd50a1acd0625fe622e6a20c50a5a7242031b831f |
| system_expand/native-owner-audio.txt | 0424b747653a30990e73e4b4f0969ebf89d98f2a1cde0f77fc032fa0ebe95d9b |
| system_expand/flutter-restored-audio.txt | 29bdc32748b546aa966030631d4bbfb315100fe7f3762d1fedf986488dcef804 |
| system_close/probe-log.txt | dad6ae1745fcc1c2d8fda8f48ed2ebd96e3bcf640021f0cca1ca95cc02f7a6db |
| system_close/native-owner-audio.txt | c501208dcaa16d9993e1c8b152248599f441cbc9f92406da1ca84c0fa28b2704 |
| system_close/flutter-restored-audio.txt | 82ed9b64fcf9324e81af8e10b1ae539f56d55355298e18f2c1fb1f6c0299aba4 |
| engine_detach/probe-log.txt | 20f581f464189d055c18536993e6212fd5f3e18faaa09d53c64d1ceaa315aba1 |
| process_death/probe-log.txt | 10e954426485e77eacf9853e83e5cd4108f6beb01499d4fff08f4c9c3976e15a |
| ios/devicectl-seek-fixed-console.log | e1009cb74fe7847a02e277242b8705e51a6da1d115023e74c42ee002208de91f |
| ios/pip_native_probe_seek_fixed.log | 85f028bc6ea2dcdd6751bcce05c8139ffa9ca0b706745f6396a1cb91651658cf |
| ios/pip_flutter_probe_seek_fixed.log | 1fcc1681ceaa406397d5cd05fefb5b53db63341a53264dea7db595997784bd9f |
| ios/pip_resume_checkpoint_seek_fixed.txt | 5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9 |
| ios/devicectl-uninstall.log | 3f6e1f92ed6206e67f8681cb2b58796f90b31f6ffa845194a57ed6de57fda9a3 |
| ios/process-oracle-v2/AppDelegate.swift | b92be4adcfd2dcf41c30aabfc60af418e447925fe371d82454ef6fe27f5d15d5 |
| ios/process-oracle-v2/main.dart | eee86c71127afff800fbc2a15522e88049375111ebdb2614f0bccccdf9325bd4 |
| ios/process-oracle-failed/before/pip_flutter_probe.log | dc8ba67f93f333badaa6abd5509fa78a08a4b0150528676278627f804ad91964 |
| ios/process-oracle-failed/before/pip_native_probe.log | d49f8377d1b7bf0782c95697b687758a43af398392785b541bae7f08dd141d15 |
| ios/process-oracle-failed/after-relaunch/pip_flutter_probe.log | d8b45a7247cabb7ddb4efc46da04aac0272e4521ecb3f29328472d591952e270 |
| ios/process-oracle-failed/after-relaunch/pip_native_probe.log | e184b2b3d763114b738e430d34f9151660d4f455ce19c8dce1bf37826005945b |
| ios/process-oracle-failed/checkpoint-3938.txt | 1cac2e47c58f84d0b8e14488f603520925b12f39da03df3462547d4256263b1c |
| ios/process-oracle-failed/terminate.json | ea8e08cd20a0d5623299dd87150b613aed424d280cf2685cba9674890feb5f93 |
| ios/process-oracle-failed/process-before.json | 1bf201b4d1c28beddd64d7796904a2a674756968d3bfdfb5b6807fa42c3aeac2 |
| ios/process-oracle-failed/process-after-kill.json | c0ff682d72a0fd7cb45b45b5a464f3dee3c106d0bf2c02c597280f47f57096a4 |
| ios/process-v2/launch1-host.log | 6392a13b4d0ef88791328424868df9d3f6753da26e64ebe291ab5c88f70d9573 |
| ios/process-v2/launch1.json | cef1e580b8ecc402abbb082418c5ffec4560166c14f431edf599969a3d9a31ad |
| ios/process-v2/before/pip_flutter_probe.log | f36c46637cbf4e7155a11d534f134faa6ca0767eb7be5df307b9d1f924311297 |
| ios/process-v2/before/pip_native_probe.log | 0af2e9bbaf07b732c33b573e931f0c16b778dd593a61834a682f8f3cad098525 |
| ios/process-v2/process-before.json | a67d06124afef60d41b52dd9b0480327eb061852e598864dce2d61c5330c5adf |
| ios/process-v2/terminate-host.log | fbcae83a3b368b949705ca89680847276047b5c3fb4cd1323776b34d8ca6a2d9 |
| ios/process-v2/terminate.json | 3c090a25e1792d835b7e727b07fadf0378a4f4d05ff90bc71fb448f53e180453 |
| ios/process-v2/process-after-kill.json | bb15fea9de8c9ed27347e183e0e71ff50803935d3b65ce1dda3110834961a6cc |
| ios/process-v2/launch2-host.log | 2e50cdef31c3996bc02af70cf61f8986a0d6c22263a99d0c72bb74c61e46bb5b |
| ios/process-v2/launch2.json | 2b1ffb46d86f53c507ebac7276f5856d0bde2f007190600fbb12c814cc8aae66 |
| ios/process-v2/after-relaunch/pip_flutter_probe.log | 18ff92382fc201a166859b2f1125c273ceb5354f2461b39752e3eb4b7f82a1f1 |
| ios/process-v2/after-relaunch/pip_native_probe.log | b269b93293b9e1e698510dcb14b179fbe9332e6714305ac1db7ca29b2112d99c |
| ios/process-v2/checkpoint-3944-before.txt | 63d5537f693522a872828c0e1856b57581ce8da83c12e51fdf91acea864221fa |
| ios/process-v2/checkpoint-3944-after-kill.txt | 63d5537f693522a872828c0e1856b57581ce8da83c12e51fdf91acea864221fa |
| ios/process-v2/checkpoint-3944-after-relaunch.txt | 63d5537f693522a872828c0e1856b57581ce8da83c12e51fdf91acea864221fa |
| ios/single-runner/xcodebuild.log | 4268c4d5aa8edc98c1d40bd6bb3a6fed4aa48436679cef690edc75b7ab4de96b |
| ios/single-runner/xcresult-summary.json | 6eb6c226ee947c07dd2b747fc26c26a39c623962579e41f2de216e7b3a25a021 |
| ios/single-runner/xcresult-tests.json | 7401747519a473e7900abd8241a842cefe60d38d67b14c9af16138279c051c6c |
| ios/single-runner/xctestrun | 64802c369f20b0ab203434a537b43da06de9acdbda4d236ab70d8e50caf70e16 |
| ios/single-runner/apps-before-uninstall.json | 88407430c6f76b6d4c0c47bfb86bdd5956bda6f47bd29368563c93a83550055e |
| ios/single-runner/apps-after-uninstall.json | d4308e0a6aa6e11325ac3577c9efede6bda22d2eccbbbcb74741637f4d642216 |
| ios/normal-runner/xcodebuild.log | fb467f7346adbee7922c69c39ecde4f5cc338d584f0d8014573f4606677897f8 |
| ios/normal-runner/xcresult-summary.json | a920bd0a657211dab71e4b1ede949588b3f69270309cc05f183dd91fb954c813 |
| ios/normal-runner/profiles-before.tsv | 5f12a5845a886fde2f1e8314f0e8bae25cc8de1bae77431147886774d0e240d0 |
| ios/normal-runner/profiles-after.tsv | 5f12a5845a886fde2f1e8314f0e8bae25cc8de1bae77431147886774d0e240d0 |
| ios/normal-runner/profiles.diff (empty) | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| ios/normal-runner/codesigning-identities-before.txt | 22192cff8ad245ff657caa3dd31192ac11ae59dab9adb988112cd379931b85ef |
| ios/normal-runner/codesigning-identities-after.txt | 22192cff8ad245ff657caa3dd31192ac11ae59dab9adb988112cd379931b85ef |
| ios/normal-runner/test-main.dart | d7fb65d5690dfb8846eb1c2f07299c93275d66f7790c4ba5c88b1b69c126d771 |
| ios/normal-runner/AppDelegate.swift | 1d625b2dac6cabb8372d4bd5ed2a8a6889cc4a9df3d793621226e3d5bcdc9f3a |
| ios/normal-runner/ReceivedVideoPictureInPictureUITests.swift | b40b31d4b7c54ce8d562a18141ebae4c163fa2da7cddcf928a31c2a5d11a8c5d |
| ios/iphone13/prompt-enumeration.json | 177b524b96cd03a7b3376537a194ba17ecfc786edbaafff3ed40a7b298aa7335 |
| ios/iphone13/prompt-action.json | 61ce0aa275fe5b40d81791a9a2da96b00fc300d59e2ecc6871fca9c56a444ae2 |
| ios/iphone13/axaudit-v3-cleanup.json | 9658b75a87a238a6d9a92400415c53c0b36f3b3f09b5b5041d4153983fd93ccd |
| ios/iphone13/release-launch-syslog-diagnostic.json | 0ee8de1d6f89b71598ef8781a4abfb21ca12b27ee9995c1b65de516de220923d |
| ios/iphone13/release-launch-syslog.log | 576df701d24fa3444f42b081abcbe548336b7ee9dd022106924cb2a4cad06aa4 |
| ios/iphone13/release-launch-syslog-filtered.log | 946990bd6c4a4ec357b7a39e4d4ce49cb4cfd3cc6a8319ac9b8b80e905eda2ed |
| ios/iphone13/release-inactive-flutter.log | 1dc40be910e8c2b44a67a5eb374b6be3cf61dd1a9c6e4d5fa9f76bd6fb944446 |
| ios/iphone13/release-inactive-native.log | 0f9afb4cb120a1172b66066e44423c32e309e600da7ee9774cc7398ed8c39133 |
| ios/iphone13/apps-after-held-prompt-uninstall.json | e396e299e8712c5254c138f7d5a445b15a0ffa483c8b655d27ddda1f4f53c969 |
| ios/iphone11/device-details.json | 3161dbb4ece2cfbb78de5b83e622a51f73e32c561097d1331a3d92a9912d0423 |
| ios/iphone11/lock-state.json | b18d1603993708f46789af83f6796cba4b424d9dae6840cc0b2a2856ae55dd93 |
| ios/iphone11/ddi-state.json | 3fab541b99210d1227eade590963a8f2b8f25c335f975a194bd004987d9b8546 |
| ios/iphone11/apps-before-install.json | 5554d5e255e18fffc9535d553ddf2ae95c75d01de48141a357ff6fd9f71bfc0d |
| ios/iphone11/install.json | 467c503f2fa1dd271711136ddf54fe30fb3f136810fc3f4b1f4e83227a82235e |
| ios/iphone11/launch.json | 2c2e1a5e352332db8f296b634be1d3c125b7039de791cbcdb09a906b98d9d206 |
| ios/iphone11/initial-flutter.log | 903425f561577479eeac7480e99fd18d45e06e155446f21235deb97f03046cb6 |
| ios/iphone11/initial-native.log | 2a0ffea6ed51c64cc02d4b60318c3bd91ecd0edb2f8a5d9a07fbf89ea6da2a9e |
| ios/axaudit/v3/helper.go | 5382d89c334c72605469a010dc92d07e57ab9f9ea21ba0c494d0e5944520614c |
| ios/axaudit/v3/helper_test.go | 1cd40c64d16333bcb2625d3c5532b5bc24ad207fd10c34495d8d51133d0ad387 |
| ios/axaudit/v3/helper-binary | 5b5fe7595efcc97ac27befc4dab0e806a8461e418c002ccbf7e0d9e7039a2a7c |
| ios/axaudit/v3/runner-monitor-defective.py | 9fa81af621d3de1c62176a533f0260b7dcc570d44377b45bc66182f5c270f954 |
| ios/axaudit/v3/runner-content-monitor.py | d701aa84f247948111a6b1e4fc9e2cc47b55b1d78fcde5e9d6a411f1ae733512 |
| ios/axaudit/v3/delayed-enumeration.json | d90d9780e5da1a16b5a222956d3d3d2f0b63b0608d6e24a63662e2f0888c56ca |
| ios/axaudit/v3/delayed-action.json | 1aaa2cfd8f579662a35736375bd9f3121484937e11e703edec4c1c670499e55e |
| ios/axaudit/v3/delayed-cleanup.json | d4b91f86e3cf7cd0fd10be9e13848444f09c03503c579aaded441bb7e5a9a3c3 |
| ios/axaudit/v3/monitor-defect-flutter.log | 36744685f810dc3064cc1762e45a46bc8b0c9e0cc835e044511247147e9d5e6f |
| ios/axaudit/v3/monitor-defect-native.log | e532c9276680f498fcf6508b972d1b9569d08cf959c090a9d40069940c358c3d |
| ios/axaudit/v3/immediate-enumeration.json | 00af589f0e539bd5f7ad0b4298a97feec85bb0fd6d7e76ccc440dd84f92553f7 |
| ios/axaudit/v3/immediate-action.json | 8e26c1bd810af3355c133dae2992022c77855ef8d86eee4f3089d5713ba25891 |
| ios/axaudit/v3/immediate-cleanup.json | 43b9d3d57a3fe78382fd3a447c653467453b4b5cad491cac14c32e77978ffce6 |
| ios/axaudit/v4/helper.go | 65d32e2dd3dbaa38962e69e667bbd829f9d6c0cf82855feb9be1bd4b218a9b19 |
| ios/axaudit/v4/helper_test.go | 5594bff2253efadcd628efbb5ffff659d86240d947a785f064a7229a046edecb |
| ios/axaudit/v4/helper-binary | 684d3cd83fc8e766c4f331c7f080704af4e7b133ce77b1afce3d1a30056a34e2 |
| ios/axaudit/v4/runner.py | fc829779d2c9e21f18e4aa3915ddcafcea823280fd8608428e50acc4ac49ef11 |
| ios/axaudit/v4/initial-generation.json | 2797c4ca9f7c09b7ce7f8e57347b9b396db2ad8c187c4af7036c3b97b235ca2b |
| ios/axaudit/v4/toggle-action.json | b60f187032608fd017e09dd864b7f9ae8992566755fa18cb8bd52e5c6359770c |
| ios/axaudit/v4/expanded-generation.json | 8039711b3df01f9542d24ea6eaa14ac3087075571ef1c15de953734d63d149f2 |
| ios/axaudit/v4/terminal-action-rejection.json | bb3c397fa5f4500a7ed236dc3948ffd88cbeeaa3bd771a51083145ff95184092 |
| ios/axaudit/v4/cleanup.json | e7071eb8f3767c1dff5fd596a6a3386a04d34c52ffea1be76eecefb73d05b83e |
| ios/axaudit/v4/flutter.log | ceaa696d3f5bd72229e8f0b32f675dee610bf9be78b2dfbb39cb36f697190c8f |
| ios/axaudit/v4/native.log | 42db944be05a78a159c1c724e19d82d7827466adb3d0d1942f4180b148483537 |
| ios/axaudit/v4/checkpoint-3889.txt | 5c760dfcec68a462a5ae2638f534798fdeff11b849b6ad97d2adf4ad28c7906b |
| ios/axaudit/v5/helper.go | 3c14d3c2ab2bb8434bc82012abcd9625809cd13f2de84b4745093f4ca55969f6 |
| ios/axaudit/v5/helper_test.go | f7b86db4744b433e945f36fbd624ec05ce46c61d83d3121a72454f54fb1b23cd |
| ios/axaudit/v5/helper-binary | fa7a7ca4242e18e9efc0cba5e2893e89afd0c6ea76ea0cc6cb9a103c248b8049 |
| ios/axaudit/v5/runner.py | f53748d7b483c437e44c873ab41f6cc5ad8cc5e4eb05807facdc11fc67ccbcf7 |
| ios/axaudit/v5/initial-generation.json | f790ba262083373a9dbb0abcffd0bbbb4378ff06da45b49ab5114cc10e7fd57c |
| ios/axaudit/v5/toggle-action.json | ddc406bef59e2870feedc7921c4325dd6a60f430b0135db7e0cfba1b64d010c7 |
| ios/axaudit/v5/terminal-poll.json | b5eae91c10bb77656099892013814ec1165ff744363bbd268340894ea641dca7 |
| ios/axaudit/v5/final-generation.json | cd3afc83071c9b8a410104dc3fcd58775dd6d9d16b10c4a12ebe861d25b068c7 |
| ios/axaudit/v5/terminal-timeout.json | ae9b67e952cb8eec95e0f95dfa24014afe2708ef810d986490b0ea5a924753c4 |
| ios/axaudit/v5/cleanup.json | 50274780c532f62e32dd951e56cd29be6b282127aabfaca71961942deda4859a |
| ios/axaudit/v5/flutter.log | 2cd7e2f3257325bc334b9776ec49efb8936395db5a2998bb7c2dd63eb86d02b4 |
| ios/axaudit/v5/native.log | 83868ea8c4781cba201208c67d97bb10c7c90cbc000cc7a1257f12f4ef811e52 |
| ios/axaudit/v5/checkpoint.txt | 0228374d12ee995cdeff8e25d819990f80d40c8773321fafe4ce1572c7df29af |
| ios/axaudit/v5/summary.json | 98fd550cb54a39f23ed499a1a56b47852225e38f3a14e97c4d58a92cccfd1c11 |
| ios/final-cleanup/iphone11-apps-before.json | 45a94619f908add81ebc1dcbe90a5d5bfe088a739672eb663dfc664cd2c00f36 |
| ios/final-cleanup/iphone11-uninstall.json | 0dc6efd67f49478411e58d73d8508085c8ccec56cddbd73774b6f7751269c968 |
| ios/final-cleanup/iphone11-apps-after.json | 73c2c3a80d778e363b15ddedaf9910009549453fe37b06a6e89b32a8a0455629 |
| ios/final-cleanup/iphone13-apps-before.json | d5eb579cc7de1a46ec8b27b08221e899239cbc76c8b1e09d1441219067f8c3ea |
| ios/final-cleanup/iphone13-uninstall.json | 86ad67062053a951fa9f5f79fbb6a5fc04b81bf93c9d3e940054b5d9afc4c47b |
| ios/final-cleanup/iphone13-apps-after.json | 98047bbca05982f1ea74f6d422ccb4acbc1e4b2b0bcd3332c23dca97ba3e2718 |

## Exact implemented production manifest

This is the reconciled Plan-243-owned surface. Several route/repository files
also contain sibling media-plan work in the dirty tree; this manifest claims
only the PiP responsibilities named here.

### New app-owned production files

- lib/core/media/app_owned_media_path_authority.dart — shared symlink-safe
  canonical authority for exact media/local_media/post_media roots.
- lib/core/media/picture_in_picture_gateway.dart — typed capability,
  request/event/terminal models and exactly-once session-fenced channels.
- lib/shared/widgets/media/media_picture_in_picture_controller.dart —
  transport-free policy, exact-current lease, real Flutter/native owner
  handoff, immediate revocation subscription, 250 ms poll backstop, guarded
  Plan-228 persistence, completion, and restore.
- android/app/src/main/kotlin/com/mknoon/app/PictureInPictureEngineCleanupCoordinator.kt
  — one shared engine-cleanup seam used by the real Flutter callback and the
  disposable proof receiver.
- android/app/src/main/kotlin/com/mknoon/app/PictureInPictureHandler.kt —
  additive channel registration, one in-process registry, engine-detach stop.
- android/app/src/main/kotlin/com/mknoon/app/ReceivedVideoPictureInPictureActivity.kt
  — non-exported video-only owner, monotonic terminal checkpoint, fail-closed
  recreation.

### Reconciled existing production/project files

- lib/core/media/received_media_egress_service.dart — consume the extracted
  canonical authority with unchanged egress behavior.
- lib/shared/widgets/media/full_screen_typed_media_viewer.dart — typed viewer
  only; explicit localized Android PiP control, no iOS/other-platform PiP
  semantics, and mutable one-owner video lifecycle.
- lib/shared/widgets/media/media_viewer_item.dart — additive typed PiP
  capability bit; default false.
- lib/features/conversation/presentation/screens/conversation_screen.dart —
  direct viewer authorization/signal composition.
- lib/features/conversation/presentation/screens/conversation_wired.dart —
  exact direct current-row authorizer, typed message-removal/attachment-change
  revocation composition, and real Plan-228 adapter.
- lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart
  — direct-library exact-current authority, continuation-page qualification,
  stale-parent eviction, ChangeNotifier signal, and resume adapter.
- lib/features/groups/presentation/screens/group_conversation_wired.dart —
  group/announcement exact-current authority, typed repository/attachment
  revocation composition, and Plan-228 adapter.
- lib/features/groups/presentation/screens/group_shared_media_library_screen.dart
  — group/announcement library authority, continuation-page qualification,
  stale-parent eviction, ChangeNotifier signal, and resume adapter.
- lib/features/conversation/domain/repositories/message_repository.dart and
  message_repository_impl.dart — typed `DirectMessageRemoval` source.
- lib/features/conversation/domain/repositories/media_attachment_repository.dart
  and media_attachment_repository_impl.dart — typed
  `MediaAttachmentAuthorizationChange` source.
- lib/features/groups/domain/repositories/group_message_repository.dart and
  group_message_repository_impl.dart — typed
  `GroupMessageAuthorizationChange` source.
- lib/l10n/app_en.arb, lib/l10n/app_de.arb, lib/l10n/app_ar.arb — explicit PiP
  action, tooltip/semantic label, and start-failure copy. Unsupported behavior
  is intentionally hidden and silent, with no user-facing unsupported string.
- lib/l10n/app_localizations.dart, lib/l10n/app_localizations_en.dart,
  lib/l10n/app_localizations_de.dart, lib/l10n/app_localizations_ar.dart —
  generated localization outputs.
- android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt — one additive
  PictureInPictureHandler registration/cleanup; preserve every existing owner
  and ordering.
- android/app/src/main/AndroidManifest.xml — declare only the dedicated
  non-exported PiP Activity.
- android/app/build.gradle.kts — proof-only source-set/property fences; both
  proof components are absent from default builds and refuse the production
  application ID.
- scripts/check_reliability_simulation_discovery.sh — one exact ignored
  classification for the canonical Android device-proof entrypoint.

### Files explicitly not modified

- lib/shared/widgets/media/full_screen_image_viewer.dart.
- lib/features/conversation/presentation/screens/direct_private_media_viewer.dart.
- lib/features/groups/presentation/screens/group_private_media_viewer.dart.
- transport, Bridge, P2P, relay, Go, encryption, delivery, and message schema.
- database schema/migrations; Plan 228 DB v96 remains the persistence owner.
- ios/Runner/AppDelegate.swift, ios/Runner/Info.plist,
  ios/Runner.xcodeproj/project.pbxproj, and all Runner/RunnerUITests PiP source:
  Path 3 adds no coordinator/channel, PiP background-audio mode, or iOS PiP UI
  test. Existing non-PiP owners remain byte-preserved except for unrelated work.
- iOS NotificationService and Share Extension source/entitlements.
- pubspec.yaml; the proof fixture is host-seeded into the installed test app's
  app-owned Documents/media subtree and is never bundled into production.

## Exact implemented test/proof manifest

### Canonical new files and names

- Test-Flight-Improv/243-proof-artifacts/pip-ownership-decision.md.
- test/core/media/picture_in_picture_gateway_test.dart
  - typed PiP session maps native lifecycle exactly once and ignores stale events
- test/shared/widgets/media/media_picture_in_picture_policy_test.dart
  - only ordinary completed local video can request PiP or checkpoint
- test/shared/widgets/media/media_picture_in_picture_handoff_test.dart
  - PiP handoff has one playback owner and one normalized durable position
  - active PiP authorization signal stops native before the polling backstop
  - native return persists only after exact current reauthorization
- test/shared/widgets/media/media_picture_in_picture_route_authorization_changes_test.dart
  - direct/group typed revocation sources filter exact current identity and
    preserve fail-closed stream errors
- test/core/media/picture_in_picture_transport_boundary_test.dart
  - PiP source and channel schema contain no messaging or secret fields
- test/core/media/android_picture_in_picture_native_contract_test.dart
  - SystemUI close uses a session fenced monotonic checkpoint when terminal position is zero
  - Flutter engine detach stops native once and process recreation is empty
- test/core/media/ios_picture_in_picture_fail_closed_contract_test.dart
  - iOS capability is always unsupported, direct start fails before handoff,
    and the PiP control/accessibility node is absent
  - AppDelegate/project/Info.plist contain no Plan 243 AVKit owner/channel,
    RunnerUITests PiP source, or PiP `UIBackgroundModes=audio`
- test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart
  - PiP persistence handles video only unknown later clamp and completion
- integration_test/received_video_picture_in_picture_proof_test.dart
  - Android video-only PiP lifecycle, completion, engine detach, and
  interruption
- integration_test/support/received_video_picture_in_picture_fixture_seed.dart
  - test-entrypoint-only lookup and SHA-256 verification of the host-seeded
    app-owned fixture; contains no production startup switch or channel
- integration_test/support/android_picture_in_picture_system_ui_control.dart,
  integration_test/support/android_picture_in_picture_system_ui_selection_result.dart,
  and their `integration_test/scripts/` selectors — bounded Pixel-6/API-36
  SystemUI geometry and exact parsed selection contract
- integration_test/fixtures/received_video_picture_in_picture_fixture.mp4 —
  deterministic H.264/AAC host fixture with the fixture hash above; not listed
  in pubspec assets and not shipped in production.
- scripts/run_received_video_picture_in_picture_proof.sh — host-controlled
  Android-only proof runner with explicit `return`, `close`,
  `process-recreation`, `completion`, `engine-detach`, and `interruption`
  scenarios; explicit target IDs only.
- android/app/src/pipProof/AndroidManifest.xml and
  PictureInPictureEngineDetachProofReceiver.kt — disposable engine-cleanup
  seam proof only.
- android/app/src/pipInterruptionProofAndroidTest/AndroidManifest.xml and
  PictureInPictureAudioFocusInterruptionProofActivity.java — distinct test-APK
  audio-focus interruption owner only.
- android/app/src/test/kotlin/com/mknoon/app/PictureInPictureNativeTest.kt and
  PictureInPictureExitClassifierTest.kt — host JVM lifecycle/classification.
- scripts/check_android_picture_in_picture_engine_detach_proof_build.sh,
  scripts/check_android_picture_in_picture_interruption_proof_build.sh,
  scripts/parse_android_picture_in_picture_task_topology.py, and the four
  `validate_android_picture_in_picture_*.py` validators — proof build fences,
  topology, SystemUI selection, restored ownership, interruption, and cleanup.
- test/integration/android_picture_in_picture_system_ui_control_test.dart,
  android_picture_in_picture_system_ui_selection_result_test.dart,
  android_picture_in_picture_restored_ownership_test.dart, and
  android_picture_in_picture_interruption_ownership_test.dart, plus their
  `test/fixtures/android_picture_in_picture_*` inputs — causal host oracles for
  the physical harness.

### Deterministic fixture and test-entrypoint ownership

The Android proof runner, not production startup, seeds the fixture. After installing
the scenario-specific integration-test build, it copies the reviewed fixture
to the installed app's `Documents/media/plan243-proof/` subtree with
explicit-device `adb push` plus `run-as`. It hashes the source before copy and
the app-owned copy after copy and requires the exact reviewed digest. No iOS
fixture is copied or device proof run.

Each scenario is built with its exact integration-test file as `FLUTTER_TARGET`
or Flutter `--target`. That test-only entrypoint obtains
`getApplicationDocumentsDirectory()`, resolves the fixed relative fixture,
rehashes it, and constructs the typed proof viewer. Production `main.dart`,
AppDelegate, MainActivity, method channels, intents, user defaults, restoration
state, and navigation contain no proof mode, fixture hook, path injection, or
scenario switch. The process-recreation phase marker belongs only to the
scenario-specific integration entrypoint and is never read by production.

### Seven exact route-composition extensions

1. test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
2. test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
3. test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
4. test/features/conversation/presentation/screens/conversation_wired_test.dart
5. test/features/groups/presentation/group_conversation_wired_test.dart
6. test/features/groups/presentation/group_shared_media_screen_test.dart
7. test/features/groups/presentation/group_shared_media_wired_test.dart

Together they prove direct conversation, direct shared library, group
conversation, group shared library, and announcement composition with a real
Plan-228 store, exact-current reloader, and primary invalidation signal.

### Exact policy, localization, egress, and private extensions

- test/core/media/received_media_egress_service_test.dart — extracted path
  authority preserves exact egress outcomes and symlink defenses.
- test/core/l10n/app_localizations_signal_test.dart.
- test/l10n/l10n_integrity_test.dart.
- test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart.
- test/features/groups/presentation/group_private_media_viewer_test.dart.

The private tests pin canEnterPictureInPicture=false and zero native/persistence
calls.

### Mandatory preservation sentinels

- test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart
  exact name: video resume handles unknown duration revalidation and completion.
- test/shared/widgets/media/full_screen_image_viewer_test.dart.
- test/core/notifications/main_activity_onnewintent_pin_test.dart.
- test/core/device/disk_space_channel_test.dart.
- test/core/lifecycle/main_keepalive_wiring_test.dart.
- test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart.
- test/core/media/received_media_egress_transport_boundary_test.dart.
- test/core/media/private_media_protection_coordinator_test.dart.
- test/core/services/share_intent_android_test.dart.
- test/core/services/share_intent_ios_test.dart.
- test/features/push/application/ios_push_project_config_test.dart.

The native sentinels preserve MainActivity/AppDelegate ownership for egress,
private protection, share filters, mDNS/permission routing, migration
keepalive, disk space, onNewIntent, APNS/FCM notification chaining, app groups,
and existing UI-test registration.

## Host-controlled device proof contract

scripts/run_received_video_picture_in_picture_proof.sh must never choose a
target implicitly.

Android mode:

- accepts one explicit adb device ID;
- installs/launches the integration app and deterministic fixture;
- waits for real Flutter video_player ownership, captures AudioService, then
  asserts zero overlap before native ownership;
- parses pinned bounds and drives real SystemUI expand/return and close;
- captures screenshot, ActivityManager, window, SurfaceFlinger, and audio
  evidence;
- drives engine detach, process force-stop/relaunch, completion, and an
  interruption;
- requires once-only terminal events, monotonic nonzero close checkpoint,
  exact-current reauthorization, no pinned task/audio afterward, and protected
  control absence.

iOS has no device-proof mode. Its Path 3 acceptance is the deterministic
host/widget/static negative contract: hidden control, unsupported capability,
start rejected before handoff, and no AVKit owner/channel/project/background-
audio additions. A physical iPhone or simulator is neither required nor
permitted to substitute for those assertions.

The Android physical device is the sole production-source system-PiP proof
target. The accepted custom-ID debug integration APK limitation is recorded in
the execution section; an available Android emulator is supplemental.

## Discovery and gate cadence

### Historical causal RED

The first production turn added only the gateway test and confirmed the absent
gateway as a causal compile RED:

~~~bash
flutter test test/core/media/picture_in_picture_gateway_test.dart \
  --plain-name 'typed PiP session maps native lifecycle exactly once and ignores stale events'
~~~

### Focused Plan 243 GREEN

~~~bash
flutter test test/core/media/picture_in_picture_gateway_test.dart
flutter test test/core/media/picture_in_picture_transport_boundary_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_policy_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_handoff_test.dart
flutter test test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart
flutter test test/core/media/android_picture_in_picture_native_contract_test.dart
flutter test test/core/media/ios_picture_in_picture_fail_closed_contract_test.dart

flutter test \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'video resume handles unknown duration revalidation and completion'
~~~

### Seven route commands

~~~bash
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/group_shared_media_screen_test.dart
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart
~~~

### Localization, private, and egress commands

~~~bash
flutter gen-l10n
flutter test \
  test/core/l10n/app_localizations_signal_test.dart \
  test/l10n/l10n_integrity_test.dart
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/features/groups/presentation/group_private_media_viewer_test.dart
flutter test test/core/media/received_media_egress_service_test.dart
~~~

### Native/shared preservation commands

~~~bash
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test \
  test/core/notifications/main_activity_onnewintent_pin_test.dart \
  test/core/device/disk_space_channel_test.dart \
  test/core/lifecycle/main_keepalive_wiring_test.dart \
  test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart \
  test/core/media/received_media_egress_transport_boundary_test.dart \
  test/core/media/private_media_protection_coordinator_test.dart \
  test/core/services/share_intent_android_test.dart \
  test/core/services/share_intent_ios_test.dart \
  test/features/push/application/ios_push_project_config_test.dart
~~~

### Exact discovery classification

~~~bash
records_file="$(mktemp)"
proof=integration_test/received_video_picture_in_picture_proof_test.dart
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$records_file"
test "$(awk -F '\t' -v proof="$proof" '$1 == "ignored" && $2 == "ignored" && $3 == proof { n++ } END { print n + 0 }' "$records_file")" -eq 1
test "$(awk -F '\t' -v proof="$proof" '$1 == "unclassified" && $3 == proof { n++ } END { print n + 0 }' "$records_file")" -eq 0
rm -f "$records_file"
~~~

### Explicit-target device closure

Resolve again immediately before execution:

~~~bash
flutter devices --machine
adb devices -l
~~~

Then use only IDs present in that live matrix:

~~~bash
ANDROID_DEVICE_ID=21071FDF600CSC

flutter test integration_test/received_video_picture_in_picture_proof_test.dart \
  -d "$ANDROID_DEVICE_ID" \
  --dart-define=PIP_PROOF_PLATFORM=android
./scripts/run_received_video_picture_in_picture_proof.sh \
  --platform android --scenario return --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh \
  --platform android --scenario close --device "$ANDROID_DEVICE_ID"
./scripts/run_received_video_picture_in_picture_proof.sh \
  --platform android --scenario process-recreation --device "$ANDROID_DEVICE_ID"
~~~

An unavailable Android target/version is N/A by project policy, not permission
to add an iOS proof leg. iOS is closed by its negative contract, not hardware.

### Curated lanes and static closure

~~~bash
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
~~~

Do not run full host-all, feature-host-all, or core-host-all as a Plan 243
default closure gate. Run full host-all once after the relevant 243-245 wave is
complete and again at final rollout/release closure, owned by the main agent.

After the coherent app-owned production change and focused/device gates pass,
refresh only the architecture graph once:

~~~bash
./graphify-arch/refresh_arch_graph.sh --incremental
~~~

The main/root agent owns that integrated refresh. Do not run a routine full
graph refresh.

## Approval boundary

Approval must explicitly confirm:

- canonical Path 3 and an Android-only PiP release claim;
- the exact dedicated Android Activity/handler seam and explicit-only entry;
- iOS/other-platform hidden capability, deterministic unsupported start, zero
  owner/channel/handoff, and no PiP background-audio/project additions;
- exact-current authority and symlink-safe canonical path reuse;
- primary signal-driven revocation with only a 250 ms poll backstop;
- one-owner Android audio/video handoff;
- session-fenced monotonic terminal checkpoint and reauthorization-before-
  persistence;
- Android process-death and engine-detach fail-closed behavior;
- the retained iOS return PASS and close FAIL/unproved as historical facts only,
  with physical-iPhone close explicitly removed from release closure;
- all four consumed Path 1 attempts without reclassifying them, inventing a
  retry, or granting any iOS/live-wrapper authority;
- the offline-only v4 audit: the passing grammar manifest, integrity-clean but
  post-proof-XCUI-rejected runner, five-mismatch unsealed wrapper with stale
  README, incomplete offline/adversarial acceptance, immutable v3/v4 rejected
  lineage, and no fifth live attempt or new authority;
- the offline-only v5 audit: the independently byte/source/signing-accepted and
  frozen runner, structurally sealed but causally rejected wrapper, confirmed
  false PASS cases with absent host confirmation, empty raw syslog, and absent
  or zero terminal-line hashes, immutable v5 artifacts, and no fifth live
  attempt or new authority;
- the unfinished unsealed wrapper-v6 staging lineage as rejected/offline-only
  and unnecessary for Path 3;
- the complete production/test/device manifest and gate cadence;
- additive Android/MainActivity changes, no Plan 243 AppDelegate/Info.plist/
  Xcode-project/RunnerUITests PiP changes, and all preservation sentinels.

This evidence record selects Path 3 and closes Plan 243 implementation,
focused/preservation tests, curated lanes, fail-closed iOS negatives, the
six-scenario production-source Android physical proof, and both required
aggregate host coverage records. The aggregate records meet the user's
explicit segmented-resume semantics and are not single uninterrupted passes.
This record does not claim a production-ID or release-signed APK proof. iOS PiP
makes no release claim; its physical return/close/process legs are historical
and N/A for closure. Runner/wrapper v3-v6 artifacts remain rejected or
offline-only as described above and grant no live authority.
