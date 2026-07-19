import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../constants/retry_constants.dart';
import '../../media/group_media_integrity_policy.dart';
import '../../media/media_file_path_convention.dart';
import '../../media/media_owner_lane.dart';
import '../../media/upload_media_outcome.dart';
import '../../media/upload_retry_projection.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'group_messages_db_helpers.dart';
import 'messages_db_helpers.dart';

/// Atomically projects one direct attachment upload failure and its parent.
///
/// Parent qualification happens before any attachment write. Only outgoing
/// `sending|failed` parents and the exact direct-owned `upload_pending` row are
/// eligible. A parent update failure therefore rolls the attachment mutation
/// back with the same transaction.
Future<UploadRetryProjectionResult> dbProjectDirectUploadFailure(
  Database db, {
  required String messageId,
  required String attachmentId,
  required UploadMediaDisposition disposition,
}) {
  return _dbProjectUploadFailure(
    db,
    parentTable: 'messages',
    parentAllowedStatuses: const {'sending', 'failed'},
    retryableParentStatus: 'sending',
    ownerLane: MediaOwnerLane.direct,
    messageId: messageId,
    attachmentId: attachmentId,
    disposition: disposition,
  );
}

/// Atomically projects one group attachment upload failure and its parent.
///
/// Group retryable parents use the existing `queued_offline` status; no new
/// status or migration is introduced.
Future<UploadRetryProjectionResult> dbProjectGroupUploadFailure(
  Database db, {
  required String messageId,
  required String attachmentId,
  required UploadMediaDisposition disposition,
}) {
  return _dbProjectUploadFailure(
    db,
    parentTable: 'group_messages',
    parentAllowedStatuses: const {'sending', 'queued_offline', 'failed'},
    retryableParentStatus: 'queued_offline',
    ownerLane: MediaOwnerLane.group,
    messageId: messageId,
    attachmentId: attachmentId,
    disposition: disposition,
  );
}

Future<UploadRetryProjectionResult> _dbProjectUploadFailure(
  Database db, {
  required String parentTable,
  required Set<String> parentAllowedStatuses,
  required String retryableParentStatus,
  required MediaOwnerLane ownerLane,
  required String messageId,
  required String attachmentId,
  required UploadMediaDisposition disposition,
}) {
  return dbWriteTransaction(db, (txn) async {
    final parentRows = await txn.rawQuery(
      'SELECT status, is_incoming FROM $parentTable WHERE id = ? LIMIT 1',
      [messageId],
    );
    if (parentRows.isEmpty) {
      return const UploadRetryProjectionResult.notApplied();
    }
    final parent = parentRows.single;
    final parentStatus = parent['status'] as String?;
    final isIncoming = ((parent['is_incoming'] as num?)?.toInt() ?? 0) != 0;
    if (isIncoming || !parentAllowedStatuses.contains(parentStatus)) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final attachmentRows = await txn.rawQuery(
      'SELECT upload_retry_count FROM media_attachments '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      "AND download_status = 'upload_pending' LIMIT 1",
      [attachmentId, messageId, ownerLane.dbValue],
    );
    if (attachmentRows.isEmpty) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final currentCount =
        (attachmentRows.single['upload_retry_count'] as num?)?.toInt() ?? 0;
    late final String attachmentStatus;
    late final int projectedCount;
    switch (disposition) {
      case UploadMediaDisposition.connectivityRetryable:
        attachmentStatus = 'upload_pending';
        projectedCount = currentCount;
        break;
      case UploadMediaDisposition.boundedRetryable:
        final incrementedCount = currentCount + 1;
        projectedCount = incrementedCount > kMaxUploadRetries
            ? kMaxUploadRetries
            : incrementedCount;
        attachmentStatus = projectedCount >= kMaxUploadRetries
            ? 'upload_failed'
            : 'upload_pending';
        break;
      case UploadMediaDisposition.terminal:
        attachmentStatus = 'upload_failed';
        projectedCount = currentCount;
        break;
    }

    final attachmentCount = await txn.rawUpdate(
      'UPDATE media_attachments SET download_status = ?, '
      'upload_retry_count = ? WHERE id = ? AND message_id = ? '
      "AND owner_lane = ? AND download_status = 'upload_pending'",
      [
        attachmentStatus,
        projectedCount,
        attachmentId,
        messageId,
        ownerLane.dbValue,
      ],
    );
    if (attachmentCount != 1) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final terminalRows = await txn.rawQuery(
      'SELECT 1 FROM media_attachments WHERE message_id = ? '
      "AND owner_lane = ? AND download_status = 'upload_failed' LIMIT 1",
      [messageId, ownerLane.dbValue],
    );
    final terminal = terminalRows.isNotEmpty;
    final allowedStatusPlaceholders = List.filled(
      parentAllowedStatuses.length,
      '?',
    ).join(', ');
    final parentCount = await txn.rawUpdate(
      'UPDATE $parentTable SET status = ? WHERE id = ? '
      'AND COALESCE(is_incoming, 0) = 0 '
      'AND status IN ($allowedStatusPlaceholders)',
      [
        terminal ? 'failed' : retryableParentStatus,
        messageId,
        ...parentAllowedStatuses,
      ],
    );
    if (parentCount != 1) {
      throw StateError('Upload retry parent qualification changed');
    }

    return UploadRetryProjectionResult(
      state: terminal
          ? UploadRetryProjectionState.terminal
          : UploadRetryProjectionState.retryPending,
      uploadRetryCount: projectedCount,
    );
  });
}

/// Atomically rearms a fully-qualified direct manual media retry.
Future<bool> dbRearmDirectUploadRetryForManualRetry(
  Database db, {
  required String messageId,
  required List<ManualUploadRetryAttachmentExpectation> attachments,
}) {
  return _dbRearmUploadRetryForManualRetry(
    db,
    parentTable: 'messages',
    retryableParentStatus: 'sending',
    ownerLane: MediaOwnerLane.direct,
    messageId: messageId,
    attachments: attachments,
  );
}

/// Atomically rearms a fully-qualified group manual media retry.
Future<bool> dbRearmGroupUploadRetryForManualRetry(
  Database db, {
  required String messageId,
  required List<ManualUploadRetryAttachmentExpectation> attachments,
}) {
  return _dbRearmUploadRetryForManualRetry(
    db,
    parentTable: 'group_messages',
    retryableParentStatus: 'queued_offline',
    ownerLane: MediaOwnerLane.group,
    messageId: messageId,
    attachments: attachments,
  );
}

Future<bool> _dbRearmUploadRetryForManualRetry(
  Database db, {
  required String parentTable,
  required String retryableParentStatus,
  required MediaOwnerLane ownerLane,
  required String messageId,
  required List<ManualUploadRetryAttachmentExpectation> attachments,
}) {
  final expectedIds = attachments
      .map((attachment) => attachment.attachmentId)
      .toSet();
  if (attachments.isEmpty || expectedIds.length != attachments.length) {
    return Future<bool>.value(false);
  }

  return dbWriteTransaction(db, (txn) async {
    final parentRows = await txn.rawQuery(
      'SELECT status, is_incoming FROM $parentTable WHERE id = ? LIMIT 1',
      [messageId],
    );
    if (parentRows.isEmpty ||
        parentRows.single['status'] != 'failed' ||
        ((parentRows.single['is_incoming'] as num?)?.toInt() ?? 0) != 0) {
      return false;
    }

    final rows = await txn.rawQuery(
      'SELECT id, local_path, download_status, upload_retry_count '
      'FROM media_attachments WHERE message_id = ? AND owner_lane = ?',
      [messageId, ownerLane.dbValue],
    );
    final unfinishedRows = rows
        .where((row) => row['download_status'] != 'done')
        .toList(growable: false);
    if (unfinishedRows.length != attachments.length ||
        unfinishedRows.any((row) => !expectedIds.contains(row['id']))) {
      return false;
    }

    final rowsById = <String, Map<String, Object?>>{
      for (final row in unfinishedRows) row['id']! as String: row,
    };
    for (final expected in attachments) {
      final row = rowsById[expected.attachmentId];
      if (row == null) return false;
      final currentCount = (row['upload_retry_count'] as num?)?.toInt() ?? 0;
      if (row['local_path'] != expected.storedLocalPath ||
          row['download_status'] != expected.downloadStatus ||
          currentCount != expected.uploadRetryCount) {
        return false;
      }
      if (expected.downloadStatus == 'upload_pending') {
        continue;
      }
      if (expected.downloadStatus != 'upload_failed' ||
          currentCount < kMaxUploadRetries) {
        return false;
      }
    }

    final parentColumns = parentTable == 'group_messages'
        ? 'status = ?, wire_envelope = NULL, inbox_retry_payload = NULL, '
              'inbox_stored = 0, retry_attempt_count = 0, '
              'next_eligible_at = NULL'
        : 'status = ?, wire_envelope = NULL';
    final parentCount = await txn.rawUpdate(
      'UPDATE $parentTable SET $parentColumns WHERE id = ? '
      "AND COALESCE(is_incoming, 0) = 0 AND status = 'failed'",
      [retryableParentStatus, messageId],
    );
    if (parentCount != 1) {
      throw StateError('Manual upload retry parent qualification changed');
    }

    for (final expected in attachments) {
      if (expected.downloadStatus != 'upload_failed') continue;
      final count = await txn.rawUpdate(
        "UPDATE media_attachments SET download_status = 'upload_pending', "
        'upload_retry_count = 0 WHERE id = ? AND message_id = ? '
        'AND owner_lane = ? AND local_path = ? '
        "AND download_status = 'upload_failed' AND upload_retry_count = ?",
        [
          expected.attachmentId,
          messageId,
          ownerLane.dbValue,
          expected.storedLocalPath,
          expected.uploadRetryCount,
        ],
      );
      if (count != 1) {
        throw StateError(
          'Manual upload retry attachment qualification changed',
        );
      }
    }
    return true;
  });
}

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
      await _applyMediaAttachmentPreservingSave(txn, row, id);
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

/// Atomic final save for an incoming direct private attachment. The parent
/// clock/expiry check and preserving attachment write share one transaction;
/// a terminal/hidden/wrong parent produces zero row mutation.
Future<bool> dbSaveDirectPrivateMediaAttachmentGuarded(
  Database db,
  Map<String, Object?> row, {
  required String messageId,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    final parentEligible =
        await dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
          txn,
          messageId,
          nowMs: nowMs,
        );
    if (!parentEligible ||
        row['message_id'] != messageId ||
        row['owner_lane'] != MediaOwnerLane.direct.dbValue) {
      return false;
    }
    await _applyMediaAttachmentPreservingSave(
      txn,
      row,
      row['id'] as String? ?? '',
      preserveDurableMimeIdentity: true,
    );
    return true;
  });
}

/// Parent-qualified claim for a direct-private transfer. The parent clock and
/// attachment claim are evaluated atomically; a terminal/hidden/expired parent
/// cannot leave its row in `downloading`.
Future<int> dbBeginDirectPrivateMediaDownloadIfEligible(
  Database db, {
  required String messageId,
  required String attachmentId,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    final parentEligible =
        await dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
          txn,
          messageId,
          nowMs: nowMs,
        );
    if (!parentEligible) return 0;
    // `downloading` is deliberately not reclaimable without a durable transfer
    // token. Two concurrent discriminator/nonces must not both own the row.
    final statuses = <String>[
      kMediaDownloadStatusPending,
      kMediaDownloadStatusFailed,
      kMediaDownloadStatusDownloadFailed,
      kMediaDownloadStatusEvicted,
    ];
    final placeholders = List.filled(statuses.length, '?').join(', ');
    return txn.rawUpdate(
      'UPDATE media_attachments SET download_status = ? '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND download_status IN ($placeholders)',
      [
        kMediaDownloadStatusDownloading,
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
        ...statuses,
      ],
    );
  });
}

/// Fresh direct-private local-ready qualification under the shared attachment
/// lock. This never repairs a status or inserts a row.
Future<int> dbQualifyDirectPrivateMediaLocalReadyIfEligible(
  Database db, {
  required String messageId,
  required String attachmentId,
  required String expectedLocalPath,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    final parentEligible =
        await dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
          txn,
          messageId,
          nowMs: nowMs,
        );
    if (!parentEligible) return 0;
    final rows = await txn.rawQuery(
      'SELECT 1 FROM media_attachments WHERE id = ? AND message_id = ? '
      'AND owner_lane = ? AND download_status = ? AND local_path = ? LIMIT 1',
      [
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
        kMediaDownloadStatusDone,
        expectedLocalPath,
      ],
    );
    return rows.isEmpty ? 0 : 1;
  });
}

/// Fresh parent + exact transfer-claim qualification used immediately before
/// direct-private promotion. It runs under the caller's attachment lock and
/// performs no attachment mutation.
Future<int> dbQualifyDirectPrivateMediaDownloadClaimIfEligible(
  Database db, {
  required String messageId,
  required String attachmentId,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    final parentEligible =
        await dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
          txn,
          messageId,
          nowMs: nowMs,
        );
    if (!parentEligible) return 0;
    final rows = await txn.rawQuery(
      'SELECT 1 FROM media_attachments WHERE id = ? AND message_id = ? '
      'AND owner_lane = ? AND download_status = ? LIMIT 1',
      [
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
        kMediaDownloadStatusDownloading,
      ],
    );
    return rows.isEmpty ? 0 : 1;
  });
}

/// Exact UPDATE-only failure transition for a direct-private download. It
/// cannot reinsert metadata/key state after lifecycle cleanup wins.
Future<int> dbRecordDirectPrivateMediaDownloadFailureIfEligible(
  Database db, {
  required String messageId,
  required String attachmentId,
  required int nowMs,
  required bool incrementRetryCount,
  required String failureStatus,
  required String expectedDownloadStatus,
  String? expectedLocalPath,
  bool clearLocalPath = false,
}) {
  const allowedStatuses = {
    kMediaDownloadStatusFailed,
    kMediaDownloadStatusDownloadFailed,
    kMediaDownloadStatusIntegrityFailed,
  };
  if (!allowedStatuses.contains(failureStatus)) {
    throw ArgumentError.value(failureStatus, 'failureStatus');
  }
  return dbWriteTransaction(db, (txn) async {
    final parentEligible =
        await dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
          txn,
          messageId,
          nowMs: nowMs,
        );
    if (!parentEligible) return 0;
    return txn.rawUpdate(
      'UPDATE media_attachments SET '
      'download_status = CASE WHEN ? = 1 THEN '
      'CASE WHEN COALESCE(download_retry_count, 0) + 1 >= ? THEN ? ELSE ? END '
      'ELSE ? END, '
      'download_retry_count = CASE WHEN ? = 1 '
      'THEN COALESCE(download_retry_count, 0) + 1 '
      'ELSE download_retry_count END, '
      'local_path = CASE WHEN ? = 1 THEN NULL ELSE local_path END '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND download_status = ? '
      'AND (? = 0 OR local_path = ?)',
      [
        incrementRetryCount ? 1 : 0,
        kMaxDownloadRetries,
        kMediaDownloadStatusDownloadFailed,
        kMediaDownloadStatusFailed,
        failureStatus,
        incrementRetryCount ? 1 : 0,
        clearLocalPath ? 1 : 0,
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
        expectedDownloadStatus,
        expectedLocalPath == null ? 0 : 1,
        expectedLocalPath,
      ],
    );
  });
}

Future<int> dbBeginGroupPrivateMediaDownloadIfEligible(
  Database db, {
  required String groupId,
  required String messageId,
  required String attachmentId,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    if (!await dbAdvanceAndQualifyGroupPrivateMediaParent(
      txn,
      messageId,
      groupId: groupId,
      nowMs: nowMs,
    )) {
      return 0;
    }
    const statuses = <String>[
      kMediaDownloadStatusPending,
      kMediaDownloadStatusFailed,
      kMediaDownloadStatusDownloadFailed,
      kMediaDownloadStatusEvicted,
    ];
    final placeholders = List.filled(statuses.length, '?').join(', ');
    return txn.rawUpdate(
      'UPDATE media_attachments SET download_status = ? '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND download_status IN ($placeholders)',
      [
        kMediaDownloadStatusDownloading,
        attachmentId,
        messageId,
        MediaOwnerLane.group.dbValue,
        ...statuses,
      ],
    );
  });
}

Future<int> dbQualifyGroupPrivateMediaLocalReadyIfEligible(
  Database db, {
  required String groupId,
  required String messageId,
  required String attachmentId,
  required String expectedLocalPath,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    if (!await dbAdvanceAndQualifyGroupPrivateMediaParent(
      txn,
      messageId,
      groupId: groupId,
      nowMs: nowMs,
    )) {
      return 0;
    }
    final rows = await txn.rawQuery(
      'SELECT 1 FROM media_attachments WHERE id = ? AND message_id = ? '
      'AND owner_lane = ? AND download_status = ? AND local_path = ? LIMIT 1',
      [
        attachmentId,
        messageId,
        MediaOwnerLane.group.dbValue,
        kMediaDownloadStatusDone,
        expectedLocalPath,
      ],
    );
    return rows.isEmpty ? 0 : 1;
  });
}

Future<int> dbQualifyGroupPrivateMediaDownloadClaimIfEligible(
  Database db, {
  required String groupId,
  required String messageId,
  required String attachmentId,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    if (!await dbAdvanceAndQualifyGroupPrivateMediaParent(
      txn,
      messageId,
      groupId: groupId,
      nowMs: nowMs,
    )) {
      return 0;
    }
    final rows = await txn.rawQuery(
      'SELECT 1 FROM media_attachments WHERE id = ? AND message_id = ? '
      'AND owner_lane = ? AND download_status = ? LIMIT 1',
      [
        attachmentId,
        messageId,
        MediaOwnerLane.group.dbValue,
        kMediaDownloadStatusDownloading,
      ],
    );
    return rows.isEmpty ? 0 : 1;
  });
}

Future<int> dbRecordGroupPrivateMediaDownloadFailureIfEligible(
  Database db, {
  required String groupId,
  required String messageId,
  required String attachmentId,
  required int nowMs,
  required bool incrementRetryCount,
  required String failureStatus,
  required String expectedDownloadStatus,
  String? expectedLocalPath,
  bool clearLocalPath = false,
}) {
  const allowedStatuses = {
    kMediaDownloadStatusFailed,
    kMediaDownloadStatusDownloadFailed,
    kMediaDownloadStatusIntegrityFailed,
  };
  if (!allowedStatuses.contains(failureStatus)) {
    throw ArgumentError.value(failureStatus, 'failureStatus');
  }
  return dbWriteTransaction(db, (txn) async {
    if (!await dbAdvanceAndQualifyGroupPrivateMediaParent(
      txn,
      messageId,
      groupId: groupId,
      nowMs: nowMs,
    )) {
      return 0;
    }
    return txn.rawUpdate(
      'UPDATE media_attachments SET '
      'download_status = CASE WHEN ? = 1 THEN '
      'CASE WHEN COALESCE(download_retry_count, 0) + 1 >= ? THEN ? ELSE ? END '
      'ELSE ? END, '
      'download_retry_count = CASE WHEN ? = 1 '
      'THEN COALESCE(download_retry_count, 0) + 1 '
      'ELSE download_retry_count END, '
      'local_path = CASE WHEN ? = 1 THEN NULL ELSE local_path END '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND download_status = ? AND (? = 0 OR local_path = ?)',
      [
        incrementRetryCount ? 1 : 0,
        kMaxDownloadRetries,
        kMediaDownloadStatusDownloadFailed,
        kMediaDownloadStatusFailed,
        failureStatus,
        incrementRetryCount ? 1 : 0,
        clearLocalPath ? 1 : 0,
        attachmentId,
        messageId,
        MediaOwnerLane.group.dbValue,
        expectedDownloadStatus,
        expectedLocalPath == null ? 0 : 1,
        expectedLocalPath,
      ],
    );
  });
}

Future<int> dbCommitGroupPrivateMediaDownloadIfEligible(
  Database db, {
  required String groupId,
  required String messageId,
  required String attachmentId,
  required String localPath,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    final identity = await txn.rawQuery(
      'SELECT parent.group_id AS group_id, attachment.mime AS mime '
      'FROM media_attachments attachment '
      'JOIN group_messages parent ON parent.id = attachment.message_id '
      'WHERE attachment.id = ? AND attachment.message_id = ? '
      "AND attachment.owner_lane = 'group' LIMIT 1",
      [attachmentId, messageId],
    );
    if (identity.isEmpty || identity.single['group_id'] != groupId) return 0;
    final expectedLocalPath = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: groupId,
      blobId: attachmentId,
      mime: identity.single['mime'] as String,
    );
    if (localPath != expectedLocalPath ||
        !await dbAdvanceAndQualifyGroupPrivateMediaParent(
          txn,
          messageId,
          groupId: groupId,
          nowMs: nowMs,
        )) {
      return 0;
    }
    return txn.rawUpdate(
      'UPDATE media_attachments SET local_path = ?, download_status = ?, '
      'download_retry_count = 0 '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND download_status = ?',
      [
        localPath,
        kMediaDownloadStatusDone,
        attachmentId,
        messageId,
        MediaOwnerLane.group.dbValue,
        kMediaDownloadStatusDownloading,
      ],
    );
  });
}

/// The shared preserving-save merge body. MUST run inside a
/// [dbWriteTransaction]; both the plain and the 235 group-guarded save reuse
/// this exact logic so their preservation semantics can never drift.
Future<void> _applyMediaAttachmentPreservingSave(
  DatabaseExecutor txn,
  Map<String, Object?> row,
  String id, {
  bool preserveDurableMimeIdentity = false,
}) async {
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
  // MIME/media type become path identity only after a durable copy exists, or
  // when a DB-qualified private parent invokes the guarded save. Ordinary
  // pending/failed direct replays must still be able to correct descriptors.
  final existingHasDurablePath =
      mediaLocalPathHasValue(existing['local_path'] as String?) &&
      const {
        kMediaDownloadStatusDone,
        kMediaDownloadStatusEvicted,
      }.contains(existing['download_status']);
  if (preserveDurableMimeIdentity || existingHasDurablePath) {
    merged['mime'] = existing['mime'];
    merged['media_type'] = existing['media_type'];
  }
  // 229: a user-evicted local copy survives ordinary replay (wire rows
  // decode as `pending` with no path — they must not re-arm a transfer
  // or resurrect a path). Only an explicit local retry, which writes
  // `downloading`, may leave the evicted state through this save path;
  // the conditional download commit is the only path back to `done`.
  if (existing['download_status'] == kMediaDownloadStatusEvicted &&
      merged['download_status'] != kMediaDownloadStatusDownloading) {
    merged['download_status'] = kMediaDownloadStatusEvicted;
    merged['local_path'] = existing['local_path'];
  }
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
}

/// 235: guarded final write for INCOMING group media.
///
/// Same preserving-save semantics as [dbSaveMediaAttachmentPreservingLocalState]
/// but, in the SAME transaction as the attachment-row write, it verifies:
///  - a live exact `(group_id, message_id)` parent row exists (a same-ID
///    parent silently rejected by the migration-069 tombstone — or one that
///    belongs to another group — must not acquire attachments), and
///  - no `group_media_deletion_journal` row reserves the attachment ID (an
///    active deletion operation blocks re-save/re-parent).
///
/// Returns true when the row was written; false when the guard refused (no
/// side effect at all — the caller must also skip secure-key writes).
Future<bool> dbSaveGroupMediaAttachmentGuarded(
  Database db,
  Map<String, Object?> row, {
  required String groupId,
}) async {
  final id = row['id'] as String? ?? '';
  final messageId = row['message_id'] as String? ?? '';

  try {
    final saved = await dbWriteTransaction(db, (txn) async {
      final parentRows = await txn.rawQuery(
        'SELECT 1 FROM group_messages WHERE id = ? AND group_id = ? AND ('
        '(media_policy_version = 0 AND media_lifecycle = ? '
        'AND media_duration_seconds IS NULL AND media_protected = 0 '
        'AND media_received_at IS NULL AND media_expires_at IS NULL '
        'AND media_last_checked_at IS NULL AND media_consumed_at IS NULL '
        'AND media_expired_at IS NULL AND media_cleanup_pending = 0) OR '
        '(media_policy_version = 1 AND media_protected = 1 '
        "AND media_lifecycle IN ('standard','view_once','disappearing') "
        'AND media_consumed_at IS NULL AND media_expired_at IS NULL '
        'AND media_cleanup_pending = 0 '
        "AND (media_lifecycle != 'disappearing' OR ("
        'media_expires_at IS NOT NULL AND media_last_checked_at IS NOT NULL '
        'AND media_last_checked_at < media_expires_at)))) LIMIT 1',
        [messageId, groupId, 'standard'],
      );
      if (parentRows.isEmpty) {
        return false;
      }
      final journalRows = await txn.query(
        'group_media_deletion_journal',
        columns: ['attachment_id'],
        where: 'attachment_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (journalRows.isNotEmpty) {
        return false;
      }
      await _applyMediaAttachmentPreservingSave(txn, row, id);
      return true;
    });
    emitFlowEvent(
      layer: 'DB',
      event: saved
          ? 'MEDIA_DB_GROUP_GUARDED_SAVE_SUCCESS'
          : 'MEDIA_DB_GROUP_GUARDED_SAVE_REFUSED',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
    return saved;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_GROUP_GUARDED_SAVE_ERROR',
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

/// 229: source states a download may conditionally claim into `downloading`.
/// `done` is deliberately absent (a completed row is adopted, never
/// re-transferred) and `evicted` is reachable only through the explicit
/// user-retry paths — every automatic entry point filters evicted rows out
/// before the use case runs.
const Set<String> kMediaDownloadClaimableStatuses = {
  kMediaDownloadStatusPending,
  kMediaDownloadStatusDownloading,
  kMediaDownloadStatusFailed,
  kMediaDownloadStatusDownloadFailed,
  kMediaDownloadStatusEvicted,
};

/// 229: owner-aware CAS claim into `downloading`. Affects the row only when
/// it is addressed under its exact owner lane AND currently claimable.
/// Returns the affected row count — 0 is a lost/disallowed claim, never
/// success.
Future<int> dbBeginMediaDownload(
  Database db,
  String id, {
  required String ownerLane,
}) async {
  final statuses = kMediaDownloadClaimableStatuses.toList();
  final placeholders = List.filled(statuses.length, '?').join(', ');
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET download_status = ? '
    'WHERE id = ? AND owner_lane = ? AND download_status IN ($placeholders)',
    [kMediaDownloadStatusDownloading, id, ownerLane, ...statuses],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_DOWNLOAD_CLAIM',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'ownerLane': ownerLane,
      'affected': affected,
    },
  );
  return affected;
}

/// 229: owner-aware CAS commit of the canonical relative path. Commits
/// `done` (and resets the retry budget, INV-DL-2) ONLY from this download's
/// own `downloading` claim — a claim lost to a concurrent state change (e.g.
/// an eviction) affects zero rows and the caller must fail closed.
Future<int> dbCommitMediaDownloadLocalPath(
  Database db,
  String id, {
  required String ownerLane,
  required String localPath,
}) async {
  // 235: a GROUP commit anti-joins active deletion-journal rows so a download
  // that lost to Delete-for-me can never promote/restore a local path. The
  // direct lane keeps the pre-235 statement byte-identical (its journal is a
  // different plan's contract).
  final journalAntiJoin = ownerLane == 'group'
      ? 'AND NOT EXISTS (SELECT 1 FROM group_media_deletion_journal j '
            'WHERE j.attachment_id = media_attachments.id) '
      : '';
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET local_path = ?, download_status = ?, '
    'download_retry_count = 0 '
    'WHERE id = ? AND owner_lane = ? AND download_status = ? $journalAntiJoin',
    [
      localPath,
      kMediaDownloadStatusDone,
      id,
      ownerLane,
      kMediaDownloadStatusDownloading,
    ],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_DOWNLOAD_COMMIT',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'ownerLane': ownerLane,
      'affected': affected,
    },
  );
  return affected;
}

/// 229: owner-aware CAS eviction claim. Flips the exact
/// `(id, owner, localPath, done)` row to `evicted` while RETAINING the
/// stored path (deletion happens after the durable claim; the path is
/// nulled only by [dbFinalizeMediaEvictedPathCleared]). Returns the affected
/// row count — 0 means the row changed underneath the caller (busy download,
/// path repair, another eviction) and nothing may be deleted.
Future<int> dbClaimMediaEvicted(
  Database db,
  String id, {
  required String ownerLane,
  required String expectedLocalPath,
}) async {
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET download_status = ? '
    'WHERE id = ? AND owner_lane = ? AND local_path = ? '
    'AND download_status = ?',
    [
      kMediaDownloadStatusEvicted,
      id,
      ownerLane,
      expectedLocalPath,
      kMediaDownloadStatusDone,
    ],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_EVICTED_CLAIM',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'ownerLane': ownerLane,
      'affected': affected,
    },
  );
  return affected;
}

/// 229: clears the stored path of a row that is still `evicted` under its
/// exact owner (the post-deletion finalize, or the fresh-manager
/// reconciliation of a cleanup-pending row whose file is proven absent).
Future<int> dbFinalizeMediaEvictedPathCleared(
  Database db,
  String id, {
  required String ownerLane,
}) async {
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET local_path = NULL '
    'WHERE id = ? AND owner_lane = ? AND download_status = ?',
    [id, ownerLane, kMediaDownloadStatusEvicted],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_EVICTED_PATH_CLEARED',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'ownerLane': ownerLane,
      'affected': affected,
    },
  );
  return affected;
}

const _directPrivateMediaCleanupAuthorityPredicate =
    'EXISTS ('
    'SELECT 1 FROM messages parent '
    'WHERE parent.id = ? '
    'AND parent.id = media_attachments.message_id '
    'AND parent.private_media_policy_version IS NOT NULL '
    'AND parent.private_media_policy_version > 0 '
    "AND parent.private_media_mode IN "
    "('protected','view_once','disappearing','unsupported') "
    'AND ('
    'parent.hidden_at IS NOT NULL OR parent.deleted_at IS NOT NULL OR '
    "parent.private_media_state IN ('consumed','expired','unsupported')"
    '))';

/// Exact DB-backed authorization for private file/key/row cleanup. Knowing an
/// attachment ID alone must never authorize active or cross-lane key removal.
Future<bool> dbCanCleanupDirectPrivateMediaAttachmentExact(
  Database db, {
  required String messageId,
  required String attachmentId,
}) async {
  final rows = await db.rawQuery(
    'SELECT 1 FROM media_attachments '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND $_directPrivateMediaCleanupAuthorityPredicate '
    'LIMIT 1',
    [attachmentId, messageId, 'direct', messageId],
  );
  return rows.isNotEmpty;
}

/// Exact direct-owned attachment-row finalize used only after durable private
/// terminal authority and successful file/key cleanup.
///
/// The terminal/hidden parent predicate is intentionally repeated here rather
/// than trusting an earlier application-layer read. This method is exposed as
/// a narrow repository capability, so a direct caller must not be able to
/// remove an attachment from an active private message by bypassing the
/// lifecycle adapter.
Future<int> dbDeleteDirectPrivateMediaAttachmentExact(
  Database db, {
  required String messageId,
  required String attachmentId,
}) {
  return db.rawDelete(
    'DELETE FROM media_attachments '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND $_directPrivateMediaCleanupAuthorityPredicate',
    [attachmentId, messageId, 'direct', messageId],
  );
}

const _groupPrivateMediaCleanupAuthorityPredicate =
    'EXISTS ('
    'SELECT 1 FROM group_messages parent '
    'WHERE parent.id = ? AND parent.id = media_attachments.message_id '
    'AND parent.media_policy_version > 0 '
    'AND (parent.media_consumed_at IS NOT NULL '
    'OR parent.media_expired_at IS NOT NULL '
    "OR parent.media_lifecycle = 'unsupported') "
    'AND parent.media_cleanup_pending = 1)';

Future<bool> dbCanCleanupGroupPrivateMediaAttachmentExact(
  Database db, {
  required String messageId,
  required String attachmentId,
}) async {
  final rows = await db.rawQuery(
    'SELECT 1 FROM media_attachments '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND $_groupPrivateMediaCleanupAuthorityPredicate LIMIT 1',
    [attachmentId, messageId, MediaOwnerLane.group.dbValue, messageId],
  );
  return rows.isNotEmpty;
}

Future<int> dbDeleteGroupPrivateMediaAttachmentExact(
  Database db, {
  required String messageId,
  required String attachmentId,
}) {
  return db.rawDelete(
    'DELETE FROM media_attachments '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND $_groupPrivateMediaCleanupAuthorityPredicate',
    [attachmentId, messageId, MediaOwnerLane.group.dbValue, messageId],
  );
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

/// Atomically updates one exact direct bookmark only while its current parent
/// remains live, visible, and canonically ordinary.
///
/// A legitimate privacy/terminal/deletion race returns false with zero write;
/// the generic ID-only writer remains unchanged for group/announcement use.
Future<bool> dbSetDirectMediaBookmarkedIfOrdinary(
  Database db, {
  required String messageId,
  required String attachmentId,
  required bool bookmarked,
}) async {
  final changed = await db.rawUpdate(
    'UPDATE media_attachments SET is_bookmarked = ? '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    "AND media_type IN ('image', 'video') "
    'AND EXISTS (SELECT 1 FROM messages p '
    'WHERE p.id = media_attachments.message_id '
    'AND p.hidden_at IS NULL AND p.deleted_at IS NULL '
    'AND p.private_media_policy_version = 0 '
    "AND p.private_media_mode = 'ordinary' "
    'AND p.private_media_duration_seconds IS NULL '
    "AND p.private_media_state = 'none' "
    'AND p.private_media_received_at_ms IS NULL '
    'AND p.private_media_expires_at_ms IS NULL '
    'AND p.private_media_revealed_at_ms IS NULL '
    'AND p.private_media_terminal_at_ms IS NULL '
    'AND p.private_media_clock_high_water_ms IS NULL)',
    [bookmarked ? 1 : 0, attachmentId, messageId, 'direct'],
  );
  return changed == 1;
}

/// Atomically updates one exact group bookmark only while its current parent
/// remains live, visible, and canonically ordinary.
///
/// The exact group/message/attachment identity and owner lane are repeated in
/// SQL. A privacy transition, local deletion, missing row, or same-ID sibling
/// therefore returns false with zero mutation.
Future<bool> dbSetGroupMediaBookmarkedIfOrdinary(
  Database db, {
  required String groupId,
  required String messageId,
  required String attachmentId,
  required bool bookmarked,
}) async {
  final changed = await db.rawUpdate(
    'UPDATE media_attachments SET is_bookmarked = ? '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    "AND media_type IN ('image', 'video') "
    'AND EXISTS (SELECT 1 FROM group_messages p '
    'WHERE p.id = media_attachments.message_id '
    'AND p.id = ? AND p.group_id = ? '
    'AND p.media_policy_version = 0 '
    "AND p.media_lifecycle = 'standard' "
    'AND p.media_duration_seconds IS NULL '
    'AND p.media_protected = 0 '
    'AND p.media_received_at IS NULL '
    'AND p.media_expires_at IS NULL '
    'AND p.media_last_checked_at IS NULL '
    'AND p.media_consumed_at IS NULL '
    'AND p.media_expired_at IS NULL '
    'AND p.media_cleanup_pending = 0 '
    'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions t '
    'WHERE t.message_id = p.id AND t.group_id = p.group_id))',
    [bookmarked ? 1 : 0, attachmentId, messageId, 'group', messageId, groupId],
  );
  return changed == 1;
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
