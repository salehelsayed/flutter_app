import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

// Task 12b: the SQL reply reservation is the duplicate guard, the pacer and
// the bounded queue. Every case runs against the real production schema.

final _peer = TestEd25519Identity.fromSeedByte(0x71);
final _other = TestEd25519Identity.fromSeedByte(0x72);
final _self = TestEd25519Identity.fromSeedByte(0x73);
final _t0 = DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch;
const _second = 1000;
const _hour = 3600 * 1000;

Future<Database> _open(String path) => databaseFactoryFfiNoIsolate.openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: currentIdentityDatabaseVersion,
    singleInstance: false,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
  ),
);

Future<void> _addContact(Database db, TestEd25519Identity id) =>
    dbUpsertContact(
      db,
      ContactModel(
        peerId: id.peerId,
        publicKey: id.publicKey,
        rendezvous: '/dns4/relay/tcp/443',
        username: 'peer',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ).toMap(),
    );

var _ids = 0;
String _uuid() {
  final n = (_ids++).toRadixString(16).padLeft(12, '0');
  return '00000000-0000-4000-8000-$n';
}

ContactRepairClaim _claim({
  TestEd25519Identity? peer,
  String? requestId,
  String digest = 'digest-1',
  int? signedAtMs,
  int? wallNowMs,
  int revision = 1,
  String? authority,
}) {
  final id = peer ?? _peer;
  return ContactRepairClaim(
    peerId: id.peerId,
    requestId: requestId ?? _uuid(),
    requestDigest: digest,
    signedAtMs: signedAtMs ?? _t0,
    authorityFingerprint:
        authority ?? ed25519AuthorityFingerprint(id.publicKey),
    localAuthorityFingerprint: ed25519AuthorityFingerprint(_self.publicKey),
    relationshipRevision: revision,
    wallNowMs: wallNowMs ?? _t0,
  );
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqlContactRepairRepository repo;

  setUp(() async {
    db = await _open(inMemoryDatabasePath);
    repo = SqlContactRepairRepository(db);
    await _addContact(db, _peer);
  });

  tearDown(() => db.close());

  test('one reservation per signed request ID; same digest is a duplicate '
      'with the same reply ID; a different digest is a conflict', () async {
    final first = await repo.claimReply(_claim(requestId: _uuid()));
    expect(first.status, ContactRepairClaimStatus.reserved);
    final requestId =
        (await db.query('contact_repair_requests')).single['request_id']!
            as String;

    final again = await repo.claimReply(_claim(requestId: requestId));
    expect(again.status, ContactRepairClaimStatus.duplicate);
    expect(again.replyId, first.replyId);

    final forged = await repo.claimReply(
      _claim(requestId: requestId, digest: 'digest-2'),
    );
    expect(forged.status, ContactRepairClaimStatus.conflict);
    final rows = await db.query('contact_repair_requests');
    expect(rows, hasLength(1));
    expect(rows.single['request_digest'], 'digest-1');
    expect(rows.single['reply_id'], first.replyId);
    expect(
      await repo.lookupRequestDigest(
        peerId: _peer.peerId,
        requestId: requestId,
      ),
      'digest-1',
    );
  });

  test('two independent repository handles racing the same request reserve '
      'exactly one reply', () async {
    final dir = await Directory.systemTemp.createTemp('repair_race');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/account.db';
    final h1 = await _open(path);
    final h2 = await _open(path);
    addTearDown(() async {
      await h1.close();
      await h2.close();
    });
    await _addContact(h1, _peer);
    final requestId = _uuid();
    final r1 = SqlContactRepairRepository(h1);
    final r2 = SqlContactRepairRepository(h2);
    // Both handles start their claim in the same turn. SQLite serialises the
    // writers: the loser either sees the committed row (duplicate) or gets a
    // retryable SQLITE_BUSY, and its retry is then a duplicate. It never
    // reserves a second reply.
    Future<ContactRepairClaimOutcome?> attempt(SqlContactRepairRepository r) =>
        r
            .claimReply(_claim(requestId: requestId))
            .then<ContactRepairClaimOutcome?>(
              (o) => o,
              onError: (Object e) {
                expect(e.toString(), contains('database is locked'));
                return null;
              },
            );
    final raced = await Future.wait([attempt(r1), attempt(r2)]);
    final settled = <ContactRepairClaimOutcome>[
      for (var i = 0; i < 2; i++)
        raced[i] ??
            await (i == 0 ? r1 : r2).claimReply(_claim(requestId: requestId)),
    ];
    expect(
      settled.where((o) => o.status == ContactRepairClaimStatus.reserved),
      hasLength(1),
    );
    expect(
      settled.where((o) => o.status == ContactRepairClaimStatus.duplicate),
      hasLength(1),
    );
    expect(settled[0].replyId, settled[1].replyId);
    expect(await h1.query('contact_repair_requests'), hasLength(1));
  });

  test(
    'distinct requests in one window are paced 5 s apart, durable across '
    'reopen, and bounded at 4 pending per peer with a retryable overflow',
    () async {
      final dir = await Directory.systemTemp.createTemp('repair_pace');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/account.db';
      var handle = await _open(path);
      await _addContact(handle, _peer);
      var store = SqlContactRepairRepository(handle);
      final due = <int?>[];
      for (var i = 0; i < 3; i++) {
        due.add((await store.claimReply(_claim())).dueAtMs);
      }
      expect(due, [_t0, _t0 + 5 * _second, _t0 + 10 * _second]);

      await handle.close();
      handle = await _open(path);
      store = SqlContactRepairRepository(handle);
      final fourth = await store.claimReply(_claim());
      expect(fourth.status, ContactRepairClaimStatus.reserved);
      expect(fourth.dueAtMs, _t0 + 15 * _second);

      final fifth = await store.claimReply(_claim());
      expect(fifth.status, ContactRepairClaimStatus.overflow);
      expect(fifth.queued, isFalse);
      expect(await handle.query('contact_repair_requests'), hasLength(4));
      await handle.close();
    },
  );

  test('stored authority, relationship revision, block and deletion are '
      'rechecked inside the reservation', () async {
    expect(
      (await repo.claimReply(_claim(revision: 2))).status,
      ContactRepairClaimStatus.refused,
    );
    expect(
      (await repo.claimReply(
        _claim(authority: ed25519AuthorityFingerprint(_other.publicKey)),
      )).status,
      ContactRepairClaimStatus.refused,
    );
    expect(
      (await repo.claimReply(_claim(peer: _other))).status,
      ContactRepairClaimStatus.refused,
    );
    await dbBlockContact(db, _peer.peerId);
    expect(
      (await repo.claimReply(_claim())).status,
      ContactRepairClaimStatus.refused,
    );
    expect(await db.query('contact_repair_requests'), isEmpty);
  });

  test(
    'freshness uses the persisted effective clock: stale, future, and a '
    'wall clock moved back behind the high-water all stay ineligible',
    () async {
      expect(
        (await repo.claimReply(_claim(signedAtMs: _t0 - 25 * _hour))).status,
        ContactRepairClaimStatus.stale,
      );
      expect(
        (await repo.claimReply(
          _claim(signedAtMs: _t0 + 6 * 60 * _second),
        )).status,
        ContactRepairClaimStatus.stale,
      );
      // Clock forward: the high-water moves to t0 + 23 h.
      expect(
        (await repo.claimReply(
          _claim(signedAtMs: _t0 + 23 * _hour, wallNowMs: _t0 + 23 * _hour),
        )).status,
        ContactRepairClaimStatus.reserved,
      );
      // Wall clock back to t0: the anomaly defers automatic work.
      expect(
        (await repo.claimReply(_claim(signedAtMs: _t0, wallNowMs: _t0))).status,
        ContactRepairClaimStatus.clockAnomaly,
      );
      // Wall clock back only slightly (inside the anomaly tolerance): a request
      // 24 h 2 min older than the high-water is stale even though it is only
      // 23 h 58 min older than the wall clock.
      expect(
        (await repo.claimReply(
          _claim(
            signedAtMs: _t0 - 62 * 60 * _second,
            wallNowMs: _t0 + 23 * _hour - 4 * 60 * _second,
          ),
        )).status,
        ContactRepairClaimStatus.stale,
      );
    },
  );

  test('young guards are never evicted to make room: at the per-peer guard '
      'cap a new request is deferred', () async {
    final batch = db.batch();
    for (var i = 0; i < ContactRepairLimits.maxGuardsPerPeer; i++) {
      batch.insert('contact_repair_requests', <String, Object?>{
        'peer_id': _peer.peerId,
        'request_id': 'guard-$i',
        'request_digest': 'd',
        'signed_at_ms': _t0,
        'guard_until_ms': _t0 + 25 * _hour,
        'authority_fingerprint': 'a',
        'local_authority_fingerprint': 'l',
        'relationship_revision': 1,
        'state': 'completed',
        'reply_id': 'reply-$i',
        'due_at_ms': _t0,
        'created_at_ms': _t0,
        'updated_at_ms': _t0,
      });
    }
    await batch.commit(noResult: true);
    final outcome = await repo.claimReply(_claim(wallNowMs: _t0 + _hour));
    expect(outcome.status, ContactRepairClaimStatus.overflow);
    expect(await repo.collectGarbage(wallNowMs: _t0 + _hour), 0);
    final count = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM contact_repair_requests',
    )).single['n'];
    expect(count, ContactRepairLimits.maxGuardsPerPeer);

    // After the guards can no longer be fresh they are collected in batches.
    final collected = await repo.collectGarbage(wallNowMs: _t0 + 26 * _hour);
    expect(collected, ContactRepairLimits.garbageBatch);
  });

  group('worker claims', () {
    test('respect the global transmit cap and due times, consume one attempt '
        'per take, and exhaust after the attempt budget', () async {
      await _addContact(db, _other);
      await repo.claimReply(_claim());
      await repo.claimReply(_claim());
      await repo.claimReply(_claim(peer: _other));

      final first = await repo.takeDueJobs(
        claimToken: 'w1',
        wallNowMs: _t0,
        limit: 10,
      );
      // Two due now (one per peer); the second for _peer is paced to t0+5s.
      expect(first, hasLength(2));
      expect(first.every((j) => j.attempts == 1), isTrue);
      expect(
        await repo.takeDueJobs(
          claimToken: 'w1',
          wallNowMs: _t0 + _hour,
          limit: 10,
        ),
        isEmpty,
        reason: 'transmit cap is 2',
      );

      var job = first.firstWhere((j) => j.peerId == _peer.peerId);
      for (
        var attempt = 1;
        attempt < ContactRepairLimits.maxAttempts;
        attempt++
      ) {
        expect(
          await repo.releaseForRetry(job: job, claimToken: 'w1', dueAtMs: _t0),
          isTrue,
        );
        final again = await repo.takeDueJobs(
          claimToken: 'w1',
          wallNowMs: _t0,
          limit: 1,
        );
        job = again.single;
        expect(
          job.requestId,
          first.firstWhere((j) => j.peerId == _peer.peerId).requestId,
        );
        expect(job.attempts, attempt + 1);
      }
      await repo.releaseForRetry(job: job, claimToken: 'w1', dueAtMs: _t0);
      final row = (await db.query(
        'contact_repair_requests',
        where: 'request_id = ?',
        whereArgs: [job.requestId],
      )).single;
      expect(row['state'], 'exhausted');
    });

    test(
      'a takeover fences the old owner and keeps the used attempts',
      () async {
        await repo.claimReply(_claim());
        final job = (await repo.takeDueJobs(
          claimToken: 'old',
          wallNowMs: _t0,
          limit: 1,
        )).single;
        expect(await repo.takeOverInFlight(newClaimToken: 'new'), 1);

        expect(
          await repo.commitEnvelope(
            job: job,
            claimToken: 'old',
            envelopeJson: '{}',
            grantGeneration: null,
          ),
          isFalse,
        );
        expect(await repo.stillOwns(job: job, claimToken: 'old'), isFalse);
        expect(await repo.completeJob(job: job, claimToken: 'old'), isFalse);

        final resumed = (await repo.takeDueJobs(
          claimToken: 'new',
          wallNowMs: _t0,
          limit: 1,
        )).single;
        expect(resumed.replyId, job.replyId);
        expect(resumed.attempts, 2);
      },
    );

    test('an envelope is committed once and survives a re-queue', () async {
      await repo.claimReply(_claim());
      final job = (await repo.takeDueJobs(
        claimToken: 'w',
        wallNowMs: _t0,
        limit: 1,
      )).single;
      expect(
        await repo.commitEnvelope(
          job: job,
          claimToken: 'w',
          envelopeJson: '{"bytes":1}',
          grantGeneration: 7,
        ),
        isTrue,
      );
      expect(
        await repo.commitEnvelope(
          job: job,
          claimToken: 'w',
          envelopeJson: '{"bytes":2}',
          grantGeneration: 8,
        ),
        isFalse,
      );
      await repo.releaseForRetry(job: job, claimToken: 'w', dueAtMs: _t0);
      final again = (await repo.takeDueJobs(
        claimToken: 'w',
        wallNowMs: _t0,
        limit: 1,
      )).single;
      expect(again.envelopeJson, '{"bytes":1}');
      expect(again.grantGeneration, 7);
    });
  });

  test('marker support is remembered per peer', () async {
    expect(await repo.peerSupportsMarked(_peer.peerId), isFalse);
    await repo.recordPeerSupportsMarked(_peer.peerId);
    expect(await repo.peerSupportsMarked(_peer.peerId), isTrue);
    expect(await repo.peerSupportsMarked(_other.peerId), isFalse);
  });
}
