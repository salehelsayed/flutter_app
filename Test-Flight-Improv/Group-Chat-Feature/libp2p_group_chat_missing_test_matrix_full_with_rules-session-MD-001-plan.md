# MD-001 Session Plan -- Media MIME Allowlist And Dangerous Type Rejection

## Final Verdict

- Session id: `MD-001`
- Source row id: `MD-001`
- Source row: `Media MIME allowlist and dangerous type rejection`
- Current source status: `Open`
- Breakdown disposition: `needs_code_and_tests`
- Session classification: `implementation-ready`
- Expected closure target: `Covered` only if both declared-MIME rejection and spoofed-content rejection are proven in repo-owned tests. If only declared metadata is proven, leave `MD-001` `Partial`.

## Real Scope

In scope for the execution session:

- Add one canonical group media MIME policy that uses exact allowed MIME values and rejects malformed, empty, wildcard, executable, scriptable, archive, generic binary, unsupported file, and mismatched `mediaType` descriptors.
- Apply that policy to group media before upload, before retry upload, before group publish/inbox-store payload creation, before incoming live or replayed media is persisted, before notification preview uses media metadata, before auto-download starts, and before a downloaded file is marked `done` or rendered.
- Add small content-sniffing proof for spoofed media where repo-owned tests can create deterministic local files. This can be implemented with a direct dependency on `package:mime` or a small header-byte helper, but the policy must stay exact and testable.
- Add focused unit and integration tests that fail before implementation and prove allowed media still works while dangerous or spoofed media is blocked.
- Inspect Go media and relay paths and add Go tests only if group-specific MIME validation is actually implemented there.

Out of scope:

- Enabling generic file attachments for groups. `MD-013` owns that product scope.
- Broad media integrity, encrypted content hash validation, chunk verification, thumbnail privacy, quarantine UI, size limits, removed-member media access, or media-key derivation.
- Changing relay opacity for encrypted blobs unless there is a group-specific validation boundary that does not break existing 1:1/post/profile contracts.
- Rewriting media storage, upload chunking, video playback, or media cache eviction.
- Changing source matrix, inventory, or breakdown during this planning-only session.

## Closure Bar

`MD-001` is good enough for `Covered` when all of the following are true:

- Allowed group media types still send, persist, replay, download, notify, and render through existing image/video/voice paths.
- Disallowed declared MIME values such as `application/octet-stream`, `application/x-msdownload`, `application/pdf`, `text/html`, `image/svg+xml`, malformed strings, missing MIME, wildcard strings, and unsupported video/audio variants fail before group upload, group publish, group inbox-store, local media attachment persistence, notification preview, auto-download, or display.
- Spoofed media is proven in repo-owned tests by using real local bytes whose content signature does not match the declared allowed MIME. Those files must not be uploaded or marked `done`; downloaded spoofed files must be deleted or left failed before UI display.
- Direct tests prove send, retry, live receive, offline replay, foreground-drain, download, and display boundaries.
- The exact row bundle label `SMOKE-GAP-05` is recorded as satisfied by the focused direct suites plus the recommended smoke/fake-network evidence. `SMOKE-GAP-05` is not a runnable `scripts/run_test_gates.sh` target in the inspected repo.

`MD-001` must remain `Partial` if the implementation rejects dangerous declared MIME values but cannot prove spoofed bytes before storage/display. It must remain blocked if the policy cannot be applied before local storage on incoming live/replay paths.

## Source Of Truth

- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- Session breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- Current inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md`
- Gate script: `scripts/run_test_gates.sh`; if it disagrees with gate definitions, the script wins.
- Current code and tests win over stale prose. Current source row status is `Open` and the breakdown classifies this row as `implementation-ready`.

## Session Classification

`implementation-ready`

Reason: the repo has clear send, retry, receive/replay, persistence, UI, and relay code paths to enforce and test. No prerequisite product capability is needed to reject dangerous MIME values for currently supported group image/video/voice media. Full closure is acceptance-gated on proving spoofed bytes, but that is a testable implementation detail rather than a planning blocker.

## Exact Problem Statement

Current group media flows mostly propagate MIME strings as trusted metadata. The app infers `mediaType` from broad MIME prefixes, persists remote media descriptors directly, downloads media based on persisted MIME, and renders done image/video attachments from local files. The Go media relay stores and returns MIME as metadata without allowlist enforcement.

The user-visible risk is that a group message can carry dangerous or spoofed media metadata that is accepted into local state, triggers a download, influences notification preview, or reaches a display widget. `MD-001` must make group media fail closed before display or storage while preserving the currently supported image, video, GIF, and voice-note journeys.

Behavior that must stay unchanged:

- Existing group image, video, GIF, and voice-note fan-out continues to work.
- Existing retry and foreground-drain flows keep descriptor preservation and no-duplicate behavior.
- Relay authorization behavior through `allowedPeers` remains unchanged.
- Generic file support is not enabled for groups.

## Evidence Collected

- `MediaAttachment.mediaTypeFromMime` currently accepts any `image/*`, `video/*`, or `audio/*` prefix and returns `file` for everything else. `MediaAttachment.fromJson` defaults missing MIME to `application/octet-stream`.
- `GroupConversationWired._mimeFromPath` maps extensions to MIME values and falls back to `application/octet-stream`; it currently maps some types that do not have corresponding stable storage extensions in `MediaFileManager`.
- `uploadMedia` passes the caller-supplied MIME to `callP2PMediaUpload`, copies the file to persistent storage using that MIME, and returns a `MediaAttachment` without validation.
- `sendGroupMessage` serializes `mediaAttachments.map((a) => a.toJson())` into both the live publish payload and encrypted offline replay payload, then persists outgoing attachments after publish/inbox outcomes. It does not validate media MIME or `mediaType`.
- `retryIncompleteGroupUploads` reads upload-pending attachment MIME from the DB and calls `uploadMediaFn` with it. It preserves GIF MIME, but does not reject invalid pending MIME before upload.
- `handleIncomingGroupMessage` and duplicate enrichment call `MediaAttachment.fromJson(...).copyWith(messageId: ...)` and save attachments directly. This covers both live listener and replay paths.
- `drainGroupOfflineInbox` forwards replayed `media` lists into either `GroupMessageListener.handleReplayEnvelope` or `handleIncomingGroupMessage`, so the same receive validation must cover offline inbox replay.
- `GroupMessageListener` builds notification preview attachments from raw incoming media metadata and auto-downloads persisted attachments after handling. Notification preview must not use unsanitized media metadata.
- `downloadMedia` chooses a destination path from persisted attachment MIME, ignores any mismatch between the descriptor MIME and relay-returned MIME, and marks the attachment `done` after size checks only.
- `MediaGridCell` and `MediaThumbnailImage` display `done` image/video attachments from `localPath`; legacy invalid rows could still render unless display code checks allowed group media or invalid rows are never marked done.
- `go-mknoon/node.MediaUpload`, `go-mknoon/bridge.MediaUpload`, and `go-relay-server.handleMediaUpload` carry MIME through as metadata. The relay currently accepts `application/pdf` and `application/octet-stream` in tests, including an opacity test for encrypted random bytes.
- Existing coverage proves only allowed happy-path descriptors: `group_media_fanout_test.dart` covers `image/jpeg`, `video/mp4`, and `audio/mp4`; `retry_incomplete_group_uploads_use_case_test.dart` preserves `image/gif`; `foreground_group_push_drain_test.dart` drains `image/jpeg`. No inspected test proves dangerous or spoofed MIME rejection.

## Files And Repos To Inspect Next

Production files:

- `lib/core/media/media_file_manager.dart`
- `lib/core/constants/media_constants.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`

Go and relay files:

- `go-mknoon/node/media.go`
- `go-mknoon/bridge/bridge.go`
- `go-relay-server/media.go`

Tests and fakes:

- `test/core/media/*_test.dart`
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/shared/fakes/in_memory_media_attachment_repository.dart`
- `test/shared/fakes/fake_media_file_manager.dart`
- `go-mknoon/node/media_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-relay-server/media_test.go`

## Existing Tests Covering This Area

- `test/features/groups/integration/group_media_fanout_test.dart` proves existing members receive image, video, and voice descriptors and one receiver downloads media.
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` proves interrupted group media retry preserves `image/gif`, reuses blob IDs, and preserves done siblings.
- `integration_test/foreground_group_push_drain_test.dart` proves a foreground push drains an image descriptor exactly once, stores it, downloads it, and produces one notification.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` proves media descriptors from offline replay are saved, including mixed media and `file` descriptors.
- `test/features/conversation/domain/models/media_attachment_test.dart` proves broad prefix-based inference, default `application/octet-stream`, and current `file` mapping for unknown MIME.
- `go-relay-server/media_test.go` proves relay media happy path, size limit, authorization, group `AllowedPeers`, and existing generic/opaque MIME acceptance.

Missing:

- No test rejects dangerous declared MIME on group send.
- No test rejects dangerous declared MIME on group retry.
- No test rejects dangerous declared MIME on live receive or offline replay before local DB attachment persistence.
- No test rejects raw incoming media metadata before notification preview or auto-download.
- No test rejects relay-returned MIME mismatch or byte-level spoofing before marking downloaded media done.
- No widget test prevents legacy invalid done attachments from rendering through `Image.file`.

## Regression / Tests To Add First

Add tests before implementation in this order:

1. Unit policy tests in a new focused file such as `test/core/media/group_media_mime_policy_test.dart`:
   - allows exact current group media MIME values needed by existing product paths: `image/jpeg`, `image/png`, `image/gif`, `image/webp`, `image/heic`, `video/mp4`, `video/quicktime`, `audio/mp4`, `audio/aac`, `audio/mpeg`, and `audio/ogg` if kept by storage/display support;
   - rejects empty, missing, malformed, wildcard, uppercase-with-spaces unless normalized, `application/octet-stream`, `application/pdf`, `text/html`, `image/svg+xml`, archive types, and executable types;
   - rejects `mediaType` mismatches such as `mime: image/jpeg, mediaType: video`;
   - proves spoofed file bytes are rejected for at least one image case and one script/binary case.
2. `send_group_message_use_case_test.dart`: direct-call invalid `MediaAttachment` fails before message persistence, `group:publish`, `group:inboxStore`, and media attachment save.
3. `group_conversation_wired_test.dart` or the smallest adjacent composer test: local selected file with spoofed bytes is rejected before `uploadMediaFn` and before durable pending-upload row creation.
4. `retry_incomplete_group_uploads_use_case_test.dart`: an upload-pending attachment with dangerous MIME is terminalized or marked failed without calling `uploadMediaFn`, publish, or inbox-store.
5. `handle_incoming_group_message_use_case_test.dart`: invalid live media descriptor rejects the whole incoming media message before message or attachment storage.
6. `drain_group_offline_inbox_use_case_test.dart`: invalid replay media descriptor from encrypted inbox replay does not persist message/media and emits a skip/reject event.
7. `group_message_listener_test.dart`: invalid media does not create notification preview media and does not trigger auto-download.
8. `download_media_use_case_test.dart`: relay-returned MIME mismatch or spoofed downloaded bytes keeps status `failed`, deletes the local file, and never marks the attachment `done`.
9. `media_grid_cell_test.dart` or `media_thumbnail_image_test.dart`: a legacy invalid done media row renders a failed placeholder rather than an image/video thumbnail.
10. Extend `group_media_fanout_test.dart` with one fake-network bad descriptor case only if unit/application tests do not already exercise the receive path through the same listener. Do not add 3-party E2E for this row.

## Step-By-Step Implementation Plan

1. Create a narrow reusable media policy helper, preferably under `lib/core/media/` or `lib/features/conversation/domain/models/`, with no UI dependencies:
   - normalize MIME strings to trimmed lowercase;
   - define exact allowed group media MIME values;
   - map allowed MIME to canonical `mediaType`;
   - validate descriptor shape and reject any `mediaType` that disagrees with MIME;
   - expose a file/header validation function for spoofed local/downloaded files.
2. Replace broad group media inference at group boundaries with the policy:
   - keep `MediaAttachment.mediaTypeFromMime` backward compatible for non-group model behavior if needed;
   - add a group-specific constructor/sanitizer rather than silently changing all non-group callers unless tests show shared behavior should change.
3. Enforce pre-upload validation in `GroupConversationWired` before durable copy or `uploadMediaFn`:
   - block invalid local files before pending-upload rows are created;
   - show the existing send failure/snackbar style used by nearby media upload errors;
   - keep allowed image/video/GIF/voice flows unchanged.
4. Enforce use-case validation in `sendGroupMessage` before the optimistic message row is saved:
   - if any attachment is invalid, return `SendGroupMessageResult.error`;
   - do not call `group:publish` or `group:inboxStore`;
   - do not save media attachments.
5. Enforce retry validation in `retryIncompleteGroupUploads` before resolving local path or calling `uploadMediaFn`:
   - invalid pending rows should become `upload_failed` or an explicit failed state using the existing retry/failure vocabulary;
   - emit a clear flow event such as `RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INVALID_MIME`.
6. Enforce receive/replay validation in `handleIncomingGroupMessage` and duplicate enrichment:
   - validate every raw media descriptor before saving the `GroupMessage`;
   - reject the whole media-bearing message if any descriptor is invalid, so the user does not see a misleading text-only row for a blocked attachment;
   - keep duplicate no-op behavior for existing valid attachments.
7. Update `GroupMessageListener` to use sanitized/saved attachments for notification body and auto-download decisions:
   - do not build notification preview from raw invalid media metadata;
   - do not start auto-download when no valid persisted media exists.
8. Harden `downloadMedia`:
   - reject disallowed or mismatched relay-returned MIME;
   - validate downloaded bytes against the expected allowed MIME before `updateLocalPath`;
   - on failure, mark `failed` and delete the partial file.
9. Add a defensive display guard for legacy invalid done rows in shared media widgets, or a group-specific guard where group media is loaded, so invalid old rows cannot be rendered.
10. Inspect Go media/relay paths after Dart validation is in place:
   - if no Go validation is needed, leave relay opacity unchanged and document why;
   - if group-specific Go validation is added, preserve existing non-group opacity tests or split group media policy from generic media relay behavior.
11. Run focused tests first, then group gate and completeness check.
12. Update the source matrix, inventory, and breakdown ledger only in the later execution/closure session after test evidence exists.

Stop early if a focused test proves the repo already rejects dangerous and spoofed group media at all required boundaries. In that case, do evidence-only closure instead of adding code.

## Risks And Edge Cases

- `MediaAttachment.mediaTypeFromMime` is shared. Tightening it globally can break 1:1, posts, profile, or legacy media tests. Prefer group-specific validation unless shared tests justify a broader change.
- The relay intentionally stores opaque encrypted bytes and currently accepts `application/octet-stream` in Go tests. A relay-level allowlist can break encryption opacity and non-group media unless scoped carefully.
- File-extension MIME and content-sniffed MIME can disagree. For `MD-001`, disagreement must fail closed for group media instead of trusting the extension.
- Some existing extension maps include types not consistently supported by storage/display. If the executor keeps them allowed, it must update storage/display mapping and tests; otherwise, block them explicitly.
- Remote live/replay descriptors are untrusted. Validating only sender UI is insufficient.
- Notification preview currently uses raw media metadata. That can produce "Photo" for blocked media unless fixed.
- Download validation must happen before `updateLocalPath` marks the row `done`.
- A dirty worktree contains many unrelated group changes from other agents. Do not revert them while implementing this row.

## Exact Tests And Gates To Run

Regression-first direct suites:

```sh
flutter test --no-pub \
  test/core/media/group_media_mime_policy_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
```

Focused group media integration:

```sh
flutter test --no-pub \
  test/features/groups/integration/group_media_fanout_test.dart
```

Required broad group gates from the breakdown:

```sh
flutter test --no-pub test/features/groups
flutter test --no-pub test/features/groups/integration
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Recommended `SMOKE-GAP-05` smoke/fake-network evidence:

```sh
flutter test -d <device-id> integration_test/foreground_group_push_drain_test.dart
dart run integration_test/scripts/run_foreground_group_push_simulator_smoke.dart -d <alice-device>,<bob-device>
```

If Go media, bridge, or relay code is changed:

```sh
(cd go-mknoon && go test ./node/ ./bridge/ -run 'Media|Group' -v)
(cd go-relay-server && go test ./... -run 'Media|Group' -v)
```

Hygiene:

```sh
git diff --check
```

Do not treat `SMOKE-GAP-05` as a shell command; it is a source-matrix smoke bundle label covering `MD-001`, `MD-002`, `MD-003`, `MD-011`, and `MD-012`.

## Known-Failure Interpretation

- A failure in the direct policy, send, retry, receive, drain, listener, download, or display tests added for `MD-001` is in scope.
- A failure in `group_media_fanout_test.dart` or `foreground_group_push_drain_test.dart` is in scope if it involves allowed media being rejected, descriptor loss, missing download, duplicate rows, or notification preview behavior.
- A failure in broad `test/features/groups` outside media/MIME paths must be triaged against the current dirty worktree before being attributed to `MD-001`.
- Existing `test-gate-definitions.md` notes posts phase integration startup failures on macOS; those are unrelated unless this session touches posts media or gate definitions.
- If Go relay tests fail because `application/octet-stream` or `application/pdf` is newly rejected, that likely means the implementation broadened group MIME policy into generic relay behavior and must be revisited.
- Passing declared-MIME allowlist tests without spoofed-byte tests is not enough for `Covered`; record `Partial`.

## Done Criteria

- A canonical group media MIME policy exists and is covered by unit tests.
- Invalid or dangerous media is blocked before group upload, retry upload, publish/inbox-store, incoming live storage, offline replay storage, notification preview, auto-download, and display.
- Spoofed local/downloaded bytes are rejected before upload or before download completion is marked `done`.
- Existing allowed image/video/GIF/voice group tests still pass.
- `SMOKE-GAP-05` evidence is mapped to actual direct and smoke commands.
- Required direct tests, broad group tests, Group Messaging Gate, completeness check, and `git diff --check` pass, or failures are captured with exact known-failure classification.
- Matrix/inventory/breakdown updates are deferred to the execution/closure session and must preserve `Partial` if spoofed bytes are not fully proven.

## Scope Guard

Do not:

- Add generic group file attachment support.
- Add media size-limit, hash/integrity, quarantine UI, chunking, cache eviction, removed-member access, or media-key work.
- Reject opaque encrypted relay blobs globally unless all non-group media contracts are updated intentionally.
- Use broad prefix checks such as `startsWith('image/')` as the final group policy.
- Accept `mediaType` supplied by a remote peer when it disagrees with the canonical MIME mapping.
- Persist a media-bearing incoming message after one attachment is rejected unless product explicitly chooses a visible blocked-attachment placeholder in a separate row.
- Reclassify `MD-001` as `Covered` without spoofed-content proof.
- Revert or overwrite unrelated dirty-worktree edits.

## Accepted Differences / Intentionally Out Of Scope

- The Go relay's generic media protocol can remain MIME-agnostic if Dart group boundaries enforce `MD-001`. That preserves existing encrypted-blob opacity and non-group contracts.
- Generic files remain unsupported for groups even though the shared media model and relay can represent `file` metadata.
- Full content integrity and hash validation belongs to `MD-003`, not this row.
- Unsafe-media quarantine and retry UI belongs to `MD-012`; this row may use existing failed placeholders but should not build a quarantine product.
- Full simulator media/recovery matrix belongs to `MD-014`; `MD-001` needs smoke/fake-network confidence, not 3-party E2E.

## Dependency Impact

- `MD-002` should reuse the same policy boundary when adding size checks, but must not be bundled into this session.
- `MD-003` can build on the download-before-display checkpoint for hash validation later.
- `MD-012` can build on the failed/blocked state emitted here for quarantine UI later.
- Existing group media onboarding/fan-out rows depend on allowed image/video/voice behavior staying stable.
- If the policy helper becomes shared beyond groups, 1:1 media, posts, profile media, and relay tests must be included in the execution gate list.

## Structural Blockers Remaining

- None for the implementation plan.
- Acceptance blocker for `Covered`: spoofed content must be proven with repo-owned tests. Without that proof, leave `MD-001` `Partial`.

## Incremental Details Intentionally Deferred

- The executor may choose `package:mime` with a direct `pubspec.yaml` dependency or a small local header-sniff helper. The acceptance bar is behavior and tests, not the exact implementation mechanism.
- Exact user-facing error text can reuse nearby media upload failure copy; do not create new UI scope unless existing widgets need a short failure state.
- Final matrix/inventory/breakdown wording should be written only after execution captures test output.

## Exact Docs / Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/core/constants/media_constants.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `go-mknoon/node/media.go`
- `go-mknoon/bridge/bridge.go`
- `go-relay-server/media.go`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `go-mknoon/node/media_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-relay-server/media_test.go`

## Why The Plan Is Safe To Implement Now

The plan is safe to execute because the row is narrow, the current code has explicit group media entry points, and the required tests can be added before implementation. The main guard is to keep validation at group-owned boundaries unless the executor intentionally expands the shared media contract and then runs the broader shared test set. The plan is unsafe only for a `Covered` claim if spoofed-content rejection cannot be proven before storage/display in repo-owned tests.
