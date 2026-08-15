import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/services/protected_group_content_contract.dart';

/// Classifies the durable target shape for strict protected reactions.
///
/// Existing ordinary blob-free messages remain valid targets even when they
/// predate protected-message evidence. An existing ineligible shape is
/// terminal; only a genuinely absent row remains eligible to wait for a
/// crossed staged message.
Future<ProtectedGroupReactionTargetDisposition>
dbClassifyProtectedGroupReactionTarget(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
}) async {
  final rows = await db.query(
    'group_messages',
    columns: const <String>[
      'group_id',
      'text',
      'quoted_message_id',
      'is_forwarded',
      'media_policy_version',
    ],
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return ProtectedGroupReactionTargetDisposition.prerequisiteWaiting;
  }
  final row = rows.single;
  final hasMediaTable = (await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'media_attachments' LIMIT 1",
  )).isNotEmpty;
  final media = !hasMediaTable
      ? const <Map<String, Object?>>[]
      : await db.query(
          'media_attachments',
          columns: const <String>['id'],
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
          limit: 1,
        );
  final text = row['text'];
  final eligible =
      row['group_id'] == groupId &&
      text is String &&
      text.trim().isNotEmpty &&
      !text.trimLeft().startsWith(r'{"__sys":') &&
      (row['quoted_message_id'] as String?)?.isNotEmpty != true &&
      (row['is_forwarded'] as num?)?.toInt() != 1 &&
      (row['media_policy_version'] as num?)?.toInt() == 0 &&
      media.isEmpty;
  return eligible
      ? ProtectedGroupReactionTargetDisposition.available
      : ProtectedGroupReactionTargetDisposition.terminal;
}

/// Production classifier shared by protected receive and sender retry. The
/// scalar target check owns existing legacy/protected rows; exact deletion and
/// terminal history upgrade only a genuinely absent target from waiting to a
/// permanent terminal disposition.
Future<ProtectedGroupReactionTargetDisposition>
dbClassifyProtectedGroupReactionTargetWithEvidence(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
}) async {
  final target = await dbClassifyProtectedGroupReactionTarget(
    db,
    groupId: groupId,
    messageId: messageId,
  );
  if (target != ProtectedGroupReactionTargetDisposition.prerequisiteWaiting) {
    return target;
  }
  final deletionTable = (await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'group_message_local_deletions' LIMIT 1",
  )).isNotEmpty;
  if (deletionTable) {
    final deletion = await db.query(
      'group_message_local_deletions',
      columns: const <String>['group_id'],
      where: 'message_id = ? AND group_id = ?',
      whereArgs: <Object?>[messageId, groupId],
      limit: 1,
    );
    if (deletion.isNotEmpty) {
      return ProtectedGroupReactionTargetDisposition.terminal;
    }
  }
  return await dbHasProtectedGroupContentTerminalInTransaction(
        db,
        groupId: groupId,
        payloadType: protectedGroupContentMessagePayloadType,
        contentEventId: messageId,
      )
      ? ProtectedGroupReactionTargetDisposition.terminal
      : ProtectedGroupReactionTargetDisposition.prerequisiteWaiting;
}
