import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/deterministic_notification_id.dart';
import '../direct_media_blob_custody.dart';
import '../../services/protected_group_content_contract.dart';
import '../db_write_transaction.dart';
import 'direct_media_blob_custody_db_helpers.dart';
import 'group_event_log_db_helpers.dart';
import 'group_message_local_deletions_db_helpers.dart';
import 'group_notification_display_outbox_db_helpers.dart';
import 'group_notification_reconciliation_outbox_db_helpers.dart';
import 'protected_group_reaction_display_terminal_db_helpers.dart';

const String protectedGroupMessageEventType = 'protected_message';
const String protectedGroupReactionEventType = 'protected_reaction';
const String protectedGroupContentPreparedEventType =
    'protected_content_prepared';
const String protectedGroupContentTerminalEventType =
    'protected_content_terminal';

Future<bool> dbHasExactProtectedGroupContentPreparedOwner(
  DatabaseExecutor txn, {
  required String groupId,
  required String payloadType,
  required String contentEventId,
  required String ownerKind,
  required String ownerId,
  required String ownerStatus,
  required String retryWrapper,
  required Map<String, Object?> eventPayload,
}) async {
  final sourceEventId = payloadType == 'group_message'
      ? 'ppm1:${base64Url.encode(utf8.encode(contentEventId)).replaceAll('=', '')}'
      : payloadType == 'group_reaction'
      ? 'ppr1:$contentEventId'
      : '';
  if (sourceEventId.isEmpty || retryWrapper.isEmpty) return false;
  final expected = <String, Object?>{
    ...eventPayload,
    'preparedOwnerKind': ownerKind,
    'preparedOwnerId': ownerId,
    'preparedOwnerStatus': ownerStatus,
    'replayEnvelopeHash': _retryReplayEnvelopeHash(retryWrapper),
  };
  final rows = await txn.query(
    'group_event_log',
    columns: const <String>['canonical_payload'],
    where: 'group_id = ? AND event_type = ? AND source_event_id = ?',
    whereArgs: <Object?>[
      groupId,
      protectedGroupContentPreparedEventType,
      sourceEventId,
    ],
    limit: 1,
  );
  return rows.isNotEmpty &&
      rows.single['canonical_payload'] ==
          canonicalizeGroupEventLogPayload(expected);
}

bool isExactProtectedGroupContentPreparedStage({
  required String groupId,
  required String payloadType,
  required String contentEventId,
  required String ownerKind,
  required String ownerId,
  required String ownerStatus,
  required String retryWrapper,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> preparedEventPayload,
}) {
  try {
    final manifest = ProtectedGroupContentRetryManifest.decode(retryWrapper);
    final wrapper = jsonDecode(retryWrapper);
    if (wrapper is! Map ||
        wrapper.length != 5 ||
        !wrapper.keys.toSet().containsAll(const <String>{
          'groupId',
          'message',
          'custodyContract',
          'custodyKind',
          'recipientPeerIds',
        }) ||
        wrapper['groupId'] != groupId ||
        wrapper['custodyContract'] != 'ack_or_expiry_v1' ||
        wrapper['custodyKind'] != 'group_content_v1' ||
        wrapper['message'] is! String) {
      return false;
    }
    final replay = jsonDecode(wrapper['message'] as String);
    final payload = preparedEventPayload['payload'];
    if (replay is! Map || payload is! Map) return false;
    final exactPayload = payload.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final expectedSourceId = payloadType == 'group_message'
        ? 'ppm1:${base64Url.encode(utf8.encode(contentEventId)).replaceAll('=', '')}'
        : payloadType == 'group_reaction'
        ? 'ppr1:$contentEventId'
        : '';
    final expectedKeys = <String>{
      'custodyKind',
      'groupId',
      'payloadType',
      'contentEventId',
      'authorityEventAt',
      'authorityEventId',
      'authorityKeyEpoch',
      'logicalSenderPeerId',
      'senderDeviceId',
      'senderTransportPeerId',
      'senderPublicKey',
      'recipientPeerIds',
      'payload',
      'preparedOwnerKind',
      'preparedOwnerId',
      'preparedOwnerStatus',
      'replayEnvelopeHash',
    };
    return manifest.groupId == groupId &&
        manifest.payloadType == payloadType &&
        manifest.contentEventId == contentEventId &&
        manifest.pendingRecipientPeerIds.length ==
            manifest.fullRecipientPeerIds.length &&
        manifest.pendingRecipientPeerIds.toSet().containsAll(
          manifest.fullRecipientPeerIds,
        ) &&
        preparedEventPayload.length == expectedKeys.length &&
        preparedEventPayload.keys.toSet().containsAll(expectedKeys) &&
        ownerKind == payloadType &&
        ownerId == contentEventId &&
        ownerStatus ==
            (payloadType == 'group_message' ? 'queued_offline' : 'pending') &&
        sourceEventId == expectedSourceId &&
        sourcePeerId == preparedEventPayload['logicalSenderPeerId'] &&
        sourceTimestamp == payload['timestamp'] &&
        preparedEventPayload['custodyKind'] == 'group_content_v1' &&
        preparedEventPayload['groupId'] == groupId &&
        preparedEventPayload['payloadType'] == payloadType &&
        preparedEventPayload['contentEventId'] == contentEventId &&
        preparedEventPayload['logicalSenderPeerId'] ==
            manifest.logicalSenderPeerId &&
        preparedEventPayload['senderDeviceId'] == manifest.senderDeviceId &&
        preparedEventPayload['senderTransportPeerId'] ==
            manifest.senderTransportPeerId &&
        preparedEventPayload['senderPublicKey'] == manifest.senderPublicKey &&
        manifest.matchesCanonicalPlaintext(exactPayload) &&
        exactPayload['groupId'] == groupId &&
        exactPayload['keyEpoch'] == manifest.keyEpoch &&
        exactPayload['senderDeviceId'] == manifest.senderDeviceId &&
        exactPayload['transportPeerId'] == manifest.senderTransportPeerId &&
        exactPayload['custodyKind'] == 'group_content_v1' &&
        exactPayload['contentEventId'] == contentEventId &&
        exactPayload['authorityEventAt'] == replay['authorityEventAt'] &&
        exactPayload['authorityEventId'] == replay['authorityEventId'] &&
        exactPayload['authorityKeyEpoch'] == replay['authorityKeyEpoch'] &&
        jsonEncode(exactPayload['recipientPeerIds'] as List) ==
            jsonEncode(manifest.fullRecipientPeerIds) &&
        (payloadType == 'group_message'
            ? exactPayload['messageId'] == contentEventId &&
                  exactPayload['senderId'] == manifest.logicalSenderPeerId
            : exactPayload['eventId'] == contentEventId &&
                  exactPayload['senderPeerId'] ==
                      manifest.logicalSenderPeerId &&
                  exactPayload['messageId'] ==
                      manifest.reactionTargetMessageId &&
                  exactPayload['action'] == manifest.reactionAction) &&
        replay['groupId'] == groupId &&
        replay['payloadType'] == payloadType &&
        replay['contentEventId'] == contentEventId &&
        replay['messageId'] == contentEventId &&
        replay['senderPeerId'] == sourcePeerId &&
        replay['authorityEventAt'] ==
            preparedEventPayload['authorityEventAt'] &&
        replay['authorityEventId'] ==
            preparedEventPayload['authorityEventId'] &&
        replay['authorityKeyEpoch'] ==
            preparedEventPayload['authorityKeyEpoch'] &&
        jsonEncode(replay['recipientPeerIds'] as List) ==
            jsonEncode(preparedEventPayload['recipientPeerIds'] as List) &&
        jsonEncode(wrapper['recipientPeerIds'] as List) ==
            jsonEncode(replay['recipientPeerIds'] as List) &&
        preparedEventPayload['preparedOwnerKind'] == ownerKind &&
        preparedEventPayload['preparedOwnerId'] == ownerId &&
        preparedEventPayload['preparedOwnerStatus'] == ownerStatus &&
        preparedEventPayload['replayEnvelopeHash'] ==
            sha256
                .convert(utf8.encode(wrapper['message'] as String))
                .toString();
  } catch (_) {
    return false;
  }
}

Future<bool> dbHasProtectedGroupContentTerminalInTransaction(
  DatabaseExecutor txn, {
  required String groupId,
  required String payloadType,
  required String contentEventId,
}) async {
  var afterSequence = 0;
  while (true) {
    final rows = await txn.rawQuery(
      'SELECT sequence, canonical_payload FROM group_event_log '
      'WHERE group_id = ? AND event_type = ? AND sequence > ? '
      'ORDER BY sequence ASC LIMIT 200',
      <Object?>[groupId, protectedGroupContentTerminalEventType, afterSequence],
    );
    for (final row in rows) {
      final raw = row['canonical_payload'];
      if (raw is! String) continue;
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded['payloadType'] == payloadType &&
          decoded['contentEventId'] == contentEventId) {
        final reason = decoded['reasonCode'];
        if (reason is String &&
            (reason.startsWith('protected_') ||
                reason == 'authority_reconciliation_invalidated')) {
          return true;
        }
      }
    }
    if (rows.length < 200) return false;
    final next = rows.last['sequence'];
    if (next is! int || next <= afterSequence) {
      throw StateError('protected terminal scan cursor stalled');
    }
    afterSequence = next;
  }
}

String _retryReplayEnvelopeHash(String retryWrapper) {
  try {
    final decoded = jsonDecode(retryWrapper);
    if (decoded is! Map || decoded['message'] is! String) {
      throw const FormatException('missing prepared replay envelope');
    }
    final message = decoded['message'] as String;
    if (message.isEmpty) {
      throw const FormatException('empty prepared replay envelope');
    }
    return sha256.convert(utf8.encode(message)).toString();
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('invalid prepared retry wrapper');
  }
}

enum DbProtectedGroupContentCommitResult {
  applied,
  exactDuplicate,
  staleDominated,
  prerequisiteMissing,
}

Future<DbProtectedGroupContentCommitResult> dbCommitProtectedGroupMessage(
  Database db, {
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required Map<String, Object?> messageRow,
  List<Map<String, Object?>> mediaAttachmentRows =
      const <Map<String, Object?>>[],
  List<DirectMediaBlobCustodyRow> incomingMediaCustodyRows =
      const <DirectMediaBlobCustodyRow>[],
  Map<String, Object?>? readyDisplayOutboxRow,
}) {
  return dbWriteTransaction(
    db,
    (txn) => dbCommitProtectedGroupMessageInTransaction(
      txn,
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      eventPayload: eventPayload,
      messageRow: messageRow,
      mediaAttachmentRows: mediaAttachmentRows,
      incomingMediaCustodyRows: incomingMediaCustodyRows,
      readyDisplayOutboxRow: readyDisplayOutboxRow,
    ),
    exclusive: true,
  );
}

Future<DbProtectedGroupContentCommitResult>
dbCommitProtectedGroupMessageInTransaction(
  DatabaseExecutor txn, {
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required Map<String, Object?> messageRow,
  List<Map<String, Object?>> mediaAttachmentRows =
      const <Map<String, Object?>>[],
  List<DirectMediaBlobCustodyRow> incomingMediaCustodyRows =
      const <DirectMediaBlobCustodyRow>[],
  Map<String, Object?>? readyDisplayOutboxRow,
}) async {
  _validateProtectedEventAuthority(
    groupId: groupId,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    expectedPrefix: 'pm1:',
  );
  final messageId = _requiredString(messageRow, 'id');
  if (mediaAttachmentRows.isEmpty != incomingMediaCustodyRows.isEmpty) {
    throw const FormatException(
      'protected media descriptors and custody must commit together',
    );
  }
  if (messageRow['group_id'] != groupId ||
      await dbIsGroupMessageLocallyDeleted(txn, messageId)) {
    return DbProtectedGroupContentCommitResult.prerequisiteMissing;
  }
  final parent = await txn.query(
    'groups',
    columns: const <String>['id'],
    where: 'id = ?',
    whereArgs: <Object?>[groupId],
    limit: 1,
  );
  if (parent.isEmpty) {
    return DbProtectedGroupContentCommitResult.prerequisiteMissing;
  }
  if (mediaAttachmentRows.isEmpty &&
      await dbHasMediaAttachmentForProtectedGroupMessage(txn, messageId)) {
    // Blob-free custody may never bless a scalar row whose shared message ID
    // already owns media in another projection path. Check before appending
    // durable protected evidence so a collision cannot become displayable.
    return DbProtectedGroupContentCommitResult.prerequisiteMissing;
  }

  final current = await _loadExact(txn, 'group_messages', 'id', messageId);
  if (current != null && !_sameIncomingFields(current, messageRow)) {
    throw GroupEventLogTamperException(
      'protected message projection conflicts with exact event identity',
    );
  }
  if (current == null) {
    // Historical authority was already authenticated by the caller. This
    // deliberately bypasses only the mutable-current parent guard; local
    // deletion and exact group existence were checked above.
    await txn.insert(
      'group_messages',
      messageRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
  if (mediaAttachmentRows.isNotEmpty) {
    await _stageProtectedGroupMediaDescriptors(
      txn,
      groupId: groupId,
      messageId: messageId,
      attachmentRows: mediaAttachmentRows,
      custodyRows: incomingMediaCustodyRows,
    );
  }
  final appended = await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: groupId,
    eventType: protectedGroupMessageEventType,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    payload: eventPayload,
  );
  if (readyDisplayOutboxRow != null) {
    await _insertReadyDisplayOutboxExact(txn, readyDisplayOutboxRow);
  }
  final readback = await _loadExact(txn, 'group_messages', 'id', messageId);
  if (readback == null || !_sameIncomingFields(readback, messageRow)) {
    throw StateError('protected message exact readback failed');
  }
  if (mediaAttachmentRows.isNotEmpty &&
      !await _hasExactProtectedGroupMediaDescriptors(
        txn,
        messageId: messageId,
        attachmentRows: mediaAttachmentRows,
      )) {
    throw StateError('protected group-media exact readback failed');
  }
  return appended.inserted
      ? DbProtectedGroupContentCommitResult.applied
      : DbProtectedGroupContentCommitResult.exactDuplicate;
}

Future<void> _stageProtectedGroupMediaDescriptors(
  DatabaseExecutor txn, {
  required String groupId,
  required String messageId,
  required List<Map<String, Object?>> attachmentRows,
  required List<DirectMediaBlobCustodyRow> custodyRows,
}) async {
  final attachmentIds = <String>{};
  for (final candidate in attachmentRows) {
    final attachmentId = candidate['id'];
    if (attachmentId is! String ||
        attachmentId.isEmpty ||
        !attachmentIds.add(attachmentId) ||
        candidate['message_id'] != messageId ||
        candidate['owner_lane'] != 'group') {
      throw const FormatException('invalid protected group-media descriptor');
    }
    final existing = await txn.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: <Object?>[attachmentId],
      limit: 2,
    );
    if (existing.isEmpty) {
      await txn.insert(
        'media_attachments',
        candidate,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else if (existing.length != 1 ||
        !_sameProtectedGroupMediaDescriptor(existing.single, candidate)) {
      throw GroupEventLogTamperException(
        'protected group-media descriptor conflicts with exact event identity',
      );
    }
  }
  if (custodyRows.length != attachmentRows.length ||
      custodyRows.any(
        (row) =>
            row.ownerLane != MediaBlobCustodyOwnerLane.group ||
            row.groupId != groupId ||
            row.messageId != messageId ||
            row.direction != DirectMediaBlobCustodyDirection.incoming ||
            row.state != DirectMediaBlobCustodyState.incomingCommitted ||
            !attachmentIds.contains(row.attachmentId),
      )) {
    throw const FormatException('invalid protected group-media custody');
  }
  final staged = await dbStageGroupMediaBlobCustodyWithinTransaction(
    txn,
    attachmentRows: attachmentRows,
    custodyRows: custodyRows,
  );
  if (staged == DirectMediaBlobCustodyBatchStageOutcome.refused) {
    throw GroupEventLogTamperException(
      'protected group-media custody conflicts with exact event identity',
    );
  }
}

bool _sameProtectedGroupMediaDescriptor(
  Map<String, Object?> current,
  Map<String, Object?> expected,
) {
  for (final entry in expected.entries) {
    if (entry.key == 'group_media_blob_custody_fingerprint') continue;
    if (current[entry.key] != entry.value) return false;
  }
  return true;
}

Future<bool> _hasExactProtectedGroupMediaDescriptors(
  DatabaseExecutor txn, {
  required String messageId,
  required List<Map<String, Object?>> attachmentRows,
}) async {
  final rows = await txn.query(
    'media_attachments',
    where: 'message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[messageId, 'group'],
  );
  if (rows.length != attachmentRows.length) return false;
  final byId = <String, Map<String, Object?>>{
    for (final row in rows) row['id']! as String: row,
  };
  return attachmentRows.every((expected) {
    final current = byId[expected['id']];
    final fingerprint = current?['group_media_blob_custody_fingerprint'];
    return current != null &&
        _sameProtectedGroupMediaDescriptor(current, expected) &&
        fingerprint is String &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint);
  });
}

Future<bool> dbHasMediaAttachmentForProtectedGroupMessage(
  DatabaseExecutor txn,
  String messageId,
) async {
  final hasTable = (await txn.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'media_attachments' LIMIT 1",
  )).isNotEmpty;
  if (!hasTable) return false;
  final rows = await txn.query(
    'media_attachments',
    columns: const <String>['id'],
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<DbProtectedGroupContentCommitResult> dbCommitProtectedGroupReaction(
  Database db, {
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required Map<String, Object?> reactionRow,
  required String transitionId,
  required String action,
  Map<String, Object?>? readyDisplayOutboxRow,
}) {
  return dbWriteTransaction(
    db,
    (txn) => dbCommitProtectedGroupReactionInTransaction(
      txn,
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      eventPayload: eventPayload,
      reactionRow: reactionRow,
      transitionId: transitionId,
      action: action,
      readyDisplayOutboxRow: readyDisplayOutboxRow,
    ),
    exclusive: true,
  );
}

Future<DbProtectedGroupContentCommitResult>
dbCommitProtectedGroupReactionInTransaction(
  DatabaseExecutor txn, {
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required Map<String, Object?> reactionRow,
  required String transitionId,
  required String action,
  Map<String, Object?>? readyDisplayOutboxRow,
}) async {
  _validateProtectedEventAuthority(
    groupId: groupId,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    expectedPrefix: 'pr1:',
  );
  if (sourceEventId != 'pr1:$transitionId' ||
      (action != 'add' && action != 'remove')) {
    throw ArgumentError('crossed protected reaction event authority');
  }
  final messageId = _requiredString(reactionRow, 'message_id');
  final senderPeerId = _requiredString(reactionRow, 'sender_peer_id');
  final timestamp = _requiredString(reactionRow, 'timestamp');
  final emoji = _requiredString(reactionRow, 'emoji');
  final expectedTransition = _buildReactionTransitionId(
    groupId: groupId,
    messageId: messageId,
    senderPeerId: senderPeerId,
    action: action,
    emoji: emoji,
    timestamp: timestamp,
  );
  if (transitionId != expectedTransition) {
    throw ArgumentError('invalid protected reaction transition id');
  }
  final target = await txn.query(
    'group_messages',
    columns: const <String>[
      'id',
      'text',
      'quoted_message_id',
      'is_forwarded',
      'media_policy_version',
    ],
    where: 'id = ? AND group_id = ?',
    whereArgs: <Object?>[messageId, groupId],
    limit: 1,
  );
  final targetRow = target.isEmpty ? null : target.single;
  final hasAttachmentTable = (await txn.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'media_attachments' LIMIT 1",
  )).isNotEmpty;
  final attachment = targetRow == null || !hasAttachmentTable
      ? const <Map<String, Object?>>[]
      : await txn.query(
          'media_attachments',
          columns: const <String>['id'],
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
          limit: 1,
        );
  if (targetRow == null ||
      (targetRow['text'] as String? ?? '').trimLeft().startsWith(
        r'{"__sys":',
      ) ||
      (targetRow['quoted_message_id'] as String?)?.isNotEmpty == true ||
      targetRow['is_forwarded'] != 0 ||
      targetRow['media_policy_version'] != 0 ||
      attachment.isNotEmpty) {
    return DbProtectedGroupContentCommitResult.prerequisiteMissing;
  }

  final appended = await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: groupId,
    eventType: protectedGroupReactionEventType,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    payload: eventPayload,
  );
  final currentRows = await txn.query(
    'message_reactions',
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: <Object?>[messageId, senderPeerId],
    limit: 1,
  );
  final current = currentRows.isEmpty ? null : currentRows.single;
  if (current != null) {
    final currentRemovedAt = current['removed_at'] as String?;
    final currentAction = currentRemovedAt == null ? 'add' : 'remove';
    final currentTransition = _buildReactionTransitionId(
      groupId: groupId,
      messageId: messageId,
      senderPeerId: senderPeerId,
      action: currentAction,
      emoji: _requiredString(current, 'emoji'),
      timestamp: currentRemovedAt ?? _requiredString(current, 'timestamp'),
    );
    final comparison = compareGroupReactionTransitionIds(
      transitionId,
      currentTransition,
    );
    if (comparison < 0) {
      return DbProtectedGroupContentCommitResult.staleDominated;
    }
    if (comparison == 0) {
      final exact = Map<String, Object?>.from(reactionRow)
        ..['removed_at'] = action == 'remove' ? timestamp : null;
      if (!_sameIncomingFields(current, exact)) {
        throw GroupEventLogTamperException(
          'protected reaction projection conflicts with transition',
        );
      }
      if (readyDisplayOutboxRow != null) {
        final displayed =
            action == 'add' &&
            await dbHasProtectedGroupReactionDisplayTerminalExact(
              txn,
              groupId: groupId,
              transitionId: transitionId,
              messageId: messageId,
              actorPeerId: senderPeerId,
              reactionId: _requiredString(reactionRow, 'id'),
              eventTimestamp: timestamp,
            );
        if (displayed) {
          await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
            txn,
            groupId: groupId,
            messageId: messageId,
            actorPeerId: senderPeerId,
          );
        } else {
          await _insertReadyDisplayOutboxExact(txn, readyDisplayOutboxRow);
        }
      }
      return appended.inserted
          ? DbProtectedGroupContentCommitResult.applied
          : DbProtectedGroupContentCommitResult.exactDuplicate;
    }
  }

  final normalized = Map<String, Object?>.from(reactionRow)
    ..['removed_at'] = action == 'remove' ? timestamp : null;
  final displayed =
      action == 'add' &&
      await dbHasProtectedGroupReactionDisplayTerminalExact(
        txn,
        groupId: groupId,
        transitionId: transitionId,
        messageId: messageId,
        actorPeerId: senderPeerId,
        reactionId: _requiredString(reactionRow, 'id'),
        eventTimestamp: timestamp,
      );
  if (displayed) {
    normalized['notification_display_terminal_event_id'] =
        boundedReactionEventIdentity(transitionId);
  } else if (action == 'remove') {
    final priorTerminal = current?['notification_display_terminal_event_id'];
    if (priorTerminal is String && priorTerminal.isNotEmpty) {
      normalized['notification_display_terminal_event_id'] = priorTerminal;
    }
  }
  await txn.insert(
    'message_reactions',
    normalized,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  if (action == 'add') {
    if (displayed) {
      await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
        txn,
        groupId: groupId,
        messageId: messageId,
        actorPeerId: senderPeerId,
      );
    } else if (readyDisplayOutboxRow != null) {
      await _insertReadyDisplayOutboxExact(txn, readyDisplayOutboxRow);
    }
  } else {
    await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
      txn,
      groupId: groupId,
      messageId: messageId,
      actorPeerId: senderPeerId,
    );
    await dbEnqueueGroupNotificationReconciliationOutbox(txn, groupId: groupId);
  }
  final readbackRows = await txn.query(
    'message_reactions',
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: <Object?>[messageId, senderPeerId],
    limit: 1,
  );
  if (readbackRows.isEmpty ||
      !_sameIncomingFields(readbackRows.single, normalized)) {
    throw StateError('protected reaction exact readback failed');
  }
  return DbProtectedGroupContentCommitResult.applied;
}

Future<DbProtectedGroupContentCommitResult>
dbCommitProtectedGroupContentTerminal(
  Database db, {
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
}) {
  return dbWriteTransaction(
    db,
    (txn) => dbCommitProtectedGroupContentTerminalInTransaction(
      txn,
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      eventPayload: eventPayload,
    ),
    exclusive: true,
  );
}

Future<DbProtectedGroupContentCommitResult>
dbCommitProtectedGroupContentTerminalInTransaction(
  DatabaseExecutor txn, {
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
}) async {
  _validateProtectedEventAuthority(
    groupId: groupId,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    expectedPrefix: 'pt1:',
  );
  final appended = await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: groupId,
    eventType: protectedGroupContentTerminalEventType,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    payload: eventPayload,
  );
  final readback = await txn.query(
    'group_event_log',
    columns: const <String>['source_event_id'],
    where: 'group_id = ? AND source_event_id = ? AND event_type = ?',
    whereArgs: <Object?>[
      groupId,
      sourceEventId,
      protectedGroupContentTerminalEventType,
    ],
    limit: 1,
  );
  if (readback.isEmpty) {
    throw StateError('protected content terminal readback failed');
  }
  return appended.inserted
      ? DbProtectedGroupContentCommitResult.applied
      : DbProtectedGroupContentCommitResult.exactDuplicate;
}

Future<Map<String, Object?>?> _loadExact(
  DatabaseExecutor txn,
  String table,
  String key,
  String value,
) async {
  final rows = await txn.query(
    table,
    where: '$key = ?',
    whereArgs: <Object?>[value],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<void> _insertReadyDisplayOutboxExact(
  DatabaseExecutor txn,
  Map<String, Object?> row,
) async {
  if (row['readiness'] != 'ready' || row['revision'] != 1) {
    throw StateError('protected display custody must start exact-ready');
  }
  final eventId = _requiredString(row, 'event_id');
  final existing = await _loadExact(
    txn,
    'group_notification_display_outbox',
    'event_id',
    eventId,
  );
  if (existing != null) {
    if (!_sameIncomingFields(existing, row)) {
      throw StateError('protected display event authority conflict');
    }
    return;
  }
  final count = Sqflite.firstIntValue(
    await txn.rawQuery(
      'SELECT COUNT(*) FROM group_notification_display_outbox',
    ),
  );
  if ((count ?? 0) >= kGroupNotificationDisplayOutboxCapacity) {
    throw StateError('group notification display outbox capacity exhausted');
  }
  await txn.insert(
    'group_notification_display_outbox',
    row,
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
}

void _validateProtectedEventAuthority({
  required String groupId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required String expectedPrefix,
}) {
  if (groupId.isEmpty ||
      sourcePeerId.isEmpty ||
      !sourceEventId.startsWith(expectedPrefix) ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
      ).hasMatch(sourceTimestamp) ||
      DateTime.tryParse(sourceTimestamp)?.isUtc != true) {
    throw ArgumentError('invalid protected content event authority');
  }
}

String _requiredString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, key, 'must be a canonical String');
  }
  return value;
}

bool _sameIncomingFields(
  Map<String, Object?> current,
  Map<String, Object?> incoming,
) {
  for (final entry in incoming.entries) {
    final left = current[entry.key];
    final right = entry.value;
    if (left is num && right is num) {
      if (left.toInt() != right.toInt()) return false;
    } else if (left != right) {
      return false;
    }
  }
  return true;
}

String _buildReactionTransitionId({
  required String groupId,
  required String messageId,
  required String senderPeerId,
  required String action,
  required String emoji,
  required String timestamp,
}) {
  final at = DateTime.tryParse(timestamp)?.toUtc();
  if (at == null) throw ArgumentError.value(timestamp, 'timestamp');
  final stateDigest = sha256
      .convert(
        utf8.encode(
          jsonEncode(<String>[
            'group_reaction_state_v1',
            groupId,
            messageId,
            senderPeerId,
          ]),
        ),
      )
      .toString()
      .substring(0, 32);
  final eventDigest = sha256
      .convert(
        utf8.encode(
          jsonEncode(<String>[
            'group_reaction_event_v1',
            stateDigest,
            action,
            emoji,
            _fixedUtc(at),
          ]),
        ),
      )
      .toString()
      .substring(0, 32);
  return 'gr1:$stateDigest:'
      '${at.microsecondsSinceEpoch.toString().padLeft(20, '0')}:'
      '$eventDigest';
}

String _fixedUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}.'
      '${micros.toString().padLeft(6, '0')}Z';
}
