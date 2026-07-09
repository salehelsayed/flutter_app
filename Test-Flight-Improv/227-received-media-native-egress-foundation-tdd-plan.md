# 227 - Received Media Native Egress Foundation

Status: execution-ready
Type: New Feature
Spec: free-text intent — save one or more received images/videos to the phone and share them through the OS without changing messaging transport
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `full_screen_image_viewer.dart`, `media_file_manager.dart`, `share_intent_service.dart`, `pubspec.yaml`, Android manifest/MainActivity, iOS Info.plist/AppDelegate, media/share tests, gate scripts | HEAD resolves app-owned media for rendering and only receives OS shares; it has no outbound Save/Share gateway. Native egress is isolated from all message transports. | Add causal gateway tests before native/Dart production edits. |

## Problem And Evidence

- Behavior to improve: a user who has received completed images/videos must be able to save one or a bounded selection to Photos/Gallery or Files/Downloads, or hand one selection to the OS chooser.
- Impact: the only current action is in-app viewing; users cannot retain or reuse ordinary received media outside Mknoon.
- Confirmed current gap: `FullScreenImageViewer` accepts only `localPath`, `allPaths`, and an optional video builder at `lib/shared/widgets/media/full_screen_image_viewer.dart:19`; its app bar has only Back and a page counter at `:62`.
- Confirmed current mechanism: `MediaFileManager.resolveStoredPath` re-roots relative/stale app-owned paths at `lib/core/media/media_file_manager.dart:219`; this is the canonical pre-egress resolver.
- Confirmed current gap: `ShareIntentService` wraps only `receive_sharing_intent` at `lib/core/services/share_intent_service.dart:16`; `pubspec.yaml:63` has an inbound share dependency but no outbound media egress implementation.
- Confirmed platform gap: Android has inbound `ACTION_SEND` filters but no outbound FileProvider/MediaStore egress handler (`android/app/src/main/AndroidManifest.xml:35`); iOS has read-library usage copy but no add-only usage key or media-egress channel (`ios/Runner/Info.plist:58`, `ios/Runner/AppDelegate.swift:8`).
- Existing coverage: `test/core/media/media_file_manager_test.dart` covers path ownership/resolution; `test/core/services/share_intent_service_test.dart` covers inbound buffering; neither can fail for outbound Save/Share behavior.
- Missing coverage: no Dart decision/gateway test, single/batch native OS proof, cancellation/permission proof, or scoped temporary-copy cleanup proof exists.
- Refuted findings: “received media is not downloaded” is refuted — completed attachments live under app Documents and are displayable; the missing behavior is user-visible egress, not relay download.
- Unresolved findings: N/A — the plan fixes the public contract and native mechanisms explicitly; interactive chooser destination behavior remains device-proof rather than host-asserted.
- Affected production, test, and gate files: new `lib/core/media/received_media_egress.dart`, new `lib/core/media/method_channel_received_media_egress_gateway.dart`, `media_file_manager.dart`, Android `MainActivity.kt`/manifest/FileProvider paths, iOS `AppDelegate.swift`/Info.plist, new Dart/device tests, and device-proof discovery.

## Scope Contract And Guard

In scope:
- Add public finite `kMaxMediaEgressItems` plus bounded-list `MediaEgressRequest`, `MediaEgressItem`, `MediaEgressDestination`, `MediaEgressItemResult`, aggregate `MediaEgressResult`, `ReceivedMediaEgressGateway`, and `ReceivedMediaEgressService`. The contract is bounded by the constant; lane plans do not invent separate native limits.
- Resolve, deduplicate by attachment ID, and validate every selected app-owned file before any platform call; ineligible items receive typed per-item results while the eligible ordered subset may proceed.
- Implement `saveToPhotos`, `saveToFiles`, and `shareExternally` through one `mknoon/received_media_egress` method-channel contract.
- Android: MediaStore for Gallery/Downloads and FileProvider `content://` URIs plus `ClipData`/`FLAG_GRANT_READ_URI_PERMISSION`; use `ACTION_SEND` for one item and `ACTION_SEND_MULTIPLE` for a batch.
- iOS: `PHPhotoLibrary.performChanges`, multi-URL `UIDocumentPickerViewController`, and multi-item `UIActivityViewController`.
- Return typed saved, chooser-presented, cancel, permission-denied, missing-file, unsupported-type, and platform-failure outcomes; do not claim an external recipient consumed a share. Clean only egress-owned temporary copies.

Must preserve:
- Relative/stale path recovery -> `test/core/media/media_file_manager_test.dart`; `GREEN sentinel`.
- Inbound cold/warm share capture -> `test/core/services/share_intent_service_test.dart`; `GREEN sentinel`.
- App-private originals and database rows remain unchanged after save/share/cancel -> `received_media_egress_service_test.dart::egress never deletes or rewrites the source attachment`; causal preservation row.

Hard `Do not`:
- Do not call `P2PService`, Bridge, relay, inbox, group publish, or go-libp2p code.
- Do not grant a raw filesystem path or broad storage permission to another app.
- Do not export pending, missing, integrity-failed, view-once, disappearing-expired, or policy-protected media.
- Do not claim that deleting a Mknoon message revokes a copy already saved/shared outside the app.
- Do not delete arbitrary absolute/gallery paths during temp cleanup.

Deferred / accepted difference:
- Viewer/bubble buttons and lane policy are owned by plans 231, 235, and 239.
- Library selection and UX are owned by plans 233, 237, and 241; this foundation proves both one-item and bounded-list native egress so those host plans do not make an unclosed batch-platform claim.
- Android API 24-28 legacy write-permission UX may use the existing `permission_handler`; API 29+ must use scoped MediaStore. Both are device-proofed.

Dependencies:
- Existing `MediaFileManager` path/ownership rules and app lifecycle/root view-controller availability.
- No dependency on 1:1, group, or announcement delivery plans.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-227-01 | A selection through `kMaxMediaEgressItems` completed app-owned image/video items resolves to canonical sources, deduplicates stable IDs, preserves order, and builds one request; cap+1 fails before native dispatch. | `test/core/media/received_media_egress_service_test.dart::completed app-owned selection builds one canonical bounded egress request` | host unit / temp directory + fake resolver/gateway, at-cap and cap+1 fixtures | HEAD compile RED: service/types/cap do not exist -> one gateway call contains ordered unique canonical paths, attachment IDs, MIME, and destination at the cap; cap+1 returns a typed rejection with zero native calls | bypass `resolveStoredPath`, key by path, remove the cap check, or accept a missing file -> TC-227-01 red | `flutter test test/core/media/received_media_egress_service_test.dart --plain-name 'completed app-owned selection builds one canonical bounded egress request'`; AUTO (`core-host-all`; `test/core/**`) |
| TC-227-02 | Pending, missing, quarantined, expired, or protected items fail closed per item and never cross native egress; eligible siblings may proceed once. | `test/core/media/received_media_egress_service_test.dart::mixed eligibility returns per-item truth and sends only the eligible subset` | host unit / table-driven items + fake gateway | HEAD compile RED -> each rejected item has its typed result; one ordered eligible subset call occurs, or zero calls when none qualify | pass the original unfiltered list or abort every eligible sibling -> TC-227-02 red | `flutter test test/core/media/received_media_egress_service_test.dart --plain-name 'mixed eligibility returns per-item truth and sends only the eligible subset'`; AUTO (`test/core/**`) |
| TC-227-03 | Save-to-Photos, Save-to-Files, one-item Share, and multi-item Share map to distinct native shapes and preserve ordered MIME/name metadata. | `test/core/media/received_media_egress_channel_test.dart::Dart channel maps single and batch destinations without path leakage` | host unit / mock MethodChannel messenger | HEAD compile RED -> exact methods/arguments and per-item/aggregate results pass; Share yields `presented`, never false delivery success; no raw path appears in diagnostics | map Files to Photos, map a batch to one-item send, or report share as recipient-delivered -> TC-227-03 red | `flutter test test/core/media/received_media_egress_channel_test.dart`; AUTO (`test/core/**`) |
| TC-227-04 | Cancel, denied permission, unsupported MIME, and native error are truthful and never delete the source. | `test/core/media/received_media_egress_service_test.dart::failed or cancelled egress preserves source and cleans only owned temp copies` | host unit / real temp files + fake native outcomes | HEAD compile RED -> original bytes/row callback untouched; egress cache removed only when owned | call `deleteFile(source)` in failure cleanup -> TC-227-04 red | `flutter test test/core/media/received_media_egress_service_test.dart --plain-name 'failed or cancelled egress preserves source and cleans only owned temp copies'`; AUTO (`test/core/**`) |
| TC-227-05 | Android saves an image+video selection through scoped MediaStore and shares it with read-only FileProvider URIs using the correct one/many Intent shape. | `integration_test/received_media_native_egress_proof_test.dart::android single and batch save share use scoped native destinations` | Android device proof / real MediaStore, chooser, app-private sources | HEAD manual/device RED: no channel implementation -> both saved items are visible; one-item chooser uses `ACTION_SEND`; batch uses `ACTION_SEND_MULTIPLE` with ordered `content://` ClipData/read grants; cancellation/presentation settles once | emit `file://`, omit any read grant, collapse batch to one URI, or write outside MediaStore -> TC-227-05 fails | `flutter test integration_test/received_media_native_egress_proof_test.dart -d "$ANDROID_DEVICE_ID" --dart-define=MEDIA_EGRESS_PLATFORM=android`; exact `ignored`/manual-native discovery rule |
| TC-227-06 | iOS saves an image+video selection, presents multi-file export/share from a live presenter, and settles permission/cancel/presented outcomes once. | `integration_test/received_media_native_egress_proof_test.dart::ios single and batch photos files share complete once` | iOS device proof / real PHPhotoLibrary, document picker, activity controller | HEAD manual/device RED: no channel -> both items reach the chosen save/export surface; one/many share shapes present; cancel/denied/presented completes exactly once and sources remain | omit add-only usage copy, drop one URL, double-complete, claim recipient delivery, or present off-root -> TC-227-06 fails | `flutter test integration_test/received_media_native_egress_proof_test.dart -d "$IOS_DEVICE_ID" --dart-define=MEDIA_EGRESS_PLATFORM=ios`; same exact `ignored`/manual-native discovery rule |
| TC-227-07 | Existing cold-start and warm-stream inbound OS share capture remains behaviorally independent. | `test/core/services/share_intent_service_test.dart::1d: intentStream emits converted intents from the plugin stream` and `::1e: getInitialIntent handles cold-start text shares` | `GREEN sentinel` / existing host plugin-stream and initial-intent fixtures | GREEN on HEAD -> both remain GREEN after outbound channel addition | reuse/reset the inbound plugin stream or initial-intent state from outbound egress -> sentinel red | `flutter test test/core/services/share_intent_service_test.dart --plain-name '1d: intentStream emits converted intents from the plugin stream'`; `flutter test test/core/services/share_intent_service_test.dart --plain-name '1e: getInitialIntent handles cold-start text shares'`; AUTO (`core-host-all`; `test/core/**`) |
| TC-227-08 | Egress is transport-free. | `test/core/media/received_media_egress_transport_boundary_test.dart::egress source imports no bridge p2p or messaging delivery modules` | host source-contract test | HEAD compile RED: target sources absent -> new Dart/native egress sources contain no P2P/Bridge/group publish imports or channel names | add a bridge/P2P import or call -> TC-227-08 red | `flutter test test/core/media/received_media_egress_transport_boundary_test.dart`; AUTO (`test/core/**`) |

### Test Notes

- TC-227-05/06 require a human to choose or cancel the OS destination; the test records the single Dart completion and displays the expected filename/hash so the operator can verify the visible saved copy. Host mocks do not substitute for these OS boundaries.
- Diagnostics may include attachment-id prefixes and typed outcomes, never source paths, captions, filenames derived from user text, or media bytes.

## Implementation Steps

1. Snapshot `git status --short`; add TC-227-01..04 and TC-227-08 before production edits.
2. Add the domain/service contract and fail-closed file/eligibility resolution in `lib/core/media/received_media_egress.dart`; stop-if any caller must import a delivery use case.
3. Add the Dart method-channel gateway with one-completion semantics and redacted telemetry.
4. Add Android MediaStore/FileProvider and iOS Photos/Files/share handlers plus least-privilege manifest/plist configuration.
5. Add the device proof and an explicit `ignored`/manual-native-proof rule in `scripts/check_reliability_simulation_discovery.sh`; run discovery, host GREEN, both platform closures, sentinels, and hygiene.

## Risks And Blind Spots

- Decrypted content leaves the app by user request -> TC-227-02 gates protected content; lane UI must disclose the irreversible boundary.
- URI/path leakage -> TC-227-03/05 and redacted telemetry assertions.
- Lifecycle/presenter races -> TC-227-06 proves completion once through success/cancel/denial.
- Lifecycle / derived-state durability: N/A — egress is an immediate action with no durable in-app derived state.
- Sibling-surface consistency: lane plans own button parity; TC-227-08 ensures the shared primitive stays surface-neutral.
- Destructive-action side effects: TC-227-04 asserts original and arbitrary paths survive.
- Invariant re-verification under new transitions: every gateway result rechecks mounted/completion state and owned-temp identity; TC-227-04/06.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# First causal RED; expect non-zero because the egress contract is absent
flutter test test/core/media/received_media_egress_service_test.dart --plain-name 'completed app-owned selection builds one canonical bounded egress request'

# Focused host GREEN; expect exit 0 and zero failed tests
flutter test test/core/media/received_media_egress_service_test.dart
flutter test test/core/media/received_media_egress_channel_test.dart
flutter test test/core/media/received_media_egress_transport_boundary_test.dart

# Shared preservation and core sweep; expect exit 0
flutter test test/core/media/media_file_manager_test.dart test/core/services/share_intent_service_test.dart
./scripts/run_host_test_gates.sh core-host-all

# Discover devices, then run once on Android and once on iOS; each must complete all prompted checks
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^ignored[[:space:]]+ignored[[:space:]]+integration_test/received_media_native_egress_proof_test\.dart[[:space:]]+'
flutter devices --machine
test -n "$ANDROID_DEVICE_ID"
test -n "$IOS_DEVICE_ID"
flutter test integration_test/received_media_native_egress_proof_test.dart -d "$ANDROID_DEVICE_ID" --dart-define=MEDIA_EGRESS_PLATFORM=android
flutter test integration_test/received_media_native_egress_proof_test.dart -d "$IOS_DEVICE_ID" --dart-define=MEDIA_EGRESS_PLATFORM=ios

# Hygiene; expect no new analyzer issues or whitespace errors
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: single-device, repeated on one Android and one iOS physical device (simulators may support chooser smoke but do not close Photos/Gallery visibility).
- Boundary being proven: real MediaStore/FileProvider, PHPhotoLibrary/document picker/activity controller presentation, permissions, URI grants, and cancellation callbacks.
- Live availability check: `flutter devices --machine` -> export distinct `$ANDROID_DEVICE_ID` and `$IOS_DEVICE_ID`; a missing platform leaves that row environment-blocked, not GREEN.
- Required setup: ordinary downloaded JPEG and MP4 fixtures copied into the app-owned media directory; Photos/storage permission initially undecided; operator able to accept and deny once.
- Closure role: required closure evidence for native egress; no relay is involved.
- Device selectors: `$ANDROID_DEVICE_ID` and `$IOS_DEVICE_ID` are required explicitly so the two commands cannot accidentally reuse one default target.
- Registration: add an exact `integration_test/received_media_native_egress_proof_test.dart` case to `classify_path` in `scripts/check_reliability_simulation_discovery.sh`, recording category/kind `ignored` with note `manual Android/iOS received-media native egress proof outside default reliability-sim`; do not add it to a transport family array.
- Discovery command: `./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg 'ignored[[:space:]]+ignored[[:space:]]+integration_test/received_media_native_egress_proof_test.dart'`; expect exactly one classified record and no unclassified record for the path.
- Closure commands: the two platform-specific `flutter test` commands above; each exits 0 only after the prompted save/share/cancel observations complete once.
- Deferred device work: none; both platform rows are required before implementation closure.

## Execution Interpretation And Done Criteria

- Expected RED: TC-227-01 fails to compile because `ReceivedMediaEgressService` does not exist.
- Green sentinel: existing media path and inbound share tests remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Environment blocker: absent Android/iOS physical device blocks only the corresponding required device row and therefore final closure.
- Scope drift: any messaging wire, relay, encryption-key distribution, or go-libp2p edit requires a new lane plan and blocks this plan.

- [ ] Every behavior has a named test or justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation and core gates pass with semantic outcomes.
- [ ] Device proof is classified and passes on Android and iOS.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/core/media/received_media_egress_service_test.dart --plain-name 'completed app-owned selection builds one canonical bounded egress request'`.
- Preservation command: `flutter test test/core/media/media_file_manager_test.dart test/core/services/share_intent_service_test.dart`.
- Manual registration: add the exact proof path as `ignored`/manual native proof in `scripts/check_reliability_simulation_discovery.sh`; no family-array edit.
- Migration: none.
- Boundary closure: Android + iOS physical-device egress proof; no relay/crypto claim.
- Unresolved evidence: none; unavailable devices are execution environment blockers, not planning evidence gaps.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
