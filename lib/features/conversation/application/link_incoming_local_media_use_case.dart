import 'dart:io';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// Persists an inbound local-WiFi media blob and returns its on-disk path, or
/// null on failure. Injected so the use-case is testable without a real
/// `LocalMediaServer`; production passes `LocalMediaServer.persistMedia`.
typedef LocalMediaPersistFn =
    Future<String?> Function(String mediaId, String fromPeerId);

/// Local media can arrive well before the encrypted metadata envelope on real
/// devices, especially when the receiver is off the chat screen. Keep the temp
/// blob linkable for the same bounded window as the local media server TTL.
const Duration kDefaultLocalMediaMetadataGrace = Duration(minutes: 5);

/// Outcome of [linkIncomingLocalMedia] — lets callers and tests assert which
/// branch was taken without scraping flow events.
enum LinkLocalMediaOutcome {
  /// Media persisted and the attachment row repointed at the persisted file.
  linked,

  /// The attachment was no longer a pending download (the relay-CDN fallback
  /// already completed it), so we skipped to avoid clobbering it.
  skippedNotPending,

  /// `persistMedia` returned null (the temp->persistent move failed).
  persistFailed,

  /// An unexpected error was thrown and swallowed.
  error,

  /// 112: the bytes are an enc-flagged ciphertext artifact. They were moved
  /// to the download seam's staging path (`<canonical>.enc`); the row was
  /// NOT linked or completed — completion happens only via decrypt-adopt.
  stagedForDecrypt,
}

/// NET-REL-01 P3: bridges an inbound local-WiFi media transfer into the
/// attachment pipeline.
///
/// The bytes arrive over the local media server; the matching attachment row
/// (keyed by [LocalMediaReady.id]) is inserted in 'pending' status by the
/// text-envelope receive path ([handle_incoming_chat_message_use_case]).
///
/// Local media can beat the encrypted chat envelope on a warm LAN connection,
/// so this waits briefly for the attachment row before deciding the blob is
/// unknown. Once the row exists, this moves the file temp->persistent
/// (otherwise the 5-min pendingTtl GC reclaims it) and points the attachment's
/// local path at the persisted file.
///
/// Dedupe vs the relay-CDN fallback: act while the attachment is still
/// incomplete. The local-media ready callback can arrive after the fallback
/// path has moved the row from `pending` to `downloading` or `failed`; those
/// states are still repairable. If the relay path already completed it
/// (`done` with a local path), skip so we do not clobber it.
///
/// Errors are swallowed (logged via [emitFlowEvent]) — a failed local-media
/// link must never crash the incoming pipeline; the relay-CDN fallback path
/// remains responsible for eventual delivery.
Future<LinkLocalMediaOutcome> linkIncomingLocalMedia({
  required LocalMediaReady media,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required LocalMediaPersistFn persistMedia,
  // Required to derive the decrypt-adopt staging path for enc-flagged
  // transfers (112 Phase 1.5); plaintext links never touch it.
  MediaFileManager? mediaFileManager,
  Duration pendingLookupGrace = kDefaultLocalMediaMetadataGrace,
  Duration pendingLookupInterval = const Duration(milliseconds: 50),
}) async {
  try {
    final attachment = await _waitForLinkableAttachment(
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaId: media.id,
      grace: pendingLookupGrace,
      interval: pendingLookupInterval,
    );
    if (attachment == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_RECEIVE_SKIP_NOT_PENDING',
        details: {'id': media.id},
      );
      return LinkLocalMediaOutcome.skippedNotPending;
    }

    if (media.enc) {
      // Ciphertext custody: enc-flagged bytes must NEVER be linked or
      // completed through the plaintext path — an old-style link would
      // persist garbage as `done` media with no repair trigger (112
      // Section 4). Stage at the exact path the download adoption seam
      // decrypt-promotes from, keyed on the ROW's mime (from the
      // encrypted envelope), and leave the row pending.
      if (mediaFileManager == null || !attachment.hasEncryptionKeyMaterial) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_RECEIVE_ENC_UNLINKABLE',
          details: {
            'id': media.id,
            'hasKeyMaterial': attachment.hasEncryptionKeyMaterial,
            'hasFileManager': mediaFileManager != null,
          },
        );
        return LinkLocalMediaOutcome.skippedNotPending;
      }
      final persistedPath = await persistMedia(media.id, media.from);
      if (persistedPath == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_RECEIVE_PERSIST_FAILED',
          details: {'id': media.id},
        );
        return LinkLocalMediaOutcome.persistFailed;
      }
      final absolutePath = await mediaFileManager.localPathForAttachment(
        contactPeerId: media.from,
        blobId: media.id,
        mime: attachment.mime,
      );
      final stagedFile = File('$absolutePath.enc');
      await stagedFile.parent.create(recursive: true);
      if (await stagedFile.exists()) {
        await stagedFile.delete();
      }
      await File(persistedPath).rename(stagedFile.path);
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_RECEIVE_ENC_STAGED',
        details: {'id': media.id, 'stagedPath': stagedFile.path},
      );
      return LinkLocalMediaOutcome.stagedForDecrypt;
    }

    final persistedPath = await persistMedia(media.id, media.from);
    if (persistedPath == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_RECEIVE_PERSIST_FAILED',
        details: {'id': media.id},
      );
      return LinkLocalMediaOutcome.persistFailed;
    }
    await mediaAttachmentRepo.updateLocalPath(media.id, persistedPath);
    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MEDIA_RECEIVE_ATTACHMENT_LINKED',
      details: {'id': media.id, 'path': persistedPath},
    );
    return LinkLocalMediaOutcome.linked;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MEDIA_RECEIVE_ERROR',
      details: {'id': media.id, 'error': e.toString()},
    );
    return LinkLocalMediaOutcome.error;
  }
}

enum _LocalMediaLinkDecision { link, skip, wait }

/// Waits for a linkable attachment row and returns it, or null when no
/// linkable row appears within [grace] (unknown blob or already completed).
Future<MediaAttachment?> _waitForLinkableAttachment({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required String mediaId,
  required Duration grace,
  required Duration interval,
}) async {
  Future<(_LocalMediaLinkDecision, MediaAttachment?)> decide() async {
    final attachment = await _findAttachmentById(
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaId: mediaId,
    );
    if (attachment == null) {
      return (_LocalMediaLinkDecision.wait, null);
    }
    return _canLinkLocalMedia(attachment)
        ? (_LocalMediaLinkDecision.link, attachment)
        : (_LocalMediaLinkDecision.skip, null);
  }

  var (decision, attachment) = await decide();
  if (decision != _LocalMediaLinkDecision.wait) {
    return attachment;
  }
  if (grace <= Duration.zero) {
    return null;
  }

  final effectiveInterval = interval > Duration.zero
      ? interval
      : const Duration(milliseconds: 50);
  final deadline = DateTime.now().add(grace);
  while (DateTime.now().isBefore(deadline)) {
    final remaining = deadline.difference(DateTime.now());
    final delay = remaining < effectiveInterval ? remaining : effectiveInterval;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    (decision, attachment) = await decide();
    if (decision != _LocalMediaLinkDecision.wait) {
      return attachment;
    }
  }

  return null;
}

Future<MediaAttachment?> _findAttachmentById({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required String mediaId,
}) async {
  if (mediaAttachmentRepo is MediaAttachmentByIdLookup) {
    final byIdLookup = mediaAttachmentRepo as MediaAttachmentByIdLookup;
    return byIdLookup.getAttachmentById(mediaId);
  }

  final pending = await mediaAttachmentRepo.getPendingDownloads();
  for (final attachment in pending) {
    if (attachment.id == mediaId) {
      return attachment;
    }
  }
  return null;
}

bool _canLinkLocalMedia(MediaAttachment attachment) {
  final localPath = attachment.localPath;
  final hasLocalPath = localPath != null && localPath.isNotEmpty;
  if (attachment.downloadStatus == kMediaDownloadStatusDone && hasLocalPath) {
    return false;
  }

  return attachment.downloadStatus != kMediaDownloadStatusUploadPending &&
      attachment.downloadStatus != kMediaDownloadStatusUploadFailed &&
      attachment.downloadStatus != kMediaDownloadStatusUploadCancelled &&
      attachment.downloadStatus != kMediaDownloadStatusIntegrityFailed;
}
