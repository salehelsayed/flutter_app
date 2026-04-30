# MD-002 Implementation Plan

Session id: `MD-002`  
Source row id: `MD-002`  
Source doc: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`  
Breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

Final verdict: `implementation-ready`, with one non-negotiable closure condition. MD-002 can be marked `Covered` only when repo-owned tests prove oversized group media is rejected on send, retry, live receive, offline inbox replay, notification/auto-download, and download/display boundaries before publish, storage, or `media:download`. If receive-side oversized remote or inbox payload rejection before message/attachment storage and download cannot be proven, MD-002 must remain `Partial` or blocked.

## Evidence Collector

- Source row `MD-002` is P0/Open and requires unit plus integration coverage for "Per-media and total-message size limits apply on send and receive"; expected behavior is safe rejection with no downloads, crashes, or misleading sent states.
- `MD-001` is already closed by `lib/core/media/group_media_mime_policy.dart`; MD-002 should compose with that MIME policy but must not reopen MIME allowlist, spoofing, hash/integrity, quarantine UI, generic file support, or simulator matrix scope.
- Group composer has a configurable total pending-media budget: `GroupConversationWired.maxAttachmentBudgetBytes` defaults to `kGeneralMediaAttachmentBudgetBytes`, currently 5 GB. `_resolvePendingMediaCandidates` checks combined pending media bytes and offers compression; tests already cover oversized picker compression and rejection. This is UI-only and not a receive/send-use-case contract.
- GIF picker input has a separate `kMaxGifFileSize` guard, currently 25 MB. It is not a general group media size policy and does not cover uploaded, retried, remote, or replayed descriptors.
- `sendGroupMessage` sanitizes group media MIME descriptors only, then serializes `MediaAttachment.toJson()` into publish and inbox payloads. It does not validate `size`, per-media bytes, or total media bytes before pre-persisting a `sending` row, publishing, or storing relay inbox payloads.
- `uploadMedia` validates group MIME/signature and records `File.length()`, but it does not reject oversized group uploads before calling `media:upload`.
- Durable group upload prep stores `upload_pending` rows with size `0`; retry currently validates MIME only and can call `uploadMediaFn` for pending rows without a size check.
- `handleIncomingGroupMessage` validates incoming media MIME descriptors before storage, but does not validate descriptor `size`. It saves the message first, then saves media attachments as pending downloads. Duplicate replay can enrich an existing message with missing media attachments.
- `GroupMessageListener` forwards `media` into `handleIncomingGroupMessage`, then builds notification preview text and auto-downloads pending attachments after persistence. Existing invalid MIME tests prove the listener can suppress notification and download when the handler rejects, but there is no size equivalent.
- `drainGroupOfflineInbox` routes replayed media through `GroupMessageListener.handleReplayEnvelope` or directly through `handleIncomingGroupMessage`, so one shared receive-side size validator can cover live and replay paths if tested directly.
- `downloadMedia(enforceGroupMediaPolicy: true)` validates descriptors and downloaded MIME/signature. It does not reject oversized declared sizes before calling `media:download`; the Go node currently learns relay response size before copying bytes but has no caller-supplied max size to abort before file write.
- Display guard `MediaGridCell` rejects legacy invalid MIME descriptors before thumbnail render, but it has no size guard for legacy oversized `done` attachments.
- Go client framing limits inbox frames to 128 KB (`MaxFrameLen`), while the relay media server enforces a 5 GB media upload max and 5 GB pending bytes per recipient. Relay tests already cover upload size rejection and boundary acceptance. These are useful lower-level boundaries, but they do not prove Flutter group send/receive rejects oversized descriptors before publish/storage/download.

## real scope

Implement a group media size policy and apply it only to group media send, upload, retry, receive, listener auto-download, group media download, and legacy display guards.

The session owns:

- Per-media size validation for group media descriptors and local files.
- Total media bytes per group message validation across all attachments.
- Rejection before group publish, relay inbox store, bridge upload, message/attachment storage on receive, notification preview, auto-download, and done-media display.
- Tests that prove boundary values are accepted and over-boundary values are rejected on both send and receive paths.
- Go/bridge download guard only if needed to prevent a relay-declared oversized blob from being written before Dart can reject it.

The session does not own:

- MIME allowlist changes beyond composing size validation after `GroupMediaMimePolicy`.
- Hash/integrity verification (`MD-003`), quarantine/retry UI (`MD-012`), generic file support (`MD-013`), simulator matrix expansion (`MD-014`), peer scoring/abuse policy (`AB-004`/`AB-006`), or general text/payload length policy (`MS-013`).

## closure bar

MD-002 is good enough when:

- A single group media attachment at the configured per-media limit is accepted, and one byte over is rejected.
- A group message with total declared media bytes at the configured total limit is accepted, and one byte over is rejected.
- Rejections happen before expensive or externally visible work: no `media:upload`, no `group:publish`, no `group:inboxStore`, no message row, no media row, no notification preview, no `media:download`, no local file display for oversized group media.
- Retry treats oversized pending upload rows as terminal invalid media for this message, not a transient retry loop.
- Live receive and offline replay both reject oversized remote descriptors before storage/download.
- Existing allowed image, video, GIF, and voice group fan-out remains green.

MD-002 must remain `Partial` or blocked if any receive-side live/replay oversized payload can create a message row, create a media attachment row, show a notification preview, call `media:download`, mark a download `done`, or render a thumbnail.

## source of truth

- Current code and tests win over stale prose.
- Source row: `libp2p_group_chat_missing_test_matrix_full_with_rules.md` row `MD-002`.
- Breakdown row: `libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` row `MD-002`.
- `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` for named gate membership.
- Existing `MD-001` closure text is authoritative for MIME policy scope and must not be reworked.
- Relay server `go-relay-server/media.go` currently defines the hard media upload ceiling; Flutter defaults should not claim a higher group media limit than the relay accepts.

## session classification

`implementation-ready`.

Evidence shows a real code gap: current group media size handling is mostly UI budget and relay upload limit, not a shared send/receive application contract. The planned work is code plus direct tests.

## exact problem statement

Group media size limits are not consistently enforced across group send and receive paths. A caller can bypass the composer and call `sendGroupMessage` with oversized `MediaAttachment.size`; remote live or inbox replay payloads can carry oversized media descriptors that pass MIME validation, get persisted as pending downloads, enter notification preview, and trigger auto-download. Retry can attempt pending oversized uploads. Download/display can trust oversized descriptors unless MIME validation fails.

User-visible behavior must improve so oversized group media is rejected safely, never appears as sent, never creates persisted incoming media, never triggers download, and never renders as valid media. Valid in-limit image, video, GIF, and voice behavior must stay unchanged.

## files and repos to inspect next

Production files:

- `lib/core/media/group_media_mime_policy.dart`
- `lib/core/media/pending_composer_media.dart`
- `lib/core/constants/media_constants.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/media.go`
- `go-mknoon/node/config.go`
- `go-relay-server/media.go`
- `go-relay-server/inbox.go`

Tests:

- `test/core/media/group_media_mime_policy_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/media_test.go`
- `go-relay-server/media_test.go`

## existing tests covering this area

- `group_conversation_wired_test.dart` covers pending composer budget overflow, compression-under-budget, and post-compression rejection for gallery attachments.
- `send_group_message_use_case_test.dart` covers media serialization and MIME-based rejection before persistence/publish/inbox, but not size rejection.
- `retry_incomplete_group_uploads_use_case_test.dart` covers MIME terminalization and retry preservation, but not oversized terminalization.
- `handle_incoming_group_message_use_case_test.dart` covers allowed media persistence and invalid MIME/mediaType rejection before storage, but not oversized size rejection.
- `group_message_listener_test.dart` covers invalid MIME suppression before notification and auto-download, but not oversized suppression.
- `drain_group_offline_inbox_use_case_test.dart` covers encrypted replay media persistence and dangerous MIME rejection before message/attachment storage, but not oversized replay.
- `download_media_use_case_test.dart` covers invalid file, relay MIME mismatch, and spoofed bytes after download, but not declared-size rejection before download.
- `group_media_fanout_test.dart` covers allowed image/video/voice fan-out and auto-download via fake network, but not boundary/oversized fan-out.
- `foreground_group_push_drain_test.dart` covers foreground push media drain, notification, and one download trigger for valid media, but not oversized rejection.
- `go-relay-server/media_test.go` already covers relay upload size limit and exact-max acceptance.

## regression/tests to add first

Add or extend tests before implementation:

- New `test/core/media/group_media_size_policy_test.dart`: exact boundary accept, per-media over-boundary reject, total over-boundary reject, missing/zero/negative/non-numeric size reject, total-sum overflow safety, GIF per-format cap preserved, and MIME policy composition stays separate.
- `send_group_message_use_case_test.dart`: oversized single attachment and oversized total list return `SendGroupMessageResult.error` with `message == null`, no message/media rows, no `group:publish`, and no `group:inboxStore`; exact-boundary media still publishes and inbox-stores.
- `upload_media_use_case_test.dart`: group upload with oversized local file returns null before `media:upload`; in-limit group upload still calls bridge; 1:1 upload behavior stays unchanged unless explicitly given a group policy.
- `group_conversation_wired_test.dart`: durable prep saves real pending size instead of `0`; oversized voice/gallery send does not leave a sent row and does not call upload/publish.
- `retry_incomplete_group_uploads_use_case_test.dart`: oversized pending upload is marked `upload_failed`, `uploadMediaFn` is not called, and no group publish/inbox occurs; total over limit across done plus pending attachments aborts final resend.
- `handle_incoming_group_message_use_case_test.dart`: oversized live descriptor and total-over-limit descriptor return null before message/media storage; duplicate replay with oversized media does not enrich an existing sparse message.
- `drain_group_offline_inbox_use_case_test.dart`: encrypted replay with oversized media is skipped before message/attachment storage.
- `group_message_listener_test.dart`: oversized live media descriptor is rejected before notification preview and before `media:download`.
- `download_media_use_case_test.dart`: group enforced download rejects oversized declared attachment before bridge command and marks failed; if bridge max-bytes is implemented, relay-returned oversized metadata is rejected before local file creation.
- `media_grid_cell_test.dart`: legacy oversized `done` group media renders failed placeholder and does not build `MediaThumbnailImage`.
- `group_media_fanout_test.dart`: valid boundary descriptor still fans out; oversized descriptor from a fake-network sender is not stored or downloaded by recipients.
- `foreground_group_push_drain_test.dart`: oversized foreground group push/replay creates no message/media rows, shows no notification, and calls no `media:download`.
- Go tests only if bridge/node download max is changed: `go-mknoon/node/media_test.go` or `go-mknoon/bridge/bridge_test.go` proves oversized relay metadata aborts before bytes are copied; keep existing `go-relay-server/media_test.go` size-limit tests green.

## step-by-step implementation plan

1. Add a small group media size policy in `lib/core/media`, separate from MIME policy but used immediately after MIME validation. Defaults should not exceed the relay media server's current 5 GB max. Preserve the existing GIF cap as a per-format cap. Provide test-only limit injection through pure validation methods rather than changing production defaults.
2. Update composer and durable-upload prep to use the policy for selected media, initial pending media, gallery/video media, and voice recordings. Store real `budgetBytes`/recording bytes in durable `upload_pending` rows so retry can validate without trusting `0`.
3. Update `uploadMedia` for group uploads (`allowedPeers != null`) to validate local file length before `callP2PMediaUpload`. Oversized returns null with a specific flow event before bridge upload.
4. Update `sendGroupMessage` to validate `mediaAttachments` per-item and total bytes before building `wireEnvelope`, `inboxPayload`, `replayEnvelope`, pre-persisting the message, calling `group:publish`, or calling `group:inboxStore`.
5. Update `retryIncompleteGroupUploads` to validate pending and done attachments before reupload and before final resend. Resolve the durable file path and stat the file when stored size is missing or zero. Treat oversize as terminal invalid media for this message, not transient retry.
6. Update `handleIncomingGroupMessage` so wire media descriptors are MIME- and size-validated before duplicate enrichment, group lookup, message save, or attachment save.
7. Verify `drainGroupOfflineInbox` needs no custom size logic if it always routes message media through `handleIncomingGroupMessage` or `GroupMessageListener`; add replay tests to prove this.
8. Update `GroupMessageListener` only if needed for clearer events; behavior should naturally suppress notification and auto-download when the handler returns null.
9. Update `downloadMedia(enforceGroupMediaPolicy: true)` to reject oversized declared attachments before marking `downloading` or calling bridge. If Dart cannot prevent relay-returned oversize from being written, extend `callP2PMediaDownload`, `go-mknoon/bridge.MediaDownload`, and `go-mknoon/node.MediaDownload` with an optional `maxBytes` guard checked after relay metadata and before file creation/copy.
10. Update `MediaGridCell` to render oversized legacy group media as failed when the descriptor is invalid for group size policy.
11. Run the focused direct suites first. If any evidence shows an existing lower-level policy already fully covers a boundary, stop broadening and reduce implementation to tests plus docs for that proven behavior.
12. After tests pass, update the matrix row and `test-inventory.md` only during the execution/closure phase, not during this planning session.

## risks and edge cases

- Missing, zero, negative, floating, string, or huge integer `size` fields on remote descriptors.
- Total-size integer overflow when many descriptors claim very large sizes.
- Durable retry rows currently saved with size `0`; implementation must stat durable files or start saving real sizes before treating `0` as invalid.
- Optimistic UI can briefly show a sending item; it must not become `sent` or publish/inbox-store oversized media, and failed cleanup must restore composer state consistently.
- Duplicate inbox replay can currently enrich sparse messages; size validation must run before enrichment.
- Foreground push recovery must not show "Photo" notification text for oversized remote media.
- Auto-download is fire-and-forget; tests need deterministic fakes proving no `media:download` command was sent.
- Relay metadata can report a size larger than the descriptor; bridge/node max-bytes support may be needed to avoid writing bytes before Dart can reject.
- Existing 1:1 and post media paths share upload/download helpers; group enforcement must be opt-in through group flags or policy calls and must not regress 1:1 media.

## exact tests and gates to run

Focused Flutter tests:

```bash
flutter test --no-pub test/core/media/group_media_size_policy_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart
flutter test --no-pub test/features/conversation/application/upload_media_use_case_test.dart
flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart
flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
flutter test --no-pub test/shared/widgets/media/media_grid_cell_test.dart
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub integration_test/foreground_group_push_drain_test.dart
```

Go tests if bridge/node/relay media size code changes:

```bash
cd go-mknoon && go test ./bridge ./node -run 'Media|Group' -v
cd go-relay-server && go test ./... -run 'Media|SizeLimit|GroupInbox' -v
```

Named and broad gates:

```bash
flutter test --no-pub test/features/groups
flutter test --no-pub test/features/groups/integration
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Recommended smoke/fake-network/3-party evidence:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub integration_test/foreground_group_push_drain_test.dart
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly
```

`SMOKE-GAP-05` is a matrix bundle label, not a shell target. For MD-002, map it to the focused direct suites above, `group_media_fanout_test.dart`, `foreground_group_push_drain_test.dart`, broad group runs, `groups`, and `completeness-check`.

## known-failure interpretation

- Treat failures in the new MD-002 tests as blocking.
- Treat pre-existing unrelated failures in a dirty worktree as existing risk, not MD-002 regressions, only after rerunning the exact failing command and confirming the failure is unrelated to touched files.
- If `group-real-network-nightly` cannot run because `FLUTTER_DEVICE_ID` or relay addresses are unavailable, record that as missing recommended external proof. It does not alone block `Covered` because the source row marks 3-party E2E recommended, but it must be called out in closure evidence.
- If any direct repo-owned receive test cannot prove rejection before storage/download, the row cannot be accepted regardless of other green gates.

## done criteria

- New group media size policy tests pass for boundaries, malformed sizes, total sums, and GIF cap composition.
- Send-side direct tests prove no upload, publish, inbox store, persisted sent state, or media row for oversized group media.
- Retry tests prove oversized pending media is terminalized without upload/resend.
- Live receive and encrypted inbox replay tests prove oversized media creates no message or attachment row.
- Listener and foreground push tests prove no notification and no `media:download` for oversized media.
- Download/display tests prove oversized descriptors are not downloaded or rendered as valid media.
- Existing allowed media fan-out still passes for image, video, GIF, and voice.
- Required gates pass or are documented with unrelated pre-existing failures.
- Matrix/test-inventory closure updates are made by the execution/closure agent after verification.

## scope guard

Do not add quarantine UX, warning banners, moderation/peer-scoring, chunk resume, hash verification, generic file attachments, new MIME types, new simulator matrix entries, or broad text length policy. Do not change relay defaults unless a direct MD-002 boundary requires it. Do not widen 1:1/post media behavior except for backward-compatible optional helper parameters with default behavior unchanged.

Overengineering would include a user-configurable settings UI, per-group admin-configurable limits, resumable transfer protocol changes, or file-type-specific product limits beyond existing GIF and relay-backed defaults.

## accepted differences / intentionally out of scope

- The relay server already enforces a hard 5 GB upload max and per-recipient pending-byte cap; Flutter MD-002 should mirror or stay below that, not replace relay enforcement.
- 1:1 media and posts can keep their existing media size behavior unless a shared helper must accept an optional group limit parameter.
- Raw encrypted envelope/frame byte limits are covered by existing 128 KB frame guards and the separate `MS-013` row for message/payload length; MD-002 is scoped to declared media bytes and media transfer size.
- Hash/integrity, spoofed-byte content verification, and dangerous MIME rejection remain owned by MD-001/MD-003 boundaries and should not be redesigned here.
- Recommended 3-party E2E can be recorded as unavailable if the environment lacks devices/relays, but repo-owned live/replay receive proof is mandatory.

## dependency impact

- `MD-003` hash/integrity can rely on MD-002's size guard to avoid downloading obviously oversized media before hash checks.
- `MD-012` quarantine UI should only handle media rejected after validation/download attempts; MD-002 should terminally fail oversized media without building quarantine UX.
- `MD-013` generic file support must later extend the size policy deliberately for file media instead of bypassing it.
- `AB-006` suspicious/oversized auto-download work can depend on MD-002's no-auto-download proof for oversized descriptors.
- `SMOKE-GAP-05` cannot close fully for size safety until MD-002 direct and integration evidence is recorded.

## Reviewer Pass

Sufficiency: sufficient with the constraints above. The plan names the missing send, retry, receive, replay, listener, download, display, Flutter, Go client, and relay evidence. The regression-first rule is explicit, and the closure bar blocks acceptance without receive-side pre-storage/pre-download proof.

Missing or deferred details: exact production limit values should be confirmed during implementation against product/relay constraints. If no product-specific lower limit exists, use relay-compatible defaults and test with injected lower limits.

Overengineering check: the plan avoids settings UI, per-group config, quarantine UI, chunking, and hash/integrity work.

## Arbiter Pass

Structural blockers remaining: none for implementation planning.

Incremental details intentionally deferred: final constant names, flow-event names, and whether Go node download max-bytes support is needed after Dart pre-download checks.

Accepted differences intentionally left unchanged: 1:1/post media behavior, MD-003 integrity, MD-012 quarantine UI, MD-013 generic file support, MD-014 simulator matrix, and `MS-013` raw message length policy.
