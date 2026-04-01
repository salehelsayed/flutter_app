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
import 'package:flutter_app/core/database/migrations/014_wire_envelope_column.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

void main() {
  late Database db;
  late MessageRepositoryImpl messageRepo;

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
    await runWireEnvelopeMigration(db);
    await runMessagesDeletedStateMigration(db);

    messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(db, row),
      dbLoadMessagesForContact: (peerId) =>
          dbLoadMessagesForContact(db, peerId),
      dbLoadLatestMessageForContact: (peerId) =>
          dbLoadLatestMessageForContact(db, peerId),
      dbUpdateMessageStatus: (id, status) =>
          dbUpdateMessageStatus(db, id, status),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbCountMessagesForContact: (peerId) =>
          dbCountMessagesForContact(db, peerId),
      dbMarkConversationAsRead: (peerId) =>
          dbMarkConversationAsRead(db, peerId),
      dbCountUnreadForContact: (peerId) => dbCountUnreadForContact(db, peerId),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (peerId) =>
          dbDeleteMessagesForContact(db, peerId),
      dbDeleteMessage: (id) => dbDeleteMessage(db, id),
      dbLoadMessagesPage: (peerId, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            db,
            peerId,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, wireEnvelope) =>
          dbUpdateWireEnvelope(db, id, wireEnvelope),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbLoadStuckSendingOutgoingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
      dbConditionalTransitionStatus:
          (id, {required fromStatus, required toStatus}) =>
              dbConditionalTransitionStatus(
                db,
                id,
                fromStatus: fromStatus,
                toStatus: toStatus,
              ),
    );
  });

  tearDown(() async => db.close());

  Map<String, Object?> makeRow({
    required String id,
    required String status,
    String contactPeerId = 'peer-a',
    String? wireEnvelope,
  }) => {
    'id': id,
    'contact_peer_id': contactPeerId,
    'sender_peer_id': 'my-peer-id',
    'text': 'Hello',
    'timestamp': '2026-01-01T00:00:00.000Z',
    'status': status,
    'is_incoming': 0,
    'created_at': '2026-01-01T00:00:00.000Z',
    'wire_envelope': wireEnvelope,
  };

  group('DB state after handleAppPaused', () {
    test('sending message is persisted as failed in DB after pause', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-001', status: 'sending'));

      await handleAppPaused(messageRepo: messageRepo);

      final rows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-001'],
      );
      expect(rows.single['status'], 'failed');
    });

    test('wire_envelope survives the sending->failed transition', () async {
      const envelope = '{"version":"2","encrypted":{}}';
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-002', status: 'sending', wireEnvelope: envelope),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final rows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-002'],
      );
      expect(rows.single['status'], 'failed');
      expect(rows.single['wire_envelope'], envelope);
    });

    test('delivered messages remain delivered after pause', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-003', status: 'delivered'));

      await handleAppPaused(messageRepo: messageRepo);

      final rows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-003'],
      );
      expect(rows.single['status'], 'delivered');
    });

    test('messageChanges stream emits updated messages', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-004', status: 'sending'));

      // Set up listener BEFORE the pause call so we capture the emission
      final emitted = <String>[];
      final sub = messageRepo.messageChanges.listen(
        (msg) => emitted.add('${msg.id}:${msg.status}'),
      );

      await handleAppPaused(messageRepo: messageRepo);

      // Allow microtasks to flush
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(emitted, contains('msg-004:failed'));
    });

    test(
      'failed messages are available for retryFailedMessages after pause',
      () async {
        await dbInsertMessage(db, makeRow(id: 'msg-005', status: 'sending'));

        await handleAppPaused(messageRepo: messageRepo);

        final failed = await messageRepo.getFailedOutgoingMessages();
        expect(failed.length, 1);
        expect(failed.first.id, 'msg-005');
        expect(failed.first.status, 'failed');
      },
    );

    test(
      'getSendingOutgoingMessages returns empty after pause completes',
      () async {
        await dbInsertMessage(db, makeRow(id: 'msg-006', status: 'sending'));

        await handleAppPaused(messageRepo: messageRepo);

        final sending = await messageRepo.getSendingOutgoingMessages();
        expect(
          sending,
          isEmpty,
          reason: 'No messages should remain in sending state after pause',
        );
      },
    );
  });
}
