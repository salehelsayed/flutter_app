import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';

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
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeRequestRow({
    String peerId = 'peer-req-001',
    String publicKey = 'pk-base64',
    String rendezvous = '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
    String username = 'Bob',
    String signature = 'sig-base64',
    String receivedAt = '2026-01-01T00:00:00.000Z',
    String status = 'pending',
    String? mlKemPublicKey,
  }) {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'received_at': receivedAt,
      'status': status,
      'ml_kem_public_key': mlKemPublicKey,
    };
  }

  group('dbLoadPendingRequests', () {
    test('returns empty list when no requests', () async {
      final results = await dbLoadPendingRequests(db);
      expect(results, isEmpty);
    });

    test('returns only pending requests', () async {
      await dbUpsertRequest(
        db,
        makeRequestRow(peerId: 'peer-pending', status: 'pending'),
      );
      await dbUpsertRequest(
        db,
        makeRequestRow(peerId: 'peer-accepted', status: 'accepted'),
      );

      final results = await dbLoadPendingRequests(db);
      expect(results.length, 1);
      expect(results[0]['peer_id'], 'peer-pending');
    });

    test('ordered by received_at DESC', () async {
      await dbUpsertRequest(
        db,
        makeRequestRow(
          peerId: 'peer-old',
          receivedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      await dbUpsertRequest(
        db,
        makeRequestRow(
          peerId: 'peer-new',
          receivedAt: '2026-01-02T00:00:00.000Z',
        ),
      );
      await dbUpsertRequest(
        db,
        makeRequestRow(
          peerId: 'peer-mid',
          receivedAt: '2026-01-01T12:00:00.000Z',
        ),
      );

      final results = await dbLoadPendingRequests(db);
      expect(results.length, 3);
      expect(results[0]['peer_id'], 'peer-new');
      expect(results[1]['peer_id'], 'peer-mid');
      expect(results[2]['peer_id'], 'peer-old');
    });
  });

  group('dbLoadRequest', () {
    test('returns null for non-existent peerId', () async {
      final result = await dbLoadRequest(db, 'non-existent');
      expect(result, isNull);
    });

    test('returns request when exists', () async {
      await dbUpsertRequest(db, makeRequestRow(peerId: 'peer-exists'));

      final result = await dbLoadRequest(db, 'peer-exists');
      expect(result, isNotNull);
      expect(result!['peer_id'], 'peer-exists');
      expect(result['username'], 'Bob');
    });
  });

  group('dbUpsertRequest', () {
    test('inserts new request', () async {
      await dbUpsertRequest(db, makeRequestRow());

      final rows = await db.query('contact_requests');
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer-req-001');
      expect(rows[0]['username'], 'Bob');
    });

    test('upserts on conflict', () async {
      await dbUpsertRequest(
        db,
        makeRequestRow(username: 'OriginalName'),
      );
      await dbUpsertRequest(
        db,
        makeRequestRow(username: 'UpdatedName'),
      );

      final rows = await db.query('contact_requests');
      expect(rows.length, 1);
      expect(rows[0]['username'], 'UpdatedName');
    });
  });

  group('dbUpdateRequestStatus', () {
    test('updates status from pending to accepted', () async {
      await dbUpsertRequest(db, makeRequestRow(status: 'pending'));

      await dbUpdateRequestStatus(db, 'peer-req-001', 'accepted');

      final result = await dbLoadRequest(db, 'peer-req-001');
      expect(result, isNotNull);
      expect(result!['status'], 'accepted');
    });

    test('updates status from pending to declined', () async {
      await dbUpsertRequest(db, makeRequestRow(status: 'pending'));

      await dbUpdateRequestStatus(db, 'peer-req-001', 'declined');

      final result = await dbLoadRequest(db, 'peer-req-001');
      expect(result, isNotNull);
      expect(result!['status'], 'declined');
    });
  });

  group('dbDeleteRequest', () {
    test('deletes existing request', () async {
      await dbUpsertRequest(db, makeRequestRow());

      await dbDeleteRequest(db, 'peer-req-001');

      final result = await dbLoadRequest(db, 'peer-req-001');
      expect(result, isNull);
    });

    test('no error for non-existent', () async {
      // Should complete without throwing
      await dbDeleteRequest(db, 'non-existent');
    });
  });

  group('dbRequestExists', () {
    test('returns false for non-existent', () async {
      final exists = await dbRequestExists(db, 'non-existent');
      expect(exists, isFalse);
    });

    test('returns true for existing', () async {
      await dbUpsertRequest(db, makeRequestRow(peerId: 'peer-exists'));

      final exists = await dbRequestExists(db, 'peer-exists');
      expect(exists, isTrue);
    });
  });
}
