// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/109_direct_reaction_inbox_custody_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _t0 = '2026-08-07T07:00:00.000Z';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;
  late String freshPath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_reaction_custody_v109_',
    );
    upgradePath = '${tempDirectory.path}/upgrade.db';
    freshPath = '${tempDirectory.path}/fresh.db';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'TC-343-01 v109 installs immutable direct-reaction custody and refuses downgrade without mutation',
    () async {
      var upgraded = await databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 108,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await upgraded.insert('messages', <String, Object?>{
        'id': 'historical-message',
        'contact_peer_id': 'peer-history',
        'sender_peer_id': 'peer-self',
        'text': 'historical direct target',
        'timestamp': _t0,
        'status': 'sent',
        'is_incoming': 0,
        'created_at': _t0,
      });
      await upgraded.insert('message_reactions', <String, Object?>{
        'id': 'historical-reaction',
        'message_id': 'historical-message',
        'emoji': '👍',
        'sender_peer_id': 'peer-self',
        'timestamp': _t0,
        'created_at': _t0,
        'removed_at': null,
      });
      await upgraded.close();

      upgraded = await databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      addTearDown(() async {
        if (upgraded.isOpen) await upgraded.close();
      });

      expect(currentIdentityDatabaseVersion, 110);
      expect(await _userVersion(upgraded), 110);
      expect(await upgraded.query('message_reactions'), hasLength(1));
      expect(
        await upgraded.query('direct_reaction_inbox_custody_outbox'),
        isEmpty,
        reason: 'historical reactions have no reconstructible exact envelope',
      );
      await _expectExactSchema(upgraded);

      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 109);
        expect(entries, hasLength(1));
        expect(entries.single.name, '109_direct_reaction_inbox_custody_outbox');
        expect(
          entries.single.run,
          same(runDirectReactionInboxCustodyOutboxMigration),
        );
        expect(registry[registry.indexOf(entries.single) + 1].version, 110);
        expect(registry.last.version, 110);
        final v108 = registry.indexWhere((entry) => entry.version == 108);
        expect(registry.indexOf(entries.single), v108 + 1);
      }

      await runDirectReactionInboxCustodyOutboxMigration(upgraded);
      await runDirectReactionInboxCustodyOutboxMigration(upgraded);
      await _expectExactSchema(upgraded);
      expect(await upgraded.query('message_reactions'), hasLength(1));
      expect(
        await upgraded.query('direct_reaction_inbox_custody_outbox'),
        isEmpty,
      );

      final fresh = await databaseFactoryFfi.openDatabase(
        freshPath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      await _expectExactSchema(fresh);
      expect(await _userVersion(fresh), 110);
      expect(
        await fresh.query('direct_reaction_inbox_custody_outbox'),
        isEmpty,
      );
      await fresh.close();

      await upgraded.insert(
        'direct_reaction_inbox_custody_outbox',
        _custodyRow(eventId: 'downgrade-event'),
      );
      final snapshotBeforeDowngrade = await upgraded.query(
        'direct_reaction_inbox_custody_outbox',
      );
      await upgraded.close();

      await expectLater(
        databaseFactoryFfi.openDatabase(
          upgradePath,
          options: OpenDatabaseOptions(
            version: 108,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: onDatabaseVersionChangeError,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      upgraded = await databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      expect(await _userVersion(upgraded), 110);
      expect(
        await upgraded.query('direct_reaction_inbox_custody_outbox'),
        snapshotBeforeDowngrade,
      );
    },
  );

  test(
    'TC-343-08c literal v108 inventory has no stale current-version consumer',
    () {
      final stale = <String>[];
      for (final rootName in const <String>[
        'lib',
        'test',
        'integration_test',
      ]) {
        final root = Directory('${Directory.current.path}/$rootName');
        for (final entity in root.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final relative = entity.path.substring(
            Directory.current.path.length + 1,
          );
          if (relative ==
              'test/core/database/migrations/109_direct_reaction_inbox_custody_outbox_test.dart') {
            continue;
          }
          final lines = entity.readAsLinesSync();
          for (var index = 0; index < lines.length; index++) {
            final compact = lines[index].replaceAll(RegExp(r'\s+'), ' ');
            if (compact.contains(
                  'const int currentIdentityDatabaseVersion = 108',
                ) ||
                compact.contains(
                  'expect(currentIdentityDatabaseVersion, 108)',
                ) ||
                compact.contains('expect(manifest.databaseVersion, 108)')) {
              stale.add('$relative:${index + 1}:${lines[index].trim()}');
            }
          }
        }
      }
      expect(stale, isEmpty, reason: 'stale current-version pins: $stale');
    },
  );
}

Future<void> _expectExactSchema(Database db) async {
  final columns = await db.rawQuery(
    'PRAGMA table_info(direct_reaction_inbox_custody_outbox)',
  );
  expect(columns.map((column) => column['name']).toList(), <String>[
    'recipient_peer_id',
    'event_id',
    'wire_envelope',
    'retry_count',
    'last_attempt_at',
    'last_error_code',
    'created_at',
    'updated_at',
  ]);
  expect(columns.map((column) => column['type']).toList(), <String>[
    'TEXT',
    'TEXT',
    'TEXT',
    'INTEGER',
    'TEXT',
    'TEXT',
    'TEXT',
    'TEXT',
  ]);
  expect(columns.map((column) => column['pk']).toList(), <int>[
    1,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
  expect(
    await db.rawQuery(
      'PRAGMA foreign_key_list(direct_reaction_inbox_custody_outbox)',
    ),
    isEmpty,
  );
  final tableSql =
      (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
            const <Object?>['direct_reaction_inbox_custody_outbox'],
          )).single['sql']
          as String;
  expect(tableSql, contains('retry_count >= 0'));
  for (final code in const <String>[
    'store_failed',
    'store_rejected_full',
    'store_threw',
    'local_completion_failed',
  ]) {
    expect(tableSql, contains("'$code'"));
  }
  for (final forbidden in const <String>[
    'message_id',
    'emoji',
    'preview',
    'media',
    'push_payload',
    'action TEXT',
    'target_message',
  ]) {
    expect(tableSql.toLowerCase(), isNot(contains(forbidden)));
  }
  final indexColumns = await db.rawQuery(
    'PRAGMA index_info(idx_direct_reaction_inbox_custody_outbox_fair_load)',
  );
  expect(indexColumns.map((column) => column['name']).toList(), <String>[
    'last_attempt_at',
    'created_at',
    'recipient_peer_id',
    'event_id',
  ]);
}

Map<String, Object?> _custodyRow({required String eventId}) =>
    <String, Object?>{
      'recipient_peer_id': 'recipient-peer',
      'event_id': eventId,
      'wire_envelope': '{"cipher":"exact"}',
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': _t0,
      'updated_at': _t0,
    };

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.single.values.single as num).toInt();
}
