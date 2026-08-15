import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/deterministic_notification_id.dart';
import 'group_event_log_db_helpers.dart';

const String protectedGroupReactionDisplayTerminalEventType =
    'protected_reaction_display_terminal';
const String _protectedGroupReactionEventType = 'protected_reaction';

String protectedGroupReactionDisplayTerminalSourceEventId(String transitionId) {
  final normalized = transitionId.trim();
  if (normalized.isEmpty || normalized != transitionId) {
    throw ArgumentError.value(
      transitionId,
      'transitionId',
      'must be canonical and non-empty',
    );
  }
  return 'prdt1:$normalized';
}

Map<String, Object?> _terminalPayload({
  required String groupId,
  required String transitionId,
  required String messageId,
  required String actorPeerId,
  required String reactionId,
  required String eventTimestamp,
}) => <String, Object?>{
  'reasonCode': protectedGroupReactionDisplayTerminalEventType,
  'groupId': groupId,
  'contentEventId': transitionId,
  'messageId': messageId,
  'actorPeerId': actorPeerId,
  'reactionId': reactionId,
  'action': 'add',
  'eventTimestamp': eventTimestamp,
  'terminalEventIdentity': boundedReactionEventIdentity(transitionId),
};

/// Appends durable suppression only when [transitionId] is already backed by
/// exact protected-reaction evidence.
///
/// The caller owns the surrounding transaction that updates the canonical
/// reaction and retires display custody. A protected transition with no exact
/// canonical update is an invariant violation and rolls that transaction back.
Future<bool> dbAppendProtectedGroupReactionDisplayTerminalIfExact(
  DatabaseExecutor txn, {
  required String groupId,
  required String transitionId,
  required String messageId,
  required String actorPeerId,
  required String reactionId,
  required String eventTimestamp,
}) async {
  if (!await _groupEventLogExists(txn)) return false;
  final sourceRows = await txn.query(
    'group_event_log',
    where: 'group_id = ? AND source_event_id = ?',
    whereArgs: <Object?>[groupId, 'pr1:$transitionId'],
    limit: 1,
  );
  if (sourceRows.isEmpty) return false;
  final source = sourceRows.single;
  if (!_isExactProtectedAddSource(
    source,
    groupId: groupId,
    transitionId: transitionId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    reactionId: reactionId,
    eventTimestamp: eventTimestamp,
  )) {
    throw GroupEventLogTamperException(
      'protected reaction display source authority conflict',
    );
  }
  await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: groupId,
    eventType: protectedGroupReactionDisplayTerminalEventType,
    sourcePeerId: actorPeerId,
    sourceEventId: protectedGroupReactionDisplayTerminalSourceEventId(
      transitionId,
    ),
    sourceTimestamp: eventTimestamp,
    payload: _terminalPayload(
      groupId: groupId,
      transitionId: transitionId,
      messageId: messageId,
      actorPeerId: actorPeerId,
      reactionId: reactionId,
      eventTimestamp: eventTimestamp,
    ),
  );
  return true;
}

/// Exact-loads durable display suppression for one protected ADD transition.
/// A row under the domain-separated source id with different authority is
/// tamper, not absence.
Future<bool> dbHasProtectedGroupReactionDisplayTerminalExact(
  DatabaseExecutor db, {
  required String groupId,
  required String transitionId,
  required String messageId,
  required String actorPeerId,
  required String reactionId,
  required String eventTimestamp,
}) async {
  if (!await _groupEventLogExists(db)) return false;
  final rows = await db.query(
    'group_event_log',
    where: 'group_id = ? AND source_event_id = ?',
    whereArgs: <Object?>[
      groupId,
      protectedGroupReactionDisplayTerminalSourceEventId(transitionId),
    ],
    limit: 1,
  );
  if (rows.isEmpty) return false;
  final row = rows.single;
  final exact =
      row['event_type'] == protectedGroupReactionDisplayTerminalEventType &&
      row['source_peer_id'] == actorPeerId &&
      row['source_timestamp'] == eventTimestamp &&
      row['canonical_payload'] ==
          canonicalizeGroupEventLogPayload(
            _terminalPayload(
              groupId: groupId,
              transitionId: transitionId,
              messageId: messageId,
              actorPeerId: actorPeerId,
              reactionId: reactionId,
              eventTimestamp: eventTimestamp,
            ),
          );
  if (!exact) {
    throw GroupEventLogTamperException(
      'protected reaction display terminal authority conflict',
    );
  }
  return true;
}

Future<bool> _groupEventLogExists(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>['group_event_log'],
  );
  return rows.isNotEmpty;
}

bool _isExactProtectedAddSource(
  Map<String, Object?> row, {
  required String groupId,
  required String transitionId,
  required String messageId,
  required String actorPeerId,
  required String reactionId,
  required String eventTimestamp,
}) {
  if (row['event_type'] != _protectedGroupReactionEventType ||
      row['source_peer_id'] != actorPeerId ||
      row['source_timestamp'] != eventTimestamp) {
    return false;
  }
  try {
    final decoded = jsonDecode(row['canonical_payload'] as String);
    if (decoded is! Map) return false;
    final payload = decoded['payload'];
    return payload is Map &&
        decoded['custodyKind'] == 'group_content_v1' &&
        decoded['groupId'] == groupId &&
        decoded['payloadType'] == 'group_reaction' &&
        decoded['contentEventId'] == transitionId &&
        decoded['logicalSenderPeerId'] == actorPeerId &&
        payload['id'] == reactionId &&
        payload['eventId'] == transitionId &&
        payload['messageId'] == messageId &&
        payload['senderPeerId'] == actorPeerId &&
        payload['action'] == 'add' &&
        payload['timestamp'] == eventTimestamp;
  } catch (_) {
    return false;
  }
}
