# 1:1 Media Unavailable Debug - Codex Run

Date: 2026-06-11
Model target: gpt-5.5
Reasoning effort target: xhigh
Workflow source copy: .agents/skills/one-to-one-media-unavailable-debug-codex/references/original-claude-workflow.js

## Executive Summary

The strongest explanation is not a plain sender upload failure. On the normal relay path, the sender uploads media before sending the envelope; if upload fails, the direct envelope should not be sent. A sender thumbnail only proves A still has a local file.

The confirmed high-risk mechanisms are on the receiver/transport side:

1. Relay media custody is not durable/shared like envelope custody. Media metadata is in memory, while inbox/control-plane state can be Redis-backed or otherwise outlive/route around the media store.
2. Local-WiFi media can skip relay upload after an ACK that proves temp-file receipt, not durable receiver attachment linkage.
3. Direct relay blobs are auto-deleted after server-side streaming, before Flutter has durably committed `local_path`.

There are also confirmed permanence/diagnostic issues: direct 1:1 unavailable-media retry is not wired in the screen, duplicate envelope replay does not repair failed media, and thumbnail generation can show the same unavailable placeholder even when a local video file exists.

## Graphify Queries Used

- `cd graphify-arch && graphify query "Trace 1:1 direct in-app video media unavailable sender receiver relay upload download file lifecycle retry paths" --budget 3000`
- `cd graphify-arch && graphify query "1:1 direct in-app camera video sender media upload UploadMediaUseCase SendChatMessageUseCase _preparePendingMedia sent status thumbnail" --budget 4500`
- `cd graphify-arch && graphify query "1:1 direct receiver incoming chat message video attachment media unavailable download media_attachments MediaFileManager thumbnail retry" --budget 4500`
- `cd graphify-arch && graphify query "go mknoon relay one-to-one media upload download bridge timeout relay store fetch TTL size cap media blob" --budget 4500`
- `cd graphify-arch && graphify query "tests 1:1 direct media unavailable video upload download retry media attachments host reliability simulation Go tests" --budget 4500`
- `cd graphify-arch && graphify query "direct 1:1 media encryption metadata encryptedUploadPath contentHash encryptionKeyBase64 downloadMedia enforceGroupMediaPolicy" --budget 4500`

## Graphify Process Notes

- Use `graphify-arch` first for app-owned architecture and workflow routing. It was the right default here: `graphify-arch/GRAPH_SELECTION.md` shows a smaller graph, 0.9675 app-owned node ratio, and removal of vendored/native SQLCipher hubs.
- Query with incident-shaped phrases plus concrete symbols. Generic anchors such as `trace`, `relay`, or `media_attachments` overmatched broad test/schema nodes.
- Treat graphify as a routing map only. Every finding below was source-checked directly.
- Current sufficiency: `graphify-arch` is sufficient for first-pass debug. The full `graphify-out` graph remains useful for generated/native/vendor fallback. For future media incidents, build a third scoped graph only if repeated work continues: direct conversation media, `go-mknoon`, `go-relay-server`, local discovery, media storage, l10n media states, and targeted reliability tests.

## Ranked Root Causes

1. **Relay media metadata is volatile while envelopes can persist.**
   `MediaStore` constructs fresh in-memory `index`/`byPeer` maps and does not rebuild them from disk (`go-relay-server/media.go:45-62`). The app wires Redis-capable control-plane stores, then separately creates `NewMediaStore` (`go-relay-server/main.go:87-103`, `go-relay-server/server_bootstrap.go:84-121`). A post-upload relay restart, deploy, or different relay instance can still deliver the envelope while `media.lookup(id)` returns `not found` (`go-relay-server/media.go:394-397`), and Flutter marks the attachment failed (`lib/features/conversation/application/download_media_use_case.dart:974-990`).

2. **Receiver can download from the wrong reachable relay and stop.**
   Go opens one media stream to the first reachable configured relay (`go-mknoon/node/media.go:212-263`). `MediaDownload` treats a relay `not found` as terminal and does not try later relays (`go-mknoon/node/media.go:413-445`). This is the multi-relay form of root cause 1.

3. **Local-WiFi success suppresses relay fallback before receiver durability.**
   Sender tries local media first and skips `uploadMediaFn` on `localSuccess` (`lib/features/conversation/presentation/screens/conversation_wired.dart:1793-1843`). The receiver sends `media_uploaded` after temp-file/hash success (`lib/core/local_discovery/local_ws_server.dart:189-208`, `lib/core/local_discovery/local_media_server.dart:364-378`), but durable `updateLocalPath` happens later through `linkIncomingLocalMedia` (`lib/main.dart:1818-1823`, `lib/features/conversation/application/link_incoming_local_media_use_case.dart:57-88`). If that link misses the envelope row, times out, or persist fails, there is no relay blob to fetch.

4. **Direct relay auto-delete can race receiver local-path commit.**
   Relay auto-deletes non-group blobs after streaming (`go-relay-server/media.go:431-445`). Native writes `outputPath` before returning success (`go-mknoon/node/media.go:447-470`), but Flutter commits `local_path` only after the bridge call returns (`lib/features/conversation/application/download_media_use_case.dart:1344-1353`). If the app dies or DB update fails in between, retry misses the orphan because local repair requires stored `localPath` (`lib/features/conversation/application/download_media_use_case.dart:330-341`), retries relay, then can delete the orphan as failed cleanup (`lib/features/conversation/application/download_media_use_case.dart:584-589`).

5. **Recovery/UI gaps make failures sticky.**
   Direct `ConversationScreen` builds `LetterCard` without `onRetryUnavailableMedia` (`lib/features/conversation/presentation/screens/conversation_screen.dart:517-552`), even though `LetterCard`/media widgets support it (`lib/features/conversation/presentation/widgets/letter_card.dart:234-253`, `lib/shared/widgets/media/media_grid_cell.dart:88-103`). Duplicate envelopes return before media repair (`lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:200-209`, `lib/features/conversation/application/chat_message_listener.dart:416-423`).

6. **Thumbnail failures can masquerade as missing media.**
   A done video still uses `MediaThumbnailImage`; null thumbnail generation maps to the same unavailable placeholder (`lib/shared/widgets/media/media_grid_cell.dart:105-118`, `lib/shared/widgets/media/media_thumbnail_image.dart:75-85`, `lib/core/media/video_thumbnail_cache.dart:64-87`). This is a visual false-positive unless B's DB row is `failed`/`pending` or the local file is missing.

## Confirmed Findings

- Confirmed high: relay media metadata is in-memory and can diverge from persistent/shared envelope state.
- Confirmed high: media download does not fail over after a reachable relay returns `not found`.
- Confirmed high: local-WiFi `media_uploaded` proves temp receipt, not durable receiver attachment linkage, while sender skips relay upload.
- Confirmed high: direct relay auto-delete can make receiver DB/local commit failures unrecoverable.
- Confirmed medium: direct 1:1 unavailable-media retry is not wired to the shared retry UI.
- Confirmed medium: duplicate replay does not repair already-failed media; it is a recovery gap, not the first failure.
- Confirmed medium: thumbnail failure can show `Media unavailable` with a playable local video.

## Unverified Findings

- Stable-ID reupload can destroy an existing relay blob if retry reuses the same ID and `os.Create` truncates the final path before replacement upload completes (`go-relay-server/media.go:348-363`).
- Media cap/inbox cap mismatch can keep 100 envelopes but only 50 media blobs per peer (`go-relay-server/media.go:20-21`, `go-relay-server/inbox.go:24-27`).
- Initial page load may overwrite streamed media updates because `_loadInitialPage` assigns `_messages = messages` after listeners are started (`lib/features/conversation/presentation/screens/conversation_wired.dart:486-488`, `1059-1070`, `1342-1347`).
- Local media DB repair may not invalidate an already-open direct conversation UI.
- Non-mp4/quicktime video MIME variants can be accepted as video but invalidated by shared display policy; less likely for normal in-app camera mp4/mov output.

## Refuted Findings

- Refuted for current production 1:1: direct encrypted media is saved as ciphertext. `uploadMedia` only sets blob encryption/hash metadata when `allowedPeers != null` (`lib/features/conversation/application/upload_media_use_case.dart:213-279`). Current direct 1:1 send paths omit `allowedPeers`, so this requires injected, legacy, or corrupted direct payloads rather than a normal TestFlight direct send.
- Refuted as primary cause: plain relay upload failure before envelope send. The sender path requires upload success before sending the direct envelope; upload failure should leave A failed/restored, not sent.

## Discriminating Evidence To Pull

Sender phone:

- `messages` row for message id: `status`, `transport`, `wire_envelope`, timestamps.
- `media_attachments` row: `id`, `message_id`, `mime`, `size`, `local_path`, `download_status`, encryption fields.
- FLOW logs for `MEDIA_UPLOAD_START`, `P2P_MEDIA_UPLOAD_RESPONSE`, `MEDIA_UPLOAD_SUCCESS/FAILED`, `LOCAL_MEDIA_*`, `RETRY_FAILED_MESSAGE_*`.
- File existence for `pending_uploads/<messageId>/<attachmentId>` and `media/<peer>/<blob>`.
- Whether `isLocalPeer` was true and whether `sendLocalMedia` succeeded.

Receiver phone:

- `messages` row exists for the same id and timestamp.
- `media_attachments` row status: `pending`, `downloading`, `failed`, or `done`; whether `local_path` is null/relative/absolute.
- File existence and size for `media/<sender>/<blob>.<ext>`, plus sibling `<video>.thumb.jpg`.
- FLOW logs for `P2P_MEDIA_DOWNLOAD_REQUEST/RESPONSE`, `MEDIA_DOWNLOAD_FAILED`, `MEDIA_DOWNLOAD_INVALID_FILE`, `MEDIA_DOWNLOAD_SUCCESS`, `MEDIA_DOWNLOAD_RELAY_DEPENDENCY_RISK`, `LOCAL_MEDIA_RECEIVE_*`.
- Tap/play behavior if row is `done`: distinguishes thumbnail false-unavailable from actual missing blob.

Relay:

- For the blob id: upload log, download log, `not found`, `not authorized`, incomplete stream, auto-delete, TTL/peer-cap delete.
- Relay deploy/restart time between A upload and B download.
- `RELAY_BACKEND` and Redis/shared backend settings.
- Number of distinct relay peer IDs/instances and A/B relay order.
- On each relay instance: file presence under media data dir and whether runtime metadata/index contains the blob.

## Failing Tests To Add

- Go relay restart durability: upload 1:1 blob, recreate `MediaStore` over same data dir, retrieve envelope via Redis/shared path, assert download still works.
- Go multi-relay routing: sender uploads through relay A, receiver first reaches empty relay B, assert download retries A instead of terminal `not found`.
- Flutter download orphan adoption: seed pending attachment with no `localPath` plus canonical local file, make relay return `not found`, assert `downloadMedia` adopts the file rather than deleting it.
- Local-WiFi fallback: ACK local temp upload, delay/suppress envelope row past grace or fail `persistMedia`, assert sender does not skip relay fallback or receiver recovers.
- Direct UI retry: failed incoming direct video renders a retry control and invokes `downloadMedia`.
- Duplicate replay repair: duplicate media envelope with failed attachment should trigger media repair/retry, not only duplicate rejection.
- Thumbnail false-unavailable: valid done video with thumbnail failure should show a video fallback/play affordance, not only `media_unavailable`.
- End-to-end acceptance: in-app camera video on A -> B receives envelope -> B has playable local file -> no `Media unavailable` -> retry works if first download fails.

## Trace Digest

- **Sender path:** Relay upload success is required before direct envelope send. A thumbnail proves only A local file availability. Local-WiFi is the exception because relay upload is skipped after local transfer success.
- **Receiver path:** Incoming direct envelopes persist metadata, then media download runs fire-and-forget. Download failure sets `failed` and renders unavailable.
- **Relay path:** Media and envelope custody are separate. Media is local disk plus process-local index; inbox/control-plane may persist/share independently.
- **File lifecycle:** Receiver relay downloads use deterministic `media/<sender>/<blob>.<ext>` paths, but DB `local_path` commit is a later Flutter step.
- **Retry/recovery:** Sender recovery is broad; receiver media recovery is mostly conversation-load driven. Resume/reconnect does not appear to sweep stuck incoming media.
- **Video-specific:** Thumbnail generation is local-only and can mimic missing media.
- **Coverage:** Current tests do not prove the exact recorded-video A-to-B playable-file path.

