import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/contact_request/application/contact_repair_outbox_worker.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../support/contact_repair_harness.dart';

// Task 12b worker: one immutable envelope per claimed request, committed
// before the first send, re-sent byte for byte, fenced on authority,
// relationship, local identity, grant generation and ownership.

final _bus = Ed25519ContactRequestCryptoBus();
final _a = TestEd25519Identity.fromSeedByte(0xE1); // the replier
final _b = TestEd25519Identity.fromSeedByte(0xE2); // the requester
final _c = TestEd25519Identity.fromSeedByte(0xE3);
final _t0 = DateTime.now().toUtc().millisecondsSinceEpoch;

final class _Grants {
  _Grants();
  CallWakeHandleGrant? current;
  var mints = 0;
  var resolves = 0;

  Future<CallWakeHandleGrant?> resolve(String peerId) async {
    resolves++;
    if (current == null) {
      mints++;
      current = grantFor(generation: mints);
    }
    return current;
  }

  static CallWakeHandleGrant grantFor({required int generation}) =>
      CallWakeHandleGrant(
        handle: '0123456789abcdef0123456789abcde${generation % 10}',
        recipientDevicePeerId: _b.peerId,
        deviceKeyEpoch: 1,
        generation: generation,
        issuedAtMs: _t0 - 1000,
        expiresAtMs: _t0 + const Duration(hours: 2).inMilliseconds,
      );
}

final class _Replier {
  _Replier(this.db, {this.now})
    : contacts = databaseContactRepository(db),
      repo = SqlContactRepairRepository(db);

  final Database db;
  final int Function()? now;
  final ContactRepositoryImpl contacts;
  final SqlContactRepairRepository repo;
  final network = FakeP2PNetwork();
  late final p2p = FakeP2PService(peerId: _a.peerId, network: network);
  final bridge = Ed25519ContactRequestBridge(_bus);
  late final identities = FakeIdentityRepository()
    ..seed(testIdentityModel(_a, username: 'A', mlKemPublicKey: 'a-mlkem'));
  final grants = _Grants();
  final distributed = <int>[];

  ContactRepairOutboxWorker worker({
    String? token,
    Future<void> Function(ContactRepairWorkerStage)? hook,
    bool withGrants = true,
  }) => ContactRepairOutboxWorker(
    repository: repo,
    p2pService: p2p,
    identityRepo: identities,
    bridge: bridge,
    contactRepo: contacts,
    resolveCallWakeHandle: withGrants ? grants.resolve : null,
    onCallWakeHandleDistributed: (_, grant) async =>
        distributed.add(grant.generation),
    nowMs: now,
    claimToken: token,
    scheduleWakeups: false,
    debugStageHook: hook,
  );

  Future<String> claim({TestEd25519Identity? peer, String? requestId}) async {
    final id = peer ?? _b;
    final rid = requestId ?? nextControlId();
    final consent = await repo.readConsent(id.peerId);
    final outcome = await repo.claimReply(
      ContactRepairClaim(
        peerId: id.peerId,
        requestId: rid,
        requestDigest: 'digest-$rid',
        signedAtMs: _t0,
        authorityFingerprint: ed25519AuthorityFingerprint(id.publicKey),
        localAuthorityFingerprint: ed25519AuthorityFingerprint(_a.publicKey),
        relationshipRevision: consent?.revision ?? 0,
        wallNowMs: now?.call() ?? _t0,
      ),
    );
    expect(outcome.status, ContactRepairClaimStatus.reserved);
    return rid;
  }

  /// Everything delivered to [peer]'s relay inbox, oldest first.
  List<String> inbox([TestEd25519Identity? peer]) => network
      .retrieveInbox((peer ?? _b).peerId)
      .map((m) => m['message'] as String)
      .toList();

  Future<Map<String, Object?>> row(String requestId) async => (await db.query(
    'contact_repair_requests',
    where: 'request_id = ?',
    whereArgs: [requestId],
  )).single;
}

Map<String, dynamic> _openedPayload(
  Ed25519ContactRequestBridge bridge,
  String envelope,
) {
  final msgId = (jsonDecode(envelope) as Map)['msgId'];
  return bridge.encrypts.lastWhere((e) => e.msgId == msgId).payload;
}

void main() {
  setUpAll(() {
    _bus
      ..register(_a)
      ..register(_b)
      ..register(_c);
  });

  late _Replier a;
  setUp(() async {
    a = _Replier(await openRepairTestDatabase());
    await a.contacts.addContact(contactFor(_b, mlKem: 'b-mlkem'));
  });
  tearDown(() => a.db.close());

  test(
    'builds one signed repair reply to the stored key and completes',
    () async {
      final requestId = await a.claim();
      await a.worker().drain();

      final sent = a.inbox();
      expect(sent, hasLength(1));
      final row = await a.row(requestId);
      expect(row['state'], 'completed');
      final encrypt = a.bridge.encrypts.single;
      expect(encrypt.recipientPublicKey, _b.publicKey);
      final cr = encrypt.payload['cr'] as Map<String, dynamic>;
      expect(cr, {
        'v': 1,
        'kind': 'repair_reply',
        'id': row['reply_id'],
        'to': _b.peerId,
        'replyTo': requestId,
      });
      expect((jsonDecode(sent.single) as Map)['msgId'], row['reply_id']);
      expect((encrypt.payload['cwh'] as Map)['generation'], 1);
    },
  );

  test(
    'retries re-send the committed bytes and stop at the attempt budget',
    () async {
      var now = _t0;
      a = _Replier(a.db, now: () => now);
      a.network.inboxDisabled = true;
      final requestId = await a.claim();
      final worker = a.worker();
      await worker.drain();
      expect((await a.row(requestId))['state'], 'ready');
      final committed = (await a.row(requestId))['envelope_json'];

      now += const Duration(minutes: 1).inMilliseconds;
      await worker.drain();
      now += const Duration(minutes: 1).inMilliseconds;
      a.network.inboxDisabled = false;
      // The third and last attempt succeeds with the same bytes.
      await worker.drain();

      final row = await a.row(requestId);
      expect(row['state'], 'completed');
      expect(row['attempts'], ContactRepairLimits.maxAttempts);
      expect(row['envelope_json'], committed);
      expect(a.bridge.encrypts, hasLength(1));
      // Relay inbox acceptance is not the receiver's exact receipt: the grant
      // it carries stays distribution-pending.
      expect(a.distributed, isEmpty);
      final sent = a.inbox();
      expect(sent, hasLength(1));
      expect(
        sent.single,
        (jsonDecode(committed! as String) as Map)['messageJson'],
      );
    },
  );

  test(
    'a job whose attempts are all used is exhausted, never re-minted',
    () async {
      var now = _t0;
      a = _Replier(a.db, now: () => now);
      a.network.inboxDisabled = true;
      final requestId = await a.claim();
      final worker = a.worker();
      for (var i = 0; i < 5; i++) {
        await worker.drain();
        now += const Duration(minutes: 1).inMilliseconds;
      }
      expect((await a.row(requestId))['state'], 'exhausted');
      expect(a.bridge.encrypts, hasLength(1));
    },
  );

  group('crash and takeover at each boundary', () {
    for (final stage in ContactRepairWorkerStage.values) {
      test('frozen at ${stage.name}: the new owner finishes with the one '
          'stable reply, the old owner can no longer send', () async {
        final dir = await Directory.systemTemp.createTemp('repair_worker');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/account.db';
        final h1 = await openRepairTestDatabase(path);
        final h2 = await openRepairTestDatabase(path);
        addTearDown(() async {
          await h1.close();
          await h2.close();
        });
        final first = _Replier(h1);
        await first.contacts.addContact(contactFor(_b, mlKem: 'b-mlkem'));
        final requestId = await first.claim();

        final frozen = Completer<void>();
        final release = Completer<void>();
        final oldOwner = first.worker(
          token: 'old',
          hook: (s) async {
            if (s != stage) return;
            frozen.complete();
            await release.future;
          },
        );
        final oldRun = oldOwner.drain();
        await frozen.future;

        // Same process restarted: a second handle, a new owner, the same
        // network and bridge observers.
        final second = _Replier(h2);
        final newOwner = ContactRepairOutboxWorker(
          repository: second.repo,
          p2pService: first.p2p,
          identityRepo: first.identities,
          bridge: first.bridge,
          contactRepo: second.contacts,
          resolveCallWakeHandle: first.grants.resolve,
          claimToken: 'new',
          scheduleWakeups: false,
        );
        await newOwner.start();
        release.complete();
        await oldRun;

        final row = await second.row(requestId);
        expect(row['state'], 'completed');
        expect(row['attempts'], 2, reason: 'restart does not refill attempts');
        final sent = first.inbox();
        // Only the 'transmitted' freeze sent before the crash; its bytes are
        // re-sent unchanged. No other stage lets the old owner send.
        expect(
          sent,
          hasLength(stage == ContactRepairWorkerStage.transmitted ? 2 : 1),
        );
        expect(sent.toSet(), hasLength(1));
        final payload = _openedPayload(first.bridge, sent.first);
        expect((payload['cr'] as Map)['id'], row['reply_id']);
        expect(first.grants.mints, 1, reason: 'no second grant');
      });
    }
  });

  group('fencing', () {
    test(
      'a block while the reply is being built cancels it before any send',
      () async {
        final requestId = await a.claim();
        await a
            .worker(
              hook: (stage) async {
                if (stage == ContactRepairWorkerStage.built) {
                  await a.contacts.blockContact(_b.peerId);
                }
              },
            )
            .drain();
        expect(a.inbox(), isEmpty);
        expect((await a.row(requestId))['state'], 'cancelled');
      },
    );

    test('delete then re-add with the same keys: the old job stays fenced and '
        'cannot send to the new relationship', () async {
      var now = _t0;
      a = _Replier(a.db, now: () => now);
      final requestId = await a.claim();
      await a.contacts.deleteContact(_b.peerId);
      await a.contacts.addContact(contactFor(_b, mlKem: 'b-mlkem'));
      await a.worker().drain();
      expect(a.inbox(), isEmpty);
      expect((await a.row(requestId))['state'], 'cancelled');

      // A genuine new request after the re-add repairs again (after pacing).
      final again = await a.claim();
      now += ContactRepairLimits.replyPacing.inMilliseconds;
      await a.worker().drain();
      expect(a.inbox(), hasLength(1));
      expect((await a.row(again))['state'], 'completed');
    });

    test('a stored key replaced before send cancels the job', () async {
      final requestId = await a.claim();
      await a
          .worker(
            hook: (stage) async {
              if (stage == ContactRepairWorkerStage.committed) {
                await a.contacts.addContact(
                  contactFor(_b, publicKey: _c.publicKey, mlKem: 'b-mlkem'),
                );
              }
            },
          )
          .drain();
      expect(a.inbox(), isEmpty);
      expect((await a.row(requestId))['state'], 'cancelled');
    });

    test('a rotated grant before send cancels the job; distribution stays '
        'pending and no second reply is minted', () async {
      final requestId = await a.claim();
      await a
          .worker(
            hook: (stage) async {
              if (stage == ContactRepairWorkerStage.committed) {
                a.grants.current = _Grants.grantFor(generation: 9);
              }
            },
          )
          .drain();
      expect(a.inbox(), isEmpty);
      expect((await a.row(requestId))['state'], 'cancelled');
      expect(a.distributed, isEmpty);
      expect(a.bridge.encrypts, hasLength(1));
    });
  });

  test('repeated requests reuse the current grant generation', () async {
    var now = _t0;
    a = _Replier(a.db, now: () => now);
    final first = await a.claim();
    final second = await a.claim();
    final worker = a.worker();
    await worker.drain();
    now += ContactRepairLimits.replyPacing.inMilliseconds;
    await worker.drain();
    expect((await a.row(first))['state'], 'completed');
    expect((await a.row(second))['state'], 'completed');
    expect(a.grants.mints, 1);
    expect(
      a.bridge.encrypts.map((e) => (e.payload['cwh'] as Map)['generation']),
      [1, 1],
    );
  });

  test('never more than two replies are transmitting at once', () async {
    await a.contacts.addContact(contactFor(_c, mlKem: 'c-mlkem'));
    final third = TestEd25519Identity.fromSeedByte(0xE4);
    _bus.register(third);
    await a.contacts.addContact(contactFor(third, mlKem: 't-mlkem'));
    await a.claim(peer: _b);
    await a.claim(peer: _c);
    await a.claim(peer: third);
    var inFlight = 0;
    var peak = 0;
    await a
        .worker(
          hook: (stage) async {
            if (stage == ContactRepairWorkerStage.claimed) {
              inFlight++;
              peak = inFlight > peak ? inFlight : peak;
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            if (stage == ContactRepairWorkerStage.transmitted) inFlight--;
          },
        )
        .drain();
    expect(peak, ContactRepairLimits.maxTransmitting);
    final states = (await a.db.query(
      'contact_repair_requests',
    )).map((r) => r['state']).toSet();
    expect(states, {'completed'});
  });
}
