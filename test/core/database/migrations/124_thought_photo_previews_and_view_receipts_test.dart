// ignore_for_file: file_names
import 'dart:io';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final from123 in [false, true]) {
    test(
      'v124 thought previews and view receipts ${from123 ? 'upgrade v123' : 'fresh install'}',
      () async {
        final dir = await Directory.systemTemp.createTemp('thought-124-');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/db.sqlite';
        Future<Database> open(int version) =>
            databaseFactoryFfiNoIsolate.openDatabase(
              path,
              options: OpenDatabaseOptions(
                version: version,
                singleInstance: false,
                onCreate: runProductionOnCreate,
                onUpgrade: runProductionOnUpgrade,
              ),
            );
        if (from123) {
          final old = await open(123);
          await old.insert('post_media_attachments', {
            'media_id': 'old-media',
            'post_id': 'old-post',
            'blob_id': 'old-blob',
            'kind': 'image',
            'mime': 'image/jpeg',
            'size_bytes': 10,
            'position': 0,
            'download_status': 'done',
            'created_at': '2026-10-27T10:00:00Z',
          });
          await old.close();
        }
        final db = await open(currentIdentityDatabaseVersion);
        addTearDown(db.close);
        expect(await db.getVersion(), 124);

        final mediaColumns = await db.rawQuery(
          'PRAGMA table_info(post_media_attachments)',
        );
        final preview = mediaColumns.singleWhere(
          (column) => column['name'] == 'preview_base64',
        );
        expect(preview['type'], 'TEXT');
        expect(preview['notnull'], 0);
        if (from123) {
          final kept = await db.query(
            'post_media_attachments',
            where: 'media_id = ?',
            whereArgs: ['old-media'],
          );
          expect(kept.single['blob_id'], 'old-blob');
          expect(kept.single['preview_base64'], isNull);
        }

        final receipts = await db.rawQuery(
          'PRAGMA table_info(post_view_receipts)',
        );
        expect(
          [
            for (final column in receipts)
              (column['name'], column['notnull'], column['pk']),
          ],
          [('post_id', 1, 1), ('viewer_peer_id', 1, 2), ('viewed_at', 1, 0)],
        );
        await db.insert('post_view_receipts', {
          'post_id': 'p1',
          'viewer_peer_id': 'alice',
          'viewed_at': '2026-10-27T10:00:00Z',
        });
        await db.rawInsert(
          'INSERT OR IGNORE INTO post_view_receipts '
          '(post_id, viewer_peer_id, viewed_at) VALUES (?, ?, ?)',
          ['p1', 'alice', '2026-10-27T11:00:00Z'],
        );
        expect(
          (await db.query('post_view_receipts')).single['viewed_at'],
          '2026-10-27T10:00:00Z',
        );

        final index = await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_messages_thought_quote'",
        );
        expect(
          index.single['sql'],
          contains('WHERE quoted_message_id IS NOT NULL'),
        );
      },
    );
  }
}
