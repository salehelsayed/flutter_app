import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/059_media_attachment_encryption_columns.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

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

  test('adds media encryption columns idempotently', () async {
    await runMediaAttachmentEncryptionColumnsMigration(db);
    await runMediaAttachmentEncryptionColumnsMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
    final names = columns.map((column) => column['name']).toList();
    expect(
      names.where((name) => name == 'encryption_key_base64'),
      hasLength(1),
    );
    expect(names.where((name) => name == 'encryption_nonce'), hasLength(1));
    expect(names.where((name) => name == 'encryption_scheme'), hasLength(1));

    await db.insert('media_attachments', {
      'id': 'blob-1',
      'message_id': 'msg-1',
      'mime': 'image/jpeg',
      'size': 5,
      'media_type': 'image',
      'download_status': 'done',
      'created_at': '2026-04-30T12:00:00.000Z',
      'encryption_key_base64': 'key-1',
      'encryption_nonce': 'nonce-1',
      'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    });

    final row = (await db.query('media_attachments')).single;
    expect(row['encryption_key_base64'], 'key-1');
    expect(row['encryption_nonce'], 'nonce-1');
    expect(
      row['encryption_scheme'],
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
  });
}
