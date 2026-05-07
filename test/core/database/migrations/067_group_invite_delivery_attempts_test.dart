import 'package:flutter_app/core/database/migrations/067_group_invite_delivery_attempts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  group('Migration 067: group_invite_delivery_attempts', () {
    test('creates local invite delivery attempts table and indexes', () async {
      await runGroupInviteDeliveryAttemptsMigration(db);

      final columns = await db.rawQuery(
        "PRAGMA table_info('group_invite_delivery_attempts')",
      );
      expect(
        columns.map((row) => row['name']).toSet(),
        containsAll([
          'group_id',
          'peer_id',
          'username',
          'status',
          'attempted_at',
          'updated_at',
          'last_error',
        ]),
      );

      final indexes = await db.rawQuery(
        "PRAGMA index_list('group_invite_delivery_attempts')",
      );
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(
        indexNames,
        contains('idx_group_invite_delivery_attempts_group_status'),
      );
      expect(indexNames, contains('idx_group_invite_delivery_attempts_peer'));
    });

    test('is idempotent', () async {
      await runGroupInviteDeliveryAttemptsMigration(db);
      await runGroupInviteDeliveryAttemptsMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'group_invite_delivery_attempts'",
      );
      expect(tables, isNotEmpty);
    });

    test(
      'enforces one status row per group/member and allowed statuses',
      () async {
        await runGroupInviteDeliveryAttemptsMigration(db);

        await db.insert('group_invite_delivery_attempts', {
          'group_id': 'group-1',
          'peer_id': 'peer-a',
          'username': 'Alice',
          'status': 'sent',
          'attempted_at': '2026-05-07T12:00:00.000Z',
          'updated_at': '2026-05-07T12:00:00.000Z',
        });
        await db.insert(
          'group_invite_delivery_attempts',
          {
            'group_id': 'group-1',
            'peer_id': 'peer-a',
            'username': 'Alice',
            'status': 'queued',
            'attempted_at': '2026-05-07T12:05:00.000Z',
            'updated_at': '2026-05-07T12:05:00.000Z',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final rows = await db.query('group_invite_delivery_attempts');
        expect(rows, hasLength(1));
        expect(rows.single['status'], 'queued');

        expect(
          () async => db.insert('group_invite_delivery_attempts', {
            'group_id': 'group-1',
            'peer_id': 'peer-b',
            'username': 'Bob',
            'status': 'accepted',
            'attempted_at': '2026-05-07T12:00:00.000Z',
            'updated_at': '2026-05-07T12:00:00.000Z',
          }),
          throwsA(anything),
        );
      },
    );
  });
}
