// ignore_for_file: file_names
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Documents extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Documents(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  sqfliteFfiInit();
  late Directory temporary;
  late PathProviderPlatform originalPaths;
  late String databasePath;
  Future<Database> openAt(int version, {bool interrupt = false}) =>
      databaseFactoryFfiNoIsolate.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: version,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: (db, old, target) async {
            await runProductionOnUpgrade(db, old, target);
            if (interrupt) throw StateError('synthetic interrupted upgrade');
          },
        ),
      );
  Future<List<String>> tables(Database db) async => (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND (name='posts' OR name GLOB 'post_*')",
  )).map((row) => row['name'] as String).toList();
  Future<void> seedAll(Database db) async {
    for (final table in await tables(db)) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final row = <String, Object?>{};
      for (final column in columns) {
        if (column['dflt_value'] != null) continue;
        if (column['notnull'] != 1 && column['pk'] == 0) continue;
        final type = column['type'] as String;
        row[column['name'] as String] = type.contains('INT')
            ? 1
            : type == 'BLOB'
            ? Uint8List.fromList([1, 2, 3])
            : 'old';
      }
      if (row.isNotEmpty) {
        await db.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('thought-reset-');
    databasePath = p.join(temporary.path, 'identity.sqlite');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(temporary.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    await temporary.delete(recursive: true);
  });

  test(
    'upgrade removes every Posts table row and startup removes media after a killed file sweep',
    () async {
      var db = await openAt(121);
      await seedAll(db);
      final oldTables = await tables(db);
      for (final table in oldTables) {
        expect(await db.query(table), isNotEmpty, reason: table);
      }
      final media = Directory(p.join(temporary.path, 'post_media', 'old'));
      await media.create(recursive: true);
      await File(p.join(media.path, 'private.jpg')).writeAsBytes([1, 2, 3]);
      await db.close();
      db = await openAt(122);
      for (final table in oldTables) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      // Simulate process death after the committed migration, before file cleanup.
      await db.close();
      expect(await media.exists(), isTrue);
      db = await openAt(122);
      final files = MediaFileManager();
      await files.deleteOrphanPostMedia(await dbLoadAllPostIds(db));
      expect(await media.exists(), isFalse);
      await files.deleteOrphanPostMedia(await dbLoadAllPostIds(db));
      expect(await media.exists(), isFalse);
      await db.close();
    },
  );

  test(
    'interrupted database upgrade rolls every deletion back and safely retries',
    () async {
      var db = await openAt(121);
      await seedAll(db);
      final names = await tables(db);
      await db.close();
      await expectLater(openAt(122, interrupt: true), throwsStateError);
      db = await openAt(121);
      for (final table in names) {
        expect(await db.query(table), isNotEmpty, reason: table);
      }
      await db.close();
      db = await openAt(122);
      for (final table in names) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      await db.close();
    },
  );

  test(
    'orphan cleanup preserves live thought folders and ignores symlinks',
    () async {
      final live = Directory(p.join(temporary.path, 'post_media', 'live'));
      final orphan = Directory(p.join(temporary.path, 'post_media', 'orphan'));
      final outside = Directory(p.join(temporary.path, 'outside'));
      for (final directory in [live, orphan, outside]) {
        await directory.create(recursive: true);
      }
      await Link(
        p.join(temporary.path, 'post_media', 'external'),
      ).create(outside.path);
      await MediaFileManager().deleteOrphanPostMedia({'live'});
      expect(await live.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
      expect(await outside.exists(), isTrue);
    },
  );
}
