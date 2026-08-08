import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/direct_media_blob_custody.dart';
import '../../media/direct_media_blob_terminalization.dart';
import '../../media/group_media_integrity_policy.dart'
    show kMediaDownloadStatusDone, kMediaDownloadStatusDownloadFailed;
import '../../media/media_owner_lane.dart';
import '../db_write_transaction.dart';
import '../direct_media_blob_custody.dart';

const String kDirectMediaBlobCustodyTable = 'direct_media_blob_custody';
const int kDirectMediaBlobCustodyMaxLoadBatch = 50;

enum DirectMediaBlobCustodyBatchStageOutcome { applied, idempotent, refused }

/// Atomically publishes one complete initial custody generation.
///
/// Every row must belong to one message/direction and be either
/// `outgoing_prepared` or `incoming_committed`. A partial pre-existing batch is
/// refused; only an exact complete replay is idempotent. This lets both sender
/// and receiver owners establish all-or-zero authority before any side effect.
Future<DirectMediaBlobCustodyBatchStageOutcome>
dbStageInitialDirectMediaBlobCustodyBatch(
  Database db, {
  required List<DirectMediaBlobCustodyRow> rows,
}) {
  if (!_isValidInitialBatch(rows)) {
    return Future<DirectMediaBlobCustodyBatchStageOutcome>.value(
      DirectMediaBlobCustodyBatchStageOutcome.refused,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final attachmentIds = rows
        .map((row) => row.attachmentId)
        .toList(growable: false);
    final current = await _loadRowsByAttachmentIds(txn, attachmentIds);
    if (current.isNotEmpty) {
      if (current.length != rows.length) {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      final currentById = <String, DirectMediaBlobCustodyRow>{};
      try {
        for (final raw in current) {
          final parsed = DirectMediaBlobCustodyRow.fromMap(raw);
          currentById[parsed.attachmentId] = parsed;
        }
      } on FormatException {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      final exact = rows.every((candidate) {
        final existing = currentById[candidate.attachmentId];
        return existing != null &&
            existing.exactDatabaseProjectionMatches(candidate);
      });
      return exact
          ? DirectMediaBlobCustodyBatchStageOutcome.idempotent
          : DirectMediaBlobCustodyBatchStageOutcome.refused;
    }

    for (final row in rows) {
      await txn.insert(
        kDirectMediaBlobCustodyTable,
        row.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    final committed = await _loadRowsByAttachmentIds(txn, attachmentIds);
    if (committed.length != rows.length) {
      throw StateError('direct-media blob custody batch lost rows at commit');
    }
    final committedById = <String, DirectMediaBlobCustodyRow>{
      for (final raw in committed)
        DirectMediaBlobCustodyRow.fromMap(raw).attachmentId:
            DirectMediaBlobCustodyRow.fromMap(raw),
    };
    if (!rows.every((candidate) {
      final stored = committedById[candidate.attachmentId];
      return stored != null && stored.exactDatabaseProjectionMatches(candidate);
    })) {
      throw StateError('direct-media blob custody batch changed during commit');
    }
    return DirectMediaBlobCustodyBatchStageOutcome.applied;
  });
}

Future<DirectMediaBlobCustodyRow?> dbLoadDirectMediaBlobCustodyForAttachment(
  DatabaseExecutor db, {
  required String attachmentId,
}) async {
  if (attachmentId.trim().isEmpty) return null;
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'attachment_id = ?',
    whereArgs: <Object?>[attachmentId],
    limit: 1,
  );
  return rows.isEmpty ? null : DirectMediaBlobCustodyRow.fromMap(rows.single);
}

Future<List<DirectMediaBlobCustodyRow>> dbLoadDirectMediaBlobCustodyForMessage(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  if (messageId.trim().isEmpty) return const [];
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    orderBy: 'direction ASC, attachment_id ASC',
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

/// Loads a bounded deterministic state page for lifecycle/bootstrap drains.
Future<List<DirectMediaBlobCustodyRow>> dbLoadDirectMediaBlobCustodyByStates(
  DatabaseExecutor db, {
  required Set<DirectMediaBlobCustodyState> states,
  int limit = kDirectMediaBlobCustodyMaxLoadBatch,
}) async {
  if (states.isEmpty || limit <= 0) return const [];
  final orderedStates = states.map((state) => state.dbValue).toList()..sort();
  final placeholders = List.filled(orderedStates.length, '?').join(',');
  final bounded = math.min(limit, kDirectMediaBlobCustodyMaxLoadBatch);
  final rows = await db.rawQuery(
    'SELECT * FROM $kDirectMediaBlobCustodyTable '
    'WHERE state IN ($placeholders) '
    'ORDER BY next_attempt_at ASC, updated_at ASC, attachment_id ASC LIMIT ?',
    <Object?>[...orderedStates, bounded],
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

/// Applies one allowed exact state transition under its own write transaction.
Future<bool> dbTransitionDirectMediaBlobCustodyIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
  required DirectMediaBlobCustodyRow next,
}) {
  // The standalone transition is intentionally narrow: upload proof and
  // incoming ACK-progress owners may update their row, but message-wide
  // cleanup authority and v108 binding are available only to the dedicated
  // transaction-composable owners below.
  if (next.state == DirectMediaBlobCustodyState.outgoingCleanupPending ||
      expected.inboxCustodyIncarnationId != next.inboxCustodyIncarnationId) {
    return Future<bool>.value(false);
  }
  return dbWriteTransaction(
    db,
    (txn) => dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
      txn,
      expected: expected,
      next: next,
    ),
  );
}

/// Transaction-composable form used when a media/message/v108 mutation must
/// commit with the custody transition. The caller owns rollback of a `false`
/// result alongside its other writes.
Future<bool> dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
  DatabaseExecutor txn, {
  required DirectMediaBlobCustodyRow expected,
  required DirectMediaBlobCustodyRow next,
}) async {
  if (!expected.canTransitionTo(next)) return false;
  final current = await dbLoadDirectMediaBlobCustodyForAttachment(
    txn,
    attachmentId: expected.attachmentId,
  );
  if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
    return false;
  }

  final nextMap = Map<String, Object?>.from(next.toMap())
    ..remove('attachment_id');
  final changed = await txn.update(
    kDirectMediaBlobCustodyTable,
    nextMap,
    where: 'attachment_id = ? AND state = ?',
    whereArgs: <Object?>[expected.attachmentId, expected.state.dbValue],
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
  if (changed != 1) return false;

  final committed = await dbLoadDirectMediaBlobCustodyForAttachment(
    txn,
    attachmentId: expected.attachmentId,
  );
  if (committed == null || !committed.exactDatabaseProjectionMatches(next)) {
    throw StateError('direct-media blob custody transition lost exact state');
  }
  return true;
}

final class _DirectMediaBlobTerminalizationRollback implements Exception {
  const _DirectMediaBlobTerminalizationRollback();
}

/// Atomically retires one complete outgoing generation without v108 custody.
///
/// The caller must provide the exact, complete current generation. The helper
/// re-reads the whole message-wide v111 set inside the transaction, proves
/// exact v108 absence, qualifies one explicit terminal reason, and publishes
/// every row as `outgoing_cleanup_pending` together. Artifact unlinking is a
/// later lifecycle operation and may never precede this commit.
Future<DirectMediaBlobTerminalizationOutcome>
dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact(
  Database db, {
  required List<DirectMediaBlobCustodyRow> expectedRows,
  required DirectMediaBlobTerminalizationReason reason,
  required int nowMs,
}) async {
  if (nowMs <= 0 || !_isValidOutgoingTerminalizationBatch(expectedRows)) {
    return DirectMediaBlobTerminalizationOutcome.refused;
  }
  final messageId = expectedRows.first.messageId;

  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadDirectMediaBlobCustodyForMessage(
        txn,
        messageId: messageId,
      );
      if (current.length != expectedRows.length) {
        return DirectMediaBlobTerminalizationOutcome.refused;
      }
      final expectedById = <String, DirectMediaBlobCustodyRow>{
        for (final row in expectedRows) row.attachmentId: row,
      };
      if (!current.every((row) {
        final expected = expectedById[row.attachmentId];
        return expected != null && row.exactDatabaseProjectionMatches(expected);
      })) {
        return DirectMediaBlobTerminalizationOutcome.refused;
      }

      if (current.every(
        (row) =>
            row.state == DirectMediaBlobCustodyState.outgoingCleanupPending,
      )) {
        return DirectMediaBlobTerminalizationOutcome.alreadyTerminal;
      }
      if (current.any(
        (row) =>
            row.state != DirectMediaBlobCustodyState.outgoingPrepared &&
            row.state != DirectMediaBlobCustodyState.outgoingStored,
      )) {
        return DirectMediaBlobTerminalizationOutcome.refused;
      }

      final v108Rows = await txn.query(
        'direct_inbox_custody_outbox',
        columns: const <String>['message_id', 'incarnation_id'],
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        limit: 2,
      );
      if (v108Rows.isNotEmpty) {
        if (v108Rows.length != 1) {
          return DirectMediaBlobTerminalizationOutcome.refused;
        }
        final incarnationId = v108Rows.single['incarnation_id'] as String?;
        final exactV108Owner =
            incarnationId != null &&
            current.every(
              (row) =>
                  row.state == DirectMediaBlobCustodyState.outgoingStored &&
                  row.inboxCustodyIncarnationId == incarnationId,
            );
        return exactV108Owner
            ? DirectMediaBlobTerminalizationOutcome.blockedByV108
            : DirectMediaBlobTerminalizationOutcome.refused;
      }

      // A missing v108 row does not authorize cleanup of a formerly bound
      // generation. That contradiction must fail closed for the atomic v108
      // completion owner to reconcile.
      if (current.any((row) => row.inboxCustodyIncarnationId != null)) {
        return DirectMediaBlobTerminalizationOutcome.refused;
      }

      final eligible = switch (reason) {
        DirectMediaBlobTerminalizationReason.explicitCancellation => true,
        DirectMediaBlobTerminalizationReason.parentDeletedOrMissing =>
          await _outgoingDirectMediaBlobParentIsDeletedOrMissing(
            txn,
            messageId: messageId,
          ),
        DirectMediaBlobTerminalizationReason.expiredUnboundProof => current.any(
          (row) =>
              row.state == DirectMediaBlobCustodyState.outgoingStored &&
              row.expiresAtMs != null &&
              row.expiresAtMs! <= nowMs,
        ),
      };
      if (!eligible) {
        return DirectMediaBlobTerminalizationOutcome.refused;
      }

      final updatedAt = DateTime.fromMillisecondsSinceEpoch(
        nowMs,
        isUtc: true,
      ).toIso8601String();
      final nextRows = current
          .map(
            (row) => row.copyWith(
              state: DirectMediaBlobCustodyState.outgoingCleanupPending,
              updatedAt: updatedAt,
            ),
          )
          .toList(growable: false);
      for (var index = 0; index < current.length; index++) {
        final changed =
            await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
              txn,
              expected: current[index],
              next: nextRows[index],
            );
        if (!changed) throw const _DirectMediaBlobTerminalizationRollback();
      }

      final committed = await dbLoadDirectMediaBlobCustodyForMessage(
        txn,
        messageId: messageId,
      );
      final nextById = <String, DirectMediaBlobCustodyRow>{
        for (final row in nextRows) row.attachmentId: row,
      };
      if (committed.length != nextRows.length ||
          !committed.every((row) {
            final next = nextById[row.attachmentId];
            return next != null && row.exactDatabaseProjectionMatches(next);
          })) {
        throw StateError(
          'direct-media blob terminalization lost complete generation',
        );
      }
      return DirectMediaBlobTerminalizationOutcome.applied;
    });
  } on _DirectMediaBlobTerminalizationRollback {
    return DirectMediaBlobTerminalizationOutcome.refused;
  }
}

/// Removes an outgoing artifact row only after an owner has durably published
/// the exact `outgoing_cleanup_pending` authority and verified file absence.
Future<bool> dbDeleteDirectMediaBlobCleanupPendingIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
}) {
  if (expected.state != DirectMediaBlobCustodyState.outgoingCleanupPending) {
    return Future<bool>.value(false);
  }
  return dbWriteTransaction(db, (txn) async {
    final current = await dbLoadDirectMediaBlobCustodyForAttachment(
      txn,
      attachmentId: expected.attachmentId,
    );
    if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
      return false;
    }
    final deleted = await txn.delete(
      kDirectMediaBlobCustodyTable,
      where: 'attachment_id = ? AND state = ?',
      whereArgs: <Object?>[
        expected.attachmentId,
        DirectMediaBlobCustodyState.outgoingCleanupPending.dbValue,
      ],
    );
    return deleted == 1;
  });
}

/// Retires a strict incoming ACK obligation only after the native owner has
/// returned an exact `acked` or `already_acked` result from its persisted
/// source relay.
Future<bool> dbDeleteIncomingDirectMediaBlobAckPendingIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
}) {
  if (expected.state != DirectMediaBlobCustodyState.incomingAckPending) {
    return Future<bool>.value(false);
  }
  return _deleteIncomingDirectMediaBlobIfExact(
    db,
    expected: expected,
    terminalizeAttachment: false,
  );
}

/// Expiry convergence for source-less LAN adoption and retained ACK retries.
/// The persisted relay expiry is the sole clock bound; callers cannot retire a
/// live obligation by supplying a synthetic result.
Future<bool> dbDeleteIncomingDirectMediaBlobIfExpired(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
  required int nowMs,
}) {
  if (expected.direction != DirectMediaBlobCustodyDirection.incoming ||
      expected.expiresAtMs == null ||
      nowMs < expected.expiresAtMs!) {
    return Future<bool>.value(false);
  }
  return _deleteIncomingDirectMediaBlobIfExact(
    db,
    expected: expected,
    terminalizeAttachment: true,
  );
}

Future<bool> _deleteIncomingDirectMediaBlobIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
  required bool terminalizeAttachment,
}) => dbWriteTransaction(db, (txn) async {
  final current = await dbLoadDirectMediaBlobCustodyForAttachment(
    txn,
    attachmentId: expected.attachmentId,
  );
  if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
    return false;
  }
  final commitmentFingerprint = computeDirectMediaBlobCommitmentFingerprint(
    attachmentId: expected.attachmentId,
    commitment: DirectMediaBlobCustodyCommitment(
      kind: expected.custodyKind,
      contract: expected.custodyContract,
      contentHash: expected.contentHash,
      ciphertextSize: expected.ciphertextSize,
      transportMime: expected.transportMime,
      expiresAtMs: expected.expiresAtMs!,
    ),
  );
  final attachmentRows = await txn.query(
    'media_attachments',
    columns: const <String>[
      'id',
      'message_id',
      'owner_lane',
      'local_path',
      'download_status',
      'direct_media_blob_custody_fingerprint',
    ],
    where: 'id = ?',
    whereArgs: <Object?>[expected.attachmentId],
    limit: 1,
  );
  if (attachmentRows.isNotEmpty) {
    final attachment = attachmentRows.single;
    if (attachment['message_id'] != expected.messageId ||
        attachment['owner_lane'] != MediaOwnerLane.direct.dbValue ||
        attachment['direct_media_blob_custody_fingerprint'] !=
            commitmentFingerprint) {
      return false;
    }
    if (terminalizeAttachment) {
      final hasDurableLocalCopy =
          attachment['download_status'] == kMediaDownloadStatusDone &&
          attachment['local_path'] is String &&
          (attachment['local_path'] as String).isNotEmpty;
      final nextStatus = hasDurableLocalCopy
          ? kMediaDownloadStatusDone
          : kMediaDownloadStatusDownloadFailed;
      final changed = await txn.rawUpdate(
        'UPDATE media_attachments SET download_status = ? '
        'WHERE id = ? AND message_id = ? AND owner_lane = ? '
        'AND direct_media_blob_custody_fingerprint = ?',
        <Object?>[
          nextStatus,
          expected.attachmentId,
          expected.messageId,
          MediaOwnerLane.direct.dbValue,
          commitmentFingerprint,
        ],
      );
      if (changed != 1) {
        throw StateError(
          'strict incoming expiry lost durable attachment terminalization',
        );
      }
    }
  }
  final deleted = await txn.delete(
    kDirectMediaBlobCustodyTable,
    where: 'attachment_id = ? AND state = ?',
    whereArgs: <Object?>[expected.attachmentId, expected.state.dbValue],
  );
  if (deleted != 1 && terminalizeAttachment && attachmentRows.isNotEmpty) {
    throw StateError('strict incoming expiry lost exact v111 retirement');
  }
  return deleted == 1;
});

bool _isValidInitialBatch(List<DirectMediaBlobCustodyRow> rows) {
  if (rows.isEmpty) return false;
  final first = rows.first;
  final expectedState =
      first.direction == DirectMediaBlobCustodyDirection.outgoing
      ? DirectMediaBlobCustodyState.outgoingPrepared
      : DirectMediaBlobCustodyState.incomingCommitted;
  if (first.state != expectedState) return false;
  final ids = <String>{};
  return rows.every(
    (row) =>
        row.messageId == first.messageId &&
        row.direction == first.direction &&
        row.state == expectedState &&
        ids.add(row.attachmentId),
  );
}

Future<List<Map<String, Object?>>> _loadRowsByAttachmentIds(
  DatabaseExecutor db,
  List<String> attachmentIds,
) {
  final placeholders = List.filled(attachmentIds.length, '?').join(',');
  return db.rawQuery(
    'SELECT * FROM $kDirectMediaBlobCustodyTable '
    'WHERE attachment_id IN ($placeholders) ORDER BY attachment_id ASC',
    attachmentIds,
  );
}

bool _isValidOutgoingTerminalizationBatch(
  List<DirectMediaBlobCustodyRow> rows,
) {
  if (rows.isEmpty) return false;
  final first = rows.first;
  final ids = <String>{};
  final active = rows.every(
    (row) =>
        row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
        row.state == DirectMediaBlobCustodyState.outgoingStored,
  );
  final terminal = rows.every(
    (row) => row.state == DirectMediaBlobCustodyState.outgoingCleanupPending,
  );
  return first.direction == DirectMediaBlobCustodyDirection.outgoing &&
      (active || terminal) &&
      rows.every(
        (row) =>
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.messageId == first.messageId &&
            ids.add(row.attachmentId),
      );
}

Future<bool> _outgoingDirectMediaBlobParentIsDeletedOrMissing(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final parents = await db.query(
    'messages',
    columns: const <String>['id', 'hidden_at', 'deleted_at'],
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 2,
  );
  return parents.isEmpty ||
      (parents.length == 1 &&
          (parents.single['hidden_at'] != null ||
              parents.single['deleted_at'] != null));
}
