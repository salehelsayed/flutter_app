// ignore_for_file: file_names

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/100_direct_private_media_lifecycle.dart';
import 'package:flutter_app/core/database/migrations/101_group_private_media_lifecycle.dart';
import 'package:flutter_app/core/database/migrations/102_groups_self_removed_at.dart';
import 'package:flutter_app/core/database/migrations/103_group_exit_intents.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _columnDefinitions = <String, String>{
  'media_policy_version':
      "INTEGER NOT NULL DEFAULT 0 CHECK (typeof(media_policy_version) = 'integer' AND media_policy_version >= 0)",
  'media_lifecycle':
      "TEXT NOT NULL DEFAULT 'standard' CHECK (media_lifecycle IN ('standard','view_once','disappearing','unsupported'))",
  'media_duration_seconds':
      "INTEGER CHECK (media_duration_seconds IS NULL OR (typeof(media_duration_seconds) = 'integer' AND media_duration_seconds IN (3600,86400,604800)))",
  'media_protected':
      'INTEGER NOT NULL DEFAULT 0 CHECK (media_protected IN (0,1))',
  'media_received_at':
      "INTEGER CHECK (media_received_at IS NULL OR (typeof(media_received_at) = 'integer' AND media_received_at >= 0))",
  'media_expires_at':
      "INTEGER CHECK (media_expires_at IS NULL OR (typeof(media_expires_at) = 'integer' AND media_expires_at >= 0))",
  'media_last_checked_at':
      "INTEGER CHECK (media_last_checked_at IS NULL OR (typeof(media_last_checked_at) = 'integer' AND media_last_checked_at >= 0))",
  'media_consumed_at':
      "INTEGER CHECK (media_consumed_at IS NULL OR (typeof(media_consumed_at) = 'integer' AND media_consumed_at >= 0))",
  'media_expired_at':
      "INTEGER CHECK (media_expired_at IS NULL OR (typeof(media_expired_at) = 'integer' AND media_expired_at >= 0))",
  'media_cleanup_pending':
      'INTEGER NOT NULL DEFAULT 0 CHECK (media_cleanup_pending IN (0,1))',
};

Map<String, Object?> _directMessage(String id) => <String, Object?>{
  'id': id,
  'contact_peer_id': 'contact-1',
  'sender_peer_id': 'contact-1',
  'text': 'direct $id',
  'timestamp': '2026-07-12T00:00:00.000Z',
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': '2026-07-12T00:00:00.000Z',
  'is_forwarded': 1,
  'private_media_policy_version': 1,
  'private_media_mode': 'view_once',
  'private_media_state': 'available',
  'private_media_received_at_ms': 1000,
  'private_media_clock_high_water_ms': 1000,
};

Map<String, Object?> _groupMessage(String id) => <String, Object?>{
  'id': id,
  'group_id': 'group-1',
  'sender_peer_id': 'group-peer',
  'sender_username': 'Group peer',
  'text': 'group $id',
  'timestamp': '2026-07-12T00:00:00.000Z',
  'key_generation': 3,
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': '2026-07-12T00:00:00.000Z',
  'is_forwarded': 1,
};

Future<Map<String, Map<String, Object?>>> _columns(
  Database db,
  String table,
) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {for (final row in rows) row['name'] as String: row};
}

Future<List<String>> _indexColumns(Database db, String indexName) async {
  final rows = await db.rawQuery('PRAGMA index_info($indexName)');
  final ordered = [...rows]
    ..sort(
      (a, b) =>
          (a['seqno'] as num).toInt().compareTo((b['seqno'] as num).toInt()),
    );
  return ordered.map((row) => row['name'] as String).toList();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'GPL-01 v101 preserves v100 and adds constrained group private lifecycle idempotently',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 100);

      await db.insert('messages', _directMessage('shared-parent'));
      await db.insert('group_messages', _groupMessage('shared-parent'));
      for (final fixture in const [
        ('direct-att', 'shared-parent', 'direct'),
        ('group-att', 'shared-parent', 'group'),
        ('unresolved-att', 'missing-parent', 'unresolved'),
      ]) {
        await db.insert('media_attachments', {
          'id': fixture.$1,
          'message_id': fixture.$2,
          'mime': 'image/jpeg',
          'size': 42,
          'media_type': 'image',
          'local_path': '/media/${fixture.$1}.jpg',
          'download_status': 'done',
          'created_at': '2026-07-12T00:00:01.000Z',
          'owner_lane': fixture.$3,
          'is_bookmarked': 1,
          'last_playback_position_ms': 321,
        });
      }

      final directSchemaBefore = (await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'",
      )).single['sql'];
      final directBefore = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['shared-parent'],
      )).single;
      final attachmentsBefore = await db.query(
        'media_attachments',
        orderBy: 'id',
      );

      await runProductionOnUpgrade(db, 100, 101);
      await runProductionOnUpgrade(db, 100, 101);
      await runGroupPrivateMediaLifecycleMigration(db);

      expect(currentIdentityDatabaseVersion, 118);
      for (final registry in [
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final index100 = registry.indexWhere((entry) => entry.version == 100);
        final index101 = registry.indexWhere((entry) => entry.version == 101);
        final index102 = registry.indexWhere((entry) => entry.version == 102);
        final index103 = registry.indexWhere((entry) => entry.version == 103);
        final index104 = registry.indexWhere((entry) => entry.version == 104);
        expect(registry.where((entry) => entry.version == 100), hasLength(1));
        expect(registry.where((entry) => entry.version == 101), hasLength(1));
        expect(registry.where((entry) => entry.version == 102), hasLength(1));
        expect(registry.where((entry) => entry.version == 103), hasLength(1));
        expect(registry.where((entry) => entry.version == 104), hasLength(1));
        expect(registry.where((entry) => entry.version == 105), hasLength(1));
        expect(registry.where((entry) => entry.version == 106), hasLength(1));
        expect(registry.where((entry) => entry.version == 107), hasLength(1));
        expect(registry.where((entry) => entry.version == 108), hasLength(1));
        expect(registry.where((entry) => entry.version == 109), hasLength(1));
        expect(registry.where((entry) => entry.version == 110), hasLength(1));
        expect(registry.where((entry) => entry.version == 111), hasLength(1));
        expect(index101, index100 + 1);
        expect(index102, index101 + 1);
        expect(index103, index102 + 1);
        expect(index104, index103 + 1);
        final index105 = registry.indexWhere((entry) => entry.version == 105);
        final index106 = registry.indexWhere((entry) => entry.version == 106);
        final index107 = registry.indexWhere((entry) => entry.version == 107);
        final index108 = registry.indexWhere((entry) => entry.version == 108);
        final index109 = registry.indexWhere((entry) => entry.version == 109);
        final index110 = registry.indexWhere((entry) => entry.version == 110);
        final index111 = registry.indexWhere((entry) => entry.version == 111);
        expect(index105, index104 + 1);
        expect(index106, index105 + 1);
        expect(index107, index106 + 1);
        expect(index108, index107 + 1);
        expect(index109, index108 + 1);
        expect(index110, index109 + 1);
        expect(index111, index110 + 1);
        expect(index111, registry.length - 8);
        expect(
          registry[index100].run,
          same(runDirectPrivateMediaLifecycleMigration),
        );
        expect(registry[index108].name, '108_direct_inbox_custody_outbox');
        expect(
          registry[index109].name,
          '109_direct_reaction_inbox_custody_outbox',
        );
        expect(registry[index110].name, '110_direct_media_custody_intent');
        expect(registry[index111].name, '111_direct_media_blob_custody');
        expect(registry[index101].name, '101_group_private_media_lifecycle');
        expect(
          registry[index101].run,
          same(runGroupPrivateMediaLifecycleMigration),
        );
        expect(registry[index102].name, '102_groups_self_removed_at');
        expect(registry[index102].run, same(runGroupsSelfRemovedAtMigration));
        expect(registry[index103].name, '103_group_exit_intents');
        expect(registry[index103].run, same(runGroupExitIntentsMigration));
        expect(registry[index104].name, '104_group_exit_diagnostics');
        expect(registry[index104].run, same(runGroupExitDiagnosticsMigration));
        expect(registry[index105].name, '105_reaction_outbox_needs_build');
        expect(
          registry[index106].name,
          '106_group_notification_display_outbox',
        );
      }

      final columns = await _columns(db, 'group_messages');
      expect(columns.keys, containsAll(_columnDefinitions.keys));
      expect(columns['media_policy_version']!['type'], 'INTEGER');
      expect(columns['media_policy_version']!['notnull'], 1);
      expect(columns['media_policy_version']!['dflt_value'], '0');
      expect(columns['media_lifecycle']!['type'], 'TEXT');
      expect(columns['media_lifecycle']!['notnull'], 1);
      expect(columns['media_lifecycle']!['dflt_value'], "'standard'");
      expect(columns['media_duration_seconds']!['notnull'], 0);
      expect(columns['media_protected']!['notnull'], 1);
      expect(columns['media_protected']!['dflt_value'], '0');
      expect(columns['media_cleanup_pending']!['notnull'], 1);
      expect(columns['media_cleanup_pending']!['dflt_value'], '0');
      for (final nullable in const [
        'media_duration_seconds',
        'media_received_at',
        'media_expires_at',
        'media_last_checked_at',
        'media_consumed_at',
        'media_expired_at',
      ]) {
        expect(columns[nullable]!['type'], 'INTEGER', reason: nullable);
        expect(columns[nullable]!['notnull'], 0, reason: nullable);
        expect(columns[nullable]!['dflt_value'], isNull, reason: nullable);
      }

      final tableSql =
          (await db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name='group_messages'",
              )).single['sql']
              as String;
      for (final definition in _columnDefinitions.entries) {
        expect(
          tableSql,
          contains('${definition.key} ${definition.value}'),
          reason: definition.key,
        );
      }
      expect(
        await _indexColumns(db, 'idx_group_messages_private_media_expiry'),
        ['media_expires_at'],
      );

      final legacy = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['shared-parent'],
      )).single;
      expect(legacy['media_policy_version'], 0);
      expect(legacy['media_lifecycle'], 'standard');
      expect(legacy['media_duration_seconds'], isNull);
      expect(legacy['media_protected'], 0);
      expect(legacy['media_received_at'], isNull);
      expect(legacy['media_expires_at'], isNull);
      expect(legacy['media_last_checked_at'], isNull);
      expect(legacy['media_consumed_at'], isNull);
      expect(legacy['media_expired_at'], isNull);
      expect(legacy['media_cleanup_pending'], 0);

      expect(
        (await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'",
        )).single['sql'],
        directSchemaBefore,
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: ['shared-parent'],
        )).single,
        directBefore,
      );
      expect(
        await db.query('media_attachments', orderBy: 'id'),
        attachmentsBefore,
      );

      await db.update(
        'group_messages',
        {
          'media_policy_version': 1,
          'media_lifecycle': 'disappearing',
          'media_duration_seconds': 3600,
          'media_protected': 1,
          'media_received_at': 1000,
          'media_expires_at': 3601000,
          'media_last_checked_at': 2000,
          'media_cleanup_pending': 0,
        },
        where: 'id = ?',
        whereArgs: ['shared-parent'],
      );

      for (final invalid in <String, Object?>{
        'media_policy_version': -1,
        'media_lifecycle': 'future',
        'media_duration_seconds': 60,
        'media_protected': 2,
        'media_received_at': -1,
        'media_expires_at': -1,
        'media_last_checked_at': -1,
        'media_consumed_at': -1,
        'media_expired_at': -1,
        'media_cleanup_pending': 2,
      }.entries) {
        await expectLater(
          db.update(
            'group_messages',
            {invalid.key: invalid.value},
            where: 'id = ?',
            whereArgs: ['shared-parent'],
          ),
          throwsA(anything),
          reason: '${invalid.key} must enforce its v101 CHECK',
        );
      }

      for (final strictIntegerColumn in const [
        'media_policy_version',
        'media_duration_seconds',
        'media_received_at',
        'media_expires_at',
        'media_last_checked_at',
        'media_consumed_at',
        'media_expired_at',
      ]) {
        await expectLater(
          db.update(
            'group_messages',
            {strictIntegerColumn: 1.5},
            where: 'id = ?',
            whereArgs: ['shared-parent'],
          ),
          throwsA(anything),
          reason: '$strictIntegerColumn must reject REAL storage',
        );
      }
    },
  );
}
