import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/058_media_attachment_integrity_columns.dart';
import 'package:flutter_app/core/database/migrations/059_media_attachment_encryption_columns.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

  // ---------------------------------------------------------------------------
  // 156 QW-8 (cold-start-2): one-shot sentinel so the scrub does NOT re-scan the
  // encrypted media_attachments + group_keys tables on every launch.
  // ---------------------------------------------------------------------------
  test(
    'TC-14: scrub short-circuits on second launch (emits SCRUB_SKIPPED, no '
    'START/SUCCESS)',
    () async {
      await insertLegacyMediaKeyRow();
      await insertLegacyGroupKeyRow();

      final events = <String>[];
      debugSetFlowEventSink((p) => events.add(p['event'] as String));
      addTearDown(() => debugSetFlowEventSink(null));

      // First launch: real scrub runs and sets the sentinel.
      await scrubLegacyGroupSecretsToSecureStorage(
        db: db,
        secureKeyStore: secureKeyStore,
      );
      events.clear();

      // Second launch: must short-circuit.
      await scrubLegacyGroupSecretsToSecureStorage(
        db: db,
        secureKeyStore: secureKeyStore,
      );

      expect(
        events.where((e) => e == 'GROUP_SECRET_STORAGE_SCRUB_SKIPPED'),
        hasLength(1),
      );
      expect(events, isNot(contains('GROUP_SECRET_STORAGE_SCRUB_START')));
      expect(events, isNot(contains('GROUP_SECRET_STORAGE_SCRUB_SUCCESS')));
    },
  );

  test('TC-15: second scrub run performs ZERO table scans', () async {
    await insertLegacyMediaKeyRow();
    await insertLegacyGroupKeyRow();

    // First launch sets the sentinel into the (persistent) FakeSecureKeyStore.
    await scrubLegacyGroupSecretsToSecureStorage(
      db: db,
      secureKeyStore: secureKeyStore,
    );

    // Second launch through a counting proxy: the sentinel guard must return
    // before any db access (no `_tableExists`, no table scans).
    final countingDb = _CountingDb(db);
    await scrubLegacyGroupSecretsToSecureStorage(
      db: countingDb,
      secureKeyStore: secureKeyStore,
    );

    expect(countingDb.queryCount, 0);
  });
}

/// Thin [Database] proxy that counts `query(...)` calls and forwards them to the
/// real db. Any other db method would route through [noSuchMethod] (and throw) —
/// but a correctly-guarded second scrub touches the db zero times.
class _CountingDb implements Database {
  _CountingDb(this._inner);

  final Database _inner;
  int queryCount = 0;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    queryCount++;
    return _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
