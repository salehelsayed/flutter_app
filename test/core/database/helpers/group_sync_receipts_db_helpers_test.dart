import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_sync_receipts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/061_group_message_transport_peer_id.dart';
import 'package:flutter_app/core/database/migrations/066_group_sync_receipts.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _runSchema(db);
  });

  tearDown(() async {
    await db.close();
  });

  GroupMessage message({String id = 'msg-1', DateTime? readAt}) {
    final now = DateTime.utc(2026, 5, 1, 12);
    return GroupMessage(
      id: id,
      groupId: 'group-1',
      senderPeerId: 'peer-a',
      senderUsername: 'Alice',
      text: 'hello',
      timestamp: now,
      keyGeneration: 1,
      status: 'delivered',
      isIncoming: true,
      readAt: readAt,
      createdAt: now,
    );
  }

  GroupMessageReceipt receipt({
    String messageId = 'msg-1',
    String type = groupMessageReceiptTypeDelivered,
    String memberPeerId = 'peer-local',
  }) {
    final now = DateTime.utc(2026, 5, 1, 12, 1);
    return GroupMessageReceipt(
      groupId: 'group-1',
      messageId: messageId,
      receiptType: type,
      memberPeerId: memberPeerId,
      receiptAt: now,
      sourceEventId: 'receipt-$messageId-$type-$memberPeerId',
      createdAt: now,
      updatedAt: now,
    );
  }

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS persists cursor and receipts across reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('group_sync_receipts_');
      final path = '${dir.path}/sync.db';
      var persistentDb = await databaseFactoryFfi.openDatabase(path);
      var closed = false;
      try {
        await _runSchema(persistentDb);
        await dbUpsertGroupInboxCursor(
          persistentDb,
          groupId: 'group-1',
          cursor: 'cursor-2',
          updatedAt: DateTime.utc(2026, 5, 1, 12),
        );
        await dbUpsertGroupMessageReceipt(persistentDb, receipt().toMap());

        await persistentDb.close();
        closed = true;
        persistentDb = await databaseFactoryFfi.openDatabase(path);
        closed = false;

        final cursor = await dbLoadGroupInboxCursor(persistentDb, 'group-1');
        expect(cursor?['cursor'], 'cursor-2');
        final receipts = await dbLoadGroupMessageReceipts(
          persistentDb,
          groupId: 'group-1',
          messageId: 'msg-1',
        );
        expect(receipts, hasLength(1));
      } finally {
        if (!closed) await persistentDb.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS commits message receipt read-state and cursor together',
    () async {
      await dbApplyGroupInboxPageTransaction(
        db,
        groupId: 'group-1',
        nextCursor: 'cursor-2',
        receiptRows: () => [receipt(type: groupMessageReceiptTypeRead).toMap()],
        markReadMessageIds: () => ['msg-1'],
        apply: (txn) => dbInsertGroupMessage(txn, message().toMap()),
      );

      expect(await dbLoadGroupMessage(db, 'msg-1'), isNotNull);
      expect((await dbLoadGroupMessage(db, 'msg-1'))!['read_at'], isNotNull);
      expect(
        await dbLoadGroupMessageReceipts(
          db,
          groupId: 'group-1',
          messageId: 'msg-1',
        ),
        hasLength(1),
      );
      expect(
        (await dbLoadGroupInboxCursor(db, 'group-1'))?['cursor'],
        'cursor-2',
      );
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS rolls back message receipt read-state and cursor on failure',
    () async {
      await expectLater(
        dbApplyGroupInboxPageTransaction(
          db,
          groupId: 'group-1',
          nextCursor: 'cursor-2',
          receiptRows: () => [
            receipt(type: groupMessageReceiptTypeRead).toMap(),
          ],
          markReadMessageIds: () => ['msg-1'],
          apply: (txn) => dbInsertGroupMessage(txn, message().toMap()),
          beforeCommitForTest: (_) async => throw StateError('boom'),
        ),
        throwsStateError,
      );

      expect(await dbLoadGroupMessage(db, 'msg-1'), isNull);
      expect(
        await dbLoadGroupMessageReceipts(
          db,
          groupId: 'group-1',
          messageId: 'msg-1',
        ),
        isEmpty,
      );
      expect(await dbLoadGroupInboxCursor(db, 'group-1'), isNull);
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS duplicate receipts are idempotent',
    () async {
      await dbUpsertGroupMessageReceipt(db, receipt().toMap());
      await dbUpsertGroupMessageReceipt(db, receipt().toMap());

      final receipts = await dbLoadGroupMessageReceipts(
        db,
        groupId: 'group-1',
        messageId: 'msg-1',
      );
      expect(receipts, hasLength(1));
    },
  );
}

Future<void> _runSchema(Database db) async {
  await runGroupMessagesTablesMigration(db);
  await runGroupQuotedMessageIdMigration(db);
  await runGroupMessageReliabilityColumnsMigration(db);
  await runGroupMessageTransportPeerIdMigration(db);
  await runGroupSyncReceiptsMigration(db);
}
