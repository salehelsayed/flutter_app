// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'VC2-02 v117 adds privacy-safe call history with empty backfill',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'call_history_v117_',
      );
      final path = p.join(directory.path, 'upgrade.db');
      Database? db;
      addTearDown(() async {
        if (db?.isOpen ?? false) await db!.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      db = await openDatabase(
        path,
        version: 116,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      );
      expect(await _tableExists(db, kCallHistoryTable), isFalse);
      await db.close();

      db = await openDatabase(
        path,
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      );
      expect(currentIdentityDatabaseVersion, 117);
      expect(await _userVersion(db), 117);
      expect(await db.query(kCallHistoryTable), isEmpty);

      final columns = (await db.rawQuery(
        'PRAGMA table_info($kCallHistoryTable)',
      )).map((row) => row['name'] as String).toList();
      expect(columns, <String>[
        'call_id',
        'contact_account_peer_id',
        'direction',
        'terminal_reason',
        'status',
        'started_at',
        'connected_at',
        'ended_at',
        'transport_route_class',
        'created_at',
        'updated_at',
      ]);
      for (final forbidden in <String>[
        'sdp',
        'ice',
        'candidate',
        'credential',
        'crypto',
        'key',
        'call_handle',
        'push_token',
        'wake_handle',
      ]) {
        expect(columns.join(' '), isNot(contains(forbidden)));
      }

      final frozenStatusRow = <String, Object?>{
        'call_id': '11111111-1111-4111-8111-111111111111',
        'contact_account_peer_id': 'contact-a',
        'direction': 'outgoing',
        'terminal_reason': 'caller_cancelled',
        'status': 'cancelled',
        'started_at': '2026-08-30T12:00:00.000Z',
        'connected_at': null,
        'ended_at': '2026-08-30T12:00:05.000Z',
        'transport_route_class': null,
        'created_at': '2026-08-30T12:00:05.000Z',
        'updated_at': '2026-08-30T12:00:05.000Z',
      };
      await db.insert(kCallHistoryTable, frozenStatusRow);
      for (final invalidStatus in <String>[
        'canceled',
        'no_answer',
        'rejected',
      ]) {
        expect(
          () => db!.insert(kCallHistoryTable, <String, Object?>{
            ...frozenStatusRow,
            'call_id': switch (invalidStatus) {
              'canceled' => '22222222-2222-4222-8222-222222222222',
              'no_answer' => '33333333-3333-4333-8333-333333333333',
              _ => '44444444-4444-4444-8444-444444444444',
            },
            'status': invalidStatus,
          }),
          throwsA(isA<DatabaseException>()),
          reason: invalidStatus,
        );
      }

      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 117);
        expect(entries, hasLength(1));
        expect(entries.single.name, '117_call_history');
        expect(entries.single.run, same(runCallHistoryMigration));
        expect(registry.last, same(entries.single));
      }
    },
  );
}

Future<bool> _tableExists(Database db, String name) async => (await db.rawQuery(
  "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
  <Object?>[name],
)).isNotEmpty;

Future<int> _userVersion(Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).single.values.single as int;
