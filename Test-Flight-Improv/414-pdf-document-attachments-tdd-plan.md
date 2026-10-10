# Plan 414 — PDF attachments in 1:1 and group chats (TDD)

Status: IMPLEMENTED 2026-10-10 on branch `pdf-attachments-407` (worktree `.claude/worktrees/pdf-407`). Lanes green. Device proof partial: iPhone UI steps blocked. Decisions D1-D5 confirmed by the user 2026-10-10.
Origin: user request 2026-10-10. "The app shares images, videos and audio, but not PDF."
Scope: PDF only (`application/pdf`). Other document types (docx, xlsx, zip and so on) are out of scope.

Anchors below come from source reads on `wave3-baseline-20260930` @ `0b61b27c1`. Re-check each line number before editing.

## Problem

A user cannot send a PDF today.

- **No picker.** `pubspec.yaml` has `image_picker` only. `MediaPicker` (`lib/core/media/media_picker.dart:5-26`) offers gallery, photo and video. The attach sheets have three options: `conversation_wired.dart` ~:5609-5660, `group_conversation_wired.dart` ~:4748, `linked_group_conversation_wired.dart:399`.
- **No PDF MIME.** Four copies of `_mimeFromPath` miss `pdf`. They are `conversation_wired.dart:5548-5566`, `group_conversation_wired.dart:7718`, `share_batch_delivery_coordinator.dart:2727-2745` and `posts_wired.dart:1122`. A PDF becomes `application/octet-stream`. `MediaAttachment.mediaTypeFromMime` (`media_attachment.dart:165-170`) then sets `mediaType = 'file'`.
- **Groups block PDFs on purpose.** `lib/core/media/group_media_mime_policy.dart:15-27` allows only image, video and audio. `:136-141` rejects the PDF file signature as `dangerous_signature`.
- **1:1 accepts but shows nothing.** The share sheet (`AndroidManifest.xml:80-100` `*/*`, iOS `Share Extension/Info.plist:26-27`) lets a PDF into 1:1 as `octet-stream`. Upload and download have no 1:1 MIME check (`upload_media_use_case.dart:487`, `download_media_use_case.dart:2137-2200`). The receiver auto-downloads it. `LetterCard` draws only image/video (`letter_card.dart:191`) and audio (`:194`). `LetterBubble` behaves the same (`letter_bubble.dart:70-75`). The result is an empty bubble. The stored file has no extension, because `extensionFromMime('application/octet-stream')` returns `''` (`media_file_path_convention.dart:65`).
- **No file name.** The wire format (`media_attachment.dart:249-302`) and the `media_attachments` table (`migrations/010_media_attachments.dart:19-31` and later ALTERs) have no name field.
- **No way to open a file.** No `ACTION_VIEW`, `QLPreviewController` or `UIDocumentInteractionController` exists. Save and share (`ReceivedMediaEgress`) refuse PDFs in four places: Dart `received_media_egress.dart:85`, `:130-141`; Swift `ReceivedMediaEgressCoordinator.swift:206-208`; Kotlin `ReceivedMediaEgressHandler.kt:165-168`; provider `ReceivedMediaEgressProvider.kt:64-74`.

Already in place and kept:
- The `'file'` kind in `MediaStorageKind` (`media_storage.dart:6-15`) and both private-media kind enums.
- A 100 MB per-file cap for `'file'` (`group_media_size_policy.dart:14`, `:29-45`). It runs in both composers and in the share batch.
- Chat-list and notification labels for files (`orbit_media_preview_label.dart:50-51`, `notification_preview_copy.dart:45-46`, `NotificationPreviewResolver.swift:3317-3318`).
- `extensionFromMime('application/pdf')` returns `.pdf` (`media_file_path_convention.dart:63`).
- 1:1 delete removes every attachment file (`delete_message_use_case.dart:1287-1315`). Group delete-for-me removes the file when the extension is not empty (`group_media_deletion_journal_db_helpers.dart:89-106`).
- Private media (view-once, disappearing) already excludes `'file'` (`private_media_policy.dart:76-98`, `:410-412`).
- **Go bridge and relay need no change.** The relay checks only that the MIME is 1-255 printable ASCII characters (`go-relay-server/media_custody.go:282-289`), with a 5 GB cap (`media.go:28`). The bridge needs a non-empty MIME (`go-mknoon/node/media.go:906`).

## Decisions (confirmed by the user 2026-10-10, all defaults)

| # | Decision | Chosen | Why |
|---|---|---|---|
| D1 | Which types | PDF only | One file signature to check. Every other type keeps its current behaviour. |
| D2 | How to view | The OS viewer. iOS: `QLPreviewController` (Quick Look, runs out of process). Android: `ACTION_VIEW` through the existing `ReceivedMediaEgressProvider` with a read grant. | No PDF parser in our process. An in-app renderer (`pdfx`, pdfium) would parse untrusted PDFs inside the app. |
| D3 | Old group clients | Ship receive and display first. Turn on sending later with a dart-define, `MKNOON_ENABLE_DOCUMENT_ATTACHMENTS` (follow the `VOICE_CALL_*` pattern). Default off. | There is no capability exchange (no version field on `GroupMember`, `group_member.dart:80-87`). An old group client drops the whole message (`handle_incoming_group_message_use_case.dart:258-269`). |
| D4 | Non-PDF files from the share sheet | Reject them with the existing unsupported-media message. Do not send them as `'file'`. | Today they arrive as an invisible bubble in 1:1. |
| D5 | Picker package | `file_picker` with `FileType.custom, allowedExtensions: ['pdf']` | It uses the system document picker on both platforms. MIT licence. |

## Design

### S1 — One MIME helper
- New `lib/core/media/media_mime.dart` with `mimeFromPath(String path)`. It holds today's map plus `pdf` → `application/pdf`.
- Replace the four `_mimeFromPath` copies with calls to it. Keep their outputs identical for every existing extension.
- Add `isSupportedDocumentMime(String mime)`. It returns true only for `application/pdf`.

### S2 — File name on the wire and in the database
- Add `String? fileName` to `MediaAttachment`: fields (`media_attachment.dart:20-60`), `fromMap`/`toMap` (:175-240) and `fromJson`/`toJson` (:249-302). Write the key only when it is not null, so image/video/audio JSON is unchanged.
- Migration `lib/core/database/migrations/120_media_attachment_file_name.dart`: `ALTER TABLE media_attachments ADD COLUMN file_name TEXT`.
  - Register it in both lists in `production_migration_registry.dart` (create :685-689, upgrade :1243-1247, import :121).
  - Bump `currentIdentityDatabaseVersion` (`app_database_version.dart:80`).
  - Update the hard-coded 119 in `full_migration_chain_test.dart` (:1487, :1507, :1522, :1585).
- New `sanitizeAttachmentFileName(String raw)`, used on send and on receive:
  - Take the base name only (drop `/` and `\` parts).
  - Remove control characters and bidi override characters (U+202A-U+202E, U+2066-U+2069).
  - Cap the length at 120 characters and keep the extension.
  - Fall back to `document.pdf` when the name is empty.
- The name is for display only. The file on disk keeps the `media/<peerOrGroupId>/<blobId>.pdf` path (`media_file_path_convention.dart:6-12`).

### S3 — Policy (the security change)
- **Group.** In `group_media_mime_policy.dart`:
  - Add `'application/pdf': 'file'` to `allowedMimeToMediaType` (:15-27).
  - In the signature check (:136-141), accept `_DetectedSignature.pdf` only when the declared MIME is `application/pdf`. A PDF signature under any other MIME stays `dangerous_signature`.
  - Add the `pdf` case to `_signatureMatchesMime` (:240-253).
  - html, exe and zip stay blocked.
  - This one file feeds upload, send, receive, download, retry, custody, integrity, composer, grid cell and forward. See the list in the Risks section.
- **1:1.** Add a narrow check for `mediaType == 'file'` only. Image/video/audio 1:1 behaviour stays the same.
  - On send: the MIME must be `application/pdf` and the first bytes must be `%PDF-`.
  - On download: when the bytes are decrypted, a declared `application/pdf` file must start with `%PDF-`. If not, mark the attachment failed. Never open it.
  - An incoming `'file'` with any other MIME keeps today's storage behaviour, but it shows the unsupported tile (S4).
- **Share sheet (D4).** In `share_batch_delivery_coordinator.dart`, files whose MIME is not image/video/audio and not `application/pdf` are skipped. Use their own skip reason, not `skippedOversizedGifCount` (:1576).
- **Private media.** The private toggle stays off when a document is pending. Eligibility already says no. Add a test so it stays that way.

### S4 — Display and open
- New `DocumentAttachmentTile` widget: PDF icon, file name, size, and the state (uploading, downloading, failed with retry, ready). Tapping a ready tile opens it.
- Use it in `LetterCard` (`letter_card.dart:190-194`, `:439-470`) and `LetterBubble` (`letter_bubble.dart:70-110`) for `mediaType == 'file'`. These widgets serve both 1:1 and group (`letter_card_group_test.dart`, `letter_card_one_to_one_test.dart`).
- A `'file'` whose MIME is not `application/pdf` shows an "Unsupported file" tile and cannot be opened.
- **Open (D2).** Add destination `open` to `ReceivedMediaEgress` (`received_media_egress.dart:9`).
  - Dart: allow `application/pdf` in the request check (:85) and add `.pdf` to `mediaEgressExtensionForMime` (:130-141).
  - iOS (`ReceivedMediaEgressCoordinator.swift`): add `application/pdf` to `allowedMimes` (:206-208). `open` presents `QLPreviewController` on a temporary copy, and deletes the copy on dismiss.
  - Android: add `application/pdf` to `allowedMimes` (`ReceivedMediaEgressHandler.kt:165-168`). `getType` returns `application/pdf` for `.pdf` (`ReceivedMediaEgressProvider.kt:64-74`). `open` fires `ACTION_VIEW` with `FLAG_GRANT_READ_URI_PERMISSION`. If no app can handle it, return a typed `no_viewer` result. Dart shows a message.
- Save to Files and Share work for PDFs through the same allowlist change.
- The shared-media library and long-press "save to Photos" stay image/video only (`conversation_screen.dart:2035`, `:2066`, `:2204`; `direct_shared_media_library_screen.dart:49`). The long-press menu on a document offers Save to Files and Share.

### S5 — Pick and send
- Add `file_picker` to `pubspec.yaml`. Add `pickDocuments()` to `MediaPicker` and to `test/shared/fakes/fake_media_picker.dart`.
- Add a "Document" row to the three attach sheets. It shows only when `MKNOON_ENABLE_DOCUMENT_ATTACHMENTS` is true. The linked role must still respect `modalityGate.allowsMediaAuthoring` (`conversation_wired.dart:5568-5580`).
- A picked PDF goes through the existing pending-media path with `mediaType 'file'`, the sanitized `fileName` and the 100 MB cap.
- The group path keeps the real MIME on upload. Group download compares the relay MIME with the expected MIME (`download_media_use_case.dart:3333-3345`). 1:1 keeps the opaque MIME on the relay (`media_attachment.dart:14`).

### S6 — Text and translations
- `media_preview_text.dart:45-47` has hard-coded English `'File'` / `'N files'`. Move them to l10n. Show the file name when there is one PDF. Add a document icon to `mediaPreviewIcon` (:54-66).
- New keys in every `lib/l10n/app_*.arb`: attach "Document", "Unsupported file", "No app can open this file", "Could not open the file", "Only PDF files can be shared".
- Existing keys are reused: `orbit_preview_file`, `notification_group_reaction_target_file`, `settings_media_type_file`, `media_save_destination_files`.

## TDD rows

Each row is written RED first, then made GREEN. Record evidence in `Test-Flight-Improv/evidence/414/`.

| Slice | Test file → test | Expected RED |
|---|---|---|
| S1 | `test/core/media/media_mime_test.dart` (new): `pdf maps to application/pdf`; `every extension the four old copies knew maps the same` | compile (file missing) |
| S1 | same: `isSupportedDocumentMime accepts only application/pdf` | compile |
| S2 | `media_attachment_test.dart`: `fileName round-trips through JSON and map`; `JSON without fileName decodes to null`; `image attachment JSON has no fileName key` | compile (`fileName` missing) |
| S2 | `test/core/database/migrations/120_media_attachment_file_name_test.dart` (new): column added on upgrade and create; existing rows keep null | compile |
| S2 | `full_migration_chain_test.dart`: version 120 | fail (119) |
| S2 | `test/core/media/attachment_file_name_test.dart` (new): path parts dropped; bidi and control characters removed; long name capped and keeps `.pdf`; empty → `document.pdf` | compile |
| S3 | `group_media_mime_policy_test.dart`: `application/pdf with %PDF- bytes is valid file`; `PDF bytes declared as image/jpeg stay dangerous_signature`; `application/pdf with non-PDF bytes is invalid`; `zip, html, exe still dangerous` | fail (pdf rejected) |
| S3 | `handle_incoming_group_message_use_case_test.dart`: a group message with a PDF descriptor is stored, not `ignored` | fail (ignored) |
| S3 | 1:1 send and download tests: `file with non-PDF bytes is refused on send`; `downloaded application/pdf without %PDF- is marked failed` | fail |
| S3 | `share_batch_delivery_coordinator` test: `a .docx share is skipped with the unsupported-document reason`; `a .pdf share sends application/pdf` | fail |
| S3 | private-media eligibility test: a pending PDF keeps the private toggle off | pass expected (guard row) |
| S4 | `test/features/conversation/presentation/widgets/document_attachment_tile_test.dart` (new): name, size, states, tap fires open only when ready | compile |
| S4 | `letter_card_test.dart`, `letter_bubble_test.dart`, `letter_card_group_test.dart`, `letter_card_one_to_one_test.dart`: a `'file'` PDF attachment renders the tile; a non-PDF `'file'` renders the unsupported tile | fail (empty) |
| S4 | `received_media_egress_channel_test.dart` / `_service_test.dart`: `open` destination accepted for PDF; `no_viewer` result maps to the message | fail |
| S4 | Kotlin: provider `getType` for `.pdf`; handler `open` builds `ACTION_VIEW` with a read grant (via `run_call_native_unit_tests.sh` or the egress unit test task) | fail |
| S5 | composer wired tests (1:1, group, linked): "Document" hidden when the flag is off; shown when on; linked role without authoring hides it; a picked PDF becomes a pending `'file'` with `fileName` | fail |
| S6 | `media_preview_text` test: one PDF shows its name; plural is localized | fail |

Swift (`QLPreviewController`) cannot be unit-tested here. Prove it on the iPhone.

## Gates

1. After each slice: `python3 graphify-arch/tdd_context.py affected <changed files> --budget 600`. Run the tests it names first.
2. `flutter analyze` on the changed files is clean. `dart format` is clean. Do not run `dart fix --apply`.
3. Register new test files in `scripts/run_test_gates.sh`:
   - Media and policy tests: `ONE_TO_ONE_TESTS` (:32) and `GROUP_TESTS` (:581).
   - Widget tests: `FEED_TESTS` (:509).
   - Migration 120: the same arrays that hold 117 and 118 (`run_test_gates.sh:64`, `:217`).
   - Also add them to `ONE_TO_ONE_HOST_TESTS` in `scripts/run_host_test_gates.sh` (:18).
   - Then grep the arrays. The completeness check passes on regex fallbacks and proves nothing (memory: GROUP_TESTS unenforced).
4. Lanes, in this order, with the tree frozen: 1:1 lane, group lane, feed lane, then host-all through `host-run`.
5. Run `graphify-arch/refresh_arch_graph.sh --incremental` once after the code is done.

## Device proof (Pixel 6 + iPhone 13)

Build with `MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true`. Use the provenance-checked deploy scripts.

1. 1:1 iPhone → Pixel: pick a 2 MB PDF. The tile shows the name and size on both phones. Tap opens the Android viewer.
2. 1:1 Pixel → iPhone: same. Tap opens Quick Look. Dismiss deletes the temporary copy.
3. Group of 3: send a PDF with a caption. Every member sees the tile and the caption.
4. Share sheet: PDF from the iOS Files app, Mail and Safari, and from Android Files. The `com.adobe.pdf`-only provider case is unverified (`ShareViewController.swift:71`, `:109-113`). Fix it here if it fails.
5. A `.docx` from the share sheet is refused with the message.
6. A 101 MB PDF is refused by the size cap.
7. Delete-for-me on a PDF message removes `media/<id>/<blob>.pdf` on both phones.
8. Notification and chat-list text show the file name.

## Risks

| # | Risk | Effect | Mitigation |
|---|---|---|---|
| R1 | **Old group clients drop the whole message.** No version exchange exists. A PDF fails `_validateIncomingMediaDescriptors` → `ignored` (`handle_incoming_group_message_use_case.dart:258-269`). | Members on old builds never see the PDF or its caption. They get no hint that a message arrived. | D3: release receive support first. Turn on sending only when testers are on that build. Tell testers to update. |
| R2 | **Old 1:1 clients show an empty bubble.** They store `'file'`, auto-download it, and `LetterCard` draws nothing. The file has no `.pdf` extension. | A blank message. A caption still shows. Chat list says "File". | Same release order (D3). Accept the blank bubble for the short overlap. |
| R3 | **Security: PDFs were blocked as dangerous on purpose.** | A crafted PDF could attack a PDF viewer. | PDF only (D1). Match the MIME and the `%PDF-` signature on send and receive, 1:1 and group. Open only in the OS viewer, never in our process (D2). html, exe and zip stay blocked. |
| R4 | **Android has no guaranteed PDF viewer.** | Tap does nothing on some phones. | Typed `no_viewer` result and a message. Save to Files and Share still work. |
| R5 | **Many group sites use one policy file.** Upload :487/:514/:688, send `send_group_message_use_case.dart:1297`, receive :1225/:1607/:1712, download :2138/:2819/:3335/:3544, both retry use cases, custody coordinator :1017, integrity policy :200/:307, composer :4502/:7744, `media_grid_cell.dart:160`, forward `build_received_media_forward.dart:288`. | A PDF passes one site and fails another, so it sticks in "sending" or "downloading". | Run the full group lane. Device step 3. Check `media_grid_cell` and forward with a PDF on purpose. |
| R6 | **The file name is untrusted input.** | Bidi tricks (`evil‮fdp.exe`), path parts, very long names. | `sanitizeAttachmentFileName` on send and receive. The name is display-only. The disk path never uses it. |
| R7 | **Migration 120.** | A failed upgrade blocks app start. | Additive nullable column only. Migration test plus the full chain test. |
| R8 | **MIME map merge changes an existing type.** | Images or videos get a different MIME and break. | The S1 test pins every old extension to its old MIME. |
| R9 | **Share-sheet behaviour change (D4).** | A user who shared other file types into 1:1 now gets a refusal. Today those arrive blank, so nothing useful is lost. | Clear message. Mention it in release notes. |
| R10 | **Storage use.** 1:1 auto-download includes `'file'` by default (`media_download_preferences.dart:20-33`). | Up to 100 MB per PDF downloads without asking. | Keep the default, which matches video. The user can turn `'file'` off in settings. |
| R11 | **iOS share extension may skip some PDFs.** Providers that offer only `com.adobe.pdf` are skipped (`ShareViewController.swift:71`). | PDFs shared from some apps never arrive. | Device step 4. Add `com.adobe.pdf` handling if it fails. |

## Not in this plan

- Other document types (docx, xlsx, txt, zip).
- An in-app PDF renderer or page thumbnails.
- PDFs in posts. `posts_wired.dart` keeps its own MIME map, which differs from the chat maps.
- Sending PDFs from the linked-device group screen. It opens the gallery directly through a separate runtime (`linked_group_conversation_wired.dart:396`). Receiving and showing PDFs there works, because it uses the same bubble widgets.
- A general app-version or capability exchange between peers. It would fix R1 and R2 for every future media type, so it deserves its own plan.

## Execution (2026-10-10, worktree `.claude/worktrees/pdf-407`, branch `pdf-attachments-407`)

The plan was first numbered 407. That number, and 408 to 413, were already used by call work (`evidence/407/` holds plan 407 call evidence), so this plan is 414.

### Changes from the design above

- **Build switch name.** `MKNOON_ENABLE_DOCUMENT_ATTACHMENTS` (`lib/core/config/document_attachments_flag.dart`), following the repo's `MKNOON_ENABLE_*` defines. The 1:1 and group screens take `documentAttachmentsEnabled` so tests can turn it on.
- **Strict group media.** Group media with strict delivery is rebuilt on receive from a signed list of fields (`ProtectedGroupMediaAttachmentCommitment`), so `fileName` was added there too. It is written only for documents, so image, video and audio messages keep the exact old field set. The stored copy of that list (`group_messages_db_helpers.dart`) accepts the same optional key and re-encodes byte for byte.
- **1:1 receive check.** The `%PDF-` check runs where a PDF leaves the app (open, Save to Files, Share) in `ReceivedMediaEgressService`, not during download. A file labelled PDF with other bytes is refused there. Group downloads also get the check from `GroupMediaMimePolicy.validateFile`.
- **Save and share.** The document tile has its own menu: Save to Files and Share. PDFs never go to Photos (Dart, Swift and Kotlin all refuse it).
- **Upload name.** `runUploadMedia` takes an optional `fileName` and stamps it on the uploaded attachment. `UploadMediaFn` is unchanged, so no test fake had to change.
- **Share sheet.** Skipped files reuse the existing skip count and reason fields of `ProcessedShareMediaBatch`. The reason is English text, like the existing reasons there.
- **Text.** `mediaPreviewText` (quote previews) shows the name of a single PDF and a document icon. Its other words stay English, as they are for every media type today. Chat list and notification text keep the existing translated "File" label.

### Evidence (`Test-Flight-Improv/evidence/414/`)

- `s1_s2_run1_red_db_offsets.txt`: first run, 432 passed, 4 failed. Three old migration tests checked list positions that v120 moved. One new file was not yet used by app code. All four fixed.
- `s1_s3_run2.txt`: 722 passed, 1 failed (`uploadMedia infers mediaType from mime` used non-PDF bytes for `application/pdf`; fixture fixed). `s3_upload_rerun.txt`: that file 43/43.
- `analyze_all.txt`: whole-project analyzer, 0 errors (1 old info in `linkable_text_test.dart`).
- `s4_s5_run1.txt`: 1341/1341 passed (tile, bubbles, egress, composers, received-media action suites, `test/core/media/`, `test/shared/widgets/media/`).
- `s4_new_tests_names.txt`: per-test list for the new files, 162/162 passed. `s6_preview_names.txt`: 10/10.
- `kotlin_egress_run3_junit.xml`: Android `ReceivedMediaEgressNativeTest` 14/14 (3 new). Runs 1 and 2 failed to build: `file_picker` was not yet installed, and then `file_picker` 11 skipped its Kotlin sources because this project keeps `android.builtInKotlin=false`. Fixed in `android/build.gradle.kts` by applying the Kotlin plugin to `:file_picker` only.
- `lane_summary.txt`: groups 5386/5386, feed 339/339, completeness PASS, runtime-roots PASS, 1:1 Flutter 5203/5203 plus macOS integration 2/2. The 1:1 lane still exits 64 in `go_binding_staleness_contract_test.sh`, which fails the same way in the main checkout (pre-existing, no Go change here).
- Lanes run with `FLUTTER_DEVICE_ID=macos` (`docker-ws/pdf414_lane.sh`), so integration tests never install debug builds on the phones.
- Swift (`ReceivedMediaEgressCoordinator.swift`, Quick Look) is not compiled by any of the above; the iOS device build is its first check.

## Device proof (2026-10-10) — partial

Full table: `evidence/414/e2e/E2E_RESULTS.md`.

- PASS on the Pixel 6: "Document" row, fake PDF refused, 1:1 PDF send, opening the PDF in Drive PDF Viewer, group PDF send.
- PASS on the iPhone 13 (file level): both PDFs downloaded and decrypted, byte-equal to the originals; the release build with the Quick Look Swift code compiles and installs.
- BLOCKED: iPhone UI steps (tile, Quick Look, Save to Files, iPhone-to-Pixel send). XCUITest could not enable automation mode on three attempts.
- NOT RUN: share sheet on the device (shell shares cannot grant URI access; the chooser lists five "MKnoon" test builds).
- Findings F1 (viewer title), F2 (share plugin crash on unreadable URIs) and F3 (share-sheet text) were fixed the same day; see `E2E_RESULTS.md`. F1 and F2 are proven on the Pixel.

Status: implementation done and lane-green; device proof partial (iPhone UI steps pending).

