import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/051_pending_group_invites.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 051: pending_group_invites', () {
    test('creates pending_group_invites table', () async {
      await runPendingGroupInvitesMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pending_group_invites'",
      );
      expect(tables, isNotEmpty);
    });

    test('stores and loads pending invite rows', () async {
      await runPendingGroupInvitesMigration(db);

      await db.insert('pending_group_invites', {
        'group_id': 'group-1',
        'invite_id': 'invite-1',
        'payload_json': '{"type":"group_invite"}',
        'group_name': 'Book Club',
        'group_type': 'chat',
        'group_description': 'A group for book lovers',
        'avatar_blob_id': 'blob-1',
        'avatar_mime': 'image/jpeg',
        'sender_peer_id': 'peer-admin',
        'sender_username': 'Admin',
        'created_by': 'peer-admin',
        'created_at': '2026-04-05T12:00:00.000Z',
        'metadata_updated_at': '2026-04-05T12:05:00.000Z',
        'received_at': '2026-04-05T13:00:00.000Z',
        'expires_at': '2026-04-12T13:00:00.000Z',
      });

      final rows = await db.query(
        'pending_group_invites',
        where: 'group_id = ?',
        whereArgs: ['group-1'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['group_name'], 'Book Club');
      expect(rows.first['expires_at'], '2026-04-12T13:00:00.000Z');
    });

    test('is idempotent', () async {
      await runPendingGroupInvitesMigration(db);
      await runPendingGroupInvitesMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pending_group_invites'",
      );
      expect(tables, isNotEmpty);
    });
  });
}
