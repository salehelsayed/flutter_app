import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/group_media_integrity_policy.dart';
import '../../media/media_owner_lane.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';

/// Inserts a media attachment row verbatim (no merge, REPLACE on conflict).
///
/// 228: production save paths must use
/// [dbSaveMediaAttachmentPreservingLocalState] instead — a blind REPLACE
/// erases local-only owner/bookmark/playback state on replay. This raw insert
/// remains for fixtures and migration tooling only.
Future<void> dbInsertMediaAttachment(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'media_attachments',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// True when a local path column value is non-blank.
bool mediaLocalPathHasValue(String? path) =>
    path != null && path.trim().isNotEmpty;

/// True when a local path points into the transient `pending_uploads/`
/// staging area (not a durable media location).
bool mediaLocalPathIsTransient(String? path) {
  if (path == null || path.isEmpty) {
    return false;
  }
  final normalized = path.replaceAll('\\', '/');
  return normalized.startsWith('pending_uploads/') ||
      normalized.contains('/pending_uploads/');
}

const Set<String> _nonTerminalMediaStatuses = {
  kMediaDownloadStatusPending,
  kMediaDownloadStatusDownloading,
  kMediaDownloadStatusUploadPending,
};

/// Completed-local-path preservation policy (raw column values): an existing
/// completed download must survive an ordinary metadata replay that would
/// otherwise regress it to a non-terminal status or a transient path.
bool shouldPreserveCompletedMediaLocalPath({
  required String? existingStatus,
  required String? existingPath,
  required String? incomingStatus,
  required String? incomingPath,
}) {
  if (existingStatus != kMediaDownloadStatusDone ||
      !mediaLocalPathHasValue(existingPath)) {
    return false;
  }

  if (_nonTerminalMediaStatuses.contains(incomingStatus)) {
    return true;
  }

  if (incomingStatus == kMediaDownloadStatusDone) {
    if (!mediaLocalPathHasValue(incomingPath)) {
      return true;
    }
    return mediaLocalPathIsTransient(incomingPath) &&
        !mediaLocalPathIsTransient(existingPath);
  }

  return false;
}

/// 228: atomic owner-guarded save. New rows insert verbatim; an existing row
/// with the same id is updated in ONE transaction that:
///  - fails closed ([MediaAttachmentOwnerViolation]) if the incoming row
///    would re-parent the attachment to another owner lane or message —
///    this is the in-database race guard behind the repository's
///    pre-side-effect identity validation;
///  - preserves local-only state (owner_lane, is_bookmarked,
///    last_playback_position_ms) across ordinary replays;
///  - re-clamps a stored playback position when the replay supplies a
///    (new) known duration;
///  - preserves a completed local path per
///    [shouldPreserveCompletedMediaLocalPath].
Future<void> dbSaveMediaAttachmentPreservingLocalState(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_SAVE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    // dbWriteTransaction (never raw db.transaction): the zone guard makes a
    // bridge call inside this merge impossible to introduce silently.
    await dbWriteTransaction(db, (txn) async {
      final existingRows = await txn.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existingRows.isEmpty) {
        await txn.insert('media_attachments', row);
        return;
      }

      final existing = existingRows.first;
      if (existing['owner_lane'] != row['owner_lane'] ||
          existing['message_id'] != row['message_id']) {
        throw MediaAttachmentOwnerViolation(
          'save would re-parent attachment '
          '${id.length > 8 ? id.substring(0, 8) : id} from '
          '(${existing['owner_lane']}, ${existing['message_id']}) to '
          '(${row['owner_lane']}, ${row['message_id']})',
        );
      }

      final merged = Map<String, Object?>.from(row);
      // Local-only viewer state always survives an ordinary replay.
      merged['is_bookmarked'] = existing['is_bookmarked'];
      var position =
          ((existing['last_playback_position_ms'] as num?)?.toInt()) ?? 0;
      final durationMs = (merged['duration_ms'] as num?)?.toInt();
      if (durationMs != null && durationMs >= 0 && position > durationMs) {
        // A replay supplied a (newly) known duration — re-clamp the stored
        // resume position instead of trusting a stale overshoot.
        position = durationMs;
      }
      merged['last_playback_position_ms'] = position;

      if (shouldPreserveCompletedMediaLocalPath(
        existingStatus: existing['download_status'] as String?,
        existingPath: existing['local_path'] as String?,
        incomingStatus: merged['download_status'] as String?,
        incomingPath: merged['local_path'] as String?,
      )) {
        emitFlowEvent(
          layer: 'DB',
          event: 'MEDIA_DB_SAVE_PRESERVED_COMPLETED_LOCAL_PATH',
          details: {
            'id': id.length > 8 ? id.substring(0, 8) : id,
            'incomingStatus': merged['download_status'],
          },
        );
        merged['local_path'] = existing['local_path'];
        merged['download_status'] = existing['download_status'];
      }

      await txn.update(
        'media_attachments',
        merged,
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_SAVE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_SAVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all media attachments for a single message in one owner lane.
///
/// 228: direct and group message IDs can collide, so the owner filter is a
/// hard SQL predicate — `unresolved` legacy rows never surface here.
Future<List<Map<String, Object?>>> dbLoadMediaForMessage(
  Database db,
  String messageId, {
  required String ownerLane,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_FOR_MESSAGE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'ownerLane': ownerLane,
    },
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: [messageId, ownerLane],
      orderBy: 'created_at ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGE_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single media attachment by blob/attachment ID.
///
/// Attachment IDs are the table's global row identity (PRIMARY KEY), so a
/// by-ID lookup cannot cross owner lanes and stays untyped.
Future<Map<String, Object?>?> dbLoadMediaById(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_BY_ID_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    emitFlowEvent(
      layer: 'DB',
      event: results.isEmpty
          ? 'MEDIA_DB_LOAD_BY_ID_NOT_FOUND'
          : 'MEDIA_DB_LOAD_BY_ID_FOUND',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );

    return results.isEmpty ? null : results.first;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_BY_ID_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all media attachments for multiple messages (single owner lane) in
/// a single query.
Future<List<Map<String, Object?>>> dbLoadMediaForMessages(
  Database db,
  List<String> messageIds, {
  required String ownerLane,
}) async {
  if (messageIds.isEmpty) return [];

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_FOR_MESSAGES_START',
    details: {'messageCount': messageIds.length, 'ownerLane': ownerLane},
  );

  try {
    final placeholders = List.filled(messageIds.length, '?').join(',');
    final results = await db.rawQuery(
      'SELECT * FROM media_attachments '
      'WHERE message_id IN ($placeholders) AND owner_lane = ? '
      'ORDER BY created_at ASC',
      [...messageIds, ownerLane],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGES_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGES_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the local path and download status of a media attachment.
Future<void> dbUpdateMediaLocalPath(
  Database db,
  String id,
  String localPath,
  String downloadStatus,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_UPDATE_LOCAL_PATH_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.update(
      'media_attachments',
      {
        'local_path': localPath,
        'download_status': downloadStatus,
        // A successful local-path commit resets the bounded download retry
        // budget so a future transient failure starts fresh (INV-DL-2).
        'download_retry_count': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_LOCAL_PATH_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_LOCAL_PATH_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the download status of a media attachment.
Future<void> dbUpdateMediaDownloadStatus(
  Database db,
  String id,
  String downloadStatus,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_UPDATE_STATUS_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'status': downloadStatus,
    },
  );

  try {
    await db.update(
      'media_attachments',
      {'download_status': downloadStatus},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_STATUS_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// 228: sets the local bookmark flag. Only visual media (image/video) can be
/// bookmarked; a missing row or another media type fails with ArgumentError.
Future<void> dbSetMediaBookmarked(
  Database db,
  String id, {
  required bool bookmarked,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_SET_BOOKMARKED_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'bookmarked': bookmarked,
    },
  );

  try {
    final rows = await db.query(
      'media_attachments',
      columns: const ['media_type'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(id, 'id', 'unknown media attachment');
    }
    final mediaType = rows.single['media_type'] as String?;
    if (mediaType != 'image' && mediaType != 'video') {
      throw ArgumentError.value(
        mediaType,
        'mediaType',
        'only image/video attachments can be bookmarked',
      );
    }

    await db.update(
      'media_attachments',
      {'is_bookmarked': bookmarked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_SET_BOOKMARKED_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_SET_BOOKMARKED_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// 228: stores a durable video resume position.
///
/// Semantics (TC-228-10): non-video rows are rejected; a negative position
/// clamps to 0; with a known duration, reaching (or passing) the end counts
/// as completion and resets the stored position to 0; with an unknown
/// duration the non-negative position is stored as-is and re-clamped later
/// when a replay supplies the duration (see
/// [dbSaveMediaAttachmentPreservingLocalState]).
Future<void> dbUpdateMediaPlaybackPosition(
  Database db,
  String id,
  int positionMs,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_UPDATE_PLAYBACK_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'positionMs': positionMs,
    },
  );

  try {
    final rows = await db.query(
      'media_attachments',
      columns: const ['media_type', 'duration_ms'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(id, 'id', 'unknown media attachment');
    }
    final mediaType = rows.single['media_type'] as String?;
    if (mediaType != 'video') {
      throw ArgumentError.value(
        mediaType,
        'mediaType',
        'playback position applies only to video attachments',
      );
    }

    var stored = positionMs < 0 ? 0 : positionMs;
    final durationMs = (rows.single['duration_ms'] as num?)?.toInt();
    if (durationMs != null && durationMs > 0 && stored >= durationMs) {
      // Completion: resume restarts from the beginning.
      stored = 0;
    }

    await db.update(
      'media_attachments',
      {'last_playback_position_ms': stored},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_PLAYBACK_SUCCESS',
      details: {
        'id': id.length > 8 ? id.substring(0, 8) : id,
        'storedMs': stored,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_PLAYBACK_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all media attachments for a message in one owner lane.
Future<int> dbDeleteMediaForMessage(
  Database db,
  String messageId, {
  required String ownerLane,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_DELETE_FOR_MESSAGE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'ownerLane': ownerLane,
    },
  );

  try {
    final count = await db.delete(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: [messageId, ownerLane],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_MESSAGE_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_MESSAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all DIRECT-owned media attachments for a contact via subquery on
/// messages.
///
/// 228: the owner predicate keeps a same-ID group sibling and unresolved
/// legacy rows out of contact cleanup — `messages.id` values are not globally
/// unique across lanes.
Future<int> dbDeleteMediaForContact(Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_DELETE_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final count = await db.rawDelete(
      "DELETE FROM media_attachments WHERE owner_lane = 'direct' "
      'AND message_id IN '
      '(SELECT id FROM messages WHERE contact_peer_id = ?)',
      [contactPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Marks one message's upload-pending attachment rows (single owner lane) as
/// upload-failed.
Future<int> dbMarkUploadPendingAttachmentsFailedForMessage(
  Database db,
  String messageId, {
  required String ownerLane,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_TERMINALIZE_UPLOADS_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'ownerLane': ownerLane,
    },
  );

  try {
    final count = await db.update(
      'media_attachments',
      {'download_status': 'upload_failed'},
      where:
          "message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
      whereArgs: [messageId, ownerLane],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_TERMINALIZE_UPLOADS_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_TERMINALIZE_UPLOADS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns one owner lane's media_attachments rows with
/// download_status='upload_pending', ordered by created_at ASC (oldest
/// first).
///
/// These are outgoing attachments whose upload was interrupted before
/// completing. They must be re-uploaded on the next retry cycle.
///
/// 228: the owner filter is applied in SQL BEFORE the LIMIT so a burst of
/// sibling-lane rows can never starve this lane's retry budget.
///
/// Returns at most [limit] rows.
Future<List<Map<String, Object?>>> dbLoadUploadPendingAttachments(
  Database db, {
  int limit = 50,
  required String ownerLane,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_START',
    details: {'limit': limit, 'ownerLane': ownerLane},
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: "download_status = 'upload_pending' AND owner_lane = ?",
      whereArgs: [ownerLane],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all media attachments with download_status = 'pending'.
///
/// Untyped by design: its only consumer resolves rows by unique attachment
/// ID (link_incoming_local_media fallback), which cannot cross lanes.
Future<List<Map<String, Object?>>> dbLoadPendingMediaDownloads(
  Database db,
) async {
  emitFlowEvent(layer: 'DB', event: 'MEDIA_DB_LOAD_PENDING_START', details: {});

  try {
    final results = await db.query(
      'media_attachments',
      where: "download_status = ?",
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
