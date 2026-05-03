import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/058_media_attachment_integrity_columns.dart';
import 'package:flutter_app/core/database/migrations/059_media_attachment_encryption_columns.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_secure_key_store.dart';

void main() {
  late Database db;
  late FakeSecureKeyStore secureKeyStore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runMediaAttachmentsMigration(db);
    await runMediaAttachmentIntegrityColumnsMigration(db);
    await runMediaAttachmentEncryptionColumnsMigration(db);
    await runGroupMessagesTablesMigration(db);
    secureKeyStore = FakeSecureKeyStore();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertLegacyMediaKeyRow({
    String id = 'media-1',
    String key = 'legacy-media-key-base64',
  }) async {
    await db.insert('media_attachments', {
      'id': id,
      'message_id': 'message-1',
      'mime': 'image/jpeg',
      'size': 123,
      'media_type': 'image',
      'download_status': 'pending',
      'created_at': '2026-05-01T00:00:00.000Z',
      'encryption_key_base64': key,
      'encryption_nonce': 'nonce-base64',
      'encryption_scheme': 'blob_aes_256_gcm_v1',
    });
  }

  Future<void> insertLegacyGroupKeyRow({
    String groupId = 'group-1',
    int keyGeneration = 7,
    String key = 'legacy-group-key-base64',
  }) async {
    await db.insert('group_keys', {
      'group_id': groupId,
      'key_generation': keyGeneration,
      'encrypted_key': key,
      'created_at': '2026-05-01T00:00:00.000Z',
    });
  }

  test(
    'PREREQ-SECRET-STORAGE-WRAPPING plaintext media key row moves to secure storage and SQL reference form',
    () async {
      await insertLegacyMediaKeyRow();

      await scrubLegacyGroupSecretsToSecureStorage(
        db: db,
        secureKeyStore: secureKeyStore,
      );

      final row = (await db.query('media_attachments')).single;
      final rawKey = row['encryption_key_base64'] as String;
      final secureStoreKey = mediaAttachmentEncryptionKeyStoreName('media-1');

      expect(rawKey, secureStoreReferenceForKey(secureStoreKey));
      expect(rawKey, isNot('legacy-media-key-base64'));
      expect(
        await secureKeyStore.read(secureStoreKey),
        'legacy-media-key-base64',
      );
    },
  );

  test(
    'PREREQ-SECRET-STORAGE-WRAPPING plaintext group key row moves to secure storage and SQL reference form',
    () async {
      await insertLegacyGroupKeyRow();

      await scrubLegacyGroupSecretsToSecureStorage(
        db: db,
        secureKeyStore: secureKeyStore,
      );

      final row = (await db.query('group_keys')).single;
      final rawKey = row['encrypted_key'] as String;
      final secureStoreKey = groupKeyMaterialStoreName('group-1', 7);

      expect(rawKey, secureStoreReferenceForKey(secureStoreKey));
      expect(rawKey, isNot('legacy-group-key-base64'));
      expect(
        await secureKeyStore.read(secureStoreKey),
        'legacy-group-key-base64',
      );
    },
  );

  test(
    'PREREQ-SECRET-STORAGE-WRAPPING legacy scrub rerun is idempotent',
    () async {
      await insertLegacyMediaKeyRow();
      await insertLegacyGroupKeyRow();

      await scrubLegacyGroupSecretsToSecureStorage(
        db: db,
        secureKeyStore: secureKeyStore,
      );
      final mediaReference = (await db.query('media_attachments')).single;
      final groupReference = (await db.query('group_keys')).single;

      await scrubLegacyGroupSecretsToSecureStorage(
        db: db,
        secureKeyStore: secureKeyStore,
      );

      final mediaAfterRerun = (await db.query('media_attachments')).single;
      final groupAfterRerun = (await db.query('group_keys')).single;
      expect(
        mediaAfterRerun['encryption_key_base64'],
        mediaReference['encryption_key_base64'],
      );
      expect(groupAfterRerun['encrypted_key'], groupReference['encrypted_key']);
      expect(
        await secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName('media-1'),
        ),
        'legacy-media-key-base64',
      );
      expect(
        await secureKeyStore.read(groupKeyMaterialStoreName('group-1', 7)),
        'legacy-group-key-base64',
      );
    },
  );
}
