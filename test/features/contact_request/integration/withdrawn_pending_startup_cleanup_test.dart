import 'dart:async';
import 'dart:io';

import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/contact_request/data/cleanup_withdrawn_contact_requests.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

void main() {
  final withdrawn = TestEd25519Identity.fromSeedByte(0x61);
  final legitimate = TestEd25519Identity.fromSeedByte(0x62);
  final readded = TestEd25519Identity.fromSeedByte(0x63);
  final declined = TestEd25519Identity.fromSeedByte(0x64);
  final acceptedIdentity = TestEd25519Identity.fromSeedByte(0x65);
  final declinedIdentity = TestEd25519Identity.fromSeedByte(0x66);
  final local = TestEd25519Identity.fromSeedByte(0x67);
  late Directory directory;
  late Database db;

  ContactRequestModel request(
    TestEd25519Identity peer, {
    String receivedAt = '2026-01-02T00:00:00.000Z',
    ContactRequestStatus status = ContactRequestStatus.pending,
  }) => ContactRequestModel(
    peerId: peer.peerId,
    publicKey: peer.publicKey,
    rendezvous: repairRendezvous,
    username: 'Stored peer',
    signature: 'historical-signature-${peer.peerId}',
    receivedAt: receivedAt,
    status: status,
  );

  Future<void> withdraw(TestEd25519Identity peer) async {
    final contacts = databaseContactRepository(db);
    await contacts.addContact(contactFor(peer));
    await contacts.deleteContact(peer.peerId);
    final consent = await db.query(
      'contact_relationship_consent',
      where: 'peer_id = ?',
      whereArgs: [peer.peerId],
    );
    expect(consent.single['state'], 'withdrawn');
    expect(await contacts.getContact(peer.peerId), isNull);
  }

  Future<void> reopen() async {
    await db.close();
    db = await openRepairTestDatabase('${directory.path}/account.db');
  }

  Future<List<Map<String, Object?>>> rawRequest(String peerId) =>
      db.query('contact_requests', where: 'peer_id = ?', whereArgs: [peerId]);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('withdrawn-pending-');
    db = await openRepairTestDatabase('${directory.path}/account.db');
    await withdraw(withdrawn);
    // Represent a row already persisted by an older receiver. This deliberately
    // bypasses incoming-message admission, which now rejects new such traffic.
    await buildWidgetRequestRepository(db).addRequest(request(withdrawn));
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'cold pending list hides a withdrawn absent peer historical row',
    () async {
      await reopen();
      expect((await rawRequest(withdrawn.peerId)).single['status'], 'pending');
      expect(
        await buildWidgetRequestRepository(db).getPendingRequests(),
        isEmpty,
      );
    },
  );

  test(
    'cold exact lookup hides a withdrawn absent peer historical row',
    () async {
      await reopen();
      expect((await rawRequest(withdrawn.peerId)).single['status'], 'pending');
      expect(
        await buildWidgetRequestRepository(db).getRequest(withdrawn.peerId),
        isNull,
      );
    },
  );

  test(
    'cold listener attach never prompts for a withdrawn historical row',
    () async {
      // DESC ordering makes this legitimate request the final replay item. Its
      // observed event proves replay passed the stale row, without timer sleeps.
      await buildWidgetRequestRepository(
        db,
      ).addRequest(request(legitimate, receivedAt: '2026-01-01T00:00:00.000Z'));
      await reopen();
      final bus = Ed25519ContactRequestCryptoBus()..register(local);
      final listener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: buildWidgetRequestRepository(db),
        contactRepo: databaseContactRepository(db),
        bridge: Ed25519ContactRequestBridge(bus),
        getOwnPeerId: () => local.peerId,
        getOwnPrivateKey: () async => local.privateKey,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
              bool retryPendingRequest = false,
            }) async => contactFor(legitimate),
      );
      final prompts = <String>[];
      final sentinel = Completer<void>();
      final subscription = listener.requestStream.listen((event) {
        prompts.add(event.peerId);
        if (event.peerId == legitimate.peerId) sentinel.complete();
      });
      try {
        // No listener.start(): UI attachment itself initiates the cold replay.
        await sentinel.future.timeout(const Duration(seconds: 5));
        expect(prompts, [legitimate.peerId]);
        expect(
          (await rawRequest(withdrawn.peerId)).single['status'],
          'pending',
        );
      } finally {
        await subscription.cancel();
        listener.dispose();
      }
    },
  );

  test(
    'cold queries preserve legitimate, readded, declined and terminal rows',
    () async {
      final requests = buildWidgetRequestRepository(db);
      await requests.addRequest(request(legitimate));
      await withdraw(readded);
      await databaseContactRepository(db).addContact(contactFor(readded));
      await requests.addRequest(request(readded));
      await requests.addRequest(request(declined));
      await requests.updateStatus(
        declined.peerId,
        ContactRequestStatus.declined,
      );
      await requests.addRequest(request(declined));
      for (final peer in [acceptedIdentity, declinedIdentity]) {
        await withdraw(peer);
      }
      final terminal = [
        request(acceptedIdentity, status: ContactRequestStatus.accepted),
        request(declinedIdentity, status: ContactRequestStatus.declined),
      ];
      for (final row in terminal) {
        await requests.addRequest(row);
      }
      await reopen();
      final reopened = buildWidgetRequestRepository(db);
      final visible = (await reopened.getPendingRequests())
          .map((row) => row.peerId)
          .toSet();
      for (final peer in [legitimate, readded, declined]) {
        expect(visible, contains(peer.peerId));
        expect(
          (await reopened.getRequest(peer.peerId))?.status,
          ContactRequestStatus.pending,
        );
      }
      expect(
        await databaseContactRepository(db).getContact(readded.peerId),
        isNotNull,
      );
      for (final row in terminal) {
        expect((await reopened.getRequest(row.peerId))?.toMap(), row.toMap());
        expect(visible, isNot(contains(row.peerId)));
      }
    },
  );

  test(
    'cleanup retires before deletion, survives reopen and is idempotent',
    () async {
      await reopen();
      final retired = <String>[];
      Future<void> retire(String peerId, bool Function() isExpired) async {
        expect(isExpired(), isFalse);
        expect(await rawRequest(peerId), hasLength(1));
        retired.add(peerId);
      }

      expect(
        await cleanupWithdrawnContactRequests(
          db: db,
          retireNotification: retire,
          timeout: const Duration(seconds: 5),
        ),
        1,
      );
      expect(retired, [withdrawn.peerId]);
      await reopen();
      final consent = await db.query(
        'contact_relationship_consent',
        where: 'peer_id = ?',
        whereArgs: [withdrawn.peerId],
      );
      expect(consent.single['state'], 'withdrawn');
      expect(await rawRequest(withdrawn.peerId), isEmpty);
      expect(
        await cleanupWithdrawnContactRequests(
          db: db,
          retireNotification: retire,
          timeout: const Duration(seconds: 5),
        ),
        0,
      );
      expect(retired, hasLength(1));
    },
  );

  test(
    'failed notification retirement preserves row for next cleanup',
    () async {
      expect(
        await cleanupWithdrawnContactRequests(
          db: db,
          retireNotification: (_, _) async =>
              throw StateError('OS unavailable'),
          timeout: const Duration(seconds: 5),
        ),
        0,
      );
      expect(await rawRequest(withdrawn.peerId), hasLength(1));
      expect(
        await cleanupWithdrawnContactRequests(
          db: db,
          retireNotification: (_, _) async {},
          timeout: const Duration(seconds: 5),
        ),
        1,
      );
    },
  );

  test(
    'readding while notification retirement waits preserves the row',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final cleanup = cleanupWithdrawnContactRequests(
        db: db,
        retireNotification: (_, _) async {
          entered.complete();
          await release.future;
        },
        timeout: const Duration(seconds: 5),
      );
      await entered.future;
      await databaseContactRepository(db).addContact(contactFor(withdrawn));
      release.complete();
      expect(await cleanup, 0);
      expect(await rawRequest(withdrawn.peerId), hasLength(1));
      expect(
        await buildWidgetRequestRepository(db).getRequest(withdrawn.peerId),
        isNotNull,
      );
    },
  );

  test(
    'a superseding pending identity survives notification retirement',
    () async {
      final replacement = request(
        withdrawn,
        receivedAt: '2026-02-01T00:00:00.000Z',
      );
      expect(
        await cleanupWithdrawnContactRequests(
          db: db,
          retireNotification: (_, _) async {
            await buildWidgetRequestRepository(db).addRequest(replacement);
          },
          timeout: const Duration(seconds: 5),
        ),
        0,
      );
      expect((await rawRequest(withdrawn.peerId)).single, replacement.toMap());
    },
  );

  test(
    'cleanup preserves legitimate, readded, declined and terminal rows',
    () async {
      final requests = buildWidgetRequestRepository(db);
      await requests.addRequest(request(legitimate));
      await withdraw(readded);
      await databaseContactRepository(db).addContact(contactFor(readded));
      await requests.addRequest(request(readded));
      await requests.addRequest(request(declined));
      await requests.updateStatus(
        declined.peerId,
        ContactRequestStatus.declined,
      );
      await requests.addRequest(request(declined));
      await withdraw(acceptedIdentity);
      await requests.addRequest(
        request(acceptedIdentity, status: ContactRequestStatus.accepted),
      );
      await withdraw(declinedIdentity);
      await requests.addRequest(
        request(declinedIdentity, status: ContactRequestStatus.declined),
      );
      final preserved = await db.query(
        'contact_requests',
        where: 'peer_id != ?',
        whereArgs: [withdrawn.peerId],
        orderBy: 'peer_id',
      );
      final retired = <String>[];
      expect(
        await cleanupWithdrawnContactRequests(
          db: db,
          retireNotification: (peer, _) async {
            retired.add(peer);
          },
          timeout: const Duration(seconds: 5),
        ),
        1,
      );
      expect(retired, [withdrawn.peerId]);
      expect(await db.query('contact_requests', orderBy: 'peer_id'), preserved);
    },
  );

  test('slow database releases deadline and never starts late retirement', () {
    fakeAsync((async) {
      final selected = Completer<List<Map<String, Object?>>>();
      final slow = _CleanupDatabaseProbe(selected.future);
      var retirements = 0;
      int? result;
      cleanupWithdrawnContactRequests(
        db: slow,
        retireNotification: (_, _) async {
          retirements++;
        },
      ).then((value) => result = value);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 150));
      expect(result, 0);
      selected.complete([request(withdrawn).toMap()]);
      async.flushMicrotasks();
      expect(retirements, 0);
      expect(slow.transactions, 0);
    });
  });

  test(
    'slow OS timeout leaves retry row and never schedules late deletion',
    () {
      fakeAsync((async) {
        final row = request(withdrawn).toMap();
        final slow = _CleanupDatabaseProbe(Future.value([row]));
        final cancelled = Completer<void>();
        bool Function()? expired;
        int? result;
        cleanupWithdrawnContactRequests(
          db: slow,
          retireNotification: (_, isExpired) {
            expired = isExpired;
            return cancelled.future;
          },
        ).then((value) => result = value);
        async.flushMicrotasks();
        expect(expired, isNotNull);
        expect(expired!(), isFalse);
        async.elapse(const Duration(milliseconds: 150));
        expect(result, 0);
        expect(expired!(), isTrue);
        cancelled.complete();
        async.flushMicrotasks();
        expect(slow.transactions, 0);
        expect(slow.reads, 2);
      });
    },
  );
}

// Only the deadline probes replace SQLite: real-SQL tests above prove row
// retention/deletion. Controlled futures prove late native completions cannot
// schedule a write, without wall-clock timing assumptions.
class _CleanupDatabaseProbe implements Database {
  _CleanupDatabaseProbe(this.rows);
  final Future<List<Map<String, Object?>>> rows;
  int reads = 0;
  int transactions = 0;

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
    reads++;
    return rows;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    transactions++;
    throw StateError('deadline must prevent transaction scheduling');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
