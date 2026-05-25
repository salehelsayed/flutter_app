import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_pending_membership_messages_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/072_group_pending_membership_messages.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_membership_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_membership_message_repository_impl.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupPendingMembershipMessagesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> pendingRow({
    String id = 'membership:group-1:msg-1',
    String groupId = 'group-1',
    String senderPeerId = 'peer-late',
    String? messageId = 'msg-1',
    String text = 'pending text',
    String receivedAt = '2026-05-23T12:00:00.000Z',
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'message_id': messageId,
      'payload_json': jsonEncode({
        'groupId': groupId,
        'senderId': senderPeerId,
        'messageId': messageId,
        'text': text,
        'timestamp': receivedAt,
      }),
      'received_at': receivedAt,
      'created_at': receivedAt,
      'updated_at': receivedAt,
    };
  }

  test(
    'upserts by group message id and loads oldest first for sender',
    () async {
      final created = await dbUpsertGroupPendingMembershipMessage(
        db,
        pendingRow(),
      );
      final updated = await dbUpsertGroupPendingMembershipMessage(
        db,
        pendingRow(
          id: 'membership:group-1:msg-1-replacement',
          text: 'updated text',
          receivedAt: '2026-05-23T12:00:01.000Z',
        ),
      );
      await dbUpsertGroupPendingMembershipMessage(
        db,
        pendingRow(
          id: 'membership:group-1:msg-2',
          messageId: 'msg-2',
          text: 'second text',
          receivedAt: '2026-05-23T12:00:02.000Z',
        ),
      );

      expect(created['id'], 'membership:group-1:msg-1');
      expect(updated['id'], 'membership:group-1:msg-1');
      final allRows = await dbLoadGroupPendingMembershipMessages(db);
      expect(allRows, hasLength(2));
      expect(
        jsonDecode(allRows.first['payload_json'] as String)['text'],
        'updated text',
      );

      final senderRows = await dbLoadGroupPendingMembershipMessagesForSenders(
        db,
        groupId: 'group-1',
        senderPeerIds: ['peer-late'],
      );
      expect(senderRows.map((row) => row['message_id']), ['msg-1', 'msg-2']);
    },
  );

  test('deletes by id and by group message id', () async {
    await dbUpsertGroupPendingMembershipMessage(db, pendingRow());
    await dbUpsertGroupPendingMembershipMessage(
      db,
      pendingRow(
        id: 'membership:group-1:msg-2',
        messageId: 'msg-2',
        receivedAt: '2026-05-23T12:00:01.000Z',
      ),
    );

    await dbDeleteGroupPendingMembershipMessage(db, 'membership:group-1:msg-1');
    expect(await dbLoadGroupPendingMembershipMessages(db), hasLength(1));

    await dbDeleteGroupPendingMembershipMessageByGroupAndMessageId(
      db,
      groupId: 'group-1',
      messageId: 'msg-2',
    );
    expect(await dbLoadGroupPendingMembershipMessages(db), isEmpty);
  });

  test(
    'repository implementation saves, loads, and deletes pending messages',
    () async {
      final repo = GroupPendingMembershipMessageRepositoryImpl(
        dbUpsertGroupPendingMembershipMessage: (row) =>
            dbUpsertGroupPendingMembershipMessage(db, row),
        dbLoadGroupPendingMembershipMessages: ({int limit = 200}) =>
            dbLoadGroupPendingMembershipMessages(db, limit: limit),
        dbLoadGroupPendingMembershipMessagesForSenders:
            ({required groupId, required senderPeerIds, int limit = 50}) =>
                dbLoadGroupPendingMembershipMessagesForSenders(
                  db,
                  groupId: groupId,
                  senderPeerIds: senderPeerIds,
                  limit: limit,
                ),
        dbDeleteGroupPendingMembershipMessage: (id) =>
            dbDeleteGroupPendingMembershipMessage(db, id),
        dbDeleteGroupPendingMembershipMessageByGroupAndMessageId:
            ({required groupId, required messageId}) =>
                dbDeleteGroupPendingMembershipMessageByGroupAndMessageId(
                  db,
                  groupId: groupId,
                  messageId: messageId,
                ),
        dbPruneGroupPendingMembershipMessages: (groupId, {required maxRows}) =>
            dbPruneGroupPendingMembershipMessages(
              db,
              groupId,
              maxRows: maxRows,
            ),
      );
      final now = DateTime.utc(2026, 5, 23, 12);
      await repo.savePendingMessage(
        GroupPendingMembershipMessage(
          id: 'membership:group-1:repo-msg',
          groupId: 'group-1',
          senderPeerId: 'peer-late',
          messageId: 'repo-msg',
          payloadJson: '{"messageId":"repo-msg"}',
          receivedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final rows = await repo.getPendingMessagesForGroupAndSenders(
        groupId: 'group-1',
        senderPeerIds: ['peer-late'],
      );
      expect(rows.map((row) => row.messageId), ['repo-msg']);

      await repo.deletePendingMessageByGroupAndMessageId(
        groupId: 'group-1',
        messageId: 'repo-msg',
      );
      expect(await repo.getPendingMessages(), isEmpty);
    },
  );

  test('prunes oldest rows beyond group cap', () async {
    for (var i = 0; i < 4; i++) {
      await dbUpsertGroupPendingMembershipMessage(
        db,
        pendingRow(
          id: 'membership:group-1:msg-$i',
          messageId: 'msg-$i',
          receivedAt: '2026-05-23T12:00:0$i.000Z',
        ),
      );
    }

    await dbPruneGroupPendingMembershipMessages(db, 'group-1', maxRows: 2);

    final rows = await dbLoadGroupPendingMembershipMessages(db);
    expect(rows.map((row) => row['message_id']), ['msg-2', 'msg-3']);
  });

  test('persists rows across database reopen', () async {
    final dir = await Directory.systemTemp.createTemp(
      'group_pending_membership_messages_',
    );
    final path = '${dir.path}/pending.db';
    var persistentDb = await databaseFactoryFfi.openDatabase(path);
    var persistentDbClosed = false;

    try {
      await runGroupPendingMembershipMessagesMigration(persistentDb);
      await dbUpsertGroupPendingMembershipMessage(
        persistentDb,
        pendingRow(
          id: 'membership:group-1:msg-restart',
          messageId: 'msg-restart',
          text: 'restart durable text',
        ),
      );

      await persistentDb.close();
      persistentDbClosed = true;

      persistentDb = await databaseFactoryFfi.openDatabase(path);
      persistentDbClosed = false;

      final rows = await dbLoadGroupPendingMembershipMessages(persistentDb);
      expect(rows, hasLength(1));
      expect(rows.single['message_id'], 'msg-restart');
      expect(
        jsonDecode(rows.single['payload_json'] as String)['text'],
        'restart durable text',
      );
    } finally {
      if (!persistentDbClosed) {
        await persistentDb.close();
      }
      await dir.delete(recursive: true);
    }
  });
}
