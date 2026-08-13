import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';

typedef AppendGroupEventLogEntry =
    Future<Map<String, Object?>> Function({
      required String groupId,
      required String eventType,
      required String sourcePeerId,
      required String sourceEventId,
      required String sourceTimestamp,
      required Map<String, Object?> payload,
      DateTime? createdAt,
    });

/// Result of an append attempted inside an existing SQL transaction.
///
/// [inserted] is false only for an exact replay of the same source event. A
/// conflicting replay still throws [GroupEventLogTamperException]. Callers
/// that require a phase-unique fact (for example an accepted-membership
/// binding) can therefore reject replay without opening a nested transaction.
class GroupEventLogAppendResult {
  const GroupEventLogAppendResult({required this.row, required this.inserted});

  final Map<String, Object?> row;
  final bool inserted;
}

class GroupEventLogTamperException implements Exception {
  GroupEventLogTamperException(this.message);

  final String message;

  @override
  String toString() => 'GroupEventLogTamperException: $message';
}

class GroupEventLogChainViolation {
  const GroupEventLogChainViolation({
    required this.groupId,
    required this.sequence,
    required this.reason,
  });

  final String groupId;
  final int sequence;
  final String reason;

  @override
  String toString() =>
      'GroupEventLogChainViolation(groupId: $groupId, '
      'sequence: $sequence, reason: $reason)';
}

String canonicalizeGroupEventLogPayload(Map<String, Object?> payload) {
  return jsonEncode(_canonicalizeValue(payload));
}

Future<Map<String, Object?>> dbAppendGroupEventLogEntry(
  Database db, {
  required String groupId,
  required String eventType,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> payload,
  DateTime? createdAt,
}) {
  return dbWriteTransaction(db, (txn) async {
    final result = await dbAppendGroupEventLogEntryInTransaction(
      txn,
      groupId: groupId,
      eventType: eventType,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      payload: payload,
      createdAt: createdAt,
    );
    return result.row;
  });
}

/// Appends an event-log entry using the caller's transaction.
///
/// This is the transaction-scoped counterpart to [dbAppendGroupEventLogEntry].
/// It deliberately accepts [DatabaseExecutor] so migration callbacks and
/// already-open write transactions can share the same primitive without
/// nesting [dbWriteTransaction].
Future<GroupEventLogAppendResult> dbAppendGroupEventLogEntryInTransaction(
  DatabaseExecutor txn, {
  required String groupId,
  required String eventType,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> payload,
  DateTime? createdAt,
}) {
  return _appendGroupEventLogEntry(
    txn,
    groupId: groupId,
    eventType: eventType,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    payload: payload,
    createdAt: createdAt,
  );
}

Future<List<Map<String, Object?>>> dbLoadGroupEventLogEntries(
  Database db,
  String groupId,
) {
  return db.query(
    'group_event_log',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'sequence ASC',
  );
}

Future<Map<String, Object?>?> dbLoadGroupEventLogEntryExact(
  Database db, {
  required String groupId,
  required String sourceEventId,
}) async {
  final rows = await db.query(
    'group_event_log',
    where: 'group_id = ? AND source_event_id = ?',
    whereArgs: <Object?>[groupId, sourceEventId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Bounded history page in chronological index order, optionally newest-first.
/// [afterSourceTimestamp]/[afterSourceEventId] always mean after the cursor in
/// the selected order, so descending callers page toward older rows.
Future<List<Map<String, Object?>>> dbLoadGroupEventLogTypePage(
  Database db, {
  required String groupId,
  required String eventType,
  String? afterSourceTimestamp,
  String? afterSourceEventId,
  String? throughSourceTimestamp,
  bool newestFirst = false,
  int limit = 100,
}) {
  if (limit < 1 || limit > 200) {
    throw RangeError.range(limit, 1, 200, 'limit');
  }
  final where = <String>['group_id = ?', 'event_type = ?'];
  final args = <Object?>[groupId, eventType];
  if (afterSourceTimestamp != null) {
    final comparison = newestFirst ? '<' : '>';
    where.add(
      '(source_timestamp $comparison ? OR '
      '(source_timestamp = ? AND source_event_id $comparison ?))',
    );
    args.addAll(<Object?>[
      afterSourceTimestamp,
      afterSourceTimestamp,
      afterSourceEventId ?? '',
    ]);
  }
  if (throughSourceTimestamp != null) {
    where.add('source_timestamp <= ?');
    args.add(throughSourceTimestamp);
  }
  return db.query(
    'group_event_log',
    where: where.join(' AND '),
    whereArgs: args,
    orderBy: newestFirst
        ? 'source_timestamp DESC, source_event_id DESC'
        : 'source_timestamp ASC, source_event_id ASC',
    limit: limit,
  );
}

/// Loads authenticated PREPARED facts that have no terminal COMPLETE/ABORTED
/// fact, directly at the durable event-log boundary.
///
/// Filtering terminal rows and the authenticated local author in SQL keeps
/// restart discovery bounded without starving an old interrupted transition
/// behind newer completed work or receiver-authored PREPARED history.
Future<List<Map<String, Object?>>> dbLoadUnfinishedProtectedAuthorityPage(
  Database db, {
  required String groupId,
  required String sourcePeerId,
  String? afterSourceTimestamp,
  String? afterSourceEventId,
  int limit = 100,
}) {
  if (sourcePeerId.isEmpty) {
    throw ArgumentError.value(sourcePeerId, 'sourcePeerId');
  }
  if (limit < 1 || limit > 200) {
    throw RangeError.range(limit, 1, 200, 'limit');
  }
  final where = <String>[
    'prepared.group_id = ?',
    'prepared.source_peer_id = ?',
    "prepared.event_type = 'protected_authority_prepared'",
    "prepared.source_event_id LIKE 'pga1:p:%'",
    '''NOT EXISTS (
      SELECT 1
      FROM group_event_log AS terminal
      WHERE terminal.group_id = prepared.group_id
        AND terminal.event_type IN (
          'protected_authority_complete',
          'protected_authority_aborted'
        )
        AND terminal.source_event_id IN (
          'pga1:c:' || substr(prepared.source_event_id, 8),
          'pga1:a:' || substr(prepared.source_event_id, 8)
        )
    )''',
  ];
  final args = <Object?>[groupId, sourcePeerId];
  if (afterSourceTimestamp != null) {
    where.add(
      '(prepared.source_timestamp < ? OR '
      '(prepared.source_timestamp = ? AND prepared.source_event_id < ?))',
    );
    args.addAll(<Object?>[
      afterSourceTimestamp,
      afterSourceTimestamp,
      afterSourceEventId ?? '',
    ]);
  }
  return db.rawQuery(
    '''
      SELECT prepared.*
      FROM group_event_log AS prepared
      WHERE ${where.join(' AND ')}
      ORDER BY prepared.source_timestamp DESC, prepared.source_event_id DESC
      LIMIT ?
    ''',
    <Object?>[...args, limit],
  );
}

Future<List<GroupEventLogChainViolation>> dbVerifyGroupEventLogChain(
  Database db,
) async {
  final rows = await db.query(
    'group_event_log',
    orderBy: 'group_id ASC, sequence ASC',
  );
  final violations = <GroupEventLogChainViolation>[];
  String? currentGroupId;
  var expectedSequence = 1;
  String? previousHash;

  for (final row in rows) {
    final groupId = row['group_id'] as String;
    final sequence = row['sequence'] as int;
    if (groupId != currentGroupId) {
      currentGroupId = groupId;
      expectedSequence = 1;
      previousHash = null;
    }

    if (sequence != expectedSequence) {
      violations.add(
        GroupEventLogChainViolation(
          groupId: groupId,
          sequence: sequence,
          reason: 'sequence_gap',
        ),
      );
    }

    final storedPreviousHash = row['previous_entry_hash'] as String?;
    if (storedPreviousHash != previousHash) {
      violations.add(
        GroupEventLogChainViolation(
          groupId: groupId,
          sequence: sequence,
          reason: 'previous_hash_mismatch',
        ),
      );
    }

    final recomputedHash = _computeEntryHash(
      groupId: groupId,
      sequence: sequence,
      eventType: row['event_type'] as String,
      sourcePeerId: row['source_peer_id'] as String,
      sourceEventId: row['source_event_id'] as String,
      sourceTimestamp: row['source_timestamp'] as String,
      canonicalPayload: row['canonical_payload'] as String,
      previousEntryHash: storedPreviousHash,
      createdAt: row['created_at'] as String,
    );
    final storedHash = row['entry_hash'] as String;
    if (recomputedHash != storedHash) {
      violations.add(
        GroupEventLogChainViolation(
          groupId: groupId,
          sequence: sequence,
          reason: 'entry_hash_mismatch',
        ),
      );
    }

    previousHash = storedHash;
    expectedSequence++;
  }

  return violations;
}

Future<GroupEventLogAppendResult> _appendGroupEventLogEntry(
  DatabaseExecutor txn, {
  required String groupId,
  required String eventType,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> payload,
  DateTime? createdAt,
}) async {
  if (groupId.isEmpty || eventType.isEmpty || sourceEventId.isEmpty) {
    throw ArgumentError('groupId, eventType, and sourceEventId are required');
  }

  final canonicalPayload = canonicalizeGroupEventLogPayload(payload);
  final existing = await txn.query(
    'group_event_log',
    where: 'group_id = ? AND source_event_id = ?',
    whereArgs: [groupId, sourceEventId],
    limit: 1,
  );
  if (existing.isNotEmpty) {
    final row = existing.single;
    final exactReplay =
        row['event_type'] == eventType &&
        row['source_peer_id'] == sourcePeerId &&
        row['source_timestamp'] == sourceTimestamp &&
        row['canonical_payload'] == canonicalPayload;
    if (!exactReplay) {
      throw GroupEventLogTamperException(
        'conflicting_replay source_event=${_safeDiagnosticId(sourceEventId)}',
      );
    }
    return GroupEventLogAppendResult(row: row, inserted: false);
  }

  final latest = await txn.query(
    'group_event_log',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'sequence DESC',
    limit: 1,
  );
  final previousEntryHash = latest.isEmpty
      ? null
      : latest.single['entry_hash'] as String;
  final sequence = latest.isEmpty ? 1 : (latest.single['sequence'] as int) + 1;
  final createdAtIso = (createdAt ?? DateTime.now().toUtc()).toIso8601String();
  final entryHash = _computeEntryHash(
    groupId: groupId,
    sequence: sequence,
    eventType: eventType,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    canonicalPayload: canonicalPayload,
    previousEntryHash: previousEntryHash,
    createdAt: createdAtIso,
  );
  final row = <String, Object?>{
    'id': _stableEntryId(groupId, sourceEventId),
    'group_id': groupId,
    'sequence': sequence,
    'event_type': eventType,
    'source_peer_id': sourcePeerId,
    'source_event_id': sourceEventId,
    'source_timestamp': sourceTimestamp,
    'canonical_payload': canonicalPayload,
    'previous_entry_hash': previousEntryHash,
    'entry_hash': entryHash,
    'created_at': createdAtIso,
  };

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_EVENT_LOG_DB_APPEND_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'eventType': eventType,
      'sequence': sequence,
    },
  );

  await txn.insert('group_event_log', row);

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_EVENT_LOG_DB_APPEND_SUCCESS',
    details: {'eventType': eventType, 'sequence': sequence},
  );

  return GroupEventLogAppendResult(row: row, inserted: true);
}

String _stableEntryId(String groupId, String sourceEventId) {
  return sha256.convert(utf8.encode('$groupId\u001f$sourceEventId')).toString();
}

String _safeDiagnosticId(String value) {
  final digest = sha256.convert(utf8.encode(value)).toString();
  return digest.substring(0, 12);
}

String _computeEntryHash({
  required String groupId,
  required int sequence,
  required String eventType,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required String canonicalPayload,
  required String? previousEntryHash,
  required String createdAt,
}) {
  final hashPayload = canonicalizeGroupEventLogPayload({
    'groupId': groupId,
    'sequence': sequence,
    'eventType': eventType,
    'sourcePeerId': sourcePeerId,
    'sourceEventId': sourceEventId,
    'sourceTimestamp': sourceTimestamp,
    'canonicalPayload': canonicalPayload,
    'previousEntryHash': previousEntryHash,
    'createdAt': createdAt,
  });
  return sha256.convert(utf8.encode(hashPayload)).toString();
}

Object? _canonicalizeValue(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key.toString()] = _canonicalizeValue(entry.value);
    }
    return sorted;
  }
  if (value is Iterable) {
    return value.map(_canonicalizeValue).toList(growable: false);
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  return value;
}
