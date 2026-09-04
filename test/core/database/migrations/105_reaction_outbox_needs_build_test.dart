// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _row(
  String id, {
  String status = 'pending',
  String payload = '{"groupId":"g-1"}',
}) => <String, Object?>{
  'reaction_id': id,
  'group_id': 'g-1',
  'message_id': 'm-1',
  'sender_peer_id': 'p-1',
  'emoji': '\u{1F44D}',
  'action': 'add',
  'inbox_retry_payload': payload,
  'delivery_status': status,
  'last_error': null,
  'created_at': '2026-08-01T10:00:00.000Z',
  'updated_at': '2026-08-01T10:00:00.000Z',
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'migration widens status and preserves rows, rowid, and indexes',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reaction_outbox_v105_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final path = '${tempDir.path}/identity.db';

      final predecessor = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 104,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await predecessor.insert('group_reaction_replay_outbox', _row('r-1'));
      await predecessor.insert(
        'group_reaction_replay_outbox',
        _row('r-2', status: 'failed'),
      );
      final rowidsBefore = await predecessor.rawQuery(
        'SELECT rowid, reaction_id FROM group_reaction_replay_outbox '
        'ORDER BY reaction_id',
      );
      await predecessor.close();

      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });

      expect(currentIdentityDatabaseVersion, 117);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        117,
      );

      // Rows preserved verbatim, rowid included (tiebreak readers).
      final rowidsAfter = await db.rawQuery(
        'SELECT rowid, reaction_id FROM group_reaction_replay_outbox '
        'ORDER BY reaction_id',
      );
      expect(rowidsAfter, rowidsBefore);

      // Both indexes recreated.
      final indexes = (await db.rawQuery(
        "PRAGMA index_list('group_reaction_replay_outbox')",
      )).map((row) => row['name']).toSet();
      expect(
        indexes,
        containsAll(<String>{
          'idx_group_reaction_replay_outbox_retryable',
          'idx_group_reaction_replay_outbox_group_message',
        }),
      );

      // needs_build with sentinel-empty payload is representable...
      await db.insert(
        'group_reaction_replay_outbox',
        _row('r-3', status: 'needs_build', payload: ''),
      );
      // ...but an empty payload with any OTHER status stays illegal, and an
      // unknown status stays illegal.
      await expectLater(
        db.insert(
          'group_reaction_replay_outbox',
          _row('r-bad-1', status: 'pending', payload: ''),
        ),
        throwsA(anything),
      );
      await expectLater(
        db.insert('group_reaction_replay_outbox', _row('r-bad-2', status: 'x')),
        throwsA(anything),
      );

      // Old-build read path honesty (TC-319-14): the UNFILTERED
      // latest-for-target shape parses the sentinel row without crashing.
      final latest = await db.rawQuery(
        'SELECT * FROM group_reaction_replay_outbox '
        'WHERE group_id = ? AND message_id = ? AND sender_peer_id = ? '
        'ORDER BY created_at DESC, rowid DESC LIMIT 1',
        ['g-1', 'm-1', 'p-1'],
      );
      expect(latest.single['inbox_retry_payload'] as String, '');

      // Run-twice idempotency: re-running the migration body rebuilds the
      // table with identical schema and rows.
      final registry = productionUpgradeMigrations;
      final v105 = registry.singleWhere((entry) => entry.version == 105);
      await v105.run(db);
      final rowsAfterRerun = await db.query(
        'group_reaction_replay_outbox',
        orderBy: 'reaction_id',
      );
      expect(rowsAfterRerun, hasLength(3));
      expect(rowsAfterRerun.first['reaction_id'], 'r-1');
    },
  );
}
