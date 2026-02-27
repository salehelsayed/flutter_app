import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';

Map<String, Object?> makeReactionRow({
  String id = 'r1',
  String messageId = 'msg-1',
  String emoji = '👍',
  String senderPeerId = 'sender-1',
  String timestamp = '2026-02-27T10:00:00.000Z',
  String createdAt = '2026-02-27T10:00:01.000Z',
}) {
  return {
    'id': id,
    'message_id': messageId,
    'emoji': emoji,
    'sender_peer_id': senderPeerId,
    'timestamp': timestamp,
    'created_at': createdAt,
  };
}

Map<String, Object?> makeMessageRow({
  String id = 'msg-1',
  String contactPeerId = 'contact-1',
  String senderPeerId = 'sender-1',
  String text = 'Hello',
  String timestamp = '2026-02-27T09:00:00.000Z',
  String status = 'delivered',
  int isIncoming = 1,
  String createdAt = '2026-02-27T09:00:01.000Z',
}) {
  return {
    'id': id,
    'contact_peer_id': contactPeerId,
    'sender_peer_id': senderPeerId,
    'text': text,
    'timestamp': timestamp,
    'status': status,
    'is_incoming': isIncoming,
    'created_at': createdAt,
  };
}

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
    await runMessageReactionsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('dbInsertReaction', () {
    test('inserts a reaction', () async {
      await dbInsertReaction(db, makeReactionRow());

      final rows = await db.query('message_reactions');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'r1');
      expect(rows[0]['emoji'], '👍');
    });

    test('upsert — REPLACE on conflict replaces existing row', () async {
      await dbInsertReaction(db, makeReactionRow());
      // Same message_id + sender_peer_id, different emoji
      await dbInsertReaction(db, makeReactionRow(id: 'r2', emoji: '❤️'));

      final rows = await db.query('message_reactions');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'r2');
      expect(rows[0]['emoji'], '❤️');
    });
  });

  group('dbLoadReactionsForMessage', () {
    test('returns empty list for no reactions', () async {
      final results = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(results, isEmpty);
    });

    test('returns matching reactions', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
          db,
          makeReactionRow(
              id: 'r2', messageId: 'msg-1', senderPeerId: 'sender-2'));
      await dbInsertReaction(db, makeReactionRow(id: 'r3', messageId: 'msg-2'));

      final results = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(results.length, 2);
    });

    test('ordered by timestamp ASC', () async {
      await dbInsertReaction(db, makeReactionRow(
        id: 'r1',
        senderPeerId: 'sender-1',
        timestamp: '2026-02-27T10:02:00.000Z',
      ));
      await dbInsertReaction(db, makeReactionRow(
        id: 'r2',
        senderPeerId: 'sender-2',
        timestamp: '2026-02-27T10:01:00.000Z',
      ));

      final results = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(results[0]['id'], 'r2'); // earlier timestamp first
      expect(results[1]['id'], 'r1');
    });
  });

  group('dbLoadReactionsForMessages', () {
    test('returns empty for empty input', () async {
      final results = await dbLoadReactionsForMessages(db, []);
      expect(results, isEmpty);
    });

    test('batch loads reactions for multiple messages', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
          db,
          makeReactionRow(
              id: 'r2',
              messageId: 'msg-2',
              senderPeerId: 'sender-2'));
      await dbInsertReaction(
          db,
          makeReactionRow(
              id: 'r3',
              messageId: 'msg-3',
              senderPeerId: 'sender-3'));

      final results =
          await dbLoadReactionsForMessages(db, ['msg-1', 'msg-2']);
      expect(results.length, 2);
      final messageIds =
          results.map((r) => r['message_id'] as String).toSet();
      expect(messageIds, containsAll(['msg-1', 'msg-2']));
    });
  });

  group('dbDeleteReaction', () {
    test('deletes matching reaction', () async {
      await dbInsertReaction(db, makeReactionRow());
      final count = await dbDeleteReaction(db, 'msg-1', 'sender-1');
      expect(count, 1);

      final rows = await db.query('message_reactions');
      expect(rows, isEmpty);
    });

    test('returns 0 when no match', () async {
      final count = await dbDeleteReaction(db, 'msg-999', 'sender-999');
      expect(count, 0);
    });
  });

  group('dbDeleteReactionsForMessage', () {
    test('deletes all reactions for a message', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
          db,
          makeReactionRow(
              id: 'r2',
              messageId: 'msg-1',
              senderPeerId: 'sender-2'));
      await dbInsertReaction(db, makeReactionRow(id: 'r3', messageId: 'msg-2'));

      final count = await dbDeleteReactionsForMessage(db, 'msg-1');
      expect(count, 2);

      final remaining = await db.query('message_reactions');
      expect(remaining.length, 1);
      expect(remaining[0]['message_id'], 'msg-2');
    });
  });

  group('dbDeleteReactionsForContact', () {
    test('deletes via subquery on messages table', () async {
      // Insert messages for two different contacts
      await db.insert('messages', makeMessageRow(
        id: 'msg-1',
        contactPeerId: 'contact-1',
      ));
      await db.insert('messages', makeMessageRow(
        id: 'msg-2',
        contactPeerId: 'contact-1',
      ));
      await db.insert('messages', makeMessageRow(
        id: 'msg-3',
        contactPeerId: 'contact-2',
      ));

      // Insert reactions on messages from both contacts
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
          db,
          makeReactionRow(
              id: 'r2',
              messageId: 'msg-2',
              senderPeerId: 'sender-2'));
      await dbInsertReaction(
          db,
          makeReactionRow(
              id: 'r3',
              messageId: 'msg-3',
              senderPeerId: 'sender-3'));

      final count = await dbDeleteReactionsForContact(db, 'contact-1');
      expect(count, 2);

      // Only contact-2's reaction remains
      final remaining = await db.query('message_reactions');
      expect(remaining.length, 1);
      expect(remaining[0]['message_id'], 'msg-3');
    });
  });
}
