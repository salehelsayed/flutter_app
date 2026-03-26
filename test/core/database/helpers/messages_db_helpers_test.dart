import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';

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
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    await runSecretNullChecksMigration(db);
    await runReadAtColumnMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runQuotedMessageIdMigration(db);
    await runTransportColumnMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeMessageRow({
    String id = 'msg-001',
    String contactPeerId = 'peer-a',
    String senderPeerId = 'peer-a',
    String text = 'Hello world',
    String timestamp = '2026-01-01T00:00:00.000Z',
    String status = 'sent',
    int isIncoming = 0,
    String createdAt = '2026-01-01T00:00:00.000Z',
    String? readAt,
    String? quotedMessageId,
    String? transport,
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
      'read_at': readAt,
      'quoted_message_id': quotedMessageId,
      'transport': transport,
    };
  }

  Map<String, Object?> makeContactRow({
    String peerId = 'peer-a',
    String publicKey = 'pk',
    String rendezvous = '/dns4/relay',
    String username = 'Alice',
    String signature = 'sig',
    String scannedAt = '2026-01-01T00:00:00.000Z',
    int isArchived = 0,
    String? archivedAt,
    int isBlocked = 0,
    String? blockedAt,
  }) {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'scanned_at': scannedAt,
      'is_archived': isArchived,
      'archived_at': archivedAt,
      'is_blocked': isBlocked,
      'blocked_at': blockedAt,
    };
  }

  group('dbInsertMessage', () {
    test('inserts a new message', () async {
      await dbInsertMessage(db, makeMessageRow());

      final rows = await db.query('messages');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'msg-001');
      expect(rows[0]['text'], 'Hello world');
    });

    test('replaces on conflict (same id)', () async {
      await dbInsertMessage(db, makeMessageRow(text: 'Original'));
      await dbInsertMessage(db, makeMessageRow(text: 'Replaced'));

      final rows = await db.query('messages');
      expect(rows.length, 1);
      expect(rows[0]['text'], 'Replaced');
    });
  });

  group('dbLoadMessagesPage', () {
    test('returns empty list for no messages', () async {
      final results = await dbLoadMessagesPage(db, 'peer-a');
      expect(results, isEmpty);
    });

    test('returns messages in chronological (ASC) order', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-1',
        timestamp: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-2',
        timestamp: '2026-01-02T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-3',
        timestamp: '2026-01-03T00:00:00.000Z',
      ));

      final results = await dbLoadMessagesPage(db, 'peer-a');
      expect(results.length, 3);
      expect(results[0]['id'], 'msg-1');
      expect(results[1]['id'], 'msg-2');
      expect(results[2]['id'], 'msg-3');
    });

    test('respects limit parameter', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-1',
        timestamp: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-2',
        timestamp: '2026-01-02T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-3',
        timestamp: '2026-01-03T00:00:00.000Z',
      ));

      final results = await dbLoadMessagesPage(db, 'peer-a', limit: 2);
      expect(results.length, 2);
      // With no cursor, returns the most recent 2 (DESC) then reverses to ASC
      expect(results[0]['id'], 'msg-2');
      expect(results[1]['id'], 'msg-3');
    });

    test('uses beforeTimestamp cursor for pagination', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-1',
        timestamp: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-2',
        timestamp: '2026-01-02T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-3',
        timestamp: '2026-01-03T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-4',
        timestamp: '2026-01-04T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-5',
        timestamp: '2026-01-05T00:00:00.000Z',
      ));

      // Cursor before msg-3: should return msg-1 and msg-2
      final results = await dbLoadMessagesPage(
        db,
        'peer-a',
        beforeTimestamp: '2026-01-03T00:00:00.000Z',
      );
      expect(results.length, 2);
      expect(results[0]['id'], 'msg-1');
      expect(results[1]['id'], 'msg-2');
    });

    test('returns most recent page when no cursor', () async {
      // Insert 5 messages, default limit is 50 so all should come back
      for (var i = 1; i <= 5; i++) {
        await dbInsertMessage(db, makeMessageRow(
          id: 'msg-$i',
          timestamp: '2026-01-0${i}T00:00:00.000Z',
        ));
      }

      final results = await dbLoadMessagesPage(db, 'peer-a');
      expect(results.length, 5);
      // Should be in ASC order
      expect(results[0]['id'], 'msg-1');
      expect(results[4]['id'], 'msg-5');
    });
  });

  group('dbLoadMessagesForContact', () {
    test('returns only messages for the given contact', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a1',
        contactPeerId: 'peer-a',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-b1',
        contactPeerId: 'peer-b',
      ));

      final results = await dbLoadMessagesForContact(db, 'peer-a');
      expect(results.length, 1);
      expect(results[0]['id'], 'msg-a1');
    });

    test('ordered by timestamp ASC', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-2',
        timestamp: '2026-01-02T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-1',
        timestamp: '2026-01-01T00:00:00.000Z',
      ));

      final results = await dbLoadMessagesForContact(db, 'peer-a');
      expect(results.length, 2);
      expect(results[0]['id'], 'msg-1');
      expect(results[1]['id'], 'msg-2');
    });
  });

  group('dbLoadLatestMessageForContact', () {
    test('returns null when no messages', () async {
      final result = await dbLoadLatestMessageForContact(db, 'peer-a');
      expect(result, isNull);
    });

    test('returns the most recent message', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-old',
        timestamp: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-new',
        timestamp: '2026-01-02T00:00:00.000Z',
      ));

      final result = await dbLoadLatestMessageForContact(db, 'peer-a');
      expect(result, isNotNull);
      expect(result!['id'], 'msg-new');
    });
  });

  group('dbUpdateMessageStatus', () {
    test('updates status field and returns affected row count', () async {
      await dbInsertMessage(db, makeMessageRow(status: 'sent'));

      final updated = await dbUpdateMessageStatus(db, 'msg-001', 'delivered');

      final row = await dbLoadMessage(db, 'msg-001');
      expect(updated, 1);
      expect(row, isNotNull);
      expect(row!['status'], 'delivered');
    });

    test('can update from sent to delivered', () async {
      await dbInsertMessage(db, makeMessageRow(status: 'sent'));

      final updated = await dbUpdateMessageStatus(db, 'msg-001', 'delivered');

      final row = await dbLoadMessage(db, 'msg-001');
      expect(updated, 1);
      expect(row!['status'], 'delivered');
    });

    test('returns 0 when the row does not exist', () async {
      final updated = await dbUpdateMessageStatus(
        db,
        'missing-row',
        'delivered',
      );

      expect(updated, 0);
    });
  });

  group('dbGetMessageCount', () {
    test('returns 0 when empty', () async {
      final count = await dbGetMessageCount(db);
      expect(count, 0);
    });

    test('returns total count across all contacts', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a1',
        contactPeerId: 'peer-a',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-b1',
        contactPeerId: 'peer-b',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a2',
        contactPeerId: 'peer-a',
      ));

      final count = await dbGetMessageCount(db);
      expect(count, 3);
    });
  });

  group('dbCountMessagesForContact', () {
    test('returns count for specific contact only', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a1',
        contactPeerId: 'peer-a',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a2',
        contactPeerId: 'peer-a',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-b1',
        contactPeerId: 'peer-b',
      ));

      final count = await dbCountMessagesForContact(db, 'peer-a');
      expect(count, 2);
    });
  });

  group('dbMarkConversationAsRead', () {
    test('marks unread incoming messages as read', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-in1',
        isIncoming: 1,
        readAt: null,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-in2',
        isIncoming: 1,
        readAt: null,
      ));

      await dbMarkConversationAsRead(db, 'peer-a');

      final msg1 = await dbLoadMessage(db, 'msg-in1');
      final msg2 = await dbLoadMessage(db, 'msg-in2');
      expect(msg1!['read_at'], isNotNull);
      expect(msg2!['read_at'], isNotNull);
    });

    test('does NOT mark outgoing messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-out',
        isIncoming: 0,
        readAt: null,
      ));

      await dbMarkConversationAsRead(db, 'peer-a');

      final msg = await dbLoadMessage(db, 'msg-out');
      expect(msg!['read_at'], isNull);
    });

    test('does NOT re-mark already read messages', () async {
      const alreadyRead = '2026-01-01T12:00:00.000Z';
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-read',
        isIncoming: 1,
        readAt: alreadyRead,
      ));

      await dbMarkConversationAsRead(db, 'peer-a');

      final msg = await dbLoadMessage(db, 'msg-read');
      // read_at should remain the original value, not be updated
      expect(msg!['read_at'], alreadyRead);
    });

    test('returns count of newly marked messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-unread1',
        isIncoming: 1,
        readAt: null,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-unread2',
        isIncoming: 1,
        readAt: null,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-already-read',
        isIncoming: 1,
        readAt: '2026-01-01T12:00:00.000Z',
      ));

      final count = await dbMarkConversationAsRead(db, 'peer-a');
      expect(count, 2);
    });
  });

  group('dbCountUnreadForContact', () {
    test('returns count of unread incoming messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-unread1',
        isIncoming: 1,
        readAt: null,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-unread2',
        isIncoming: 1,
        readAt: null,
      ));

      final count = await dbCountUnreadForContact(db, 'peer-a');
      expect(count, 2);
    });

    test('does not count outgoing messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-out',
        isIncoming: 0,
        readAt: null,
      ));

      final count = await dbCountUnreadForContact(db, 'peer-a');
      expect(count, 0);
    });

    test('does not count already-read messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-read',
        isIncoming: 1,
        readAt: '2026-01-01T12:00:00.000Z',
      ));

      final count = await dbCountUnreadForContact(db, 'peer-a');
      expect(count, 0);
    });
  });

  group('dbCountTotalUnread', () {
    test('counts across all contacts', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a1',
        contactPeerId: 'peer-a',
        isIncoming: 1,
        readAt: null,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-b1',
        contactPeerId: 'peer-b',
        senderPeerId: 'peer-b',
        isIncoming: 1,
        readAt: null,
      ));

      final count = await dbCountTotalUnread(db);
      expect(count, 2);
    });
  });

  group('dbCountTotalUnreadExcludingArchived', () {
    test('excludes messages from archived contacts', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-archived',
        isArchived: 1,
        archivedAt: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-archived',
        contactPeerId: 'peer-archived',
        senderPeerId: 'peer-archived',
        isIncoming: 1,
        readAt: null,
      ));

      final count = await dbCountTotalUnreadExcludingArchived(db);
      expect(count, 0);
    });

    test('excludes messages from blocked contacts', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-blocked',
        isBlocked: 1,
        blockedAt: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-blocked',
        contactPeerId: 'peer-blocked',
        senderPeerId: 'peer-blocked',
        isIncoming: 1,
        readAt: null,
      ));

      final count = await dbCountTotalUnreadExcludingArchived(db);
      expect(count, 0);
    });

    test('includes messages from active contacts', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-active',
        isArchived: 0,
        isBlocked: 0,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-active',
        contactPeerId: 'peer-active',
        senderPeerId: 'peer-active',
        isIncoming: 1,
        readAt: null,
      ));

      // Also add an archived contact with a message to verify it is excluded
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-archived',
        isArchived: 1,
        archivedAt: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-archived',
        contactPeerId: 'peer-archived',
        senderPeerId: 'peer-archived',
        isIncoming: 1,
        readAt: null,
      ));

      final count = await dbCountTotalUnreadExcludingArchived(db);
      expect(count, 1);
    });
  });

  group('dbDeleteMessagesForContact', () {
    test('deletes all messages for contact', () async {
      await dbInsertMessage(db, makeMessageRow(id: 'msg-1'));
      await dbInsertMessage(db, makeMessageRow(id: 'msg-2'));

      await dbDeleteMessagesForContact(db, 'peer-a');

      final results = await dbLoadMessagesForContact(db, 'peer-a');
      expect(results, isEmpty);
    });

    test('returns count of deleted rows', () async {
      await dbInsertMessage(db, makeMessageRow(id: 'msg-1'));
      await dbInsertMessage(db, makeMessageRow(id: 'msg-2'));

      final count = await dbDeleteMessagesForContact(db, 'peer-a');
      expect(count, 2);
    });

    test('does not delete messages for other contacts', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-a1',
        contactPeerId: 'peer-a',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-b1',
        contactPeerId: 'peer-b',
      ));

      await dbDeleteMessagesForContact(db, 'peer-a');

      final remainingA = await dbLoadMessagesForContact(db, 'peer-a');
      final remainingB = await dbLoadMessagesForContact(db, 'peer-b');
      expect(remainingA, isEmpty);
      expect(remainingB.length, 1);
    });
  });

  group('dbLoadFailedOutgoingMessages', () {
    test('returns only failed outgoing messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-failed-out',
        status: 'failed',
        isIncoming: 0,
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-sent-out',
        status: 'sent',
        isIncoming: 0,
      ));

      final results = await dbLoadFailedOutgoingMessages(db);
      expect(results.length, 1);
      expect(results[0]['id'], 'msg-failed-out');
    });

    test('does not return failed incoming messages', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-failed-in',
        status: 'failed',
        isIncoming: 1,
      ));

      final results = await dbLoadFailedOutgoingMessages(db);
      expect(results, isEmpty);
    });

    test('ordered by timestamp ASC', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-f2',
        status: 'failed',
        isIncoming: 0,
        timestamp: '2026-01-02T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-f1',
        status: 'failed',
        isIncoming: 0,
        timestamp: '2026-01-01T00:00:00.000Z',
      ));

      final results = await dbLoadFailedOutgoingMessages(db);
      expect(results.length, 2);
      expect(results[0]['id'], 'msg-f1');
      expect(results[1]['id'], 'msg-f2');
    });

    test('respects limit', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-f1',
        status: 'failed',
        isIncoming: 0,
        timestamp: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-f2',
        status: 'failed',
        isIncoming: 0,
        timestamp: '2026-01-02T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-f3',
        status: 'failed',
        isIncoming: 0,
        timestamp: '2026-01-03T00:00:00.000Z',
      ));

      final results = await dbLoadFailedOutgoingMessages(db, limit: 2);
      expect(results.length, 2);
      expect(results[0]['id'], 'msg-f1');
      expect(results[1]['id'], 'msg-f2');
    });
  });

  group('dbLoadMessage', () {
    test('returns null for non-existent', () async {
      final result = await dbLoadMessage(db, 'non-existent');
      expect(result, isNull);
    });

    test('returns message when exists', () async {
      await dbInsertMessage(db, makeMessageRow(id: 'msg-exists'));

      final result = await dbLoadMessage(db, 'msg-exists');
      expect(result, isNotNull);
      expect(result!['id'], 'msg-exists');
      expect(result['text'], 'Hello world');
    });
  });

  group('transport column round-trip', () {
    test('insert+load transport=wifi', () async {
      await dbInsertMessage(db, makeMessageRow(transport: 'wifi'));

      final row = await dbLoadMessage(db, 'msg-001');
      expect(row, isNotNull);
      expect(row!['transport'], 'wifi');
    });

    test('insert+load transport=relay', () async {
      await dbInsertMessage(db, makeMessageRow(transport: 'relay'));

      final row = await dbLoadMessage(db, 'msg-001');
      expect(row!['transport'], 'relay');
    });

    test('insert+load transport=inbox', () async {
      await dbInsertMessage(db, makeMessageRow(transport: 'inbox'));

      final row = await dbLoadMessage(db, 'msg-001');
      expect(row!['transport'], 'inbox');
    });

    test('null transport round-trip', () async {
      await dbInsertMessage(db, makeMessageRow(transport: null));

      final row = await dbLoadMessage(db, 'msg-001');
      expect(row!['transport'], isNull);
    });

    test('INSERT OR REPLACE overwrites transport', () async {
      await dbInsertMessage(db, makeMessageRow(transport: 'wifi'));
      await dbInsertMessage(db, makeMessageRow(transport: 'relay'));

      final row = await dbLoadMessage(db, 'msg-001');
      expect(row!['transport'], 'relay');
    });

    test('transport appears in dbLoadMessagesPage results', () async {
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-wifi',
        transport: 'wifi',
        timestamp: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertMessage(db, makeMessageRow(
        id: 'msg-relay',
        transport: 'relay',
        timestamp: '2026-01-02T00:00:00.000Z',
      ));

      final results = await dbLoadMessagesPage(db, 'peer-a');
      expect(results.length, 2);
      expect(results[0]['transport'], 'wifi');
      expect(results[1]['transport'], 'relay');
    });
  });
}
