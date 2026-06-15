import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/038_posts_repost_media_crypto.dart';
import 'package:flutter_app/core/database/migrations/076_post_media_attachment_crypto_columns.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsRepostMediaCryptoMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> attachmentColumns() async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(post_media_attachments)',
    );
    return columns.map((column) => column['name'] as String).toList();
  }

  test(
    '076 adds nullable encryption_scheme and content_hash TEXT columns to post_media_attachments',
    () async {
      expect(await attachmentColumns(), isNot(contains('encryption_scheme')));
      expect(await attachmentColumns(), isNot(contains('content_hash')));

      await runPostMediaAttachmentCryptoColumnsMigration(db);

      expect(await attachmentColumns(), contains('encryption_scheme'));
      expect(await attachmentColumns(), contains('content_hash'));
    },
  );

  test('preserves existing rows with null scheme and hash', () async {
    await db.insert('post_media_attachments', {
      'media_id': 'legacy-media-1',
      'post_id': 'post-1',
      'blob_id': 'blob-1',
      'kind': 'image',
      'mime': 'image/jpeg',
      'size_bytes': 1024,
      'position': 0,
      'download_status': 'done',
      'created_at': '2026-06-01T10:00:00.000Z',
      'encryption_key_base64': 'legacy-key',
      'encryption_nonce': 'legacy-nonce',
      'is_encrypted': 1,
    });

    await runPostMediaAttachmentCryptoColumnsMigration(db);

    final row = (await db.query(
      'post_media_attachments',
      where: 'media_id = ?',
      whereArgs: ['legacy-media-1'],
    )).single;
    expect(row['encryption_key_base64'], 'legacy-key');
    expect(row['encryption_scheme'], isNull);
    expect(row['content_hash'], isNull);
  });

  test('is idempotent', () async {
    await runPostMediaAttachmentCryptoColumnsMigration(db);
    await runPostMediaAttachmentCryptoColumnsMigration(db);

    final schemeColumns = (await attachmentColumns())
        .where((name) => name == 'encryption_scheme')
        .toList();
    expect(schemeColumns, hasLength(1));
  });
}
