// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/103_group_exit_intents.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'PB264-04 v103 schema, empty backfill, constraints, registry, and rerun are exact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'group_exit_intents_v103_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final databasePath = '${tempDir.path}/identity.db';

      final predecessor = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 102,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (predecessor.isOpen) await predecessor.close();
      });
      expect(
        (await predecessor.rawQuery(
          'PRAGMA user_version',
        )).single.values.single,
        102,
      );
      await predecessor.insert('groups', <String, Object?>{
        'id': 'legacy-group',
        'name': 'Legacy',
        'type': 'chat',
        'topic_name': 'topic-legacy',
        'created_at': '2026-07-20T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'member',
      });
      await predecessor.insert('pending_group_broadcasts', <String, Object?>{
        'id': 'legacy-role',
        'group_id': 'legacy-group',
        'kind': 'member_role_updated',
        'sys_text': '{}',
        'recipient_peer_ids': '[]',
        'event_at': '2026-07-20T12:00:00.000Z',
        'source_message_id': 'legacy-source',
        'created_at': '2026-07-20T12:00:00.000Z',
        'updated_at': '2026-07-20T12:00:00.000Z',
      });
      final legacyGroupsBefore = await predecessor.query('groups');
      final legacyBroadcastsBefore = await predecessor.query(
        'pending_group_broadcasts',
      );
      await predecessor.close();

      // This is a literal file-backed v102 -> v103 reopen through the same
      // callbacks used by production. Directly invoking the migration alone
      // cannot prove registry ordering or SQLite's version dispatch.
      final upgraded = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 103,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (upgraded.isOpen) await upgraded.close();
      });
      expect(
        (await upgraded.rawQuery('PRAGMA user_version')).single.values.single,
        103,
      );

      await runGroupExitIntentsMigration(upgraded);
      await runGroupExitIntentsMigration(upgraded);
      await upgraded.close();

      final db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 103,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });

      expect(currentIdentityDatabaseVersion, 105);
      expect(productionCreateMigrations.last.version, 105);
      expect(productionUpgradeMigrations.last.version, 105);
      expect(
        productionUpgradeMigrations
            .singleWhere((entry) => entry.version == 103)
            .name,
        '103_group_exit_intents',
      );
      expect(
        productionUpgradeMigrations
            .singleWhere((entry) => entry.version == 104)
            .name,
        '104_group_exit_diagnostics',
      );
      expect(
        productionUpgradeMigrations.last.name,
        '105_reaction_outbox_needs_build',
      );
      expect(await db.query('group_exit_intents'), isEmpty);
      expect(await db.query('groups'), legacyGroupsBefore);
      expect(
        await db.query('pending_group_broadcasts'),
        legacyBroadcastsBefore,
      );

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_exit_intents)',
      );
      expect(columns.map((row) => row['name']), <String>[
        'group_id',
        'intent_id',
        'self_peer_id',
        'self_joined_at',
        'state',
        'pending_broadcast_id',
        'source_event_id',
        'event_at',
        'revision',
        'last_error_code',
        'created_at',
        'updated_at',
      ]);
      final indexes = await db.rawQuery(
        'PRAGMA index_list(group_exit_intents)',
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_group_exit_intents_state_updated'),
      );

      Map<String, Object?> validRow({
        String groupId = 'group-1',
        String intentId = 'intent-1',
        String pendingId = 'pending-1',
        String state = 'queued',
        String? sourceEventId,
        String? eventAt,
        int revision = 0,
        String? lastErrorCode,
      }) => <String, Object?>{
        'group_id': groupId,
        'intent_id': intentId,
        'self_peer_id': 'peer-self',
        'self_joined_at': '2026-07-20T12:01:00.000Z',
        'state': state,
        'pending_broadcast_id': pendingId,
        'source_event_id': sourceEventId,
        'event_at': eventAt,
        'revision': revision,
        'last_error_code': lastErrorCode,
        'created_at': '2026-07-20T12:00:00.000Z',
        'updated_at': '2026-07-20T12:00:00.000Z',
      };

      await db.insert('group_exit_intents', validRow());
      for (final invalid in <Map<String, Object?>>[
        validRow(
          groupId: 'bad-state',
          intentId: 'bad-state',
          pendingId: 'bad-state',
          state: 'unknown',
        ),
        validRow(
          groupId: 'bad-queued-shape',
          intentId: 'bad-queued-shape',
          pendingId: 'bad-queued-shape',
          sourceEventId: 'source',
          eventAt: '2026-07-20T12:02:00.000Z',
        ),
        validRow(
          groupId: 'bad-pending-shape',
          intentId: 'bad-pending-shape',
          pendingId: 'bad-pending-shape',
          state: 'leave_notice_pending',
          sourceEventId: 'source',
        ),
        validRow(
          groupId: 'bad-revision',
          intentId: 'bad-revision',
          pendingId: 'bad-revision',
          revision: -1,
        ),
        validRow(
          groupId: 'bad-error-raw',
          intentId: 'bad-error-raw',
          pendingId: 'bad-error-raw',
          lastErrorCode: 'SocketException: secret payload',
        ),
        validRow(
          groupId: 'bad-error-long',
          intentId: 'bad-error-long',
          pendingId: 'bad-error-long',
          lastErrorCode: List<String>.filled(65, 'x').join(),
        ),
        validRow(
          groupId: 'bad-error-empty',
          intentId: 'bad-error-empty',
          pendingId: 'bad-error-empty',
          lastErrorCode: '',
        ),
        validRow(groupId: 'duplicate-intent', pendingId: 'pending-2'),
        validRow(groupId: 'duplicate-pending', intentId: 'intent-2'),
      ]) {
        await expectLater(
          db.insert('group_exit_intents', invalid),
          throwsA(isA<DatabaseException>()),
        );
      }

      await db.insert(
        'group_exit_intents',
        validRow(
          groupId: 'later',
          intentId: 'intent-later',
          pendingId: 'pending-later',
          state: 'native_leave_pending',
          sourceEventId: 'source-later',
          eventAt: '2026-07-20T12:02:00.000Z',
          revision: 4,
          lastErrorCode: 'native_retry:timeout-1',
        ),
      );
      expect(await db.query('group_exit_intents'), hasLength(2));
    },
  );
}
