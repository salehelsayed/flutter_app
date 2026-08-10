import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../constants/retry_constants.dart';
import '../../media/group_media_integrity_policy.dart';
import '../../media/direct_media_blob_custody.dart';
import '../../media/direct_media_custody_intent.dart';
import '../../media/direct_private_media_path_guard.dart';
import '../../media/media_file_path_convention.dart';
import '../../media/media_owner_lane.dart';
import '../../media/outgoing_direct_private_mutation_coordinator.dart';
import '../../media/private_media_policy.dart';
import '../../media/upload_media_outcome.dart';
import '../../media/upload_retry_projection.dart';
import '../../secure_storage/secret_storage_references.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import '../direct_inbox_event_envelope.dart';
import '../direct_media_blob_custody.dart';
import '../outgoing_transport_mutation.dart';
import 'direct_media_blob_custody_db_helpers.dart';
import 'direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'group_messages_db_helpers.dart';
import 'group_parent_write_guard.dart';
import 'direct_inbox_custody_outbox_db_helpers.dart';
import 'messages_db_helpers.dart';

enum DirectMediaBlobGenerationDbStageOutcome {
  applied,
  idempotent,
  refused;

  bool get authorizesStrictUpload =>
      this == DirectMediaBlobGenerationDbStageOutcome.applied ||
      this == DirectMediaBlobGenerationDbStageOutcome.idempotent;
}

final class DirectMediaBlobGenerationDbStageResult {
  const DirectMediaBlobGenerationDbStageResult({
    required this.outcome,
    this.attachmentRows = const <Map<String, Object?>>[],
    this.custodyRows = const <Map<String, Object?>>[],
  });

  const DirectMediaBlobGenerationDbStageResult.refused()
    : outcome = DirectMediaBlobGenerationDbStageOutcome.refused,
      attachmentRows = const <Map<String, Object?>>[],
      custodyRows = const <Map<String, Object?>>[];

  final DirectMediaBlobGenerationDbStageOutcome outcome;
  final List<Map<String, Object?>> attachmentRows;
  final List<Map<String, Object?>> custodyRows;
}

enum _OutgoingPrivateParentMutationAuthority {
  ordinaryOrIncoming,
  available,
  activeLease,
  terminal,
  refused,
}

_OutgoingPrivateParentMutationAuthority
_classifyOutgoingPrivateParentMutationAuthority(Map<String, Object?> parent) {
  final incoming = ((parent['is_incoming'] as num?)?.toInt() ?? 0) != 0;
  if (incoming) {
    return _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming;
  }
  final version = (parent['private_media_policy_version'] as num?)?.toInt();
  final mode = parent['private_media_mode'] as String?;
  final legacyOrdinary = version == null && mode == null;
  final ordinary = version == 0 && (mode == null || mode == 'ordinary');
  // Sender one-more-look authority is intentionally limited to protected and
  // view-once. Existing outgoing disappearing media keeps its established
  // generic upload persistence/retry behavior; it must never inherit the
  // sender-open CAS merely because it is also policy version 1.
  final existingDisappearing = version == 1 && mode == 'disappearing';
  if (legacyOrdinary || ordinary || existingDisappearing) {
    return _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming;
  }
  if (version != 1 || (mode != 'protected' && mode != 'view_once')) {
    return _OutgoingPrivateParentMutationAuthority.refused;
  }
  if (parent['hidden_at'] != null || parent['deleted_at'] != null) {
    return _OutgoingPrivateParentMutationAuthority.terminal;
  }
  final state = parent['private_media_state'] as String?;
  final terminalAt = parent['private_media_terminal_at_ms'];
  if ((state == 'opening' || state == 'viewing') && terminalAt == null) {
    return _OutgoingPrivateParentMutationAuthority.activeLease;
  }
  if (state == 'available' &&
      parent['private_media_revealed_at_ms'] == null &&
      terminalAt == null) {
    return _OutgoingPrivateParentMutationAuthority.available;
  }
  return _OutgoingPrivateParentMutationAuthority.terminal;
}

String? _expectedPendingPathForMutation({
  required String messageId,
  required String attachmentId,
  required String mime,
}) {
  if (messageId.isEmpty || attachmentId.isEmpty || mime.isEmpty) return null;
  try {
    return MediaFilePathConvention.relativePathForPendingUpload(
      messageId: messageId,
      attachmentId: attachmentId,
      mime: mime,
    );
  } catch (_) {
    return null;
  }
}

bool _hasExactOutgoingPrivatePendingIdentity(
  Map<String, Object?> row, {
  required String messageId,
}) {
  final attachmentId = row['id'] as String? ?? '';
  final mime = row['mime'] as String? ?? '';
  final expected = _expectedPendingPathForMutation(
    messageId: messageId,
    attachmentId: attachmentId,
    mime: mime,
  );
  return expected != null &&
      row['message_id'] == messageId &&
      row['owner_lane'] == MediaOwnerLane.direct.dbValue &&
      row['local_path'] == expected &&
      ((row['size'] as num?)?.toInt() ?? 0) > 0;
}

bool _isExactOutgoingPrivatePendingMutationRow(
  Map<String, Object?> row, {
  required String messageId,
}) =>
    _hasExactOutgoingPrivatePendingIdentity(row, messageId: messageId) &&
    row['download_status'] == kMediaDownloadStatusUploadPending;

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

const _groupUploadParentAuthorityFields = <String>[
  'id',
  'group_id',
  'sender_peer_id',
  'transport_peer_id',
  'sender_username',
  'text',
  'timestamp',
  'last_send_attempt_at',
  'quoted_message_id',
  'logical_delivery_id',
  'key_generation',
  'status',
  'is_incoming',
  'is_forwarded',
  'media_policy_version',
  'media_lifecycle',
  'media_duration_seconds',
  'media_protected',
  'media_received_at',
  'media_expires_at',
  'media_last_checked_at',
  'media_consumed_at',
  'media_expired_at',
  'media_cleanup_pending',
  'created_at',
  'wire_envelope',
  'inbox_stored',
  'inbox_retry_payload',
  'retry_attempt_count',
  'next_eligible_at',
];

const _groupUploadAttachmentAuthorityFields = <String>[
  'id',
  'message_id',
  'owner_lane',
  'mime',
  'size',
  'media_type',
  'width',
  'height',
  'duration_ms',
  'local_path',
  'download_status',
  'created_at',
  'waveform',
  'upload_retry_count',
  'download_retry_count',
  'content_hash',
  'thumbnail_hash',
  'encryption_key_base64',
  'encryption_nonce',
  'encryption_scheme',
];

bool _sameExactDatabaseFields(
  Map<String, Object?> current,
  Map<String, Object?> expected,
  Iterable<String> fields,
) {
  for (final field in fields) {
    final left = current[field];
    final right = expected[field];
    if (left is num && right is num) {
      if (left.toInt() != right.toInt()) return false;
      continue;
    }
    if (left != right) return false;
  }
  return true;
}

/// Commits one uploaded group attachment only while both its exact outgoing
/// parent and exact pending attachment still belong to the same live
/// membership window.
Future<bool> dbCompleteGroupUploadRetry(
  Database db, {
  required Map<String, Object?> expectedParent,
  required Map<String, Object?> expectedAttachment,
  required Map<String, Object?> completedAttachment,
}) {
  return dbWriteTransaction(db, (txn) async {
    final messageId = expectedParent['id'] as String? ?? '';
    final groupId = expectedParent['group_id'] as String? ?? '';
    final attachmentId = expectedAttachment['id'] as String? ?? '';
    final completedEncryptionKey =
        completedAttachment['encryption_key_base64'] as String?;
    if (messageId.isEmpty ||
        groupId.isEmpty ||
        attachmentId.isEmpty ||
        expectedAttachment['message_id'] != messageId ||
        expectedAttachment['owner_lane'] != MediaOwnerLane.group.dbValue ||
        expectedAttachment['download_status'] != 'upload_pending' ||
        completedAttachment['id'] != attachmentId ||
        completedAttachment['message_id'] != messageId ||
        completedAttachment['owner_lane'] != MediaOwnerLane.group.dbValue ||
        completedAttachment['download_status'] != 'done' ||
        (completedEncryptionKey != null &&
            completedEncryptionKey.isNotEmpty &&
            !isSecureStoreReference(completedEncryptionKey)) ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }

    final parentRows = await txn.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (parentRows.isEmpty ||
        !_sameExactDatabaseFields(
          parentRows.single,
          expectedParent,
          _groupUploadParentAuthorityFields,
        )) {
      return false;
    }

    final attachmentRows = await txn.query(
      'media_attachments',
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: [attachmentId, messageId, MediaOwnerLane.group.dbValue],
      limit: 1,
    );
    if (attachmentRows.isEmpty ||
        !_sameExactDatabaseFields(
          attachmentRows.single,
          expectedAttachment,
          _groupUploadAttachmentAuthorityFields,
        )) {
      return false;
    }

    const locallyOwnedCompletionFields = <String>{
      'created_at',
      'thumbnail_hash',
      'upload_retry_count',
      'download_retry_count',
    };
    final completedValues = <String, Object?>{
      for (final field in _groupUploadAttachmentAuthorityFields)
        if (field != 'id' && field != 'message_id' && field != 'owner_lane')
          field: locallyOwnedCompletionFields.contains(field)
              ? expectedAttachment[field]
              : completedAttachment[field],
    };
    final count = await txn.update(
      'media_attachments',
      completedValues,
      where:
          "id = ? AND message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
      whereArgs: [attachmentId, messageId, MediaOwnerLane.group.dbValue],
    );
    return count == 1;
  });
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
      'SELECT * FROM $parentTable WHERE id = ? LIMIT 1',
      [messageId],
    );
    if (parentRows.isEmpty) {
      return const UploadRetryProjectionResult.notApplied();
    }
    final parent = parentRows.single;
    if (ownerLane == MediaOwnerLane.group &&
        !await dbAllowsOrdinaryGroupWrite(
          txn,
          parent['group_id'] as String? ?? '',
        )) {
      return const UploadRetryProjectionResult.notApplied();
    }
    final parentStatus = parent['status'] as String?;
    final isIncoming = ((parent['is_incoming'] as num?)?.toInt() ?? 0) != 0;
    if (isIncoming || !parentAllowedStatuses.contains(parentStatus)) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final privateAuthority = ownerLane == MediaOwnerLane.direct
        ? _classifyOutgoingPrivateParentMutationAuthority(parent)
        : _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming;
    switch (privateAuthority) {
      case _OutgoingPrivateParentMutationAuthority.activeLease:
        return const UploadRetryProjectionResult.notAppliedActiveLease();
      case _OutgoingPrivateParentMutationAuthority.terminal:
        return const UploadRetryProjectionResult.notAppliedTerminal();
      case _OutgoingPrivateParentMutationAuthority.refused:
        return const UploadRetryProjectionResult.notApplied();
      case _OutgoingPrivateParentMutationAuthority.available:
      case _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming:
        break;
    }

    final attachmentRows = await txn.rawQuery(
      'SELECT * FROM media_attachments '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      "AND download_status = 'upload_pending' LIMIT 1",
      [attachmentId, messageId, ownerLane.dbValue],
    );
    if (attachmentRows.isEmpty) {
      return const UploadRetryProjectionResult.notApplied();
    }
    final existingAttachment = attachmentRows.single;
    if (privateAuthority == _OutgoingPrivateParentMutationAuthority.available &&
        !_isExactOutgoingPrivatePendingMutationRow(
          existingAttachment,
          messageId: messageId,
        )) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final currentCount =
        (existingAttachment['upload_retry_count'] as num?)?.toInt() ?? 0;
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

    final privateAttachmentPredicate =
        privateAuthority == _OutgoingPrivateParentMutationAuthority.available
        ? ' AND local_path = ? AND mime = ? AND size = ? '
              'AND EXISTS (SELECT 1 FROM messages private_parent '
              'WHERE private_parent.id = media_attachments.message_id '
              'AND private_parent.is_incoming = 0 '
              'AND private_parent.hidden_at IS NULL '
              'AND private_parent.deleted_at IS NULL '
              'AND private_parent.private_media_policy_version = 1 '
              "AND private_parent.private_media_mode IN ('protected','view_once') "
              "AND private_parent.private_media_state = 'available' "
              'AND private_parent.private_media_revealed_at_ms IS NULL '
              'AND private_parent.private_media_terminal_at_ms IS NULL)'
        : '';
    final attachmentCount = await txn.rawUpdate(
      'UPDATE media_attachments SET download_status = ?, '
      'upload_retry_count = ? WHERE id = ? AND message_id = ? '
      "AND owner_lane = ? AND download_status = 'upload_pending'"
      '$privateAttachmentPredicate',
      [
        attachmentStatus,
        projectedCount,
        attachmentId,
        messageId,
        ownerLane.dbValue,
        if (privateAuthority ==
            _OutgoingPrivateParentMutationAuthority.available) ...<Object?>[
          existingAttachment['local_path'],
          existingAttachment['mime'],
          existingAttachment['size'],
        ],
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
    final privateParentPredicate =
        privateAuthority == _OutgoingPrivateParentMutationAuthority.available
        ? ' AND hidden_at IS NULL AND deleted_at IS NULL '
              'AND private_media_policy_version = 1 '
              "AND private_media_mode IN ('protected','view_once') "
              "AND private_media_state = 'available' "
              'AND private_media_revealed_at_ms IS NULL '
              'AND private_media_terminal_at_ms IS NULL'
        : '';
    final parentCount = await txn.rawUpdate(
      'UPDATE $parentTable SET status = ? WHERE id = ? '
      'AND COALESCE(is_incoming, 0) = 0 '
      'AND status IN ($allowedStatusPlaceholders)$privateParentPredicate',
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
      'SELECT * FROM $parentTable WHERE id = ? LIMIT 1',
      [messageId],
    );
    if (parentRows.isEmpty ||
        parentRows.single['status'] != 'failed' ||
        ((parentRows.single['is_incoming'] as num?)?.toInt() ?? 0) != 0) {
      return false;
    }
    final privateAuthority = ownerLane == MediaOwnerLane.direct
        ? _classifyOutgoingPrivateParentMutationAuthority(parentRows.single)
        : _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming;
    final parent = parentRows.single;
    if (ownerLane == MediaOwnerLane.group &&
        !await dbAllowsOrdinaryGroupWrite(
          txn,
          parent['group_id'] as String? ?? '',
        )) {
      return false;
    }
    final rawEnvelope = parent['wire_envelope'];
    final envelopeMissing =
        rawEnvelope == null ||
        rawEnvelope == '' ||
        (rawEnvelope is List<int> && rawEnvelope.isEmpty);
    final terminalTransportCustody =
        ownerLane == MediaOwnerLane.direct &&
        privateAuthority == _OutgoingPrivateParentMutationAuthority.terminal &&
        parent['hidden_at'] == null &&
        parent['deleted_at'] == null &&
        ((parent['private_media_policy_version'] as num?)?.toInt() == 1) &&
        (parent['private_media_mode'] == 'protected' ||
            parent['private_media_mode'] == 'view_once') &&
        parent['private_media_state'] == 'consumed' &&
        parent['private_media_terminal_at_ms'] != null &&
        envelopeMissing;
    if (privateAuthority !=
            _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming &&
        privateAuthority != _OutgoingPrivateParentMutationAuthority.available &&
        !terminalTransportCustody) {
      return false;
    }

    final requiresExactPrivatePending =
        privateAuthority == _OutgoingPrivateParentMutationAuthority.available ||
        terminalTransportCustody;
    final attachmentColumns = requiresExactPrivatePending
        ? 'id, message_id, owner_lane, mime, size, local_path, '
              'download_status, upload_retry_count'
        : 'id, local_path, download_status, upload_retry_count';
    final rows = await txn.rawQuery(
      'SELECT $attachmentColumns FROM media_attachments '
      'WHERE message_id = ? AND owner_lane = ?',
      [messageId, ownerLane.dbValue],
    );
    final unfinishedRows = rows
        .where((row) => row['download_status'] != 'done')
        .toList(growable: false);
    if (unfinishedRows.length != attachments.length ||
        unfinishedRows.any((row) => !expectedIds.contains(row['id']))) {
      return false;
    }
    if (requiresExactPrivatePending &&
        unfinishedRows.any(
          (row) => !_isExactOutgoingPrivatePendingMutationRow(<String, Object?>{
            ...row,
            // Rearm accepts terminal upload failures at the exact pending
            // identity; path authority is identical to upload_pending.
            'download_status': kMediaDownloadStatusUploadPending,
          }, messageId: messageId),
        )) {
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
    final privateParentPredicate = requiresExactPrivatePending
        ? terminalTransportCustody
              ? ' AND hidden_at IS NULL AND deleted_at IS NULL '
                    'AND private_media_policy_version = 1 '
                    "AND private_media_mode IN ('protected','view_once') "
                    "AND private_media_state = 'consumed' "
                    'AND private_media_terminal_at_ms IS NOT NULL '
                    'AND (wire_envelope IS NULL OR LENGTH(wire_envelope) = 0)'
              : ' AND hidden_at IS NULL AND deleted_at IS NULL '
                    'AND private_media_policy_version = 1 '
                    "AND private_media_mode IN ('protected','view_once') "
                    "AND private_media_state = 'available' "
                    'AND private_media_revealed_at_ms IS NULL '
                    'AND private_media_terminal_at_ms IS NULL'
        : '';
    final parentCount = await txn.rawUpdate(
      'UPDATE $parentTable SET $parentColumns WHERE id = ? '
      "AND COALESCE(is_incoming, 0) = 0 AND status = 'failed'"
      '$privateParentPredicate',
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

/// Internal-authority refusal surfaced by the final transactional generic-save
/// guard so repository callers can compensate a secure-key write and then
/// treat the stale custody loser as a successful no-op.
final class GenericMediaAttachmentCustodySaveRefused implements Exception {
  const GenericMediaAttachmentCustodySaveRefused();
}

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

/// Returns whether an unqualified whole-row attachment save may proceed.
///
/// A committed direct-media initial envelope owns its attachment projection
/// for as long as v108 custody exists. Once v108 retires, the exact complete
/// encrypted attachment itself remains monotonic; exact outgoing deletion
/// authority also prevents a user-removed row from being recreated. Callers
/// must run this check before preparing a secure-store key write; the
/// preserving SQL merge repeats the predicate in its transaction as the final
/// race guard.
Future<bool> dbCanApplyGenericMediaAttachmentSave(
  Database db,
  Map<String, Object?> row,
) => dbWriteTransaction(
  db,
  (txn) =>
      _canApplyGenericMediaAttachmentSave(txn, row, requireCustodySchema: true),
);

const _ordinaryOutgoingAttachmentAttemptColumns = <String>[
  'id',
  'message_id',
  'owner_lane',
  'mime',
  'size',
  'media_type',
  'width',
  'height',
  'duration_ms',
  'local_path',
  'download_status',
  'created_at',
  'waveform',
  'upload_retry_count',
  'download_retry_count',
  'content_hash',
  'thumbnail_hash',
  'encryption_key_base64',
  'encryption_nonce',
  'encryption_scheme',
];

/// Descriptor and ciphertext identity that becomes monotonic once a direct
/// attachment has a complete encrypted projection. Local lifecycle columns
/// (path, status, retry counters, bookmark, and playback) intentionally stay
/// outside this set so download repair and eviction can continue to converge.
const _immutableDirectMediaProjectionColumns = <String>[
  'mime',
  'size',
  'media_type',
  'width',
  'height',
  'duration_ms',
  'created_at',
  'waveform',
  'content_hash',
  'thumbnail_hash',
  'encryption_key_base64',
  'encryption_nonce',
  'encryption_scheme',
];

bool _sameOrdinaryOutgoingAttachmentAttempt(
  Map<String, Object?> current,
  Map<String, Object?> candidate,
) => _ordinaryOutgoingAttachmentAttemptColumns.every((column) {
  if (column == 'upload_retry_count' || column == 'download_retry_count') {
    final currentCount = (current[column] as num?)?.toInt() ?? 0;
    final candidateCount = (candidate[column] as num?)?.toInt() ?? 0;
    return currentCount == candidateCount;
  }
  return current[column] == candidate[column];
});

bool _isReplaceableLegacyOrdinaryUploadPlaceholder(
  Map<String, Object?> row, {
  required String messageId,
  required Set<String> candidateIds,
}) =>
    row['message_id'] == messageId &&
    row['owner_lane'] == MediaOwnerLane.direct.dbValue &&
    !candidateIds.contains(row['id']) &&
    row['download_status'] == kMediaDownloadStatusUploadPending &&
    ((row['size'] as num?)?.toInt() ?? -1) == 0 &&
    row['content_hash'] == null &&
    row['thumbnail_hash'] == null &&
    row['encryption_key_base64'] == null &&
    row['encryption_nonce'] == null &&
    row['encryption_scheme'] == null;

final class _OrdinaryOutgoingProjectionRefused implements Exception {
  const _OrdinaryOutgoingProjectionRefused();
}

/// Atomically stages one media-bearing ordinary outgoing attempt.
///
/// The parent/envelope CAS and the exact direct-owned attachment projection
/// share one SQLite transaction. Secure-key preparation and compensation stay
/// in [MediaAttachmentRepositoryImpl]; this helper accepts storage-reference
/// rows only and never crosses a bridge or secure store while the transaction
/// is open.
Future<OutgoingOrdinaryMutationOutcome> dbStageOutgoingOrdinaryAttemptWithMedia(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required List<Map<String, Object?>> attachmentRows,
  required OutgoingOrdinaryAttemptKind kind,
}) {
  final messageId = stagedRow['id'] as String? ?? '';
  final attachmentIds = attachmentRows
      .map((row) => row['id'] as String? ?? '')
      .toList(growable: false);
  final uniqueAttachmentIds = attachmentIds.toSet();
  final validShape =
      messageId.isNotEmpty &&
      expectedRow?['direct_media_custody_intent_id'] == null &&
      stagedRow['direct_media_custody_intent_id'] == null &&
      attachmentRows.isNotEmpty &&
      uniqueAttachmentIds.length == attachmentRows.length &&
      !uniqueAttachmentIds.contains('') &&
      kind != OutgoingOrdinaryAttemptKind.tombstoneInitial &&
      kind != OutgoingOrdinaryAttemptKind.tombstoneRetry &&
      attachmentRows.every(
        (row) =>
            row['message_id'] == messageId &&
            row['owner_lane'] == MediaOwnerLane.direct.dbValue,
      );
  if (!validShape) {
    return Future<OutgoingOrdinaryMutationOutcome>.value(
      OutgoingOrdinaryMutationOutcome.refused,
    );
  }

  return _stageOutgoingOrdinaryAttemptWithMediaTransaction(
    db,
    expectedRow: expectedRow,
    stagedRow: stagedRow,
    attachmentRows: attachmentRows,
    kind: kind,
    messageId: messageId,
    uniqueAttachmentIds: uniqueAttachmentIds,
  );
}

/// Storage result of the combined ordinary-media/v108 transaction.
///
/// Every authorizing result returns the exact immutable custody row selected
/// inside the transaction. The parent/media rows are the same transactional
/// snapshot, but may be absent or lifecycle-mutated when an idempotent loser
/// enters after settlement or physical deletion.
class DirectMediaInboxCustodyDbStageResult {
  const DirectMediaInboxCustodyDbStageResult({
    required this.outcome,
    required this.messageRow,
    required this.attachmentRows,
    required this.custodyRow,
    required this.hasExactMutableProjection,
  });

  const DirectMediaInboxCustodyDbStageResult.refused()
    : outcome = OutgoingOrdinaryMutationOutcome.refused,
      messageRow = null,
      attachmentRows = const <Map<String, Object?>>[],
      custodyRow = null,
      hasExactMutableProjection = false;

  final OutgoingOrdinaryMutationOutcome outcome;
  final Map<String, Object?>? messageRow;
  final List<Map<String, Object?>> attachmentRows;
  final Map<String, Object?>? custodyRow;

  /// Whether the returned parent and attachment rows still exactly describe
  /// the committed initial attempt.
  ///
  /// An idempotent result may legitimately be `false`: v108 is deliberately
  /// independent of the mutable message/media projection so settlement or
  /// physical deletion cannot revoke an already-committed envelope.
  final bool hasExactMutableProjection;
}

final class _DirectMediaInboxCustodyRollback implements Exception {
  const _DirectMediaInboxCustodyRollback();
}

final class _DirectMediaCustodyFailureRollback implements Exception {
  const _DirectMediaCustodyFailureRollback();
}

const String _directInboxCustodyOutboxTable = 'direct_inbox_custody_outbox';
const String _directMediaCustodyIntentColumn = 'direct_media_custody_intent_id';
const String _blobAesGcmV1 = 'blob_aes_256_gcm_v1';

/// Atomically records one upload failure only while the caller still owns the
/// exact manifest-bound preparation and no immutable v108 authority exists.
///
/// This is deliberately separate from [dbProjectDirectUploadFailure]. A
/// token-bearing preparation must requalify its complete parent/attachment
/// snapshot; a single-row legacy projection could otherwise mutate a crossed
/// or already-custodied attempt.
Future<UploadRetryProjectionResult>
dbProjectOutgoingDirectMediaCustodyUploadFailure(
  Database db, {
  required Map<String, Object?> expectedParentRow,
  required List<Map<String, Object?>> expectedAttachmentRows,
  required String failedAttachmentId,
  required UploadMediaDisposition disposition,
}) async {
  final messageId = expectedParentRow['id'] as String? ?? '';
  final recipientPeerId = expectedParentRow['contact_peer_id'] as String? ?? '';
  final intentId =
      expectedParentRow[_directMediaCustodyIntentColumn] as String?;
  final attachmentIds = expectedAttachmentRows
      .map((row) => row['id'] as String? ?? '')
      .toList(growable: false);
  final uniqueAttachmentIds = attachmentIds.toSet();
  final expectedFailedRows = expectedAttachmentRows
      .where((row) => row['id'] == failedAttachmentId)
      .toList(growable: false);
  final validExpectedShape =
      messageId.trim().isNotEmpty &&
      recipientPeerId.trim().isNotEmpty &&
      expectedAttachmentRows.isNotEmpty &&
      uniqueAttachmentIds.length == expectedAttachmentRows.length &&
      !uniqueAttachmentIds.contains('') &&
      _isExactLowercaseHex(intentId, 32) &&
      intentId ==
          computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: attachmentIds,
          ) &&
      _isEligiblePreparedDirectMediaCustodyParent(
        expectedParentRow,
        recipientPeerId: recipientPeerId,
        intentId: intentId!,
      ) &&
      expectedAttachmentRows.every(
        (row) => _isValidDirectMediaCustodyPreparationAttachment(
          row,
          messageId: messageId,
        ),
      ) &&
      expectedFailedRows.length == 1 &&
      expectedFailedRows.single['download_status'] ==
          kMediaDownloadStatusUploadPending;
  if (!validExpectedShape) {
    return const UploadRetryProjectionResult.notApplied();
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final currentParents = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      final currentAttachments = await txn.query(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      // Message identity is the global v108 exclusion key. Also reject an
      // impossible crossed incarnation elsewhere rather than letting failure
      // state make that collision look like an unowned preparation.
      final currentCustody = await txn.rawQuery(
        'SELECT 1 FROM $_directInboxCustodyOutboxTable '
        'WHERE message_id = ? OR incarnation_id = ? LIMIT 1',
        <Object?>[messageId, intentId],
      );
      if (currentCustody.isNotEmpty ||
          currentParents.length != 1 ||
          !_messageDatabaseProjectionMatches(
            currentParents.single,
            expectedParentRow,
          ) ||
          !_isEligiblePreparedDirectMediaCustodyParent(
            currentParents.single,
            recipientPeerId: recipientPeerId,
            intentId: intentId,
          ) ||
          !_exactDirectMediaCustodyFailureProjection(
            currentAttachments,
            expectedAttachmentRows,
          )) {
        return const UploadRetryProjectionResult.notApplied();
      }

      final failedRow = currentAttachments.singleWhere(
        (row) => row['id'] == failedAttachmentId,
      );
      final currentCount =
          (failedRow['upload_retry_count'] as num?)?.toInt() ?? 0;
      late final String projectedAttachmentStatus;
      late final int projectedRetryCount;
      switch (disposition) {
        case UploadMediaDisposition.connectivityRetryable:
          projectedAttachmentStatus = kMediaDownloadStatusUploadPending;
          projectedRetryCount = currentCount;
          break;
        case UploadMediaDisposition.boundedRetryable:
          final incremented = currentCount + 1;
          projectedRetryCount = incremented > kMaxUploadRetries
              ? kMaxUploadRetries
              : incremented;
          projectedAttachmentStatus = projectedRetryCount >= kMaxUploadRetries
              ? 'upload_failed'
              : kMediaDownloadStatusUploadPending;
          break;
        case UploadMediaDisposition.terminal:
          projectedAttachmentStatus = 'upload_failed';
          projectedRetryCount = currentCount;
          break;
      }

      final attachmentCount = await txn.rawUpdate(
        'UPDATE media_attachments SET download_status = ?, '
        'upload_retry_count = ? WHERE id = ? AND message_id = ? '
        'AND owner_lane = ? AND download_status = ? '
        'AND upload_retry_count = ?',
        <Object?>[
          projectedAttachmentStatus,
          projectedRetryCount,
          failedAttachmentId,
          messageId,
          MediaOwnerLane.direct.dbValue,
          kMediaDownloadStatusUploadPending,
          currentCount,
        ],
      );
      if (attachmentCount != 1) {
        throw const _DirectMediaCustodyFailureRollback();
      }

      final projectedParentStatus = projectedAttachmentStatus == 'upload_failed'
          ? 'failed'
          : 'sending';
      final parentCount = await txn.rawUpdate(
        'UPDATE messages SET status = ? WHERE id = ? '
        'AND contact_peer_id = ? AND status = ? '
        'AND direct_media_custody_intent_id = ? '
        'AND wire_envelope IS NULL AND transport IS NULL '
        'AND relay_expires_at IS NULL AND custody_checked_at IS NULL',
        <Object?>[
          projectedParentStatus,
          messageId,
          recipientPeerId,
          expectedParentRow['status'],
          intentId,
        ],
      );
      if (parentCount != 1) {
        throw const _DirectMediaCustodyFailureRollback();
      }

      final committedParents = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      final committedAttachments = await txn.query(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      final committedCustody = await txn.rawQuery(
        'SELECT 1 FROM $_directInboxCustodyOutboxTable '
        'WHERE message_id = ? OR incarnation_id = ? LIMIT 1',
        <Object?>[messageId, intentId],
      );
      final projectedParent = Map<String, Object?>.from(expectedParentRow)
        ..['status'] = projectedParentStatus;
      final projectedAttachments = expectedAttachmentRows
          .map(Map<String, Object?>.from)
          .toList(growable: false);
      final projectedFailed = projectedAttachments.singleWhere(
        (row) => row['id'] == failedAttachmentId,
      );
      projectedFailed['download_status'] = projectedAttachmentStatus;
      projectedFailed['upload_retry_count'] = projectedRetryCount;
      if (committedCustody.isNotEmpty ||
          committedParents.length != 1 ||
          !_messageDatabaseProjectionMatches(
            committedParents.single,
            projectedParent,
          ) ||
          !_exactDirectMediaCustodyFailureProjection(
            committedAttachments,
            projectedAttachments,
          )) {
        throw const _DirectMediaCustodyFailureRollback();
      }

      return UploadRetryProjectionResult(
        state: projectedAttachmentStatus == 'upload_failed'
            ? UploadRetryProjectionState.terminal
            : UploadRetryProjectionState.retryPending,
        uploadRetryCount: projectedRetryCount,
      );
    });
  } on _DirectMediaCustodyFailureRollback {
    return const UploadRetryProjectionResult.notApplied();
  }
}

/// Atomically publishes a canonical fresh ordinary-direct parent and its
/// complete v110/v111 media generation.
///
/// Unlike [dbStageOutgoingDirectMediaBlobGeneration], this entry requires the
/// parent and all attachment predecessors to be absent. An already-complete
/// exact winner is adopted idempotently; partial/crossed state is refused.
///
/// [authorizedForwardDedupKey] selects between the two canonical parent shapes
/// documented on [_isCanonicalFreshDirectMediaBlobParent]. It is never
/// persisted and never derived from the candidate parent.
Future<DirectMediaBlobGenerationDbStageResult>
dbStageFreshOutgoingDirectMediaBlobGeneration(
  Database db, {
  required Map<String, Object?> parentRow,
  required List<Map<String, Object?>> expectedAttachmentRows,
  required List<Map<String, Object?>> preparedAttachmentRows,
  required List<DirectMediaBlobCustodyRow> custodyRows,
  String? authorizedForwardDedupKey,
}) async {
  final messageId = parentRow['id'] as String? ?? '';
  final recipientPeerId = parentRow['contact_peer_id'] as String? ?? '';
  final attachmentIds = expectedAttachmentRows
      .map((row) => row['id'] as String? ?? '')
      .toList(growable: false);
  final expectedIds = attachmentIds.toSet();
  final expectedById = <String, Map<String, Object?>>{
    for (final row in expectedAttachmentRows)
      if (row['id'] is String) row['id']! as String: row,
  };
  final preparedById = <String, Map<String, Object?>>{
    for (final row in preparedAttachmentRows)
      if (row['id'] is String) row['id']! as String: row,
  };
  final custodyById = <String, DirectMediaBlobCustodyRow>{
    for (final row in custodyRows) row.attachmentId: row,
  };
  final intentId = parentRow[_directMediaCustodyIntentColumn] as String?;
  final validShape =
      messageId.trim().isNotEmpty &&
      recipientPeerId.trim().isNotEmpty &&
      attachmentIds.isNotEmpty &&
      expectedIds.length == attachmentIds.length &&
      !expectedIds.contains('') &&
      expectedById.length == expectedIds.length &&
      preparedById.length == expectedIds.length &&
      preparedById.keys.toSet().containsAll(expectedIds) &&
      custodyById.length == expectedIds.length &&
      custodyById.keys.toSet().containsAll(expectedIds) &&
      _isExactLowercaseHex(intentId, 32) &&
      intentId ==
          computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: attachmentIds,
          ) &&
      _isCanonicalFreshDirectMediaBlobParent(
        parentRow,
        recipientPeerId: recipientPeerId,
        intentId: intentId!,
        authorizedForwardDedupKey: authorizedForwardDedupKey,
      ) &&
      expectedAttachmentRows.every(
        (row) => _isValidDirectMediaCustodyPreparationAttachment(
          row,
          messageId: messageId,
        ),
      ) &&
      preparedAttachmentRows.every((candidate) {
        final attachmentId = candidate['id'] as String? ?? '';
        final expected = expectedById[attachmentId];
        final custody = custodyById[attachmentId];
        return expected != null &&
            custody != null &&
            _samePreparedDirectMediaIdentity(expected, candidate) &&
            candidate['local_path'] == expected['local_path'] &&
            candidate['download_status'] == kMediaDownloadStatusUploadPending &&
            hasImmutableDirectMediaCustodyAttachmentProjection(candidate) &&
            custody.messageId == messageId &&
            custody.direction == DirectMediaBlobCustodyDirection.outgoing &&
            custody.state == DirectMediaBlobCustodyState.outgoingPrepared &&
            custody.inboxCustodyIncarnationId == null &&
            custody.recipientPeerId == recipientPeerId &&
            custody.contentHash == candidate['content_hash'] &&
            custody.ciphertextSize > 0 &&
            custody.expiresAtMs == null &&
            custody.custodyRelayPeerId == null;
      });
  if (!validShape) {
    return const DirectMediaBlobGenerationDbStageResult.refused();
  }

  return dbWriteTransaction(db, (txn) async {
    final currentParents = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final currentAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'id ASC',
    );
    final currentCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    final placeholders = List.filled(attachmentIds.length, '?').join(',');
    final attachmentIdCollisions = await txn.rawQuery(
      'SELECT * FROM media_attachments WHERE id IN ($placeholders) '
      'ORDER BY id ASC',
      attachmentIds,
    );
    final custodyIdCollisions = await txn.rawQuery(
      'SELECT * FROM $kDirectMediaBlobCustodyTable '
      'WHERE attachment_id IN ($placeholders) ORDER BY attachment_id ASC',
      attachmentIds,
    );
    final v108 = await txn.query(
      _directInboxCustodyOutboxTable,
      columns: const <String>['message_id'],
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );

    if (currentCustody.isNotEmpty || custodyIdCollisions.isNotEmpty) {
      final winnerAttachments = <String, Map<String, Object?>>{
        for (final row in currentAttachments) row['id']! as String: row,
      };
      final winnerRows = <String, DirectMediaBlobCustodyRow>{};
      try {
        for (final raw in currentCustody) {
          final row = DirectMediaBlobCustodyRow.fromMap(raw);
          winnerRows[row.attachmentId] = row;
        }
      } on FormatException {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      final exactWinner =
          v108.isEmpty &&
          currentParents.length == 1 &&
          _messageDatabaseProjectionMatches(currentParents.single, parentRow) &&
          currentAttachments.length == expectedIds.length &&
          attachmentIdCollisions.length == expectedIds.length &&
          currentCustody.length == expectedIds.length &&
          custodyIdCollisions.length == expectedIds.length &&
          winnerAttachments.length == expectedIds.length &&
          winnerRows.length == expectedIds.length &&
          expectedIds.every((attachmentId) {
            final expected = expectedById[attachmentId];
            final attachment = winnerAttachments[attachmentId];
            final custody = winnerRows[attachmentId];
            final reopenable = custody == null
                ? false
                : switch (custody.state) {
                    DirectMediaBlobCustodyState.outgoingPrepared =>
                      custody.inboxCustodyIncarnationId == null &&
                          custody.expiresAtMs == null &&
                          custody.custodyRelayPeerId == null,
                    DirectMediaBlobCustodyState.outgoingStored =>
                      custody.inboxCustodyIncarnationId == null &&
                          custody.expiresAtMs != null &&
                          custody.expiresAtMs! > 0 &&
                          _isNonBlankDatabaseString(custody.custodyRelayPeerId),
                    _ => false,
                  };
            return expected != null &&
                attachment != null &&
                custody != null &&
                reopenable &&
                _samePreparedDirectMediaIdentity(expected, attachment) &&
                attachment['local_path'] == expected['local_path'] &&
                attachment['download_status'] ==
                    kMediaDownloadStatusUploadPending &&
                hasImmutableDirectMediaCustodyAttachmentProjection(
                  attachment,
                ) &&
                custody.messageId == messageId &&
                custody.direction == DirectMediaBlobCustodyDirection.outgoing &&
                custody.recipientPeerId == recipientPeerId &&
                custody.contentHash == attachment['content_hash'];
          });
      if (!exactWinner) {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      return DirectMediaBlobGenerationDbStageResult(
        outcome: DirectMediaBlobGenerationDbStageOutcome.idempotent,
        attachmentRows: currentAttachments
            .map(Map<String, Object?>.from)
            .toList(growable: false),
        custodyRows: currentCustody
            .map(Map<String, Object?>.from)
            .toList(growable: false),
      );
    }

    final exactAbsence =
        v108.isEmpty &&
        currentParents.isEmpty &&
        currentAttachments.isEmpty &&
        currentCustody.isEmpty &&
        attachmentIdCollisions.isEmpty &&
        custodyIdCollisions.isEmpty;
    if (!exactAbsence) {
      return const DirectMediaBlobGenerationDbStageResult.refused();
    }

    await txn.insert(
      'messages',
      parentRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    for (final candidate in preparedAttachmentRows) {
      await _applyMediaAttachmentPreservingSave(
        txn,
        candidate,
        candidate['id']! as String,
      );
    }
    for (final row in custodyRows) {
      await txn.insert(
        kDirectMediaBlobCustodyTable,
        row.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    final committedParents = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final committedAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'id ASC',
    );
    final committedCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    final committedRows = <String, DirectMediaBlobCustodyRow>{
      for (final raw in committedCustody)
        DirectMediaBlobCustodyRow.fromMap(raw).attachmentId:
            DirectMediaBlobCustodyRow.fromMap(raw),
    };
    final exactCommit =
        committedParents.length == 1 &&
        _messageDatabaseProjectionMatches(committedParents.single, parentRow) &&
        committedAttachments.length == preparedAttachmentRows.length &&
        committedCustody.length == custodyRows.length &&
        _exactDirectMediaCustodyFailureProjection(
          committedAttachments,
          preparedAttachmentRows,
        ) &&
        custodyRows.every((expected) {
          final committed = committedRows[expected.attachmentId];
          return committed != null &&
              committed.exactDatabaseProjectionMatches(expected);
        });
    if (!exactCommit) {
      throw StateError('fresh direct-media blob owner lost atomic projection');
    }
    return DirectMediaBlobGenerationDbStageResult(
      outcome: DirectMediaBlobGenerationDbStageOutcome.applied,
      attachmentRows: committedAttachments
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      custodyRows: committedCustody
          .map(Map<String, Object?>.from)
          .toList(growable: false),
    );
  });
}

/// Atomically acquires v108 initial-envelope custody for one newly authored
/// ordinary direct-media message.
///
/// Publishes the complete prepared direct-media ciphertext generation before
/// any LAN or relay request.
///
/// A concurrent complete winner is adopted idempotently. A partial generation,
/// pre-existing v108 authority, crossed Plan 345 intent/projection, or any
/// attachment/custody mismatch is refused without changing either table.
Future<DirectMediaBlobGenerationDbStageResult>
dbStageOutgoingDirectMediaBlobGeneration(
  Database db, {
  required Map<String, Object?> expectedParentRow,
  required List<Map<String, Object?>> expectedAttachmentRows,
  required List<Map<String, Object?>> preparedAttachmentRows,
  required List<DirectMediaBlobCustodyRow> custodyRows,
}) async {
  final messageId = expectedParentRow['id'] as String? ?? '';
  final recipientPeerId = expectedParentRow['contact_peer_id'] as String? ?? '';
  final attachmentIds = expectedAttachmentRows
      .map((row) => row['id'] as String? ?? '')
      .toList(growable: false);
  final expectedIds = attachmentIds.toSet();
  final preparedById = <String, Map<String, Object?>>{
    for (final row in preparedAttachmentRows)
      if (row['id'] is String) row['id']! as String: row,
  };
  final custodyById = <String, DirectMediaBlobCustodyRow>{
    for (final row in custodyRows) row.attachmentId: row,
  };
  final expectedById = <String, Map<String, Object?>>{
    for (final row in expectedAttachmentRows)
      if (row['id'] is String) row['id']! as String: row,
  };
  final intentId =
      expectedParentRow[_directMediaCustodyIntentColumn] as String?;
  final validShape =
      messageId.trim().isNotEmpty &&
      recipientPeerId.trim().isNotEmpty &&
      attachmentIds.isNotEmpty &&
      expectedIds.length == attachmentIds.length &&
      !expectedIds.contains('') &&
      preparedById.length == expectedIds.length &&
      preparedById.keys.toSet().containsAll(expectedIds) &&
      custodyById.length == expectedIds.length &&
      custodyById.keys.toSet().containsAll(expectedIds) &&
      _isExactLowercaseHex(intentId, 32) &&
      intentId ==
          computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: attachmentIds,
          ) &&
      _isEligiblePreparedDirectMediaCustodyParent(
        expectedParentRow,
        recipientPeerId: recipientPeerId,
        intentId: intentId!,
      ) &&
      expectedAttachmentRows.every(
        (row) => _isValidDirectMediaCustodyPreparationAttachment(
          row,
          messageId: messageId,
        ),
      ) &&
      preparedAttachmentRows.every((candidate) {
        final attachmentId = candidate['id'] as String? ?? '';
        final expected = expectedById[attachmentId];
        final custody = custodyById[attachmentId];
        return expected != null &&
            custody != null &&
            _samePreparedDirectMediaIdentity(expected, candidate) &&
            candidate['download_status'] == kMediaDownloadStatusUploadPending &&
            candidate['local_path'] == expected['local_path'] &&
            hasImmutableDirectMediaCustodyAttachmentProjection(candidate) &&
            custody.messageId == messageId &&
            custody.direction == DirectMediaBlobCustodyDirection.outgoing &&
            custody.state == DirectMediaBlobCustodyState.outgoingPrepared &&
            custody.recipientPeerId == recipientPeerId &&
            custody.contentHash == candidate['content_hash'] &&
            custody.ciphertextSize > 0 &&
            custody.expiresAtMs == null &&
            custody.custodyRelayPeerId == null;
      });
  if (!validShape) {
    return const DirectMediaBlobGenerationDbStageResult.refused();
  }

  return dbWriteTransaction(db, (txn) async {
    final currentParents = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final currentAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      orderBy: 'id ASC',
    );
    final currentCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    final attachmentPlaceholders = List.filled(
      attachmentIds.length,
      '?',
    ).join(',');
    final custodyIdCollisions = await txn.rawQuery(
      'SELECT * FROM $kDirectMediaBlobCustodyTable '
      'WHERE attachment_id IN ($attachmentPlaceholders) '
      'ORDER BY attachment_id ASC',
      attachmentIds,
    );
    final v108 = await txn.query(
      _directInboxCustodyOutboxTable,
      columns: const <String>['message_id'],
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );

    if (currentCustody.isNotEmpty || custodyIdCollisions.isNotEmpty) {
      final exactWinner =
          v108.isEmpty &&
          currentParents.length == 1 &&
          _messageDatabaseProjectionMatches(
            currentParents.single,
            expectedParentRow,
          ) &&
          currentAttachments.length == expectedIds.length &&
          currentCustody.length == expectedIds.length &&
          custodyIdCollisions.length == expectedIds.length;
      if (!exactWinner) {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      final winnerAttachments = <String, Map<String, Object?>>{
        for (final row in currentAttachments) row['id']! as String: row,
      };
      final winnerRows = <String, DirectMediaBlobCustodyRow>{};
      try {
        for (final raw in currentCustody) {
          final row = DirectMediaBlobCustodyRow.fromMap(raw);
          winnerRows[row.attachmentId] = row;
        }
      } on FormatException {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      final completeWinner =
          winnerAttachments.length == expectedIds.length &&
          winnerRows.length == expectedIds.length &&
          expectedIds.every((attachmentId) {
            final attachment = winnerAttachments[attachmentId];
            final custody = winnerRows[attachmentId];
            final reopenableProof = custody == null
                ? false
                : switch (custody.state) {
                    DirectMediaBlobCustodyState.outgoingPrepared =>
                      custody.inboxCustodyIncarnationId == null &&
                          custody.expiresAtMs == null &&
                          custody.custodyRelayPeerId == null,
                    DirectMediaBlobCustodyState.outgoingStored =>
                      custody.inboxCustodyIncarnationId == null &&
                          custody.expiresAtMs != null &&
                          custody.expiresAtMs! > 0 &&
                          custody.custodyRelayPeerId != null &&
                          custody.custodyRelayPeerId!.isNotEmpty &&
                          custody.custodyRelayPeerId!.trim() ==
                              custody.custodyRelayPeerId,
                    _ => false,
                  };
            return attachment != null &&
                custody != null &&
                reopenableProof &&
                attachment['message_id'] == messageId &&
                attachment['owner_lane'] == MediaOwnerLane.direct.dbValue &&
                attachment['download_status'] ==
                    kMediaDownloadStatusUploadPending &&
                hasImmutableDirectMediaCustodyAttachmentProjection(
                  attachment,
                ) &&
                custody.messageId == messageId &&
                custody.direction == DirectMediaBlobCustodyDirection.outgoing &&
                custody.recipientPeerId == recipientPeerId &&
                custody.contentHash == attachment['content_hash'];
          });
      if (!completeWinner) {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      return DirectMediaBlobGenerationDbStageResult(
        outcome: DirectMediaBlobGenerationDbStageOutcome.idempotent,
        attachmentRows: currentAttachments
            .map(Map<String, Object?>.from)
            .toList(growable: false),
        custodyRows: currentCustody
            .map(Map<String, Object?>.from)
            .toList(growable: false),
      );
    }

    final exactPredecessor =
        v108.isEmpty &&
        currentParents.length == 1 &&
        _messageDatabaseProjectionMatches(
          currentParents.single,
          expectedParentRow,
        ) &&
        _isEligiblePreparedDirectMediaCustodyParent(
          currentParents.single,
          recipientPeerId: recipientPeerId,
          intentId: intentId,
        ) &&
        currentAttachments.length == expectedAttachmentRows.length &&
        _exactDirectMediaCustodyFailureProjection(
          currentAttachments,
          expectedAttachmentRows,
        ) &&
        _preparedDirectMediaProjectionCanFinalize(
          currentAttachments,
          preparedAttachmentRows,
        );
    if (!exactPredecessor) {
      return const DirectMediaBlobGenerationDbStageResult.refused();
    }

    for (final candidate in preparedAttachmentRows) {
      await _applyMediaAttachmentPreservingSave(
        txn,
        candidate,
        candidate['id']! as String,
      );
    }
    for (final row in custodyRows) {
      await txn.insert(
        kDirectMediaBlobCustodyTable,
        row.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    final committedAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      orderBy: 'id ASC',
    );
    final committedCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    final committedRows = <String, DirectMediaBlobCustodyRow>{
      for (final raw in committedCustody)
        DirectMediaBlobCustodyRow.fromMap(raw).attachmentId:
            DirectMediaBlobCustodyRow.fromMap(raw),
    };
    final exactCommit =
        committedAttachments.length == preparedAttachmentRows.length &&
        committedCustody.length == custodyRows.length &&
        _exactDirectMediaCustodyFailureProjection(
          committedAttachments,
          preparedAttachmentRows,
        ) &&
        custodyRows.every((expected) {
          final committed = committedRows[expected.attachmentId];
          return committed != null &&
              committed.exactDatabaseProjectionMatches(expected);
        });
    if (!exactCommit) {
      throw StateError('direct-media blob generation lost atomic projection');
    }
    return DirectMediaBlobGenerationDbStageResult(
      outcome: DirectMediaBlobGenerationDbStageOutcome.applied,
      attachmentRows: committedAttachments
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      custodyRows: committedCustody
          .map(Map<String, Object?>.from)
          .toList(growable: false),
    );
  });
}

/// Whether one persisted outgoing private parent can still own strict blob
/// custody for its single convention-pending attachment.
///
/// [requireAvailable] is true only for fresh publication, which writes the
/// prepared encryption projection onto that pending row. Reopen/adoption also
/// accepts the exact active-lease and consumed transport-only shapes the
/// existing private completion coordinator already authorizes; neither may
/// mutate the row here.
bool _isEligibleOutgoingPrivateBlobCustodyParent(
  Map<String, Object?> row, {
  required String recipientPeerId,
  required bool requireAvailable,
}) {
  final authority = _classifyOutgoingPrivateParentMutationAuthority(row);
  final envelope = row['wire_envelope'];
  final envelopeMissing =
      envelope == null ||
      (envelope is String && envelope.isEmpty) ||
      (envelope is List<int> && envelope.isEmpty);
  final terminalTransportCustody =
      authority == _OutgoingPrivateParentMutationAuthority.terminal &&
      row['hidden_at'] == null &&
      row['deleted_at'] == null &&
      row['private_media_state'] == 'consumed' &&
      row['private_media_terminal_at_ms'] != null;
  final authorized = requireAvailable
      ? authority == _OutgoingPrivateParentMutationAuthority.available
      : authority == _OutgoingPrivateParentMutationAuthority.available ||
            authority == _OutgoingPrivateParentMutationAuthority.activeLease ||
            terminalTransportCustody;
  return authorized &&
      envelopeMissing &&
      row['contact_peer_id'] == recipientPeerId &&
      _isNonBlankDatabaseString(row['id']) &&
      _isNonBlankDatabaseString(row['sender_peer_id']) &&
      _isNonBlankDatabaseString(row['timestamp']) &&
      _isNonBlankDatabaseString(row['created_at']) &&
      const <String>{'sending', 'failed'}.contains(row['status']) &&
      row['edited_at'] == null &&
      row['deleted_by_peer_id'] == null &&
      row['transport'] == null &&
      row['relay_expires_at'] == null &&
      row['custody_checked_at'] == null &&
      row[_directMediaCustodyIntentColumn] == null &&
      row['private_media_duration_seconds'] == null &&
      row['private_media_received_at_ms'] == null &&
      row['private_media_expires_at_ms'] == null;
}

/// Whether one persisted attachment row is the exact convention-owned private
/// pending projection this plan may publish over.
bool _isExactOutgoingPrivatePendingBlobCustodyAttachment(
  Map<String, Object?> row, {
  required String messageId,
}) =>
    _isExactOutgoingPrivatePendingMutationRow(row, messageId: messageId) &&
    _isNonBlankDatabaseString(row['created_at']) &&
    row['media_type'] ==
        _directMediaTypeForMime(row['mime'] as String? ?? '') &&
    _isNullOrNonNegativeDatabaseInteger(row['width']) &&
    _isNullOrNonNegativeDatabaseInteger(row['height']) &&
    _isNullOrNonNegativeDatabaseInteger(row['duration_ms']) &&
    _isValidDirectMediaCustodyWaveform(row['waveform']) &&
    row['content_hash'] == null &&
    row['thumbnail_hash'] == null &&
    row['encryption_key_base64'] == null &&
    row['encryption_nonce'] == null &&
    row['encryption_scheme'] == null;

/// Whether a prepared/stored private v111 row can still be reopened.
bool _privateBlobCustodyRowIsReopenable(DirectMediaBlobCustodyRow row) =>
    switch (row.state) {
      DirectMediaBlobCustodyState.outgoingPrepared =>
        row.inboxCustodyIncarnationId == null &&
            row.expiresAtMs == null &&
            row.custodyRelayPeerId == null,
      DirectMediaBlobCustodyState.outgoingStored =>
        row.inboxCustodyIncarnationId == null &&
            row.expiresAtMs != null &&
            row.expiresAtMs! > 0 &&
            row.custodyRelayPeerId != null &&
            row.custodyRelayPeerId!.isNotEmpty &&
            row.custodyRelayPeerId!.trim() == row.custodyRelayPeerId,
      _ => false,
    };

/// Atomically publishes the exact encrypted v111 generation for one newly
/// authored protected or View-Once direct-media initial.
///
/// Plan 354 deliberately reuses the durable private parent plus its single
/// convention-owned pending attachment as the sole preparation authority: no
/// v110 intent is minted, inferred, or required. A concurrent exact winner is
/// adopted idempotently before any capacity or write work; every crossed
/// key/hash/path/policy/state/custody byte refuses without changing either
/// table.
Future<DirectMediaBlobGenerationDbStageResult>
dbStageOutgoingDirectPrivateMediaBlobGeneration(
  Database db, {
  required Map<String, Object?> expectedParentRow,
  required Map<String, Object?> expectedAttachmentRow,
  required Map<String, Object?> preparedAttachmentRow,
  required DirectMediaBlobCustodyRow custodyRow,
}) async {
  final messageId = expectedParentRow['id'] as String? ?? '';
  final recipientPeerId = expectedParentRow['contact_peer_id'] as String? ?? '';
  final attachmentId = expectedAttachmentRow['id'] as String? ?? '';
  final mime = expectedAttachmentRow['mime'] as String? ?? '';
  final validShape =
      messageId.trim().isNotEmpty &&
      recipientPeerId.trim().isNotEmpty &&
      attachmentId.trim().isNotEmpty &&
      preparedAttachmentRow['id'] == attachmentId &&
      custodyRow.attachmentId == attachmentId &&
      DirectPrivateMediaPathGuard.identifiersAreSafe(
        contactPeerId: recipientPeerId,
        messageId: messageId,
        attachmentId: attachmentId,
      ) &&
      _isEligibleOutgoingPrivateBlobCustodyParent(
        expectedParentRow,
        recipientPeerId: recipientPeerId,
        requireAvailable: false,
      ) &&
      privateMediaInitialProducerMatrixAllowsDatabaseIdentity(
        policyVersion: expectedParentRow['private_media_policy_version'],
        mode: expectedParentRow['private_media_mode'],
        durationSeconds: expectedParentRow['private_media_duration_seconds'],
        mime: mime,
        mediaType: expectedAttachmentRow['media_type'],
      ) &&
      _isExactOutgoingPrivatePendingBlobCustodyAttachment(
        expectedAttachmentRow,
        messageId: messageId,
      ) &&
      _samePreparedDirectMediaIdentity(
        expectedAttachmentRow,
        preparedAttachmentRow,
      ) &&
      preparedAttachmentRow['download_status'] ==
          kMediaDownloadStatusUploadPending &&
      preparedAttachmentRow['local_path'] ==
          expectedAttachmentRow['local_path'] &&
      hasImmutableDirectMediaCustodyAttachmentProjection(
        preparedAttachmentRow,
      ) &&
      custodyRow.messageId == messageId &&
      custodyRow.direction == DirectMediaBlobCustodyDirection.outgoing &&
      custodyRow.state == DirectMediaBlobCustodyState.outgoingPrepared &&
      custodyRow.inboxCustodyIncarnationId == null &&
      custodyRow.recipientPeerId == recipientPeerId &&
      custodyRow.contentHash == preparedAttachmentRow['content_hash'] &&
      custodyRow.ciphertextSize > 0 &&
      custodyRow.expiresAtMs == null &&
      custodyRow.custodyRelayPeerId == null &&
      _isNonBlankDatabaseString(custodyRow.ciphertextRelativePath);
  if (!validShape) {
    return const DirectMediaBlobGenerationDbStageResult.refused();
  }

  return dbWriteTransaction(db, (txn) async {
    final currentParents = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final currentAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      orderBy: 'id ASC',
    );
    final currentCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    final custodyIdCollisions = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'attachment_id = ?',
      whereArgs: <Object?>[attachmentId],
    );
    final v108 = await txn.query(
      _directInboxCustodyOutboxTable,
      columns: const <String>['message_id'],
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final exactDurableParent =
        currentParents.length == 1 &&
        _messageDatabaseProjectionMatches(
          currentParents.single,
          expectedParentRow,
        );

    // Exact-winner adoption precedes every capacity check and write.
    if (currentCustody.isNotEmpty || custodyIdCollisions.isNotEmpty) {
      if (v108.isNotEmpty ||
          !exactDurableParent ||
          currentAttachments.length != 1 ||
          currentCustody.length != 1 ||
          custodyIdCollisions.length != 1) {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      final DirectMediaBlobCustodyRow winner;
      try {
        winner = DirectMediaBlobCustodyRow.fromMap(currentCustody.single);
      } on FormatException {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      final attachment = currentAttachments.single;
      final completeWinner =
          _privateBlobCustodyRowIsReopenable(winner) &&
          winner.attachmentId == attachmentId &&
          winner.messageId == messageId &&
          winner.direction == DirectMediaBlobCustodyDirection.outgoing &&
          winner.recipientPeerId == recipientPeerId &&
          attachment['id'] == attachmentId &&
          attachment['message_id'] == messageId &&
          attachment['owner_lane'] == MediaOwnerLane.direct.dbValue &&
          attachment['download_status'] == kMediaDownloadStatusUploadPending &&
          attachment['local_path'] == expectedAttachmentRow['local_path'] &&
          hasImmutableDirectMediaCustodyAttachmentProjection(attachment) &&
          winner.contentHash == attachment['content_hash'];
      if (!completeWinner) {
        return const DirectMediaBlobGenerationDbStageResult.refused();
      }
      return DirectMediaBlobGenerationDbStageResult(
        outcome: DirectMediaBlobGenerationDbStageOutcome.idempotent,
        attachmentRows: currentAttachments
            .map(Map<String, Object?>.from)
            .toList(growable: false),
        custodyRows: currentCustody
            .map(Map<String, Object?>.from)
            .toList(growable: false),
      );
    }

    final exactPredecessor =
        v108.isEmpty &&
        exactDurableParent &&
        _isEligibleOutgoingPrivateBlobCustodyParent(
          currentParents.single,
          recipientPeerId: recipientPeerId,
          requireAvailable: true,
        ) &&
        currentAttachments.length == 1 &&
        _exactDirectMediaCustodyFailureProjection(currentAttachments, <
          Map<String, Object?>
        >[
          expectedAttachmentRow,
        ]);
    if (!exactPredecessor) {
      return const DirectMediaBlobGenerationDbStageResult.refused();
    }

    // The private preparation authority owns exactly four encryption columns
    // here. The generic preserving save is deliberately not used: it routes
    // every private parent through the narrow non-completion mutation, which
    // cannot publish a prepared ciphertext identity. Every other persisted
    // column — including the convention pending path and status — stays
    // byte-identical, and the predicate below re-proves it after commit.
    final updated = await txn.update(
      'media_attachments',
      <String, Object?>{
        'content_hash': preparedAttachmentRow['content_hash'],
        'encryption_key_base64':
            preparedAttachmentRow['encryption_key_base64'],
        'encryption_nonce': preparedAttachmentRow['encryption_nonce'],
        'encryption_scheme': preparedAttachmentRow['encryption_scheme'],
      },
      where:
          'id = ? AND message_id = ? AND owner_lane = ? '
          'AND download_status = ? AND local_path = ? '
          'AND content_hash IS NULL AND encryption_key_base64 IS NULL '
          'AND encryption_nonce IS NULL AND encryption_scheme IS NULL',
      whereArgs: <Object?>[
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
        kMediaDownloadStatusUploadPending,
        expectedAttachmentRow['local_path'],
      ],
    );
    if (updated != 1) {
      return const DirectMediaBlobGenerationDbStageResult.refused();
    }
    await txn.insert(
      kDirectMediaBlobCustodyTable,
      custodyRow.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    final committedAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      orderBy: 'id ASC',
    );
    final committedCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    final exactCommit =
        committedAttachments.length == 1 &&
        committedCustody.length == 1 &&
        _exactDirectMediaCustodyFailureProjection(committedAttachments, <
          Map<String, Object?>
        >[
          preparedAttachmentRow,
        ]) &&
        DirectMediaBlobCustodyRow.fromMap(
          committedCustody.single,
        ).exactDatabaseProjectionMatches(custodyRow);
    if (!exactCommit) {
      throw StateError(
        'private direct-media blob generation lost atomic projection',
      );
    }
    return DirectMediaBlobGenerationDbStageResult(
      outcome: DirectMediaBlobGenerationDbStageOutcome.applied,
      attachmentRows: committedAttachments
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      custodyRows: committedCustody
          .map(Map<String, Object?>.from)
          .toList(growable: false),
    );
  });
}

/// A prepared predecessor proves freshness with its manifest-bound v110 token,
/// which also becomes the immutable outbox incarnation. A marker-free fresh
/// insert mints its random 32-hex incarnation from SQLite inside this same
/// transaction. Every successful result contains the exact immutable custody
/// row selected after commit, including an already-committed competing winner.
Future<DirectMediaInboxCustodyDbStageResult>
dbStageOutgoingDirectMediaInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required List<Map<String, Object?>> attachmentRows,
  required OutgoingOrdinaryAttemptKind kind,
  required String recipientPeerId,
  required String wireEnvelope,
  String? wireMediaBlobManifestHash,
  int? wireMediaBlobExpiresAtMs,
  int capacity = kDirectInboxCustodyOutboxCapacity,
  int? nowMs,
}) async {
  final strictPreflightNowMs =
      nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
  final messageId = stagedRow['id'] as String? ?? '';
  final attachmentIds = attachmentRows
      .map((row) => row['id'] as String? ?? '')
      .toList(growable: false);
  final uniqueAttachmentIds = attachmentIds.toSet();
  final prepared = expectedRow != null;
  final intentId = expectedRow?[_directMediaCustodyIntentColumn] as String?;
  final hasNoStrictWireBinding =
      wireMediaBlobManifestHash == null && wireMediaBlobExpiresAtMs == null;
  final hasExactStrictWireBindingShape =
      _isExactLowercaseHex(wireMediaBlobManifestHash, 64) &&
      wireMediaBlobExpiresAtMs != null &&
      wireMediaBlobExpiresAtMs > 0;
  final validMode = prepared
      ? kind == OutgoingOrdinaryAttemptKind.existing
      : kind == OutgoingOrdinaryAttemptKind.fresh;
  final validPreparedIntent =
      !prepared ||
      (_isExactLowercaseHex(intentId, 32) &&
          intentId ==
              computeDirectMediaCustodyIntentId(
                messageId: messageId,
                attachmentIds: attachmentIds,
              ));
  final validShape =
      capacity >= 0 &&
      (hasNoStrictWireBinding || hasExactStrictWireBindingShape) &&
      validMode &&
      validPreparedIntent &&
      messageId.trim().isNotEmpty &&
      recipientPeerId.trim().isNotEmpty &&
      stagedRow['contact_peer_id'] == recipientPeerId &&
      stagedRow['wire_envelope'] == wireEnvelope &&
      stagedRow[_directMediaCustodyIntentColumn] == null &&
      attachmentRows.isNotEmpty &&
      uniqueAttachmentIds.length == attachmentRows.length &&
      !uniqueAttachmentIds.contains('') &&
      _isEligibleDirectMediaCustodyParent(stagedRow) &&
      attachmentRows.every(
        (row) =>
            _isCompleteDirectMediaCustodyAttachment(
              row,
              messageId: messageId,
            ) ||
            (prepared &&
                hasExactStrictWireBindingShape &&
                _isStoredStrictPendingCompletionAttachment(
                  row,
                  messageId: messageId,
                )),
      ) &&
      isExactV2DirectChatInitialEnvelope(
        wireEnvelope,
        messageId: messageId,
        senderPeerId: stagedRow['sender_peer_id'],
      );
  if (!validShape) {
    return const DirectMediaInboxCustodyDbStageResult.refused();
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final currentMessages = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      final currentProjection = await txn.query(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      final currentBlobCustody = await txn.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ? AND direction = ?',
        whereArgs: <Object?>[
          messageId,
          DirectMediaBlobCustodyDirection.outgoing.dbValue,
        ],
        orderBy: 'attachment_id ASC',
      );
      String? mediaBlobManifestHash;
      int? mediaBlobExpiresAtMs;
      List<DirectMediaBlobCustodyRow> strictBlobRows = const [];
      var authorizesStoredStrictPendingFinalization = false;
      if (currentBlobCustody.isNotEmpty) {
        try {
          strictBlobRows = currentBlobCustody
              .map(DirectMediaBlobCustodyRow.fromMap)
              .toList(growable: false);
        } on FormatException {
          return const DirectMediaInboxCustodyDbStageResult.refused();
        }
        final attachmentById = <String, Map<String, Object?>>{
          for (final row in attachmentRows) row['id']! as String: row,
        };
        final exactStrictGeneration =
            prepared &&
            strictBlobRows.length == attachmentRows.length &&
            strictBlobRows.every((row) {
              final attachment = attachmentById[row.attachmentId];
              return row.state == DirectMediaBlobCustodyState.outgoingStored &&
                  (row.inboxCustodyIncarnationId == null ||
                      row.inboxCustodyIncarnationId == intentId) &&
                  row.recipientPeerId == recipientPeerId &&
                  row.expiresAtMs != null &&
                  row.expiresAtMs! > strictPreflightNowMs + 3000 &&
                  row.custodyRelayPeerId != null &&
                  attachment != null &&
                  attachment['content_hash'] == row.contentHash;
            });
        if (!exactStrictGeneration) {
          return const DirectMediaInboxCustodyDbStageResult.refused();
        }
        final manifest = strictBlobRows
            .map(
              (row) => DirectMediaBlobManifestProjection(
                attachmentId: row.attachmentId,
                commitment: DirectMediaBlobCustodyCommitment(
                  contentHash: row.contentHash,
                  ciphertextSize: row.ciphertextSize,
                  expiresAtMs: row.expiresAtMs!,
                ),
              ),
            )
            .toList(growable: false);
        mediaBlobManifestHash = computeDirectMediaBlobManifestHash(manifest);
        mediaBlobExpiresAtMs = earliestDirectMediaBlobExpiryMs(manifest);
        if (wireMediaBlobManifestHash != mediaBlobManifestHash ||
            wireMediaBlobExpiresAtMs != mediaBlobExpiresAtMs) {
          return const DirectMediaInboxCustodyDbStageResult.refused();
        }
        // This authority is intentionally minted only after the v111 rows,
        // their canonical manifest hash, and their earliest expiry have all
        // matched the caller's strict wire commitment in this transaction.
        // It is the sole exception that lets a restart project an already
        // published ciphertext row from upload_pending to done while retaining
        // its exact canonical pending_uploads path.
        authorizesStoredStrictPendingFinalization =
            _storedStrictGenerationAuthorizesPendingFinalization(
              current: currentProjection,
              candidates: attachmentRows,
              strictBlobRows: strictBlobRows,
              messageId: messageId,
              recipientPeerId: recipientPeerId,
              strictPreflightNowMs: strictPreflightNowMs,
            );
      } else if (wireMediaBlobManifestHash != null ||
          wireMediaBlobExpiresAtMs != null) {
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }
      final currentMessageCustody = await txn.query(
        _directInboxCustodyOutboxTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );
      final currentPreparedIncarnation = prepared
          ? await txn.query(
              _directInboxCustodyOutboxTable,
              where: 'incarnation_id = ?',
              whereArgs: <Object?>[intentId],
            )
          : const <Map<String, Object?>>[];

      // A differently encrypted competing finalizer adopts the exact durable
      // winner. Mutable parent/media rows may already have settled or been
      // physically deleted; neither can revoke the independent v108 row.
      // Querying the whole message scope also prevents a marker-free fresh
      // caller from creating a second authority under another recipient.
      if (currentMessageCustody.isNotEmpty ||
          currentPreparedIncarnation.isNotEmpty) {
        final oneMessageAuthority = currentMessageCustody.length == 1;
        final onePreparedAuthority =
            !prepared || currentPreparedIncarnation.length == 1;
        if (!oneMessageAuthority || !onePreparedAuthority) {
          return const DirectMediaInboxCustodyDbStageResult.refused();
        }
        final custody = currentMessageCustody.single;
        final winnerEnvelopeValue = custody['wire_envelope'];
        final winnerEnvelope = winnerEnvelopeValue is String
            ? winnerEnvelopeValue
            : null;
        final expectedPreparedIncarnation = prepared ? intentId : null;
        final exactPreparedIncarnation =
            expectedPreparedIncarnation == null ||
            custody['incarnation_id'] == expectedPreparedIncarnation;
        final samePreparedAuthority =
            !prepared ||
            _sameDirectMediaCustodyAuthority(
              custody,
              currentPreparedIncarnation.single,
            );
        final exactWinner =
            exactPreparedIncarnation &&
            samePreparedAuthority &&
            custody['media_blob_manifest_hash'] == mediaBlobManifestHash &&
            custody['media_blob_expires_at_ms'] == mediaBlobExpiresAtMs &&
            _immutableDirectMediaCustodyMatches(
              custody,
              recipientPeerId: recipientPeerId,
              messageId: messageId,
            ) &&
            winnerEnvelope != null &&
            isExactV2DirectChatInitialEnvelope(
              winnerEnvelope,
              messageId: messageId,
              senderPeerId: stagedRow['sender_peer_id'],
            );
        if (!exactWinner) {
          return const DirectMediaInboxCustodyDbStageResult.refused();
        }
        final hasExactMutableProjection =
            currentMessages.length == 1 &&
            _adoptableDirectMediaCustodyParent(
              currentMessages.single,
              stagedRow,
              winnerEnvelope: winnerEnvelope,
            ) &&
            _exactDirectMediaCustodyProjection(
              currentProjection,
              attachmentRows,
            );
        return DirectMediaInboxCustodyDbStageResult(
          outcome: OutgoingOrdinaryMutationOutcome.idempotent,
          messageRow: currentMessages.length == 1
              ? Map<String, Object?>.from(currentMessages.single)
              : null,
          attachmentRows: currentProjection
              .map(Map<String, Object?>.from)
              .toList(growable: false),
          custodyRow: Map<String, Object?>.from(custody),
          hasExactMutableProjection: hasExactMutableProjection,
        );
      }

      if (strictBlobRows.any((row) => row.inboxCustodyIncarnationId != null)) {
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }

      if (prepared) {
        if (currentMessages.length != 1 ||
            !_messageDatabaseProjectionMatches(
              currentMessages.single,
              expectedRow,
            ) ||
            !_isEligiblePreparedDirectMediaCustodyParent(
              currentMessages.single,
              recipientPeerId: recipientPeerId,
              intentId: intentId!,
            ) ||
            !_preparedDirectMediaProjectionCanFinalize(
              currentProjection,
              attachmentRows,
              allowStoredStrictPendingFinalization:
                  authorizesStoredStrictPendingFinalization,
            )) {
          return const DirectMediaInboxCustodyDbStageResult.refused();
        }
      } else if (currentMessages.isNotEmpty || currentProjection.isNotEmpty) {
        // Marker-free fresh authority is insert-only. In particular it never
        // blesses an orphaned or partially prepared attachment projection.
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }

      final incarnationId = prepared
          ? intentId!
          : await _mintUnusedDirectMediaCustodyIncarnation(txn);
      if (incarnationId.isEmpty) {
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }
      final incarnationCollision = await txn.query(
        _directInboxCustodyOutboxTable,
        columns: const <String>['incarnation_id'],
        where: 'incarnation_id = ?',
        whereArgs: <Object?>[incarnationId],
        limit: 1,
      );
      if (incarnationCollision.isNotEmpty) {
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM $_directInboxCustodyOutboxTable',
      );
      final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
      if (count >= capacity) {
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }

      final parentOutcome =
          await dbStageOutgoingOrdinaryAttemptWithinTransaction(
            txn,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            allowDirectAttachments: true,
            allowDirectMediaCustodyIntent: true,
          );
      if (parentOutcome != OutgoingOrdinaryMutationOutcome.applied) {
        return const DirectMediaInboxCustodyDbStageResult.refused();
      }

      if (prepared) {
        final currentById = <String, Map<String, Object?>>{
          for (final row in currentProjection) row['id']! as String: row,
        };
        for (final candidate in attachmentRows) {
          final current = currentById[candidate['id']]!;
          if (current['download_status'] == kMediaDownloadStatusUploadPending) {
            await _applyMediaAttachmentPreservingSave(
              txn,
              candidate,
              candidate['id'] as String,
            );
          }
        }
        final consumed = await txn.rawUpdate(
          'UPDATE messages SET $_directMediaCustodyIntentColumn = NULL '
          'WHERE id = ? AND contact_peer_id = ? AND is_incoming = 0 '
          'AND status = ? AND wire_envelope = ? '
          'AND $_directMediaCustodyIntentColumn = ?',
          <Object?>[
            messageId,
            recipientPeerId,
            'sending',
            wireEnvelope,
            intentId,
          ],
        );
        if (consumed != 1) throw const _DirectMediaInboxCustodyRollback();
      } else {
        for (final candidate in attachmentRows) {
          await _applyMediaAttachmentPreservingSave(
            txn,
            candidate,
            candidate['id'] as String,
          );
        }
      }

      if (strictBlobRows.isNotEmpty) {
        final boundAt = DateTime.fromMillisecondsSinceEpoch(
          strictPreflightNowMs,
          isUtc: true,
        ).toIso8601String();
        for (final row in strictBlobRows) {
          final bound = row.copyWith(
            inboxCustodyIncarnationId: incarnationId,
            updatedAt: boundAt,
          );
          final changed =
              await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
                txn,
                expected: row,
                next: bound,
              );
          if (!changed) throw const _DirectMediaInboxCustodyRollback();
        }
      }

      final createdAt = stagedRow['created_at'] as String? ?? '';
      await txn.insert(_directInboxCustodyOutboxTable, <String, Object?>{
        'recipient_peer_id': recipientPeerId,
        'message_id': messageId,
        'incarnation_id': incarnationId,
        'wire_envelope': wireEnvelope,
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'media_blob_manifest_hash': mediaBlobManifestHash,
        'media_blob_expires_at_ms': mediaBlobExpiresAtMs,
        'created_at': createdAt,
        'updated_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final committedMessages = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      final committedProjection = await txn.query(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      final committedCustody = await txn.query(
        _directInboxCustodyOutboxTable,
        where: 'recipient_peer_id = ? AND message_id = ?',
        whereArgs: <Object?>[recipientPeerId, messageId],
        limit: 1,
      );
      final committedBlobCustody = await txn.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ? AND direction = ?',
        whereArgs: <Object?>[
          messageId,
          DirectMediaBlobCustodyDirection.outgoing.dbValue,
        ],
      );
      final exactBlobCommit = strictBlobRows.isEmpty
          ? committedBlobCustody.isEmpty
          : committedBlobCustody.length == strictBlobRows.length &&
                committedBlobCustody.every(
                  (raw) =>
                      DirectMediaBlobCustodyRow.fromMap(
                        raw,
                      ).inboxCustodyIncarnationId ==
                      incarnationId,
                );
      final exactCommit =
          committedMessages.length == 1 &&
          committedMessages.single[_directMediaCustodyIntentColumn] == null &&
          committedMessages.single['wire_envelope'] == wireEnvelope &&
          _exactDirectMediaCustodyProjection(
            committedProjection,
            attachmentRows,
          ) &&
          committedCustody.length == 1 &&
          committedCustody.single['incarnation_id'] == incarnationId &&
          committedCustody.single['wire_envelope'] == wireEnvelope &&
          committedCustody.single['media_blob_manifest_hash'] ==
              mediaBlobManifestHash &&
          committedCustody.single['media_blob_expires_at_ms'] ==
              mediaBlobExpiresAtMs &&
          exactBlobCommit;
      if (!exactCommit) throw const _DirectMediaInboxCustodyRollback();

      return DirectMediaInboxCustodyDbStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.applied,
        messageRow: Map<String, Object?>.from(committedMessages.single),
        attachmentRows: committedProjection
            .map(Map<String, Object?>.from)
            .toList(growable: false),
        custodyRow: Map<String, Object?>.from(committedCustody.single),
        hasExactMutableProjection: true,
      );
    });
  } on _DirectMediaInboxCustodyRollback {
    return const DirectMediaInboxCustodyDbStageResult.refused();
  }
}

Future<String> _mintUnusedDirectMediaCustodyIncarnation(
  DatabaseExecutor txn,
) async {
  // A bounded retry makes the UNIQUE collision path explicit while keeping
  // every random draw inside the staging transaction.
  for (var attempt = 0; attempt < 4; attempt++) {
    final rows = await txn.rawQuery(
      'SELECT lower(hex(randomblob(16))) AS incarnation_id',
    );
    final candidate = rows.single['incarnation_id'] as String? ?? '';
    if (!_isExactLowercaseHex(candidate, 32)) continue;
    final collision = await txn.query(
      _directInboxCustodyOutboxTable,
      columns: const <String>['incarnation_id'],
      where: 'incarnation_id = ?',
      whereArgs: <Object?>[candidate],
      limit: 1,
    );
    if (collision.isEmpty) return candidate;
  }
  return '';
}

bool _isEligibleDirectMediaCustodyParent(Map<String, Object?> row) =>
    _isNonBlankDatabaseString(row['id']) &&
    _isNonBlankDatabaseString(row['contact_peer_id']) &&
    _isNonBlankDatabaseString(row['sender_peer_id']) &&
    _isNonBlankDatabaseString(row['timestamp']) &&
    _isNonBlankDatabaseString(row['created_at']) &&
    row['status'] == 'sending' &&
    ((row['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
    row['edited_at'] == null &&
    row['deleted_at'] == null &&
    row['deleted_by_peer_id'] == null &&
    row['hidden_at'] == null &&
    row['transport'] == null &&
    row['relay_expires_at'] == null &&
    row['custody_checked_at'] == null &&
    ((row['private_media_policy_version'] as num?)?.toInt() ?? -1) == 0 &&
    row['private_media_mode'] == 'ordinary' &&
    row['private_media_duration_seconds'] == null &&
    row['private_media_state'] == 'none' &&
    row['private_media_received_at_ms'] == null &&
    row['private_media_expires_at_ms'] == null &&
    row['private_media_revealed_at_ms'] == null &&
    row['private_media_terminal_at_ms'] == null &&
    row['private_media_clock_high_water_ms'] == null;

bool _isEligiblePreparedDirectMediaCustodyParent(
  Map<String, Object?> row, {
  required String recipientPeerId,
  required String intentId,
}) =>
    row['contact_peer_id'] == recipientPeerId &&
    row[_directMediaCustodyIntentColumn] == intentId &&
    row['wire_envelope'] == null &&
    row['transport'] == null &&
    row['relay_expires_at'] == null &&
    row['custody_checked_at'] == null &&
    const <String>{'sending', 'failed'}.contains(row['status']) &&
    _isEligibleDirectMediaCustodyParent(
      Map<String, Object?>.from(row)..['status'] = 'sending',
    );

/// Exactly two canonical fresh-parent shapes are publishable here.
///
/// [authorizedForwardDedupKey] is null for the marker-free external OS share
/// (`id == dedup_key`, not forwarded). A nonblank value is one entry-authorized
/// internal forward: the parent MUST be forwarded and its dedup key MUST equal
/// that exact token. The token is supplied independently by a reviewed caller
/// and is never derived from the candidate row. Every other canonical
/// invariant is identical in both shapes.
bool _isCanonicalFreshDirectMediaBlobParent(
  Map<String, Object?> row, {
  required String recipientPeerId,
  required String intentId,
  required String? authorizedForwardDedupKey,
}) {
  final isForwarded = ((row['is_forwarded'] as num?)?.toInt() ?? 0) == 1;
  final bool canonicalIdentity;
  if (authorizedForwardDedupKey == null) {
    canonicalIdentity = !isForwarded && row['id'] == row['dedup_key'];
  } else {
    final token = authorizedForwardDedupKey.trim();
    canonicalIdentity =
        token.isNotEmpty &&
        token == authorizedForwardDedupKey &&
        isForwarded &&
        row['dedup_key'] == authorizedForwardDedupKey;
  }
  return canonicalIdentity &&
      _isEligiblePreparedDirectMediaCustodyParent(
        row,
        recipientPeerId: recipientPeerId,
        intentId: intentId,
      ) &&
      row['timestamp'] == row['created_at'] &&
      row['read_at'] == null &&
      row['quoted_message_id'] == null;
}

bool hasImmutableDirectMediaCustodyAttachmentProjection(
  Map<String, Object?> row,
) {
  final attachmentId = row['id'];
  final mime = row['mime'];
  final mediaType = row['media_type'];
  final size = row['size'];
  final thumbnailHash = row['thumbnail_hash'];
  final encryptionKey = row['encryption_key_base64'];
  final expectedKeyReference = attachmentId is String
      ? secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        )
      : null;
  return _isNonBlankDatabaseString(attachmentId) &&
      _isNonBlankDatabaseString(row['message_id']) &&
      row['owner_lane'] == MediaOwnerLane.direct.dbValue &&
      _isNonBlankDatabaseString(mime) &&
      size is int &&
      size > 0 &&
      mediaType == _directMediaTypeForMime(mime! as String) &&
      _isNullOrNonNegativeDatabaseInteger(row['width']) &&
      _isNullOrNonNegativeDatabaseInteger(row['height']) &&
      _isNullOrNonNegativeDatabaseInteger(row['duration_ms']) &&
      _isValidDirectMediaCustodyWaveform(row['waveform']) &&
      _isNonBlankDatabaseString(row['created_at']) &&
      _isExactLowercaseHex(row['content_hash'], 64) &&
      (thumbnailHash == null || _isExactLowercaseHex(thumbnailHash, 64)) &&
      encryptionKey == expectedKeyReference &&
      _isNonBlankDatabaseString(row['encryption_nonce']) &&
      row['encryption_scheme'] == _blobAesGcmV1;
}

/// Whether a generic save must retain an already-complete encrypted identity.
///
/// A legacy ordinary retry is the one qualified exception: its persisted
/// upload row can already carry crypto from the failed attempt, while a later
/// successful upload necessarily supplies a new ciphertext identity. The
/// upload-completion transition must therefore commit that new identity. Once
/// the row has left an upload state, later lifecycle repairs remain pinned.
bool shouldPreserveImmutableDirectMediaCustodyAttachmentProjection({
  required Map<String, Object?> existing,
  required Map<String, Object?> candidate,
}) {
  if (!hasImmutableDirectMediaCustodyAttachmentProjection(existing)) {
    return false;
  }
  final completesPendingUpload =
      const <String>{
        kMediaDownloadStatusUploadPending,
        kMediaDownloadStatusUploadFailed,
      }.contains(existing['download_status']) &&
      candidate['download_status'] == kMediaDownloadStatusDone;
  return !completesPendingUpload;
}

bool _isCompleteDirectMediaCustodyAttachment(
  Map<String, Object?> row, {
  required String messageId,
}) {
  final localPathValue = row['local_path'];
  final localPath = localPathValue is String ? localPathValue : null;
  return row['message_id'] == messageId &&
      hasImmutableDirectMediaCustodyAttachmentProjection(row) &&
      row['download_status'] == kMediaDownloadStatusDone &&
      mediaLocalPathHasValue(localPath) &&
      !mediaLocalPathIsTransient(localPath);
}

/// The only complete attachment shape that may retain transient storage.
///
/// A Plan 347 restart reuses the exact ciphertext generation already published
/// under v111. Its render source therefore remains at the canonical
/// `pending_uploads/<message>/<attachment>.<ext>` path until v108 is bound.
/// This predicate is only a syntactic admission check; the caller must still
/// prove the exact outgoing_stored v111 generation and wire commitment inside
/// the same transaction before authorizing the state transition.
bool _isStoredStrictPendingCompletionAttachment(
  Map<String, Object?> row, {
  required String messageId,
}) {
  final attachmentId = row['id'];
  final mime = row['mime'];
  final uploadRetryCount = row['upload_retry_count'];
  final downloadRetryCount = row['download_retry_count'];
  if (attachmentId is! String || mime is! String) return false;
  final expectedPendingPath =
      MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: mime,
      );
  return row['message_id'] == messageId &&
      hasImmutableDirectMediaCustodyAttachmentProjection(row) &&
      row['download_status'] == kMediaDownloadStatusDone &&
      row['local_path'] == expectedPendingPath &&
      (uploadRetryCount == null ||
          (uploadRetryCount is int && uploadRetryCount >= 0)) &&
      (downloadRetryCount == null ||
          (downloadRetryCount is int && downloadRetryCount >= 0));
}

bool _isValidDirectMediaCustodyPreparationAttachment(
  Map<String, Object?> row, {
  required String messageId,
}) {
  if (row['download_status'] == kMediaDownloadStatusDone) {
    return _isCompleteDirectMediaCustodyAttachment(row, messageId: messageId);
  }
  final attachmentId = row['id'];
  final mime = row['mime'];
  final size = row['size'];
  final uploadRetryCount = row['upload_retry_count'];
  final downloadRetryCount = row['download_retry_count'];
  final expectedPendingPath = attachmentId is String && mime is String
      ? _expectedPendingPathForMutation(
          messageId: messageId,
          attachmentId: attachmentId,
          mime: mime,
        )
      : null;
  return _isNonBlankDatabaseString(attachmentId) &&
      row['message_id'] == messageId &&
      row['owner_lane'] == MediaOwnerLane.direct.dbValue &&
      _isNonBlankDatabaseString(mime) &&
      size is int &&
      size > 0 &&
      row['media_type'] == _directMediaTypeForMime(mime! as String) &&
      _isNullOrNonNegativeDatabaseInteger(row['width']) &&
      _isNullOrNonNegativeDatabaseInteger(row['height']) &&
      _isNullOrNonNegativeDatabaseInteger(row['duration_ms']) &&
      _isValidDirectMediaCustodyWaveform(row['waveform']) &&
      row['download_status'] == kMediaDownloadStatusUploadPending &&
      expectedPendingPath != null &&
      row['local_path'] == expectedPendingPath &&
      _isNonBlankDatabaseString(row['created_at']) &&
      (uploadRetryCount == null ||
          (uploadRetryCount is int && uploadRetryCount >= 0)) &&
      (downloadRetryCount == null ||
          (downloadRetryCount is int && downloadRetryCount >= 0)) &&
      row['content_hash'] == null &&
      row['thumbnail_hash'] == null &&
      row['encryption_key_base64'] == null &&
      row['encryption_nonce'] == null &&
      row['encryption_scheme'] == null;
}

String _directMediaTypeForMime(String mime) {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'audio';
  return 'file';
}

bool _isNullOrNonNegativeDatabaseInteger(Object? value) =>
    value == null || (value is int && value >= 0);

bool _isValidDirectMediaCustodyWaveform(Object? value) {
  if (value == null) return true;
  if (value is! String) return false;
  try {
    final decoded = jsonDecode(value);
    return decoded is List<dynamic> &&
        decoded.every(
          (sample) =>
              sample is num &&
              sample.toDouble().isFinite &&
              sample >= 0 &&
              sample <= 1,
        );
  } catch (_) {
    return false;
  }
}

bool _preparedDirectMediaProjectionCanFinalize(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> candidates, {
  bool allowStoredStrictPendingFinalization = false,
}) {
  if (current.length != candidates.length) return false;
  final candidatesById = <String, Map<String, Object?>>{
    for (final row in candidates) row['id']! as String: row,
  };
  if (candidatesById.length != candidates.length) return false;
  for (final persisted in current) {
    final candidate = candidatesById[persisted['id']];
    if (candidate == null ||
        persisted['owner_lane'] != MediaOwnerLane.direct.dbValue ||
        persisted['message_id'] != candidate['message_id']) {
      return false;
    }
    if (persisted['download_status'] == kMediaDownloadStatusDone) {
      if (!_sameOrdinaryOutgoingAttachmentAttempt(persisted, candidate)) {
        return false;
      }
      continue;
    }
    if (persisted['download_status'] != kMediaDownloadStatusUploadPending ||
        (!_samePreparedDirectMediaIdentity(persisted, candidate) &&
            !(allowStoredStrictPendingFinalization &&
                _sameStoredStrictPendingFinalization(persisted, candidate)))) {
      return false;
    }
  }
  return true;
}

/// Proves that every candidate is the exact crypto-bearing v111 generation
/// already persisted under its canonical pending path.
///
/// The caller invokes this only after matching the canonical v111 manifest and
/// earliest expiry against the strict wire fields. Keeping the projection
/// proof separate makes the exceptional upload_pending -> done arm explicit
/// and leaves the legacy fresh-preparation transition unchanged.
bool _storedStrictGenerationAuthorizesPendingFinalization({
  required List<Map<String, Object?>> current,
  required List<Map<String, Object?>> candidates,
  required List<DirectMediaBlobCustodyRow> strictBlobRows,
  required String messageId,
  required String recipientPeerId,
  required int strictPreflightNowMs,
}) {
  if (current.length != candidates.length ||
      current.length != strictBlobRows.length ||
      current.isEmpty) {
    return false;
  }
  final currentById = <String, Map<String, Object?>>{
    for (final row in current)
      if (row['id'] is String) row['id']! as String: row,
  };
  final candidatesById = <String, Map<String, Object?>>{
    for (final row in candidates)
      if (row['id'] is String) row['id']! as String: row,
  };
  if (currentById.length != current.length ||
      candidatesById.length != candidates.length) {
    return false;
  }
  return strictBlobRows.every((row) {
    final persisted = currentById[row.attachmentId];
    final candidate = candidatesById[row.attachmentId];
    final relayPeerId = row.custodyRelayPeerId;
    return persisted != null &&
        candidate != null &&
        row.messageId == messageId &&
        row.direction == DirectMediaBlobCustodyDirection.outgoing &&
        row.state == DirectMediaBlobCustodyState.outgoingStored &&
        row.inboxCustodyIncarnationId == null &&
        row.recipientPeerId == recipientPeerId &&
        row.expiresAtMs != null &&
        row.expiresAtMs! > strictPreflightNowMs + 3000 &&
        relayPeerId != null &&
        relayPeerId.isNotEmpty &&
        relayPeerId.trim() == relayPeerId &&
        persisted['content_hash'] == row.contentHash &&
        candidate['content_hash'] == row.contentHash &&
        _sameStoredStrictPendingFinalization(persisted, candidate);
  });
}

bool _sameStoredStrictPendingFinalization(
  Map<String, Object?> current,
  Map<String, Object?> candidate,
) {
  final messageId = current['message_id'] as String? ?? '';
  final attachmentId = current['id'] as String? ?? '';
  final mime = current['mime'] as String? ?? '';
  if (messageId.isEmpty || attachmentId.isEmpty || mime.isEmpty) return false;
  final expectedPendingPath =
      MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: mime,
      );
  return current['download_status'] == kMediaDownloadStatusUploadPending &&
      candidate['download_status'] == kMediaDownloadStatusDone &&
      current['local_path'] == expectedPendingPath &&
      candidate['local_path'] == expectedPendingPath &&
      hasImmutableDirectMediaCustodyAttachmentProjection(current) &&
      hasImmutableDirectMediaCustodyAttachmentProjection(candidate) &&
      _ordinaryOutgoingAttachmentAttemptColumns
          .where((column) => column != 'download_status')
          .every(
            (column) => _sameDatabaseScalar(current[column], candidate[column]),
          );
}

const _preparedDirectMediaStableColumns = <String>[
  'id',
  'message_id',
  'owner_lane',
  'mime',
  'size',
  'media_type',
  'width',
  'height',
  'duration_ms',
  'created_at',
  'waveform',
];

bool _samePreparedDirectMediaIdentity(
  Map<String, Object?> current,
  Map<String, Object?> candidate,
) {
  final messageId = current['message_id'] as String? ?? '';
  final attachmentId = current['id'] as String? ?? '';
  final mime = current['mime'] as String? ?? '';
  if (messageId.isEmpty || attachmentId.isEmpty || mime.isEmpty) return false;
  final expectedPendingPath =
      MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: mime,
      );
  return _preparedDirectMediaStableColumns.every(
        (column) => _sameDatabaseScalar(current[column], candidate[column]),
      ) &&
      current['local_path'] == expectedPendingPath &&
      current['content_hash'] == null &&
      current['thumbnail_hash'] == null &&
      current['encryption_key_base64'] == null &&
      current['encryption_nonce'] == null &&
      current['encryption_scheme'] == null;
}

bool _exactDirectMediaCustodyProjection(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> candidates,
) {
  if (current.length != candidates.length) return false;
  final candidatesById = <String, Map<String, Object?>>{
    for (final row in candidates) row['id']! as String: row,
  };
  return candidatesById.length == candidates.length &&
      current.every((row) {
        final candidate = candidatesById[row['id']];
        return candidate != null &&
            _sameOrdinaryOutgoingAttachmentAttempt(row, candidate);
      });
}

bool _exactDirectMediaCustodyFailureProjection(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> expected,
) {
  if (current.length != expected.length) return false;
  final expectedById = <String, Map<String, Object?>>{
    for (final row in expected) row['id']! as String: row,
  };
  return expectedById.length == expected.length &&
      current.every((row) {
        final expectedRow = expectedById[row['id']];
        return expectedRow != null &&
            expectedRow.entries.every(
              (entry) => _sameDatabaseScalar(row[entry.key], entry.value),
            );
      });
}

bool _adoptableDirectMediaCustodyParent(
  Map<String, Object?> current,
  Map<String, Object?> attempted, {
  required String winnerEnvelope,
}) {
  if (current[_directMediaCustodyIntentColumn] != null ||
      (current['wire_envelope'] != winnerEnvelope &&
          current['wire_envelope'] != null) ||
      !_isEligibleDirectMediaCustodyParent(current)) {
    return false;
  }
  return attempted.entries
      .where(
        (entry) =>
            entry.key != 'wire_envelope' &&
            entry.key != _directMediaCustodyIntentColumn,
      )
      .every((entry) => _sameDatabaseScalar(current[entry.key], entry.value));
}

bool _immutableDirectMediaCustodyMatches(
  Map<String, Object?> row, {
  required String recipientPeerId,
  required String messageId,
}) =>
    row['recipient_peer_id'] == recipientPeerId &&
    row['message_id'] == messageId &&
    _isExactLowercaseHex(row['incarnation_id'], 32) &&
    _isNonBlankDatabaseString(row['wire_envelope']);

bool _sameDirectMediaCustodyAuthority(
  Map<String, Object?> left,
  Map<String, Object?> right,
) =>
    left['recipient_peer_id'] == right['recipient_peer_id'] &&
    left['message_id'] == right['message_id'] &&
    left['incarnation_id'] == right['incarnation_id'] &&
    left['wire_envelope'] == right['wire_envelope'];

bool _messageDatabaseProjectionMatches(
  Map<String, Object?> current,
  Map<String, Object?> attempted,
) => attempted.entries.every(
  (entry) => _sameDatabaseScalar(current[entry.key], entry.value),
);

bool _sameDatabaseScalar(Object? left, Object? right) {
  if (left is num && right is num) return left == right;
  return left == right;
}

bool _isNonBlankDatabaseString(Object? value) =>
    value is String && value.trim().isNotEmpty;

bool _isExactLowercaseHex(Object? value, int length) =>
    value is String &&
    value.length == length &&
    RegExp('^[0-9a-f]{$length}\$').hasMatch(value);

Future<OutgoingOrdinaryMutationOutcome>
_stageOutgoingOrdinaryAttemptWithMediaTransaction(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required List<Map<String, Object?>> attachmentRows,
  required OutgoingOrdinaryAttemptKind kind,
  required String messageId,
  required Set<String> uniqueAttachmentIds,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final existingCustody = await txn.query(
        _directInboxCustodyOutboxTable,
        columns: const <String>['incarnation_id'],
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (existingCustody.isNotEmpty) {
        // v108 custody is the immutable transport authority. Generic media
        // staging may never replace its parent envelope after the v110
        // preparation token has already been consumed. Message IDs are the
        // parent PK, so matching only that immutable identity also closes a
        // stale caller attempting to rewrite the recipient projection.
        return OutgoingOrdinaryMutationOutcome.refused;
      }
      final currentParents = await txn.query(
        'messages',
        columns: const <String>['direct_media_custody_intent_id'],
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (currentParents.isNotEmpty &&
          currentParents.single['direct_media_custody_intent_id'] != null) {
        return OutgoingOrdinaryMutationOutcome.refused;
      }
      final currentProjection = await txn.query(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      final staleProjection = currentProjection
          .where((row) => !uniqueAttachmentIds.contains(row['id']))
          .toList(growable: false);
      if (staleProjection.any(
            (row) =>
                kind != OutgoingOrdinaryAttemptKind.fresh ||
                !_isReplaceableLegacyOrdinaryUploadPlaceholder(
                  row,
                  messageId: messageId,
                  candidateIds: uniqueAttachmentIds,
                ),
          ) ||
          (kind == OutgoingOrdinaryAttemptKind.fresh &&
              currentProjection.any(
                (row) => uniqueAttachmentIds.contains(row['id']),
              ))) {
        return OutgoingOrdinaryMutationOutcome.refused;
      }
      for (final row in attachmentRows) {
        final existing = await txn.query(
          'media_attachments',
          columns: const <String>['message_id', 'owner_lane'],
          where: 'id = ?',
          whereArgs: <Object?>[row['id']],
          limit: 1,
        );
        if (existing.isNotEmpty &&
            (existing.single['message_id'] != messageId ||
                existing.single['owner_lane'] !=
                    MediaOwnerLane.direct.dbValue)) {
          return OutgoingOrdinaryMutationOutcome.refused;
        }
      }

      final parentOutcome =
          await dbStageOutgoingOrdinaryAttemptWithinTransaction(
            txn,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            allowDirectAttachments: true,
          );
      if (!parentOutcome.authorizesTransport) return parentOutcome;

      if (parentOutcome == OutgoingOrdinaryMutationOutcome.idempotent) {
        for (final row in attachmentRows) {
          final existing = await txn.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: <Object?>[row['id']],
            limit: 1,
          );
          if (existing.isEmpty ||
              !_sameOrdinaryOutgoingAttachmentAttempt(existing.single, row)) {
            return OutgoingOrdinaryMutationOutcome.refused;
          }
        }
      }

      var removedLegacyPlaceholder = false;
      for (final stale in staleProjection) {
        final changed = await txn.delete(
          'media_attachments',
          where:
              'id = ? AND message_id = ? AND owner_lane = ? '
              'AND download_status = ? AND size = 0 '
              'AND content_hash IS NULL AND thumbnail_hash IS NULL '
              'AND encryption_key_base64 IS NULL '
              'AND encryption_nonce IS NULL AND encryption_scheme IS NULL',
          whereArgs: <Object?>[
            stale['id'],
            messageId,
            MediaOwnerLane.direct.dbValue,
            kMediaDownloadStatusUploadPending,
          ],
        );
        if (changed != 1) {
          throw const _OrdinaryOutgoingProjectionRefused();
        }
        removedLegacyPlaceholder = true;
      }

      if (parentOutcome == OutgoingOrdinaryMutationOutcome.idempotent) {
        final finalProjection = await txn.query(
          'media_attachments',
          where: 'message_id = ? AND owner_lane = ?',
          whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
        );
        final candidatesById = <String, Map<String, Object?>>{
          for (final row in attachmentRows) row['id']! as String: row,
        };
        final exactProjection =
            finalProjection.length == uniqueAttachmentIds.length &&
            finalProjection.every((current) {
              final candidate = candidatesById[current['id']];
              return candidate != null &&
                  _sameOrdinaryOutgoingAttachmentAttempt(current, candidate);
            });
        if (!exactProjection) {
          throw const _OrdinaryOutgoingProjectionRefused();
        }
        return removedLegacyPlaceholder
            ? OutgoingOrdinaryMutationOutcome.applied
            : OutgoingOrdinaryMutationOutcome.idempotent;
      }

      for (final row in attachmentRows) {
        await _applyMediaAttachmentPreservingSave(
          txn,
          row,
          row['id'] as String,
        );
      }
      final finalProjection = await txn.query(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      final candidatesById = <String, Map<String, Object?>>{
        for (final row in attachmentRows) row['id']! as String: row,
      };
      final exactProjection =
          finalProjection.length == uniqueAttachmentIds.length &&
          finalProjection.every((current) {
            final candidate = candidatesById[current['id']];
            return candidate != null &&
                _sameOrdinaryOutgoingAttachmentAttempt(current, candidate);
          });
      if (!exactProjection) {
        // Throwing is intentional: a plain refused return would commit the
        // already-staged parent. The wrapper converts this rollback sentinel
        // into the stable refusal outcome after SQLite has undone both sides.
        throw const _OrdinaryOutgoingProjectionRefused();
      }
      return parentOutcome;
    });
  } on _OrdinaryOutgoingProjectionRefused {
    return OutgoingOrdinaryMutationOutcome.refused;
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

/// Classifies one outgoing direct-private upload completion without mutating
/// either the attachment row or its secure key.
///
/// The classification and every durable identity read share one SQLite
/// transaction. The repository additionally compares the hydrated secure-key
/// value before accepting [OutgoingDirectPrivateCompletionQualification
/// .identicalCommittedCandidate].
Future<OutgoingDirectPrivateCompletionQualification>
dbClassifyOutgoingDirectPrivateMediaCompletion(
  Database db,
  Map<String, Object?> completionRow, {
  required String expectedPendingLocalPath,
}) {
  return dbWriteTransaction(db, (txn) async {
    final messageId = completionRow['message_id'] as String? ?? '';
    final attachmentId = completionRow['id'] as String? ?? '';
    final parents = await txn.query(
      'messages',
      columns: const <String>[
        'id',
        'contact_peer_id',
        'status',
        'is_incoming',
        'wire_envelope',
        'hidden_at',
        'deleted_at',
        'private_media_policy_version',
        'private_media_mode',
        'private_media_state',
        'private_media_revealed_at_ms',
        'private_media_terminal_at_ms',
      ],
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (parents.isEmpty) {
      return OutgoingDirectPrivateCompletionQualification.refused;
    }
    final parent = parents.single;
    final isOutgoing = ((parent['is_incoming'] as num?)?.toInt() ?? 0) == 0;
    final policyVersion = (parent['private_media_policy_version'] as num?)
        ?.toInt();
    final mode = parent['private_media_mode'] as String?;
    final isOutgoingPrivateParent =
        isOutgoing &&
        policyVersion == 1 &&
        (mode == 'protected' || mode == 'view_once');
    final isOutgoingGenericParent =
        isOutgoing &&
        ((policyVersion == null && mode == null) ||
            (policyVersion == 0 && (mode == null || mode == 'ordinary')) ||
            (policyVersion == 1 && mode == 'disappearing'));
    if (!isOutgoing || isOutgoingGenericParent) {
      return OutgoingDirectPrivateCompletionQualification.notPrivateParent;
    }
    if (!isOutgoingPrivateParent) {
      // Outgoing nonordinary/future-policy shapes are not generic-media
      // authority. In particular, a v2+ protected parent must fail closed
      // instead of falling through to an INSERT-capable repository save.
      return OutgoingDirectPrivateCompletionQualification.refused;
    }
    if (parent['hidden_at'] != null || parent['deleted_at'] != null) {
      return OutgoingDirectPrivateCompletionQualification.refused;
    }

    final rows = await txn.query(
      'media_attachments',
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
      ],
      limit: 1,
    );
    if (rows.isEmpty ||
        !_outgoingPrivateCompletionConventionMatches(
          parent: parent,
          persistedRow: rows.single,
          completionRow: completionRow,
          expectedPendingLocalPath: expectedPendingLocalPath,
        )) {
      return OutgoingDirectPrivateCompletionQualification.refused;
    }
    final row = rows.single;
    final state = parent['private_media_state'] as String?;
    final terminalAt = parent['private_media_terminal_at_ms'];
    final pendingIdentity =
        row['download_status'] == kMediaDownloadStatusUploadPending &&
        row['local_path'] == expectedPendingLocalPath &&
        row['mime'] == completionRow['mime'] &&
        row['size'] == completionRow['size'];

    if (state == 'available' &&
        terminalAt == null &&
        parent['private_media_revealed_at_ms'] == null) {
      if (pendingIdentity) {
        return OutgoingDirectPrivateCompletionQualification.availablePending;
      }
      if (_persistedCompletionFingerprintMatches(row, completionRow)) {
        return OutgoingDirectPrivateCompletionQualification
            .identicalCommittedCandidate;
      }
      return OutgoingDirectPrivateCompletionQualification.refused;
    }
    if ((state == 'opening' || state == 'viewing') &&
        terminalAt == null &&
        pendingIdentity) {
      return OutgoingDirectPrivateCompletionQualification.activeLeasePending;
    }
    final envelope = parent['wire_envelope'];
    final envelopeMissing =
        envelope == null ||
        (envelope is String && envelope.isEmpty) ||
        (envelope is List<int> && envelope.isEmpty);
    if (state == 'consumed' &&
        terminalAt != null &&
        (parent['status'] == 'sending' || parent['status'] == 'failed') &&
        envelopeMissing &&
        pendingIdentity) {
      return OutgoingDirectPrivateCompletionQualification
          .transportOnlyTerminalCustody;
    }
    return OutgoingDirectPrivateCompletionQualification.refused;
  });
}

/// Commits a complete uploaded attachment only while its exact outgoing
/// private parent is still available and its exact pending row is unchanged.
/// Parent qualification and the full-row update are one transaction.
Future<bool> dbCommitOutgoingDirectPrivateMediaAvailableCompletion(
  Database db,
  Map<String, Object?> completionRow, {
  required String expectedPendingLocalPath,
}) {
  return dbWriteTransaction(db, (txn) async {
    final identity = await _loadOutgoingPrivateCompletionIdentity(
      txn,
      completionRow,
      expectedPendingLocalPath: expectedPendingLocalPath,
      requiredParentState: 'available',
      requiredMode: null,
    );
    if (identity == null ||
        identity.persistedRow['download_status'] !=
            kMediaDownloadStatusUploadPending ||
        identity.persistedRow['local_path'] != expectedPendingLocalPath) {
      return false;
    }
    final updated = await txn.update(
      'media_attachments',
      _outgoingPrivateCompletionUpdate(completionRow),
      where:
          'id = ? AND message_id = ? AND owner_lane = ? '
          'AND download_status = ? AND local_path = ? AND mime = ? '
          'AND size = ? AND EXISTS (SELECT 1 FROM messages parent '
          'WHERE parent.id = media_attachments.message_id '
          'AND parent.is_incoming = 0 AND parent.hidden_at IS NULL '
          'AND parent.deleted_at IS NULL '
          'AND parent.private_media_policy_version = 1 '
          "AND parent.private_media_mode IN ('protected','view_once') "
          "AND parent.private_media_state = 'available' "
          'AND parent.private_media_revealed_at_ms IS NULL '
          'AND parent.private_media_terminal_at_ms IS NULL)',
      whereArgs: <Object?>[
        completionRow['id'],
        completionRow['message_id'],
        MediaOwnerLane.direct.dbValue,
        kMediaDownloadStatusUploadPending,
        expectedPendingLocalPath,
        completionRow['mime'],
        completionRow['size'],
      ],
    );
    return updated == 1;
  });
}

/// Settlement-owned atomic rollback/finalize for an outgoing pre-frame lease.
///
/// `opening -> available` and `upload_pending -> done/canonical` either both
/// commit or both roll back. A trigger/constraint failure after the parent CAS
/// therefore cannot expose an available parent with the stale pending row.
Future<bool> dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion(
  Database db,
  Map<String, Object?> completionRow, {
  required String expectedPendingLocalPath,
  required String mode,
}) {
  if (mode != 'protected' && mode != 'view_once') {
    return Future<bool>.value(false);
  }
  return dbWriteTransaction(db, (txn) async {
    final identity = await _loadOutgoingPrivateCompletionIdentity(
      txn,
      completionRow,
      expectedPendingLocalPath: expectedPendingLocalPath,
      requiredParentState: 'opening',
      requiredMode: mode,
    );
    if (identity == null ||
        identity.persistedRow['download_status'] !=
            kMediaDownloadStatusUploadPending ||
        identity.persistedRow['local_path'] != expectedPendingLocalPath) {
      return false;
    }
    final parentUpdated = await txn.rawUpdate(
      "UPDATE messages SET private_media_state = 'available' "
      'WHERE id = ? AND is_incoming = 0 AND hidden_at IS NULL '
      'AND deleted_at IS NULL AND private_media_policy_version = 1 '
      'AND private_media_mode = ? '
      "AND private_media_state = 'opening' "
      'AND private_media_revealed_at_ms IS NULL '
      'AND private_media_terminal_at_ms IS NULL '
      'AND EXISTS (SELECT 1 FROM media_attachments attachment '
      'WHERE attachment.id = ? AND attachment.message_id = messages.id '
      'AND attachment.owner_lane = ? '
      'AND attachment.download_status = ? AND attachment.local_path = ? '
      'AND attachment.mime = ? AND attachment.size = ?)',
      <Object?>[
        completionRow['message_id'],
        mode,
        completionRow['id'],
        MediaOwnerLane.direct.dbValue,
        kMediaDownloadStatusUploadPending,
        expectedPendingLocalPath,
        completionRow['mime'],
        completionRow['size'],
      ],
    );
    if (parentUpdated != 1) return false;
    final attachmentUpdated = await txn.update(
      'media_attachments',
      _outgoingPrivateCompletionUpdate(completionRow),
      where:
          'id = ? AND message_id = ? AND owner_lane = ? '
          'AND download_status = ? AND local_path = ? AND mime = ? '
          'AND size = ?',
      whereArgs: <Object?>[
        completionRow['id'],
        completionRow['message_id'],
        MediaOwnerLane.direct.dbValue,
        kMediaDownloadStatusUploadPending,
        expectedPendingLocalPath,
        completionRow['mime'],
        completionRow['size'],
      ],
    );
    if (attachmentUpdated != 1) {
      throw StateError('outgoing private completion identity changed');
    }
    return true;
  });
}

Future<({Map<String, Object?> parent, Map<String, Object?> persistedRow})?>
_loadOutgoingPrivateCompletionIdentity(
  DatabaseExecutor txn,
  Map<String, Object?> completionRow, {
  required String expectedPendingLocalPath,
  required String requiredParentState,
  required String? requiredMode,
}) async {
  final messageId = completionRow['message_id'] as String? ?? '';
  final attachmentId = completionRow['id'] as String? ?? '';
  final parents = await txn.query(
    'messages',
    where:
        'id = ? AND is_incoming = 0 AND hidden_at IS NULL '
        'AND deleted_at IS NULL AND private_media_policy_version = 1 '
        "AND private_media_mode IN ('protected','view_once') "
        'AND private_media_state = ? '
        'AND private_media_revealed_at_ms IS NULL '
        'AND private_media_terminal_at_ms IS NULL',
    whereArgs: <Object?>[messageId, requiredParentState],
    limit: 1,
  );
  if (parents.isEmpty ||
      (requiredMode != null &&
          parents.single['private_media_mode'] != requiredMode)) {
    return null;
  }
  final rows = await txn.query(
    'media_attachments',
    where: 'id = ? AND message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[
      attachmentId,
      messageId,
      MediaOwnerLane.direct.dbValue,
    ],
    limit: 1,
  );
  if (rows.isEmpty ||
      !_outgoingPrivateCompletionConventionMatches(
        parent: parents.single,
        persistedRow: rows.single,
        completionRow: completionRow,
        expectedPendingLocalPath: expectedPendingLocalPath,
      )) {
    return null;
  }
  return (parent: parents.single, persistedRow: rows.single);
}

bool _outgoingPrivateCompletionConventionMatches({
  required Map<String, Object?> parent,
  required Map<String, Object?> persistedRow,
  required Map<String, Object?> completionRow,
  required String expectedPendingLocalPath,
}) {
  final messageId = completionRow['message_id'] as String? ?? '';
  final attachmentId = completionRow['id'] as String? ?? '';
  final mime = completionRow['mime'] as String? ?? '';
  final contactPeerId = parent['contact_peer_id'] as String? ?? '';
  if (messageId.isEmpty ||
      attachmentId.isEmpty ||
      mime.isEmpty ||
      contactPeerId.isEmpty ||
      completionRow['owner_lane'] != MediaOwnerLane.direct.dbValue ||
      completionRow['download_status'] != kMediaDownloadStatusDone ||
      (completionRow['size'] as num?)?.toInt() == null ||
      (completionRow['size'] as num).toInt() <= 0) {
    return false;
  }
  final canonical = MediaFilePathConvention.relativePathForAttachment(
    contactPeerId: contactPeerId,
    blobId: attachmentId,
    mime: mime,
  );
  final pending = MediaFilePathConvention.relativePathForPendingUpload(
    messageId: messageId,
    attachmentId: attachmentId,
    mime: mime,
  );
  return completionRow['local_path'] == canonical &&
      expectedPendingLocalPath == pending &&
      persistedRow['message_id'] == messageId &&
      persistedRow['id'] == attachmentId &&
      persistedRow['owner_lane'] == MediaOwnerLane.direct.dbValue;
}

bool _persistedCompletionFingerprintMatches(
  Map<String, Object?> persistedRow,
  Map<String, Object?> completionRow,
) {
  const fields = <String>[
    'id',
    'message_id',
    'owner_lane',
    'local_path',
    'download_status',
    'mime',
    'size',
    'content_hash',
    'thumbnail_hash',
    'encryption_key_base64',
    'encryption_nonce',
    'encryption_scheme',
  ];
  return fields.every((field) => persistedRow[field] == completionRow[field]);
}

Map<String, Object?> _outgoingPrivateCompletionUpdate(
  Map<String, Object?> completionRow,
) {
  return <String, Object?>{
    'mime': completionRow['mime'],
    'size': completionRow['size'],
    'media_type': completionRow['media_type'],
    'width': completionRow['width'],
    'height': completionRow['height'],
    'duration_ms': completionRow['duration_ms'],
    'local_path': completionRow['local_path'],
    'download_status': completionRow['download_status'],
    'created_at': completionRow['created_at'],
    'waveform': completionRow['waveform'],
    'upload_retry_count': completionRow['upload_retry_count'] ?? 0,
    'download_retry_count': completionRow['download_retry_count'] ?? 0,
    'content_hash': completionRow['content_hash'],
    'thumbnail_hash': completionRow['thumbnail_hash'],
    'encryption_key_base64': completionRow['encryption_key_base64'],
    'encryption_nonce': completionRow['encryption_nonce'],
    'encryption_scheme': completionRow['encryption_scheme'],
    'owner_lane': MediaOwnerLane.direct.dbValue,
  };
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

/// Exact path-only repair for the deployed outgoing direct-private row whose
/// completed upload retained an absolute pending-upload path.
///
/// The caller has already authorized the canonical regular file and exact
/// size beneath the independently trusted media root while holding the
/// attachment lifecycle lock. This statement rechecks every durable identity
/// dimension and changes only `local_path`; it never promotes a pending row or
/// fabricates completion/crypto metadata.
Future<int> dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible(
  Database db, {
  required String messageId,
  required String attachmentId,
  required String expectedStoredLocalPath,
  required String canonicalLocalPath,
  required String expectedContactPeerId,
  required String expectedMime,
  required int expectedSize,
}) {
  final expectedCanonical = MediaFilePathConvention.relativePathForAttachment(
    contactPeerId: expectedContactPeerId,
    blobId: attachmentId,
    mime: expectedMime,
  );
  if (messageId.isEmpty ||
      attachmentId.isEmpty ||
      expectedStoredLocalPath.isEmpty ||
      expectedStoredLocalPath == canonicalLocalPath ||
      canonicalLocalPath != expectedCanonical ||
      expectedContactPeerId.isEmpty ||
      expectedMime.isEmpty ||
      expectedSize <= 0) {
    return Future<int>.value(0);
  }
  return db.rawUpdate(
    'UPDATE media_attachments SET local_path = ? '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND download_status = ? AND local_path = ? AND mime = ? AND size = ? '
    'AND EXISTS (SELECT 1 FROM messages parent '
    'WHERE parent.id = media_attachments.message_id '
    'AND parent.contact_peer_id = ? AND parent.is_incoming = 0 '
    'AND parent.hidden_at IS NULL AND parent.deleted_at IS NULL '
    'AND parent.private_media_policy_version = 1 '
    "AND parent.private_media_mode IN ('protected','view_once') "
    "AND parent.private_media_state = 'available' "
    'AND parent.private_media_revealed_at_ms IS NULL '
    'AND parent.private_media_terminal_at_ms IS NULL)',
    <Object?>[
      canonicalLocalPath,
      attachmentId,
      messageId,
      MediaOwnerLane.direct.dbValue,
      kMediaDownloadStatusDone,
      expectedStoredLocalPath,
      expectedMime,
      expectedSize,
      expectedContactPeerId,
    ],
  );
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

/// Applies the narrow metadata-only portion of an outgoing direct-private
/// save. This is the authority boundary for generic failure/cancel writers:
/// they may change only status/retry count while the exact convention-pending
/// row and its parent remain `available` in this same transaction.
///
/// Active leases and terminal parents are typed no-ops. Ordinary/incoming
/// parents are explicitly classified so the repository may retain its
/// generic save behavior only for those parents.
Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
dbApplyOutgoingDirectPrivateNonCompletionMutation(
  Database db,
  Map<String, Object?> row, {
  bool missingParentIsOrdinary = false,
}) {
  return dbWriteTransaction(
    db,
    (txn) => _applyOutgoingDirectPrivateNonCompletionMutation(
      txn,
      row,
      missingParentIsOrdinary: missingParentIsOrdinary,
    ),
  );
}

/// Inserts the first durable pending row for an outgoing protected/view-once
/// upload only while its exact parent remains visible and `available`.
///
/// This is intentionally separate from both generic attachment persistence
/// and non-completion mutation. A protected/view-once parent may reach this
/// seam only after its pending file was copied to the convention-relative
/// message/attachment path. Missing, terminal, active-lease, future-policy,
/// malformed, or conflicting identities are refused without a generic
/// fallback. Ordinary, incoming, and disappearing parents are classified as
/// [OutgoingDirectPrivatePendingPreparationOutcome.notPrivateParent].
Future<OutgoingDirectPrivatePendingPreparationOutcome>
dbInsertOutgoingDirectPrivatePendingAttachmentIfEligible(
  Database db,
  Map<String, Object?> row,
) => dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible(
  db,
  <Map<String, Object?>>[row],
);

/// Batch form of [dbInsertOutgoingDirectPrivatePendingAttachmentIfEligible].
/// Every row is qualified and inserted in one write transaction, so a later
/// malformed/conflicting attachment cannot leave an earlier row published as
/// viewer authority.
Future<OutgoingDirectPrivatePendingPreparationOutcome>
dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible(
  Database db,
  List<Map<String, Object?>> rows,
) {
  return dbWriteTransaction(db, (txn) async {
    if (rows.isEmpty) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    if (rows.any((row) => row['owner_lane'] != MediaOwnerLane.direct.dbValue)) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final messageIds = rows
        .map((row) => row['message_id'] as String? ?? '')
        .toSet();
    final attachmentIds = rows.map((row) => row['id'] as String? ?? '').toSet();
    if (messageIds.length != 1 ||
        messageIds.single.isEmpty ||
        attachmentIds.length != rows.length ||
        attachmentIds.contains('')) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final messageId = messageIds.single;

    final parentRows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (parentRows.isEmpty) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final parent = parentRows.single;
    final authority = _classifyOutgoingPrivateParentMutationAuthority(parent);
    if (authority ==
        _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming) {
      // Parent policy, never attachment crypto metadata, selects the generic
      // lane. Ordinary uploads may already carry their historical
      // hash/key/nonce fields when their first row is persisted.
      return OutgoingDirectPrivatePendingPreparationOutcome.notPrivateParent;
    }
    if (authority != _OutgoingPrivateParentMutationAuthority.available) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final contactPeerId = parent['contact_peer_id'] as String? ?? '';
    for (final row in rows) {
      final attachmentId = row['id'] as String? ?? '';
      final mime = row['mime'] as String? ?? '';
      if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
            contactPeerId: contactPeerId,
            messageId: messageId,
            attachmentId: attachmentId,
          ) ||
          MediaFilePathConvention.extensionFromMime(mime).isEmpty) {
        return OutgoingDirectPrivatePendingPreparationOutcome.refused;
      }
      bool completionFieldHasValue(String field) {
        final value = row[field];
        return value != null && (value is! String || value.trim().isNotEmpty);
      }

      if (const <String>[
            'content_hash',
            'thumbnail_hash',
            'encryption_key_base64',
            'encryption_nonce',
            'encryption_scheme',
          ].any(completionFieldHasValue) ||
          !_isExactOutgoingPrivatePendingMutationRow(
            row,
            messageId: messageId,
          )) {
        return OutgoingDirectPrivatePendingPreparationOutcome.refused;
      }
      final existingRows = await txn.query(
        'media_attachments',
        columns: const <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[attachmentId],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        return OutgoingDirectPrivatePendingPreparationOutcome.refused;
      }
    }

    // The parent query and insert share one SQLCipher write transaction. A
    // concurrent lifecycle claim therefore cannot land between qualification
    // and insertion. Repeating the positive parent predicate here also makes
    // the write's authority explicit and protects alternate transaction
    // implementations used by tests.
    final stillAvailable = await txn.rawQuery(
      'SELECT 1 FROM messages WHERE id = ? AND is_incoming = 0 '
      'AND hidden_at IS NULL AND deleted_at IS NULL '
      'AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      "AND private_media_state = 'available' "
      'AND private_media_revealed_at_ms IS NULL '
      'AND private_media_terminal_at_ms IS NULL LIMIT 1',
      <Object?>[messageId],
    );
    if (stillAvailable.isEmpty) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }

    for (final row in rows) {
      await txn.insert('media_attachments', row);
    }
    return OutgoingDirectPrivatePendingPreparationOutcome.inserted;
  });
}

/// Deletes the exact pending-path attachment set of one outgoing
/// protected/view-once parent while it remains `available`.
///
/// This is the typed counterpart of generic message-level attachment
/// deletion. It accepts only upload-pending/failure/cancel states that retain
/// the convention-owned pending identity. Active leases and terminal parents
/// are explicit no-ops; ordinary/incoming/disappearing parents are returned
/// to the caller for their existing generic path.
Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion(
  Database db,
  String messageId,
) => dbWriteTransaction(db, (txn) async {
  final qualification = await _qualifyOutgoingDirectPrivatePendingDeletion(
    txn,
    messageId,
  );
  return qualification.outcome;
});

Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible(
  Database db,
  String messageId,
) {
  return dbWriteTransaction(db, (txn) async {
    final qualification = await _qualifyOutgoingDirectPrivatePendingDeletion(
      txn,
      messageId,
    );
    if (qualification.outcome !=
        OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
      return qualification.outcome;
    }
    final deleted = await txn.rawDelete(
      "DELETE FROM media_attachments WHERE message_id = ? AND owner_lane = ? "
      "AND download_status IN ('upload_pending','upload_failed','upload_cancelled') "
      'AND EXISTS (SELECT 1 FROM messages private_parent '
      'WHERE private_parent.id = media_attachments.message_id '
      'AND private_parent.is_incoming = 0 '
      'AND private_parent.hidden_at IS NULL '
      'AND private_parent.deleted_at IS NULL '
      'AND private_parent.private_media_policy_version = 1 '
      "AND private_parent.private_media_mode IN ('protected','view_once') "
      "AND private_parent.private_media_state = 'available' "
      'AND private_parent.private_media_revealed_at_ms IS NULL '
      'AND private_parent.private_media_terminal_at_ms IS NULL)',
      <Object?>[messageId, MediaOwnerLane.direct.dbValue],
    );
    if (deleted != qualification.rowCount) {
      throw StateError(
        'Outgoing private pending deletion qualification changed',
      );
    }
    return OutgoingDirectPrivateNonCompletionMutationOutcome.applied;
  });
}

Future<
  ({OutgoingDirectPrivateNonCompletionMutationOutcome outcome, int rowCount})
>
_qualifyOutgoingDirectPrivatePendingDeletion(
  DatabaseExecutor txn,
  String messageId,
) async {
  final parentRows = await txn.query(
    'messages',
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  if (parentRows.isEmpty) {
    return (
      outcome: OutgoingDirectPrivateNonCompletionMutationOutcome.refused,
      rowCount: 0,
    );
  }
  final authority = _classifyOutgoingPrivateParentMutationAuthority(
    parentRows.single,
  );
  switch (authority) {
    case _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming:
      return (
        outcome:
            OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent,
        rowCount: 0,
      );
    case _OutgoingPrivateParentMutationAuthority.activeLease:
      return (
        outcome: OutgoingDirectPrivateNonCompletionMutationOutcome
            .notAppliedActiveLease,
        rowCount: 0,
      );
    case _OutgoingPrivateParentMutationAuthority.terminal:
      return (
        outcome: OutgoingDirectPrivateNonCompletionMutationOutcome.terminalNoOp,
        rowCount: 0,
      );
    case _OutgoingPrivateParentMutationAuthority.refused:
      return (
        outcome: OutgoingDirectPrivateNonCompletionMutationOutcome.refused,
        rowCount: 0,
      );
    case _OutgoingPrivateParentMutationAuthority.available:
      break;
  }

  final rows = await txn.query(
    'media_attachments',
    where: 'message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
  );
  const deletableStatuses = <String>{
    kMediaDownloadStatusUploadPending,
    'upload_failed',
    'upload_cancelled',
  };
  if (rows.isEmpty ||
      rows.any(
        (row) =>
            !_hasExactOutgoingPrivatePendingIdentity(
              row,
              messageId: messageId,
            ) ||
            !deletableStatuses.contains(row['download_status']),
      )) {
    return (
      outcome: OutgoingDirectPrivateNonCompletionMutationOutcome.refused,
      rowCount: 0,
    );
  }
  return (
    outcome: OutgoingDirectPrivateNonCompletionMutationOutcome.applied,
    rowCount: rows.length,
  );
}

Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
_applyOutgoingDirectPrivateNonCompletionMutation(
  DatabaseExecutor txn,
  Map<String, Object?> row, {
  bool missingParentIsOrdinary = false,
}) async {
  if (row['owner_lane'] != MediaOwnerLane.direct.dbValue) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent;
  }
  final messageId = row['message_id'] as String? ?? '';
  final attachmentId = row['id'] as String? ?? '';
  if (messageId.isEmpty || attachmentId.isEmpty) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  final parents = await txn.query(
    'messages',
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  if (parents.isEmpty) {
    return missingParentIsOrdinary
        ? OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent
        : OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  final authority = _classifyOutgoingPrivateParentMutationAuthority(
    parents.single,
  );
  switch (authority) {
    case _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming:
      return OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent;
    case _OutgoingPrivateParentMutationAuthority.activeLease:
      return OutgoingDirectPrivateNonCompletionMutationOutcome
          .notAppliedActiveLease;
    case _OutgoingPrivateParentMutationAuthority.terminal:
      return OutgoingDirectPrivateNonCompletionMutationOutcome.terminalNoOp;
    case _OutgoingPrivateParentMutationAuthority.refused:
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    case _OutgoingPrivateParentMutationAuthority.available:
      break;
  }

  final persistedRows = await txn.query(
    'media_attachments',
    where: 'id = ? AND message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[
      attachmentId,
      messageId,
      MediaOwnerLane.direct.dbValue,
    ],
    limit: 1,
  );
  if (persistedRows.isEmpty) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  final persisted = persistedRows.single;
  if (!_isExactOutgoingPrivatePendingMutationRow(
    persisted,
    messageId: messageId,
  )) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  final nextStatus = row['download_status'] as String?;
  if (!const <String>{
    kMediaDownloadStatusUploadPending,
    'upload_failed',
    'upload_cancelled',
  }.contains(nextStatus)) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  const immutableFields = <String>[
    'id',
    'message_id',
    'owner_lane',
    'mime',
    'size',
    'local_path',
    'content_hash',
    'thumbnail_hash',
    'encryption_key_base64',
    'encryption_nonce',
    'encryption_scheme',
  ];
  if (immutableFields.any((field) => persisted[field] != row[field])) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  final retryCount = (row['upload_retry_count'] as num?)?.toInt() ?? 0;
  if (retryCount < 0) {
    return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
  }
  final changed = await txn.rawUpdate(
    'UPDATE media_attachments SET download_status = ?, '
    'upload_retry_count = ? WHERE id = ? AND message_id = ? '
    'AND owner_lane = ? AND download_status = ? AND local_path = ? '
    'AND mime = ? AND size = ? '
    'AND EXISTS (SELECT 1 FROM messages private_parent '
    'WHERE private_parent.id = media_attachments.message_id '
    'AND private_parent.is_incoming = 0 '
    'AND private_parent.hidden_at IS NULL '
    'AND private_parent.deleted_at IS NULL '
    'AND private_parent.private_media_policy_version = 1 '
    "AND private_parent.private_media_mode IN ('protected','view_once') "
    "AND private_parent.private_media_state = 'available' "
    'AND private_parent.private_media_revealed_at_ms IS NULL '
    'AND private_parent.private_media_terminal_at_ms IS NULL)',
    <Object?>[
      nextStatus,
      retryCount,
      attachmentId,
      messageId,
      MediaOwnerLane.direct.dbValue,
      kMediaDownloadStatusUploadPending,
      persisted['local_path'],
      persisted['mime'],
      persisted['size'],
    ],
  );
  return changed == 1
      ? OutgoingDirectPrivateNonCompletionMutationOutcome.applied
      : OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
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
  if (!await _canApplyGenericMediaAttachmentSave(txn, row)) {
    // The caller has no predecessor CAS for an immutable custody winner. This
    // also blocks INSERT after user deletion while v108 (or its post-retirement
    // terminal parent tombstone) remains the durable authority.
    throw const GenericMediaAttachmentCustodySaveRefused();
  }
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

  final privateMutation =
      await _applyOutgoingDirectPrivateNonCompletionMutation(
        txn,
        row,
        // Low-level migration/fixture callers historically merge orphan rows.
        // Production repository callers use the exported guard first, where a
        // missing parent remains a refusal.
        missingParentIsOrdinary: true,
      );
  if (privateMutation !=
      OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent) {
    // The guarded helper either committed the narrow available-state update
    // or deliberately refused it. Never follow a private result with the
    // INSERT/full-row generic merge below.
    return;
  }

  final merged = Map<String, Object?>.from(row);
  if (shouldPreserveImmutableDirectMediaCustodyAttachmentProjection(
    existing: existing,
    candidate: row,
  )) {
    for (final column in _immutableDirectMediaProjectionColumns) {
      merged[column] = existing[column];
    }
  }
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
  // Strict adoption provenance outlives its independent v111 ACK/expiry row.
  // A proof-less ordinary replay can never clear or replace it.
  if (existing.containsKey('direct_media_blob_custody_fingerprint')) {
    merged['direct_media_blob_custody_fingerprint'] =
        existing['direct_media_blob_custody_fingerprint'];
  }
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

Future<bool> _canApplyGenericMediaAttachmentSave(
  DatabaseExecutor db,
  Map<String, Object?> row, {
  bool requireCustodySchema = false,
}) async {
  if (row['owner_lane'] != MediaOwnerLane.direct.dbValue) return true;
  final messageId = row['message_id'];
  if (!_isNonBlankDatabaseString(messageId)) return true;

  final schemaRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name IN ('messages', '$_directInboxCustodyOutboxTable')",
  );
  final tables = schemaRows
      .map((row) => row['name'])
      .whereType<String>()
      .toSet();
  final hasCustodyTable = tables.contains(_directInboxCustodyOutboxTable);
  final hasMessagesTable = tables.contains('messages');
  if (requireCustodySchema && (!hasCustodyTable || !hasMessagesTable)) {
    throw StateError(
      'generic direct attachment custody guard requires current schema',
    );
  }
  if (hasCustodyTable) {
    final custody = await db.query(
      _directInboxCustodyOutboxTable,
      columns: const <String>['message_id'],
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (custody.isNotEmpty) return false;
  }

  if (!hasMessagesTable) return true;

  final parents = await db.query(
    'messages',
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  if (parents.isEmpty) return true;

  final parent = parents.single;
  final outgoing = ((parent['is_incoming'] as num?)?.toInt() ?? 0) == 0;
  if (!outgoing) {
    // An author's incoming tombstone is durable deletion authority. A delayed
    // generic whole-row save must never recreate an attachment behind it.
    return !_isExactIncomingAuthorTombstone(
      parent,
      senderPeerId: parent['sender_peer_id'],
    );
  }
  final canonicalOrdinary =
      ((parent['private_media_policy_version'] as num?)?.toInt() ?? -1) == 0 &&
      parent['private_media_mode'] == 'ordinary' &&
      parent['private_media_duration_seconds'] == null &&
      parent['private_media_state'] == 'none' &&
      parent['private_media_received_at_ms'] == null &&
      parent['private_media_expires_at_ms'] == null &&
      parent['private_media_revealed_at_ms'] == null &&
      parent['private_media_terminal_at_ms'] == null &&
      parent['private_media_clock_high_water_ms'] == null;
  if (!canonicalOrdinary) return true;
  final exactRemovedCompletionTombstone =
      parent['text'] == '' &&
      parent['status'] == 'inboxed' &&
      parent['edited_at'] == null &&
      parent['deleted_at'] == null &&
      parent['hidden_at'] != null &&
      parent['wire_envelope'] == null &&
      parent['transport'] == 'inbox';
  if (exactRemovedCompletionTombstone) {
    return false;
  }
  final deletedAt = parent['deleted_at'];
  final deletedByPeerId = parent['deleted_by_peer_id'];
  final exactOutgoingDeletion =
      _isNonBlankDatabaseString(deletedAt) &&
      _isNonBlankDatabaseString(deletedByPeerId) &&
      deletedByPeerId == parent['sender_peer_id'] &&
      parent['text'] == '' &&
      (_isExactV2DirectMessageDeletionEnvelope(
            parent['wire_envelope'],
            senderPeerId: parent['sender_peer_id'],
          ) ||
          (parent['status'] == 'delivered' &&
              parent['wire_envelope'] == null &&
              parent['hidden_at'] == deletedAt));
  return !exactOutgoingDeletion;
}

bool _isExactV2DirectMessageDeletionEnvelope(
  Object? rawEnvelope, {
  required Object? senderPeerId,
}) {
  if (rawEnvelope is! String) return false;
  try {
    final decoded = jsonDecode(rawEnvelope);
    if (decoded is! Map<String, dynamic>) return false;
    final encrypted = decoded['encrypted'];
    return decoded['type'] == 'message_deletion' &&
        decoded['version'] == '2' &&
        decoded['senderPeerId'] == senderPeerId &&
        encrypted is Map<String, dynamic> &&
        _isNonBlankDatabaseString(encrypted['kem']) &&
        _isNonBlankDatabaseString(encrypted['ciphertext']) &&
        _isNonBlankDatabaseString(encrypted['nonce']);
  } catch (_) {
    return false;
  }
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
      final ordinaryParent = await dbOrdinaryGroupParentPredicate(
        txn,
        groupIdExpression: 'group_messages.group_id',
      );
      final parentRows = await txn.rawQuery(
        'SELECT 1 FROM group_messages WHERE id = ? AND group_id = ? '
        'AND $ordinaryParent AND ('
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

/// Loads a bounded, newest-first set of outgoing direct-private completions
/// whose canonical completion makes its convention pending source redundant
/// and therefore eligible for retried plaintext cleanup.
///
/// The query is intentionally read-only and never accesses secure storage. It
/// returns only the persisted secure-store reference as part of the complete
/// attachment row; the repository must hydrate that reference and reject a
/// missing key before emitting a candidate. The application lifecycle adapter
/// independently requalifies the exact parent, attachment, canonical file,
/// pending path, key material, and transfer lease under the repository
/// lifecycle lock before unlinking anything.
Future<List<Map<String, Object?>>>
dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates(
  Database db, {
  int limit = 50,
}) async {
  if (limit <= 0) return const <Map<String, Object?>>[];
  final boundedLimit = limit.clamp(1, 100);
  return db.rawQuery(
    '''
      SELECT
        attachment.*,
        parent.contact_peer_id AS contact_peer_id
      FROM media_attachments AS attachment
      INNER JOIN messages AS parent ON parent.id = attachment.message_id
      WHERE attachment.owner_lane = ?
        AND attachment.download_status = 'done'
        AND attachment.size > 0
        AND attachment.local_path IS NOT NULL
        AND attachment.local_path LIKE 'media/%'
        AND attachment.content_hash IS NOT NULL
        AND length(trim(attachment.content_hash)) > 0
        AND attachment.encryption_key_base64 IS NOT NULL
        AND length(trim(attachment.encryption_key_base64)) > 0
        AND attachment.encryption_nonce IS NOT NULL
        AND length(trim(attachment.encryption_nonce)) > 0
        AND attachment.encryption_scheme IS NOT NULL
        AND length(trim(attachment.encryption_scheme)) > 0
        AND parent.is_incoming = 0
        AND parent.hidden_at IS NULL
        AND parent.deleted_at IS NULL
        AND parent.private_media_policy_version = 1
        AND parent.private_media_mode IN ('protected', 'view_once')
        AND parent.private_media_state = 'available'
        AND parent.private_media_revealed_at_ms IS NULL
        AND parent.private_media_terminal_at_ms IS NULL
      ORDER BY parent.created_at DESC, attachment.created_at DESC,
        attachment.id DESC
      LIMIT ?
    ''',
    <Object?>[MediaOwnerLane.direct.dbValue, boundedLimit],
  );
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

Future<int> _dbBeginOrdinaryGroupMediaDownloadExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required String expectedDownloadStatus,
  required String? expectedLocalPath,
  required bool explicitUserRetry,
  required String event,
}) async {
  final claimableStatuses = <String>[
    kMediaDownloadStatusPending,
    kMediaDownloadStatusDownloading,
    kMediaDownloadStatusFailed,
    if (explicitUserRetry) kMediaDownloadStatusDownloadFailed,
    if (explicitUserRetry) kMediaDownloadStatusEvicted,
  ];
  final statusPlaceholders = List<String>.filled(
    claimableStatuses.length,
    '?',
  ).join(', ');
  final retryCeiling = explicitUserRetry
      ? ''
      : 'AND COALESCE(download_retry_count, 0) < ? ';
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET download_status = ? '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND download_status = ? '
    'AND download_status IN ($statusPlaceholders) '
    '$retryCeiling'
    'AND ((local_path IS NULL AND ? IS NULL) OR local_path = ?) '
    'AND EXISTS (SELECT 1 FROM group_messages group_message_parent '
    'WHERE group_message_parent.id = media_attachments.message_id '
    'AND group_message_parent.id = ? AND group_message_parent.group_id = ? '
    'AND group_message_parent.is_incoming = 1 '
    'AND group_message_parent.media_policy_version = 0 '
    "AND group_message_parent.media_lifecycle = 'standard' "
    'AND group_message_parent.media_duration_seconds IS NULL '
    'AND group_message_parent.media_protected = 0 '
    'AND group_message_parent.media_received_at IS NULL '
    'AND group_message_parent.media_expires_at IS NULL '
    'AND group_message_parent.media_last_checked_at IS NULL '
    'AND group_message_parent.media_consumed_at IS NULL '
    'AND group_message_parent.media_expired_at IS NULL '
    'AND group_message_parent.media_cleanup_pending = 0 '
    'AND EXISTS (SELECT 1 FROM groups active_group '
    'WHERE active_group.id = group_message_parent.group_id '
    'AND active_group.self_removed_at IS NULL '
    'AND active_group.is_dissolved = 0) '
    'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions deleted '
    'WHERE deleted.message_id = group_message_parent.id '
    'AND deleted.group_id = group_message_parent.group_id)) '
    'AND NOT EXISTS (SELECT 1 FROM group_media_deletion_journal journal '
    'WHERE journal.attachment_id = media_attachments.id)',
    <Object?>[
      kMediaDownloadStatusDownloading,
      id,
      messageId,
      MediaOwnerLane.group.dbValue,
      expectedDownloadStatus,
      ...claimableStatuses,
      if (!explicitUserRetry) kMaxDownloadRetries,
      expectedLocalPath,
      expectedLocalPath,
      messageId,
      groupId,
    ],
  );
  emitFlowEvent(
    layer: 'DB',
    event: event,
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'groupId': groupId,
      'messageId': messageId,
      'affected': affected,
    },
  );
  return affected;
}

/// Claims one currently authorized ordinary incoming GROUP attachment for an
/// automatic download.
///
/// Terminal `download_failed` and user-only `evicted` are intentionally not
/// claimable here. The exact expected state/path and all parent/group/deletion
/// authority are evaluated by the same UPDATE, closing the race between a
/// recovery coordinator's read and the first bridge side effect.
Future<int> dbBeginOrdinaryGroupAutomaticMediaDownloadExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required String expectedDownloadStatus,
  required String? expectedLocalPath,
}) => _dbBeginOrdinaryGroupMediaDownloadExact(
  db,
  id,
  groupId: groupId,
  messageId: messageId,
  expectedDownloadStatus: expectedDownloadStatus,
  expectedLocalPath: expectedLocalPath,
  explicitUserRetry: false,
  event: 'MEDIA_DB_ORDINARY_GROUP_AUTOMATIC_DOWNLOAD_CLAIM',
);

/// Claims one currently authorized ordinary incoming GROUP attachment for an
/// explicit user retry.
///
/// This shares the complete automatic authority predicate, but preserves the
/// broad user retry contract by admitting `download_failed` and `evicted`
/// rows without applying the automatic retry ceiling.
Future<int> dbBeginOrdinaryGroupExplicitMediaDownloadExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required String expectedDownloadStatus,
  required String? expectedLocalPath,
}) => _dbBeginOrdinaryGroupMediaDownloadExact(
  db,
  id,
  groupId: groupId,
  messageId: messageId,
  expectedDownloadStatus: expectedDownloadStatus,
  expectedLocalPath: expectedLocalPath,
  explicitUserRetry: true,
  event: 'MEDIA_DB_ORDINARY_GROUP_EXPLICIT_DOWNLOAD_CLAIM',
);

Future<int> _dbCommitOrdinaryGroupMediaDownloadLocalPathExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required String? expectedLocalPath,
  required String localPath,
  required String event,
}) async {
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET local_path = ?, download_status = ?, '
    'download_retry_count = 0 '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND download_status = ? '
    'AND ((local_path IS NULL AND ? IS NULL) OR local_path = ?) '
    'AND EXISTS (SELECT 1 FROM group_messages group_message_parent '
    'WHERE group_message_parent.id = media_attachments.message_id '
    'AND group_message_parent.id = ? AND group_message_parent.group_id = ? '
    'AND group_message_parent.is_incoming = 1 '
    'AND group_message_parent.media_policy_version = 0 '
    "AND group_message_parent.media_lifecycle = 'standard' "
    'AND group_message_parent.media_duration_seconds IS NULL '
    'AND group_message_parent.media_protected = 0 '
    'AND group_message_parent.media_received_at IS NULL '
    'AND group_message_parent.media_expires_at IS NULL '
    'AND group_message_parent.media_last_checked_at IS NULL '
    'AND group_message_parent.media_consumed_at IS NULL '
    'AND group_message_parent.media_expired_at IS NULL '
    'AND group_message_parent.media_cleanup_pending = 0 '
    'AND EXISTS (SELECT 1 FROM groups active_group '
    'WHERE active_group.id = group_message_parent.group_id '
    'AND active_group.self_removed_at IS NULL '
    'AND active_group.is_dissolved = 0) '
    'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions deleted '
    'WHERE deleted.message_id = group_message_parent.id '
    'AND deleted.group_id = group_message_parent.group_id)) '
    'AND NOT EXISTS (SELECT 1 FROM group_media_deletion_journal journal '
    'WHERE journal.attachment_id = media_attachments.id)',
    <Object?>[
      localPath,
      kMediaDownloadStatusDone,
      id,
      messageId,
      MediaOwnerLane.group.dbValue,
      kMediaDownloadStatusDownloading,
      expectedLocalPath,
      expectedLocalPath,
      messageId,
      groupId,
    ],
  );
  emitFlowEvent(
    layer: 'DB',
    event: event,
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'groupId': groupId,
      'messageId': messageId,
      'affected': affected,
    },
  );
  return affected;
}

/// Commits one automatic ordinary GROUP download only while all authority
/// that admitted its claim is still current.
Future<int> dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required String? expectedLocalPath,
  required String localPath,
}) => _dbCommitOrdinaryGroupMediaDownloadLocalPathExact(
  db,
  id,
  groupId: groupId,
  messageId: messageId,
  expectedLocalPath: expectedLocalPath,
  localPath: localPath,
  event: 'MEDIA_DB_ORDINARY_GROUP_AUTOMATIC_DOWNLOAD_COMMIT',
);

/// Commits one explicit ordinary GROUP retry only while the same exact
/// attachment, parent, group, local-visibility, and journal authority remains
/// current.
Future<int> dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required String? expectedLocalPath,
  required String localPath,
}) => _dbCommitOrdinaryGroupMediaDownloadLocalPathExact(
  db,
  id,
  groupId: groupId,
  messageId: messageId,
  expectedLocalPath: expectedLocalPath,
  localPath: localPath,
  event: 'MEDIA_DB_ORDINARY_GROUP_EXPLICIT_DOWNLOAD_COMMIT',
);

/// Atomically records one incoming ordinary-group download failure.
///
/// This is deliberately UPDATE-only and qualifies the exact attachment tuple,
/// live ordinary incoming parent, active group, local-deletion tombstone, and
/// deletion journal in the same SQLite statement. A missing/deleted row or a
/// lost status/path authority therefore affects zero rows and can never be
/// resurrected through the generic preserving-save path.
Future<int> dbRecordOrdinaryGroupMediaDownloadFailureExact(
  Database db,
  String id, {
  required String groupId,
  required String messageId,
  required bool incrementRetryCount,
  required String failureStatus,
  required String expectedDownloadStatus,
  required String? expectedLocalPath,
  required bool clearLocalPath,
}) async {
  const allowedStatuses = {
    kMediaDownloadStatusFailed,
    kMediaDownloadStatusDownloadFailed,
    kMediaDownloadStatusIntegrityFailed,
  };
  if (!allowedStatuses.contains(failureStatus)) {
    throw ArgumentError.value(failureStatus, 'failureStatus');
  }

  final activeGroup = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_message_parent.group_id',
  );
  final activeDissolutionGuard = await dbHasSelfRemovedGroupWriteGuard(db)
      ? 'AND EXISTS (SELECT 1 FROM groups active_failure_group '
            'WHERE active_failure_group.id = group_message_parent.group_id '
            'AND active_failure_group.is_dissolved = 0) '
      : '';
  final affected = await db.rawUpdate(
    'UPDATE media_attachments SET '
    'download_status = CASE WHEN ? = 1 THEN '
    'CASE WHEN COALESCE(download_retry_count, 0) + 1 >= ? '
    'THEN ? ELSE ? END ELSE ? END, '
    'download_retry_count = CASE WHEN ? = 1 '
    'THEN COALESCE(download_retry_count, 0) + 1 '
    'ELSE download_retry_count END, '
    'local_path = CASE WHEN ? = 1 THEN NULL ELSE local_path END '
    'WHERE id = ? AND message_id = ? AND owner_lane = ? '
    'AND download_status = ? '
    'AND ((local_path IS NULL AND ? IS NULL) OR local_path = ?) '
    'AND EXISTS (SELECT 1 FROM group_messages group_message_parent '
    'WHERE group_message_parent.id = media_attachments.message_id '
    'AND group_message_parent.id = ? AND group_message_parent.group_id = ? '
    'AND group_message_parent.is_incoming = 1 '
    'AND group_message_parent.media_policy_version = 0 '
    "AND group_message_parent.media_lifecycle = 'standard' "
    'AND group_message_parent.media_duration_seconds IS NULL '
    'AND group_message_parent.media_protected = 0 '
    'AND group_message_parent.media_received_at IS NULL '
    'AND group_message_parent.media_expires_at IS NULL '
    'AND group_message_parent.media_last_checked_at IS NULL '
    'AND group_message_parent.media_consumed_at IS NULL '
    'AND group_message_parent.media_expired_at IS NULL '
    'AND group_message_parent.media_cleanup_pending = 0 '
    'AND $activeGroup '
    '$activeDissolutionGuard'
    'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions deleted '
    'WHERE deleted.message_id = group_message_parent.id '
    'AND deleted.group_id = group_message_parent.group_id)) '
    'AND NOT EXISTS (SELECT 1 FROM group_media_deletion_journal journal '
    'WHERE journal.attachment_id = media_attachments.id)',
    <Object?>[
      incrementRetryCount ? 1 : 0,
      kMaxDownloadRetries,
      kMediaDownloadStatusDownloadFailed,
      kMediaDownloadStatusFailed,
      failureStatus,
      incrementRetryCount ? 1 : 0,
      clearLocalPath ? 1 : 0,
      id,
      messageId,
      MediaOwnerLane.group.dbValue,
      expectedDownloadStatus,
      expectedLocalPath,
      expectedLocalPath,
      messageId,
      groupId,
    ],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_ORDINARY_GROUP_DOWNLOAD_FAILURE',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'groupId': groupId,
      'messageId': messageId,
      'failureStatus': failureStatus,
      'incrementRetryCount': incrementRetryCount,
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
    final count = await dbWriteTransaction(db, (txn) async {
      if (ownerLane == MediaOwnerLane.direct.dbValue) {
        final parents = await txn.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
          limit: 1,
        );
        if (parents.isNotEmpty) {
          final authority = _classifyOutgoingPrivateParentMutationAuthority(
            parents.single,
          );
          if (authority !=
              _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming) {
            // Private bulk deletion has no exact typed intent. Available-state
            // cancellation/failure uses the narrow guarded writers above;
            // terminal deletion uses dbDeleteDirectPrivateMediaAttachmentExact.
            return 0;
          }
        }
      }
      return txn.delete(
        'media_attachments',
        where: 'message_id = ? AND owner_lane = ?',
        whereArgs: [messageId, ownerLane],
      );
    });

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
      '(SELECT id FROM messages WHERE contact_peer_id = ? '
      'AND (COALESCE(private_media_policy_version, 0) = 0 '
      'OR (COALESCE(is_incoming, 0) = 0 '
      'AND private_media_policy_version = 1 '
      "AND private_media_mode = 'disappearing')))",
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
    final count = await dbWriteTransaction(db, (txn) async {
      if (ownerLane != MediaOwnerLane.direct.dbValue) {
        return txn.update(
          'media_attachments',
          const <String, Object?>{'download_status': 'upload_failed'},
          where:
              "message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
          whereArgs: <Object?>[messageId, ownerLane],
        );
      }
      final parents = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (parents.isEmpty) {
        final pendingRows = await txn.query(
          'media_attachments',
          where:
              "message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
          whereArgs: <Object?>[messageId, ownerLane],
        );
        if (pendingRows.any(
          (row) => _isExactOutgoingPrivatePendingMutationRow(
            row,
            messageId: messageId,
          ),
        )) {
          return 0;
        }
        return txn.update(
          'media_attachments',
          const <String, Object?>{'download_status': 'upload_failed'},
          where:
              "message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
          whereArgs: <Object?>[messageId, ownerLane],
        );
      }
      final authority = _classifyOutgoingPrivateParentMutationAuthority(
        parents.single,
      );
      if (authority ==
          _OutgoingPrivateParentMutationAuthority.ordinaryOrIncoming) {
        return txn.update(
          'media_attachments',
          const <String, Object?>{'download_status': 'upload_failed'},
          where:
              "message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
          whereArgs: <Object?>[messageId, ownerLane],
        );
      }
      if (authority != _OutgoingPrivateParentMutationAuthority.available) {
        return 0;
      }
      final pendingRows = await txn.query(
        'media_attachments',
        where:
            "message_id = ? AND owner_lane = ? AND download_status = 'upload_pending'",
        whereArgs: <Object?>[messageId, ownerLane],
      );
      if (pendingRows.isEmpty ||
          pendingRows.any(
            (row) => !_isExactOutgoingPrivatePendingMutationRow(
              row,
              messageId: messageId,
            ),
          )) {
        return 0;
      }
      return txn.rawUpdate(
        "UPDATE media_attachments SET download_status = 'upload_failed' "
        'WHERE message_id = ? AND owner_lane = ? '
        "AND download_status = 'upload_pending' "
        'AND EXISTS (SELECT 1 FROM messages private_parent '
        'WHERE private_parent.id = media_attachments.message_id '
        'AND private_parent.is_incoming = 0 '
        'AND private_parent.hidden_at IS NULL '
        'AND private_parent.deleted_at IS NULL '
        'AND private_parent.private_media_policy_version = 1 '
        "AND private_parent.private_media_mode IN ('protected','view_once') "
        "AND private_parent.private_media_state = 'available' "
        'AND private_parent.private_media_revealed_at_ms IS NULL '
        'AND private_parent.private_media_terminal_at_ms IS NULL)',
        <Object?>[messageId, ownerLane],
      );
    });

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
    final results = ownerLane != MediaOwnerLane.group.dbValue
        ? await db.query(
            'media_attachments',
            where: "download_status = 'upload_pending' AND owner_lane = ?",
            whereArgs: [ownerLane],
            orderBy: 'created_at ASC',
            limit: limit,
          )
        : await _loadAuthorizedGroupUploadPendingAttachments(db, limit: limit);

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

Future<List<Map<String, Object?>>> _loadAuthorizedGroupUploadPendingAttachments(
  Database db, {
  required int limit,
}) async {
  if (!await dbHasSelfRemovedGroupWriteGuard(db)) {
    return db.query(
      'media_attachments',
      where: "download_status = 'upload_pending' AND owner_lane = ?",
      whereArgs: [MediaOwnerLane.group.dbValue],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_parent.group_id',
  );
  return db.rawQuery(
    '''
SELECT attachment.*
FROM media_attachments attachment
JOIN group_messages group_parent ON group_parent.id = attachment.message_id
WHERE attachment.download_status = 'upload_pending'
  AND attachment.owner_lane = ?
  AND group_parent.status != 'send_failed'
  AND $parent
ORDER BY attachment.created_at ASC
LIMIT ?
''',
    [MediaOwnerLane.group.dbValue, limit],
  );
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

/// Loads one stable page of durable automatic GROUP download work.
///
/// Authority is applied in SQL before [limit]: only current incoming ordinary
/// parents in active groups, outside local-deletion and attachment-deletion
/// journals, may surface. The cursor is the strict `(created_at, id)` successor
/// of the last row inspected by the caller, so policy-denied rows cannot cause
/// a fixed first page to repeat forever.
Future<List<Map<String, Object?>>> dbLoadRecoverableGroupMediaDownloadPage(
  Database db, {
  required int limit,
  String? afterCreatedAt,
  String? afterAttachmentId,
}) async {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'must be positive');
  }
  final hasCreatedAt = afterCreatedAt != null;
  final hasAttachmentId = afterAttachmentId != null;
  if (hasCreatedAt != hasAttachmentId ||
      (afterCreatedAt != null && afterCreatedAt.isEmpty) ||
      (afterAttachmentId != null && afterAttachmentId.isEmpty)) {
    throw ArgumentError(
      'afterCreatedAt and afterAttachmentId must be a non-empty pair',
    );
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_RECOVERABLE_GROUP_DOWNLOADS_START',
    details: {'limit': limit, 'hasCursor': hasCreatedAt},
  );

  final cursorPredicate = hasCreatedAt
      ? 'AND (attachment.created_at > ? OR '
            '(attachment.created_at = ? AND attachment.id > ?))'
      : '';
  final cursorArguments = hasCreatedAt
      ? <Object?>[afterCreatedAt, afterCreatedAt, afterAttachmentId]
      : const <Object?>[];

  try {
    final rows = await db.rawQuery(
      '''
SELECT attachment.*, group_parent.group_id AS recovery_group_id
FROM media_attachments attachment
JOIN group_messages group_parent
  ON group_parent.id = attachment.message_id
JOIN groups active_group
  ON active_group.id = group_parent.group_id
WHERE attachment.owner_lane = ?
  AND attachment.download_status IN (?, ?, ?)
  AND COALESCE(attachment.download_retry_count, 0) < ?
  AND group_parent.is_incoming = 1
  AND group_parent.media_policy_version = 0
  AND group_parent.media_lifecycle = 'standard'
  AND group_parent.media_duration_seconds IS NULL
  AND group_parent.media_protected = 0
  AND group_parent.media_received_at IS NULL
  AND group_parent.media_expires_at IS NULL
  AND group_parent.media_last_checked_at IS NULL
  AND group_parent.media_consumed_at IS NULL
  AND group_parent.media_expired_at IS NULL
  AND group_parent.media_cleanup_pending = 0
  AND active_group.self_removed_at IS NULL
  AND active_group.is_dissolved = 0
  AND NOT EXISTS (
    SELECT 1 FROM group_message_local_deletions deleted
    WHERE deleted.message_id = group_parent.id
      AND deleted.group_id = group_parent.group_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM group_media_deletion_journal journal
    WHERE journal.attachment_id = attachment.id
  )
  $cursorPredicate
ORDER BY attachment.created_at ASC, attachment.id ASC
LIMIT ?
''',
      <Object?>[
        MediaOwnerLane.group.dbValue,
        kMediaDownloadStatusPending,
        kMediaDownloadStatusDownloading,
        kMediaDownloadStatusFailed,
        kMaxDownloadRetries,
        ...cursorArguments,
        limit,
      ],
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_RECOVERABLE_GROUP_DOWNLOADS_SUCCESS',
      details: {'count': rows.length},
    );
    return rows;
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_RECOVERABLE_GROUP_DOWNLOADS_ERROR',
      details: {'error': error.toString()},
    );
    rethrow;
  }
}

enum IncomingDirectMediaBlobDbStageOutcome {
  applied,
  idempotent,

  /// An exact ordinary incoming author tombstone already won for this target.
  /// Nothing was staged and nothing may be published, but the event is durably
  /// settled: the caller still owes its initial message receipt.
  supersededByDeletion,
  refused,
}

final class IncomingDirectMediaBlobDbStageResult {
  const IncomingDirectMediaBlobDbStageResult({
    required this.outcome,
    this.messageRow,
    this.attachmentRows = const <Map<String, Object?>>[],
  });

  const IncomingDirectMediaBlobDbStageResult.refused()
    : outcome = IncomingDirectMediaBlobDbStageOutcome.refused,
      messageRow = null,
      attachmentRows = const <Map<String, Object?>>[];

  final IncomingDirectMediaBlobDbStageOutcome outcome;
  final Map<String, Object?>? messageRow;
  final List<Map<String, Object?>> attachmentRows;
}

/// Atomically publishes a strict incoming ordinary-direct message, its exact
/// complete attachment projection, and all source-less v111 obligations.
///
/// No cache, stream, notification, delivery receipt, or inbox ACK is emitted
/// here. Callers may perform those side effects only after an applied or exact
/// idempotent result has returned.
Future<IncomingDirectMediaBlobDbStageResult>
dbStageIncomingDirectMediaBlobCustody(
  Database db, {
  required Map<String, Object?> messageRow,
  required List<Map<String, Object?>> attachmentRows,
  required List<DirectMediaBlobCustodyRow> custodyRows,
}) async {
  final messageId = messageRow['id'] as String? ?? '';
  final attachmentIds = attachmentRows
      .map((row) => row['id'] as String? ?? '')
      .toList(growable: false);
  final uniqueIds = attachmentIds.toSet();
  final custodyById = <String, DirectMediaBlobCustodyRow>{
    for (final row in custodyRows) row.attachmentId: row,
  };
  final validParent =
      messageId.trim().isNotEmpty &&
      messageRow['contact_peer_id'] == messageRow['sender_peer_id'] &&
      ((messageRow['is_incoming'] as num?)?.toInt() ?? 0) == 1 &&
      messageRow['status'] == 'delivered' &&
      messageRow['deleted_at'] == null &&
      messageRow['hidden_at'] == null &&
      ((messageRow['private_media_policy_version'] as num?)?.toInt() ?? 0) ==
          0 &&
      messageRow['private_media_mode'] == 'ordinary' &&
      messageRow['direct_media_custody_intent_id'] == null;
  final validShape =
      validParent &&
      attachmentRows.isNotEmpty &&
      attachmentRows.length == custodyRows.length &&
      uniqueIds.length == attachmentRows.length &&
      !uniqueIds.contains('') &&
      custodyById.length == custodyRows.length &&
      attachmentRows.every((attachment) {
        final id = attachment['id'] as String? ?? '';
        final custody = custodyById[id];
        return attachment['message_id'] == messageId &&
            attachment['owner_lane'] == MediaOwnerLane.direct.dbValue &&
            attachment['local_path'] == null &&
            attachment['download_status'] == kMediaDownloadStatusPending &&
            _isNonBlankDatabaseString(attachment['mime']) &&
            ((attachment['size'] as num?)?.toInt() ?? 0) > 0 &&
            _isNonBlankDatabaseString(attachment['encryption_key_base64']) &&
            _isNonBlankDatabaseString(attachment['encryption_nonce']) &&
            attachment['encryption_scheme'] == _blobAesGcmV1 &&
            custody != null &&
            custody.messageId == messageId &&
            custody.direction == DirectMediaBlobCustodyDirection.incoming &&
            custody.state == DirectMediaBlobCustodyState.incomingCommitted &&
            attachment['content_hash'] == custody.contentHash &&
            attachment['direct_media_blob_custody_fingerprint'] ==
                computeDirectMediaBlobCommitmentFingerprint(
                  attachmentId: id,
                  commitment: DirectMediaBlobCustodyCommitment(
                    kind: custody.custodyKind,
                    contract: custody.custodyContract,
                    contentHash: custody.contentHash,
                    ciphertextSize: custody.ciphertextSize,
                    transportMime: custody.transportMime,
                    expiresAtMs: custody.expiresAtMs!,
                  ),
                );
      });
  if (!validShape) {
    return const IncomingDirectMediaBlobDbStageResult.refused();
  }

  return dbWriteTransaction(db, (txn) async {
    final existingParents = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final attachmentPlaceholders = List.filled(
      attachmentIds.length,
      '?',
    ).join(',');
    final existingAttachments = await txn.rawQuery(
      'SELECT * FROM media_attachments WHERE id IN ($attachmentPlaceholders) '
      'OR (message_id = ? AND owner_lane = ?)',
      <Object?>[...attachmentIds, messageId, MediaOwnerLane.direct.dbValue],
    );
    final existingCustody = await txn.rawQuery(
      'SELECT * FROM $kDirectMediaBlobCustodyTable '
      'WHERE attachment_id IN ($attachmentPlaceholders) OR message_id = ?',
      <Object?>[...attachmentIds, messageId],
    );

    if (existingParents.length == 1 &&
        _isExactIncomingAuthorTombstone(
          existingParents.single,
          senderPeerId: messageRow['sender_peer_id'],
        )) {
      // Durable precedence, not a refusal: the deletion already won this
      // target, so no attachment row, v111 obligation, stream event, or
      // notification may be created behind it.
      return const IncomingDirectMediaBlobDbStageResult(
        outcome: IncomingDirectMediaBlobDbStageOutcome.supersededByDeletion,
      );
    }

    if (existingParents.isNotEmpty ||
        existingAttachments.isNotEmpty ||
        existingCustody.isNotEmpty) {
      if (existingParents.length != 1 ||
          !_messageDatabaseProjectionMatches(
            existingParents.single,
            messageRow,
          ) ||
          existingAttachments.length != attachmentRows.length ||
          existingCustody.length != custodyRows.length ||
          !_exactDirectMediaCustodyFailureProjection(
            existingAttachments,
            attachmentRows,
          )) {
        return const IncomingDirectMediaBlobDbStageResult.refused();
      }
      final currentCustodyById = <String, DirectMediaBlobCustodyRow>{};
      try {
        for (final raw in existingCustody) {
          final parsed = DirectMediaBlobCustodyRow.fromMap(raw);
          currentCustodyById[parsed.attachmentId] = parsed;
        }
      } on FormatException {
        return const IncomingDirectMediaBlobDbStageResult.refused();
      }
      if (!custodyRows.every((expected) {
        final current = currentCustodyById[expected.attachmentId];
        return current != null &&
            current.exactDatabaseProjectionMatches(expected);
      })) {
        return const IncomingDirectMediaBlobDbStageResult.refused();
      }
      return IncomingDirectMediaBlobDbStageResult(
        outcome: IncomingDirectMediaBlobDbStageOutcome.idempotent,
        messageRow: Map<String, Object?>.from(existingParents.single),
        attachmentRows: existingAttachments
            .map(Map<String, Object?>.from)
            .toList(growable: false),
      );
    }

    await txn.insert(
      'messages',
      messageRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    for (final attachment in attachmentRows) {
      await txn.insert(
        'media_attachments',
        attachment,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    for (final custody in custodyRows) {
      await txn.insert(
        kDirectMediaBlobCustodyTable,
        custody.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    final committedParent = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final committedAttachments = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      orderBy: 'id ASC',
    );
    final committedCustody = await txn.query(
      kDirectMediaBlobCustodyTable,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'attachment_id ASC',
    );
    if (committedParent.length != 1 ||
        !_messageDatabaseProjectionMatches(
          committedParent.single,
          messageRow,
        ) ||
        committedAttachments.length != attachmentRows.length ||
        !_exactDirectMediaCustodyFailureProjection(
          committedAttachments,
          attachmentRows,
        ) ||
        committedCustody.length != custodyRows.length) {
      throw StateError('strict incoming media stage lost atomic projection');
    }
    final committedCustodyById = <String, DirectMediaBlobCustodyRow>{
      for (final raw in committedCustody)
        DirectMediaBlobCustodyRow.fromMap(raw).attachmentId:
            DirectMediaBlobCustodyRow.fromMap(raw),
    };
    if (!custodyRows.every((expected) {
      final committed = committedCustodyById[expected.attachmentId];
      return committed != null &&
          committed.exactDatabaseProjectionMatches(expected);
    })) {
      throw StateError('strict incoming media custody changed during commit');
    }
    return IncomingDirectMediaBlobDbStageResult(
      outcome: IncomingDirectMediaBlobDbStageOutcome.applied,
      messageRow: Map<String, Object?>.from(committedParent.single),
      attachmentRows: committedAttachments
          .map(Map<String, Object?>.from)
          .toList(growable: false),
    );
  });
}

/// Atomically commits a durable strict plaintext path and, for a relay source,
/// the exact source-pinned ACK obligation. A verified LAN adoption has no
/// source and deliberately leaves the v111 row `incoming_committed`.
Future<bool> dbCommitIncomingDirectMediaBlobLocalPath(
  Database db, {
  required Map<String, Object?> expectedAttachmentRow,
  required DirectMediaBlobCustodyRow expectedCustody,
  required String localPath,
  required String? sourceRelayPeerId,
  required String updatedAt,
}) {
  final attachmentId = expectedAttachmentRow['id'] as String? ?? '';
  final messageId = expectedAttachmentRow['message_id'] as String? ?? '';
  if (attachmentId.isEmpty ||
      messageId.isEmpty ||
      localPath.trim().isEmpty ||
      localPath != localPath.trim() ||
      updatedAt.trim().isEmpty ||
      expectedAttachmentRow['owner_lane'] != MediaOwnerLane.direct.dbValue ||
      expectedCustody.attachmentId != attachmentId ||
      expectedCustody.messageId != messageId ||
      expectedCustody.state != DirectMediaBlobCustodyState.incomingCommitted ||
      (sourceRelayPeerId != null &&
          (sourceRelayPeerId.trim().isEmpty ||
              sourceRelayPeerId != sourceRelayPeerId.trim()))) {
    return Future<bool>.value(false);
  }
  final nextCustody = sourceRelayPeerId == null
      ? expectedCustody
      : expectedCustody.copyWith(
          state: DirectMediaBlobCustodyState.incomingAckPending,
          custodyRelayPeerId: sourceRelayPeerId,
          updatedAt: updatedAt,
        );

  return dbWriteTransaction(db, (txn) async {
    final parentRows = await txn.query(
      'messages',
      columns: const <String>[
        'id',
        'contact_peer_id',
        'is_incoming',
        'private_media_policy_version',
        'private_media_mode',
        'deleted_at',
        'hidden_at',
      ],
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (parentRows.length != 1 ||
        ((parentRows.single['is_incoming'] as num?)?.toInt() ?? 0) != 1 ||
        ((parentRows.single['private_media_policy_version'] as num?)?.toInt() ??
                0) !=
            0 ||
        parentRows.single['private_media_mode'] != 'ordinary' ||
        // A durable deletion or local hide already won this parent. Committing
        // plaintext behind it would resurrect the media the user removed; the
        // independent v111 obligation still converges by ACK or expiry.
        parentRows.single['deleted_at'] != null ||
        parentRows.single['hidden_at'] != null) {
      return false;
    }
    final expectedPath = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: parentRows.single['contact_peer_id']! as String,
      blobId: attachmentId,
      mime: expectedAttachmentRow['mime']! as String,
    );
    if (localPath != expectedPath) return false;

    final attachmentRows = await txn.query(
      'media_attachments',
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
      ],
      limit: 1,
    );
    final currentCustody = await dbLoadDirectMediaBlobCustodyForAttachment(
      txn,
      attachmentId: attachmentId,
    );
    if (attachmentRows.length != 1 || currentCustody == null) return false;

    final completedProjection = Map<String, Object?>.from(expectedAttachmentRow)
      ..['local_path'] = localPath
      ..['download_status'] = kMediaDownloadStatusDone
      ..['download_retry_count'] = 0;
    final alreadyCommitted =
        _messageDatabaseProjectionMatches(
          attachmentRows.single,
          completedProjection,
        ) &&
        currentCustody.exactDatabaseProjectionMatches(nextCustody);
    if (alreadyCommitted) return true;
    if (!_messageDatabaseProjectionMatches(
          attachmentRows.single,
          expectedAttachmentRow,
        ) ||
        !currentCustody.exactDatabaseProjectionMatches(expectedCustody)) {
      return false;
    }

    final attachmentChanged = await txn.rawUpdate(
      'UPDATE media_attachments SET local_path = ?, download_status = ?, '
      'download_retry_count = 0 WHERE id = ? AND message_id = ? '
      'AND owner_lane = ?',
      <Object?>[
        localPath,
        kMediaDownloadStatusDone,
        attachmentId,
        messageId,
        MediaOwnerLane.direct.dbValue,
      ],
    );
    if (attachmentChanged != 1) {
      throw StateError('strict incoming media local commit lost attachment');
    }
    if (sourceRelayPeerId != null &&
        !await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
          txn,
          expected: expectedCustody,
          next: nextCustody,
        )) {
      throw StateError('strict incoming media local commit lost ACK authority');
    }
    return true;
  });
}

/// True for a durable ordinary incoming tombstone authored by [senderPeerId].
///
/// This is the receiver-side precedence marker: an author's deletion, not a
/// local hide and not a crossed-sender row.
bool _isExactIncomingAuthorTombstone(
  Map<String, Object?> row, {
  required Object? senderPeerId,
}) =>
    ((row['is_incoming'] as num?)?.toInt() ?? 0) == 1 &&
    _isNonBlankDatabaseString(row['deleted_at']) &&
    row['deleted_by_peer_id'] == senderPeerId &&
    row['sender_peer_id'] == senderPeerId &&
    row['contact_peer_id'] == senderPeerId;

/// DB-authoritative deletion lane for one outgoing ordinary direct parent.
///
/// The parent's in-memory media list is a UI snapshot and is never authority
/// here. Only the persisted direct attachment projection, the independent v111
/// generation, and the immutable v108 row decide which owner may delete.
enum OutgoingDirectDeletionLane {
  /// No direct attachment rows: the Plan 349 text mutation owner applies.
  text,

  /// A provable strict Plan 347 lineage: the Plan 351 media owner applies.
  strictMedia,

  /// Historical fingerprint-less media without v111 authority. The legacy
  /// ordinary transport owner keeps it and never promotes it.
  legacyMedia,

  /// Crossed, partial, or ambiguous authority. Every owner fails closed.
  contradiction,
}

/// Storage result of the atomic ordinary direct-media deletion transaction.
final class DirectMediaDeletionCustodyDbStageResult {
  const DirectMediaDeletionCustodyDbStageResult({
    required this.outcome,
    this.messageRow,
    this.custodyRow,
  });

  const DirectMediaDeletionCustodyDbStageResult.refused()
    : outcome = OutgoingOrdinaryMutationOutcome.refused,
      messageRow = null,
      custodyRow = null;

  final OutgoingOrdinaryMutationOutcome outcome;
  final Map<String, Object?>? messageRow;
  final Map<String, Object?>? custodyRow;

  bool get authorizesTransport => outcome.authorizesTransport;

  /// True only while this deletion owns an exact retained v109 event.
  bool get ownsMutationEvent => custodyRow != null;
}

/// Classifies which deletion owner may act on [messageId] right now.
///
/// This is advisory only: it selects an owner and mints identity, but the
/// staging transaction repeats every predicate before it mutates anything.
Future<OutgoingDirectDeletionLane> dbClassifyOutgoingDirectDeletionLane(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final authority = await _loadDirectDeletionLaneAuthority(
    db,
    messageId: messageId,
  );
  return authority.lane;
}

/// Atomically commits the exact v111 state transition, the visible tombstone,
/// and the raw-event v109 obligation for one strict ordinary direct-media
/// delete-for-everyone.
///
/// Either all three land or none does. The helper never terminalizes, deletes,
/// or falsely acknowledges an independent v111 obligation, never retires a live
/// v108 incarnation, and never performs artifact cleanup: cleanup is a caller
/// operation that may only start after this transaction has authorized it.
///
/// [capacity] and [beforeCustodyInsertForTest] are test seams. Production uses
/// the shared 512-row default and supplies no barrier.
Future<DirectMediaDeletionCustodyDbStageResult>
dbStageOutgoingDirectMediaDeletionInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required OutgoingOrdinaryAttemptKind kind,
  required String recipientPeerId,
  required String eventId,
  required String wireEnvelope,
  required String updatedAt,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeCustodyInsertForTest,
}) {
  final classified = classifyDirectInboxEventEnvelope(wireEnvelope);
  final messageId = stagedRow['id'];
  final senderPeerId = stagedRow['sender_peer_id'];
  final createdAt = stagedRow['created_at'];
  final isDeletion =
      kind == OutgoingOrdinaryAttemptKind.tombstoneInitial ||
      kind == OutgoingOrdinaryAttemptKind.tombstoneRetry;
  final valid =
      capacity >= 0 &&
      isDeletion &&
      expectedRow != null &&
      _isNonBlankDatabaseString(recipientPeerId) &&
      _isNonBlankDatabaseString(eventId) &&
      _isNonBlankDatabaseString(updatedAt) &&
      _isNonBlankDatabaseString(messageId) &&
      _isNonBlankDatabaseString(senderPeerId) &&
      _isNonBlankDatabaseString(createdAt) &&
      DateTime.tryParse(createdAt! as String) != null &&
      classified != null &&
      classified.kind == DirectInboxEventEnvelopeKind.deletion &&
      classified.eventId == eventId &&
      classified.senderPeerId == senderPeerId &&
      expectedRow['id'] == messageId &&
      stagedRow['contact_peer_id'] == recipientPeerId &&
      stagedRow['wire_envelope'] == wireEnvelope &&
      isStrictOrdinaryOutgoingDirectPolicy(expectedRow) &&
      isStrictOrdinaryOutgoingDirectPolicy(stagedRow) &&
      isExactOutgoingDirectDeletionProjection(stagedRow);
  if (!valid) {
    return Future<DirectMediaDeletionCustodyDbStageResult>.value(
      const DirectMediaDeletionCustodyDbStageResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    // Exact replay is checked before shared capacity so an already-owned event
    // stays idempotent without replaying an older parent projection.
    final existingCustody = await txn.query(
      kDirectReactionInboxCustodyOutboxTable,
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (existingCustody.isNotEmpty) {
      final row = existingCustody.single;
      if (row['wire_envelope'] != wireEnvelope) {
        return const DirectMediaDeletionCustodyDbStageResult.refused();
      }
      final currentParents = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      return DirectMediaDeletionCustodyDbStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.idempotent,
        messageRow: currentParents.isEmpty
            ? null
            : Map<String, Object?>.from(currentParents.single),
        custodyRow: Map<String, Object?>.from(row),
      );
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $kDirectReactionInboxCustodyOutboxTable',
    );
    if (((countRows.single['count'] as num?)?.toInt() ?? 0) >= capacity) {
      return const DirectMediaDeletionCustodyDbStageResult.refused();
    }

    // The lane is re-derived here, so a drift between advisory selection and
    // this commit fails closed instead of downgrading to another owner.
    final authority = await _loadDirectDeletionLaneAuthority(
      txn,
      messageId: messageId! as String,
    );
    if (authority.lane != OutgoingDirectDeletionLane.strictMedia) {
      return const DirectMediaDeletionCustodyDbStageResult.refused();
    }

    final messageOutcome =
        await dbStageOutgoingOrdinaryAttemptWithinTransaction(
          txn,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
        );
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return DirectMediaDeletionCustodyDbStageResult(
        outcome: messageOutcome == OutgoingOrdinaryMutationOutcome.idempotent
            ? OutgoingOrdinaryMutationOutcome.refused
            : messageOutcome,
      );
    }

    for (final row in authority.cleanupTransitions) {
      final moved =
          await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
            txn,
            expected: row,
            next: row.copyWith(
              state: DirectMediaBlobCustodyState.outgoingCleanupPending,
              updatedAt: updatedAt,
            ),
          );
      if (!moved) {
        throw StateError(
          'direct media deletion lost its exact v111 generation',
        );
      }
    }

    final custodyRow = <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'event_id': eventId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
    // Test-only barrier between the parent/v111 writes and the v109 insert.
    await beforeCustodyInsertForTest?.call();
    await txn.insert(
      kDirectReactionInboxCustodyOutboxTable,
      custodyRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final committed = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (committed.length != 1) {
      throw StateError('direct media deletion lost its exact tombstone');
    }
    return DirectMediaDeletionCustodyDbStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      messageRow: Map<String, Object?>.from(committed.single),
      custodyRow: custodyRow,
    );
  });
}

/// The lane plus the exact v111 rows that must move to cleanup with the
/// tombstone. An empty transition list never means "nothing to preserve".
final class _DirectDeletionLaneAuthority {
  const _DirectDeletionLaneAuthority(
    this.lane, {
    this.cleanupTransitions = const <DirectMediaBlobCustodyRow>[],
  });

  const _DirectDeletionLaneAuthority.contradiction()
    : lane = OutgoingDirectDeletionLane.contradiction,
      cleanupTransitions = const <DirectMediaBlobCustodyRow>[];

  final OutgoingDirectDeletionLane lane;
  final List<DirectMediaBlobCustodyRow> cleanupTransitions;
}

Future<_DirectDeletionLaneAuthority> _loadDirectDeletionLaneAuthority(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final attachments = await db.query(
    'media_attachments',
    columns: const <String>['id', 'direct_media_blob_custody_fingerprint'],
    where: 'message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
    orderBy: 'id ASC',
  );
  final rawBlobRows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    orderBy: 'attachment_id ASC',
  );
  List<DirectMediaBlobCustodyRow> blobRows;
  try {
    blobRows = rawBlobRows
        .map(DirectMediaBlobCustodyRow.fromMap)
        .toList(growable: false);
  } on FormatException {
    return const _DirectDeletionLaneAuthority.contradiction();
  }

  if (attachments.isEmpty) {
    return blobRows.isEmpty
        ? const _DirectDeletionLaneAuthority(OutgoingDirectDeletionLane.text)
        : const _DirectDeletionLaneAuthority.contradiction();
  }
  if (blobRows.any(
    (row) => row.direction != DirectMediaBlobCustodyDirection.outgoing,
  )) {
    return const _DirectDeletionLaneAuthority.contradiction();
  }

  final fingerprintById = <String, String?>{
    for (final attachment in attachments)
      attachment['id']! as String:
          attachment['direct_media_blob_custody_fingerprint'] as String?,
  };
  final fingerprints = fingerprintById.values.toList(growable: false);
  final allNullFingerprints = fingerprints.every((value) => value == null);
  final allStrictFingerprints = fingerprints.every(
    (value) => _isExactLowercaseHex(value, 64),
  );
  if (!allNullFingerprints && !allStrictFingerprints) {
    return const _DirectDeletionLaneAuthority.contradiction();
  }

  final v108Rows = await db.query(
    _directInboxCustodyOutboxTable,
    columns: const <String>[
      'incarnation_id',
      'media_blob_manifest_hash',
      'media_blob_expires_at_ms',
    ],
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    limit: 2,
  );
  if (v108Rows.length > 1) {
    return const _DirectDeletionLaneAuthority.contradiction();
  }
  final v108 = v108Rows.isEmpty ? null : v108Rows.single;
  final v108ManifestHash = v108?['media_blob_manifest_hash'] as String?;
  final v108ExpiresAtMs = (v108?['media_blob_expires_at_ms'] as num?)?.toInt();

  if (blobRows.isEmpty) {
    // A manifest-bearing v108 with no v111 at all is impossible under valid
    // transitions: retirement and cleanup are atomic. Plan 353 makes this
    // shape reachable for FINGERPRINTED rows too, so the contradiction is
    // checked before the strict-lineage answer rather than after it.
    if (v108 != null && (v108ManifestHash != null || v108ExpiresAtMs != null)) {
      return const _DirectDeletionLaneAuthority.contradiction();
    }
    if (allStrictFingerprints) {
      // Every remaining row still retains a valid strict commitment digest, so
      // the strict owner keeps custody even after v111 has fully converged.
      return const _DirectDeletionLaneAuthority(
        OutgoingDirectDeletionLane.strictMedia,
      );
    }
    // No v108, or a historical unbound one continuing its original lifecycle
    // on legacy transport.
    return const _DirectDeletionLaneAuthority(
      OutgoingDirectDeletionLane.legacyMedia,
    );
  }

  // Fingerprint parity: a persisted digest must be recomputable from the exact
  // extant commitment. A different but well-formed value is a crossed proof.
  for (final row in blobRows) {
    if (!fingerprintById.containsKey(row.attachmentId)) {
      return const _DirectDeletionLaneAuthority.contradiction();
    }
    final fingerprint = fingerprintById[row.attachmentId];
    if (row.expiresAtMs == null) {
      if (fingerprint != null) {
        return const _DirectDeletionLaneAuthority.contradiction();
      }
      continue;
    }
    if (fingerprint != null &&
        fingerprint !=
            computeDirectMediaBlobCommitmentFingerprint(
              attachmentId: row.attachmentId,
              commitment: DirectMediaBlobCustodyCommitment(
                kind: row.custodyKind,
                contract: row.custodyContract,
                contentHash: row.contentHash,
                ciphertextSize: row.ciphertextSize,
                transportMime: row.transportMime,
                expiresAtMs: row.expiresAtMs!,
              ),
            )) {
      return const _DirectDeletionLaneAuthority.contradiction();
    }
  }

  final active = blobRows.every(
    (row) =>
        row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
        row.state == DirectMediaBlobCustodyState.outgoingStored,
  );
  final terminal = blobRows.every(
    (row) => row.state == DirectMediaBlobCustodyState.outgoingCleanupPending,
  );
  if (!active && !terminal) {
    return const _DirectDeletionLaneAuthority.contradiction();
  }

  if (v108 == null) {
    if (terminal) {
      // A subset left after physical cleanup is expected; those rows keep
      // their own obligations and must survive the tombstone unchanged.
      return const _DirectDeletionLaneAuthority(
        OutgoingDirectDeletionLane.strictMedia,
      );
    }
    if (blobRows.length != attachments.length ||
        blobRows.any((row) => row.inboxCustodyIncarnationId != null)) {
      return const _DirectDeletionLaneAuthority.contradiction();
    }
    return _DirectDeletionLaneAuthority(
      OutgoingDirectDeletionLane.strictMedia,
      cleanupTransitions: blobRows,
    );
  }

  final incarnationId = v108['incarnation_id'];
  if (v108ManifestHash == null ||
      v108ExpiresAtMs == null ||
      !active ||
      blobRows.length != attachments.length ||
      blobRows.any(
        (row) =>
            row.state != DirectMediaBlobCustodyState.outgoingStored ||
            row.inboxCustodyIncarnationId != incarnationId ||
            row.expiresAtMs == null,
      )) {
    return const _DirectDeletionLaneAuthority.contradiction();
  }
  final manifest = blobRows
      .map(
        (row) => DirectMediaBlobManifestProjection(
          attachmentId: row.attachmentId,
          commitment: DirectMediaBlobCustodyCommitment(
            contentHash: row.contentHash,
            ciphertextSize: row.ciphertextSize,
            expiresAtMs: row.expiresAtMs!,
          ),
        ),
      )
      .toList(growable: false);
  if (computeDirectMediaBlobManifestHash(manifest) != v108ManifestHash ||
      earliestDirectMediaBlobExpiryMs(manifest) != v108ExpiresAtMs) {
    return const _DirectDeletionLaneAuthority.contradiction();
  }
  // The live incarnation keeps its bound generation: exact v108 completion
  // still owns the transition to cleanup after this tombstone.
  return const _DirectDeletionLaneAuthority(
    OutgoingDirectDeletionLane.strictMedia,
  );
}

/// DB-authoritative caption-only EDIT lane for one outgoing ordinary direct
/// parent.
///
/// The caller's `ConversationMessage.media` is a UI snapshot and is never
/// authority here: only the persisted attachment projection, the independent
/// v111 generation, the immutable v108 row and the per-attachment lineage
/// decide whether a caption EDIT may take exact v109 custody.
enum OutgoingDirectMediaCaptionEditLane {
  /// No direct attachment rows: the Plan 349 text mutation owner applies.
  notMedia,

  /// A provable immutable strict generation: this caption owner applies.
  strictMedia,

  /// Historical fingerprint-less media without v111 authority. The legacy
  /// ordinary transport owner keeps it and never promotes it.
  legacyMedia,

  /// Crossed, partial, or ambiguous authority. Every owner fails closed.
  contradiction,
}

/// The canonical persisted parent and attachment projection a caption-only
/// EDIT must be built from.
final class OutgoingDirectMediaCaptionEditProjection {
  const OutgoingDirectMediaCaptionEditProjection({
    required this.lane,
    this.parentRow,
    this.attachmentRows = const <Map<String, Object?>>[],
  });

  const OutgoingDirectMediaCaptionEditProjection.contradiction()
    : lane = OutgoingDirectMediaCaptionEditLane.contradiction,
      parentRow = null,
      attachmentRows = const <Map<String, Object?>>[];

  final OutgoingDirectMediaCaptionEditLane lane;
  final Map<String, Object?>? parentRow;

  /// Deterministic `created_at ASC, id ASC` order.
  final List<Map<String, Object?>> attachmentRows;
}

/// Storage result of the atomic ordinary direct-media caption EDIT.
final class DirectMediaCaptionEditCustodyDbStageResult {
  const DirectMediaCaptionEditCustodyDbStageResult({
    required this.outcome,
    this.messageRow,
    this.custodyRow,
  });

  const DirectMediaCaptionEditCustodyDbStageResult.refused()
    : outcome = OutgoingOrdinaryMutationOutcome.refused,
      messageRow = null,
      custodyRow = null;

  final OutgoingOrdinaryMutationOutcome outcome;
  final Map<String, Object?>? messageRow;
  final Map<String, Object?>? custodyRow;

  bool get authorizesTransport => outcome.authorizesTransport;

  /// True only while this caption EDIT owns an exact retained v109 event.
  bool get ownsMutationEvent => custodyRow != null;
}

/// Loads the persisted classification and canonical projection for a
/// caption-only EDIT of [messageId].
///
/// This is advisory only: the staging transaction below re-derives every
/// predicate before it mutates anything, so a lane that drifts between
/// selection and commit fails closed there instead of downgrading.
Future<OutgoingDirectMediaCaptionEditProjection>
dbLoadOutgoingDirectMediaCaptionEditProjection(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final authority = await _loadDirectCaptionEditAuthority(
    db,
    messageId: messageId,
  );
  return OutgoingDirectMediaCaptionEditProjection(
    lane: authority.lane,
    parentRow: authority.parentRow,
    attachmentRows: authority.attachmentRows,
  );
}

/// Atomically commits one caption-only EDIT of a strict ordinary direct-media
/// parent: the exact edit-attempt projection, any provable null-to-exact
/// lineage stamps, and one raw-event v109 obligation.
///
/// Either all of them land or none does. Nothing here transitions, cancels,
/// acknowledges, re-encrypts, uploads or deletes a v111 obligation, retires a
/// live v108 incarnation, or rewrites a single attachment descriptor: the
/// persisted media generation is immutable across a caption EDIT.
///
/// [expectedAttachmentRows] carries ONLY deterministic storage-reference
/// expectations derived by the repository outside this transaction. Raw
/// encryption keys are hydrated under the media lifecycle lock and never
/// reach SQLite.
///
/// [capacity] and [beforeCustodyInsertForTest] are test seams. Production uses
/// the shared 512-row default and supplies no barrier.
Future<DirectMediaCaptionEditCustodyDbStageResult>
dbStageOutgoingDirectMediaCaptionEditInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required OutgoingOrdinaryAttemptKind kind,
  required String recipientPeerId,
  required String eventId,
  required String wireEnvelope,
  required List<Map<String, Object?>> expectedAttachmentRows,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeCustodyInsertForTest,
}) {
  final classified = classifyDirectInboxEventEnvelope(wireEnvelope);
  final messageId = stagedRow['id'];
  final senderPeerId = stagedRow['sender_peer_id'];
  final createdAt = stagedRow['created_at'];
  final valid =
      capacity >= 0 &&
      kind == OutgoingOrdinaryAttemptKind.edit &&
      expectedRow != null &&
      expectedAttachmentRows.isNotEmpty &&
      _isNonBlankDatabaseString(recipientPeerId) &&
      _isNonBlankDatabaseString(eventId) &&
      _isNonBlankDatabaseString(messageId) &&
      _isNonBlankDatabaseString(senderPeerId) &&
      _isNonBlankDatabaseString(createdAt) &&
      DateTime.tryParse(createdAt! as String) != null &&
      classified != null &&
      classified.kind == DirectInboxEventEnvelopeKind.edit &&
      classified.eventId == eventId &&
      classified.senderPeerId == senderPeerId &&
      classified.targetMessageId == messageId &&
      expectedRow['id'] == messageId &&
      stagedRow['contact_peer_id'] == recipientPeerId &&
      stagedRow['wire_envelope'] == wireEnvelope &&
      _isNonBlankDatabaseString(stagedRow['edited_at']) &&
      stagedRow['deleted_at'] == null &&
      stagedRow['deleted_by_peer_id'] == null &&
      stagedRow['hidden_at'] == null &&
      isStrictOrdinaryOutgoingDirectPolicy(expectedRow) &&
      isStrictOrdinaryOutgoingDirectPolicy(stagedRow);
  if (!valid) {
    return Future<DirectMediaCaptionEditCustodyDbStageResult>.value(
      const DirectMediaCaptionEditCustodyDbStageResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    // Exact replay is checked before shared capacity so an already-owned event
    // stays idempotent without replaying an older parent projection.
    final existingCustody = await txn.query(
      kDirectReactionInboxCustodyOutboxTable,
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (existingCustody.isNotEmpty) {
      final row = existingCustody.single;
      if (row['wire_envelope'] != wireEnvelope) {
        return const DirectMediaCaptionEditCustodyDbStageResult.refused();
      }
      final currentParents = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      return DirectMediaCaptionEditCustodyDbStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.idempotent,
        messageRow: currentParents.isEmpty
            ? null
            : Map<String, Object?>.from(currentParents.single),
        custodyRow: Map<String, Object?>.from(row),
      );
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $kDirectReactionInboxCustodyOutboxTable',
    );
    if (((countRows.single['count'] as num?)?.toInt() ?? 0) >= capacity) {
      return const DirectMediaCaptionEditCustodyDbStageResult.refused();
    }

    // FULL prevalidation before the first write: the lane, the canonical
    // projection and the caller's storage-reference expectations must all
    // still agree, or nothing changes.
    final authority = await _loadDirectCaptionEditAuthority(
      txn,
      messageId: messageId! as String,
    );
    if (authority.lane != OutgoingDirectMediaCaptionEditLane.strictMedia ||
        !_matchesStorageReferenceExpectations(
          persisted: authority.attachmentRows,
          expected: expectedAttachmentRows,
        )) {
      return const DirectMediaCaptionEditCustodyDbStageResult.refused();
    }

    final messageOutcome =
        await dbStageOutgoingOrdinaryAttemptWithinTransaction(
          txn,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
          allowDirectAttachments: true,
        );
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return DirectMediaCaptionEditCustodyDbStageResult(
        outcome: messageOutcome == OutgoingOrdinaryMutationOutcome.idempotent
            ? OutgoingOrdinaryMutationOutcome.refused
            : messageOutcome,
      );
    }

    // The last point at which the complete bound generation is still provable
    // gets its already-proven per-attachment digests. A lost CAS throws so the
    // shared transaction rolls the caption and the v109 insert back with it.
    if (authority.stampableBlobRows.isNotEmpty &&
        !await dbStampExactStrictOutgoingLineageWithinTransaction(
          txn,
          messageId: messageId as String,
          strictBlobRows: authority.stampableBlobRows,
        )) {
      throw StateError('direct media caption edit lost its exact lineage');
    }

    final custodyRow = <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'event_id': eventId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
    // Test-only barrier between the parent/lineage writes and the v109 insert.
    await beforeCustodyInsertForTest?.call();
    await txn.insert(
      kDirectReactionInboxCustodyOutboxTable,
      custodyRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final committed = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (committed.length != 1) {
      throw StateError('direct media caption edit lost its exact parent');
    }
    return DirectMediaCaptionEditCustodyDbStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      messageRow: Map<String, Object?>.from(committed.single),
      custodyRow: custodyRow,
    );
  });
}

/// Durable disposition of one incoming ordinary direct-media caption EDIT.
enum IncomingDirectMediaCaptionEditOutcome {
  /// The caption and its monotonic editedAt became durable.
  applied,

  /// The exact same caption/editedAt is already durable.
  durableReplay,

  /// A newer edit or an author tombstone already won. The event is settled.
  superseded,

  /// The original is absent or hidden and NOT deleted. Nothing was written and
  /// the caller retains its exact envelope for a later replay.
  missingOriginal,

  /// A live pre-353 all-null/no-v111 parent. The caller resumes its existing
  /// generic media-edit path unchanged.
  legacyParent,

  /// Crossed, partial or ambiguous authority. Nothing changed and there is no
  /// generic fallback.
  refused,
}

/// Result of the atomic incoming caption apply.
final class IncomingDirectMediaCaptionEditDbResult {
  const IncomingDirectMediaCaptionEditDbResult({
    required this.outcome,
    this.messageRow,
  });

  const IncomingDirectMediaCaptionEditDbResult.refused()
    : outcome = IncomingDirectMediaCaptionEditOutcome.refused,
      messageRow = null;

  final IncomingDirectMediaCaptionEditOutcome outcome;
  final Map<String, Object?>? messageRow;

  /// True for every outcome that settles the sender's event durably.
  bool get isDurable =>
      outcome == IncomingDirectMediaCaptionEditOutcome.applied ||
      outcome == IncomingDirectMediaCaptionEditOutcome.durableReplay ||
      outcome == IncomingDirectMediaCaptionEditOutcome.superseded;
}

/// Conditionally applies one incoming caption-only EDIT over an exact
/// immutable strict media descriptor set.
///
/// Only `text` and `edited_at` may change. Status, transport, read and
/// lifecycle fields, every attachment descriptor and every v111 row are
/// preserved. An author tombstone is classified first as durable supersession;
/// an absent or hidden nondeleted original writes NOTHING so the caller's
/// exact retained envelope stays the retry owner.
Future<IncomingDirectMediaCaptionEditDbResult>
dbApplyIncomingDirectMediaCaptionEdit(
  Database db, {
  required Map<String, Object?> expectedParentIdentity,
  required List<Map<String, Object?>> expectedAttachmentRows,
  required String text,
  required String editedAt,
}) {
  final messageId = expectedParentIdentity['id'];
  final senderPeerId = expectedParentIdentity['sender_peer_id'];
  if (!_isNonBlankDatabaseString(messageId) ||
      !_isNonBlankDatabaseString(senderPeerId) ||
      !_isNonBlankDatabaseString(editedAt) ||
      DateTime.tryParse(editedAt) == null ||
      expectedAttachmentRows.isEmpty) {
    return Future<IncomingDirectMediaCaptionEditDbResult>.value(
      const IncomingDirectMediaCaptionEditDbResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final rows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const IncomingDirectMediaCaptionEditDbResult(
        outcome: IncomingDirectMediaCaptionEditOutcome.missingOriginal,
      );
    }
    final current = rows.single;

    // Deletion precedence is decided BEFORE hidden/missing handling: an exact
    // author tombstone is durable supersession, never a deferral.
    if (_isExactIncomingAuthorTombstone(current, senderPeerId: senderPeerId)) {
      return IncomingDirectMediaCaptionEditDbResult(
        outcome: IncomingDirectMediaCaptionEditOutcome.superseded,
        messageRow: Map<String, Object?>.from(current),
      );
    }
    if (current['hidden_at'] != null || current['deleted_at'] != null) {
      // A hidden NONDELETED original cannot prove this caption's authority.
      // Write nothing; the caller's exact envelope remains retryable.
      return const IncomingDirectMediaCaptionEditDbResult(
        outcome: IncomingDirectMediaCaptionEditOutcome.missingOriginal,
      );
    }

    if (((current['is_incoming'] as num?)?.toInt() ?? 0) != 1 ||
        current['sender_peer_id'] != senderPeerId ||
        current['contact_peer_id'] !=
            expectedParentIdentity['contact_peer_id'] ||
        current['timestamp'] != expectedParentIdentity['timestamp'] ||
        current['quoted_message_id'] !=
            expectedParentIdentity['quoted_message_id'] ||
        current['dedup_key'] != expectedParentIdentity['dedup_key'] ||
        ((current['is_forwarded'] as num?)?.toInt() ?? 0) !=
            ((expectedParentIdentity['is_forwarded'] as num?)?.toInt() ?? 0) ||
        !_isOrdinaryIncomingMediaPolicy(current)) {
      return const IncomingDirectMediaCaptionEditDbResult.refused();
    }

    final lane = await _classifyIncomingCaptionEditAuthority(
      txn,
      messageId: messageId! as String,
      expectedAttachmentRows: expectedAttachmentRows,
    );
    switch (lane) {
      case _IncomingCaptionEditLane.refused:
        return const IncomingDirectMediaCaptionEditDbResult.refused();
      case _IncomingCaptionEditLane.legacy:
        return IncomingDirectMediaCaptionEditDbResult(
          outcome: IncomingDirectMediaCaptionEditOutcome.legacyParent,
          messageRow: Map<String, Object?>.from(current),
        );
      case _IncomingCaptionEditLane.strict:
        break;
    }

    final currentEditedAt = current['edited_at'] as String?;
    if (current['text'] == text && currentEditedAt == editedAt) {
      return IncomingDirectMediaCaptionEditDbResult(
        outcome: IncomingDirectMediaCaptionEditOutcome.durableReplay,
        messageRow: Map<String, Object?>.from(current),
      );
    }
    if (currentEditedAt != null) {
      final incoming = DateTime.tryParse(editedAt);
      final durable = DateTime.tryParse(currentEditedAt);
      if (incoming == null || durable == null) {
        return const IncomingDirectMediaCaptionEditDbResult.refused();
      }
      if (!incoming.isAfter(durable)) {
        return IncomingDirectMediaCaptionEditDbResult(
          outcome: IncomingDirectMediaCaptionEditOutcome.superseded,
          messageRow: Map<String, Object?>.from(current),
        );
      }
    }

    final changed = await txn.update(
      'messages',
      <String, Object?>{'text': text, 'edited_at': editedAt},
      where:
          'id = ? AND is_incoming = 1 AND sender_peer_id = ? '
          'AND deleted_at IS NULL AND hidden_at IS NULL '
          'AND ${currentEditedAt == null ? 'edited_at IS NULL' : 'edited_at = ?'}',
      whereArgs: <Object?>[messageId, senderPeerId, ?currentEditedAt],
    );
    if (changed != 1) {
      throw StateError('incoming media caption edit lost its exact parent');
    }
    final committed = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    return IncomingDirectMediaCaptionEditDbResult(
      outcome: IncomingDirectMediaCaptionEditOutcome.applied,
      messageRow: Map<String, Object?>.from(committed.single),
    );
  });
}

enum _IncomingCaptionEditLane { strict, legacy, refused }

/// Incoming authority: all-exact fingerprints plus an absent or exact-subset
/// incoming v111 set whose state is exactly committed or ack-pending.
Future<_IncomingCaptionEditLane> _classifyIncomingCaptionEditAuthority(
  DatabaseExecutor txn, {
  required String messageId,
  required List<Map<String, Object?>> expectedAttachmentRows,
}) async {
  final attachments = await txn.query(
    'media_attachments',
    where: 'message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
    orderBy: 'created_at ASC, id ASC',
  );
  if (attachments.isEmpty) return _IncomingCaptionEditLane.refused;

  final rawBlobRows = await txn.query(
    kDirectMediaBlobCustodyTable,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    orderBy: 'attachment_id ASC',
  );
  List<DirectMediaBlobCustodyRow> blobRows;
  try {
    blobRows = rawBlobRows
        .map(DirectMediaBlobCustodyRow.fromMap)
        .toList(growable: false);
  } on FormatException {
    return _IncomingCaptionEditLane.refused;
  }

  final fingerprints = attachments
      .map((row) => row['direct_media_blob_custody_fingerprint'] as String?)
      .toList(growable: false);
  final allNull = fingerprints.every((value) => value == null);
  final allExact = fingerprints.every(
    (value) => _isExactLowercaseHex(value, 64),
  );
  if (!allNull && !allExact) return _IncomingCaptionEditLane.refused;

  if (allNull) {
    // A live pre-353 parent keeps its unchanged generic media-edit path, but
    // only while no v111 obligation claims otherwise.
    return blobRows.isEmpty
        ? _IncomingCaptionEditLane.legacy
        : _IncomingCaptionEditLane.refused;
  }

  final attachmentIds = <String>{};
  for (final row in attachments) {
    final id = row['id'];
    if (id is! String || !attachmentIds.add(id)) {
      return _IncomingCaptionEditLane.refused;
    }
  }
  for (final row in blobRows) {
    if (row.direction != DirectMediaBlobCustodyDirection.incoming ||
        !attachmentIds.contains(row.attachmentId) ||
        (row.state != DirectMediaBlobCustodyState.incomingCommitted &&
            row.state != DirectMediaBlobCustodyState.incomingAckPending)) {
      return _IncomingCaptionEditLane.refused;
    }
  }

  return _matchesStorageReferenceExpectations(
        persisted: attachments,
        expected: expectedAttachmentRows,
      )
      ? _IncomingCaptionEditLane.strict
      : _IncomingCaptionEditLane.refused;
}

/// The lane plus the canonical projection and the v111 rows whose exact
/// lineage this transaction may still stamp.
final class _DirectCaptionEditAuthority {
  const _DirectCaptionEditAuthority(
    this.lane, {
    this.parentRow,
    this.attachmentRows = const <Map<String, Object?>>[],
    this.stampableBlobRows = const <DirectMediaBlobCustodyRow>[],
  });

  const _DirectCaptionEditAuthority.contradiction()
    : lane = OutgoingDirectMediaCaptionEditLane.contradiction,
      parentRow = null,
      attachmentRows = const <Map<String, Object?>>[],
      stampableBlobRows = const <DirectMediaBlobCustodyRow>[];

  final OutgoingDirectMediaCaptionEditLane lane;
  final Map<String, Object?>? parentRow;
  final List<Map<String, Object?>> attachmentRows;
  final List<DirectMediaBlobCustodyRow> stampableBlobRows;
}

Future<_DirectCaptionEditAuthority> _loadDirectCaptionEditAuthority(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final parents = await db.query(
    'messages',
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  if (parents.isEmpty) {
    return const _DirectCaptionEditAuthority.contradiction();
  }
  final parent = Map<String, Object?>.from(parents.single);
  if (!isStrictOrdinaryOutgoingDirectPolicy(parent) ||
      parent['deleted_at'] != null ||
      parent['deleted_by_peer_id'] != null ||
      parent['hidden_at'] != null) {
    return const _DirectCaptionEditAuthority.contradiction();
  }

  // Deterministic canonical order. A tied created_at resolves through id.
  final attachments = await db.query(
    'media_attachments',
    where: 'message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
    orderBy: 'created_at ASC, id ASC',
  );
  final rawBlobRows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    orderBy: 'attachment_id ASC',
  );
  List<DirectMediaBlobCustodyRow> blobRows;
  try {
    blobRows = rawBlobRows
        .map(DirectMediaBlobCustodyRow.fromMap)
        .toList(growable: false);
  } on FormatException {
    return const _DirectCaptionEditAuthority.contradiction();
  }

  if (attachments.isEmpty) {
    return blobRows.isEmpty
        ? _DirectCaptionEditAuthority(
            OutgoingDirectMediaCaptionEditLane.notMedia,
            parentRow: parent,
          )
        : const _DirectCaptionEditAuthority.contradiction();
  }
  if (blobRows.any(
    (row) => row.direction != DirectMediaBlobCustodyDirection.outgoing,
  )) {
    return const _DirectCaptionEditAuthority.contradiction();
  }

  final fingerprintById = <String, String?>{};
  for (final attachment in attachments) {
    final id = attachment['id'];
    if (id is! String || fingerprintById.containsKey(id)) {
      return const _DirectCaptionEditAuthority.contradiction();
    }
    fingerprintById[id] =
        attachment['direct_media_blob_custody_fingerprint'] as String?;
  }
  final fingerprints = fingerprintById.values.toList(growable: false);
  final allNullFingerprints = fingerprints.every((value) => value == null);
  final allExactFingerprints = fingerprints.every(
    (value) => _isExactLowercaseHex(value, 64),
  );
  if (!allNullFingerprints && !allExactFingerprints) {
    return const _DirectCaptionEditAuthority.contradiction();
  }

  final v108Rows = await db.query(
    _directInboxCustodyOutboxTable,
    columns: const <String>[
      'incarnation_id',
      'media_blob_manifest_hash',
      'media_blob_expires_at_ms',
    ],
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    limit: 2,
  );
  if (v108Rows.length > 1) {
    return const _DirectCaptionEditAuthority.contradiction();
  }
  final v108 = v108Rows.isEmpty ? null : v108Rows.single;
  final v108ManifestHash = v108?['media_blob_manifest_hash'] as String?;
  final v108ExpiresAtMs = (v108?['media_blob_expires_at_ms'] as num?)?.toInt();

  _DirectCaptionEditAuthority strict({
    List<DirectMediaBlobCustodyRow> stampable = const [],
  }) => _DirectCaptionEditAuthority(
    OutgoingDirectMediaCaptionEditLane.strictMedia,
    parentRow: parent,
    attachmentRows: attachments,
    stampableBlobRows: stampable,
  );

  if (blobRows.isEmpty) {
    // v108 retirement and v111 cleanup are atomic, so a manifest-bearing v108
    // with no generation at all is impossible however the digests look.
    if (v108 != null && (v108ManifestHash != null || v108ExpiresAtMs != null)) {
      return const _DirectCaptionEditAuthority.contradiction();
    }
    // Fully drained but still provable, or the exact historical shape.
    return allExactFingerprints
        ? strict()
        : _DirectCaptionEditAuthority(
            OutgoingDirectMediaCaptionEditLane.legacyMedia,
            parentRow: parent,
            attachmentRows: attachments,
          );
  }

  // Every extant row must carry a provable commitment, and a persisted digest
  // must be recomputable from it. A different well-formed value is crossed.
  for (final row in blobRows) {
    if (!fingerprintById.containsKey(row.attachmentId) ||
        row.expiresAtMs == null) {
      return const _DirectCaptionEditAuthority.contradiction();
    }
    final fingerprint = fingerprintById[row.attachmentId];
    if (fingerprint != null &&
        fingerprint !=
            computeDirectMediaBlobCommitmentFingerprint(
              attachmentId: row.attachmentId,
              commitment: DirectMediaBlobCustodyCommitment(
                kind: row.custodyKind,
                contract: row.custodyContract,
                contentHash: row.contentHash,
                ciphertextSize: row.ciphertextSize,
                transportMime: row.transportMime,
                expiresAtMs: row.expiresAtMs!,
              ),
            )) {
      return const _DirectCaptionEditAuthority.contradiction();
    }
  }

  final complete = blobRows.length == attachments.length;
  final terminal = blobRows.every(
    (row) => row.state == DirectMediaBlobCustodyState.outgoingCleanupPending,
  );

  if (v108 == null) {
    if (!terminal) {
      // An active generation with no v108 is still mid-acquisition: a caption
      // EDIT cannot prove that this is the immutable published generation.
      return const _DirectCaptionEditAuthority.contradiction();
    }
    if (complete) {
      return strict(stampable: allNullFingerprints ? blobRows : const []);
    }
    // A subset left after physical cleanup is only provable when every
    // physical attachment already carries its own exact digest.
    return allExactFingerprints
        ? strict()
        : const _DirectCaptionEditAuthority.contradiction();
  }

  final incarnationId = v108['incarnation_id'];
  if (v108ManifestHash == null ||
      v108ExpiresAtMs == null ||
      !complete ||
      blobRows.any(
        (row) =>
            row.state != DirectMediaBlobCustodyState.outgoingStored ||
            row.inboxCustodyIncarnationId != incarnationId,
      )) {
    return const _DirectCaptionEditAuthority.contradiction();
  }
  final manifest = blobRows
      .map(
        (row) => DirectMediaBlobManifestProjection(
          attachmentId: row.attachmentId,
          commitment: DirectMediaBlobCustodyCommitment(
            contentHash: row.contentHash,
            ciphertextSize: row.ciphertextSize,
            expiresAtMs: row.expiresAtMs!,
          ),
        ),
      )
      .toList(growable: false);
  if (computeDirectMediaBlobManifestHash(manifest) != v108ManifestHash ||
      earliestDirectMediaBlobExpiryMs(manifest) != v108ExpiresAtMs) {
    return const _DirectCaptionEditAuthority.contradiction();
  }
  return strict(stampable: allNullFingerprints ? blobRows : const []);
}

/// The exact immutable identity every caption EDIT must agree on, keyed by
/// attachment id. Only storage-reference values are compared: raw keys are
/// hydrated outside SQLite and never enter this boundary.
const _captionEditImmutableAttachmentColumns = <String>[
  'content_hash',
  'encryption_key_base64',
  'encryption_nonce',
  'encryption_scheme',
];

bool _matchesStorageReferenceExpectations({
  required List<Map<String, Object?>> persisted,
  required List<Map<String, Object?>> expected,
}) {
  if (persisted.length != expected.length || persisted.isEmpty) return false;
  final persistedById = <String, Map<String, Object?>>{};
  for (final row in persisted) {
    final id = row['id'];
    if (id is! String || persistedById.containsKey(id)) return false;
    persistedById[id] = row;
  }
  final seen = <String>{};
  for (final row in expected) {
    final id = row['id'];
    if (id is! String || !seen.add(id)) return false;
    final actual = persistedById[id];
    if (actual == null) return false;
    for (final column in _captionEditImmutableAttachmentColumns) {
      if (actual[column] != row[column]) return false;
    }
  }
  return seen.length == persistedById.length;
}

/// The ordinary incoming media policy a caption EDIT may apply over. Private,
/// view-once and disappearing rows keep their own owners.
bool _isOrdinaryIncomingMediaPolicy(Map<String, Object?> row) =>
    (row['private_media_policy_version'] as num?)?.toInt() == 0 &&
    (row['private_media_mode'] as String? ?? 'ordinary') == 'ordinary' &&
    row['private_media_duration_seconds'] == null &&
    (row['private_media_state'] as String? ?? 'none') == 'none' &&
    row['direct_media_custody_intent_id'] == null;
