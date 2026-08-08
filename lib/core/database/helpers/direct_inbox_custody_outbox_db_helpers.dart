import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import '../direct_inbox_custody_outbox_contract.dart';
import '../direct_media_blob_custody.dart';
import '../outgoing_transport_mutation.dart';
import '../../media/direct_media_blob_custody.dart';
import 'direct_media_blob_custody_db_helpers.dart';
import 'messages_db_helpers.dart';

const String _table = 'direct_inbox_custody_outbox';

const int kDirectInboxCustodyOutboxCapacity = 512;
const int kDirectInboxCustodyOutboxMaxLoadBatch = 50;

/// Atomically stages a fresh ordinary message and its immutable relay-inbox
/// custody. No message row is allowed to commit without its companion row.
///
/// [capacity] exists only so a real-DB test can prove the full condition with
/// a small fixture. Production callers use the default constant.
Future<OutgoingOrdinaryMutationOutcome> dbStageOutgoingDirectTextInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required OutgoingOrdinaryAttemptKind kind,
  required String recipientPeerId,
  required String messageId,
  required String incarnationId,
  required String wireEnvelope,
  int capacity = kDirectInboxCustodyOutboxCapacity,
}) {
  final createdAt = stagedRow['created_at'] as String? ?? '';
  final validAuthority =
      capacity >= 0 &&
      kind == OutgoingOrdinaryAttemptKind.fresh &&
      expectedRow == null &&
      recipientPeerId.trim().isNotEmpty &&
      messageId.trim().isNotEmpty &&
      incarnationId.length == 32 &&
      wireEnvelope.trim().isNotEmpty &&
      stagedRow['id'] == messageId &&
      stagedRow['contact_peer_id'] == recipientPeerId &&
      stagedRow['wire_envelope'] == wireEnvelope &&
      createdAt.trim().isNotEmpty &&
      _isEligibleFreshOrdinaryDirectText(stagedRow) &&
      isExactV2DirectChatInitialEnvelope(
        wireEnvelope,
        messageId: messageId,
        senderPeerId: stagedRow['sender_peer_id'],
      );
  if (!validAuthority) {
    return Future<OutgoingOrdinaryMutationOutcome>.value(
      OutgoingOrdinaryMutationOutcome.refused,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final currentMessages = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final currentMessageAuthority = await txn.query(
      _table,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      limit: 2,
    );
    final currentIncarnation = await txn.query(
      _table,
      where: 'incarnation_id = ?',
      whereArgs: <Object?>[incarnationId],
      limit: 1,
    );

    if (currentMessages.isNotEmpty ||
        currentMessageAuthority.isNotEmpty ||
        currentIncarnation.isNotEmpty) {
      final isExactReplay =
          currentMessages.length == 1 &&
          currentMessageAuthority.length == 1 &&
          currentIncarnation.length == 1 &&
          _messageAttemptMatches(currentMessages.single, stagedRow) &&
          _immutableCustodyMatches(
            currentMessageAuthority.single,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            incarnationId: incarnationId,
            wireEnvelope: wireEnvelope,
          ) &&
          _immutableCustodyMatches(
            currentIncarnation.single,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            incarnationId: incarnationId,
            wireEnvelope: wireEnvelope,
          );
      return isExactReplay
          ? OutgoingOrdinaryMutationOutcome.idempotent
          : OutgoingOrdinaryMutationOutcome.refused;
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count >= capacity) return OutgoingOrdinaryMutationOutcome.refused;

    final messageOutcome =
        await dbStageOutgoingOrdinaryAttemptWithinTransaction(
          txn,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
        );
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return OutgoingOrdinaryMutationOutcome.refused;
    }

    await txn.insert(_table, <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'message_id': messageId,
      'incarnation_id': incarnationId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return OutgoingOrdinaryMutationOutcome.applied;
  });
}

/// Loads a fair bounded batch. SQLite's ascending order places NULL first, so
/// never-attempted rows lead, followed by the oldest recorded attempt.
Future<List<Map<String, Object?>>> dbLoadDirectInboxCustodyOutbox(
  DatabaseExecutor db, {
  int limit = kDirectInboxCustodyOutboxMaxLoadBatch,
}) {
  if (limit <= 0) return Future<List<Map<String, Object?>>>.value(const []);
  final boundedLimit = math.min(limit, kDirectInboxCustodyOutboxMaxLoadBatch);
  return db.rawQuery(
    'SELECT * FROM $_table '
    'ORDER BY last_attempt_at ASC, created_at ASC, '
    'recipient_peer_id ASC, message_id ASC LIMIT ?',
    <Object?>[boundedLimit],
  );
}

Future<Map<String, Object?>?> dbLoadDirectInboxCustodyOutboxForMessage(
  DatabaseExecutor db, {
  required String recipientPeerId,
  required String messageId,
}) async {
  final rows = await db.query(
    _table,
    where: 'recipient_peer_id = ? AND message_id = ?',
    whereArgs: <Object?>[recipientPeerId, messageId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Loads the immutable v108 owner for [messageId] without trusting the
/// mutable parent message's current recipient projection.
///
/// More than one stored owner is corrupt/ambiguous authority. Throwing keeps
/// retry callers fail-closed instead of allowing a generic transport path to
/// interpret the ambiguity as an absent custody row.
Future<Map<String, Object?>?> dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final rows = await db.query(
    _table,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    limit: 2,
  );
  if (rows.length > 1) {
    throw StateError('Ambiguous direct inbox custody owner for message');
  }
  return rows.isEmpty ? null : rows.single;
}

/// Retains the row and records one bounded failure classification only while
/// the caller's exact immutable incarnation still owns the scope.
Future<bool> dbRecordDirectInboxCustodyFailureIfExact(
  DatabaseExecutor db, {
  required String recipientPeerId,
  required String messageId,
  required String expectedIncarnationId,
  required String expectedWireEnvelope,
  required String errorCode,
  required String attemptedAt,
}) async {
  if (!DirectInboxCustodyErrorCode.values.contains(errorCode) ||
      attemptedAt.trim().isEmpty) {
    return false;
  }
  final changed = await db.rawUpdate(
    'UPDATE $_table SET retry_count = retry_count + 1, '
    'last_attempt_at = ?, last_error_code = ?, updated_at = ? '
    'WHERE recipient_peer_id = ? AND message_id = ? '
    'AND incarnation_id = ? AND wire_envelope = ?',
    <Object?>[
      attemptedAt,
      errorCode,
      attemptedAt,
      recipientPeerId,
      messageId,
      expectedIncarnationId,
      expectedWireEnvelope,
    ],
  );
  return changed == 1;
}

/// Atomically projects accepted remote custody without downgrading stronger
/// local truth, then retires only the exact immutable incarnation.
Future<DirectInboxCustodyCompletionOutcome>
dbCompleteAcceptedDirectInboxCustodyIfExact(
  Database db, {
  required String recipientPeerId,
  required String messageId,
  required String expectedIncarnationId,
  required String expectedWireEnvelope,
  required int? relayExpiresAt,
}) {
  if (recipientPeerId.trim().isEmpty ||
      messageId.trim().isEmpty ||
      expectedIncarnationId.length != 32 ||
      expectedWireEnvelope.trim().isEmpty ||
      (relayExpiresAt != null && relayExpiresAt <= 0)) {
    return Future<DirectInboxCustodyCompletionOutcome>.value(
      DirectInboxCustodyCompletionOutcome.stale,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final custodyRows = await txn.query(
      _table,
      where: 'recipient_peer_id = ? AND message_id = ?',
      whereArgs: <Object?>[recipientPeerId, messageId],
      limit: 1,
    );
    if (custodyRows.isEmpty ||
        !_immutableCustodyMatches(
          custodyRows.single,
          recipientPeerId: recipientPeerId,
          messageId: messageId,
          incarnationId: expectedIncarnationId,
          wireEnvelope: expectedWireEnvelope,
        )) {
      return DirectInboxCustodyCompletionOutcome.stale;
    }
    final custody = custodyRows.single;
    final mediaBlobManifestHash =
        custody['media_blob_manifest_hash'] as String?;
    final mediaBlobExpiresAtMs = (custody['media_blob_expires_at_ms'] as num?)
        ?.toInt();
    final hasStrictBlobBinding =
        mediaBlobManifestHash != null && mediaBlobExpiresAtMs != null;
    if ((mediaBlobManifestHash == null) != (mediaBlobExpiresAtMs == null)) {
      return DirectInboxCustodyCompletionOutcome.stale;
    }
    List<DirectMediaBlobCustodyRow> strictBlobRows = const [];
    if (hasStrictBlobBinding) {
      if (relayExpiresAt == null ||
          relayExpiresAt <= 0 ||
          relayExpiresAt > mediaBlobExpiresAtMs) {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
      final rawMessageBlobRows = await txn.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ? AND direction = ?',
        whereArgs: <Object?>[
          messageId,
          DirectMediaBlobCustodyDirection.outgoing.dbValue,
        ],
        orderBy: 'attachment_id ASC',
      );
      try {
        strictBlobRows = rawMessageBlobRows
            .map(DirectMediaBlobCustodyRow.fromMap)
            .toList(growable: false);
      } on FormatException {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
      if (strictBlobRows.isEmpty ||
          strictBlobRows.any(
            (row) =>
                row.state != DirectMediaBlobCustodyState.outgoingStored ||
                row.inboxCustodyIncarnationId != expectedIncarnationId ||
                row.expiresAtMs == null,
          )) {
        return DirectInboxCustodyCompletionOutcome.stale;
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
      if (computeDirectMediaBlobManifestHash(manifest) !=
              mediaBlobManifestHash ||
          earliestDirectMediaBlobExpiryMs(manifest) != mediaBlobExpiresAtMs) {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
    }

    final messageRows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    var outcome = DirectInboxCustodyCompletionOutcome.messageRemoved;
    if (messageRows.isEmpty) {
      // Physical deletion is stronger than accepted relay custody, but the
      // outbox row was the only durable fact preventing a delayed generic
      // whole-row save from recreating the message after completion. Replace
      // that authority inside this same transaction with a scrubbed local
      // tombstone before retiring the exact v108 incarnation.
      await txn.insert(
        'messages',
        _removedMessageTombstoneFromCustody(
          custody,
          messageId: messageId,
          recipientPeerId: recipientPeerId,
          expectedWireEnvelope: expectedWireEnvelope,
          relayExpiresAt: relayExpiresAt,
        ),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final message = messageRows.single;
      final status = message['status'] as String?;
      final ownsMessage =
          ((message['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
          message['contact_peer_id'] == recipientPeerId;
      final userTerminal =
          message['deleted_at'] != null || message['hidden_at'] != null;
      final stillProjectsOwnedAttempt =
          message['wire_envelope'] == expectedWireEnvelope;
      final shouldAdvance =
          ownsMessage &&
          !userTerminal &&
          stillProjectsOwnedAttempt &&
          const <String>{
            'sending',
            'sent',
            'failed',
            'inboxed',
          }.contains(status);
      if (shouldAdvance) {
        final alreadyProjected =
            status == 'inboxed' &&
            message['transport'] == 'inbox' &&
            (relayExpiresAt == null ||
                message['relay_expires_at'] == relayExpiresAt);
        if (alreadyProjected) {
          outcome = DirectInboxCustodyCompletionOutcome.messagePreserved;
        } else {
          final changed = await txn.update(
            'messages',
            <String, Object?>{
              'status': 'inboxed',
              'transport': 'inbox',
              'relay_expires_at': relayExpiresAt,
              'custody_checked_at': null,
            },
            where:
                'id = ? AND contact_peer_id = ? AND is_incoming = 0 '
                'AND status = ? AND deleted_at IS NULL AND hidden_at IS NULL',
            whereArgs: <Object?>[messageId, recipientPeerId, status],
          );
          if (changed != 1) {
            throw StateError(
              'direct inbox custody message projection lost its exact row',
            );
          }
          outcome = DirectInboxCustodyCompletionOutcome.messageAdvanced;
        }
      } else {
        // Delivered and user-terminal rows are intentionally stronger than an
        // inbox-custody projection. Identity mismatches and later edit/send
        // attempts with different exact envelopes are also never edited.
        outcome = DirectInboxCustodyCompletionOutcome.messagePreserved;
      }
    }

    final deleted = await txn.delete(
      _table,
      where:
          'recipient_peer_id = ? AND message_id = ? '
          'AND incarnation_id = ? AND wire_envelope = ?',
      whereArgs: <Object?>[
        recipientPeerId,
        messageId,
        expectedIncarnationId,
        expectedWireEnvelope,
      ],
    );
    if (deleted != 1) {
      throw StateError(
        'direct inbox custody completion lost its exact incarnation',
      );
    }
    if (strictBlobRows.isNotEmpty) {
      final completedAt = DateTime.now().toUtc().toIso8601String();
      for (final row in strictBlobRows) {
        final cleanup = row.copyWith(
          state: DirectMediaBlobCustodyState.outgoingCleanupPending,
          updatedAt: completedAt,
        );
        final changed =
            await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
              txn,
              expected: row,
              next: cleanup,
            );
        if (!changed) {
          throw StateError(
            'direct inbox custody completion lost strict blob authority',
          );
        }
      }
    }
    return outcome;
  });
}

bool _immutableCustodyMatches(
  Map<String, Object?> row, {
  required String recipientPeerId,
  required String messageId,
  required String incarnationId,
  required String wireEnvelope,
}) =>
    row['recipient_peer_id'] == recipientPeerId &&
    row['message_id'] == messageId &&
    row['incarnation_id'] == incarnationId &&
    row['wire_envelope'] == wireEnvelope;

Map<String, Object?> _removedMessageTombstoneFromCustody(
  Map<String, Object?> custody, {
  required String messageId,
  required String recipientPeerId,
  required String expectedWireEnvelope,
  required int? relayExpiresAt,
}) {
  final senderPeerId = _exactInitialEnvelopeSenderPeerId(
    expectedWireEnvelope,
    messageId: messageId,
  );
  final createdAt = custody['created_at'];
  final completedAt = custody['updated_at'];
  if (senderPeerId == null ||
      !_isNonBlankString(createdAt) ||
      !_isNonBlankString(completedAt)) {
    throw StateError(
      'direct inbox custody cannot retain exact removed-message authority',
    );
  }
  return <String, Object?>{
    'id': messageId,
    'contact_peer_id': recipientPeerId,
    'sender_peer_id': senderPeerId,
    'text': '',
    'timestamp': createdAt,
    'status': 'inboxed',
    'is_incoming': 0,
    'created_at': createdAt,
    'wire_envelope': null,
    'transport': 'inbox',
    'relay_expires_at': relayExpiresAt,
    'custody_checked_at': null,
    'hidden_at': completedAt,
    'direct_media_custody_intent_id': null,
  };
}

String? _exactInitialEnvelopeSenderPeerId(
  String wireEnvelope, {
  required String messageId,
}) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) return null;
    final senderPeerId = decoded['senderPeerId'];
    if (!_isNonBlankString(senderPeerId) ||
        !isExactV2DirectChatInitialEnvelope(
          wireEnvelope,
          messageId: messageId,
          senderPeerId: senderPeerId,
        )) {
      return null;
    }
    return senderPeerId as String;
  } on FormatException {
    return null;
  }
}

bool _messageAttemptMatches(
  Map<String, Object?> current,
  Map<String, Object?> staged,
) => staged.entries.every(
  (entry) => _sameDatabaseValue(current[entry.key], entry.value),
);

bool _sameDatabaseValue(Object? left, Object? right) {
  if (left is num && right is num) return left == right;
  return left == right;
}

bool _isEligibleFreshOrdinaryDirectText(Map<String, Object?> row) =>
    _isNonBlankString(row['sender_peer_id']) &&
    _isNonBlankString(row['text']) &&
    _isNonBlankString(row['timestamp']) &&
    row['status'] == 'sending' &&
    _asInt(row['is_incoming']) == 0 &&
    row['edited_at'] == null &&
    row['deleted_at'] == null &&
    row['deleted_by_peer_id'] == null &&
    row['hidden_at'] == null &&
    row['transport'] == null &&
    row['relay_expires_at'] == null &&
    row['custody_checked_at'] == null &&
    row['direct_media_custody_intent_id'] == null &&
    _asInt(row['private_media_policy_version']) == 0 &&
    row['private_media_mode'] == 'ordinary' &&
    row['private_media_duration_seconds'] == null &&
    row['private_media_state'] == 'none' &&
    row['private_media_received_at_ms'] == null &&
    row['private_media_expires_at_ms'] == null &&
    row['private_media_revealed_at_ms'] == null &&
    row['private_media_terminal_at_ms'] == null &&
    row['private_media_clock_high_water_ms'] == null;

/// Validates the cleartext discriminator and encrypted body of one initial
/// direct `chat_message` envelope.
///
/// The frozen v108 custody wire label says "text" for compatibility, but the
/// outer envelope is shared by initial text and ordinary-media messages. Edit
/// events carry a distinct `eventId` and are deliberately excluded.
bool isExactV2DirectChatInitialEnvelope(
  String wireEnvelope, {
  required String messageId,
  required Object? senderPeerId,
}) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) return false;
    final encrypted = decoded['encrypted'];
    return decoded['type'] == 'chat_message' &&
        decoded['version'] == '2' &&
        decoded['id'] == messageId &&
        decoded['senderPeerId'] == senderPeerId &&
        !decoded.containsKey('eventId') &&
        encrypted is Map<String, dynamic> &&
        _isNonBlankString(encrypted['kem']) &&
        _isNonBlankString(encrypted['ciphertext']) &&
        _isNonBlankString(encrypted['nonce']);
  } on FormatException {
    return false;
  }
}

bool _isNonBlankString(Object? value) =>
    value is String && value.trim().isNotEmpty;

int? _asInt(Object? value) => value is num ? value.toInt() : null;
