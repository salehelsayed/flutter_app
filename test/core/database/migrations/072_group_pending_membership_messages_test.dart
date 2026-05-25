// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/072_group_pending_membership_messages.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> columns() async {
    final rows = await db.rawQuery(
      'PRAGMA table_info(group_pending_membership_messages)',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  test('creates durable pending membership message schema', () async {
    await runGroupPendingMembershipMessagesMigration(db);

    expect(
      await columns(),
      containsAll([
        'id',
        'group_id',
        'sender_peer_id',
        'message_id',
        'payload_json',
        'received_at',
        'created_at',
        'updated_at',
      ]),
    );

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='group_pending_membership_messages'",
    );
    expect(
      indexes.map((row) => row['name'] as String),
      containsAll([
        'idx_group_pending_membership_messages_group_sender_received',
        'idx_group_pending_membership_messages_group_received',
        'idx_group_pending_membership_messages_group_message',
      ]),
    );
  });

  test('is idempotent', () async {
    await runGroupPendingMembershipMessagesMigration(db);
    await runGroupPendingMembershipMessagesMigration(db);

    final idColumns = (await columns()).where((name) => name == 'id').toList();
    expect(idColumns, hasLength(1));
  });

  test(
    'enforces unique group message id only when message id is present',
    () async {
      await runGroupPendingMembershipMessagesMigration(db);

      await db.insert('group_pending_membership_messages', {
        'id': 'pending-1',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-late',
        'message_id': 'msg-1',
        'payload_json': '{"messageId":"msg-1"}',
        'received_at': '2026-05-23T12:00:00.000Z',
        'created_at': '2026-05-23T12:00:00.000Z',
        'updated_at': '2026-05-23T12:00:00.000Z',
      });

      expect(
        () => db.insert('group_pending_membership_messages', {
          'id': 'pending-2',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-late',
          'message_id': 'msg-1',
          'payload_json': '{"messageId":"msg-1","duplicate":true}',
          'received_at': '2026-05-23T12:00:01.000Z',
          'created_at': '2026-05-23T12:00:01.000Z',
          'updated_at': '2026-05-23T12:00:01.000Z',
        }),
        throwsA(anything),
      );

      await db.insert('group_pending_membership_messages', {
        'id': 'pending-no-id-1',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-late',
        'message_id': null,
        'payload_json': '{"text":"legacy one"}',
        'received_at': '2026-05-23T12:00:02.000Z',
        'created_at': '2026-05-23T12:00:02.000Z',
        'updated_at': '2026-05-23T12:00:02.000Z',
      });
      await db.insert('group_pending_membership_messages', {
        'id': 'pending-no-id-2',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-late',
        'message_id': null,
        'payload_json': '{"text":"legacy two"}',
        'received_at': '2026-05-23T12:00:03.000Z',
        'created_at': '2026-05-23T12:00:03.000Z',
        'updated_at': '2026-05-23T12:00:03.000Z',
      });
    },
  );
}
