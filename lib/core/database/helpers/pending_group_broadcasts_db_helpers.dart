import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'group_event_log_db_helpers.dart';
import 'group_exit_intents_db_helpers.dart';
import 'group_parent_write_guard.dart';

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

const _table = 'pending_group_broadcasts';
const _pendingBroadcastExactFields = <String>[
  'id',
  'group_id',
  'kind',
  'sys_text',
  'recipient_peer_ids',
  'event_at',
  'source_message_id',
  'created_at',
  'updated_at',
];

String get _pendingBroadcastExactWhere =>
    _pendingBroadcastExactFields.map((field) => '"$field" IS ?').join(' AND ');

/// Inserts a pending broadcast, idempotently: a row sharing the same
/// `(group_id, source_message_id)` is left untouched (no duplicate re-push).
Future<void> dbInsertPendingGroupBroadcast(
  Database db,
  Map<String, Object?> row,
) async {
  await dbWriteTransaction(
    db,
    (transaction) =>
        dbInsertPendingGroupBroadcastWithExecutor(transaction, row),
  );
}

/// Commits a frozen physical-recipient authority set as one durable fact.
/// Any conflicting existing target rolls the whole set back.
Future<bool> dbInsertPendingGroupBroadcastsAtomically(
  Database db,
  List<Map<String, Object?>> rows,
) async {
  if (rows.isEmpty) return false;
  try {
    return await dbWriteTransaction(db, (transaction) async {
      for (final row in rows) {
        await dbInsertPendingGroupBroadcastWithExecutor(transaction, row);
        final existing = await transaction.query(
          _table,
          where: 'group_id = ? AND source_message_id = ?',
          whereArgs: <Object?>[row['group_id'], row['source_message_id']],
          limit: 1,
        );
        if (existing.length != 1 ||
            !_samePendingBroadcastRow(existing.single, row)) {
          throw StateError('protected authority row conflict');
        }
      }
      return true;
    });
  } catch (_) {
    return false;
  }
}

/// Commits locally authored protected authority rows and their authenticated
/// prepared fact in the same transaction. Exact retries repair a fact missing
/// from a pre-history build; conflicting outbox or history bytes fail closed.
Future<bool> dbInsertPendingGroupBroadcastsWithAuthorityPreparedAtomically(
  Database db, {
  required String groupId,
  required List<Map<String, Object?>> rows,
  required String authorityPreparedSourcePeerId,
  required String authorityPreparedSourceEventId,
  required String authorityPreparedSourceTimestamp,
  required Map<String, Object?> authorityPreparedPayload,
}) async {
  if (groupId.isEmpty ||
      authorityPreparedSourcePeerId.isEmpty ||
      authorityPreparedSourceEventId.isEmpty ||
      authorityPreparedSourceTimestamp.isEmpty ||
      authorityPreparedPayload.isEmpty) {
    return false;
  }
  if (rows.any((row) => row['group_id'] != groupId)) {
    return false;
  }
  try {
    return await dbWriteTransaction(db, (transaction) async {
      if (!await dbAllowsOrdinaryGroupWrite(transaction, groupId)) {
        throw StateError('protected authority parent is unavailable');
      }
      for (final row in rows) {
        await dbInsertPendingGroupBroadcastWithExecutor(transaction, row);
        final existing = await transaction.query(
          _table,
          where: 'group_id = ? AND source_message_id = ?',
          whereArgs: <Object?>[row['group_id'], row['source_message_id']],
          limit: 1,
        );
        if (existing.length != 1 ||
            !_samePendingBroadcastRow(existing.single, row)) {
          throw StateError('protected authority row conflict');
        }
      }
      await dbAppendGroupEventLogEntryInTransaction(
        transaction,
        groupId: groupId,
        eventType: 'protected_authority_prepared',
        sourcePeerId: authorityPreparedSourcePeerId,
        sourceEventId: authorityPreparedSourceEventId,
        sourceTimestamp: authorityPreparedSourceTimestamp,
        payload: authorityPreparedPayload,
      );
      return true;
    });
  } catch (_) {
    return false;
  }
}

enum DbProtectedGroupAuthorityAbortResult {
  aborted,
  alreadyAborted,
  refusedComplete,
  conflict,
}

/// Atomically fences one exact authenticated PREPARED transition as ABORTED
/// and retires the exact outbox owners supplied by its producer.
///
/// PREPARED is append-only, so deleting outbox rows alone is not a durable
/// cancellation. The ABORTED fact prevents rowless restart discovery from
/// later completing the abandoned event against an unrelated projection.
Future<DbProtectedGroupAuthorityAbortResult>
dbAbortPendingGroupBroadcastsWithAuthorityAtomically(
  Database db, {
  required String groupId,
  required List<Map<String, Object?>> expectedRows,
  required String authorityPreparedSourcePeerId,
  required String authorityPreparedSourceEventId,
  required String authorityPreparedSourceTimestamp,
  required Map<String, Object?> authorityPreparedPayload,
  required String authorityAbortedSourcePeerId,
  required String authorityAbortedSourceEventId,
  required String authorityAbortedSourceTimestamp,
  required Map<String, Object?> authorityAbortedPayload,
  required String authorityCompleteSourceEventId,
}) async {
  final preparedSuffix = authorityPreparedSourceEventId.startsWith('pga1:p:')
      ? authorityPreparedSourceEventId.substring('pga1:p:'.length)
      : null;
  final transitionId = preparedSuffix == null
      ? null
      : _decodeProtectedAuthorityTransitionId(preparedSuffix);
  final authorityIdentity = _protectedAuthorityFactIdentity(
    authorityPreparedPayload,
  );
  if (groupId.isEmpty ||
      authorityPreparedSourcePeerId.isEmpty ||
      authorityPreparedSourceEventId.isEmpty ||
      authorityPreparedSourceTimestamp.isEmpty ||
      authorityPreparedPayload.isEmpty ||
      authorityAbortedSourcePeerId.isEmpty ||
      authorityAbortedSourceEventId.isEmpty ||
      authorityAbortedSourceTimestamp.isEmpty ||
      authorityAbortedPayload.isEmpty ||
      authorityCompleteSourceEventId.isEmpty ||
      authorityPreparedSourcePeerId != authorityAbortedSourcePeerId ||
      authorityPreparedSourceTimestamp != authorityAbortedSourceTimestamp ||
      canonicalizeGroupEventLogPayload(authorityPreparedPayload) !=
          canonicalizeGroupEventLogPayload(authorityAbortedPayload) ||
      preparedSuffix == null ||
      preparedSuffix.isEmpty ||
      authorityAbortedSourceEventId != 'pga1:a:$preparedSuffix' ||
      authorityCompleteSourceEventId != 'pga1:c:$preparedSuffix' ||
      transitionId == null ||
      authorityIdentity == null ||
      authorityIdentity.groupId != groupId ||
      authorityIdentity.eventId != transitionId ||
      expectedRows.map((row) => row['id']).toSet().length !=
          expectedRows.length ||
      expectedRows.any(
        (row) =>
            row['group_id'] != groupId ||
            !_isProtectedAuthorityAbortOwner(
              row,
              groupId: groupId,
              transitionId: transitionId,
              authorityControl: authorityIdentity.control,
              allowedRecipientPeerIds: authorityIdentity.recipientPeerIds,
              allowActivatedRoleOwner: false,
            ),
      )) {
    return DbProtectedGroupAuthorityAbortResult.conflict;
  }

  try {
    return await dbWriteTransaction(db, (transaction) async {
      Future<Map<String, Object?>?> loadFact(String sourceEventId) async {
        final rows = await transaction.query(
          'group_event_log',
          where: 'group_id = ? AND source_event_id = ?',
          whereArgs: <Object?>[groupId, sourceEventId],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.single;
      }

      final complete = await loadFact(authorityCompleteSourceEventId);
      if (complete != null) {
        return DbProtectedGroupAuthorityAbortResult.refusedComplete;
      }

      final ownerClosure = await _loadProtectedAuthorityAbortOwnerClosure(
        transaction,
        groupId: groupId,
        transitionId: transitionId,
        authorityControl: authorityIdentity.control,
        allowedRecipientPeerIds: authorityIdentity.recipientPeerIds,
      );
      if (ownerClosure == null) {
        return DbProtectedGroupAuthorityAbortResult.conflict;
      }

      final aborted = await loadFact(authorityAbortedSourceEventId);
      if (aborted != null) {
        if (!_sameAuthorityFactRow(
          aborted,
          eventType: 'protected_authority_aborted',
          sourcePeerId: authorityAbortedSourcePeerId,
          sourceTimestamp: authorityAbortedSourceTimestamp,
          payload: authorityAbortedPayload,
        )) {
          return DbProtectedGroupAuthorityAbortResult.conflict;
        }
        if (ownerClosure.isNotEmpty) {
          // ABORTED is terminal only when no delivery/ordinary owner for the
          // same transition survived (or was recreated) underneath it.
          return DbProtectedGroupAuthorityAbortResult.conflict;
        }
        for (final expected in expectedRows) {
          final idCollision = await transaction.query(
            _table,
            columns: const <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[expected['id']],
            limit: 1,
          );
          if (idCollision.isNotEmpty) {
            return DbProtectedGroupAuthorityAbortResult.conflict;
          }
        }
        return DbProtectedGroupAuthorityAbortResult.alreadyAborted;
      }

      final prepared = await loadFact(authorityPreparedSourceEventId);
      if (prepared == null ||
          !_sameAuthorityFactRow(
            prepared,
            eventType: 'protected_authority_prepared',
            sourcePeerId: authorityPreparedSourcePeerId,
            sourceTimestamp: authorityPreparedSourceTimestamp,
            payload: authorityPreparedPayload,
          )) {
        return DbProtectedGroupAuthorityAbortResult.conflict;
      }

      if (authorityIdentity.recipientPeerIds.isNotEmpty &&
          !ownerClosure.values.any(
            (row) => row['kind'] == 'group_authority_v1',
          )) {
        // A nonempty signed ACL cannot legitimately produce a rowless
        // PREPARED fact. Per-target preparation may expose only a prefix of the
        // ACL, but at least one exact protected owner must accompany the fact.
        return DbProtectedGroupAuthorityAbortResult.conflict;
      }

      final expectedOwnerIds = expectedRows
          .map((row) => row['id'] as String)
          .toSet();
      if (ownerClosure.keys.toSet().length != expectedOwnerIds.length ||
          !ownerClosure.keys.toSet().containsAll(expectedOwnerIds)) {
        // Never append ABORTED beside an omitted owner. That combination would
        // suppress restart recovery while leaving an undrainable outbox row.
        return DbProtectedGroupAuthorityAbortResult.conflict;
      }

      for (final expected in expectedRows) {
        final existing = ownerClosure[expected['id']];
        if (existing == null || !_samePendingBroadcastRow(existing, expected)) {
          return DbProtectedGroupAuthorityAbortResult.conflict;
        }
      }
      for (final expected in expectedRows) {
        final deleted = await transaction.delete(
          _table,
          where: _pendingBroadcastExactWhere,
          whereArgs: _pendingBroadcastExactFields
              .map((field) => expected[field])
              .toList(growable: false),
        );
        if (deleted != 1) {
          throw StateError('protected authority abort owner changed');
        }
      }

      await dbAppendGroupEventLogEntryInTransaction(
        transaction,
        groupId: groupId,
        eventType: 'protected_authority_aborted',
        sourcePeerId: authorityAbortedSourcePeerId,
        sourceEventId: authorityAbortedSourceEventId,
        sourceTimestamp: authorityAbortedSourceTimestamp,
        payload: authorityAbortedPayload,
      );
      return DbProtectedGroupAuthorityAbortResult.aborted;
    });
  } catch (_) {
    return DbProtectedGroupAuthorityAbortResult.conflict;
  }
}

typedef _ProtectedAuthorityFactIdentity = ({
  String groupId,
  String eventId,
  String control,
  Set<String> recipientPeerIds,
});

_ProtectedAuthorityFactIdentity? _protectedAuthorityFactIdentity(
  Map<String, Object?> payload,
) {
  final proof = payload['proof'];
  if (proof is! Map) return null;
  final body = proof['body'];
  if (body is! Map) return null;
  final groupId = body['groupId'];
  final eventId = body['eventId'];
  final control = body['control'];
  final authorityData = body['authorityData'];
  final recipients = authorityData is Map
      ? authorityData['recipientTransportPeerIds']
      : null;
  if (groupId is! String ||
      groupId.isEmpty ||
      eventId is! String ||
      eventId.isEmpty ||
      control is! String ||
      control.isEmpty ||
      recipients is! List ||
      recipients.any(
        (recipient) =>
            recipient is! String ||
            recipient.isEmpty ||
            recipient.trim() != recipient,
      ) ||
      recipients.toSet().length != recipients.length) {
    return null;
  }
  return (
    groupId: groupId,
    eventId: eventId,
    control: control,
    recipientPeerIds: recipients.cast<String>().toSet(),
  );
}

String? _decodeProtectedAuthorityTransitionId(String encoded) {
  try {
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    final decoded = utf8.decode(bytes);
    if (decoded.isEmpty ||
        base64Url.encode(utf8.encode(decoded)).replaceAll('=', '') != encoded) {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}

typedef _ProtectedAuthorityDeliveryIdentity = ({
  String control,
  String transitionId,
  String recipientPeerId,
});

_ProtectedAuthorityDeliveryIdentity? _parseProtectedAuthorityDeliveryId(
  Object? raw,
) {
  if (raw is! String ||
      raw.isEmpty ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(raw)) {
    return null;
  }
  var offset = 0;
  String? readField() {
    final colon = raw.indexOf(':', offset);
    if (colon <= offset) return null;
    final length = int.tryParse(raw.substring(offset, colon));
    if (length == null || length <= 0) return null;
    final start = colon + 1;
    final end = start + length;
    if (end > raw.length) return null;
    final value = raw.substring(start, end);
    offset = end;
    return value;
  }

  final control = readField();
  final transitionId = readField();
  final recipientPeerId = readField();
  if (control == null ||
      transitionId == null ||
      recipientPeerId == null ||
      offset != raw.length) {
    return null;
  }
  return (
    control: control,
    transitionId: transitionId,
    recipientPeerId: recipientPeerId,
  );
}

bool _isProtectedAuthorityAbortOwner(
  Map<String, Object?> row, {
  required String groupId,
  required String transitionId,
  required String authorityControl,
  required Set<String> allowedRecipientPeerIds,
  required bool allowActivatedRoleOwner,
}) {
  final id = row['id'];
  final kind = row['kind'];
  final sourceMessageId = row['source_message_id'];
  if (id is! String || id.isEmpty || row['group_id'] != groupId) return false;

  if (kind == 'group_authority_v1') {
    final identity = _parseProtectedAuthorityDeliveryId(sourceMessageId);
    if (identity == null ||
        identity.control != authorityControl ||
        identity.transitionId != transitionId ||
        !allowedRecipientPeerIds.contains(identity.recipientPeerId) ||
        id != 'protected-authority:$sourceMessageId') {
      return false;
    }
    final encodedRecipients = row['recipient_peer_ids'];
    if (encodedRecipients is! String) return false;
    try {
      final decoded = jsonDecode(encodedRecipients);
      return decoded is List &&
          decoded.length == 1 &&
          decoded.single == identity.recipientPeerId;
    } catch (_) {
      return false;
    }
  }

  final isPreparedRole = kind == 'member_role_updated_prepared';
  final isActivatedRole = kind == 'member_role_updated';
  return authorityControl == 'member_role_updated' &&
      (isPreparedRole || (allowActivatedRoleOwner && isActivatedRole)) &&
      sourceMessageId == transitionId &&
      id == 'pending_group_broadcast:$groupId:$transitionId';
}

Future<Map<String, Map<String, Object?>>?>
_loadProtectedAuthorityAbortOwnerClosure(
  DatabaseExecutor transaction, {
  required String groupId,
  required String transitionId,
  required String authorityControl,
  required Set<String> allowedRecipientPeerIds,
}) async {
  final rows = await transaction.query(
    _table,
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
  );
  final owners = <String, Map<String, Object?>>{};
  for (final row in rows) {
    final kind = row['kind'];
    if (kind == 'group_authority_v1') {
      final identity = _parseProtectedAuthorityDeliveryId(
        row['source_message_id'],
      );
      // The same conservative rule is used by restart discovery: an
      // unattributable protected row might own this transition, so cancellation
      // cannot safely establish a terminal negative fact beside it.
      if (identity == null) return null;
      if (identity.transitionId != transitionId) continue;
      if (!_isProtectedAuthorityAbortOwner(
        row,
        groupId: groupId,
        transitionId: transitionId,
        authorityControl: authorityControl,
        allowedRecipientPeerIds: allowedRecipientPeerIds,
        allowActivatedRoleOwner: false,
      )) {
        return null;
      }
    } else if ((kind == 'member_role_updated_prepared' ||
            kind == 'member_role_updated') &&
        row['source_message_id'] == transitionId) {
      if (!_isProtectedAuthorityAbortOwner(
        row,
        groupId: groupId,
        transitionId: transitionId,
        authorityControl: authorityControl,
        allowedRecipientPeerIds: allowedRecipientPeerIds,
        allowActivatedRoleOwner: true,
      )) {
        return null;
      }
    } else {
      continue;
    }
    final id = row['id'];
    if (id is! String || owners.containsKey(id)) return null;
    owners[id] = row;
  }
  return owners;
}

bool _sameAuthorityFactRow(
  Map<String, Object?> row, {
  required String eventType,
  required String sourcePeerId,
  required String sourceTimestamp,
  required Map<String, Object?> payload,
}) {
  return row['event_type'] == eventType &&
      row['source_peer_id'] == sourcePeerId &&
      row['source_timestamp'] == sourceTimestamp &&
      row['canonical_payload'] == canonicalizeGroupEventLogPayload(payload);
}

/// Retires one exact protected-authority row inside a caller-owned terminal
/// transaction. This deliberately bypasses the ordinary live-parent predicate:
/// the same transaction has already advanced (or is about to advance) the
/// exact group to its terminal dissolved projection.
Future<void> dbDeleteProtectedGroupAuthorityBroadcastIfExactInTransaction(
  DatabaseExecutor transaction, {
  required String groupId,
  required Map<String, Object?> expected,
}) async {
  if (groupId.isEmpty ||
      expected['group_id'] != groupId ||
      expected['kind'] != 'group_authority_v1') {
    throw StateError('invalid protected dissolve broadcast');
  }
  final deleted = await transaction.delete(
    _table,
    where: _pendingBroadcastExactWhere,
    whereArgs: _pendingBroadcastExactFields
        .map((field) => expected[field])
        .toList(growable: false),
  );
  if (deleted != 1) {
    throw StateError('protected dissolve broadcast changed before commit');
  }
}

bool _samePendingBroadcastRow(
  Map<String, Object?> existing,
  Map<String, Object?> expected,
) {
  for (final field in _pendingBroadcastExactFields) {
    if (existing[field] != expected[field]) return false;
  }
  return true;
}

/// Transaction-body variant for atomic authority producers.
Future<void> dbInsertPendingGroupBroadcastWithExecutor(
  DatabaseExecutor transaction,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String;
  final sourceMessageId = row['source_message_id'] as String?;
  if (!await dbAllowsOrdinaryGroupWrite(transaction, groupId)) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_BROADCAST_DB_INSERT_REFUSED_PARENT',
      details: {'groupId': _safeId(groupId)},
    );
    return;
  }
  if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
    final existing = await transaction.query(
      _table,
      where: 'group_id = ? AND source_message_id = ?',
      whereArgs: [groupId, sourceMessageId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingKind = existing.first['kind'] as String?;
      final incomingKind = row['kind'] as String?;
      if (existingKind == 'member_role_updated_prepared' &&
          incomingKind == 'member_role_updated') {
        if (!await dbAllowsPendingRoleBroadcastMutation(
          transaction,
          groupId: groupId,
          existingKind: existingKind,
          incomingKind: incomingKind!,
        )) {
          emitFlowEvent(
            layer: 'DB',
            event: 'PENDING_GROUP_BROADCAST_DB_ACTIVATION_REFUSED_EXIT',
            details: {'groupId': _safeId(groupId)},
          );
          return;
        }
        // Activation replaces every authoritative field, including the row
        // id, so exact verification and later removal refer to one payload.
        await dbUpdateOrdinaryGroupOwnedRows(
          transaction,
          table: _table,
          groupId: groupId,
          values: row,
          where: 'group_id = ? AND source_message_id = ?',
          whereArgs: [groupId, sourceMessageId],
        );
        emitFlowEvent(
          layer: 'DB',
          event: 'PENDING_GROUP_BROADCAST_DB_ACTIVATED',
          details: {'groupId': _safeId(groupId)},
        );
        return;
      }
      emitFlowEvent(
        layer: 'DB',
        event: 'PENDING_GROUP_BROADCAST_DB_INSERT_DEDUP',
        details: {'groupId': _safeId(groupId)},
      );
      return;
    }
  }

  final incomingKind = row['kind'] as String?;
  if (incomingKind != null &&
      !await dbAllowsPendingRoleBroadcastMutation(
        transaction,
        groupId: groupId,
        incomingKind: incomingKind,
      )) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_BROADCAST_DB_INSERT_REFUSED_EXIT',
      details: {'groupId': _safeId(groupId)},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_INSERT_START',
    details: {'groupId': _safeId(groupId)},
  );
  await dbInsertOrdinaryGroupOwnedRow(
    transaction,
    table: _table,
    row: row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_INSERT_SUCCESS',
    details: {'groupId': _safeId(groupId)},
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM $_table '
    'WHERE group_id = ? AND $parent '
    'ORDER BY created_at ASC',
    [groupId],
  );
}

Future<List<Map<String, Object?>>> dbLoadAllPendingGroupBroadcasts(
  Database db,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM $_table WHERE $parent ORDER BY created_at ASC',
  );
}

Future<int> dbCountPendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM $_table WHERE group_id = ? AND $parent',
    [groupId],
  );
  return (rows.first['c'] as int?) ?? 0;
}

Future<void> dbDeletePendingGroupBroadcast(Database db, String id) async {
  await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_DELETE',
    details: {'id': _safeId(id)},
  );
}

Future<bool> dbDeletePendingGroupBroadcastIfExact(
  Database db,
  Map<String, Object?> expected,
) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  final deleted = await db.delete(
    _table,
    where: '($_pendingBroadcastExactWhere) AND group_id = ? AND $parent',
    whereArgs: [
      ..._pendingBroadcastExactFields.map((field) => expected[field]),
      groupId,
    ],
  );
  return deleted == 1;
}

/// Atomically removes one physical survivor from an exact protected row.
/// Zero survivors retires the row; a stale compare changes nothing.
Future<bool> dbRemovePendingGroupBroadcastRecipientIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required String recipientPeerId,
  required String updatedAt,
}) {
  return dbWriteTransaction(db, (transaction) async {
    final rows = await transaction.query(
      _table,
      where: 'id = ?',
      whereArgs: [expected['id']],
      limit: 1,
    );
    if (rows.length != 1) return false;
    for (final field in _pendingBroadcastExactFields) {
      if (rows.single[field] != expected[field]) return false;
    }
    final rawRecipients = expected['recipient_peer_ids'] as String? ?? '[]';
    final decoded = jsonDecode(rawRecipients);
    if (decoded is! List ||
        decoded.any((value) => value is! String) ||
        !decoded.contains(recipientPeerId)) {
      return false;
    }
    final survivors = decoded.cast<String>()
      ..removeWhere((value) => value == recipientPeerId);
    if (survivors.isEmpty) {
      return await transaction.delete(
            _table,
            where: 'id = ?',
            whereArgs: [expected['id']],
          ) ==
          1;
    }
    return await transaction.update(
          _table,
          {
            'recipient_peer_ids': jsonEncode(survivors),
            'updated_at': updatedAt,
          },
          where: 'id = ?',
          whereArgs: [expected['id']],
        ) ==
        1;
  });
}

Future<void> dbDeletePendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  final deleted = await db.delete(
    _table,
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_DELETE_GROUP',
    details: {'groupId': _safeId(groupId), 'deleted': deleted},
  );
}
