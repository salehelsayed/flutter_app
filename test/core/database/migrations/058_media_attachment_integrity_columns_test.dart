import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/058_media_attachment_integrity_columns.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runMediaAttachmentsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('adds content and thumbnail hash columns idempotently', () async {
    await runMediaAttachmentIntegrityColumnsMigration(db);
    await runMediaAttachmentIntegrityColumnsMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
    final names = columns.map((column) => column['name']).toList();
    expect(names.where((name) => name == 'content_hash'), hasLength(1));
    expect(names.where((name) => name == 'thumbnail_hash'), hasLength(1));

    await db.insert('media_attachments', {
      'id': 'blob-1',
      'message_id': 'msg-1',
      'mime': 'image/jpeg',
      'size': 5,
      'media_type': 'image',
      'download_status': 'done',
      'created_at': '2026-04-30T12:00:00.000Z',
      'content_hash':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'thumbnail_hash':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    });

    final row = (await db.query('media_attachments')).single;
    expect(
      row['content_hash'],
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(
      row['thumbnail_hash'],
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
  });
}
