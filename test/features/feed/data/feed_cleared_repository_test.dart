import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/feed_cleared_threads_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/092_feed_cleared_threads.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository_impl.dart';

void main() {
  // TC-29 (decision 2): FeedClearedRepository markCleared/clearCleared/
  // getClearedWatermarks round-trip + survives reopen, via the closure-DI
  // db-helpers over a real (FFI) database.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  FeedClearedRepository buildRepo(
    Database db, {
    Future<void> Function(String threadKind, String threadId)? markThreadRead,
  }) {
    return FeedClearedRepositoryImpl(
      dbMarkFeedClearedThread: (kind, id, ms) =>
          dbMarkFeedClearedThread(db, kind, id, ms),
      dbClearFeedClearedThread: (kind, id) =>
          dbClearFeedClearedThread(db, kind, id),
      dbLoadFeedClearedThreads: () => dbLoadFeedClearedThreads(db),
      markThreadRead: markThreadRead,
    );
  }

  test('markCleared persists; getClearedWatermarks returns the watermark map',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runFeedClearedThreadsMigration(db);
    final repo = buildRepo(db);

    await repo.markCleared('contact', 'peerA', 1000, markRead: false);
    await repo.markCleared('group', 'groupB', 2000, markRead: true);

    final marks = await repo.getClearedWatermarks();
    expect(marks[('contact', 'peerA')], 1000);
    expect(marks[('group', 'groupB')], 2000);

    await db.close();
  });

  test('clearCleared removes a single watermark (Undo)', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runFeedClearedThreadsMigration(db);
    final repo = buildRepo(db);

    await repo.markCleared('contact', 'peerA', 1000, markRead: false);
    await repo.markCleared('contact', 'peerB', 1500, markRead: false);
    await repo.clearCleared('contact', 'peerA');

    final marks = await repo.getClearedWatermarks();
    expect(marks.containsKey(('contact', 'peerA')), isFalse);
    expect(marks[('contact', 'peerB')], 1500);

    await db.close();
  });

  test('watermarks survive close + reopen of the same database file', () async {
    final dir = await databaseFactoryFfi.getDatabasesPath();
    final path = '$dir/feed_cleared_reopen_test.db';
    await databaseFactoryFfi.deleteDatabase(path);

    var db = await databaseFactoryFfi.openDatabase(path);
    await runFeedClearedThreadsMigration(db);
    await buildRepo(db).markCleared('contact', 'peerA', 4242, markRead: false);
    await db.close();

    db = await databaseFactoryFfi.openDatabase(path);
    final marks = await buildRepo(db).getClearedWatermarks();
    expect(marks[('contact', 'peerA')], 4242);
    await db.close();

    await databaseFactoryFfi.deleteDatabase(path);
  });

  test('markCleared(markRead:true) fires the injected read-marking closure; '
      'markRead:false never does (INV-2 dismiss isolation)', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runFeedClearedThreadsMigration(db);

    final readCalls = <(String, String)>[];
    final repo = buildRepo(
      db,
      markThreadRead: (kind, id) async => readCalls.add((kind, id)),
    );

    await repo.markCleared('contact', 'peerA', 1000, markRead: false);
    expect(readCalls, isEmpty, reason: 'dismiss must not touch read-state');

    await repo.markCleared('contact', 'peerB', 2000, markRead: true);
    expect(readCalls, <(String, String)>[('contact', 'peerB')]);

    await db.close();
  });
}
