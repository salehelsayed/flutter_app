// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/108_direct_inbox_custody_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _timestamp = '2026-08-06T10:00:00.000Z';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;
  late String freshPath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_inbox_custody_v108_',
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
    'TC-342-01 v108 installs immutable direct-text custody and refuses downgrade without mutation',
    () async {
      var upgraded = await databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 107,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await upgraded.insert('messages', <String, Object?>{
        'id': 'historical-message',
        'contact_peer_id': 'peer-history',
        'sender_peer_id': 'peer-self',
        'text': 'historical text has no reconstructible exact envelope',
        'timestamp': _timestamp,
        'status': 'sent',
        'is_incoming': 0,
        'created_at': _timestamp,
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

      expect(currentIdentityDatabaseVersion, 116);
      expect(await _userVersion(upgraded), 116);
      expect(await upgraded.query('messages'), hasLength(1));
      expect(
        await upgraded.query('direct_inbox_custody_outbox'),
        isEmpty,
        reason: 'v108 intentionally cannot backfill historical ciphertext',
      );
      await _expectExactSchema(upgraded);

      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 108);
        expect(entries, hasLength(1));
        expect(entries.single.name, '108_direct_inbox_custody_outbox');
        expect(entries.single.run, same(runDirectInboxCustodyOutboxMigration));
        final index108 = registry.indexOf(entries.single);
        expect(registry[index108 + 1].version, 109);
      }

      await runDirectInboxCustodyOutboxMigration(upgraded);
      await runDirectInboxCustodyOutboxMigration(upgraded);
      await _expectExactSchema(upgraded);
      expect(await upgraded.query('messages'), hasLength(1));
      expect(await upgraded.query('direct_inbox_custody_outbox'), isEmpty);

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
      expect(await fresh.query('direct_inbox_custody_outbox'), isEmpty);
      await fresh.close();

      await upgraded.insert(
        'direct_inbox_custody_outbox',
        _custodyRow(messageId: 'downgrade-sentinel'),
      );
      await upgraded.close();

      await expectLater(
        databaseFactoryFfi.openDatabase(
          upgradePath,
          options: OpenDatabaseOptions(
            version: 107,
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
      expect(await _userVersion(upgraded), 116);
      await _expectExactSchema(upgraded);
      expect(
        await upgraded.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: const <Object?>['downgrade-sentinel'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'TC-342-10c literal v107 inventory contains no stale current-version consumer',
    () {
      final repo = Directory.current.absolute;
      final historicalVersion = 100 + 7;
      final literal = RegExp(
        '(^|[^A-Za-z0-9_])'
        '${RegExp.escape(historicalVersion.toString())}'
        '(?![A-Za-z0-9_])',
      );
      String classified(String path, String line) => '$path::${line.trim()}';

      final expected = <String, int>{
        classified(
          'integration_test/direct_notification_durability_sqlcipher_proof_test.dart',
          '(entry) => entry.version == $historicalVersion,',
        ): 1,
        classified(
          'integration_test/direct_notification_durability_sqlcipher_proof_test.dart',
          '.where((entry) => entry.version == $historicalVersion)',
        ): 1,
        classified(
          'integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart',
          'version: $historicalVersion,',
        ): 2,
        classified(
          'integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart',
          'expect(await _userVersion(db), $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/helpers/canonical_notification_badge_state_db_helpers_test.dart',
          'await runProductionOnCreate(db, $historicalVersion);',
        ): 1,
        classified(
          'test/features/account_migration/application/migration_database_active_importer_test.dart',
          'manifest: manifest.copyWith(databaseVersion: $historicalVersion),',
        ): 1,
        classified(
          'test/core/database/integration/full_migration_chain_test.dart',
          'final index107 = registry.indexWhere((entry) => entry.version == $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/integration/full_migration_chain_test.dart',
          'expect(registry.where((entry) => entry.version == $historicalVersion), hasLength(1));',
        ): 1,
        classified(
          'test/core/database/migrations/100_direct_private_media_lifecycle_test.dart',
          'expect(registry.where((entry) => entry.version == $historicalVersion), hasLength(1));',
        ): 1,
        classified(
          'test/core/database/migrations/100_direct_private_media_lifecycle_test.dart',
          'final index107 = registry.indexWhere((entry) => entry.version == $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/migrations/101_group_private_media_lifecycle_test.dart',
          'expect(registry.where((entry) => entry.version == $historicalVersion), hasLength(1));',
        ): 1,
        classified(
          'test/core/database/migrations/101_group_private_media_lifecycle_test.dart',
          'final index107 = registry.indexWhere((entry) => entry.version == $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/migrations/102_groups_self_removed_at_test.dart',
          'final index107 = registry.indexWhere((entry) => entry.version == $historicalVersion);',
        ): 1,
        // 360: DB v112 appended one registry entry, so the v107 offset in the
        // v104 test shifted from `length - 5` to `length - 6`.
        // 361: DB v113 appended another entry, shifting it to `length - 7`.
        // 362: DB v114 appended another entry, shifting it to `length - 8`.
        // 365: DB v115 appended another entry, shifting it to `length - 9`.
        // 369: DB v116 appended another entry, shifting it to `length - 10`.
        // The assertion itself is unchanged; only its position moved.
        classified(
          'test/core/database/migrations/104_group_exit_diagnostics_test.dart',
          'expect(registry[registry.length - 10].version, $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/migrations/106_group_notification_display_outbox_test.dart',
          'expect(productionCreateMigrations[createIndex + 1].version, $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/migrations/107_direct_notification_durability_test.dart',
          'final entries = registry.where((entry) => entry.version == $historicalVersion);',
        ): 1,
        classified(
          'test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart',
          'version: $historicalVersion,',
        ): 2,
        classified(
          'test/features/push/application/ios_push_project_config_test.dart',
          "expect(pbxproj, isNot(contains('CURRENT_PROJECT_VERSION = $historicalVersion;')));",
        ): 1,
        classified(
          'lib/core/database/production_migration_registry.dart',
          '$historicalVersion,',
        ): 2,
        classified(
          'lib/features/settings/presentation/widgets/background_choice_control.dart',
          'color: Color.fromRGBO(255, $historicalVersion, $historicalVersion, 0.95),',
        ): 2,
      };

      final actual = <String, int>{};
      for (final rootName in const <String>[
        'lib',
        'test',
        'integration_test',
      ]) {
        final root = Directory('${repo.path}/$rootName');
        for (final entity in root.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final relativePath = entity.path
              .substring(repo.path.length + 1)
              .replaceAll('\\', '/');
          for (final line in entity.readAsLinesSync()) {
            final count = literal.allMatches(line).length;
            if (count == 0) continue;
            final key = classified(relativePath, line);
            actual[key] = (actual[key] ?? 0) + count;
          }
        }
      }

      expect(
        actual,
        expected,
        reason:
            'Every historical-version literal must match one exact classified '
            'source line and occurrence count.',
      );
    },
  );
}

Future<void> _expectExactSchema(Database db) async {
  final columns = await db.rawQuery(
    'PRAGMA table_info(direct_inbox_custody_outbox)',
  );
  expect(columns.map((row) => row['name']).toList(), <String>[
    'recipient_peer_id',
    'message_id',
    'incarnation_id',
    'wire_envelope',
    'retry_count',
    'last_attempt_at',
    'last_error_code',
    'created_at',
    'updated_at',
    'media_blob_expires_at_ms',
    'media_blob_manifest_hash',
    // 361: DB v113 appends the nullable logical-contact fanout fact.
    'contact_account_peer_id',
  ]);
  expect(
    columns.map((row) => row['name']),
    isNot(
      containsAll(<String>[
        'text',
        'title',
        'body',
        'preview',
        'media_path',
        'media_key',
        'push_copy',
      ]),
    ),
  );
  expect(columns[0]['pk'], 1);
  expect(columns[1]['pk'], 2);
  expect(
    await db.rawQuery('PRAGMA foreign_key_list(direct_inbox_custody_outbox)'),
    isEmpty,
  );

  final indexes = await db.rawQuery(
    "PRAGMA index_list('direct_inbox_custody_outbox')",
  );
  final fairIndex = indexes.singleWhere(
    (row) => row['name'] == 'idx_direct_inbox_custody_outbox_fair_load',
  );
  expect(fairIndex['unique'], 0);
  expect(
    (await db.rawQuery(
      'PRAGMA index_info(idx_direct_inbox_custody_outbox_fair_load)',
    )).map((row) => row['name']).toList(),
    <String>[
      'last_attempt_at',
      'created_at',
      'recipient_peer_id',
      'message_id',
    ],
  );
  final uniqueIndexes = indexes.where((row) => row['unique'] == 1);
  expect(
    await Future.wait(
      uniqueIndexes.map(
        (index) async => (await db.rawQuery(
          'PRAGMA index_info(${index['name']})',
        )).map((row) => row['name']).toList(),
      ),
    ),
    contains(equals(<String>['incarnation_id'])),
  );

  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'blank-peer')..['recipient_peer_id'] = '   ',
  );
  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'blank-message')..['message_id'] = '',
  );
  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'short-incarnation')..['incarnation_id'] = 'short',
  );
  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'blank-envelope')..['wire_envelope'] = '  ',
  );
  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'negative-retry')..['retry_count'] = -1,
  );
  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'bad-error')..['last_error_code'] = 'plaintext',
  );
  await _expectConstraintFailure(
    db,
    _custodyRow(messageId: 'blank-created')..['created_at'] = '',
  );
}

Future<void> _expectConstraintFailure(
  Database db,
  Map<String, Object?> row,
) async {
  await expectLater(
    db.insert('direct_inbox_custody_outbox', row),
    throwsA(isA<DatabaseException>()),
  );
}

Map<String, Object?> _custodyRow({required String messageId}) =>
    <String, Object?>{
      'recipient_peer_id': 'peer-a',
      'message_id': messageId,
      'incarnation_id': _incarnationFor(messageId),
      'wire_envelope': '{"id":"$messageId","ciphertext":"opaque"}',
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    };

String _incarnationFor(String seed) => seed.codeUnits
    .fold<int>(0, (value, unit) => value + unit)
    .toRadixString(16)
    .padLeft(32, '0')
    .substring(0, 32);

Future<int> _userVersion(Database db) async =>
    ((await db.rawQuery('PRAGMA user_version')).single.values.single as num)
        .toInt();
