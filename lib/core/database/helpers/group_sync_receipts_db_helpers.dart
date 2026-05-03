import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../features/groups/domain/models/group_message_receipt.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';

typedef GroupInboxTransactionApply =
    Future<void> Function(DatabaseExecutor executor);

Future<Map<String, Object?>?> dbLoadGroupInboxCursor(
  DatabaseExecutor db,
  String groupId,
) async {
  final rows = await db.query(
    'group_inbox_cursors',
    where: 'group_id = ?',
    whereArgs: [groupId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<void> dbUpsertGroupInboxCursor(
  DatabaseExecutor db, {
  required String groupId,
  required String cursor,
  DateTime? updatedAt,
}) async {
  final now = (updatedAt ?? DateTime.now().toUtc()).toUtc();
  final existing = await dbLoadGroupInboxCursor(db, groupId);
  if (existing == null) {
    await db.insert('group_inbox_cursors', {
      'group_id': groupId,
      'cursor': cursor,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return;
  }

  await db.update(
    'group_inbox_cursors',
    {'cursor': cursor, 'updated_at': now.toIso8601String()},
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}

Future<void> dbUpsertGroupMessageReceipt(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String;
  final messageId = row['message_id'] as String;
  final receiptType = row['receipt_type'] as String;
  final memberPeerId = row['member_peer_id'] as String;
  final existing = await db.query(
    'group_message_receipts',
    where:
        'group_id = ? AND message_id = ? AND receipt_type = ? AND member_peer_id = ?',
    whereArgs: [groupId, messageId, receiptType, memberPeerId],
    limit: 1,
  );

  if (existing.isEmpty) {
    await db.insert('group_message_receipts', row);
    return;
  }

  await db.update(
    'group_message_receipts',
    {
      'sender_device_id': row['sender_device_id'],
      'receipt_at': row['receipt_at'],
      'source_event_id': row['source_event_id'],
      'updated_at': row['updated_at'],
    },
    where:
        'group_id = ? AND message_id = ? AND receipt_type = ? AND member_peer_id = ?',
    whereArgs: [groupId, messageId, receiptType, memberPeerId],
  );
}

Future<List<Map<String, Object?>>> dbLoadGroupMessageReceipts(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
  String? receiptType,
}) {
  final where = StringBuffer('group_id = ? AND message_id = ?');
  final args = <Object?>[groupId, messageId];
  if (receiptType != null) {
    where.write(' AND receipt_type = ?');
    args.add(receiptType);
  }
  return db.query(
    'group_message_receipts',
    where: where.toString(),
    whereArgs: args,
    orderBy: 'receipt_type ASC, member_peer_id ASC',
  );
}

Future<void> dbApplyGroupInboxPageTransaction(
  Database db, {
  required String groupId,
  required String nextCursor,
  required GroupInboxTransactionApply apply,
  required List<Map<String, Object?>> Function() receiptRows,
  List<String> Function()? markReadMessageIds,
  Future<void> Function(DatabaseExecutor executor)? beforeCommitForTest,
}) {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INBOX_PAGE_TRANSACTION_START',
    details: {'groupId': _safeId(groupId)},
  );

  return dbWriteTransaction(db, (txn) async {
    await apply(txn);

    final now = DateTime.now().toUtc();
    for (final receipt in receiptRows()) {
      await dbUpsertGroupMessageReceipt(txn, receipt);
    }

    for (final messageId in markReadMessageIds?.call() ?? const <String>[]) {
      await txn.rawUpdate(
        'UPDATE group_messages SET read_at = COALESCE(read_at, ?) WHERE id = ? AND group_id = ?',
        [now.toIso8601String(), messageId, groupId],
      );
    }

    await dbUpsertGroupInboxCursor(
      txn,
      groupId: groupId,
      cursor: nextCursor,
      updatedAt: now,
    );

    if (beforeCommitForTest != null) {
      await beforeCommitForTest(txn);
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INBOX_PAGE_TRANSACTION_SUCCESS',
      details: {
        'groupId': _safeId(groupId),
        'hasCursor': nextCursor.isNotEmpty,
      },
    );
  });
}

List<String> groupMessageIdsForLocalReadReceipts(
  Iterable<GroupMessageReceipt> receipts, {
  required String? localPeerId,
}) {
  final peerId = localPeerId?.trim();
  if (peerId == null || peerId.isEmpty) return const [];
  return receipts
      .where(
        (receipt) =>
            receipt.memberPeerId == peerId &&
            receipt.receiptType == groupMessageReceiptTypeRead,
      )
      .map((receipt) => receipt.messageId)
      .toSet()
      .toList(growable: false);
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
