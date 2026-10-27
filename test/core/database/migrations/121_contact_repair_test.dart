// ignore_for_file: file_names

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Task 12b: new deletions and declines are remembered by the schema itself,
// so every deletion path (single delete, atomic purge) records them, and a
// routine REPLACE re-announce never looks like a re-add.

Map<String, Object?> _contact(String peerId, {String key = 'key'}) => {
  'peer_id': peerId,
  'public_key': key,
  'rendezvous': '/dns4/relay',
  'username': 'u',
  'signature': 's',
  'scanned_at': '2026-01-01T00:00:00.000Z',
};

Future<Map<String, Object?>?> _consent(Database db, String peerId) async {
  final rows = await db.query(
    'contact_relationship_consent',
    columns: ['state', 'revision'],
    where: 'peer_id = ?',
    whereArgs: [peerId],
  );
  return rows.isEmpty ? null : rows.single;
}

Future<Database> _openAt(int version) =>
    databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onCreate: (db, v) => runProductionOnCreate(db, v),
        onUpgrade: runProductionOnUpgrade,
      ),
    );

void main() {
  sqfliteFfiInit();

  test('current schema version is 124', () {
    expect(currentIdentityDatabaseVersion, 124);
  });

  group('consent triggers', () {
    late Database db;
    setUp(() async => db = await _openAt(currentIdentityDatabaseVersion));
    tearDown(() => db.close());

    test('add, REPLACE re-announce, delete, re-add', () async {
      await dbUpsertContact(db, _contact('peer-p1-0000000'));
      expect(await _consent(db, 'peer-p1-0000000'), {
        'state': 'active',
        'revision': 1,
      });

      await dbUpsertContact(db, {
        ..._contact('peer-p1-0000000'),
        'ml_kem_public_key': 'k2',
      });
      expect(await _consent(db, 'peer-p1-0000000'), {
        'state': 'active',
        'revision': 1,
      });

      await dbDeleteContact(db, 'peer-p1-0000000');
      expect(await _consent(db, 'peer-p1-0000000'), {
        'state': 'withdrawn',
        'revision': 2,
      });

      await dbUpsertContact(db, _contact('peer-p1-0000000'));
      expect(await _consent(db, 'peer-p1-0000000'), {
        'state': 'active',
        'revision': 3,
      });
    });

    test('the atomic conversation purge records the deletion', () async {
      await dbUpsertContact(db, _contact('peer-p2-0000000'));
      await dbPurgeDirectContactConversationAndContact(db, 'peer-p2-0000000');
      expect(await _consent(db, 'peer-p2-0000000'), {
        'state': 'withdrawn',
        'revision': 2,
      });
    });

    test('a decline is remembered only when no contact exists', () async {
      await dbUpsertRequest(db, {
        'peer_id': 'peer-p3-0000000',
        'public_key': 'k',
        'rendezvous': 'r',
        'username': 'u',
        'signature': 's',
        'received_at': '2026-01-01T00:00:00.000Z',
        'status': 'pending',
      });
      await dbUpdateRequestStatus(db, 'peer-p3-0000000', 'declined');
      expect(await _consent(db, 'peer-p3-0000000'), {
        'state': 'declined',
        'revision': 1,
      });

      // A later pending upsert (REPLACE) does not erase the decline.
      await dbUpsertRequest(db, {
        'peer_id': 'peer-p3-0000000',
        'public_key': 'k',
        'rendezvous': 'r',
        'username': 'u',
        'signature': 's',
        'received_at': '2026-01-02T00:00:00.000Z',
        'status': 'pending',
      });
      expect(await _consent(db, 'peer-p3-0000000'), {
        'state': 'declined',
        'revision': 1,
      });

      // Explicit accept (contact insert) restores the relationship.
      await dbUpsertContact(db, _contact('peer-p3-0000000'));
      expect(await _consent(db, 'peer-p3-0000000'), {
        'state': 'active',
        'revision': 2,
      });
    });

    test('block and delete cancel queued repair replies', () async {
      await dbUpsertContact(db, _contact('peer-p4-0000000'));
      await dbUpsertContact(db, _contact('peer-p5-0000000'));
      for (final peer in ['peer-p4-0000000', 'peer-p5-0000000']) {
        await db.insert('contact_repair_requests', {
          'peer_id': peer,
          'request_id': 'r-$peer',
          'request_digest': 'd',
          'signed_at_ms': 1,
          'guard_until_ms': 2,
          'authority_fingerprint': 'a',
          'local_authority_fingerprint': 'l',
          'relationship_revision': 1,
          'state': 'ready',
          'reply_id': 'reply-$peer',
          'due_at_ms': 0,
          'created_at_ms': 0,
          'updated_at_ms': 0,
        });
      }
      await dbBlockContact(db, 'peer-p4-0000000');
      await dbDeleteContact(db, 'peer-p5-0000000');
      final states = {
        for (final row in await db.query('contact_repair_requests'))
          row['peer_id']: row['state'],
      };
      expect(states, {
        'peer-p4-0000000': 'cancelled',
        'peer-p5-0000000': 'cancelled',
      });
    });
  });

  test('upgrade from v120 backfills existing contacts as active revision 1 '
      'and invents no history for unknown peers', () async {
    final path =
        '${(await databaseFactoryFfiNoIsolate.getDatabasesPath())}/'
        'repair_121_upgrade_${DateTime.now().microsecondsSinceEpoch}.db';
    final v120 = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 120,
        onCreate: (db, v) => runProductionOnCreate(db, v),
      ),
    );
    await v120.insert('contacts', _contact('old-peer-0000000'));
    await v120.close();
    final upgraded = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 121,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    addTearDown(() async {
      await upgraded.close();
      await databaseFactoryFfiNoIsolate.deleteDatabase(path);
    });
    expect(await _consent(upgraded, 'old-peer-0000000'), {
      'state': 'active',
      'revision': 1,
    });
    expect(await _consent(upgraded, 'never-seen-0000000'), isNull);
    expect(await upgraded.query('contact_repair_requests'), isEmpty);
  });
}
