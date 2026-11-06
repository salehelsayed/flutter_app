# Recording-switch transaction repair

This is the published Flutter `camera_avfoundation 0.11.1` implementation, retained
at the same version with an app-local path override. `UPSTREAM.json` records every
copied upstream file's SHA-256 and the published package archive checksum from the
parent lock. The original `DefaultCamera.swift` is retained as
`upstream/DefaultCamera.swift.original`, outside the compiled Sources tree.
Nothing modifies the shared pub cache or Flutter SDK.

The patch addresses CAMERA-20261105-01: an input-construction exception previously
occurred after the old graph was removed and configuration began. Three session
admission rejections also reported failure and then continued into add/success.
Dart retry/disposal could not balance that native configuration. Apple's
AVCaptureSession header requires commit before stopRunning; app-only cleanup was
therefore insufficient.

## Allowlisted changes

- `DefaultCamera.swift`: only `setDescriptionWhileRecording` changes. Prepare the
  replacement device/input/output/connection before mutating the live graph.
  Keep the old fields unpublished until success. On any of the three admission
  rejections, remove partial candidate state, restore the exact former video and
  photo connections and delegate, commit, reapply requested zero-shutter-lag state,
  and return one error. Writer/audio are untouched. Success retains the original
  orientation, photo-dimension and zero-shutter-lag logic.
- `CaptureSession.swift`: expose AVCaptureSession's existing read-only connections
  property so the method can retain and restore the actual prior connections.
  The upstream mock already owns this property; no new transaction abstraction.
- `MockCaptureDeviceInputFactory.swift` and `MockCaptureSession.swift`: add optional
  throwing/input/output/connection admission stubs, retaining their defaults.
- `SampleBufferTests.swift`: append four native fault cases with real DefaultCamera
  and the upstream graph/writer mocks. Check restoration and balanced configuration
  before the error callback, exactly one completion, uninterrupted recording/writer/
  audio ownership, a fault-cleared successful switch, and a single stop. All
  upstream tests/assertions remain. Fault-specific assertion messages distinguish
  real baseline regression evidence from setup/compilation failures.
- `example/pubspec.yaml`: remove its unused `build_runner` dev dependency only;
  native XCTest does not run that generator. Keep flutter_test, integration_test
  and all runtime dependencies. Pin SPM in the example's local Flutter config.
  Its newly generated `pubspec.lock` pins this separate native test host; it does
  not upgrade the app's dependencies. The initial offline missing-generator exit69
  and corrected offline exit0 are retained in the owner handoff artifacts.
- `lib/src/messages.g.dart`: remove the broad `unused_import, unused_shown_name`
  file suppression and the dead `dart:typed_data` and `package:meta/meta.dart`
  imports. None of their six shown names is referenced in the body. This is local
  header/import normalization, not Pigeon regeneration: retain the Pigeon v27.3.2
  marker, `type=lint`, other imports and every generated API/codec/wire/body byte.
  `UPSTREAM.json.files` retains the published hash; the patch allowlist identifies
  the normalized local file. No Pigeon schema is included in the published files.
- `.gitignore`: exclude generated Flutter/SPM/build/IDE inputs from the local fork.
  No generated registrants, caches, Pods, DerivedData or private inputs are tracked.

The app's pubspec/lock only path-pin this same iOS package. Android, Web, camera,
camera_platform_interface, app production Dart and translations are unchanged from
camera candidate `c284cf1c7`. Vendored production Dart changes only by the generated
header/import normalization above; its executable body is unchanged. No store
version, signing or deployment changes.

## Native proof boundary and execution

The app's RunnerTests target does not discover the upstream example's
CameraSampleBufferTests. Appium cannot inject CaptureDeviceInputFactory faults or
inspect native graph/configuration balance. The existing upstream XCTest host is
therefore reused through the narrowly scoped `scripts/camera_avfoundation_native.py`.
It runs exactly four recording-switch fault selectors on an explicitly discovered
available iOS simulator. Unavailable targets are N/A by project policy.

The adapter pins the candidate Flutter context, uses the existing native/device
leases and host-capacity guard, and reuses the bounded process/raw-capture launcher.
Each variant gets a new owned source copy and internal-disk DerivedData, jobs1,
source/generated-input hashes, raw logs, exit receipts and an xcresult. Signing
and automatic provisioning are disabled. Setup-check facts are not test PASS.

`--variant both` runs the original runtime against the SAME new native test source
and then the patched runtime. Only the owned baseline scratch copy receives the
retained original file. The two variant source maps must differ only at that
runtime file. Expected RED requires all four exact cases to fail with the
fault-specific native state assertion marker and a completed XCTest failure;
compiler/setup/partial/interrupted/skipped results cannot establish RED. GREEN
requires all four exact cases to pass with exit0 and an xcresult. All original
failed attempts remain separate, immutable evidence; there is no automatic retry.

The existing SIMS native lane registers `native.camera.recording_switch` and the
change selector registers `camera-ios-native`. Its declared build exception is
limited to compiling this upstream native assertion host and its two source
variants; it does not produce or deploy a Mknoon app. The receipt-adjudicator unit
check is `camera-native-runner`.

The execution owner can use `--setup-check --simulator-id <live-id>` before the
registered comparison. Authoring, dependency generation and syntax/formatting are
not native test proof. Native mocked graph/writer tests do not prove a real
playable clip, audio continuity, permissions or a signed/installed app. Those
remain separate available-device acceptance evidence. Web recording-switch support
is not claimed.
