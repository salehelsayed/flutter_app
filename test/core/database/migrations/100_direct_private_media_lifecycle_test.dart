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

const _privateColumns = <String>[
  'private_media_policy_version',
  'private_media_mode',
  'private_media_duration_seconds',
  'private_media_state',
  'private_media_received_at_ms',
  'private_media_expires_at_ms',
  'private_media_revealed_at_ms',
  'private_media_terminal_at_ms',
  'private_media_clock_high_water_ms',
];

Map<String, Object?> _directMessage(
  String id, {
  Map<String, Object?> extra = const {},
}) => <String, Object?>{
  'id': id,
  'contact_peer_id': 'contact-1',
  'sender_peer_id': 'contact-1',
  'text': 'direct $id',
  'timestamp': '2026-07-11T00:00:00.000Z',
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': '2026-07-11T00:00:00.000Z',
  ...extra,
};

Map<String, Object?> _groupMessage(String id) => <String, Object?>{
  'id': id,
  'group_id': 'group-1',
  'sender_peer_id': 'group-peer',
  'sender_username': 'Group peer',
  'text': 'group $id',
  'timestamp': '2026-07-11T00:00:00.000Z',
  'key_generation': 3,
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': '2026-07-11T00:00:00.000Z',
  'is_forwarded': 1,
};

Future<void> _seedCompleteV99(Database db) async {
  await db.insert(
    'messages',
    _directMessage('shared-parent', extra: const {'is_forwarded': 1}),
  );
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
      'created_at': '2026-07-11T00:00:01.000Z',
      'owner_lane': fixture.$3,
      'is_bookmarked': 1,
      'last_playback_position_ms': 321,
    });
  }

  await db.insert('group_media_deletion_journal', {
    'attachment_id': 'journal-att',
    'operation_id': 'operation-1',
    'message_id': 'shared-parent',
    'group_id': 'group-1',
    'operation_intent': 'delete_for_me',
    'normalized_mime': 'image/jpeg',
    'canonical_relative_path': 'media/group-1/journal-att.jpg',
    'created_at': '2026-07-11T00:00:02.000Z',
  });
}

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
    'v100 remains the sole successor to v99 and later versions follow it',
    () {
      expect(currentIdentityDatabaseVersion, 109);
      for (final registry in [
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
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
        expect(registry.where((entry) => entry.version > 109), isEmpty);
        final index99 = registry.indexWhere((entry) => entry.version == 99);
        final index100 = registry.indexWhere((entry) => entry.version == 100);
        final index101 = registry.indexWhere((entry) => entry.version == 101);
        final index102 = registry.indexWhere((entry) => entry.version == 102);
        final index103 = registry.indexWhere((entry) => entry.version == 103);
        final index104 = registry.indexWhere((entry) => entry.version == 104);
        expect(index99, greaterThanOrEqualTo(0));
        expect(index100, index99 + 1);
        expect(index101, index100 + 1);
        expect(index102, index101 + 1);
        expect(index103, index102 + 1);
        expect(index104, index103 + 1);
        final index105 = registry.indexWhere((entry) => entry.version == 105);
        final index106 = registry.indexWhere((entry) => entry.version == 106);
        final index107 = registry.indexWhere((entry) => entry.version == 107);
        final index108 = registry.indexWhere((entry) => entry.version == 108);
        final index109 = registry.indexWhere((entry) => entry.version == 109);
        expect(index105, index104 + 1);
        expect(index106, index105 + 1);
        expect(index107, index106 + 1);
        expect(index108, index107 + 1);
        expect(index109, index108 + 1);
        expect(index109, registry.length - 1);
        expect(registry[index100].name, '100_direct_private_media_lifecycle');
        expect(
          registry[index100].run,
          same(runDirectPrivateMediaLifecycleMigration),
        );
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
        expect(registry[index107].name, '107_direct_notification_durability');
        expect(registry[index108].name, '108_direct_inbox_custody_outbox');
        expect(
          registry[index109].name,
          '109_direct_reaction_inbox_custody_outbox',
        );
      }
    },
  );

  test(
    'real 99 to 100 upgrade is idempotent constrained and preserves sibling owners',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 99);
      await _seedCompleteV99(db);

      final groupColumnsBefore = (await _columns(
        db,
        'group_messages',
      )).keys.toList();
      final groupSchemaBefore = (await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='group_messages'",
      )).single['sql'];

      await runProductionOnUpgrade(db, 99, 100);
      await runProductionOnUpgrade(db, 99, 100);
      await productionUpgradeMigrations
          .singleWhere((entry) => entry.version == 100)
          .run(db);

      final byName = await _columns(db, 'messages');
      expect(byName.keys, containsAll(_privateColumns));
      expect(byName['private_media_policy_version']!['notnull'], 1);
      expect(byName['private_media_policy_version']!['dflt_value'], '0');
      expect(byName['private_media_mode']!['notnull'], 1);
      expect(byName['private_media_mode']!['dflt_value'], "'ordinary'");
      expect(byName['private_media_duration_seconds']!['notnull'], 0);
      expect(byName['private_media_state']!['notnull'], 1);
      expect(byName['private_media_state']!['dflt_value'], "'none'");
      for (final nullable in _privateColumns.skip(4)) {
        expect(byName[nullable]!['notnull'], 0, reason: nullable);
        expect(byName[nullable]!['dflt_value'], isNull, reason: nullable);
      }
      expect(await _indexColumns(db, 'idx_messages_private_media_expiry'), [
        'private_media_expires_at_ms',
      ]);

      final direct = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['shared-parent'],
      )).single;
      expect(direct['is_forwarded'], 1);
      expect(direct['private_media_policy_version'], 0);
      expect(direct['private_media_mode'], 'ordinary');
      expect(direct['private_media_duration_seconds'], isNull);
      expect(direct['private_media_state'], 'none');
      for (final column in _privateColumns.skip(4)) {
        expect(direct[column], isNull, reason: column);
      }

      final group = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['shared-parent'],
      )).single;
      expect(group['is_forwarded'], 1);
      expect(group['key_generation'], 3);
      expect(
        (await _columns(db, 'group_messages')).keys.toList(),
        groupColumnsBefore,
      );
      expect(
        (await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='group_messages'",
        )).single['sql'],
        groupSchemaBefore,
      );

      final media = await db.query('media_attachments', orderBy: 'id');
      expect(media, hasLength(3));
      expect(media.map((row) => row['owner_lane']).toSet(), {
        'direct',
        'group',
        'unresolved',
      });
      expect(media.every((row) => row['is_bookmarked'] == 1), isTrue);
      expect(
        media.every((row) => row['last_playback_position_ms'] == 321),
        isTrue,
      );
      expect(await db.query('group_media_deletion_journal'), hasLength(1));

      await db.insert(
        'messages',
        _directMessage(
          'private-valid',
          extra: const {
            'private_media_policy_version': 1,
            'private_media_mode': 'disappearing',
            'private_media_duration_seconds': 3600,
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_expires_at_ms': 3601000,
            'private_media_revealed_at_ms': 2000,
            'private_media_terminal_at_ms': 3000,
            'private_media_clock_high_water_ms': 4000,
          },
        ),
      );
      final private = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['private-valid'],
      )).single;
      expect(private['private_media_mode'], 'disappearing');
      expect(private['private_media_state'], 'available');
      expect(private['private_media_expires_at_ms'], 3601000);

      for (final invalid in <String, Object?>{
        'private_media_policy_version': -1,
        'private_media_mode': 'future_mode',
        'private_media_duration_seconds': 60,
        'private_media_state': 'future_state',
        'private_media_received_at_ms': -1,
        'private_media_expires_at_ms': -1,
        'private_media_revealed_at_ms': -1,
        'private_media_terminal_at_ms': -1,
        'private_media_clock_high_water_ms': -1,
      }.entries) {
        await expectLater(
          db.update(
            'messages',
            {invalid.key: invalid.value},
            where: 'id = ?',
            whereArgs: ['private-valid'],
          ),
          throwsA(anything),
          reason: '${invalid.key} must enforce its v100 CHECK',
        );
      }
    },
  );

  test('fresh v100 create exposes exact defaults checks and index', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await runProductionOnCreate(db, 100);

    final columns = await _columns(db, 'messages');
    expect(columns.keys, containsAll(_privateColumns));
    expect(await _indexColumns(db, 'idx_messages_private_media_expiry'), [
      'private_media_expires_at_ms',
    ]);
    await db.insert('messages', _directMessage('fresh-default'));
    final row = (await db.query('messages')).single;
    expect(row['private_media_policy_version'], 0);
    expect(row['private_media_mode'], 'ordinary');
    expect(row['private_media_duration_seconds'], isNull);
    expect(row['private_media_state'], 'none');
    final groupColumns = await _columns(db, 'group_messages');
    expect(groupColumns, isNot(contains('media_policy_version')));
    expect(
      productionCreateMigrations.any((entry) => entry.version == 101),
      isTrue,
    );
    expect(
      productionUpgradeMigrations.any((entry) => entry.version == 101),
      isTrue,
    );
  });
}
