import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupMessagesTablesMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runGroupMessageReliabilityColumnsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper to build a group message row with sensible defaults.
  Map<String, Object?> makeRow({
    String id = 'msg-001',
    String groupId = 'group-1',
    String senderPeerId = 'peer-sender',
    String? senderUsername = 'Alice',
    String text = 'Hello group',
    String timestamp = '2026-01-15T12:00:00.000Z',
    String? quotedMessageId,
    int keyGeneration = 0,
    String status = 'sent',
    int isIncoming = 1,
    String? readAt,
    String createdAt = '2026-01-15T12:00:00.000Z',
    String? wireEnvelope,
    int inboxStored = 0,
    String? inboxRetryPayload,
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'sender_username': senderUsername,
      'text': text,
      'timestamp': timestamp,
      'quoted_message_id': quotedMessageId,
      'key_generation': keyGeneration,
      'status': status,
      'is_incoming': isIncoming,
      'read_at': readAt,
      'created_at': createdAt,
      'wire_envelope': wireEnvelope,
      'inbox_stored': inboxStored,
      'inbox_retry_payload': inboxRetryPayload,
    };
  }

  // ─── Migration Tests (1-5) ───────────────────────────────────────────

  group('migration 041', () {
    test('adds wire_envelope column', () async {
      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final names = columns.map((c) => c['name']).toList();
      expect(names, contains('wire_envelope'));
    });

    test('adds inbox_stored column with default 0', () async {
      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final names = columns.map((c) => c['name']).toList();
      expect(names, contains('inbox_stored'));

      // Insert a row without specifying inbox_stored, then read back.
      await db.insert('group_messages', {
        'id': 'default-test',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['default-test'],
      )).first;
      expect(row['inbox_stored'], 0);
    });

    test('adds inbox_retry_payload column', () async {
      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final names = columns.map((c) => c['name']).toList();
      expect(names, contains('inbox_retry_payload'));
    });

    test('is idempotent', () async {
      // Running migration a second time should not throw.
      await runGroupMessageReliabilityColumnsMigration(db);
      // Third time for good measure.
      await runGroupMessageReliabilityColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final names = columns.map((c) => c['name']).toList();
      expect(names, contains('wire_envelope'));
      expect(names, contains('inbox_stored'));
      expect(names, contains('inbox_retry_payload'));
    });

    test('preserves existing rows', () async {
      // Create a fresh DB without migration 041, insert a row, then run it.
      final freshDb = await openDatabase(inMemoryDatabasePath, version: 1);
      await runGroupMessagesTablesMigration(freshDb);
      await runGroupQuotedMessageIdMigration(freshDb);

      await freshDb.insert('group_messages', {
        'id': 'pre-existing',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'before migration',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-01T00:00:00.000Z',
      });

      // Now run migration 041
      await runGroupMessageReliabilityColumnsMigration(freshDb);

      final row = (await freshDb.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['pre-existing'],
      )).first;
      expect(row['text'], 'before migration');
      expect(row['wire_envelope'], isNull);
      expect(row['inbox_stored'], 0);
      expect(row['inbox_retry_payload'], isNull);

      await freshDb.close();
    });
  });

  // ─── dbLoadStuckSendingGroupMessages Tests (6-11) ────────────────────

  group('dbLoadStuckSendingGroupMessages', () {
    test('returns empty list when no messages exist', () async {
      final results = await dbLoadStuckSendingGroupMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(results, isEmpty);
    });

    test(
      'returns only outgoing sending messages older than threshold',
      () async {
        final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();
        final recentTs = DateTime.utc(2026, 6, 1).toIso8601String();

        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'old-sending',
            status: 'sending',
            isIncoming: 0,
            timestamp: oldTs,
            createdAt: oldTs,
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'recent-sending',
            status: 'sending',
            isIncoming: 0,
            timestamp: recentTs,
            createdAt: recentTs,
          ),
        );

        final threshold = DateTime.utc(2026, 3, 1);
        final results = await dbLoadStuckSendingGroupMessages(
          db,
          olderThan: threshold,
        );
        expect(results.length, 1);
        expect(results[0]['id'], 'old-sending');
      },
    );

    test('excludes incoming messages', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();

      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'incoming-sending',
          status: 'sending',
          isIncoming: 1,
          timestamp: oldTs,
          createdAt: oldTs,
        ),
      );

      final threshold = DateTime.utc(2026, 3, 1);
      final results = await dbLoadStuckSendingGroupMessages(
        db,
        olderThan: threshold,
      );
      expect(results, isEmpty);
    });

    test('excludes non-sending statuses', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();

      for (final status in ['sent', 'delivered', 'failed', 'pending']) {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'msg-$status',
            status: status,
            isIncoming: 0,
            timestamp: oldTs,
            createdAt: oldTs,
          ),
        );
      }

      final threshold = DateTime.utc(2026, 3, 1);
      final results = await dbLoadStuckSendingGroupMessages(
        db,
        olderThan: threshold,
      );
      expect(results, isEmpty);
    });

    test('ordered by timestamp ASC', () async {
      final ts1 = DateTime.utc(2026, 1, 1).toIso8601String();
      final ts2 = DateTime.utc(2026, 1, 2).toIso8601String();
      final ts3 = DateTime.utc(2026, 1, 3).toIso8601String();

      // Insert in reverse order to ensure ORDER BY is applied.
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'msg-3',
          status: 'sending',
          isIncoming: 0,
          timestamp: ts3,
          createdAt: ts3,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'msg-1',
          status: 'sending',
          isIncoming: 0,
          timestamp: ts1,
          createdAt: ts1,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'msg-2',
          status: 'sending',
          isIncoming: 0,
          timestamp: ts2,
          createdAt: ts2,
        ),
      );

      final threshold = DateTime.utc(2026, 6, 1);
      final results = await dbLoadStuckSendingGroupMessages(
        db,
        olderThan: threshold,
      );
      expect(results.length, 3);
      expect(results[0]['id'], 'msg-1');
      expect(results[1]['id'], 'msg-2');
      expect(results[2]['id'], 'msg-3');
    });

    test('respects limit', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();

      for (var i = 0; i < 5; i++) {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'msg-$i',
            status: 'sending',
            isIncoming: 0,
            timestamp: DateTime.utc(2026, 1, 1 + i).toIso8601String(),
            createdAt: oldTs,
          ),
        );
      }

      final threshold = DateTime.utc(2026, 6, 1);
      final results = await dbLoadStuckSendingGroupMessages(
        db,
        olderThan: threshold,
        limit: 3,
      );
      expect(results.length, 3);
    });
  });

  // ─── dbLoadFailedOutgoingGroupMessages Tests (12-15) ─────────────────

  group('dbLoadFailedOutgoingGroupMessages', () {
    test('returns only failed outgoing messages', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'failed-out', status: 'failed', isIncoming: 0),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'sent-out', status: 'sent', isIncoming: 0),
      );

      final results = await dbLoadFailedOutgoingGroupMessages(db);
      expect(results.length, 1);
      expect(results[0]['id'], 'failed-out');
    });

    test('does not return failed incoming messages', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'failed-in', status: 'failed', isIncoming: 1),
      );

      final results = await dbLoadFailedOutgoingGroupMessages(db);
      expect(results, isEmpty);
    });

    test('ordered by timestamp ASC', () async {
      final ts1 = DateTime.utc(2026, 1, 1).toIso8601String();
      final ts2 = DateTime.utc(2026, 1, 2).toIso8601String();

      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'failed-2',
          status: 'failed',
          isIncoming: 0,
          timestamp: ts2,
          createdAt: ts2,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'failed-1',
          status: 'failed',
          isIncoming: 0,
          timestamp: ts1,
          createdAt: ts1,
        ),
      );

      final results = await dbLoadFailedOutgoingGroupMessages(db);
      expect(results.length, 2);
      expect(results[0]['id'], 'failed-1');
      expect(results[1]['id'], 'failed-2');
    });

    test('respects limit', () async {
      for (var i = 0; i < 5; i++) {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'failed-$i',
            status: 'failed',
            isIncoming: 0,
            timestamp: DateTime.utc(2026, 1, 1 + i).toIso8601String(),
            createdAt: DateTime.utc(2026, 1, 1 + i).toIso8601String(),
          ),
        );
      }

      final results = await dbLoadFailedOutgoingGroupMessages(db, limit: 2);
      expect(results.length, 2);
    });
  });

  // ─── dbLoadGroupMessagesWithFailedInboxStore Tests (16-20) ───────────

  group('dbLoadGroupMessagesWithFailedInboxStore', () {
    test(
      'returns sent messages with inbox_stored=0 and inbox_retry_payload set',
      () async {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'inbox-fail',
            status: 'sent',
            isIncoming: 0,
            inboxStored: 0,
            inboxRetryPayload: '{"groupId":"g1"}',
          ),
        );

        final results = await dbLoadGroupMessagesWithFailedInboxStore(db);
        expect(results.length, 1);
        expect(results[0]['id'], 'inbox-fail');
      },
    );

    test('excludes messages where inbox_stored=1', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'inbox-ok',
          status: 'sent',
          isIncoming: 0,
          inboxStored: 1,
          inboxRetryPayload: '{"groupId":"g1"}',
        ),
      );

      final results = await dbLoadGroupMessagesWithFailedInboxStore(db);
      expect(results, isEmpty);
    });

    test('excludes messages with null inbox_retry_payload', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'no-payload',
          status: 'sent',
          isIncoming: 0,
          inboxStored: 0,
          inboxRetryPayload: null,
        ),
      );

      final results = await dbLoadGroupMessagesWithFailedInboxStore(db);
      expect(results, isEmpty);
    });

    test(
      'includes pending messages with inbox_stored=0 and retry payload set',
      () async {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'pending-inbox-fail',
            status: 'pending',
            isIncoming: 0,
            inboxStored: 0,
            inboxRetryPayload: '{"groupId":"g1"}',
          ),
        );

        final results = await dbLoadGroupMessagesWithFailedInboxStore(db);
        expect(results.length, 1);
        expect(results[0]['id'], 'pending-inbox-fail');
      },
    );

    test(
      'UP-008 pending outbound retry row survives database restart and stays eligible',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'up008_group_messages_',
        );
        final dbPath = '${dir.path}/group_messages.db';
        Database? fileDb;

        try {
          fileDb = await openDatabase(dbPath, version: 1);
          await runGroupMessagesTablesMigration(fileDb);
          await runGroupQuotedMessageIdMigration(fileDb);
          await runGroupMessageReliabilityColumnsMigration(fileDb);
          await dbInsertGroupMessage(
            fileDb,
            makeRow(
              id: 'up008-pending-after-restart',
              status: 'pending',
              isIncoming: 0,
              inboxStored: 0,
              wireEnvelope: '{"cmd":"group:publish"}',
              inboxRetryPayload:
                  '{"groupId":"group-1","message":"up008-replay"}',
            ),
          );
          await fileDb.close();
          fileDb = null;

          fileDb = await openDatabase(dbPath, version: 1);
          final results = await dbLoadGroupMessagesWithFailedInboxStore(fileDb);

          expect(results, hasLength(1));
          final loaded = GroupMessage.fromMap(results.single);
          expect(loaded.id, 'up008-pending-after-restart');
          expect(loaded.status, 'pending');
          expect(loaded.isIncoming, isFalse);
          expect(loaded.inboxStored, isFalse);
          expect(loaded.inboxRetryPayload, isNotNull);
          expect(loaded.wireEnvelope, '{"cmd":"group:publish"}');
        } finally {
          await fileDb?.close();
          await dir.delete(recursive: true);
        }
      },
    );

    test('excludes incoming messages', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'incoming-inbox-fail',
          status: 'sent',
          isIncoming: 1,
          inboxStored: 0,
          inboxRetryPayload: '{"groupId":"g1"}',
        ),
      );

      final results = await dbLoadGroupMessagesWithFailedInboxStore(db);
      expect(results, isEmpty);
    });
  });

  // ─── dbTransitionGroupSendingToFailed Tests (21-25) ──────────────────

  group('dbTransitionGroupSendingToFailed', () {
    test('transitions old sending messages to failed', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();

      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'stuck',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldTs,
          createdAt: oldTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );
      expect(count, 1);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['stuck'],
      )).first;
      expect(row['status'], 'failed');
    });

    test('does not touch recent sending messages', () async {
      final recentTs = DateTime.utc(2026, 6, 1).toIso8601String();

      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'recent',
          status: 'sending',
          isIncoming: 0,
          timestamp: recentTs,
          createdAt: recentTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );
      expect(count, 0);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['recent'],
      )).first;
      expect(row['status'], 'sending');
    });

    test('does not touch incoming messages', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();

      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'incoming-stuck',
          status: 'sending',
          isIncoming: 1,
          timestamp: oldTs,
          createdAt: oldTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );
      expect(count, 0);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['incoming-stuck'],
      )).first;
      expect(row['status'], 'sending');
    });

    test('preserves wire_envelope on transitioned rows', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();
      const envelope = '{"groupId":"g1","text":"hello"}';

      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'with-env',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldTs,
          createdAt: oldTs,
          wireEnvelope: envelope,
        ),
      );

      await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['with-env'],
      )).first;
      expect(row['status'], 'failed');
      expect(row['wire_envelope'], envelope);
    });

    test('returns count of affected rows', () async {
      final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();

      for (var i = 0; i < 3; i++) {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'stuck-$i',
            status: 'sending',
            isIncoming: 0,
            timestamp: oldTs,
            createdAt: oldTs,
          ),
        );
      }
      // One non-matching message.
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'sent-msg',
          status: 'sent',
          isIncoming: 0,
          timestamp: oldTs,
          createdAt: oldTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );
      expect(count, 3);
    });
  });

  // ─── Update Helper Tests (26-32) ────────────────────────────────────

  group('update helpers', () {
    test('dbUpdateGroupMessageInboxStored sets to 1', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'inbox-test', isIncoming: 0, inboxStored: 0),
      );

      await dbUpdateGroupMessageInboxStored(db, 'inbox-test', stored: true);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['inbox-test'],
      )).first;
      expect(row['inbox_stored'], 1);
    });

    test('dbUpdateGroupMessageInboxStored sets back to 0', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'inbox-test', isIncoming: 0, inboxStored: 1),
      );

      await dbUpdateGroupMessageInboxStored(db, 'inbox-test', stored: false);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['inbox-test'],
      )).first;
      expect(row['inbox_stored'], 0);
    });

    test('dbUpdateGroupMessageInboxRetryPayload stores JSON', () async {
      await dbInsertGroupMessage(db, makeRow(id: 'retry-test', isIncoming: 0));

      const payload = '{"groupId":"g1","recipientPeerIds":["p1"]}';
      await dbUpdateGroupMessageInboxRetryPayload(db, 'retry-test', payload);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['retry-test'],
      )).first;
      expect(row['inbox_retry_payload'], payload);
    });

    test('dbUpdateGroupMessageInboxRetryPayload clears with null', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'retry-clear',
          isIncoming: 0,
          inboxRetryPayload: '{"data":"value"}',
        ),
      );

      await dbUpdateGroupMessageInboxRetryPayload(db, 'retry-clear', null);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['retry-clear'],
      )).first;
      expect(row['inbox_retry_payload'], isNull);
    });

    test('dbUpdateGroupMessageWireEnvelope stores JSON', () async {
      await dbInsertGroupMessage(db, makeRow(id: 'env-test', isIncoming: 0));

      const envelope = '{"groupId":"g1","text":"hello","senderPeerId":"p1"}';
      await dbUpdateGroupMessageWireEnvelope(db, 'env-test', envelope);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['env-test'],
      )).first;
      expect(row['wire_envelope'], envelope);
    });

    test('dbUpdateGroupMessageWireEnvelope clears with null', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'env-clear',
          isIncoming: 0,
          wireEnvelope: '{"data":"value"}',
        ),
      );

      await dbUpdateGroupMessageWireEnvelope(db, 'env-clear', null);

      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['env-clear'],
      )).first;
      expect(row['wire_envelope'], isNull);
    });

    test('does not affect other rows', () async {
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'target', isIncoming: 0, inboxStored: 0),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'bystander', isIncoming: 0, inboxStored: 0),
      );

      await dbUpdateGroupMessageInboxStored(db, 'target', stored: true);
      await dbUpdateGroupMessageWireEnvelope(db, 'target', '{"x":1}');
      await dbUpdateGroupMessageInboxRetryPayload(db, 'target', '{"y":2}');

      final bystander = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['bystander'],
      )).first;
      expect(bystander['inbox_stored'], 0);
      expect(bystander['wire_envelope'], isNull);
      expect(bystander['inbox_retry_payload'], isNull);
    });
  });

  // ─── GroupMessage Model Tests (33-41) ────────────────────────────────

  group('GroupMessage model', () {
    test('fromMap reads wire_envelope', () {
      final msg = GroupMessage.fromMap({
        'id': 'msg-1',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'wire_envelope': '{"groupId":"g1"}',
      });
      expect(msg.wireEnvelope, '{"groupId":"g1"}');
    });

    test('fromMap defaults wire_envelope to null', () {
      final msg = GroupMessage.fromMap({
        'id': 'msg-1',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(msg.wireEnvelope, isNull);
    });

    test('fromMap reads inbox_stored as bool', () {
      final msgTrue = GroupMessage.fromMap({
        'id': 'msg-1',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'inbox_stored': 1,
      });
      expect(msgTrue.inboxStored, true);

      final msgFalse = GroupMessage.fromMap({
        'id': 'msg-2',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'inbox_stored': 0,
      });
      expect(msgFalse.inboxStored, false);
    });

    test('fromMap reads inbox_retry_payload', () {
      final msg = GroupMessage.fromMap({
        'id': 'msg-1',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'inbox_retry_payload': '{"recipientPeerIds":["p2"]}',
      });
      expect(msg.inboxRetryPayload, '{"recipientPeerIds":["p2"]}');
    });

    test('toMap serializes inbox_stored as int', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        inboxStored: true,
      );
      final map = msg.toMap();
      expect(map['inbox_stored'], 1);

      final msgFalse = msg.copyWith(inboxStored: false);
      expect(msgFalse.toMap()['inbox_stored'], 0);
    });

    test('copyWith sentinel clears wireEnvelope to null', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        wireEnvelope: '{"data":"value"}',
      );

      final cleared = msg.copyWith(wireEnvelope: null);
      expect(cleared.wireEnvelope, isNull);
    });

    test('copyWith sentinel clears inboxRetryPayload to null', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        inboxRetryPayload: '{"data":"value"}',
      );

      final cleared = msg.copyWith(inboxRetryPayload: null);
      expect(cleared.inboxRetryPayload, isNull);
    });

    test('copyWith preserves inboxRetryPayload when not specified', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        inboxRetryPayload: '{"data":"value"}',
      );

      final copy = msg.copyWith(status: 'failed');
      expect(copy.inboxRetryPayload, '{"data":"value"}');
    });

    test('copyWith preserves wireEnvelope when not specified', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        wireEnvelope: '{"data":"value"}',
      );

      final copy = msg.copyWith(status: 'failed');
      expect(copy.wireEnvelope, '{"data":"value"}');
    });
  });
}
