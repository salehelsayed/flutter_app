/// Integration test: Full DB migration chain (v1 -> v11).
///
/// Verifies:
/// 1a. Fresh install creates all tables with correct schema
/// 1b. Step-by-step upgrade preserves seeded data
/// 1c. Idempotent migrations can be re-run safely

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
  });

  /// Helper: get table names in DB
  Future<List<String>> getTableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((r) => r['name'] as String).toList()..sort();
  }

  /// Helper: get column names for a table
  Future<List<String>> getColumnNames(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toList();
  }

  group('Full DB migration chain', () {
    test('1a. Fresh install path creates all tables with correct schema',
        () async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      // Run the full fresh-install migration chain (matching main.dart onCreate)
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
      await runMlKemKeysMigration(db);
      // Skip 004 on fresh install — 005 already has nullable + CHECK
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runAvatarVersionMigration(db);

      // Verify: 5 tables exist
      final tables = await getTableNames(db);
      expect(tables, containsAll([
        'identity',
        'contacts',
        'contact_requests',
        'messages',
        'media_attachments',
      ]));

      // Verify: identity has CHECK constraints (insert non-null private_key throws)
      expect(
        () async => await db.insert('identity', {
          'id': 99,
          'peer_id': 'test',
          'public_key': 'pk',
          'private_key': 'should_fail',
          'username': 'Test',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        }),
        throwsA(anything),
      );

      // Verify: messages has read_at, quoted_message_id columns
      final msgCols = await getColumnNames(db, 'messages');
      expect(msgCols, containsAll(['read_at', 'quoted_message_id']));

      // Verify: contacts has ml_kem_public_key, is_archived, is_blocked, avatar_version
      final contactCols = await getColumnNames(db, 'contacts');
      expect(contactCols, containsAll([
        'ml_kem_public_key',
        'is_archived',
        'is_blocked',
        'avatar_version',
      ]));

      // Verify: media_attachments has all expected columns
      final mediaCols = await getColumnNames(db, 'media_attachments');
      expect(mediaCols, containsAll([
        'id',
        'message_id',
        'mime',
        'size',
        'media_type',
        'width',
        'height',
        'duration_ms',
        'local_path',
        'download_status',
        'created_at',
      ]));

      // Verify: index exists on media_attachments
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='media_attachments'",
      );
      expect(
        indexes.map((r) => r['name'] as String),
        contains('idx_media_attachments_message'),
      );
    });

    test('1b. Step-by-step upgrade preserves seeded data', () async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      // Step 1: Run migration 001 (identity, contacts, contact_requests)
      await runIdentityTableMigration(db);

      // Seed data
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'peer-abc',
        'public_key': 'pk-abc',
        'private_key': 'sk-abc',
        'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
        'username': 'TestUser',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      await db.insert('contacts', {
        'peer_id': 'contact-1',
        'public_key': 'pk-c1',
        'rendezvous': '/rv/1',
        'username': 'ContactOne',
        'signature': 'sig-c1',
        'scanned_at': '2026-01-01T00:00:00Z',
      });
      await db.insert('contact_requests', {
        'peer_id': 'req-1',
        'public_key': 'pk-r1',
        'rendezvous': '/rv/r1',
        'username': 'Requester',
        'signature': 'sig-r1',
        'received_at': '2026-01-01T00:00:00Z',
        'status': 'pending',
      });

      // Step 2: Migration 002 -> messages table
      await runMessagesTableMigration(db);
      final tables2 = await getTableNames(db);
      expect(tables2, contains('messages'));

      // Step 3: Migration 003 -> ML-KEM columns
      await runMlKemKeysMigration(db);
      final identityCols3 = await getColumnNames(db, 'identity');
      expect(identityCols3, containsAll(['ml_kem_public_key', 'ml_kem_secret_key']));
      final contactCols3 = await getColumnNames(db, 'contacts');
      expect(contactCols3, contains('ml_kem_public_key'));

      // Step 4: Migration 004 -> nullable secrets
      await runNullifySecretColumnsMigration(db);
      // Verify private_key still has value (not yet migrated)
      final identityRow4 = await db.query('identity', where: 'id = ?', whereArgs: [1]);
      expect(identityRow4.first['private_key'], 'sk-abc');

      // Run secrets migration
      final keyStore = FakeSecureKeyStore();
      await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);

      // Verify secrets moved to secure storage
      expect(await keyStore.read('identity_private_key'), 'sk-abc');
      expect(
        await keyStore.read('identity_mnemonic12'),
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      );

      // Verify DB columns are null
      final identityRow4b = await db.query('identity', where: 'id = ?', whereArgs: [1]);
      expect(identityRow4b.first['private_key'], isNull);
      expect(identityRow4b.first['mnemonic12'], isNull);

      // Step 5: Migration 005 -> CHECK constraints
      await runSecretNullChecksMigration(db);
      // Verify CHECK constraints active (non-null private_key throws)
      expect(
        () async => await db.update(
          'identity',
          {'private_key': 'should-fail'},
          where: 'id = ?',
          whereArgs: [1],
        ),
        throwsA(anything),
      );

      // Step 6: Migration 006 -> read_at column
      await runReadAtColumnMigration(db);
      final msgCols6 = await getColumnNames(db, 'messages');
      expect(msgCols6, contains('read_at'));

      // Insert messages and verify mark-read works
      await db.insert('messages', {
        'id': 'msg-1',
        'contact_peer_id': 'contact-1',
        'sender_peer_id': 'contact-1',
        'text': 'Hello',
        'timestamp': '2026-01-01T00:00:00Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-01-01T00:00:00Z',
      });
      final msgBefore = await db.query('messages', where: 'id = ?', whereArgs: ['msg-1']);
      expect(msgBefore.first['read_at'], isNull);

      // Step 7: Migration 007 -> archive columns
      await runArchiveColumnsMigration(db);
      final contactCols7 = await getColumnNames(db, 'contacts');
      expect(contactCols7, containsAll(['is_archived', 'archived_at']));

      // Step 8: Migration 008 -> block columns
      await runBlockColumnsMigration(db);
      final contactCols8 = await getColumnNames(db, 'contacts');
      expect(contactCols8, containsAll(['is_blocked', 'blocked_at']));

      // Step 9: Migration 009 -> quoted_message_id
      await runQuotedMessageIdMigration(db);
      final msgCols9 = await getColumnNames(db, 'messages');
      expect(msgCols9, contains('quoted_message_id'));

      // Step 10: Migration 010 -> media_attachments
      await runMediaAttachmentsMigration(db);
      final tables10 = await getTableNames(db);
      expect(tables10, contains('media_attachments'));

      // Step 11: Migration 011 -> avatar_version
      await runAvatarVersionMigration(db);
      final identityCols11 = await getColumnNames(db, 'identity');
      expect(identityCols11, contains('avatar_version'));
      final contactCols11 = await getColumnNames(db, 'contacts');
      expect(contactCols11, contains('avatar_version'));

      // Final: verify seeded data is preserved
      final identity = await db.query('identity', where: 'id = ?', whereArgs: [1]);
      expect(identity.first['peer_id'], 'peer-abc');
      expect(identity.first['public_key'], 'pk-abc');
      expect(identity.first['username'], 'TestUser');
      // Secrets should be null (migrated to secure storage)
      expect(identity.first['private_key'], isNull);

      final contact = await db.query('contacts', where: 'peer_id = ?', whereArgs: ['contact-1']);
      expect(contact.first['username'], 'ContactOne');
      expect(contact.first['public_key'], 'pk-c1');

      final request = await db.query('contact_requests', where: 'peer_id = ?', whereArgs: ['req-1']);
      expect(request.first['username'], 'Requester');
      expect(request.first['status'], 'pending');
    });

    test('1c. Idempotent migrations can be re-run safely', () async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      // Run full chain first
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
      await runMlKemKeysMigration(db);
      await runNullifySecretColumnsMigration(db);

      final keyStore = FakeSecureKeyStore();
      await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runAvatarVersionMigration(db);

      // Seed data
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'peer-test',
        'public_key': 'pk-test',
        'username': 'Test',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01',
      });

      // Re-run idempotent migrations (006-011)
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runAvatarVersionMigration(db);

      // Re-run secrets migration (should be no-op)
      await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);

      // Data should be intact
      final identity = await db.query('identity', where: 'id = ?', whereArgs: [1]);
      expect(identity.first['peer_id'], 'peer-test');
    });
  });
}
