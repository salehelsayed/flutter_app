# Track-3 / Wave-3 final handover

Date: 2026-07-14 (Europe/Berlin)
Status: **Track-3 / Wave-3 accepted and closed under explicit segmented host-resume semantics; final media and three-device deployment seal complete**

## What is closed

- Plan 243 is canonical Path 3: Android API 26+ with the PiP feature is the
  only advertised PiP surface. iOS, web, desktop, and other platforms hide the
  control, report unsupported, perform no playback handoff, and create no PiP
  native owner.
- Plan 243's shared Dart and Android implementation is present. The six-scenario
  physical Pixel-6/API-36 proof passes from one coherent evidence root.
- iOS PiP device testing is `N/A` by the selected product contract. The earlier
  physical-iPhone return PASS and close FAIL/unproved remain immutable history
  in `243-proof-artifacts/pip-ownership-decision.md`; they are not release gates
  and must not be reclassified.
- Plan 246 is accepted/intentionally not applicable. Reporting remains an
  explicit product non-goal; no backend, queue, credential, native, or device
  work is required.
- Focused PiP/static/route/localization/private/preservation/native tests,
  curated `1to1` and `groups`, discovery, analyzer reconciliation, diff
  hygiene, and the single incremental Graphify refresh are closed.
- Wave-3 and final-rollout host coverage are closed by two user-directed
  segmented-resume composites. Neither composite is a single uninterrupted
  `host-all` invocation, and no failed/interrupted predecessor is a pass.
- The P1 sender-view, forwarding, and external Photos image/video regressions
  are closed with zero unresolved selectors and user-confirmed manual proofs.
- The settled app is installed in place and left launched on the physical
  Pixel 6, iPhone 11, and iPhone 13 with existing identities and app data
  preserved.

## Aggregate closure state

| Gate | Accepted result | Frozen evidence |
|---|---|---|
| Wave-3 aggregate `host-all` | User-directed segmented resume: preserved items 1–416 plus exact resumed items 417–1,173; suffix PASS with 8,291 Flutter tests across 749 paths and 8/8 Go legs | `build/Plan243/final-host-gates/wave-host-all-composite/acceptance-record.md`; SHA-256 `3140017c5cca80b8712c9d5c480908b64bc7652e5825391f6925723123851198` |
| Final rollout `host-all` | User-directed segmented resume: preserved items 1–1,114 plus exact resumed items 1,115–1,173 at concurrency 1; suffix PASS with 1,063 Flutter tests across 51 paths and 8/8 Go legs; full indexed coverage 1,165 Flutter paths plus 8 Go legs | `build/Plan243/final-host-gates/final-release-host-all-composite/composite-acceptance.md`; SHA-256 `6df609df4f270c345c059bb53e9a9ee9ecab94f67ec6aaddd80dc8cf7fbfd6b1` |
| P1 media regression seal | Consolidated lock/repository/caller/direct/group **446/446 PASS**; final `core-host-all` **2,561/2,561 PASS**; preserved feature run **8,024 PASS / 1 skip / 20 failed**, followed by exact failure-only resumes **20/20 PASS**, for **8,044 unique PASS / 1 registered skip / 0 unresolved failures**. The full feature gate was not restarted. | [Final media validation summary](../build/media-p1-aggregate-resume-20260714/VALIDATION_SUMMARY.md) |
| Final three-device deployment | Profile build `1.0.0+107` installed by replacement/in-place semantics and launched on Pixel 6 `21071FDF600CSC`, iPhone 11 `00008030-001A6D2801BB802E`, and iPhone 13 `00008110-00184D622289801E`; identities, databases, contacts, chats, and group state retained; no deployment blocker. | [Final settled-tree deployment record](../build/media-final-deployment-20260714-215249/README.md) |

These composites satisfy the user's explicit resume authority only. Their
concurrent Flutter aggregates overlap the resumed suffix and must not be added
together. They are not evidence of fresh, unbroken, single-invocation passes.

## Final media and deployment seal

The sender-side image/video viewer, forwarded media-card preservation,
group-to-direct and direct-to-group forwarding, and iOS external Photos share
paths are accepted as fixed under the linked aggregate validation. Production
MIME validation remains strict; stale test payloads were replaced by shared
valid JPEG/PNG/GIF/MP4 fixtures rather than weakening the runtime guard.

Manual observations reported by the user are frozen as PASS: `Leg A done`,
`Leg B done`, `Photos image done`, `sender image opens`, and `Photos video
done`. The last observation is the final iPhone sender external-video
card/playback proof.

The final deployment used replacement/in-place installs only. All three
physical devices launched successfully after installation; the Pixel retained
its install time, peer identity, chats, group state, and online/relay-ready
status, while both iPhones retained their existing `identity.db` containers.
The exact builds, signatures, device IDs, install commands, preservation
checks, renderer proof, and launch evidence are recorded in the linked
deployment record.

Frozen upstream document dependencies, in one-way order:

- `243-proof-artifacts/pip-ownership-decision.md`: SHA-256
  `7a9ae073f90d4efe6b40051f2cb2ccf72573779704c184a00e6e49dbcea5b196`
- `243-native-media-picture-in-picture-tdd-plan.md`: SHA-256
  `abb4ea35ecfb1cb2f2ca942bfaecaf72b3d331e017f34894604141d699c16317`

## Implemented product boundary

The eligible item is an incoming, completed, integrity-verified, ordinary
video with a current owner/lane authorization and a canonical app-owned path.
Every start is explicit; Android automatic entry is disabled.

The late correctness fixes are part of the closed implementation:

- Direct authorization changes merge current-message updates, typed
  `DirectMessageRemoval`, and typed
  `MediaAttachmentAuthorizationChange`. Group/announcement changes merge the
  listener, typed `GroupMessageAuthorizationChange`, and typed attachment
  changes. Scope and exact message/attachment identity are filtered before a
  controller recheck; stream errors fail closed.
- Direct and group Shared Media continuation pages are re-qualified before
  they can become viewer pages. Failed exact-current reload removes the stale
  parent, so a continuation page cannot inherit an earlier page's authority.
- `FullScreenTypedMediaViewer` hides PiP on capability/authorization failure,
  shows localized start-failure UX for a real rejected start, and restores only
  the exact current video page.
- `MediaPictureInPictureController` serializes starts, native events,
  checkpoint coalescing, and terminal settlement. Authorization loss advances
  an epoch/loss fence and runs a priority once-only native stop; queued starts
  and checkpoints cannot regain revoked authority. Dispose waits for queued
  operations, authorization checks, and priority stops before gateway disposal.
- Android has one non-exported, video-only
  `ReceivedVideoPictureInPictureActivity`. `MainActivity` remains a separate
  non-PiP Flutter task. Session/path state is process-memory-only and is never
  replayed after process recreation.

## Reconciled production manifest

Plan-243-owned new production files:

- `lib/core/media/app_owned_media_path_authority.dart`
- `lib/core/media/picture_in_picture_gateway.dart`
- `lib/shared/widgets/media/media_picture_in_picture_controller.dart`
- `android/app/src/main/kotlin/com/mknoon/app/PictureInPictureEngineCleanupCoordinator.kt`
- `android/app/src/main/kotlin/com/mknoon/app/PictureInPictureHandler.kt`
- `android/app/src/main/kotlin/com/mknoon/app/ReceivedVideoPictureInPictureActivity.kt`

Plan-243-owned responsibilities in existing production/project files:

- `lib/core/media/received_media_egress_service.dart`
- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- direct route/library composition in `conversation_screen.dart`,
  `conversation_wired.dart`, and `direct_shared_media_library_screen.dart`
- group/announcement route/library composition in
  `group_conversation_wired.dart` and
  `group_shared_media_library_screen.dart`
- typed change-source contracts/emitters in direct message, media attachment,
  and group message repository interfaces/implementations
- the three ARB files and four generated localization files
- `android/app/build.gradle.kts`, `AndroidManifest.xml`, and `MainActivity.kt`
- exact proof discovery classification in
  `scripts/check_reliability_simulation_discovery.sh`

No Plan 243 PiP change was added to AppDelegate, Info.plist, the Xcode project,
RunnerUITests, transport, Bridge/P2P/relay/Go, wire schema, encryption, or DB
migrations. Plan 228 DB v96 remains playback-position authority.

## Reconciled test and proof manifest

Core/shared tests:

- `test/core/media/picture_in_picture_gateway_test.dart`
- `test/core/media/picture_in_picture_transport_boundary_test.dart`
- `test/core/media/android_picture_in_picture_native_contract_test.dart`
- `test/core/media/ios_picture_in_picture_fail_closed_contract_test.dart`
- `test/shared/widgets/media/media_picture_in_picture_policy_test.dart`
- `test/shared/widgets/media/media_picture_in_picture_handoff_test.dart`
- `test/shared/widgets/media/media_picture_in_picture_resume_contract_test.dart`
- `test/shared/widgets/media/media_picture_in_picture_route_authorization_changes_test.dart`
- the seven canonical route-composition files plus localization, private-viewer,
  egress, Plan-228, image-viewer, and native/shared preservation sentinels

Android/native and physical proof:

- `android/app/src/test/kotlin/com/mknoon/app/PictureInPictureNativeTest.kt`
- `android/app/src/test/kotlin/com/mknoon/app/PictureInPictureExitClassifierTest.kt`
- `android/app/src/pipProof/` engine-cleanup receiver source set
- `android/app/src/pipInterruptionProofAndroidTest/` distinct interruption
  helper test-APK source set
- `integration_test/received_video_picture_in_picture_proof_test.dart`
- fixture, seed helper, Pixel-6/API-36 SystemUI selectors, and exact selection
  result under `integration_test/fixtures`, `support`, and `scripts`
- `scripts/run_received_video_picture_in_picture_proof.sh`, both proof-build
  boundary checkers, task-topology parser, and the SystemUI/restoration/
  interruption/cleanup validators
- four causal host integration validators and their
  `test/fixtures/android_picture_in_picture_*` inputs

The proof source sets are absent from default builds. Their build properties
refuse the production application ID.

## Final coherent physical proof

Evidence root:
`build/received-video-pip-proof/final-coherent-20260714T072110Z`.

- Target: physical Pixel 6/oriole `21071FDF600CSC`, Android SDK 36,
  PiP feature present.
- Fixture: 72 seconds, 2,463,571 bytes, SHA-256
  `d10a67eb9b3d2f707018524da5d4f0473ee665af22ea9675ab6629e201fcacf5`.
- App proof identity: disposable debug ID `com.mknoon.app.pipproof`, signer
  SHA-256
  `8a6186ce9e753686790f1dc8df3fb50f51f3fbbf39ac2b7b114d6bfff29ffd20`.
  This compiled the production viewer/gateway/MainActivity/handler/Activity
  seams, but is not the production application ID, a release-signed APK, or a
  store-distribution artifact.

| Scenario | Exact result | Host log SHA-256 | Flutter log SHA-256 | APK SHA-256 |
|---|---|---|---|---|
| return | PASS — task `871`; real SystemUI expand; `restoring/systemReturn` at `11728` ms; Flutter restored playing with displayed position `11000`; native/pinned/audio cleanup exact | `05be517116834debc5bdb0fc6640718d0a5d09e6b62201a850256ea4451db939` | `66fc9795bc4532bd228858d053e115084063927cfe51b40869af535b0c42162c` | `9fe6b3752121fb929af31f1082355d1ee8f06bd5db57ecd3ea4ae2d0739d1d34` |
| close | PASS — task `873`; real SystemUI close; `stopped/systemClose` at `12041` ms; Flutter restored paused; owners settled | `e4abe5f7d43769a4a4796c59e0504c430850930d05b90c0fa3c97d32dac65811` | `f525d71e4bb086d0931dbb7c3d2e29ca1ef218b22d194aaa883e9a9f47bd19c6` | `85f270880d5261451c5aa8b3e4cffaf430c9dd07fe5a6b5fb408f4b09b3e708c` |
| process recreation | PASS — PID `17168` to `17554`; relaunch empty; native replay false | `1195ec3e47c82ca0ba580663ee0947a474ec1e95f802f0b3d7607777fd1a6f4d` | `0f964a68657cd34ba44935caafb08689988094f7a61d42a49b60a4519d605a5b` | `ac28453adade6aad0f2a510d9a0ac25b2d7c5f8c7370446d60049b127ad392bc` |
| completion | PASS — one `completed/completed` terminal, position `0`, owners settled | `42049d74bbc3375a648b11ef05bfd07db462c2dca600d2ed37032bf6ddd7db6c` | `64856001a03170d2df74d8b25916ac3c14bc939fe1d7499bdc40fdce7903300f` | `2a3d0f5eb9e03386f33f817d33c7eae077e10bce1211b53f35bb677dcf0aedbd` |
| engine detach | PASS at shared cleanup seam — `stopped/flutterEngineDetached` at `6367` ms; `flutterHostExit=0`, `proofControl=true`, `realCleanupCallback=false`, `nativeTerminal=true`, `dartTerminal=true`, owner released | `0364a9445f23860a08d9ecef71301f6df16c8361a05263e9dc3166071a04c2f9` | `419aa95af7bdf7f3d823ce7721cba18190c66dffccda2ff6e81715f974250c7f` | `02eaeb2b1386380cffb117a3a5a3245285384b44d08e3590ebf9dc20673f7122` |
| interruption | PASS — distinct UID helper `.pipproof.test`; audio-focus GAIN; exactly one `stopped/interrupted` terminal at `9283` ms; cleanup focus owners `0` | `d4a7f663c6cd40c3b565985b5a738b8df3bee0a1e9609d87588d14e3c86c6757` | `43b02026a0ec6b11dd2d4564d8bdfb0f6339e90371d799f1b6226d3ce903c05c` | app `80a8c29c1a5956d794501f5ca316556e82adcedacab81981f3d158924ca3f355`; helper `85f0b579e71d935ffb28dc5a90bf05ea671699a43095ca791837b6a0d6aceec3` |

Every scenario has zero primary/cleanup overlap and records the composite
marker `PROTECTED_NEGATIVE control=absent gatewayStart=false nativeOwner=false`.
That physical negative uses an unowned/protected-like item; it is not exhaustive
state-by-state protected-media proof. Host policy/viewer tests isolate every
protection state and private lane.

The engine-detach leg proves the shared cleanup seam, not invocation of the
real Flutter callback. Its explicit `realCleanupCallback=false` limitation is
intentional. Source/static/JVM tests prove the real callback wiring; the build
boundary proves the disposable receiver is absent from an ordinary APK.

## Host, curated, analyzer, and graph evidence

| Evidence | Accepted result |
|---|---|
| Focused Dart PiP/native | 67 tests PASS; log SHA-256 `4296629119a80680c5677e9caa66793e890d6a253d5dda5b8784f87a777f80f0` |
| Core/static selector | 54 tests PASS; log SHA-256 `ac4d4e4c9168a406993f6b0e6cb64c8804b4aab21e0e9219209a320c27d1cfbe` |
| Seven route-composition files | 362 tests PASS; log SHA-256 `f852150c5a112366810b3f6312ec2ef9d6963e15575dbdacf9acd1c294a4b4d3` |
| Localization/private/native-shared/Plan-228/image sentinels | 3 / 20 / 45 / 1 / 4 tests PASS |
| Android JVM | `BUILD SUCCESSFUL in 14s`; log SHA-256 `250b88b1f2557607994b8f6f389174ed13a89fe9da5134c844a658c2b31a4afa` |
| Engine/interruption build boundaries | PASS: default absence, proof-only presence, production-ID refusal |
| Curated `1to1` | 2064 Flutter tests plus relay Go PASS; log SHA-256 `4a2c50618414e529d32fd0859d0c2fd4e931293cd6e0d8789c14d8d107c705fa` |
| Curated `groups` | 2172 Flutter tests plus both bridge Go, node Go, and relay Go PASS; retained log SHA-256 `bba872a1dcdd08728fec22fb3403632b68f2b8a4c7eaed4e9a820973bb24c1b3` |
| Curated evidence inventory | SHA-256 `ed46425924ba7066c9b415747bfa40ee6cf612134ef96f75dc693360dd2adea7` |
| Plan 246 | 19/19 Flutter invocations covering 21 cases, 2 Go cases, 2 scans, hygiene PASS; SHA-256 `cc938bbd96870aaf177c442e29f65c11401a03262b4345baba90a2223df0ba0b` |
| Discovery | exact ignored entry and zero unclassified PASS; rerun log SHA-256 `7ba9efee5e267ba98410b146ca419e1ff5699919f9a9beaedd85687c8573d686` |
| Analyzer | canonical full `flutter analyze` EXIT 1/non-green accepted repository baseline: 1,610 issues, 0 errors, 115 warnings, 1,495 infos. Separate scoped 35-path `--no-fatal-infos` analysis EXIT 0 with 0 errors, 0 warnings, and 6 retained infos across 2 paths; it is not zero-diagnostic. Bundle manifest SHA-256 `74df203b77cbe46d1fb6d57708736a9bc6833dbbd0bf199a3a0988eda2b9942f`; canonical/scoped metadata SHA-256 `6b534b27bc0ef9fe1f3debb5e53c7ad16f039c1e948d4c268304334fdb56d76b` / `fa1ed7abfa9bc2d3f6dd676c6531002609143f411bf2ef89b32d37212f58e590`; full/scoped stdout SHA-256 `87ebe26dc473e21fa8d3b8f048d806e1d0af9afa69954de6e0bd01ad00bddf9e` / `841834cffeae2d41d29d5127db8ef86de181e918da1c69a9b337df39b306468e` |
| Hygiene | `git diff --check` exit 0; 24 tracked plus 11 untracked final paths have zero whitespace/temporary-diagnostic/conflict-marker findings; discovery completeness 1,255/1,255; completeness stdout SHA-256 `fb86e1bbcc46bf4b4120156913f192db0879479d0009503a6806afe032bcb965` |
| Graphify | one incremental refresh exit 0; refresh-time anchored query fingerprint `5e41fa2ec48b2bdc`; frozen refresh-time `graph.json` evidence digest `f87295727ce4d38a073f5eeacc910d631d300f067e099cd442e7fc4d96292da8`; frozen refresh-time overlay evidence digest `f82cf1de58b1dd80435764ebf00e61d9c305ae44e9cc6bb7a9d009466841a191`. Both are scoped only to that refresh because compact queries may regenerate the live graph and overlay as query-side artifacts |

The earlier `groups` `+2171 -1` log and the initial discovery run with two
unclassified entries are diagnostic only. The accepted evidence is the
post-barrier groups log and the clean discovery rerun above.

The Graphify refresh ran exactly once and exited 0 after 45.29 seconds: 34
changed, 2611 unchanged, 0 deleted; 53,542 graph nodes / 81,763 edges;
refresh-time overlay 1,354 files / 13,106 tests / 988 targets. The
`f8729572...` `graph.json` digest, overlay counts, and `f82cf1de...` overlay
digest are frozen refresh-time evidence only. Query-side regeneration has
since produced live `graph.json` hash `81a428e3...`; neither that live graph nor
regenerated overlay bytes are asserted as closure topology. The surrounding
zsh wrapper then failed because `status` is read-only. This happened after the
successful refresh and was retained without rerunning Graphify.

## Aggregate gate runner history

The gate runner now supports `--batch-flutter`, `--concurrency N`, and
`--reporter`, with `run_test_gates.sh` forwarding those options. Flutter paths
are batched into one invocation; Go legs remain separate.

Every unsuccessful aggregate execution remains failure or diagnostic evidence:

- The first new batched wave run planned 1,163 Flutter paths plus 8 Go legs
  (1,171 items). The nested completeness test hit
  `scripts/run_test_gates.sh: line 1119: gate_args[@]: unbound variable`; the
  run was manually interrupted with exit 130 before Go. Its
  `FAILED_INCOMPLETE` record and the older SIGTERM/143 run are not acceptance.
- The corrected first authoritative wave attempt planned 1,164 Flutter paths
  plus 8 Go legs, reached `+3886`, `~1`, `-1`, and failed at
  `chat_message_listener_test.dart:1925`. The tone-tracker case expected two
  notifications and observed one. It was manually interrupted with exit 141;
  all Go legs were `NOT_RUN`. Retained hashes: host log
  `92a9b5ee9de07efbdba3bbebc3884eb336cd2fee3833fc659e206808674a5cae`,
  result summary
  `c10e9299b50fca0e270a44287a2c693b007482350317dcc5e8bb0ac0a295bcb1`,
  and failure excerpt
  `77e99391ce0489e7973add4fb755180a9e5d11b84ed94ada2f4438830da5cb51`.
- The next Wave-3 batch used the then-current 1,172-item manifest and failed
  first at planned item 417,
  `test/features/conversation/application/link_incoming_lan_media_test.dart`,
  at `+3430`, `~1`, `-1`. It was manually interrupted. Its later reporter
  state and partial Go activity are non-acceptance; the interrupted pass-3 is
  diagnostic only and supplies only the current manifest identity.
- The first final-release batch covered the current 1,173-item inventory at
  concurrency 4 and failed at planned item 1,115,
  `test/integration/android_push_relay_registration_contract_test.dart`. A
  child `dart run` encountered the host native-assets/cache race where
  `install_name_tool` could not rename
  `.dart_tool/lib/libsqlite3.arm64.macos.dylib`. Exit 1, `+11709`, `~1`,
  `-1`, and 0/8 Go legs make it failure evidence. The exact suffix then passed
  at concurrency 1; that is an operational harness qualification, not a
  production behavior change.

The two isolation fixes now present in the canonical 1,173-item inventory are
also frozen. Notification integration cases directly await
`processIncomingMessage(...)` and assert the exact process state, removing the
timer/scheduling race behind the notification-count failure.
`FakeMediaFileManager` now uses process-and-isolate-specific temporary roots;
four tests in `fake_media_file_manager_isolation_test.dart` cover layout,
same-isolate sharing, spawned-isolate separation, and recursive teardown
isolation. The new path is why the current inventory contains 1,165 rather
than 1,164 Flutter paths; the 8 Go legs are unchanged.

The Wave-3 resume gate itself ended with result 0/PASS. Its surrounding
evidence wrapper then attempted to assign to zsh's reserved read-only
`status` variable and exited 1 after the terminal PASS. That post-gate
bookkeeping failure is retained separately and is not a failed test gate.

## Final maintenance contract

1. Preserve both aggregate records as user-directed segmented-resume evidence;
   do not describe either as a single uninterrupted pass.
2. Preserve every failed/interrupted execution above as non-acceptance history.
3. Do not rerun device proof, iOS PiP, focused suites, or Graphify unless a new
   source/test change invalidates the evidence.
4. Reopen Plan 243 only for an Android PiP regression or an explicitly
   authorized product-scope change; iOS remains hidden/unsupported and N/A.
