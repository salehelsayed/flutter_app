import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/054_group_reaction_replay_outbox.dart';
import 'package:flutter_app/core/database/migrations/060_group_event_log.dart';
import 'package:flutter_app/core/database/migrations/061_group_message_transport_peer_id.dart';
import 'package:flutter_app/core/database/migrations/069_group_message_local_deletions.dart';
import 'package:flutter_app/core/database/migrations/073_group_message_last_send_attempt_at.dart';
import 'package:flutter_app/core/database/migrations/074_group_message_logical_delivery_id.dart';
import 'package:flutter_app/core/database/migrations/082_message_reaction_tombstone.dart';
import 'package:flutter_app/core/database/migrations/087_group_message_retry_backoff_columns.dart';
import 'package:flutter_app/core/database/migrations/099_group_messages_is_forwarded.dart';
import 'package:flutter_app/core/database/migrations/101_group_private_media_lifecycle.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';

import '../../bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../integration_test/group_multi_device_real_harness.dart'
    show createGroupMultiDeviceReactionReplayOutbox;

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
    await runGroupMessageTransportPeerIdMigration(db);
    await runGroupMessageLastSendAttemptAtMigration(db);
    await runGroupMessageLogicalDeliveryIdMigration(db);
    await runGroupMessageRetryBackoffColumnsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper to build a group message row with sensible defaults.
  Map<String, Object?> makeRow({
    String id = 'msg-001',
    String groupId = 'group-1',
    String senderPeerId = 'peer-sender',
    String? transportPeerId,
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
    String? lastSendAttemptAt,
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'transport_peer_id': transportPeerId,
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
      'last_send_attempt_at': lastSendAttemptAt,
    };
  }

  group('dbInsertGroupMessage duplicate handling', () {
    test(
      'PGC-006 duplicate incoming save preserves operational fields',
      () async {
        const readAt = '2026-01-15T13:00:00.000Z';
        const createdAt = '2026-01-15T12:00:00.000Z';
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'pgc006-incoming',
            transportPeerId: 'peer-sender-device-original',
            text: 'original text',
            timestamp: '2026-01-15T12:00:00.000Z',
            quotedMessageId: 'quoted-original',
            keyGeneration: 7,
            status: 'sent',
            isIncoming: 1,
            readAt: readAt,
            createdAt: createdAt,
            wireEnvelope: '{"wire":"existing"}',
            inboxStored: 1,
            inboxRetryPayload: '{"retry":"existing"}',
          ),
        );

        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'pgc006-incoming',
            transportPeerId: null,
            senderUsername: 'Mallory',
            text: 'tampered duplicate text',
            timestamp: '2026-01-16T12:00:00.000Z',
            quotedMessageId: null,
            keyGeneration: 99,
            status: 'failed',
            isIncoming: 1,
            readAt: null,
            createdAt: '2026-01-16T12:00:00.000Z',
            wireEnvelope: null,
            inboxStored: 0,
            inboxRetryPayload: null,
          ),
        );

        final rows = await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['pgc006-incoming'],
        );
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row['sender_username'], 'Alice');
        expect(row['text'], 'original text');
        expect(row['timestamp'], '2026-01-15T12:00:00.000Z');
        expect(row['transport_peer_id'], 'peer-sender-device-original');
        expect(row['quoted_message_id'], 'quoted-original');
        expect(row['key_generation'], 7);
        expect(row['status'], 'sent');
        expect(row['is_incoming'], 1);
        expect(row['read_at'], readAt);
        expect(row['created_at'], createdAt);
        expect(row['wire_envelope'], '{"wire":"existing"}');
        expect(row['inbox_stored'], 1);
        expect(row['inbox_retry_payload'], '{"retry":"existing"}');
      },
    );

    test(
      'PGC-006 outgoing duplicate save preserves intentional state transitions',
      () async {
        Future<void> assertOutgoingTransition({
          required String id,
          required String status,
          required String? wireEnvelope,
          required int inboxStored,
          required String? inboxRetryPayload,
        }) async {
          await dbInsertGroupMessage(
            db,
            makeRow(
              id: id,
              transportPeerId: 'outgoing-device-initial',
              text: 'initial outgoing text',
              quotedMessageId: 'quoted-initial',
              status: 'sending',
              isIncoming: 0,
              wireEnvelope: '{"wire":"initial"}',
              inboxStored: 0,
              inboxRetryPayload: '{"retry":"initial"}',
            ),
          );

          await dbInsertGroupMessage(
            db,
            makeRow(
              id: id,
              transportPeerId: 'outgoing-device-final-$status',
              senderUsername: 'Alice Final',
              text: 'final outgoing $status',
              timestamp: '2026-01-15T12:01:00.000Z',
              quotedMessageId: 'quoted-final-$status',
              status: status,
              isIncoming: 0,
              readAt: null,
              createdAt: '2026-01-15T12:01:00.000Z',
              wireEnvelope: wireEnvelope,
              inboxStored: inboxStored,
              inboxRetryPayload: inboxRetryPayload,
            ),
          );

          final rows = await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: [id],
          );
          expect(rows, hasLength(1));
          final row = rows.single;
          expect(row['sender_username'], 'Alice Final');
          expect(row['text'], 'final outgoing $status');
          expect(row['timestamp'], '2026-01-15T12:01:00.000Z');
          expect(row['transport_peer_id'], 'outgoing-device-final-$status');
          expect(row['quoted_message_id'], 'quoted-final-$status');
          expect(row['status'], status);
          expect(row['is_incoming'], 0);
          expect(row['wire_envelope'], wireEnvelope);
          expect(row['inbox_stored'], inboxStored);
          expect(row['inbox_retry_payload'], inboxRetryPayload);
        }

        await assertOutgoingTransition(
          id: 'pgc006-outgoing-sent',
          status: 'sent',
          wireEnvelope: null,
          inboxStored: 1,
          inboxRetryPayload: null,
        );
        await assertOutgoingTransition(
          id: 'pgc006-outgoing-pending',
          status: 'pending',
          wireEnvelope: null,
          inboxStored: 0,
          inboxRetryPayload: '{"retry":"pending"}',
        );
        await assertOutgoingTransition(
          id: 'pgc006-outgoing-failed',
          status: 'failed',
          wireEnvelope: '{"wire":"failed"}',
          inboxStored: 0,
          inboxRetryPayload: '{"retry":"failed"}',
        );
      },
    );
  });

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

    test(
      'uses last_send_attempt_at for cutoff and falls back to timestamp',
      () async {
        final oldTs = DateTime.utc(2026, 1, 1).toIso8601String();
        final recentTs = DateTime.utc(2026, 6, 1).toIso8601String();

        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'old-logical-fresh-attempt',
            status: 'sending',
            isIncoming: 0,
            timestamp: oldTs,
            createdAt: oldTs,
            lastSendAttemptAt: recentTs,
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'recent-logical-stale-attempt',
            status: 'sending',
            isIncoming: 0,
            timestamp: recentTs,
            createdAt: recentTs,
            lastSendAttemptAt: oldTs,
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'legacy-null-attempt',
            status: 'sending',
            isIncoming: 0,
            timestamp: oldTs,
            createdAt: oldTs,
            lastSendAttemptAt: null,
          ),
        );

        final results = await dbLoadStuckSendingGroupMessages(
          db,
          olderThan: DateTime.utc(2026, 3, 1),
        );

        expect(results.map((row) => row['id']), [
          'legacy-null-attempt',
          'recent-logical-stale-attempt',
        ]);
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

    test(
      'orders matched rows by timestamp instead of last_send_attempt_at',
      () async {
        final ts1 = DateTime.utc(2026, 1, 1).toIso8601String();
        final ts2 = DateTime.utc(2026, 1, 2).toIso8601String();
        final ts3 = DateTime.utc(2026, 1, 3).toIso8601String();

        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'msg-2',
            status: 'sending',
            isIncoming: 0,
            timestamp: ts2,
            createdAt: ts2,
            lastSendAttemptAt: DateTime.utc(
              2026,
              1,
              1,
              0,
              0,
              2,
            ).toIso8601String(),
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: 'msg-3',
            status: 'sending',
            isIncoming: 0,
            timestamp: ts3,
            createdAt: ts3,
            lastSendAttemptAt: DateTime.utc(
              2026,
              1,
              1,
              0,
              0,
              1,
            ).toIso8601String(),
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
            lastSendAttemptAt: DateTime.utc(
              2026,
              1,
              1,
              0,
              0,
              3,
            ).toIso8601String(),
          ),
        );

        final results = await dbLoadStuckSendingGroupMessages(
          db,
          olderThan: DateTime.utc(2026, 3, 1),
        );

        expect(results.map((row) => row['id']), ['msg-1', 'msg-2', 'msg-3']);
      },
    );

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
          await runGroupMessageTransportPeerIdMigration(fileDb);
          await runGroupMessageLastSendAttemptAtMigration(fileDb);
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

    test('legacy media inbox retry completion remains eligible', () async {
      await runMediaAttachmentsMigration(db);
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'legacy-media-inbox-retry',
          status: 'pending',
          isIncoming: 0,
          inboxStored: 0,
          inboxRetryPayload: '{"groupId":"group-1","message":"legacy"}',
        ),
      );
      await db.insert('media_attachments', <String, Object?>{
        'id': 'legacy-media-attachment',
        'message_id': 'legacy-media-inbox-retry',
        'mime': 'image/jpeg',
        'size': 42,
        'media_type': 'image',
        'download_status': 'done',
        'created_at': '2026-01-15T12:00:00.000Z',
      });
      final expected = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: const <Object?>['legacy-media-inbox-retry'],
      )).single;

      expect(await dbCompleteGroupInboxStoreRetry(db, expected), isTrue);
      final completed = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: const <Object?>['legacy-media-inbox-retry'],
      )).single;
      expect(completed['status'], 'sent');
      expect(completed['inbox_stored'], 1);
      expect(completed['inbox_retry_payload'], isNull);
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

  group('v102 removed-parent authority', () {
    setUp(() async {
      await db.execute('''
CREATE TABLE groups (
  id TEXT PRIMARY KEY,
  self_removed_at TEXT
)
''');
      await db.insert('groups', {
        'id': 'active-group',
        'self_removed_at': null,
      });
      await db.insert('groups', {
        'id': 'marked-group',
        'self_removed_at': '2026-07-20T10:00:00.000Z',
      });
    });

    test(
      'absent or marked group refuses ordinary message writes while exact removal timeline remains allowed',
      () async {
        await dbInsertGroupMessage(
          db,
          makeRow(id: 'absent-message', groupId: 'absent-group'),
        );
        await dbInsertGroupMessage(
          db,
          makeRow(id: 'marked-message', groupId: 'marked-group'),
        );
        await dbInsertGroupMessage(
          db,
          makeRow(id: 'active-message', groupId: 'active-group'),
        );

        expect(
          await db.query(
            'group_messages',
            where: 'id IN (?, ?)',
            whereArgs: ['absent-message', 'marked-message'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: ['active-message'],
          ),
          hasLength(1),
        );

        final timeline = makeRow(
          id: 'sys-member_removed:marked-group:self-peer:1',
          groupId: 'marked-group',
          status: 'sent',
          isIncoming: 1,
        );
        expect(
          await dbInsertExactSelfRemovalTimelineMessage(
            db,
            timeline,
            expectedSelfRemovedAt: 'wrong-marker',
          ),
          isFalse,
        );
        expect(
          await dbInsertExactSelfRemovalTimelineMessage(
            db,
            timeline,
            expectedSelfRemovedAt: '2026-07-20T10:00:00.000Z',
          ),
          isTrue,
        );
        expect(
          await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: [timeline['id']],
          ),
          hasLength(1),
        );
      },
    );

    test(
      'terminalized outgoing rows cannot be manually rearmed or overwritten without evidence',
      () async {
        await db.insert(
          'group_messages',
          makeRow(
            id: 'terminal-no-evidence',
            groupId: 'active-group',
            status: 'send_failed',
            isIncoming: 0,
            inboxStored: 0,
          ),
        );
        await db.insert(
          'group_messages',
          makeRow(
            id: 'terminal-with-evidence',
            groupId: 'active-group',
            status: 'send_failed',
            isIncoming: 0,
            wireEnvelope: '{"wire":true}',
          ),
        );
        await db.insert(
          'group_messages',
          makeRow(
            id: 'terminal-empty-evidence',
            groupId: 'active-group',
            status: 'send_failed',
            isIncoming: 0,
            wireEnvelope: '',
            inboxRetryPayload: '',
          ),
        );
        await db.insert(
          'group_messages',
          makeRow(
            id: 'marked-with-evidence',
            groupId: 'marked-group',
            status: 'send_failed',
            isIncoming: 0,
            wireEnvelope: '{"wire":true}',
          ),
        );

        await dbResetGroupMessageRetryState(db, 'terminal-no-evidence');
        await dbResetGroupMessageRetryState(db, 'terminal-with-evidence');
        await dbResetGroupMessageRetryState(db, 'terminal-empty-evidence');
        await dbResetGroupMessageRetryState(db, 'marked-with-evidence');

        expect(
          (await dbLoadGroupMessage(db, 'terminal-no-evidence'))!['status'],
          'send_failed',
        );
        expect(
          (await dbLoadGroupMessage(db, 'terminal-with-evidence'))!['status'],
          'failed',
        );
        expect(
          (await dbLoadGroupMessage(db, 'terminal-empty-evidence'))!['status'],
          'send_failed',
        );
        expect(
          (await dbLoadGroupMessage(db, 'marked-with-evidence'))!['status'],
          'send_failed',
        );

        await dbUpdateGroupMessageInboxStored(
          db,
          'terminal-no-evidence',
          stored: true,
        );
        await dbUpdateGroupMessageInboxRetryPayload(
          db,
          'terminal-no-evidence',
          '{"retry":true}',
        );
        await dbUpdateGroupMessageWireEnvelope(
          db,
          'terminal-no-evidence',
          '{"wire":true}',
        );
        await dbUpdateGroupMessageStatus(db, 'terminal-no-evidence', 'sent');

        final terminal = await dbLoadGroupMessage(db, 'terminal-no-evidence');
        expect(terminal!['status'], 'send_failed');
        expect(terminal['inbox_stored'], 0);
        expect(terminal['inbox_retry_payload'], isNull);
        expect(terminal['wire_envelope'], isNull);
      },
    );

    test('outgoing retry and repush loaders exclude marked parents', () async {
      for (final groupId in ['active-group', 'marked-group']) {
        await db.insert(
          'group_messages',
          makeRow(
            id: '$groupId-retry',
            groupId: groupId,
            status: 'failed',
            isIncoming: 0,
          ),
        );
        await db.insert(
          'group_messages',
          makeRow(
            id: '$groupId-repush',
            groupId: groupId,
            status: 'sent',
            isIncoming: 0,
            inboxStored: 0,
            inboxRetryPayload: '{"retry":true}',
          ),
        );
      }

      final failed = await dbLoadFailedOutgoingGroupMessages(db);
      final retryable = await dbLoadRetryableOutgoingGroupMessages(db);
      final repush = await dbLoadGroupMessagesWithFailedInboxStore(db);
      expect(failed.map((row) => row['id']), ['active-group-retry']);
      expect(retryable.map((row) => row['id']), ['active-group-retry']);
      expect(repush.map((row) => row['id']), ['active-group-repush']);
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

    test('fromMap reads last_send_attempt_at as UTC DateTime', () {
      final msg = GroupMessage.fromMap({
        'id': 'msg-1',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'last_send_attempt_at': '2026-01-01T00:00:30.000Z',
      });

      expect(msg.lastSendAttemptAt, DateTime.parse('2026-01-01T00:00:30.000Z'));
      expect(msg.lastSendAttemptAt!.isUtc, isTrue);
    });

    test('fromMap defaults missing last_send_attempt_at to null', () {
      final msg = GroupMessage.fromMap({
        'id': 'msg-1',
        'group_id': 'g1',
        'sender_peer_id': 'p1',
        'text': 'hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
      });

      expect(msg.lastSendAttemptAt, isNull);
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

    test('toMap serializes lastSendAttemptAt as UTC ISO string', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        lastSendAttemptAt: DateTime.utc(2026, 1, 1, 0, 0, 30),
      );

      final map = msg.toMap();

      expect(map['last_send_attempt_at'], '2026-01-01T00:00:30.000Z');
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

    test('copyWith preserves and clears lastSendAttemptAt', () {
      final attemptAt = DateTime.utc(2026, 1, 1, 0, 0, 30);
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'g1',
        senderPeerId: 'p1',
        text: 'hi',
        timestamp: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
        lastSendAttemptAt: attemptAt,
      );

      final preserved = msg.copyWith(status: 'failed');
      expect(preserved.lastSendAttemptAt, attemptAt);

      final cleared = msg.copyWith(lastSendAttemptAt: null);
      expect(cleared.lastSendAttemptAt, isNull);
    });
  });

  group('protected local sender completion', () {
    test(
      'prepared stage exact-binds owner and rejects media target races before evidence',
      () async {
        final fixture = await _ProtectedSenderFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'strict-prepared-media-collision';
        const messageAt = '2026-08-13T09:30:00.000000Z';
        final messageFixture = await _buildStrictPreparedMessageFixture(
          messageId: messageId,
          timestamp: messageAt,
        );
        final messageExpected = <String, Object?>{
          ...GroupMessage(
            id: messageId,
            groupId: _protectedGroupId,
            senderPeerId: _protectedActor,
            transportPeerId: 'transport-local',
            senderUsername: 'Local',
            text: 'strict prepared fixture',
            timestamp: DateTime.parse(messageAt),
            logicalDeliveryId: messageId,
            keyGeneration: 7,
            status: GroupMessage.statusQueuedOffline,
            isIncoming: false,
            createdAt: DateTime.parse(messageAt),
            wireEnvelope: jsonEncode(<String, Object?>{
              'messageId': messageId,
              'timestamp': messageAt,
            }),
            inboxStored: false,
            inboxRetryPayload: messageFixture.retry,
          ).toMap(),
          'retry_attempt_count': 0,
          'next_eligible_at': null,
        };
        final preparedMessagePayload =
            buildLocalProtectedGroupContentPreparedEventPayload(
              eventPayload: messageFixture.eventPayload,
              ownerKind: 'group_message',
              ownerId: messageId,
              ownerStatus: GroupMessage.statusQueuedOffline,
              inboxRetryPayload: messageFixture.retry,
            );
        expect(
          isExactProtectedGroupContentPreparedStage(
            groupId: _protectedGroupId,
            payloadType: 'group_message',
            contentEventId: messageId,
            ownerKind: 'group_message',
            ownerId: messageId,
            ownerStatus: GroupMessage.statusQueuedOffline,
            retryWrapper: messageFixture.retry,
            sourcePeerId: _protectedActor,
            sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
              messageId,
            ),
            sourceTimestamp: messageAt,
            preparedEventPayload: preparedMessagePayload,
          ),
          isTrue,
        );
        String mutateRetry(
          String raw,
          void Function(Map<String, Object?> wrapper) mutate,
        ) {
          final wrapper = Map<String, Object?>.from(
            (jsonDecode(raw) as Map).cast<String, Object?>(),
          );
          mutate(wrapper);
          return jsonEncode(wrapper);
        }

        Map<String, Object?> preparedMessageFor(String retry) {
          final wrapper = (jsonDecode(retry) as Map).cast<String, Object?>();
          return <String, Object?>{
            ...preparedMessagePayload,
            'replayEnvelopeHash': sha256
                .convert(utf8.encode(wrapper['message']! as String))
                .toString(),
          };
        }

        final messagePoisonedWrappers = <String>[
          mutateRetry(messageFixture.retry, (wrapper) {
            wrapper['custodyContract'] = 'future_contract';
          }),
          mutateRetry(messageFixture.retry, (wrapper) {
            wrapper['recipientPeerIds'] = const <String>['transport-a'];
          }),
          mutateRetry(messageFixture.retry, (wrapper) {
            final envelope = Map<String, Object?>.from(
              (jsonDecode(wrapper['message']! as String) as Map)
                  .cast<String, Object?>(),
            );
            final signed = Map<String, Object?>.from(
              (jsonDecode(envelope['signedPayload']! as String) as Map)
                  .cast<String, Object?>(),
            )..['futureField'] = 'unsigned-extension';
            envelope['signedPayload'] = canonicalizeGroupEventLogPayload(
              signed,
            );
            wrapper['message'] = jsonEncode(envelope);
          }),
        ];
        for (final poisoned in messagePoisonedWrappers) {
          expect(
            await dbStagePreparedLocalGroupContentMessage(
              fixture.db,
              expected: <String, Object?>{
                ...messageExpected,
                'inbox_retry_payload': poisoned,
              },
              sourcePeerId: _protectedActor,
              sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
                messageId,
              ),
              sourceTimestamp: messageAt,
              preparedEventPayload: preparedMessageFor(poisoned),
            ),
            isFalse,
          );
        }
        for (final crossedPayload in <Map<String, Object?>>[
          <String, Object?>{
            ...preparedMessagePayload,
            'senderDeviceId': 'crossed-device',
          },
          <String, Object?>{
            ...preparedMessagePayload,
            'payload': <String, Object?>{
              ...(preparedMessagePayload['payload'] as Map)
                  .cast<String, Object?>(),
              'text': 'crossed local projection',
            },
          },
        ]) {
          expect(
            await dbStagePreparedLocalGroupContentMessage(
              fixture.db,
              expected: messageExpected,
              sourcePeerId: _protectedActor,
              sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
                messageId,
              ),
              sourceTimestamp: messageAt,
              preparedEventPayload: crossedPayload,
            ),
            isFalse,
          );
        }
        await fixture.db.insert('media_attachments', <String, Object?>{
          'id': 'collision-media',
          'message_id': messageId,
          'mime': 'image/jpeg',
          'media_type': 'image',
          'created_at': messageAt,
        });
        expect(
          await dbStagePreparedLocalGroupContentMessage(
            fixture.db,
            expected: messageExpected,
            sourcePeerId: _protectedActor,
            sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
              messageId,
            ),
            sourceTimestamp: messageAt,
            preparedEventPayload: preparedMessagePayload,
          ),
          isFalse,
        );
        expect(
          await fixture.db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: const <Object?>[messageId],
          ),
          isEmpty,
        );

        final reactionAt = DateTime.utc(2026, 8, 13, 9, 31);
        final transitionId = _protectedTransition(
          action: 'add',
          emoji: '🧭',
          at: reactionAt,
        );
        final reactionFixture = await _buildStrictPreparedReactionFixture(
          transitionId: transitionId,
          timestamp: fixedGroupContentUtc(reactionAt),
          targetMessageId: _protectedMessageId,
        );
        final reactionExpected = GroupReactionReplayOutboxEntry(
          reactionId: transitionId,
          groupId: _protectedGroupId,
          messageId: _protectedMessageId,
          senderPeerId: _protectedActor,
          emoji: '🧭',
          action: 'add',
          inboxRetryPayload: reactionFixture.retry,
          deliveryStatus: GroupReactionReplayOutboxStatus.pending,
          createdAt: fixedGroupContentUtc(reactionAt),
          updatedAt: fixedGroupContentUtc(reactionAt),
        ).toMap();
        final preparedReactionPayload =
            buildLocalProtectedGroupContentPreparedEventPayload(
              eventPayload: reactionFixture.eventPayload,
              ownerKind: 'group_reaction',
              ownerId: transitionId,
              ownerStatus: GroupReactionReplayOutboxStatus.pending,
              inboxRetryPayload: reactionFixture.retry,
            );
        Map<String, Object?> preparedReactionFor(String retry) {
          final wrapper = (jsonDecode(retry) as Map).cast<String, Object?>();
          return <String, Object?>{
            ...preparedReactionPayload,
            'replayEnvelopeHash': sha256
                .convert(utf8.encode(wrapper['message']! as String))
                .toString(),
          };
        }

        final reactionPoisonedWrappers = <String>[
          mutateRetry(reactionFixture.retry, (wrapper) {
            wrapper['custodyContract'] = 'future_contract';
          }),
          mutateRetry(reactionFixture.retry, (wrapper) {
            wrapper['recipientPeerIds'] = const <String>['transport-a'];
          }),
          mutateRetry(reactionFixture.retry, (wrapper) {
            final envelope = Map<String, Object?>.from(
              (jsonDecode(wrapper['message']! as String) as Map)
                  .cast<String, Object?>(),
            );
            final extension = Map<String, Object?>.from(
              (envelope['notificationExtension']! as Map)
                  .cast<String, Object?>(),
            )..['futureField'] = 'unsigned-extension';
            envelope['notificationExtension'] = extension;
            wrapper['message'] = jsonEncode(envelope);
          }),
        ];
        for (final poisoned in reactionPoisonedWrappers) {
          expect(
            await dbStagePreparedLocalGroupReactionContent(
              fixture.db,
              expected: <String, Object?>{
                ...reactionExpected,
                'inbox_retry_payload': poisoned,
              },
              sourcePeerId: _protectedActor,
              sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
                transitionId,
              ),
              sourceTimestamp: fixedGroupContentUtc(reactionAt),
              preparedEventPayload: preparedReactionFor(poisoned),
            ),
            isFalse,
          );
        }
        for (final crossedOwner in <Map<String, Object?>>[
          <String, Object?>{
            ...reactionExpected,
            'message_id': 'crossed-target',
          },
          <String, Object?>{...reactionExpected, 'action': 'remove'},
          <String, Object?>{...reactionExpected, 'emoji': '❌'},
        ]) {
          expect(
            await dbStagePreparedLocalGroupReactionContent(
              fixture.db,
              expected: crossedOwner,
              sourcePeerId: _protectedActor,
              sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
                transitionId,
              ),
              sourceTimestamp: fixedGroupContentUtc(reactionAt),
              preparedEventPayload: preparedReactionPayload,
            ),
            isFalse,
          );
        }
        await fixture.db.insert('media_attachments', <String, Object?>{
          'id': 'target-media-race',
          'message_id': _protectedMessageId,
          'mime': 'image/jpeg',
          'media_type': 'image',
          'created_at': fixedGroupContentUtc(reactionAt),
        });
        expect(
          await dbStagePreparedLocalGroupReactionContent(
            fixture.db,
            expected: reactionExpected,
            sourcePeerId: _protectedActor,
            sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
              transitionId,
            ),
            sourceTimestamp: fixedGroupContentUtc(reactionAt),
            preparedEventPayload: preparedReactionPayload,
          ),
          isFalse,
        );
        expect(
          await fixture.db.query(
            'group_reaction_replay_outbox',
            where: 'reaction_id = ?',
            whereArgs: <Object?>[transitionId],
          ),
          isEmpty,
        );
        expect(
          await fixture.db.query(
            'group_event_log',
            where: 'event_type = ?',
            whereArgs: const <Object?>[protectedGroupContentPreparedEventType],
          ),
          isEmpty,
        );
      },
    );

    test(
      'strict pending-recipient CAS removes one recipient and final completion requires one survivor',
      () async {
        final fixture = await _ProtectedSenderFixture.create();
        addTearDown(fixture.dispose);
        const recipients = <String>[
          'transport-a',
          'transport-b',
          'transport-c',
        ];
        const messageId = 'strict-cas-message';
        const messageAt = '2026-08-13T09:40:00.000000Z';
        final messageFixture = await _buildStrictPreparedMessageFixture(
          messageId: messageId,
          timestamp: messageAt,
          recipients: recipients,
        );
        final messageExpected = <String, Object?>{
          ...GroupMessage(
            id: messageId,
            groupId: _protectedGroupId,
            senderPeerId: _protectedActor,
            transportPeerId: 'transport-local',
            senderUsername: 'Local',
            text: 'strict prepared fixture',
            timestamp: DateTime.parse(messageAt),
            logicalDeliveryId: messageId,
            keyGeneration: 7,
            status: GroupMessage.statusQueuedOffline,
            isIncoming: false,
            createdAt: DateTime.parse(messageAt),
            wireEnvelope: '{}',
            inboxStored: false,
            inboxRetryPayload: messageFixture.retry,
          ).toMap(),
          'retry_attempt_count': 0,
          'next_eligible_at': null,
        };
        final messagePrepared =
            buildLocalProtectedGroupContentPreparedEventPayload(
              eventPayload: messageFixture.eventPayload,
              ownerKind: 'group_message',
              ownerId: messageId,
              ownerStatus: GroupMessage.statusQueuedOffline,
              inboxRetryPayload: messageFixture.retry,
            );
        expect(
          await dbStagePreparedLocalGroupContentMessage(
            fixture.db,
            expected: messageExpected,
            sourcePeerId: _protectedActor,
            sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
              messageId,
            ),
            sourceTimestamp: messageAt,
            preparedEventPayload: messagePrepared,
          ),
          isTrue,
        );
        var currentMessage = (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        final messageRetry = GroupContentRetryPayload.decode(
          messageFixture.retry,
        );
        expect(
          await dbReplaceGroupInboxRetryPayloadIfExact(
            fixture.db,
            currentMessage,
            messageRetry.encodeWithPending(const <String>['transport-c']),
          ),
          isFalse,
        );
        expect(
          await dbReplaceGroupInboxRetryPayloadIfExact(
            fixture.db,
            currentMessage,
            'legacy retry bytes',
          ),
          isFalse,
        );
        final crossedMessage = await _buildStrictPreparedMessageFixture(
          messageId: 'strict-cas-message-crossed',
          timestamp: messageAt,
          recipients: recipients,
        );
        expect(
          await dbReplaceGroupInboxRetryPayloadIfExact(
            fixture.db,
            currentMessage,
            GroupContentRetryPayload.decode(
              crossedMessage.retry,
            ).encodeWithPending(const <String>['transport-b', 'transport-c']),
          ),
          isFalse,
        );
        final messageSurvivor = messageRetry.encodeWithPending(const <String>[
          'transport-b',
          'transport-c',
        ]);
        expect(
          await dbReplaceGroupInboxRetryPayloadIfExact(
            fixture.db,
            currentMessage,
            messageSurvivor,
          ),
          isTrue,
        );
        currentMessage = (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        expect(
          await dbReplaceGroupInboxRetryPayloadIfExact(
            fixture.db,
            currentMessage,
            messageFixture.retry,
          ),
          isFalse,
        );
        final twoRecipientMessage = Map<String, Object?>.from(currentMessage);
        final messageEventsBefore = await fixture.db.query(
          'group_event_log',
          orderBy: 'sequence ASC',
        );
        expect(
          await dbCompleteGroupContentInboxStoreRetryIfExact(
            fixture.db,
            expected: currentMessage,
            sourcePeerId: _protectedActor,
            sourceEventId: localProtectedGroupMessageSourceEventId(messageId),
            sourceTimestamp: messageAt,
            eventPayload: messageFixture.eventPayload,
          ),
          isFalse,
          reason: 'two pending recipients are not a final receipt',
        );
        expect(
          (await fixture.db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: const <Object?>[messageId],
          )).single,
          twoRecipientMessage,
        );
        expect(
          await fixture.db.query('group_event_log', orderBy: 'sequence ASC'),
          messageEventsBefore,
          reason: 'refusal must not append completion evidence',
        );

        expect(
          await dbReplaceGroupInboxRetryPayloadIfExact(
            fixture.db,
            currentMessage,
            messageRetry.encodeWithPending(const <String>['transport-c']),
          ),
          isTrue,
        );
        currentMessage = (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        expect(
          await dbCompleteGroupContentInboxStoreRetryIfExact(
            fixture.db,
            expected: currentMessage,
            sourcePeerId: _protectedActor,
            sourceEventId: localProtectedGroupMessageSourceEventId(messageId),
            sourceTimestamp: messageAt,
            eventPayload: messageFixture.eventPayload,
          ),
          isTrue,
        );
        final completedMessage = (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        expect(completedMessage['status'], 'sent');
        expect(completedMessage['wire_envelope'], isNull);
        expect(completedMessage['inbox_stored'], 1);
        expect(completedMessage['inbox_retry_payload'], isNull);

        final reactionAt = DateTime.utc(2026, 8, 13, 9, 41);
        final transitionId = _protectedTransition(
          action: 'add',
          emoji: '🧭',
          at: reactionAt,
        );
        final reactionFixture = await _buildStrictPreparedReactionFixture(
          transitionId: transitionId,
          timestamp: fixedGroupContentUtc(reactionAt),
          targetMessageId: _protectedMessageId,
          recipients: recipients,
        );
        final reactionExpected = GroupReactionReplayOutboxEntry(
          reactionId: transitionId,
          groupId: _protectedGroupId,
          messageId: _protectedMessageId,
          senderPeerId: _protectedActor,
          emoji: '🧭',
          action: 'add',
          inboxRetryPayload: reactionFixture.retry,
          deliveryStatus: GroupReactionReplayOutboxStatus.pending,
          createdAt: fixedGroupContentUtc(reactionAt),
          updatedAt: fixedGroupContentUtc(reactionAt),
        ).toMap();
        final reactionPrepared =
            buildLocalProtectedGroupContentPreparedEventPayload(
              eventPayload: reactionFixture.eventPayload,
              ownerKind: 'group_reaction',
              ownerId: transitionId,
              ownerStatus: GroupReactionReplayOutboxStatus.pending,
              inboxRetryPayload: reactionFixture.retry,
            );
        expect(
          await createGroupMultiDeviceReactionReplayOutbox(
            fixture.db,
          ).stageStrictContentPrepared(
            GroupReactionReplayOutboxEntry.fromMap(reactionExpected),
            sourcePeerId: _protectedActor,
            sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
              transitionId,
            ),
            sourceTimestamp: fixedGroupContentUtc(reactionAt),
            preparedEventPayload: reactionPrepared,
          ),
          isTrue,
        );
        expect(
          await createGroupMultiDeviceReactionReplayOutbox(
            fixture.db,
          ).hasExactStrictContentPrepared(
            GroupReactionReplayOutboxEntry.fromMap(reactionExpected),
            eventPayload: reactionFixture.eventPayload,
          ),
          isTrue,
        );
        var currentReaction = (await fixture.db.query(
          'group_reaction_replay_outbox',
          where: 'reaction_id = ?',
          whereArgs: <Object?>[transitionId],
        )).single;
        final reactionRetry = GroupContentRetryPayload.decode(
          reactionFixture.retry,
        );
        Future<bool> replaceReaction(String replacement, int second) =>
            dbReplaceGroupReactionReplayOutboxPayloadIfExact(
              fixture.db,
              expected: currentReaction,
              replacement: replacement,
              updatedAt: fixedGroupContentUtc(
                reactionAt.add(Duration(seconds: second)),
              ),
            );
        expect(
          await replaceReaction(
            reactionRetry.encodeWithPending(const <String>['transport-c']),
            1,
          ),
          isFalse,
        );
        expect(await replaceReaction('legacy retry bytes', 1), isFalse);
        final crossedTransition = _protectedTransition(
          action: 'add',
          emoji: '🪢',
          at: reactionAt.add(const Duration(microseconds: 1)),
        );
        final crossedReaction = await _buildStrictPreparedReactionFixture(
          transitionId: crossedTransition,
          timestamp: fixedGroupContentUtc(
            reactionAt.add(const Duration(microseconds: 1)),
          ),
          targetMessageId: _protectedMessageId,
          recipients: recipients,
        );
        expect(
          await replaceReaction(
            GroupContentRetryPayload.decode(
              crossedReaction.retry,
            ).encodeWithPending(const <String>['transport-b', 'transport-c']),
            1,
          ),
          isFalse,
        );
        final reactionSurvivor = reactionRetry.encodeWithPending(const <String>[
          'transport-b',
          'transport-c',
        ]);
        expect(await replaceReaction(reactionSurvivor, 1), isTrue);
        currentReaction = (await fixture.db.query(
          'group_reaction_replay_outbox',
          where: 'reaction_id = ?',
          whereArgs: <Object?>[transitionId],
        )).single;
        expect(await replaceReaction(reactionFixture.retry, 2), isFalse);
        final twoRecipientReaction = Map<String, Object?>.from(currentReaction);
        final reactionEventsBefore = await fixture.db.query(
          'group_event_log',
          orderBy: 'sequence ASC',
        );
        final reactionProjectionBefore = await fixture.db.query(
          'message_reactions',
          where: 'message_id = ? AND sender_peer_id = ?',
          whereArgs: const <Object?>[_protectedMessageId, _protectedActor],
        );
        expect(
          await dbCompleteGroupReactionContentIfExact(
            fixture.db,
            expected: currentReaction,
            reactionRow: _protectedReactionRow(
              action: 'add',
              emoji: '🧭',
              timestamp: fixedGroupContentUtc(reactionAt),
            ),
            action: 'add',
            transitionId: transitionId,
            sourcePeerId: _protectedActor,
            sourceEventId: localProtectedGroupReactionSourceEventId(
              transitionId,
            ),
            sourceTimestamp: fixedGroupContentUtc(reactionAt),
            eventPayload: reactionFixture.eventPayload,
            updatedAt: fixedGroupContentUtc(
              reactionAt.add(const Duration(seconds: 2)),
            ),
          ),
          isFalse,
          reason: 'two pending recipients are not a final receipt',
        );
        expect(
          (await fixture.db.query(
            'group_reaction_replay_outbox',
            where: 'reaction_id = ?',
            whereArgs: <Object?>[transitionId],
          )).single,
          twoRecipientReaction,
        );
        expect(
          await fixture.db.query('group_event_log', orderBy: 'sequence ASC'),
          reactionEventsBefore,
          reason: 'refusal must not append reaction completion evidence',
        );
        expect(
          await fixture.db.query(
            'message_reactions',
            where: 'message_id = ? AND sender_peer_id = ?',
            whereArgs: const <Object?>[_protectedMessageId, _protectedActor],
          ),
          reactionProjectionBefore,
        );
      },
    );

    test('strict message and ADD evidence survive database restart', () async {
      final fixture = await _ProtectedSenderFixture.create();
      addTearDown(fixture.dispose);
      const messageAt = '2026-08-13T10:00:00.000000Z';
      final localMessage = <String, Object?>{
        ...GroupMessage(
          id: 'strict-empty-acl-message',
          groupId: _protectedGroupId,
          senderPeerId: _protectedActor,
          senderUsername: 'Local',
          text: 'empty ACL still has local evidence',
          timestamp: DateTime.parse(messageAt),
          keyGeneration: 7,
          status: GroupMessage.statusQueuedOffline,
          isIncoming: false,
          createdAt: DateTime.parse(messageAt),
          wireEnvelope: '{"custodyKind":"group_content_v1"}',
          inboxStored: false,
        ).toMap(),
        'retry_attempt_count': 0,
        'next_eligible_at': null,
      };
      final messageSourceEventId = localProtectedGroupMessageSourceEventId(
        'strict-empty-acl-message',
      );
      expect(
        await dbStageAndCompleteLocalGroupContentMessage(
          fixture.db,
          expected: localMessage,
          sourcePeerId: _protectedActor,
          sourceEventId: messageSourceEventId,
          sourceTimestamp: messageAt,
          eventPayload: _protectedEventPayload(
            payloadType: 'group_message',
            contentEventId: 'strict-empty-acl-message',
            timestamp: messageAt,
            recipients: const <String>[],
          ),
        ),
        isTrue,
      );
      // Exact duplicate is idempotent; a conflicting owner is rejected.
      expect(
        await dbStageAndCompleteLocalGroupContentMessage(
          fixture.db,
          expected: localMessage,
          sourcePeerId: _protectedActor,
          sourceEventId: messageSourceEventId,
          sourceTimestamp: messageAt,
          eventPayload: _protectedEventPayload(
            payloadType: 'group_message',
            contentEventId: 'strict-empty-acl-message',
            timestamp: messageAt,
            recipients: const <String>[],
          ),
        ),
        isTrue,
      );

      final addAt = DateTime.utc(2026, 8, 13, 10, 1);
      final addTransition = _protectedTransition(
        action: 'add',
        emoji: '❤️',
        at: addAt,
      );
      final addExpected = _protectedReactionOutboxRow(
        transitionId: addTransition,
        action: 'add',
        emoji: '❤️',
        timestamp: fixedGroupContentUtc(addAt),
        emptyAcl: true,
      );
      expect(
        await createGroupMultiDeviceReactionReplayOutbox(
          fixture.db,
        ).stageAndCompleteStrictLocalContent(
          GroupReactionReplayOutboxEntry.fromMap(addExpected),
          reactionRow: _protectedReactionRow(
            action: 'add',
            emoji: '❤️',
            timestamp: fixedGroupContentUtc(addAt),
          ),
          transitionId: addTransition,
          action: 'add',
          sourcePeerId: _protectedActor,
          sourceEventId: localProtectedGroupReactionSourceEventId(
            addTransition,
          ),
          sourceTimestamp: fixedGroupContentUtc(addAt),
          eventPayload: _protectedEventPayload(
            payloadType: 'group_reaction',
            contentEventId: addTransition,
            timestamp: fixedGroupContentUtc(addAt),
            recipients: const <String>[],
          ),
        ),
        isTrue,
      );

      await fixture.reopen();
      expect(
        await fixture.db.query(
          'group_event_log',
          columns: const <String>['event_type', 'source_event_id'],
          where: 'group_id = ?',
          whereArgs: const <Object?>[_protectedGroupId],
          orderBy: 'sequence ASC',
        ),
        <Map<String, Object?>>[
          <String, Object?>{
            'event_type': protectedGroupMessageEventType,
            'source_event_id': messageSourceEventId,
          },
          <String, Object?>{
            'event_type': protectedGroupReactionEventType,
            'source_event_id': localProtectedGroupReactionSourceEventId(
              addTransition,
            ),
          },
        ],
      );
      final message = (await fixture.db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: const <Object?>['strict-empty-acl-message'],
      )).single;
      expect(message['status'], 'sent');
      expect(message['wire_envelope'], isNull);
      expect(message['inbox_stored'], 1);
      final reaction = await _loadProtectedReaction(fixture.db);
      expect(reaction['emoji'], '❤️');
      expect(reaction['removed_at'], isNull);
    });

    test('newer REMOVE remains after older ADD completion', () async {
      final fixture = await _ProtectedSenderFixture.create();
      addTearDown(fixture.dispose);
      final removeAt = DateTime.utc(2026, 8, 13, 11, 2);
      final addAt = DateTime.utc(2026, 8, 13, 11, 1);
      final removeTransition = _protectedTransition(
        action: 'remove',
        emoji: '👍',
        at: removeAt,
      );
      final addTransition = _protectedTransition(
        action: 'add',
        emoji: '👍',
        at: addAt,
      );
      final removeExpected = await _seedProtectedReactionOutbox(
        fixture.db,
        transitionId: removeTransition,
        action: 'remove',
        emoji: '👍',
        timestamp: fixedGroupContentUtc(removeAt),
      );
      expect(
        await _completeProtectedReaction(
          fixture.db,
          expected: removeExpected,
          transitionId: removeTransition,
          action: 'remove',
          emoji: '👍',
          timestamp: fixedGroupContentUtc(removeAt),
        ),
        isTrue,
      );
      final addExpected = await _seedProtectedReactionOutbox(
        fixture.db,
        transitionId: addTransition,
        action: 'add',
        emoji: '👍',
        timestamp: fixedGroupContentUtc(addAt),
      );
      expect(
        await _completeProtectedReaction(
          fixture.db,
          expected: addExpected,
          transitionId: addTransition,
          action: 'add',
          emoji: '👍',
          timestamp: fixedGroupContentUtc(addAt),
        ),
        isTrue,
      );
      final reaction = await _loadProtectedReaction(fixture.db);
      expect(reaction['timestamp'], fixedGroupContentUtc(removeAt));
      expect(reaction['removed_at'], fixedGroupContentUtc(removeAt));
      expect(await _protectedReactionEventCount(fixture.db), 2);
    });

    test('equal epoch uses transition ID as the LWW tie-break', () async {
      final fixture = await _ProtectedSenderFixture.create();
      addTearDown(fixture.dispose);
      final at = DateTime.utc(2026, 8, 13, 11, 30);
      final timestamp = fixedGroupContentUtc(at);
      final candidates = <({String action, String emoji, String id})>[
        (
          action: 'add',
          emoji: '👍',
          id: _protectedTransition(action: 'add', emoji: '👍', at: at),
        ),
        (
          action: 'remove',
          emoji: '❤️',
          id: _protectedTransition(action: 'remove', emoji: '❤️', at: at),
        ),
      ]..sort((a, b) => compareGroupReactionTransitionIds(a.id, b.id));
      final loser = candidates.first;
      final winner = candidates.last;
      for (final candidate in <({String action, String emoji, String id})>[
        winner,
        loser,
      ]) {
        final expected = await _seedProtectedReactionOutbox(
          fixture.db,
          transitionId: candidate.id,
          action: candidate.action,
          emoji: candidate.emoji,
          timestamp: timestamp,
        );
        expect(
          await _completeProtectedReaction(
            fixture.db,
            expected: expected,
            transitionId: candidate.id,
            action: candidate.action,
            emoji: candidate.emoji,
            timestamp: timestamp,
          ),
          isTrue,
        );
      }
      final reaction = await _loadProtectedReaction(fixture.db);
      expect(reaction['emoji'], winner.emoji);
      expect(
        reaction['removed_at'],
        winner.action == 'remove' ? timestamp : isNull,
      );
      expect(await _protectedReactionEventCount(fixture.db), 2);
    });

    test('owner CAS miss rolls projection and event evidence back', () async {
      final fixture = await _ProtectedSenderFixture.create();
      addTearDown(fixture.dispose);
      final baselineAt = DateTime.utc(2026, 8, 13, 12);
      final baselineTransition = _protectedTransition(
        action: 'add',
        emoji: '👍',
        at: baselineAt,
      );
      final baselineExpected = await _seedProtectedReactionOutbox(
        fixture.db,
        transitionId: baselineTransition,
        action: 'add',
        emoji: '👍',
        timestamp: fixedGroupContentUtc(baselineAt),
      );
      expect(
        await _completeProtectedReaction(
          fixture.db,
          expected: baselineExpected,
          transitionId: baselineTransition,
          action: 'add',
          emoji: '👍',
          timestamp: fixedGroupContentUtc(baselineAt),
        ),
        isTrue,
      );

      final losingAt = DateTime.utc(2026, 8, 13, 12, 1);
      final losingTransition = _protectedTransition(
        action: 'remove',
        emoji: '👍',
        at: losingAt,
      );
      final losingExpected = await _seedProtectedReactionOutbox(
        fixture.db,
        transitionId: losingTransition,
        action: 'remove',
        emoji: '👍',
        timestamp: fixedGroupContentUtc(losingAt),
      );
      await fixture.db.execute('''
        CREATE TRIGGER force_reaction_owner_cas_miss
        BEFORE UPDATE OF delivery_status ON group_reaction_replay_outbox
        WHEN OLD.reaction_id = '$losingTransition'
        BEGIN SELECT RAISE(IGNORE); END
      ''');
      expect(
        await _completeProtectedReaction(
          fixture.db,
          expected: losingExpected,
          transitionId: losingTransition,
          action: 'remove',
          emoji: '👍',
          timestamp: fixedGroupContentUtc(losingAt),
        ),
        isFalse,
      );
      final reaction = await _loadProtectedReaction(fixture.db);
      expect(reaction['timestamp'], fixedGroupContentUtc(baselineAt));
      expect(reaction['removed_at'], isNull);
      expect(
        await fixture.db.query(
          'group_event_log',
          where: 'group_id = ? AND source_event_id = ?',
          whereArgs: <Object?>[
            _protectedGroupId,
            localProtectedGroupReactionSourceEventId(losingTransition),
          ],
        ),
        isEmpty,
      );
    });
  });
}

const _protectedGroupId = 'protected-local-group';
const _protectedActor = 'peer-local';
const _protectedMessageId = 'protected-local-message';

class _ProtectedSenderFixture {
  _ProtectedSenderFixture(this.directory, this.path, this.db);

  final Directory directory;
  final String path;
  Database db;

  static Future<_ProtectedSenderFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'protected_group_sender_completion_',
    );
    final path = p.join(directory.path, 'identity.db');
    final db = await openDatabase(path, version: 1);
    await runMediaAttachmentsMigration(db);
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runGroupMessageReliabilityColumnsMigration(db);
    await runGroupMessageTransportPeerIdMigration(db);
    await runGroupMessageLastSendAttemptAtMigration(db);
    await runGroupMessageLogicalDeliveryIdMigration(db);
    await runGroupMessageRetryBackoffColumnsMigration(db);
    await runGroupMessagesIsForwardedMigration(db);
    await runGroupPrivateMediaLifecycleMigration(db);
    await runMessageReactionsMigration(db);
    await runMessageReactionTombstoneMigration(db);
    await runGroupReactionReplayOutboxMigration(db);
    await runGroupEventLogMigration(db);
    await runGroupMessageLocalDeletionsMigration(db);
    const createdAt = '2026-08-13T09:00:00.000000Z';
    await db.insert('groups', <String, Object?>{
      'id': _protectedGroupId,
      'name': 'Protected local group',
      'type': 'chat',
      'topic_name': 'protected-local-topic',
      'created_at': createdAt,
      'created_by': _protectedActor,
      'my_role': 'admin',
    });
    await db.insert('group_messages', <String, Object?>{
      'id': _protectedMessageId,
      'group_id': _protectedGroupId,
      'sender_peer_id': 'peer-remote',
      'sender_username': 'Remote',
      'text': 'reaction target',
      'timestamp': createdAt,
      'key_generation': 7,
      'status': 'sent',
      'is_incoming': 1,
      'created_at': createdAt,
      'inbox_stored': 1,
    });
    return _ProtectedSenderFixture(directory, path, db);
  }

  Future<void> reopen() async {
    await db.close();
    db = await openDatabase(path, version: 1);
  }

  Future<void> dispose() async {
    if (db.isOpen) await db.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

String _protectedTransition({
  required String action,
  required String emoji,
  required DateTime at,
}) => buildGroupReactionTransitionId(
  groupId: _protectedGroupId,
  messageId: _protectedMessageId,
  logicalActorPeerId: _protectedActor,
  action: action,
  emoji: emoji,
  timestamp: at,
);

Future<({String retry, Map<String, Object?> eventPayload})>
_buildStrictPreparedMessageFixture({
  required String messageId,
  required String timestamp,
  List<String> recipients = const <String>['transport-a', 'transport-b'],
}) async {
  final groupRepo = InMemoryGroupRepository();
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: _protectedGroupId,
      keyGeneration: 7,
      encryptedKey: 'protected-group-key',
      createdAt: DateTime.utc(2026, 8, 13, 8),
    ),
  );
  final plaintext = <String, Object?>{
    'groupId': _protectedGroupId,
    'senderId': _protectedActor,
    'senderUsername': 'Local',
    'senderDeviceId': 'device-local',
    'transportPeerId': 'transport-local',
    'messageId': messageId,
    'logicalDeliveryId': messageId,
    'keyEpoch': 7,
    'text': 'strict prepared fixture',
    'timestamp': timestamp,
  };
  final retry = await buildGroupOfflineReplayInboxRetryPayload(
    bridge: FakeBridge(),
    groupRepo: groupRepo,
    groupId: _protectedGroupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(plaintext),
    senderPeerId: _protectedActor,
    senderPublicKey: 'device-pk-local',
    senderPrivateKey: 'device-sk-local',
    senderDeviceId: 'device-local',
    senderTransportPeerId: 'transport-local',
    recipientPeerIds: recipients,
    messageId: messageId,
    contentEventId: messageId,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: DateTime.utc(2026, 8, 13, 9),
      eventId: 'authority.prepared.fixture',
      keyEpoch: 7,
    ),
  );
  final replay =
      (jsonDecode(retry) as Map<String, Object?>)['message'] as String;
  return (
    retry: retry,
    eventPayload: buildLocalProtectedGroupContentEventPayload(
      replayEnvelope: replay,
      payload: plaintext,
    ),
  );
}

Future<({String retry, Map<String, Object?> eventPayload})>
_buildStrictPreparedReactionFixture({
  required String transitionId,
  required String timestamp,
  required String targetMessageId,
  String action = 'add',
  String emoji = '🧭',
  List<String> recipients = const <String>['transport-a', 'transport-b'],
}) async {
  final groupRepo = InMemoryGroupRepository();
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: _protectedGroupId,
      keyGeneration: 7,
      encryptedKey: 'protected-group-key',
      createdAt: DateTime.utc(2026, 8, 13, 8),
    ),
  );
  final plaintext = <String, Object?>{
    'id': 'protected-reaction-state',
    'messageId': targetMessageId,
    'emoji': emoji,
    'action': action,
    'senderPeerId': _protectedActor,
    'timestamp': timestamp,
    'eventId': transitionId,
  };
  final retry = await buildGroupOfflineReplayInboxRetryPayload(
    bridge: FakeBridge(),
    groupRepo: groupRepo,
    groupId: _protectedGroupId,
    payloadType: groupOfflineReplayPayloadTypeReaction,
    plaintext: jsonEncode(plaintext),
    senderPeerId: _protectedActor,
    senderPublicKey: 'device-pk-local',
    senderPrivateKey: 'device-sk-local',
    senderDeviceId: 'device-local',
    senderTransportPeerId: 'transport-local',
    recipientPeerIds: recipients,
    messageId: transitionId,
    contentEventId: transitionId,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: DateTime.utc(2026, 8, 13, 9),
      eventId: 'authority.prepared.fixture',
      keyEpoch: 7,
    ),
    reactionNotificationExtension: GroupReactionNotificationExtensionInput(
      transitionId: transitionId,
      action: action,
      targetMessageId: targetMessageId,
      reactorPeerId: _protectedActor,
      reactorTransportPeerId: 'transport-local',
      notificationRecipientTransportPeerIds: recipients,
    ),
  );
  final replay =
      (jsonDecode(retry) as Map<String, Object?>)['message'] as String;
  return (
    retry: retry,
    eventPayload: buildLocalProtectedGroupContentEventPayload(
      replayEnvelope: replay,
      payload: plaintext,
    ),
  );
}

Future<Map<String, Object?>> _seedProtectedReactionOutbox(
  Database db, {
  required String transitionId,
  required String action,
  required String emoji,
  required String timestamp,
}) async {
  final strict = await _buildStrictPreparedReactionFixture(
    transitionId: transitionId,
    timestamp: timestamp,
    targetMessageId: _protectedMessageId,
    action: action,
    emoji: emoji,
    recipients: const <String>['peer-remote-device'],
  );
  await db.insert(
    'group_reaction_replay_outbox',
    _protectedReactionOutboxRow(
      transitionId: transitionId,
      action: action,
      emoji: emoji,
      timestamp: timestamp,
      retryPayload: strict.retry,
    ),
  );
  return (await db.query(
    'group_reaction_replay_outbox',
    where: 'reaction_id = ?',
    whereArgs: <Object?>[transitionId],
  )).single;
}

Map<String, Object?> _protectedReactionOutboxRow({
  required String transitionId,
  required String action,
  required String emoji,
  required String timestamp,
  bool emptyAcl = false,
  String? retryPayload,
}) => <String, Object?>{
  'reaction_id': transitionId,
  'group_id': _protectedGroupId,
  'message_id': _protectedMessageId,
  'sender_peer_id': _protectedActor,
  'emoji': emoji,
  'action': action,
  'inbox_retry_payload': emptyAcl ? '' : retryPayload,
  'delivery_status': emptyAcl ? 'stored' : 'pending',
  'last_error': null,
  'created_at': timestamp,
  'updated_at': timestamp,
};

Map<String, Object?> _protectedReactionRow({
  required String action,
  required String emoji,
  required String timestamp,
}) => <String, Object?>{
  'id': 'protected-reaction-state',
  'message_id': _protectedMessageId,
  'emoji': emoji,
  'sender_peer_id': _protectedActor,
  'timestamp': timestamp,
  'created_at': timestamp,
  'removed_at': action == 'remove' ? timestamp : null,
};

Future<bool> _completeProtectedReaction(
  Database db, {
  required Map<String, Object?> expected,
  required String transitionId,
  required String action,
  required String emoji,
  required String timestamp,
}) async {
  final wrapper =
      (jsonDecode(expected['inbox_retry_payload']! as String) as Map)
          .cast<String, Object?>();
  final eventPayload = buildLocalProtectedGroupContentEventPayload(
    replayEnvelope: wrapper['message']! as String,
    payload: <String, Object?>{
      'id': 'protected-reaction-state',
      'messageId': _protectedMessageId,
      'emoji': emoji,
      'action': action,
      'senderPeerId': _protectedActor,
      'timestamp': timestamp,
      'eventId': transitionId,
    },
  );
  await dbAppendGroupEventLogEntry(
    db,
    groupId: _protectedGroupId,
    eventType: protectedGroupContentPreparedEventType,
    sourcePeerId: _protectedActor,
    sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
      transitionId,
    ),
    sourceTimestamp: timestamp,
    payload: <String, Object?>{
      ...eventPayload,
      'preparedOwnerKind': 'group_reaction',
      'preparedOwnerId': transitionId,
      'preparedOwnerStatus': expected['delivery_status'] as String,
      'replayEnvelopeHash': sha256
          .convert(utf8.encode(wrapper['message']! as String))
          .toString(),
    },
  );
  return dbCompleteGroupReactionContentIfExact(
    db,
    expected: expected,
    reactionRow: _protectedReactionRow(
      action: action,
      emoji: emoji,
      timestamp: timestamp,
    ),
    action: action,
    transitionId: transitionId,
    sourcePeerId: _protectedActor,
    sourceEventId: localProtectedGroupReactionSourceEventId(transitionId),
    sourceTimestamp: timestamp,
    eventPayload: eventPayload,
    updatedAt: timestamp,
  );
}

Future<Map<String, Object?>> _loadProtectedReaction(Database db) async =>
    (await db.query(
      'message_reactions',
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: const <Object?>[_protectedMessageId, _protectedActor],
    )).single;

Future<int> _protectedReactionEventCount(Database db) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS count FROM group_event_log '
    'WHERE group_id = ? AND event_type = ?',
    const <Object?>[_protectedGroupId, protectedGroupReactionEventType],
  );
  return (rows.single['count'] as num).toInt();
}

Map<String, Object?> _protectedEventPayload({
  required String payloadType,
  required String contentEventId,
  required String timestamp,
  required List<String> recipients,
}) => <String, Object?>{
  'custodyKind': groupContentCustodyKind,
  'groupId': _protectedGroupId,
  'payloadType': payloadType,
  'contentEventId': contentEventId,
  'authorityEventAt': '2026-08-13T09:30:00.000000Z',
  'authorityEventId': 'authority-event-7',
  'authorityKeyEpoch': 7,
  'logicalSenderPeerId': _protectedActor,
  'senderDeviceId': 'local-device',
  'senderTransportPeerId': 'local-transport',
  'senderPublicKey': 'local-public-key',
  'recipientPeerIds': recipients,
  'payload': <String, Object?>{
    if (payloadType == 'group_message') 'messageId': contentEventId,
    if (payloadType == 'group_reaction') 'eventId': contentEventId,
    'timestamp': timestamp,
  },
};
