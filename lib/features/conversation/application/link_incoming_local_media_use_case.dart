import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// Persists an inbound local-WiFi media blob and returns its on-disk path, or
/// null on failure. Injected so the use-case is testable without a real
/// `LocalMediaServer`; production passes `LocalMediaServer.persistMedia`.
typedef LocalMediaPersistFn =
    Future<String?> Function(String mediaId, String fromPeerId);

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
}

/// NET-REL-01 P3: bridges an inbound local-WiFi media transfer into the
/// attachment pipeline.
///
/// The bytes arrive over the local media server; the matching attachment row
/// (keyed by [LocalMediaReady.id]) was already inserted in 'pending' status by
/// the text-envelope receive path ([handle_incoming_chat_message_use_case]).
/// This moves the file temp->persistent (otherwise the 5-min pendingTtl GC
/// reclaims it) and points the attachment's local path at the persisted file.
///
/// Dedupe vs the relay-CDN fallback: only act while the attachment is still a
/// pending download; if the relay path already completed it ('done'), skip so
/// we do not clobber it.
///
/// Errors are swallowed (logged via [emitFlowEvent]) — a failed local-media
/// link must never crash the incoming pipeline; the relay-CDN fallback path
/// remains responsible for eventual delivery.
Future<LinkLocalMediaOutcome> linkIncomingLocalMedia({
  required LocalMediaReady media,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required LocalMediaPersistFn persistMedia,
}) async {
  try {
    final pending = await mediaAttachmentRepo.getPendingDownloads();
    final stillPending = pending.any((a) => a.id == media.id);
    if (!stillPending) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_RECEIVE_SKIP_NOT_PENDING',
        details: {'id': media.id},
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
