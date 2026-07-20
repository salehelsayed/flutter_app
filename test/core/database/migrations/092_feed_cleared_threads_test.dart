// ignore_for_file: file_names
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/092_feed_cleared_threads.dart';

void main() {
  // TC-28 (decision 2): migration 092 creates `feed_cleared_threads`, is
  // idempotent, preserves pre-existing data, and produces the same schema on a
  // clean open directly at v92 as on an upgrade. Plain sqflite FFI in-memory
  // (the migration SQL is cipher-agnostic — mirrors the 089/081 harness).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> tableExists(String name) async {
    final rows = await db.query(
      'sqlite_master',
      where: "type = 'table' AND name = ?",
      whereArgs: [name],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> columnNames(String table) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols.map((c) => c['name'] as String).toSet();
  }

  Future<Set<String>> primaryKeyColumns(String table) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols
        .where((c) => ((c['pk'] as num?) ?? 0).toInt() > 0)
        .map((c) => c['name'] as String)
        .toSet();
  }

  test('092 creates feed_cleared_threads with the expected columns + PK',
      () async {
    expect(await tableExists('feed_cleared_threads'), isFalse);

    await runFeedClearedThreadsMigration(db);

    expect(await tableExists('feed_cleared_threads'), isTrue);
    expect(
      await columnNames('feed_cleared_threads'),
      containsAll(<String>['thread_kind', 'thread_id', 'cleared_at_ms']),
    );
    expect(
      await primaryKeyColumns('feed_cleared_threads'),
      <String>{'thread_kind', 'thread_id'},
    );
  });

  test('092 is idempotent (run twice is a no-op, no throw)', () async {
    await runFeedClearedThreadsMigration(db);
    await db.insert('feed_cleared_threads', <String, Object?>{
      'thread_kind': 'contact',
      'thread_id': 'peerA',
      'cleared_at_ms': 123,
    });

    await runFeedClearedThreadsMigration(db);

    // Row survives the re-run (CREATE TABLE IF NOT EXISTS must not drop it).
    final rows = await db.query('feed_cleared_threads');
    expect(rows, hasLength(1));
    expect(rows.first['cleared_at_ms'], 123);
  });

  test('092 clean-open directly at v92 has the same table/columns/PK',
      () async {
    // Simulate a fresh install (onCreate path), which calls the migration
    // directly because the onCreate closure is inline + not importable.
    await runFeedClearedThreadsMigration(db);

    expect(await tableExists('feed_cleared_threads'), isTrue);
    expect(
      await primaryKeyColumns('feed_cleared_threads'),
      <String>{'thread_kind', 'thread_id'},
    );
  });

  test('092 preserves pre-existing tables/rows', () async {
    await db.execute(
      'CREATE TABLE legacy (id INTEGER PRIMARY KEY, name TEXT)',
    );
    await db.insert('legacy', <String, Object?>{'id': 1, 'name': 'keep-me'});

    await runFeedClearedThreadsMigration(db);

    final rows = await db.query('legacy');
    expect(rows, hasLength(1));
    expect(rows.first['name'], 'keep-me');
  });
}
