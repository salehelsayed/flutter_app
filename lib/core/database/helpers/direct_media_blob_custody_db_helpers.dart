import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/direct_media_blob_custody.dart';
import '../../media/direct_media_blob_terminalization.dart';
import '../../media/group_media_integrity_policy.dart'
    show kMediaDownloadStatusDone, kMediaDownloadStatusDownloadFailed;
import '../../media/group_media_blob_custody.dart'
    show computeGroupMediaBlobCustodyFingerprint;
import '../../media/media_owner_lane.dart';
import '../db_write_transaction.dart';
import '../direct_media_blob_custody.dart';

const String kDirectMediaBlobCustodyTable = 'direct_media_blob_custody';
const int kDirectMediaBlobCustodyMaxLoadBatch = 50;

enum DirectMediaBlobCustodyBatchStageOutcome { applied, idempotent, refused }

/// The lane-generalized v115 natural exact row identity.
///
/// Direct callers retain the v114 defaults: `(direct, NULL, attachment_id,
/// attachment_id, direction, recipient_peer_id)`. Group callers additionally
/// bind the exact group owner and relay custody blob ID. Incoming rows keep a
/// null [recipientPeerId].
final class DirectMediaBlobCustodyNaturalKey {
  DirectMediaBlobCustodyNaturalKey({
    required this.attachmentId,
    this.ownerLane = MediaBlobCustodyOwnerLane.direct,
    this.groupId,
    String? custodyBlobId,
    required this.direction,
    required this.recipientPeerId,
  }) : custodyBlobId = custodyBlobId ?? attachmentId {
    final outgoing = direction == DirectMediaBlobCustodyDirection.outgoing;
    if (outgoing != (recipientPeerId != null)) {
      throw ArgumentError(
        'outgoing custody identity requires a recipient; incoming forbids one',
      );
    }
    if ((ownerLane == MediaBlobCustodyOwnerLane.direct && groupId != null) ||
        (ownerLane == MediaBlobCustodyOwnerLane.group &&
            (groupId == null || groupId!.trim().isEmpty)) ||
        this.custodyBlobId.trim().isEmpty) {
      throw ArgumentError('invalid lane-qualified custody identity');
    }
  }

  DirectMediaBlobCustodyNaturalKey.ofRow(DirectMediaBlobCustodyRow row)
    : this(
        attachmentId: row.attachmentId,
        ownerLane: row.ownerLane,
        groupId: row.groupId,
        custodyBlobId: row.custodyBlobId,
        direction: row.direction,
        recipientPeerId: row.recipientPeerId,
      );

  final String attachmentId;
  final MediaBlobCustodyOwnerLane ownerLane;
  final String? groupId;
  final String custodyBlobId;
  final DirectMediaBlobCustodyDirection direction;
  final String? recipientPeerId;

  @override
  bool operator ==(Object other) =>
      other is DirectMediaBlobCustodyNaturalKey &&
      other.attachmentId == attachmentId &&
      other.ownerLane == ownerLane &&
      other.groupId == groupId &&
      other.custodyBlobId == custodyBlobId &&
      other.direction == direction &&
      other.recipientPeerId == recipientPeerId;

  @override
  int get hashCode => Object.hash(
    attachmentId,
    ownerLane,
    groupId,
    custodyBlobId,
    direction,
    recipientPeerId,
  );
}

/// Atomically publishes one complete initial custody generation.
///
/// Every row must belong to one message/direction and be either
/// `outgoing_prepared` or `incoming_committed`; under v114 an outgoing
/// generation may carry several exact `(attachment, recipient)` target rows
/// per canonical attachment. A partial pre-existing batch is refused; only an
/// exact complete replay is idempotent. This lets both sender and receiver
/// owners establish all-or-zero authority before any side effect.
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

  return dbWriteTransaction(
    db,
    (txn) => dbStageInitialDirectMediaBlobCustodyBatchWithinTransaction(
      txn,
      rows: rows,
    ),
  );
}

/// Transaction-composable form of [dbStageInitialDirectMediaBlobCustodyBatch]
/// used when the caller must commit the generation together with the durable
/// no-remint generation marker and target-snapshot requalification.
Future<DirectMediaBlobCustodyBatchStageOutcome>
dbStageInitialDirectMediaBlobCustodyBatchWithinTransaction(
  DatabaseExecutor txn, {
  required List<DirectMediaBlobCustodyRow> rows,
}) async {
  if (!_isValidInitialBatch(rows)) {
    return DirectMediaBlobCustodyBatchStageOutcome.refused;
  }
  final attachmentIds = rows
      .map((row) => row.attachmentId)
      .toSet()
      .toList(growable: false);
  final current = await _loadRowsByAttachmentIds(txn, attachmentIds);
  if (current.isNotEmpty) {
    if (current.length != rows.length) {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    final currentByKey =
        <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{};
    try {
      for (final raw in current) {
        final parsed = DirectMediaBlobCustodyRow.fromMap(raw);
        currentByKey[DirectMediaBlobCustodyNaturalKey.ofRow(parsed)] = parsed;
      }
    } on FormatException {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    } on ArgumentError {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    final exact = rows.every((candidate) {
      final existing =
          currentByKey[DirectMediaBlobCustodyNaturalKey.ofRow(candidate)];
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
  final committedByKey =
      <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{};
  for (final raw in committed) {
    final parsed = DirectMediaBlobCustodyRow.fromMap(raw);
    committedByKey[DirectMediaBlobCustodyNaturalKey.ofRow(parsed)] = parsed;
  }
  if (!rows.every((candidate) {
    final stored =
        committedByKey[DirectMediaBlobCustodyNaturalKey.ofRow(candidate)];
    return stored != null && stored.exactDatabaseProjectionMatches(candidate);
  })) {
    throw StateError('direct-media blob custody batch changed during commit');
  }
  return DirectMediaBlobCustodyBatchStageOutcome.applied;
}

/// Generic canonical-attachment lookup. Under v114 one attachment may own
/// several exact target rows, so this can only ever return the complete list;
/// exact-row owners must use [dbLoadDirectMediaBlobCustodyForTarget].
Future<List<DirectMediaBlobCustodyRow>>
dbLoadDirectMediaBlobCustodyRowsForAttachment(
  DatabaseExecutor db, {
  required String attachmentId,
}) async {
  if (attachmentId.trim().isEmpty) return const [];
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'owner_lane = ? AND attachment_id = ?',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.direct.dbValue,
      attachmentId,
    ],
    orderBy: 'direction ASC, recipient_peer_id ASC',
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

/// Exact natural-identity lookup: `(attachmentId, direction,
/// recipientPeerId)`, with `recipientPeerId == null` selecting the sole
/// incoming row. It never selects an arbitrary sibling.
Future<DirectMediaBlobCustodyRow?> dbLoadDirectMediaBlobCustodyForTarget(
  DatabaseExecutor db, {
  required String attachmentId,
  required DirectMediaBlobCustodyDirection direction,
  String? recipientPeerId,
}) async {
  final outgoing = direction == DirectMediaBlobCustodyDirection.outgoing;
  if (attachmentId.trim().isEmpty ||
      outgoing != (recipientPeerId != null) ||
      (recipientPeerId != null && recipientPeerId.trim().isEmpty)) {
    return null;
  }
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: outgoing
        ? 'owner_lane = ? AND attachment_id = ? AND direction = ? '
              'AND recipient_peer_id = ? AND custody_blob_id = attachment_id'
        : 'owner_lane = ? AND attachment_id = ? AND direction = ? '
              'AND recipient_peer_id IS NULL '
              'AND custody_blob_id = attachment_id',
    whereArgs: outgoing
        ? <Object?>[
            MediaBlobCustodyOwnerLane.direct.dbValue,
            attachmentId,
            direction.dbValue,
            recipientPeerId,
          ]
        : <Object?>[
            MediaBlobCustodyOwnerLane.direct.dbValue,
            attachmentId,
            direction.dbValue,
          ],
    limit: 2,
  );
  if (rows.isEmpty) return null;
  if (rows.length > 1) {
    throw StateError(
      'direct-media blob custody natural identity yielded siblings',
    );
  }
  return DirectMediaBlobCustodyRow.fromMap(rows.single);
}

Future<List<DirectMediaBlobCustodyRow>> dbLoadDirectMediaBlobCustodyForMessage(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  if (messageId.trim().isEmpty) return const [];
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'owner_lane = ? AND message_id = ?',
    whereArgs: <Object?>[MediaBlobCustodyOwnerLane.direct.dbValue, messageId],
    orderBy: 'direction ASC, attachment_id ASC, recipient_peer_id ASC',
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
    'WHERE owner_lane = ? AND state IN ($placeholders) '
    'ORDER BY next_attempt_at ASC, updated_at ASC, attachment_id ASC, '
    'recipient_peer_id ASC LIMIT ?',
    <Object?>[
      MediaBlobCustodyOwnerLane.direct.dbValue,
      ...orderedStates,
      bounded,
    ],
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

/// 362: the exact LINKED-scoped state page the restricted linked runtime
/// drains, so a linked secondary never touches rows it does not own.
///
/// The scope is DIRECTION-DEPENDENT, and the difference is load-bearing:
///
/// * OUTGOING rows are per-target, and only a linked generation carries a
///   logical `contact_account_peer_id`. Historical/single-target rows authored
///   by the primary must stay invisible here, so they are filtered out.
/// * INCOMING rows are inherently device-local — a linked secondary's database
///   contains only the rows that device itself received — so there is nothing
///   to filter and NO marker predicate is applied. Filtering incoming rows on
///   `contact_account_peer_id IS NOT NULL` would be a correctness bug, not a
///   restriction: that marker records that the SENDER's transport differed
///   from the logical contact (see `dbStageIncomingDirectMediaBlobCustody`),
///   so media arriving from an ordinary single-device contact is staged with a
///   NULL marker and would never be drained or downloaded at all.
Future<List<DirectMediaBlobCustodyRow>>
dbLoadLinkedDirectMediaBlobCustodyByStates(
  DatabaseExecutor db, {
  required Set<DirectMediaBlobCustodyState> states,
  int limit = kDirectMediaBlobCustodyMaxLoadBatch,
}) async {
  if (states.isEmpty || limit <= 0) return const [];
  final orderedStates = states.map((state) => state.dbValue).toList()..sort();
  final placeholders = List.filled(orderedStates.length, '?').join(',');
  final bounded = math.min(limit, kDirectMediaBlobCustodyMaxLoadBatch);
  final outgoingStates = orderedStates
      .where((state) => state.startsWith('outgoing'))
      .toList();
  // Only the outgoing arm is narrowed; see the direction note above.
  final linkedScope = outgoingStates.isEmpty
      ? ''
      : 'AND (state NOT IN (${List.filled(outgoingStates.length, '?').join(',')}) '
            'OR contact_account_peer_id IS NOT NULL) ';
  final rows = await db.rawQuery(
    'SELECT * FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND state IN ($placeholders) '
    '$linkedScope'
    'ORDER BY next_attempt_at ASC, updated_at ASC, attachment_id ASC, '
    'recipient_peer_id ASC LIMIT ?',
    <Object?>[
      MediaBlobCustodyOwnerLane.direct.dbValue,
      ...orderedStates,
      ...outgoingStates,
      bounded,
    ],
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
///
/// The transition touches exactly one natural `(attachment, direction,
/// recipient)` row; sibling target rows of the same attachment are never
/// selected, matched, or modified.
Future<bool> dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
  DatabaseExecutor txn, {
  required DirectMediaBlobCustodyRow expected,
  required DirectMediaBlobCustodyRow next,
}) async {
  if (!expected.canTransitionTo(next)) return false;
  final current = await dbLoadDirectMediaBlobCustodyForTarget(
    txn,
    attachmentId: expected.attachmentId,
    direction: expected.direction,
    recipientPeerId: expected.recipientPeerId,
  );
  if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
    return false;
  }

  final nextMap = Map<String, Object?>.from(next.toMap())
    ..remove('attachment_id')
    ..remove('owner_lane')
    ..remove('group_id')
    ..remove('custody_blob_id')
    ..remove('direction')
    ..remove('recipient_peer_id');
  final outgoing =
      expected.direction == DirectMediaBlobCustodyDirection.outgoing;
  final changed = await txn.update(
    kDirectMediaBlobCustodyTable,
    nextMap,
    where: outgoing
        ? 'owner_lane = ? AND group_id IS NULL AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id = ? AND state = ?'
        : 'owner_lane = ? AND group_id IS NULL AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id IS NULL AND state = ?',
    whereArgs: outgoing
        ? <Object?>[
            MediaBlobCustodyOwnerLane.direct.dbValue,
            expected.attachmentId,
            expected.custodyBlobId,
            expected.direction.dbValue,
            expected.recipientPeerId,
            expected.state.dbValue,
          ]
        : <Object?>[
            MediaBlobCustodyOwnerLane.direct.dbValue,
            expected.attachmentId,
            expected.custodyBlobId,
            expected.direction.dbValue,
            expected.state.dbValue,
          ],
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
  if (changed != 1) return false;

  final committed = await dbLoadDirectMediaBlobCustodyForTarget(
    txn,
    attachmentId: expected.attachmentId,
    direction: expected.direction,
    recipientPeerId: expected.recipientPeerId,
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
/// The caller must provide the exact, complete current generation — under
/// v114 that is every `(attachment, recipient)` target row of the message.
/// The helper re-reads the whole message-wide v111 set inside the
/// transaction, proves exact v108 absence, qualifies one explicit terminal
/// reason, and publishes every row as `outgoing_cleanup_pending` together; it
/// may never retire target A while staging only surviving B. Artifact
/// unlinking is a later lifecycle operation and may never precede this
/// commit.
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
      final expectedByKey =
          <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{
            for (final row in expectedRows)
              DirectMediaBlobCustodyNaturalKey.ofRow(row): row,
          };
      if (!current.every((row) {
        final expected =
            expectedByKey[DirectMediaBlobCustodyNaturalKey.ofRow(row)];
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
        columns: const <String>[
          'message_id',
          'recipient_peer_id',
          'incarnation_id',
        ],
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );
      if (v108Rows.isNotEmpty) {
        return _wholeGenerationIsExactlyBoundToV108(
              current: current,
              v108Rows: v108Rows,
            )
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
      final nextByKey =
          <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{
            for (final row in nextRows)
              DirectMediaBlobCustodyNaturalKey.ofRow(row): row,
          };
      if (committed.length != nextRows.length ||
          !committed.every((row) {
            final next = nextByKey[DirectMediaBlobCustodyNaturalKey.ofRow(row)];
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

/// True only when every current row is `outgoing_stored` and every persisted
/// v108 sibling exactly owns its recipient's complete target rows. A partial
/// or crossed binding fails closed so the atomic v108 completion owner (or a
/// per-target drain) reconciles instead of a broad terminalization.
bool _wholeGenerationIsExactlyBoundToV108({
  required List<DirectMediaBlobCustodyRow> current,
  required List<Map<String, Object?>> v108Rows,
}) {
  if (current.any(
    (row) => row.state != DirectMediaBlobCustodyState.outgoingStored,
  )) {
    return false;
  }
  final incarnationByRecipient = <String, String>{};
  for (final v108 in v108Rows) {
    final incarnationId = v108['incarnation_id'] as String?;
    if (incarnationId == null) return false;
    final recipient =
        (v108['recipient_peer_id'] as String?) ?? _legacyRecipientSentinel;
    if (incarnationByRecipient.containsKey(recipient)) return false;
    incarnationByRecipient[recipient] = incarnationId;
  }
  final custodyRecipients = current
      .map((row) => row.recipientPeerId)
      .whereType<String>()
      .toSet();
  if (v108Rows.length == 1 &&
      (v108Rows.single['recipient_peer_id'] as String?) != null &&
      custodyRecipients.length == 1) {
    // Legacy single-target shape: the sole v108 row names the sole target.
    final incarnation = v108Rows.single['incarnation_id'] as String?;
    return current.every((row) => row.inboxCustodyIncarnationId == incarnation);
  }
  if (custodyRecipients.length != incarnationByRecipient.length ||
      incarnationByRecipient.containsKey(_legacyRecipientSentinel)) {
    return false;
  }
  return current.every((row) {
    final incarnation = incarnationByRecipient[row.recipientPeerId];
    return incarnation != null && row.inboxCustodyIncarnationId == incarnation;
  });
}

const String _legacyRecipientSentinel = '\u0000legacy-null-recipient';

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
    final current = await dbLoadDirectMediaBlobCustodyForTarget(
      txn,
      attachmentId: expected.attachmentId,
      direction: expected.direction,
      recipientPeerId: expected.recipientPeerId,
    );
    if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
      return false;
    }
    final deleted = await txn.delete(
      kDirectMediaBlobCustodyTable,
      where:
          'owner_lane = ? AND group_id IS NULL AND attachment_id = ? '
          'AND custody_blob_id = ? AND direction = ? '
          'AND recipient_peer_id = ? AND state = ?',
      whereArgs: <Object?>[
        MediaBlobCustodyOwnerLane.direct.dbValue,
        expected.attachmentId,
        expected.custodyBlobId,
        expected.direction.dbValue,
        expected.recipientPeerId,
        DirectMediaBlobCustodyState.outgoingCleanupPending.dbValue,
      ],
    );
    return deleted == 1;
  });
}

/// Counts sibling v111 rows (any state, any direction) still referencing the
/// exact `(path, contentHash, ciphertextSize)` artifact proof, excluding the
/// one row identified by [excluding]. The shared encrypted artifact may be
/// unlinked only when this returns zero, under the incumbent media lifecycle
/// lock.
Future<int> dbCountOtherDirectMediaBlobCustodyRowsReferencingArtifact(
  DatabaseExecutor db, {
  required String ciphertextRelativePath,
  required String contentHash,
  required int ciphertextSize,
  required DirectMediaBlobCustodyNaturalKey excluding,
}) async {
  if (ciphertextRelativePath.trim().isEmpty) return 0;
  final outgoing =
      excluding.direction == DirectMediaBlobCustodyDirection.outgoing;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND group_id IS NULL '
    'AND ciphertext_relative_path = ? AND content_hash = ? '
    'AND ciphertext_size = ? '
    'AND NOT (attachment_id = ? AND direction = ? AND '
    '${outgoing ? 'recipient_peer_id = ?' : 'recipient_peer_id IS NULL'})',
    <Object?>[
      MediaBlobCustodyOwnerLane.direct.dbValue,
      ciphertextRelativePath,
      contentHash,
      ciphertextSize,
      excluding.attachmentId,
      excluding.direction.dbValue,
      if (outgoing) excluding.recipientPeerId,
    ],
  );
  return (rows.single['n'] as num).toInt();
}

/// Stages group custody plus each attachment's one-way no-demotion digest in
/// one caller-owned transaction. The parent and descriptors must already be
/// visible in [txn], allowing protected receive to compose this helper with
/// event, attention and notification writes without nesting a transaction.
Future<DirectMediaBlobCustodyBatchStageOutcome>
dbStageGroupMediaBlobCustodyWithinTransaction(
  DatabaseExecutor txn, {
  String? groupId,
  String? messageId,
  Map<String, String> custodyBlobIdsByAttachmentId = const <String, String>{},
  required List<Map<String, Object?>> attachmentRows,
  required List<DirectMediaBlobCustodyRow> custodyRows,
}) async {
  final resolvedGroupId =
      groupId ?? (custodyRows.isEmpty ? null : custodyRows.first.groupId);
  final resolvedMessageId =
      messageId ?? (custodyRows.isEmpty ? null : custodyRows.first.messageId);
  if (resolvedGroupId == null ||
      resolvedGroupId.trim().isEmpty ||
      resolvedMessageId == null ||
      resolvedMessageId.trim().isEmpty ||
      (custodyRows.isNotEmpty && !_isValidInitialGroupBatch(custodyRows)) ||
      attachmentRows.isEmpty) {
    return DirectMediaBlobCustodyBatchStageOutcome.refused;
  }
  final attachmentById = <String, Map<String, Object?>>{};
  for (final attachment in attachmentRows) {
    final id = attachment['id'];
    if (id is! String ||
        id.trim().isEmpty ||
        attachmentById.containsKey(id) ||
        attachment['message_id'] != resolvedMessageId ||
        attachment['owner_lane'] != 'group') {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    attachmentById[id] = attachment;
  }
  if (custodyRows.any(
        (row) =>
            row.groupId != resolvedGroupId ||
            row.messageId != resolvedMessageId ||
            !attachmentById.containsKey(row.attachmentId),
      ) ||
      (custodyRows.isNotEmpty &&
          attachmentById.keys.any(
            (id) => !custodyRows.any((row) => row.attachmentId == id),
          )) ||
      custodyBlobIdsByAttachmentId.entries.any(
        (entry) =>
            !attachmentById.containsKey(entry.key) ||
            entry.value.trim().isEmpty ||
            entry.value != entry.value.trim(),
      )) {
    return DirectMediaBlobCustodyBatchStageOutcome.refused;
  }

  final fingerprints = <String, String>{};
  var allFingerprintsAlreadyExact = true;
  for (final entry in attachmentById.entries) {
    final rows = custodyRows
        .where((row) => row.attachmentId == entry.key)
        .toList(growable: false);
    final expectedFingerprint =
        entry.value['group_media_blob_custody_fingerprint'];
    if (expectedFingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedFingerprint)) {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    if (rows.isNotEmpty &&
        rows.first.direction == DirectMediaBlobCustodyDirection.outgoing) {
      final firstRow = rows.first;
      String recomputed;
      try {
        recomputed = computeGroupMediaBlobCustodyFingerprint(
          groupId: resolvedGroupId,
          messageId: resolvedMessageId,
          attachmentId: entry.key,
          custodyBlobId: firstRow.custodyBlobId,
          contentHash: firstRow.contentHash,
          ciphertextSize: firstRow.ciphertextSize,
          recipientPeerIds: rows.map((row) => row.recipientPeerId!),
        );
      } on Object {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      if (recomputed != expectedFingerprint ||
          rows.any(
            (row) =>
                row.custodyBlobId != firstRow.custodyBlobId ||
                row.contentHash != firstRow.contentHash ||
                row.ciphertextSize != firstRow.ciphertextSize,
          )) {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
    } else if (rows.isEmpty) {
      // A sole-member group has no remote physical target and therefore no
      // custody row. It still crosses the strict no-demotion boundary: prove
      // the exact empty ACL from the encrypted attachment projection instead
      // of accepting an arbitrary caller-supplied fingerprint.
      final contentHash = entry.value['content_hash'];
      final plaintextSize = entry.value['size'];
      final encryptionScheme = entry.value['encryption_scheme'];
      final custodyBlobId = custodyBlobIdsByAttachmentId[entry.key];
      if (contentHash is! String ||
          plaintextSize is! num ||
          plaintextSize.toInt() <= 0 ||
          encryptionScheme != 'blob_aes_256_gcm_v1' ||
          custodyBlobId == null) {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      String recomputed;
      try {
        recomputed = computeGroupMediaBlobCustodyFingerprint(
          groupId: resolvedGroupId,
          messageId: resolvedMessageId,
          attachmentId: entry.key,
          custodyBlobId: custodyBlobId,
          contentHash: contentHash,
          // AES-GCM appends its fixed 128-bit authentication tag.
          ciphertextSize: plaintextSize.toInt() + 16,
          recipientPeerIds: const <String>[],
        );
      } on Object {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      if (recomputed != expectedFingerprint) {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
    }
    fingerprints[entry.key] = expectedFingerprint;
    final current = await txn.query(
      'media_attachments',
      columns: const <String>[
        'id',
        'message_id',
        'owner_lane',
        'group_media_blob_custody_fingerprint',
      ],
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[entry.key, resolvedMessageId, 'group'],
      limit: 2,
    );
    if (current.length != 1) {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    final existingFingerprint =
        current.single['group_media_blob_custody_fingerprint'] as String?;
    if (existingFingerprint == null) allFingerprintsAlreadyExact = false;
    if (existingFingerprint != null &&
        existingFingerprint != fingerprints[entry.key]) {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
  }

  final stage = custodyRows.isEmpty
      ? (allFingerprintsAlreadyExact
            ? DirectMediaBlobCustodyBatchStageOutcome.idempotent
            : DirectMediaBlobCustodyBatchStageOutcome.applied)
      : await dbStageInitialGroupMediaBlobCustodyBatchWithinTransaction(
          txn,
          rows: custodyRows,
        );
  if (stage == DirectMediaBlobCustodyBatchStageOutcome.refused) return stage;
  for (final entry in fingerprints.entries) {
    final changed = await txn.rawUpdate(
      'UPDATE media_attachments '
      'SET group_media_blob_custody_fingerprint = ? '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND (group_media_blob_custody_fingerprint IS NULL OR '
      'group_media_blob_custody_fingerprint = ?)',
      <Object?>[
        entry.value,
        entry.key,
        resolvedMessageId,
        'group',
        entry.value,
      ],
    );
    if (changed != 1) {
      throw StateError('group-media custody fingerprint stage lost owner');
    }
  }
  return stage;
}

Future<DirectMediaBlobCustodyBatchStageOutcome>
dbStageFreshOutgoingGroupMediaBlobGeneration(
  Database db, {
  required Map<String, Object?> parentRow,
  required List<Map<String, Object?>> attachmentRows,
  required List<DirectMediaBlobCustodyRow> custodyRows,
  required Map<String, String> custodyBlobIdsByAttachmentId,
}) async {
  if (attachmentRows.isEmpty ||
      custodyRows.any(
        (row) =>
            row.direction != DirectMediaBlobCustodyDirection.outgoing ||
            row.state != DirectMediaBlobCustodyState.outgoingPrepared,
      )) {
    return Future<DirectMediaBlobCustodyBatchStageOutcome>.value(
      DirectMediaBlobCustodyBatchStageOutcome.refused,
    );
  }
  try {
    return await dbWriteTransaction(db, (txn) async {
      final parentMessageId = parentRow['id'];
      final parentGroupId = parentRow['group_id'];
      if (parentMessageId is! String ||
          parentMessageId.trim().isEmpty ||
          parentGroupId is! String ||
          parentGroupId.trim().isEmpty ||
          custodyRows.any(
            (row) =>
                row.messageId != parentMessageId ||
                row.groupId != parentGroupId,
          )) {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      final attachmentIds = attachmentRows
          .map((row) => row['id'])
          .whereType<String>()
          .toList(growable: false);
      if (attachmentIds.length != attachmentRows.length ||
          attachmentIds.toSet().length != attachmentIds.length ||
          custodyBlobIdsByAttachmentId.keys.toSet().length !=
              attachmentIds.length ||
          !attachmentIds.every(custodyBlobIdsByAttachmentId.containsKey) ||
          custodyBlobIdsByAttachmentId.values.any(
            (value) => value.trim().isEmpty || value != value.trim(),
          ) ||
          attachmentRows.any(
            (row) =>
                row['message_id'] != parentMessageId ||
                row['owner_lane'] != 'group',
          ) ||
          custodyRows.any(
            (row) =>
                !attachmentIds.contains(row.attachmentId) ||
                custodyBlobIdsByAttachmentId[row.attachmentId] !=
                    row.custodyBlobId,
          )) {
        return DirectMediaBlobCustodyBatchStageOutcome.refused;
      }
      final placeholders = List<String>.filled(
        attachmentIds.length,
        '?',
      ).join(',');
      final parents = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[parentMessageId],
        limit: 2,
      );
      final currentAttachments = await txn.rawQuery(
        'SELECT * FROM media_attachments WHERE id IN ($placeholders) '
        'OR (message_id = ? AND owner_lane = ?) '
        'ORDER BY id ASC',
        <Object?>[...attachmentIds, parentMessageId, 'group'],
      );
      final currentCustody = await txn.rawQuery(
        'SELECT * FROM $kDirectMediaBlobCustodyTable '
        'WHERE owner_lane = ? AND '
        '(message_id = ? OR attachment_id IN ($placeholders)) '
        'ORDER BY group_id ASC, attachment_id ASC, direction ASC, '
        'recipient_peer_id ASC, custody_blob_id ASC',
        <Object?>[
          MediaBlobCustodyOwnerLane.group.dbValue,
          parentMessageId,
          ...attachmentIds,
        ],
      );

      final hasAnyDurableProjection =
          parents.isNotEmpty ||
          currentAttachments.isNotEmpty ||
          currentCustody.isNotEmpty;
      if (hasAnyDurableProjection) {
        final exactAttachments =
            currentAttachments.length == attachmentRows.length &&
            attachmentRows.every((candidate) {
              final current = currentAttachments.where(
                (row) => row['id'] == candidate['id'],
              );
              return current.length == 1 &&
                  _containsExactProjection(current.single, candidate);
            });
        final currentByKey =
            <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{};
        try {
          for (final raw in currentCustody) {
            final row = DirectMediaBlobCustodyRow.fromMap(raw);
            currentByKey[DirectMediaBlobCustodyNaturalKey.ofRow(row)] = row;
          }
        } on Object {
          return DirectMediaBlobCustodyBatchStageOutcome.refused;
        }
        final exactCustody =
            currentCustody.length == custodyRows.length &&
            currentByKey.length == custodyRows.length &&
            custodyRows.every((candidate) {
              final current =
                  currentByKey[DirectMediaBlobCustodyNaturalKey.ofRow(
                    candidate,
                  )];
              return current != null &&
                  current.exactDatabaseProjectionMatches(candidate);
            });
        if (parents.length != 1 ||
            !_containsExactProjection(parents.single, parentRow) ||
            !exactAttachments ||
            !exactCustody) {
          return DirectMediaBlobCustodyBatchStageOutcome.refused;
        }
        return dbStageGroupMediaBlobCustodyWithinTransaction(
          txn,
          groupId: parentGroupId,
          messageId: parentMessageId,
          custodyBlobIdsByAttachmentId: custodyBlobIdsByAttachmentId,
          attachmentRows: attachmentRows,
          custodyRows: custodyRows,
        );
      }

      await txn.insert(
        'group_messages',
        parentRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      for (final attachment in attachmentRows) {
        await txn.insert(
          'media_attachments',
          attachment,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      final result = await dbStageGroupMediaBlobCustodyWithinTransaction(
        txn,
        groupId: parentGroupId,
        messageId: parentMessageId,
        custodyBlobIdsByAttachmentId: custodyBlobIdsByAttachmentId,
        attachmentRows: attachmentRows,
        custodyRows: custodyRows,
      );
      if (result == DirectMediaBlobCustodyBatchStageOutcome.refused) {
        throw const _GroupMediaBlobStageRollback();
      }
      final committedParents = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[parentMessageId],
        limit: 2,
      );
      final committedAttachments = await txn.rawQuery(
        'SELECT * FROM media_attachments WHERE id IN ($placeholders) '
        'OR (message_id = ? AND owner_lane = ?) ORDER BY id ASC',
        <Object?>[...attachmentIds, parentMessageId, 'group'],
      );
      final committedCustody = await txn.rawQuery(
        'SELECT * FROM $kDirectMediaBlobCustodyTable '
        'WHERE owner_lane = ? AND '
        '(message_id = ? OR attachment_id IN ($placeholders)) '
        'ORDER BY group_id ASC, attachment_id ASC, direction ASC, '
        'recipient_peer_id ASC, custody_blob_id ASC',
        <Object?>[
          MediaBlobCustodyOwnerLane.group.dbValue,
          parentMessageId,
          ...attachmentIds,
        ],
      );
      final committedByKey =
          <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{};
      for (final raw in committedCustody) {
        final row = DirectMediaBlobCustodyRow.fromMap(raw);
        committedByKey[DirectMediaBlobCustodyNaturalKey.ofRow(row)] = row;
      }
      final exactCommit =
          committedParents.length == 1 &&
          _containsExactProjection(committedParents.single, parentRow) &&
          committedAttachments.length == attachmentRows.length &&
          attachmentRows.every((candidate) {
            final committed = committedAttachments.where(
              (row) => row['id'] == candidate['id'],
            );
            return committed.length == 1 &&
                _containsExactProjection(committed.single, candidate);
          }) &&
          committedCustody.length == custodyRows.length &&
          committedByKey.length == custodyRows.length &&
          custodyRows.every((candidate) {
            final committed =
                committedByKey[DirectMediaBlobCustodyNaturalKey.ofRow(
                  candidate,
                )];
            return committed != null &&
                committed.exactDatabaseProjectionMatches(candidate);
          });
      if (!exactCommit) {
        throw StateError('fresh group-media blob owner lost atomic projection');
      }
      return DirectMediaBlobCustodyBatchStageOutcome.applied;
    });
  } on _GroupMediaBlobStageRollback {
    return DirectMediaBlobCustodyBatchStageOutcome.refused;
  }
}

final class _GroupMediaBlobStageRollback implements Exception {
  const _GroupMediaBlobStageRollback();
}

Future<DirectMediaBlobCustodyBatchStageOutcome>
dbStageInitialGroupMediaBlobCustodyBatch(
  Database db, {
  required List<DirectMediaBlobCustodyRow> rows,
}) => dbWriteTransaction(
  db,
  (txn) => dbStageInitialGroupMediaBlobCustodyBatchWithinTransaction(
    txn,
    rows: rows,
  ),
);

Future<DirectMediaBlobCustodyBatchStageOutcome>
dbStageInitialGroupMediaBlobCustodyBatchWithinTransaction(
  DatabaseExecutor txn, {
  required List<DirectMediaBlobCustodyRow> rows,
}) async {
  if (!_isValidInitialGroupBatch(rows)) {
    return DirectMediaBlobCustodyBatchStageOutcome.refused;
  }
  final first = rows.first;
  final attachmentIds = rows
      .map((row) => row.attachmentId)
      .toSet()
      .toList(growable: false);
  final current = await _loadGroupRowsByAttachmentIds(
    txn,
    groupId: first.groupId!,
    attachmentIds: attachmentIds,
  );
  if (current.isNotEmpty) {
    if (current.length != rows.length) {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    final currentByKey =
        <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{};
    try {
      for (final raw in current) {
        final parsed = DirectMediaBlobCustodyRow.fromMap(raw);
        currentByKey[DirectMediaBlobCustodyNaturalKey.ofRow(parsed)] = parsed;
      }
    } on Object {
      return DirectMediaBlobCustodyBatchStageOutcome.refused;
    }
    final exact = rows.every((candidate) {
      final existing =
          currentByKey[DirectMediaBlobCustodyNaturalKey.ofRow(candidate)];
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
  final committed = await _loadGroupRowsByAttachmentIds(
    txn,
    groupId: first.groupId!,
    attachmentIds: attachmentIds,
  );
  final committedByKey =
      <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{
        for (final raw in committed)
          DirectMediaBlobCustodyNaturalKey.ofRow(
            DirectMediaBlobCustodyRow.fromMap(raw),
          ): DirectMediaBlobCustodyRow.fromMap(
            raw,
          ),
      };
  if (committed.length != rows.length ||
      !rows.every((candidate) {
        final stored =
            committedByKey[DirectMediaBlobCustodyNaturalKey.ofRow(candidate)];
        return stored != null &&
            stored.exactDatabaseProjectionMatches(candidate);
      })) {
    throw StateError('group-media blob custody batch changed during commit');
  }
  return DirectMediaBlobCustodyBatchStageOutcome.applied;
}

Future<List<DirectMediaBlobCustodyRow>>
dbLoadGroupMediaBlobCustodyRowsForAttachment(
  DatabaseExecutor db, {
  required String groupId,
  required String attachmentId,
}) async {
  if (groupId.trim().isEmpty || attachmentId.trim().isEmpty) return const [];
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'owner_lane = ? AND group_id = ? AND attachment_id = ?',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      groupId,
      attachmentId,
    ],
    orderBy: 'direction ASC, recipient_peer_id ASC, custody_blob_id ASC',
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

Future<DirectMediaBlobCustodyRow?> dbLoadGroupMediaBlobCustodyForTarget(
  DatabaseExecutor db, {
  required String groupId,
  required String attachmentId,
  required String custodyBlobId,
  required DirectMediaBlobCustodyDirection direction,
  String? recipientPeerId,
}) async {
  final outgoing = direction == DirectMediaBlobCustodyDirection.outgoing;
  if (groupId.trim().isEmpty ||
      attachmentId.trim().isEmpty ||
      custodyBlobId.trim().isEmpty ||
      outgoing != (recipientPeerId != null) ||
      (recipientPeerId != null && recipientPeerId.trim().isEmpty)) {
    return null;
  }
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: outgoing
        ? 'owner_lane = ? AND group_id = ? AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id = ?'
        : 'owner_lane = ? AND group_id = ? AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id IS NULL',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      groupId,
      attachmentId,
      custodyBlobId,
      direction.dbValue,
      if (outgoing) recipientPeerId,
    ],
    limit: 2,
  );
  if (rows.isEmpty) return null;
  if (rows.length != 1) {
    throw StateError('group-media custody natural identity yielded siblings');
  }
  return DirectMediaBlobCustodyRow.fromMap(rows.single);
}

Future<List<DirectMediaBlobCustodyRow>> dbLoadGroupMediaBlobCustodyForMessage(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
}) async {
  if (groupId.trim().isEmpty || messageId.trim().isEmpty) return const [];
  final rows = await db.query(
    kDirectMediaBlobCustodyTable,
    where: 'owner_lane = ? AND group_id = ? AND message_id = ?',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      groupId,
      messageId,
    ],
    orderBy:
        'direction ASC, attachment_id ASC, recipient_peer_id ASC, '
        'custody_blob_id ASC',
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

Future<List<DirectMediaBlobCustodyRow>> dbLoadGroupMediaBlobCustodyByStates(
  DatabaseExecutor db, {
  required Set<DirectMediaBlobCustodyState> states,
  int limit = kDirectMediaBlobCustodyMaxLoadBatch,
}) async {
  if (states.isEmpty || limit <= 0) return const [];
  final orderedStates = states.map((state) => state.dbValue).toList()..sort();
  final placeholders = List<String>.filled(orderedStates.length, '?').join(',');
  final rows = await db.rawQuery(
    'SELECT * FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND group_id IS NOT NULL '
    'AND state IN ($placeholders) '
    'ORDER BY next_attempt_at ASC, updated_at ASC, attachment_id ASC, '
    'recipient_peer_id ASC, custody_blob_id ASC LIMIT ?',
    <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      ...orderedStates,
      math.min(limit, kDirectMediaBlobCustodyMaxLoadBatch),
    ],
  );
  return rows.map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
}

/// Exact lane-qualified inventory used by the existing outgoing group-media
/// lifecycle owner to reconcile artifacts left between file publication and
/// the atomic SQL stage. This is deliberately a path inventory, not a second
/// refcount or ownership ledger.
Future<Set<String>> dbLoadGroupMediaBlobArtifactRelativePaths(
  DatabaseExecutor db,
) async {
  final rows = await db.rawQuery(
    'SELECT DISTINCT ciphertext_relative_path '
    'FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND ciphertext_relative_path IS NOT NULL '
    'ORDER BY ciphertext_relative_path ASC',
    <Object?>[MediaBlobCustodyOwnerLane.group.dbValue],
  );
  return rows
      .map((row) => row['ciphertext_relative_path'])
      .whereType<String>()
      .where((path) => path.isNotEmpty)
      .toSet();
}

Future<bool> dbTransitionGroupMediaBlobCustodyIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
  required DirectMediaBlobCustodyRow next,
}) => dbWriteTransaction(
  db,
  (txn) => dbTransitionGroupMediaBlobCustodyIfExactWithinTransaction(
    txn,
    expected: expected,
    next: next,
  ),
);

Future<bool> dbTransitionGroupMediaBlobCustodyIfExactWithinTransaction(
  DatabaseExecutor txn, {
  required DirectMediaBlobCustodyRow expected,
  required DirectMediaBlobCustodyRow next,
}) async {
  if (expected.ownerLane != MediaBlobCustodyOwnerLane.group ||
      !expected.canTransitionTo(next)) {
    return false;
  }
  final current = await dbLoadGroupMediaBlobCustodyForTarget(
    txn,
    groupId: expected.groupId!,
    attachmentId: expected.attachmentId,
    custodyBlobId: expected.custodyBlobId,
    direction: expected.direction,
    recipientPeerId: expected.recipientPeerId,
  );
  if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
    return false;
  }
  final nextMap = Map<String, Object?>.from(next.toMap())
    ..remove('attachment_id')
    ..remove('owner_lane')
    ..remove('group_id')
    ..remove('custody_blob_id')
    ..remove('direction')
    ..remove('recipient_peer_id');
  final outgoing =
      expected.direction == DirectMediaBlobCustodyDirection.outgoing;
  final changed = await txn.update(
    kDirectMediaBlobCustodyTable,
    nextMap,
    where: outgoing
        ? 'owner_lane = ? AND group_id = ? AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id = ? AND state = ?'
        : 'owner_lane = ? AND group_id = ? AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id IS NULL AND state = ?',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      expected.groupId,
      expected.attachmentId,
      expected.custodyBlobId,
      expected.direction.dbValue,
      if (outgoing) expected.recipientPeerId,
      expected.state.dbValue,
    ],
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
  if (changed != 1) return false;
  final committed = await dbLoadGroupMediaBlobCustodyForTarget(
    txn,
    groupId: expected.groupId!,
    attachmentId: expected.attachmentId,
    custodyBlobId: expected.custodyBlobId,
    direction: expected.direction,
    recipientPeerId: expected.recipientPeerId,
  );
  if (committed == null || !committed.exactDatabaseProjectionMatches(next)) {
    throw StateError('group-media blob custody CAS lost exact state');
  }
  return true;
}

Future<bool> dbDeleteGroupMediaBlobCleanupPendingIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
}) {
  if (expected.ownerLane != MediaBlobCustodyOwnerLane.group ||
      expected.state != DirectMediaBlobCustodyState.outgoingCleanupPending) {
    return Future<bool>.value(false);
  }
  return dbWriteTransaction(db, (txn) async {
    final current = await dbLoadGroupMediaBlobCustodyForTarget(
      txn,
      groupId: expected.groupId!,
      attachmentId: expected.attachmentId,
      custodyBlobId: expected.custodyBlobId,
      direction: expected.direction,
      recipientPeerId: expected.recipientPeerId,
    );
    if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
      return false;
    }
    return await txn.delete(
          kDirectMediaBlobCustodyTable,
          where:
              'owner_lane = ? AND group_id = ? AND attachment_id = ? '
              'AND custody_blob_id = ? AND direction = ? '
              'AND recipient_peer_id = ? AND state = ?',
          whereArgs: <Object?>[
            MediaBlobCustodyOwnerLane.group.dbValue,
            expected.groupId,
            expected.attachmentId,
            expected.custodyBlobId,
            expected.direction.dbValue,
            expected.recipientPeerId,
            DirectMediaBlobCustodyState.outgoingCleanupPending.dbValue,
          ],
        ) ==
        1;
  });
}

Future<bool> dbCommitIncomingGroupMediaBlobLocalPath(
  Database db, {
  required Map<String, Object?> expectedAttachmentRow,
  required DirectMediaBlobCustodyRow expectedCustody,
  required String localPath,
  required String sourceRelayPeerId,
  required String updatedAt,
  required int nowMs,
}) {
  final attachmentId = expectedAttachmentRow['id'] as String? ?? '';
  final messageId = expectedAttachmentRow['message_id'] as String? ?? '';
  if (attachmentId.trim().isEmpty ||
      messageId.trim().isEmpty ||
      localPath.trim().isEmpty ||
      localPath != localPath.trim() ||
      sourceRelayPeerId.trim().isEmpty ||
      sourceRelayPeerId != sourceRelayPeerId.trim() ||
      updatedAt.trim().isEmpty ||
      nowMs <= 0 ||
      expectedAttachmentRow['owner_lane'] != 'group' ||
      expectedCustody.ownerLane != MediaBlobCustodyOwnerLane.group ||
      expectedCustody.attachmentId != attachmentId ||
      expectedCustody.messageId != messageId ||
      expectedCustody.state != DirectMediaBlobCustodyState.incomingCommitted ||
      expectedCustody.expiresAtMs == null ||
      nowMs >= expectedCustody.expiresAtMs!) {
    return Future<bool>.value(false);
  }
  final nextCustody = expectedCustody.copyWith(
    state: DirectMediaBlobCustodyState.incomingAckPending,
    custodyRelayPeerId: sourceRelayPeerId,
    updatedAt: updatedAt,
  );
  return dbWriteTransaction(db, (txn) async {
    final parents = await txn.query(
      'group_messages',
      columns: const <String>['id', 'group_id'],
      where: 'id = ? AND group_id = ?',
      whereArgs: <Object?>[messageId, expectedCustody.groupId],
      limit: 2,
    );
    if (parents.length != 1) return false;
    final attachments = await txn.query(
      'media_attachments',
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[attachmentId, messageId, 'group'],
      limit: 2,
    );
    final current = await dbLoadGroupMediaBlobCustodyForTarget(
      txn,
      groupId: expectedCustody.groupId!,
      attachmentId: attachmentId,
      custodyBlobId: expectedCustody.custodyBlobId,
      direction: DirectMediaBlobCustodyDirection.incoming,
    );
    if (attachments.length != 1 || current == null) return false;
    final completed = Map<String, Object?>.from(expectedAttachmentRow)
      ..['local_path'] = localPath
      ..['download_status'] = kMediaDownloadStatusDone
      ..['download_retry_count'] = 0;
    if (_containsExactProjection(attachments.single, completed) &&
        current.exactDatabaseProjectionMatches(nextCustody)) {
      return true;
    }
    if (!_containsExactProjection(attachments.single, expectedAttachmentRow) ||
        !current.exactDatabaseProjectionMatches(expectedCustody)) {
      return false;
    }
    final changed = await txn.rawUpdate(
      'UPDATE media_attachments SET local_path = ?, download_status = ?, '
      'download_retry_count = 0 WHERE id = ? AND message_id = ? '
      'AND owner_lane = ? AND group_media_blob_custody_fingerprint = ?',
      <Object?>[
        localPath,
        kMediaDownloadStatusDone,
        attachmentId,
        messageId,
        'group',
        expectedAttachmentRow['group_media_blob_custody_fingerprint'],
      ],
    );
    if (changed != 1 ||
        !await dbTransitionGroupMediaBlobCustodyIfExactWithinTransaction(
          txn,
          expected: expectedCustody,
          next: nextCustody,
        )) {
      throw StateError('group-media local commit lost exact ACK authority');
    }
    return true;
  });
}

/// Atomically turns a delete-before-download decision into durable local
/// terminal suppression plus a source-pinned ACK obligation.
///
/// Authority is the exact Plan-235 deletion journal and matching local
/// tombstone with the parent already absent. A generic orphan attachment is
/// never sufficient. Durable plaintext stays `done`; otherwise the strict
/// descriptor is terminalized as `download_failed` before the row moves from
/// `incoming_committed` to `incoming_ack_pending`.
Future<bool> dbTerminalizeIncomingGroupMediaBlobForLocalDeletion(
  Database db, {
  required Map<String, Object?> expectedAttachmentRow,
  required DirectMediaBlobCustodyRow expectedCustody,
  required String sourceRelayPeerId,
  required String updatedAt,
}) {
  final attachmentId = expectedAttachmentRow['id'] as String? ?? '';
  final messageId = expectedAttachmentRow['message_id'] as String? ?? '';
  final groupId = expectedCustody.groupId;
  if (attachmentId.trim().isEmpty ||
      messageId.trim().isEmpty ||
      groupId == null ||
      sourceRelayPeerId.trim().isEmpty ||
      sourceRelayPeerId != sourceRelayPeerId.trim() ||
      updatedAt.trim().isEmpty ||
      expectedAttachmentRow['owner_lane'] != 'group' ||
      expectedAttachmentRow['group_media_blob_custody_fingerprint'] == null ||
      expectedCustody.ownerLane != MediaBlobCustodyOwnerLane.group ||
      expectedCustody.attachmentId != attachmentId ||
      expectedCustody.messageId != messageId ||
      expectedCustody.state != DirectMediaBlobCustodyState.incomingCommitted) {
    return Future<bool>.value(false);
  }
  final nextCustody = expectedCustody.copyWith(
    state: DirectMediaBlobCustodyState.incomingAckPending,
    custodyRelayPeerId: sourceRelayPeerId,
    updatedAt: updatedAt,
  );
  return dbWriteTransaction(db, (txn) async {
    final journals = await txn.query(
      'group_media_deletion_journal',
      columns: const <String>[
        'attachment_id',
        'message_id',
        'group_id',
        'operation_intent',
      ],
      where:
          'attachment_id = ? AND message_id = ? AND group_id = ? '
          "AND operation_intent = 'delete_for_me'",
      whereArgs: <Object?>[attachmentId, messageId, groupId],
      limit: 2,
    );
    final tombstones = await txn.query(
      'group_message_local_deletions',
      columns: const <String>['message_id', 'group_id'],
      where: 'message_id = ? AND group_id = ?',
      whereArgs: <Object?>[messageId, groupId],
      limit: 2,
    );
    final parents = await txn.query(
      'group_messages',
      columns: const <String>['id', 'group_id'],
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 2,
    );
    if (journals.length != 1 || tombstones.length != 1 || parents.isNotEmpty) {
      return false;
    }
    final attachments = await txn.query(
      'media_attachments',
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[attachmentId, messageId, 'group'],
      limit: 2,
    );
    final current = await dbLoadGroupMediaBlobCustodyForTarget(
      txn,
      groupId: groupId,
      attachmentId: attachmentId,
      custodyBlobId: expectedCustody.custodyBlobId,
      direction: DirectMediaBlobCustodyDirection.incoming,
    );
    if (attachments.length != 1 || current == null) return false;
    final durablePlaintext =
        attachments.single['download_status'] == kMediaDownloadStatusDone &&
        (attachments.single['local_path'] as String?)?.isNotEmpty == true;
    final terminalAttachment = Map<String, Object?>.from(expectedAttachmentRow)
      ..['download_status'] = durablePlaintext
          ? kMediaDownloadStatusDone
          : kMediaDownloadStatusDownloadFailed
      ..['download_retry_count'] = 0;
    if (_containsExactProjection(attachments.single, terminalAttachment) &&
        current.exactDatabaseProjectionMatches(nextCustody)) {
      return true;
    }
    if (!_containsExactProjection(attachments.single, expectedAttachmentRow) ||
        !current.exactDatabaseProjectionMatches(expectedCustody)) {
      return false;
    }
    final changed = await txn.rawUpdate(
      'UPDATE media_attachments SET download_status = ?, '
      'download_retry_count = 0 WHERE id = ? AND message_id = ? '
      'AND owner_lane = ? AND group_media_blob_custody_fingerprint = ?',
      <Object?>[
        durablePlaintext
            ? kMediaDownloadStatusDone
            : kMediaDownloadStatusDownloadFailed,
        attachmentId,
        messageId,
        'group',
        expectedAttachmentRow['group_media_blob_custody_fingerprint'],
      ],
    );
    if (changed != 1 ||
        !await dbTransitionGroupMediaBlobCustodyIfExactWithinTransaction(
          txn,
          expected: expectedCustody,
          next: nextCustody,
        )) {
      throw StateError(
        'group-media local deletion lost exact terminal ACK authority',
      );
    }
    return true;
  });
}

Future<bool> dbDeleteIncomingGroupMediaBlobAckPendingIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
}) {
  if (expected.ownerLane != MediaBlobCustodyOwnerLane.group ||
      expected.state != DirectMediaBlobCustodyState.incomingAckPending) {
    return Future<bool>.value(false);
  }
  return _deleteIncomingGroupMediaBlobIfExact(
    db,
    expected: expected,
    terminalizeAttachment: false,
  );
}

Future<bool> dbDeleteIncomingGroupMediaBlobIfExpired(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
  required int nowMs,
}) {
  if (expected.ownerLane != MediaBlobCustodyOwnerLane.group ||
      expected.direction != DirectMediaBlobCustodyDirection.incoming ||
      expected.expiresAtMs == null ||
      nowMs < expected.expiresAtMs!) {
    return Future<bool>.value(false);
  }
  return _deleteIncomingGroupMediaBlobIfExact(
    db,
    expected: expected,
    terminalizeAttachment: true,
  );
}

Future<bool> _deleteIncomingGroupMediaBlobIfExact(
  Database db, {
  required DirectMediaBlobCustodyRow expected,
  required bool terminalizeAttachment,
}) => dbWriteTransaction(db, (txn) async {
  final current = await dbLoadGroupMediaBlobCustodyForTarget(
    txn,
    groupId: expected.groupId!,
    attachmentId: expected.attachmentId,
    custodyBlobId: expected.custodyBlobId,
    direction: DirectMediaBlobCustodyDirection.incoming,
  );
  if (current == null || !current.exactDatabaseProjectionMatches(expected)) {
    return false;
  }
  final attachments = await txn.query(
    'media_attachments',
    columns: const <String>[
      'id',
      'message_id',
      'owner_lane',
      'local_path',
      'download_status',
      'group_media_blob_custody_fingerprint',
    ],
    where: 'id = ? AND message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[expected.attachmentId, expected.messageId, 'group'],
    limit: 2,
  );
  if (attachments.length > 1 ||
      (attachments.isNotEmpty &&
          attachments.single['group_media_blob_custody_fingerprint'] == null)) {
    return false;
  }
  if (terminalizeAttachment && attachments.isNotEmpty) {
    final durable =
        attachments.single['download_status'] == kMediaDownloadStatusDone &&
        (attachments.single['local_path'] as String?)?.isNotEmpty == true;
    final changed = await txn.rawUpdate(
      'UPDATE media_attachments SET download_status = ? '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND group_media_blob_custody_fingerprint = ?',
      <Object?>[
        durable ? kMediaDownloadStatusDone : kMediaDownloadStatusDownloadFailed,
        expected.attachmentId,
        expected.messageId,
        'group',
        attachments.single['group_media_blob_custody_fingerprint'],
      ],
    );
    if (changed != 1) {
      throw StateError('group-media expiry lost attachment terminalization');
    }
  }
  final deleted = await txn.delete(
    kDirectMediaBlobCustodyTable,
    where:
        'owner_lane = ? AND group_id = ? AND attachment_id = ? '
        'AND custody_blob_id = ? AND direction = ? '
        'AND recipient_peer_id IS NULL AND state = ?',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      expected.groupId,
      expected.attachmentId,
      expected.custodyBlobId,
      DirectMediaBlobCustodyDirection.incoming.dbValue,
      expected.state.dbValue,
    ],
  );
  if (deleted != 1 && terminalizeAttachment && attachments.isNotEmpty) {
    throw StateError('group-media expiry lost exact custody retirement');
  }
  return deleted == 1;
});

Future<int> dbCountOtherGroupMediaBlobCustodyRowsReferencingArtifact(
  DatabaseExecutor db, {
  required String ciphertextRelativePath,
  required String contentHash,
  required int ciphertextSize,
  required DirectMediaBlobCustodyNaturalKey excluding,
}) async {
  if (excluding.ownerLane != MediaBlobCustodyOwnerLane.group ||
      excluding.groupId == null ||
      ciphertextRelativePath.trim().isEmpty) {
    return 0;
  }
  final outgoing =
      excluding.direction == DirectMediaBlobCustodyDirection.outgoing;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND ciphertext_relative_path = ? '
    'AND content_hash = ? AND ciphertext_size = ? '
    'AND NOT (group_id = ? AND attachment_id = ? '
    'AND custody_blob_id = ? AND direction = ? AND '
    '${outgoing ? 'recipient_peer_id = ?' : 'recipient_peer_id IS NULL'})',
    <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      ciphertextRelativePath,
      contentHash,
      ciphertextSize,
      excluding.groupId,
      excluding.attachmentId,
      excluding.custodyBlobId,
      excluding.direction.dbValue,
      if (outgoing) excluding.recipientPeerId,
    ],
  );
  return (rows.single['n'] as num).toInt();
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
  final current = await dbLoadDirectMediaBlobCustodyForTarget(
    txn,
    attachmentId: expected.attachmentId,
    direction: DirectMediaBlobCustodyDirection.incoming,
    recipientPeerId: null,
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
      'direct_media_blob_custody_fingerprint_version',
    ],
    where: 'id = ?',
    whereArgs: <Object?>[expected.attachmentId],
    limit: 1,
  );
  if (attachmentRows.isNotEmpty) {
    final attachment = attachmentRows.single;
    // Every incoming strict attachment remains exact target-specific with a
    // NULL fingerprint version; a v2 marker on an incoming row is a crossed
    // lineage and fails closed.
    if (attachment['message_id'] != expected.messageId ||
        attachment['owner_lane'] != MediaOwnerLane.direct.dbValue ||
        attachment['direct_media_blob_custody_fingerprint'] !=
            commitmentFingerprint ||
        attachment['direct_media_blob_custody_fingerprint_version'] != null) {
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
    where:
        'owner_lane = ? AND group_id IS NULL AND attachment_id = ? '
        'AND custody_blob_id = ? AND direction = ? '
        'AND recipient_peer_id IS NULL AND state = ?',
    whereArgs: <Object?>[
      MediaBlobCustodyOwnerLane.direct.dbValue,
      expected.attachmentId,
      expected.custodyBlobId,
      DirectMediaBlobCustodyDirection.incoming.dbValue,
      expected.state.dbValue,
    ],
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
  final keys = <DirectMediaBlobCustodyNaturalKey>{};
  return rows.every(
    (row) =>
        row.ownerLane == MediaBlobCustodyOwnerLane.direct &&
        row.messageId == first.messageId &&
        row.direction == first.direction &&
        row.state == expectedState &&
        keys.add(DirectMediaBlobCustodyNaturalKey.ofRow(row)),
  );
}

bool _isValidInitialGroupBatch(List<DirectMediaBlobCustodyRow> rows) {
  if (rows.isEmpty) return false;
  final first = rows.first;
  if (first.ownerLane != MediaBlobCustodyOwnerLane.group ||
      first.groupId == null) {
    return false;
  }
  final expectedState =
      first.direction == DirectMediaBlobCustodyDirection.outgoing
      ? DirectMediaBlobCustodyState.outgoingPrepared
      : DirectMediaBlobCustodyState.incomingCommitted;
  if (first.state != expectedState) return false;
  final keys = <DirectMediaBlobCustodyNaturalKey>{};
  return rows.every(
    (row) =>
        row.ownerLane == MediaBlobCustodyOwnerLane.group &&
        row.groupId == first.groupId &&
        row.messageId == first.messageId &&
        row.direction == first.direction &&
        row.state == expectedState &&
        keys.add(DirectMediaBlobCustodyNaturalKey.ofRow(row)),
  );
}

Future<List<Map<String, Object?>>> _loadRowsByAttachmentIds(
  DatabaseExecutor db,
  List<String> attachmentIds,
) {
  final placeholders = List.filled(attachmentIds.length, '?').join(',');
  return db.rawQuery(
    'SELECT * FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND group_id IS NULL '
    'AND attachment_id IN ($placeholders) '
    'ORDER BY attachment_id ASC, direction ASC, recipient_peer_id ASC',
    <Object?>[MediaBlobCustodyOwnerLane.direct.dbValue, ...attachmentIds],
  );
}

Future<List<Map<String, Object?>>> _loadGroupRowsByAttachmentIds(
  DatabaseExecutor db, {
  required String groupId,
  required List<String> attachmentIds,
}) {
  final placeholders = List<String>.filled(attachmentIds.length, '?').join(',');
  return db.rawQuery(
    'SELECT * FROM $kDirectMediaBlobCustodyTable '
    'WHERE owner_lane = ? AND group_id = ? '
    'AND attachment_id IN ($placeholders) '
    'ORDER BY attachment_id ASC, direction ASC, recipient_peer_id ASC, '
    'custody_blob_id ASC',
    <Object?>[
      MediaBlobCustodyOwnerLane.group.dbValue,
      groupId,
      ...attachmentIds,
    ],
  );
}

bool _containsExactProjection(
  Map<String, Object?> current,
  Map<String, Object?> expected, {
  Set<String> ignoredKeys = const <String>{},
}) {
  for (final entry in expected.entries) {
    if (!ignoredKeys.contains(entry.key) && current[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _isValidOutgoingTerminalizationBatch(
  List<DirectMediaBlobCustodyRow> rows,
) {
  if (rows.isEmpty) return false;
  final first = rows.first;
  final keys = <DirectMediaBlobCustodyNaturalKey>{};
  final active = rows.every(
    (row) =>
        row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
        row.state == DirectMediaBlobCustodyState.outgoingStored,
  );
  final terminal = rows.every(
    (row) => row.state == DirectMediaBlobCustodyState.outgoingCleanupPending,
  );
  return first.direction == DirectMediaBlobCustodyDirection.outgoing &&
      first.ownerLane == MediaBlobCustodyOwnerLane.direct &&
      (active || terminal) &&
      rows.every(
        (row) =>
            row.ownerLane == MediaBlobCustodyOwnerLane.direct &&
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.messageId == first.messageId &&
            keys.add(DirectMediaBlobCustodyNaturalKey.ofRow(row)),
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
