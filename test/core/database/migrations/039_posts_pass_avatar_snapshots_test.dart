import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/039_posts_pass_avatar_snapshots.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsPassAlongMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates post_pass_avatar_snapshots table', () async {
    await runPostsPassAvatarSnapshotsMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='post_pass_avatar_snapshots'",
    );
    expect(tables, hasLength(1));

    final columns = await db.rawQuery(
      'PRAGMA table_info(post_pass_avatar_snapshots)',
    );
    final columnNames = columns.map((col) => col['name'] as String).toSet();
    expect(
      columnNames,
      containsAll(['post_id', 'author_peer_id', 'avatar_blob', 'created_at']),
    );
  });

  test('round-trips avatar BLOB through save and load helpers', () async {
    await runPostsPassAvatarSnapshotsMigration(db);

    final fakeAvatar = Uint8List.fromList(
      List<int>.generate(128, (i) => i % 256),
    );

    await dbSavePassAvatarSnapshot(
      db,
      'post-1',
      'peer-solz',
      fakeAvatar,
      '2026-03-17T10:00:00.000Z',
    );

    final loaded = await dbLoadPassAvatarSnapshot(db, 'post-1');
    expect(loaded, isNotNull);
    expect(Uint8List.fromList(loaded!), fakeAvatar);
  });

  test('returns null when no avatar snapshot exists', () async {
    await runPostsPassAvatarSnapshotsMigration(db);

    final loaded = await dbLoadPassAvatarSnapshot(db, 'no-such-post');
    expect(loaded, isNull);
  });

  test(
    'INSERT OR IGNORE preserves the first avatar for the same post_id',
    () async {
      await runPostsPassAvatarSnapshotsMigration(db);

      final firstAvatar = Uint8List.fromList([1, 2, 3, 4]);
      final secondAvatar = Uint8List.fromList([5, 6, 7, 8]);

      await dbSavePassAvatarSnapshot(
        db,
        'post-1',
        'peer-solz',
        firstAvatar,
        '2026-03-17T10:00:00.000Z',
      );
      await dbSavePassAvatarSnapshot(
        db,
        'post-1',
        'peer-solz',
        secondAvatar,
        '2026-03-17T11:00:00.000Z',
      );

      final loaded = await dbLoadPassAvatarSnapshot(db, 'post-1');
      expect(Uint8List.fromList(loaded!), firstAvatar);
    },
  );

  test('batch loads avatar snapshots for multiple posts', () async {
    await runPostsPassAvatarSnapshotsMigration(db);

    final avatar1 = Uint8List.fromList([10, 20, 30]);
    final avatar2 = Uint8List.fromList([40, 50, 60]);

    await dbSavePassAvatarSnapshot(
      db,
      'post-1',
      'peer-solz',
      avatar1,
      '2026-03-17T10:00:00.000Z',
    );
    await dbSavePassAvatarSnapshot(
      db,
      'post-2',
      'peer-dana',
      avatar2,
      '2026-03-17T10:00:00.000Z',
    );

    final snapshots = await dbLoadPassAvatarSnapshotsForPosts(db, [
      'post-1',
      'post-2',
      'post-3',
    ]);

    expect(snapshots.length, 2);
    expect(Uint8List.fromList(snapshots['post-1']!), avatar1);
    expect(Uint8List.fromList(snapshots['post-2']!), avatar2);
    expect(snapshots.containsKey('post-3'), isFalse);
  });

  test('idempotent: running migration twice does not fail', () async {
    await runPostsPassAvatarSnapshotsMigration(db);
    await runPostsPassAvatarSnapshotsMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='post_pass_avatar_snapshots'",
    );
    expect(tables, hasLength(1));
  });
}
