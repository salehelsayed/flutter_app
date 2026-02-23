import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMlKemKeysMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runAvatarVersionMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeContactRow({
    String peerId = 'peer-001',
    String publicKey = 'pk-base64',
    String rendezvous = '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
    String username = 'Alice',
    String signature = 'sig-base64',
    String scannedAt = '2026-01-01T00:00:00.000Z',
    String? avatarPath,
    String? avatarVersion,
    String? mlKemPublicKey,
    int isArchived = 0,
    String? archivedAt,
    int isBlocked = 0,
    String? blockedAt,
  }) {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'scanned_at': scannedAt,
      'avatar_path': avatarPath,
      'avatar_version': avatarVersion,
      'ml_kem_public_key': mlKemPublicKey,
      'is_archived': isArchived,
      'archived_at': archivedAt,
      'is_blocked': isBlocked,
      'blocked_at': blockedAt,
    };
  }

  group('dbLoadAllContacts', () {
    test('returns empty list when no contacts', () async {
      final results = await dbLoadAllContacts(db);
      expect(results, isEmpty);
    });

    test('returns all contacts ordered by scanned_at DESC', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-oldest',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ));
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-newest',
        scannedAt: '2026-03-01T00:00:00.000Z',
      ));
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-middle',
        scannedAt: '2026-02-01T00:00:00.000Z',
      ));

      final results = await dbLoadAllContacts(db);
      expect(results.length, 3);
      expect(results[0]['peer_id'], 'peer-newest');
      expect(results[1]['peer_id'], 'peer-middle');
      expect(results[2]['peer_id'], 'peer-oldest');
    });
  });

  group('dbLoadContact', () {
    test('returns null for non-existent peerId', () async {
      final result = await dbLoadContact(db, 'nonexistent-peer');
      expect(result, isNull);
    });

    test('returns contact when exists', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-alice',
        username: 'Alice',
      ));

      final result = await dbLoadContact(db, 'peer-alice');
      expect(result, isNotNull);
      expect(result!['username'], 'Alice');
    });
  });

  group('dbUpsertContact', () {
    test('inserts new contact', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-new'));

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-new']);
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer-new');
    });

    test('upserts on conflict', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-upsert',
        username: 'OriginalName',
      ));
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-upsert',
        username: 'UpdatedName',
      ));

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-upsert']);
      expect(rows.length, 1);
      expect(rows[0]['username'], 'UpdatedName');
    });
  });

  group('dbDeleteContact', () {
    test('deletes existing contact', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-delete'));

      await dbDeleteContact(db, 'peer-delete');

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-delete']);
      expect(rows, isEmpty);
    });

    test('no error for non-existent peerId', () async {
      // Should not throw
      await dbDeleteContact(db, 'nonexistent-peer');
    });
  });

  group('dbGetContactCount', () {
    test('returns 0 when empty', () async {
      final count = await dbGetContactCount(db);
      expect(count, 0);
    });

    test('returns correct count', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-a'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-b'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-c'));

      final count = await dbGetContactCount(db);
      expect(count, 3);
    });
  });

  group('dbArchiveContact', () {
    test('sets is_archived to 1 and archived_at to non-null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-archive'));

      await dbArchiveContact(db, 'peer-archive');

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-archive']);
      expect(rows[0]['is_archived'], 1);
      expect(rows[0]['archived_at'], isNotNull);
    });
  });

  group('dbUnarchiveContact', () {
    test('sets is_archived to 0 and archived_at to null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-unarchive'));
      await dbArchiveContact(db, 'peer-unarchive');

      await dbUnarchiveContact(db, 'peer-unarchive');

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-unarchive']);
      expect(rows[0]['is_archived'], 0);
      expect(rows[0]['archived_at'], isNull);
    });
  });

  group('dbLoadActiveContacts', () {
    test('returns only non-archived contacts', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-active'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-archived'));
      await dbArchiveContact(db, 'peer-archived');

      final results = await dbLoadActiveContacts(db);
      expect(results.length, 1);
      expect(results[0]['peer_id'], 'peer-active');
    });

    test('ordered by scanned_at DESC', () async {
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-older',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ));
      await dbUpsertContact(db, makeContactRow(
        peerId: 'peer-newer',
        scannedAt: '2026-02-01T00:00:00.000Z',
      ));

      final results = await dbLoadActiveContacts(db);
      expect(results.length, 2);
      expect(results[0]['peer_id'], 'peer-newer');
      expect(results[1]['peer_id'], 'peer-older');
    });
  });

  group('dbLoadArchivedContacts', () {
    test('returns only archived contacts', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-active'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-archived'));
      await dbArchiveContact(db, 'peer-archived');

      final results = await dbLoadArchivedContacts(db);
      expect(results.length, 1);
      expect(results[0]['peer_id'], 'peer-archived');
    });

    test('ordered by archived_at DESC', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-first-archived'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-second-archived'));
      await dbArchiveContact(db, 'peer-first-archived');
      // Small delay to ensure different archived_at timestamps
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await dbArchiveContact(db, 'peer-second-archived');

      final results = await dbLoadArchivedContacts(db);
      expect(results.length, 2);
      expect(results[0]['peer_id'], 'peer-second-archived');
      expect(results[1]['peer_id'], 'peer-first-archived');
    });
  });

  group('dbBlockContact', () {
    test('sets is_blocked to 1 and blocked_at to non-null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-block'));

      await dbBlockContact(db, 'peer-block');

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-block']);
      expect(rows[0]['is_blocked'], 1);
      expect(rows[0]['blocked_at'], isNotNull);
    });
  });

  group('dbUnblockContact', () {
    test('sets is_blocked to 0 and blocked_at to null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-unblock'));
      await dbBlockContact(db, 'peer-unblock');

      await dbUnblockContact(db, 'peer-unblock');

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-unblock']);
      expect(rows[0]['is_blocked'], 0);
      expect(rows[0]['blocked_at'], isNull);
    });
  });

  group('dbContactExists', () {
    test('returns false for non-existent', () async {
      final exists = await dbContactExists(db, 'nonexistent-peer');
      expect(exists, isFalse);
    });

    test('returns true for existing', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-exists'));

      final exists = await dbContactExists(db, 'peer-exists');
      expect(exists, isTrue);
    });
  });
}
