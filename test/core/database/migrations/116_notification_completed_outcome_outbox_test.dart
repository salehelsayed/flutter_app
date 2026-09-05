// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/116_notification_completed_outcome_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _completedAt = '2026-08-15T12:00:00.000Z';
const _expiresAt = '2026-08-22T12:00:00.000Z';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('TC-369-01 v116 outcome outbox is additive bounded and empty', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'notification_completed_outcome_v116_',
    );
    final upgradePath = p.join(tempDir.path, 'upgrade.db');
    final freshPath = p.join(tempDir.path, 'fresh.db');
    Database? db;
    addTearDown(() async {
      if (db?.isOpen ?? false) await db!.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    db = await openDatabase(
      upgradePath,
      version: 115,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
    await db.insert('contacts', <String, Object?>{
      'peer_id': 'historical-peer',
      'public_key': 'historical-public',
      'rendezvous': 'historical-relay',
      'username': 'historical',
      'signature': 'historical-signature',
      'scanned_at': _completedAt,
    });
    await db.insert('messages', <String, Object?>{
      'id': 'historical-terminal-message',
      'contact_peer_id': 'historical-peer',
      'sender_peer_id': 'historical-peer',
      'text': 'already completed before v116',
      'timestamp': _completedAt,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': _completedAt,
      'notification_display_terminal_event_id': 'historical-terminal-message',
    });
    expect(
      await _tableExists(db, kNotificationCompletedOutcomeOutboxTable),
      isFalse,
    );
    await db.close();

    db = await _openCurrent(upgradePath);
    expect(currentIdentityDatabaseVersion, 118);
    expect(await _userVersion(db), 118);
    expect(
      await _tableExists(db, kNotificationCompletedOutcomeOutboxTable),
      isTrue,
    );
    expect(
      await _columnNames(db, kNotificationCompletedOutcomeOutboxTable),
      const <String>[
        'wake_correlation',
        'outcome',
        'revision',
        'retry_count',
        'last_error_code',
        'last_attempt_at',
        'next_attempt_at',
        'completed_at',
        'created_at',
        'expires_at',
      ],
    );
    expect(
      await db.query(kNotificationCompletedOutcomeOutboxTable),
      isEmpty,
      reason: 'historical terminal display facts are not outcome authority',
    );
    expect(
      (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>['historical-terminal-message'],
      )).single['notification_display_terminal_event_id'],
      'historical-terminal-message',
    );
    for (final registry in <List<ProductionMigrationEntry>>[
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      final entries = registry.where((entry) => entry.version == 116);
      expect(entries, hasLength(1));
      expect(entries.single.name, '116_notification_completed_outcome_outbox');
      expect(
        entries.single.run,
        same(runNotificationCompletedOutcomeOutboxMigration),
      );
      expect(
        registry.indexOf(entries.single),
        registry.indexWhere((entry) => entry.version == 115) + 1,
      );
      expect(
        registry.indexWhere((entry) => entry.version == 117),
        registry.indexOf(entries.single) + 1,
      );
    }

    for (final invalid in <Map<String, Object?>>[
      <String, Object?>{..._row(0), 'wake_correlation': 'A' * 64},
      <String, Object?>{..._row(0), 'outcome': 'terminal'},
      <String, Object?>{..._row(0), 'expires_at': '2026-08-21T12:00:00.000Z'},
      <String, Object?>{..._row(0), 'retry_count': 1, 'last_error_code': null},
    ]) {
      await expectLater(
        db.insert(kNotificationCompletedOutcomeOutboxTable, invalid),
        throwsA(isA<DatabaseException>()),
      );
    }

    final batch = db.batch();
    for (
      var index = 0;
      index < kNotificationCompletedOutcomeOutboxCapacity;
      index++
    ) {
      batch.insert(kNotificationCompletedOutcomeOutboxTable, _row(index));
    }
    await batch.commit(noResult: true);
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) AS count '
        'FROM $kNotificationCompletedOutcomeOutboxTable',
      )).single['count'],
      kNotificationCompletedOutcomeOutboxCapacity,
    );
    await expectLater(
      db.update(
        kNotificationCompletedOutcomeOutboxTable,
        const <String, Object?>{'outcome': 'in_chat'},
        where: 'wake_correlation = ?',
        whereArgs: <Object?>[_row(0)['wake_correlation']],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(
        kNotificationCompletedOutcomeOutboxTable,
        _row(kNotificationCompletedOutcomeOutboxCapacity),
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(kNotificationCompletedOutcomeOutboxTable, <String, Object?>{
        ..._row(kNotificationCompletedOutcomeOutboxCapacity + 1),
        'completed_at': '2036-08-15T12:00:00.000Z',
        'created_at': '2036-08-15T12:00:00.000Z',
        'expires_at': '2036-08-22T12:00:00.000Z',
      }),
      throwsA(isA<DatabaseException>()),
      reason: 'caller-controlled future timestamps cannot bypass the cap',
    );

    final snapshot = await db.query(
      kNotificationCompletedOutcomeOutboxTable,
      orderBy: 'wake_correlation',
    );
    await runNotificationCompletedOutcomeOutboxMigration(db);
    await runNotificationCompletedOutcomeOutboxMigration(db);
    expect(
      await db.query(
        kNotificationCompletedOutcomeOutboxTable,
        orderBy: 'wake_correlation',
      ),
      snapshot,
    );
    await db.close();
    await expectLater(
      openDatabase(
        upgradePath,
        version: 115,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
      throwsA(anything),
    );
    db = await _openCurrent(upgradePath);
    expect(await _userVersion(db), 118);
    expect(
      await db.query(kNotificationCompletedOutcomeOutboxTable),
      hasLength(kNotificationCompletedOutcomeOutboxCapacity),
    );
    await db.close();

    db = await _openCurrent(freshPath);
    expect(await _userVersion(db), 118);
    expect(await db.query(kNotificationCompletedOutcomeOutboxTable), isEmpty);
    expect(
      await _columnNames(db, kNotificationCompletedOutcomeOutboxTable),
      hasLength(10),
    );
  });
}

Map<String, Object?> _row(int index) => <String, Object?>{
  'wake_correlation': index.toRadixString(16).padLeft(64, '0'),
  'outcome': switch (index % 3) {
    0 => 'os_posted',
    1 => 'in_chat',
    _ => 'suppressed_policy',
  },
  'revision': 1,
  'retry_count': 0,
  'last_error_code': null,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'completed_at': _completedAt,
  'created_at': _completedAt,
  'expires_at': _expiresAt,
};

Future<Database> _openCurrent(String path) => openDatabase(
  path,
  version: currentIdentityDatabaseVersion,
  singleInstance: false,
  onCreate: runProductionOnCreate,
  onUpgrade: runProductionOnUpgrade,
  onDowngrade: onDatabaseVersionChangeError,
);

Future<int> _userVersion(Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).single.values.single as int;

Future<bool> _tableExists(Database db, String tableName) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[tableName],
    )).isNotEmpty;

Future<List<String>> _columnNames(Database db, String tableName) async =>
    (await db.rawQuery(
      'PRAGMA table_info($tableName)',
    )).map((row) => row['name'] as String).toList(growable: false);
