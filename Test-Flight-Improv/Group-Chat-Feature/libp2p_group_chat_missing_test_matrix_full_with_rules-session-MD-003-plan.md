# MD-003 Session Plan - Media Content And Thumbnail Hash Verification

Session id: `MD-003`  
Source row id: `MD-003`  
Source doc: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`  
Breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

Final verdict: `implementation-ready after evidence collection`, but not currently coverable. The row remains `Partial` today because group media has no first-class content hash or thumbnail hash metadata, and downloaded files are marked `done` after MIME/size/signature checks only. It is safe to execute this plan now as a narrow code-plus-tests session, but unsafe to mark `MD-003` `Covered` without the implementation and proof below.

## Evidence Collector

- Source row `MD-003` is P0/Partial: media metadata must contain hashes and encrypted content IDs; valid media should display only after verification; tampered chunks, hashes, thumbnails, or metadata should fail closed and quarantine the item.
- Breakdown classifies `MD-003` as `needs_repo_evidence` / `evidence-gated`. The evidence gate is now resolved: current repo evidence shows a real implementation gap, not an already-covered row.
- `MediaAttachment` carries `id`, `messageId`, `mime`, `size`, `mediaType`, dimensions/duration, `localPath`, `downloadStatus`, `createdAt`, waveform, and upload retry count only. `fromMap`, `toMap`, `fromJson`, and `toJson` have no `contentHash`, `thumbnailHash`, digest algorithm, encrypted content id, or verification state.
- The `media_attachments` DB table has columns for id, message id, MIME, size, media type, dimensions/duration, local path, download status, and creation time, plus later waveform and upload retry columns. It has no hash or integrity columns.
- `callP2PMediaUpload` sends `id`, recipient, MIME, file path, and optional `allowedPeers`; `callP2PMediaDownload` sends `id` and `outputPath` and expects only `ok`, `id`, `mime`, and `size`. No hash is sent to or returned from the Dart bridge.
- Go media upload/download mirrors the same contract. `mediaRequest`, `mediaResponse`, and `MediaMeta` carry id, from/to, MIME, size, and creation time; the node streams bytes and verifies exact byte count only.
- `sendGroupMessage` serializes `MediaAttachment.toJson()` into live publish and encrypted inbox replay payloads. Because `toJson()` has no hash fields, live and replay media descriptors cannot carry a digest today.
- `handleIncomingGroupMessage` validates MD-001 MIME and MD-002 size, then saves incoming media as pending attachments. Duplicate enrichment uses the same path. It does not require or validate hashes.
- `GroupMessageListener` persists media through `handleIncomingGroupMessage`, then uses persisted attachments for notification preview and auto-download. Auto-download calls `downloadMedia(enforceGroupMediaPolicy: true)`.
- `downloadMedia(enforceGroupMediaPolicy: true)` rejects invalid MIME, oversized descriptors, relay MIME mismatch, bad file size, and spoofed known signatures, then calls `updateLocalPath`, which marks the row `done`. It does not compute or compare any content or thumbnail digest before save/display.
- `GroupConversationWired` retries pending/failed media downloads for visible messages and replaces failed downloads with `downloadStatus: failed`; display resolution trusts existing `done` local paths if the file exists.
- `MediaGridCell` blocks invalid MIME/size legacy rows and displays `done` image/video paths via `MediaThumbnailImage`. It has no hash guard. `MediaThumbnailImage` generates video thumbnails locally from the displayed media path unless an explicit thumbnail path is passed, but group attachments do not currently expose a thumbnail blob/path/hash field.
- Existing tests now cover MD-001 and MD-002 boundaries, including MIME, size, spoofed signature, live receive, inbox replay, listener, download, display, foreground push, and fake-network media fan-out. `rg` found no group media test for `contentHash`, `thumbnailHash`, `sha256`, digest verification, or integrity quarantine.
- `package:crypto` is already available in `pubspec.yaml`, and local discovery code has SHA-256 examples, but those helpers are not wired into group media metadata or download/display.

## real scope

Implement the smallest group media integrity contract needed for MD-003:

- Add first-class digest metadata to `MediaAttachment` for group media descriptors and persistence, at minimum `contentHash` for the blob bytes currently uploaded/downloaded through the media relay.
- Add thumbnail digest handling only for a real thumbnail surface. Since current group media has no first-class remote thumbnail blob/path, the executor must either prove no remote thumbnail can display or add the smallest `thumbnailHash` metadata needed for any thumbnail object it introduces or discovers. Do not add new thumbnail transport just to create product scope.
- Compute the content hash before group upload/publish and include it in live publish and encrypted inbox replay descriptors.
- Require and validate the content hash on live receive, inbox replay, auto-download, explicit download, startup display recovery, and legacy `done` display paths.
- On hash mismatch, missing required hash, malformed digest, or decrypt failure if an existing decrypt surface is involved, fail closed by deleting the downloaded file when present and marking the attachment with a non-displayable integrity/quarantine state.
- Add regression-first unit, application, widget, fake-network, and foreground integration coverage for valid download and tampered media.

Out of scope:

- MD-004 media key derivation/context separation.
- MD-005 chunk resume and verified partial chunks.
- MD-006 content-level deduplication.
- MD-007 encrypted thumbnail/privacy product work.
- MD-011 removed-member media access.
- MD-012 quarantine UI/retry controls beyond a data-level non-displayable status.
- MD-014 simulator/device matrix expansion.
- Generic file support, relay-wide media redesign, per-group configurable integrity policy, or new media product types.

## closure bar

`MD-003` can be marked `Covered` only when all required repo-owned proof exists:

- New group media sends compute and persist a canonical content digest for the exact bytes that are uploaded to the relay under the current media architecture.
- Live publish and encrypted inbox replay media descriptors include that digest, and receive-side code rejects media descriptors with missing, malformed, or mismatched digest metadata before trusted display.
- `downloadMedia(enforceGroupMediaPolicy: true)` computes the downloaded file digest before `updateLocalPath`, before `downloadStatus: done`, and before any UI can render the file.
- Hash mismatch or decrypt failure deletes any downloaded file and persists a non-displayable failed/quarantined state; notification preview, auto-download completion, feed/group conversation display, media grid, and full-screen viewer cannot render unverified bytes.
- Thumbnail handling is closed in one of two ways: either group code proves no first-class remote thumbnail is accepted or displayed and generated thumbnails are derived only after verified content, or first-class thumbnail metadata includes a thumbnail hash and tests prove tampered thumbnails do not display.
- Existing MD-001 MIME and MD-002 size behavior remains green and still runs before expensive download/display work.
- Focused unit/application/widget/integration gates and required broad group gates pass or have unrelated pre-existing failures documented with reruns.

`MD-003` must remain `Partial` if only content hash is implemented while a remote thumbnail surface remains unproven, if legacy hashless `done` media can still render, or if live/replay descriptors can be accepted without digest proof. It is blocked if the executor cannot safely add DB/wire metadata because of conflicting migrations or incompatible in-flight media model changes.

## source of truth

- Current code and tests win over stale prose.
- Source row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md` row `MD-003`.
- Breakdown row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` row `MD-003`.
- Existing closure docs for `MD-001` and `MD-002` are authoritative for MIME and size scope. Do not reopen them.
- `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` for named gate membership.
- For DB work, `lib/main.dart` migration ordering and version are authoritative over standalone migration filenames.

## session classification

`implementation-ready`

Reason: this planning pass resolved the evidence question. The repo does not already prove MD-003; concrete files show no first-class digest metadata and no digest verification before `done` or display. The next session should implement targeted code and tests, not collect more general evidence.

## exact problem statement

Group media integrity is not first-class. The app can send, persist, replay, download, and render group media based on blob id, MIME, size, and local path, with MD-001/MD-002 MIME and size guards. It does not bind a media descriptor to a content digest, does not verify downloaded bytes against a sender-provided digest, and has no thumbnail hash contract.

The user-visible risk is that a corrupted or tampered relay blob, replay descriptor, local file, or future thumbnail can be marked downloaded and displayed if it passes MIME/size/signature checks. MD-003 must make verified integrity a precondition for saving a downloaded path as `done` and for rendering media.

Behavior that must stay unchanged:

- Valid image, video, GIF, and voice group media still send, replay, download, notify, and display.
- MD-001 MIME rejection and MD-002 size rejection remain separate and continue to fail before hash work where possible.
- Hash failures do not introduce UI quarantine controls in this session; MD-012 owns that product UI.
- No new media encryption-key derivation or thumbnail privacy architecture is introduced.

## files and repos to inspect next

Production files:

- `pubspec.yaml`
- `lib/main.dart`
- `lib/core/database/migrations/010_media_attachments.dart`
- new migration file after current DB version, likely `lib/core/database/migrations/058_media_attachment_integrity_columns.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `go-mknoon/node/media.go`
- `go-mknoon/bridge/bridge.go`

Tests and fakes:

- new `test/core/media/group_media_integrity_policy_test.dart` or equivalent
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_test.dart`
- `test/core/database/helpers/media_attachments_db_helpers_test.dart` if added, otherwise nearest media DB helper tests
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/shared/fakes/in_memory_media_attachment_repository.dart`
- `test/shared/fakes/fake_media_file_manager.dart`

## existing tests covering this area

- `test/core/media/group_media_mime_policy_test.dart` proves allowed and blocked MIME descriptors and spoofed known signatures for MD-001.
- `test/core/media/group_media_size_policy_test.dart` proves size boundaries and malformed size handling for MD-002.
- `test/features/conversation/application/download_media_use_case_test.dart` proves invalid download file, relay MIME mismatch, oversized group descriptor rejection, and spoofed signature rejection. It does not compute or compare a digest.
- `test/features/groups/application/send_group_message_use_case_test.dart` proves media serialization and MD-001/MD-002 rejection before publish/inbox/store. It does not assert a hash in media JSON.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` proves allowed media persistence plus invalid MIME/size rejection before storage. It does not reject missing or mismatched hash metadata.
- `test/features/groups/application/group_message_listener_test.dart` proves invalid/oversized media suppresses notification and auto-download. It does not cover hash mismatch.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` proves encrypted replay media persistence and invalid/oversized replay rejection. It does not cover digest metadata in replay payloads.
- `test/shared/widgets/media/media_grid_cell_test.dart` proves legacy invalid MIME/size done media renders failed placeholder. It does not block hashless or hash-mismatched done media.
- `test/features/groups/integration/group_media_fanout_test.dart` proves valid image/video/voice fan-out, auto-download, and oversized fake-network rejection. It does not prove sender digest propagation or tampered recipient download rejection.
- `integration_test/foreground_group_push_drain_test.dart` proves representative media drain/download and oversized rejection. It does not cover content-hash verification.

Missing:

- No model/DB/wire tests for `contentHash` or `thumbnailHash`.
- No send test proves hash calculation before group publish/inbox payload creation.
- No live receive or encrypted replay test rejects missing/malformed/hash-mismatched media.
- No download test rejects downloaded bytes whose SHA-256 differs from descriptor metadata.
- No listener/foreground/fake-network test proves a tampered blob is not notified, saved as done, displayed, or left on disk.
- No widget/feed/conversation test prevents legacy hashless `done` group media from rendering.
- No thumbnail integrity test or absence proof for group remote thumbnails.

## regression/tests to add first

Add failing tests before production edits:

- New integrity policy/helper tests: SHA-256 file hashing, canonical lowercase hex validation, malformed digest rejection, missing required digest rejection for group media, digest match/mismatch, and optional thumbnail digest validation or explicit no-remote-thumbnail proof.
- `media_attachment_test.dart`: `contentHash` and `thumbnailHash` round-trip through constructor, `copyWith`, `toMap/fromMap`, and `toJson/fromJson`; legacy maps/json without hashes remain readable but are not considered verified group media.
- DB migration/helper tests: new columns are added idempotently, persisted attachments retain hash fields, and update-local-path does not erase integrity metadata.
- `upload_media_use_case_test.dart`: group upload computes content hash for the exact uploaded file bytes and returns it on `MediaAttachment`; 1:1 behavior stays unchanged unless explicitly covered.
- `send_group_message_use_case_test.dart`: media JSON sent to `group:publish` and encrypted inbox replay contains `contentHash`; missing/malformed hash attachments are rejected before message persistence, publish, inbox-store, or media save.
- `retry_incomplete_group_uploads_use_case_test.dart`: resumed upload recomputes or preserves content hash before resend; changed local bytes update the descriptor only if those exact bytes are reuploaded, otherwise fail closed.
- `handle_incoming_group_message_use_case_test.dart`: valid hash descriptors persist as pending; missing/malformed hash descriptors reject before message/media storage; duplicate enrichment cannot add hashless or mismatched media to an existing sparse row.
- `drain_group_offline_inbox_use_case_test.dart`: encrypted replay with missing/mismatched hash is skipped before message/media storage.
- `group_message_listener_test.dart`: live media with bad digest creates no notification and no `media:download`; a valid digest allows auto-download to proceed.
- `download_media_use_case_test.dart`: valid digest marks `done` and updates local path; tampered bytes mark failed/quarantined, delete output file, and do not call `updateLocalPath`; missing required digest fails before or immediately after download according to the chosen compatibility policy.
- `group_conversation_wired_test.dart`: startup/visible media recovery does not render or retry legacy hashless `done` group media as verified content.
- `media_grid_cell_test.dart` and feed/group conversation display tests: hashless or integrity-failed `done` attachments render a failed/unavailable placeholder and full-screen viewer cannot open them.
- `group_media_fanout_test.dart`: fake-network valid media carries hash to recipients and tampered download bytes do not become `done` or display.
- `foreground_group_push_drain_test.dart`: foreground push with bad hash creates no notification/download completion/display, while valid hash still drains.
- Add Go tests only if the bridge/node media response or protocol gains digest fields. If digest remains Dart descriptor metadata, Go media tests are not required for MD-003.

## step-by-step implementation plan

1. Add a narrow integrity helper under `lib/core/media/`, for example `group_media_integrity_policy.dart`, using existing `package:crypto`.
   - Compute SHA-256 over a file stream.
   - Normalize and validate lowercase hex digests.
   - Provide descriptor validation for required group `contentHash`.
   - Provide thumbnail validation hooks only for an existing thumbnail file/blob surface.
2. Add `contentHash` and `thumbnailHash` fields to `MediaAttachment`.
   - Include constructor, `fromMap`, `toMap`, `fromJson`, `toJson`, and `copyWith` support.
   - Keep legacy rows/json readable with null hashes.
   - Do not make non-group 1:1/post callers fail just because their descriptors have no group hash.
3. Add an idempotent DB migration after the current version to add `content_hash TEXT` and `thumbnail_hash TEXT` to `media_attachments`, wire it in `main.dart`, and update full migration tests.
4. Update repository/helper tests and fakes so hashes round-trip without being lost by save, update status, or update local path.
5. Compute content hash during group upload preparation.
   - For immediate upload, compute from the same local file that `uploadMedia` sends.
   - For durable pending upload, persist the hash with the pending row for the copied durable file.
   - If retry reuses a durable file, recompute before upload/resend and ensure the descriptor hash matches the bytes actually uploaded.
6. Update `sendGroupMessage` to require valid group media content hash before building `wireEnvelope`, `inboxPayload`, `replayEnvelope`, or calling publish/inbox.
   - Stop before message persistence for caller-supplied hashless or malformed attachments.
   - Include hash metadata in both live publish and encrypted inbox replay payloads.
7. Update `handleIncomingGroupMessage` and duplicate enrichment to validate hash metadata before group lookup, duplicate media enrichment, message save, or attachment save.
   - Reject missing or malformed `contentHash` for new group media descriptors.
   - Reject thumbnail hash only if a thumbnail descriptor/path/blob is present; otherwise record the explicit no-remote-thumbnail assumption in tests.
8. Update `drainGroupOfflineInbox` only if needed. It should stay thin if replay already routes through `handleIncomingGroupMessage`; add tests to prove that shared validation is used.
9. Update `downloadMedia(enforceGroupMediaPolicy: true)` to verify integrity before `updateLocalPath`.
   - Validate descriptor hash before download when missing/malformed.
   - After bridge download and MIME/size checks, compute the file digest and compare it to `attachment.contentHash`.
   - On mismatch, mark a non-displayable state. Prefer a data-level state such as `quarantined` or `integrity_failed` if tests and UI can distinguish it; otherwise use existing `failed` plus explicit flow reason. MD-012 owns richer quarantine UI.
   - Delete the downloaded file on mismatch or decrypt failure.
10. Harden display surfaces against legacy unverified rows.
    - Group conversation, feed group snapshots, `MediaGridCell`, and full-screen viewer paths must require `downloadStatus == done`, a local path, valid MIME/size, and valid/verified hash metadata for group media.
    - If a generic shared widget cannot know group context, pass an explicit verification flag/status through the attachment model rather than applying group-only policy to all 1:1/post media.
11. Address thumbnail closure carefully.
    - If group wire descriptors still have no remote thumbnail field, add tests proving `MediaGridCell` does not pass untrusted thumbnail paths and `VideoThumbnailCache` runs only from verified content.
    - If any group path can accept or display an explicit thumbnail path/blob, require `thumbnailHash` and verify it before display.
    - Do not add encrypted thumbnail transport or preview privacy work here.
12. Run focused tests first, then broad gates. Stop broadening if tests prove a supposed display path is not reachable for group media; record that as absence proof rather than adding product code.
13. After implementation and gates pass, the execution/closure agent may update the source matrix and test inventory. This planning session must not mark the row closed.

## risks and edge cases

- Legacy group media rows have no hashes. The implementation must decide whether they stay pending/failed/unavailable until redownloaded with a trusted descriptor or render as unavailable. They must not be silently treated as verified.
- Hashing the local plaintext file versus the relay blob bytes matters. In the current architecture upload sends the selected bytes directly, so the digest should describe the exact bytes written to/read from relay. If a future encrypted blob layer is used, hash the encrypted blob bytes and keep key derivation out of MD-003.
- Retry can reupload a changed local file from a stable blob id. The descriptor hash must match the bytes actually uploaded in that retry, or the resend must fail closed.
- Hash verification happens after download unless the descriptor is missing/malformed. The downloaded temp file must be deleted before any `done` state or display.
- Auto-download is fire-and-forget. Tests need deterministic fakes to prove bad hashes do not emit a displayed update after async completion.
- Shared media widgets serve 1:1, feed, posts, and groups. Avoid breaking non-group media by making group verification explicit in the attachment/status contract.
- Thumbnail support is ambiguous today. The executor must not claim thumbnail hash closure if a remote thumbnail display path exists without first-class metadata and tests.
- String `downloadStatus` has no enum. Adding `quarantined` or `integrity_failed` requires updating all status filters that currently only understand `pending`, `downloading`, `done`, `failed`, `upload_pending`, `upload_failed`, and `upload_cancelled`.
- The worktree is dirty with many unrelated session changes. The executor must work with current files and avoid reverting or overwriting unrelated edits.

## exact tests and gates to run

Focused Flutter tests:

```bash
flutter test --no-pub test/core/media/group_media_integrity_policy_test.dart
flutter test --no-pub test/features/conversation/domain/models/media_attachment_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
flutter test --no-pub test/features/conversation/application/upload_media_use_case_test.dart
flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart
flutter test --no-pub test/shared/widgets/media/media_grid_cell_test.dart
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart
```

Broad required gates:

```bash
flutter test --no-pub test/features/groups
flutter test --no-pub test/features/groups/integration
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Go gates only if Go bridge/node media protocol structs or responses change:

```bash
cd go-mknoon && go test ./bridge ./node -run 'Media|Group' -v
```

Recommended smoke/fake-network/3-party evidence:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly
```

`SMOKE-GAP-05` is a matrix bundle label, not a shell target. For MD-003, map it to the integrity-focused direct suites, fake-network `group_media_fanout_test.dart`, foreground push drain, broad `groups`, and `completeness-check`.

## known-failure interpretation

- Any new MD-003 test failure is blocking.
- Any failure in MD-001 MIME or MD-002 size tests after MD-003 changes is blocking unless a rerun proves it is unrelated infrastructure failure.
- If a broad group or integration suite fails, rerun the exact failing test. Treat it as pre-existing only if the failure is outside touched media integrity files and reproduces without the new test's assumptions.
- If the foreground integration command reports multiple devices, rerun with an explicit `-d` device, as MD-002 closure already recorded for this environment.
- If `group-real-network-nightly` cannot run because device or relay configuration is missing, record it as missing recommended external proof. It does not alone block repo-owned coverage because the source row marks 3-party E2E recommended.
- If thumbnail absence cannot be proven and no thumbnail hash is implemented, keep `MD-003` `Partial` even if content hash verification is complete.

## done criteria

- `MediaAttachment` and the DB persist content and thumbnail hash metadata without breaking legacy reads.
- New group sends include a valid content hash in live publish and encrypted inbox replay descriptors.
- Incoming live and replay media without valid required hash metadata is rejected before message/media storage.
- Downloads compute and compare content hash before `updateLocalPath` and before any `done` state.
- Hash mismatch/decrypt failure deletes downloaded bytes and leaves the attachment non-displayable.
- Group conversation, feed, media grid, and full-screen viewer cannot render unverified group media.
- Thumbnail closure is explicit: either no remote thumbnail display exists and generated thumbnails derive from verified content, or thumbnail hashes are verified before display.
- Existing valid image/video/GIF/voice group media fan-out still passes.
- Required focused tests and broad gates pass or have documented unrelated pre-existing failures.
- Source matrix/test-inventory closure updates are deferred to the execution/closure session after verification.

## scope guard

Do not implement:

- Media key derivation, per-object keys, or encryption context changes.
- Chunked transfer resume, per-chunk hashing, or partial chunk reuse.
- Full quarantine UI, retry controls, warning banners, moderation, or reporting UX.
- Remote thumbnail generation/encryption/privacy features.
- Generic file attachment support.
- Relay-wide media protocol redesign unless a direct digest field is needed and all non-group contracts are preserved.
- New simulator/device matrix ownership beyond running available recommended evidence.

Overengineering includes configurable hash algorithms, multi-hash negotiation, admin policy UI, content-addressed dedupe, cross-group cache migration, or replacing the current media repository.

## accepted differences / intentionally out of scope

- `contentHash` can describe the exact current relay blob bytes. If the current app still uploads plaintext media bytes, this session may close integrity but must not claim new media privacy or key separation.
- The media `id` remains a relay blob id/UUID, not a content-addressed id. MD-006 owns deduplication by content hash or content id.
- Missing legacy hashes can make old media unavailable rather than silently trusted. That is acceptable for P0 integrity, but any user-facing recovery UI belongs to MD-012.
- Local video thumbnails generated after verified content do not require a separate remote `thumbnailHash` unless a remote thumbnail descriptor exists.
- 1:1 and post media may keep their existing behavior unless a shared model field is added in a backward-compatible way.

## dependency impact

- `MD-004` can later use the digest fields while adding key/context separation, but must not be folded into MD-003.
- `MD-005` chunk resume should build on this content-hash contract and add per-chunk proof separately.
- `MD-006` can use content hashes for dedupe only after MD-003 proves integrity; this session should not add dedupe behavior.
- `MD-007` thumbnail privacy must revisit `thumbnailHash` if remote encrypted thumbnails become product scope.
- `MD-012` quarantine UI depends on a stable data-level integrity-failure state from MD-003.
- `AB-006` suspicious auto-download can rely on MD-003's no-auto-download/no-display behavior for bad hashes.
- `SMOKE-GAP-05` remains incomplete until MD-003, MD-011, and MD-012 have their own evidence.

## Reviewer Pass

Sufficiency: sufficient for execution with one explicit closure caveat. The plan names the concrete missing metadata, the code paths that trust downloaded media today, and the tests needed to prove send, receive, replay, download, display, fake-network, and foreground behavior.

Missing files/tests/gates: none structurally. The executor should add a specific media DB helper test if no existing helper test is appropriate, and should run Go gates only if Go protocol structs or responses change.

Stale assumptions: none found. Current code and tests show MD-001 and MD-002 landed, but they intentionally do not cover digest verification.

Overengineering check: the plan avoids MD-004 key derivation, MD-005 chunks, MD-007 thumbnail privacy, MD-012 UI, MD-014 device matrix, and relay-wide redesign.

Minimum needed: model/DB/wire content hash metadata, hash computation on send/upload, validation on receive/replay/download/display, explicit thumbnail absence proof or thumbnail hash verification, and focused tests.

## Arbiter Pass

Structural blockers remaining: none for implementation planning. There is a closure blocker for marking `MD-003` `Covered` today: no first-class hash metadata and no digest verification before display.

Incremental details intentionally deferred: exact field names beyond `contentHash`/`thumbnailHash`, exact terminal status name for hash failure, exact flow-event names, and whether an extra media DB helper test file is needed.

Accepted differences intentionally left unchanged: legacy media may become unavailable instead of trusted, current relay blob ids remain UUIDs, local generated thumbnails can be covered by absence/derivation proof, and 1:1/post media behavior remains outside the group integrity contract.
