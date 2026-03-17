import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/038_posts_repost_media_crypto.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await runPostsCoreMigration(db);
        await runPostsEngagementMigration(db);
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'migration 038 adds encryption columns to post_media_attachments and is idempotent',
    () async {
      // First run.
      await runPostsRepostMediaCryptoMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(post_media_attachments)',
      );
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      expect(columnNames, contains('encryption_key_base64'));
      expect(columnNames, contains('encryption_nonce'));
      expect(columnNames, contains('is_encrypted'));

      // Second run — idempotent.
      await runPostsRepostMediaCryptoMigration(db);

      // Insert a row with crypto metadata and verify round-trip.
      await db.insert('post_media_attachments', {
        'media_id': 'media-1',
        'post_id': 'post-1',
        'blob_id': 'blob-enc-1',
        'kind': 'image',
        'mime': 'image/jpeg',
        'size_bytes': 1024,
        'position': 0,
        'download_status': 'pending',
        'created_at': '2026-03-17T00:00:00Z',
        'encryption_key_base64': 'dGVzdC1rZXk=',
        'encryption_nonce': 'dGVzdC1ub25jZQ==',
        'is_encrypted': 1,
      });

      final rows = await db.query(
        'post_media_attachments',
        where: 'media_id = ?',
        whereArgs: ['media-1'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['encryption_key_base64'], 'dGVzdC1rZXk=');
      expect(rows.first['encryption_nonce'], 'dGVzdC1ub25jZQ==');
      expect(rows.first['is_encrypted'], 1);

      // Insert a row without crypto metadata — defaults to not encrypted.
      await db.insert('post_media_attachments', {
        'media_id': 'media-2',
        'post_id': 'post-1',
        'blob_id': 'blob-plain-1',
        'kind': 'image',
        'mime': 'image/jpeg',
        'size_bytes': 512,
        'position': 1,
        'download_status': 'pending',
        'created_at': '2026-03-17T00:00:00Z',
      });

      final plainRows = await db.query(
        'post_media_attachments',
        where: 'media_id = ?',
        whereArgs: ['media-2'],
      );
      expect(plainRows.first['encryption_key_base64'], isNull);
      expect(plainRows.first['encryption_nonce'], isNull);
      expect(plainRows.first['is_encrypted'], 0);
    },
  );
}
