// ignore_for_file: file_names

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/110_direct_media_custody_intent.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _timestamp = '2026-08-07T12:00:00.000Z';
const _validIntent = '0123456789abcdef0123456789abcdef';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;
  late String freshPath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_media_custody_intent_v110_',
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
    'TC-345-01 DB v110 adds nullable manifest-bound media intent without backfill or downgrade',
    () async {
      var upgraded = await databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 109,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await upgraded.insert('messages', _messageRow());
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
      expect(
        (await upgraded.query(
          'messages',
        )).single['direct_media_custody_intent_id'],
        isNull,
        reason: 'historical message rows have no authored-manifest proof',
      );
      await _expectExactColumn(upgraded);
      await _expectNoIntentIndex(upgraded);

      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 110);
        expect(entries, hasLength(1));
        expect(entries.single.name, '110_direct_media_custody_intent');
        expect(entries.single.run, same(runDirectMediaCustodyIntentMigration));
        expect(registry[registry.indexOf(entries.single) + 1].version, 111);
        final v109 = registry.indexWhere((entry) => entry.version == 109);
        expect(registry.indexOf(entries.single), v109 + 1);
      }

      await upgraded.update(
        'messages',
        const <String, Object?>{'direct_media_custody_intent_id': _validIntent},
        where: 'id = ?',
        whereArgs: const <Object?>['historical-message'],
      );
      for (final invalid in <String>[
        '0123456789abcdef0123456789abcde',
        '0123456789abcdef0123456789abcdef0',
        '0123456789ABCDEF0123456789ABCDEF',
        'g123456789abcdef0123456789abcdef',
        '0123456789abcdef0123456789abcdef\u0000g',
      ]) {
        await expectLater(
          upgraded.update(
            'messages',
            <String, Object?>{'direct_media_custody_intent_id': invalid},
            where: 'id = ?',
            whereArgs: const <Object?>['historical-message'],
          ),
          throwsA(isA<DatabaseException>()),
        );
      }
      await expectLater(
        upgraded.update(
          'messages',
          <String, Object?>{
            'direct_media_custody_intent_id': Uint8List.fromList(
              '0123456789abcdef0123456789abcdef'.codeUnits,
            ),
          },
          where: 'id = ?',
          whereArgs: const <Object?>['historical-message'],
        ),
        throwsA(isA<DatabaseException>()),
        reason: '32-byte ASCII lowerhex BLOBs are not TEXT authority',
      );
      expect(
        (await upgraded.query(
          'messages',
        )).single['direct_media_custody_intent_id'],
        _validIntent,
      );

      await runDirectMediaCustodyIntentMigration(upgraded);
      await runDirectMediaCustodyIntentMigration(upgraded);
      await _expectExactColumn(upgraded);
      await _expectNoIntentIndex(upgraded);
      expect(
        (await upgraded.query(
          'messages',
        )).single['direct_media_custody_intent_id'],
        _validIntent,
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
      await _expectExactColumn(fresh);
      await _expectNoIntentIndex(fresh);
      expect(await _userVersion(fresh), 116);
      expect(await fresh.query('messages'), isEmpty);
      await fresh.close();

      final snapshotBeforeDowngrade = await upgraded.query('messages');
      await upgraded.close();
      await expectLater(
        databaseFactoryFfi.openDatabase(
          upgradePath,
          options: OpenDatabaseOptions(
            version: 109,
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
      expect(await upgraded.query('messages'), snapshotBeforeDowngrade);
    },
  );

  test('media custody intent digest is canonical and domain-separated', () {
    final canonical = computeDirectMediaCustodyIntentId(
      messageId: 'message-b',
      attachmentIds: const <String>[
        'attachment-b',
        'attachment-a',
        'attachment-a',
      ],
    );

    expect(canonical, '49011a3469010883dc26e140d8fdc703');
    expect(canonical, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(
      computeDirectMediaCustodyIntentId(
        messageId: 'message-b',
        attachmentIds: const <String>['attachment-a', 'attachment-b'],
      ),
      canonical,
    );
    expect(
      computeDirectMediaCustodyIntentId(
        messageId: 'message-c',
        attachmentIds: const <String>['attachment-a', 'attachment-b'],
      ),
      isNot(canonical),
    );
    expect(
      computeDirectMediaCustodyIntentId(
        messageId: 'message-b',
        attachmentIds: const <String>['attachment-a'],
      ),
      isNot(canonical),
    );
  });
}

Map<String, Object?> _messageRow() => const <String, Object?>{
  'id': 'historical-message',
  'contact_peer_id': 'peer-history',
  'sender_peer_id': 'peer-self',
  'text': 'historical media message',
  'timestamp': _timestamp,
  'status': 'sent',
  'is_incoming': 0,
  'created_at': _timestamp,
};

Future<void> _expectExactColumn(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final column = columns.singleWhere(
    (candidate) => candidate['name'] == 'direct_media_custody_intent_id',
  );
  expect(column['type'], 'TEXT');
  expect(column['notnull'], 0);
  expect(column['dflt_value'], isNull);
  expect(column['pk'], 0);

  final tableSql =
      (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
            const <Object?>['messages'],
          )).single['sql']
          as String;
  final compactSql = tableSql.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  expect(
    compactSql,
    contains("typeof(direct_media_custody_intent_id) = 'text'"),
  );
  expect(compactSql, contains('length(direct_media_custody_intent_id) = 32'));
  expect(
    compactSql,
    contains('length(cast(direct_media_custody_intent_id as blob)) = 32'),
  );
  expect(
    compactSql,
    contains("direct_media_custody_intent_id not glob '*[^0-9a-f]*'"),
  );
}

Future<void> _expectNoIntentIndex(Database db) async {
  final indexes = await db.rawQuery('PRAGMA index_list(messages)');
  for (final index in indexes) {
    final name = index['name'] as String;
    final columns = await db.rawQuery('PRAGMA index_info($name)');
    expect(
      columns.map((column) => column['name']),
      isNot(contains('direct_media_custody_intent_id')),
    );
  }
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.single.values.single as num).toInt();
}
