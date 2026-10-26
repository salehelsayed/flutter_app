import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/contact_request/application/contact_repair_outbox_worker.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/deterministic_contact_request_crypto.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../support/contact_repair_harness.dart';

// Task 12b, two real phones in one process: each has its own production-schema
// database, real listener, real repair store and real outbox worker; the
// network, crypto and call-wake issuer are the only fakes. A compact QR re-add
// leaves the scanner without the other side's ML-KEM key; one signed request
// earns exactly one signed reply that repairs it.

final _bus = Ed25519ContactRequestCryptoBus();
final _aId = TestEd25519Identity.fromSeedByte(0xF1);
final _bId = TestEd25519Identity.fromSeedByte(0xF2);

Future<ContactModel?> _noAvatar({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
  bool retryPendingRequest = false,
}) async => null;

final class _Phone {
  _Phone._(this.me, this.peer, this.db, this.network, this.clock)
    : contacts = databaseContactRepository(db),
      repair = SqlContactRepairRepository(db) {
    p2p = FakeP2PService(peerId: me.peerId, network: network);
    identities.seed(
      testIdentityModel(
        me,
        username: 'user',
        mlKemPublicKey: 'mlkem-${me.peerId}',
      ),
    );
    worker = ContactRepairOutboxWorker(
      repository: repair,
      p2pService: p2p,
      identityRepo: identities,
      bridge: bridge,
      contactRepo: contacts,
      resolveCallWakeHandle: (target) async =>
          issued[target] ??= grantFor(target, generation: ++mints),
      onCallWakeHandleDistributed: (_, grant) async =>
          distributedGenerations.add(grant.generation),
      nowMs: () => clock.value,
      scheduleWakeups: false,
      debugStageHook: (stage) async {
        if (stage == ContactRepairWorkerStage.claimed) {
          await holdReplies?.future;
        }
      },
    );
    listener = ContactRequestListener(
      contactRequestStream: p2p.messageStream,
      requestRepo: requests,
      contactRepo: contacts,
      bridge: bridge,
      getOwnPeerId: () => me.peerId,
      getOwnPrivateKey: () async => me.privateKey,
      getOwnPublicKey: () async => me.publicKey,
      downloadProfilePictureFn: _noAvatar,
      receivedCallWakeHandleStore: grants,
      repairRepository: repair,
      repairNowMs: () => clock.value,
      onRepairReplyQueued: () => unawaited(worker.drain()),
    );
    // The fake network has no deferred ACK: answer with the exact receipt
    // for the challenge this phone itself signed into the request.
    p2p.directReplyBuilder = (target, message, delivered) {
      final msgId = (jsonDecode(message) as Map)['msgId'];
      final sent = bridge.encrypts.lastWhere((e) => e.msgId == msgId).payload;
      final challenge = sent['cwr'];
      return SendMessageResult(
        sent: delivered,
        acked: delivered,
        reply: delivered && challenge is String
            ? jsonEncode(<String, String>{'callWakeReceipt': challenge})
            : null,
      );
    };
    requests.contactRepository = contacts;
    p2p.messageStream.listen(received.add);
    listener.start();
  }

  final received = <ChatMessage>[];

  static Future<_Phone> create(
    TestEd25519Identity me,
    TestEd25519Identity peer,
    FakeP2PNetwork network,
    _Clock clock,
  ) async => _Phone._(me, peer, await openRepairTestDatabase(), network, clock);

  final TestEd25519Identity me;
  final TestEd25519Identity peer;
  final Database db;
  final FakeP2PNetwork network;
  final _Clock clock;
  final ContactRepositoryImpl contacts;
  final SqlContactRepairRepository repair;
  final requests = InMemoryContactRequestRepository();
  final grants = InMemoryReceivedCallWakeHandleStore();
  final identities = FakeIdentityRepository();
  late final bridge = Ed25519ContactRequestBridge(_bus);
  late final FakeP2PService p2p;
  late final ContactRepairOutboxWorker worker;
  late final ContactRequestListener listener;
  final issued = <String, CallWakeHandleGrant>{};
  final distributedGenerations = <int>[];
  var mints = 0;
  Completer<void>? holdReplies;

  /// Marked requests and replies this phone encrypted.
  List<String> sentKinds() => bridge.encrypts
      .map((e) => (e.payload['cr'] as Map?)?['kind'] as String? ?? 'unmarked')
      .toList();

  Future<String?> mlKemOfPeer() async =>
      (await contacts.getContact(peer.peerId))?.mlKemPublicKey;

  /// The real QR path: parse the peer's signed compact QR (identity binding
  /// and signature), add the contact, send one marked request.
  Future<void> reAddPeerFromQr(_Phone other) async {
    final (built, qr) = await buildQRPayload(
      repo: other.identities,
      callSign: (data, privateKey) => callSignPayload(
        bridge: other.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
    );
    expect(built, BuildQRPayloadResult.success);
    final (parsed, contact) = await parseQRPayload(
      qrString: qr!,
      bridge: bridge,
      ownPeerId: me.peerId,
    );
    expect(parsed, ParseQRResult.success);
    expect(contact!.mlKemPublicKey, isNull, reason: 'compact QR');
    expect(
      await addContact(repository: contacts, contact: contact),
      AddContactResult.success,
    );
    expect(
      await sendContactRequest(
        p2pService: p2p,
        identityRepo: identities,
        bridge: bridge,
        targetPeerId: other.me.peerId,
        recipientPublicKey: contact.publicKey,
        resolveCallWakeHandle: (target) async =>
            issued[target] ??= grantFor(target, generation: ++mints),
        markAsNewRequest: true,
      ),
      SendContactRequestResult.success,
    );
  }

  Future<void> dispose() async {
    worker.dispose();
    listener.dispose();
    await db.close();
  }
}

final class _Clock {
  _Clock(this.value);
  int value;
}

CallWakeHandleGrant grantFor(String recipient, {required int generation}) {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  return CallWakeHandleGrant(
    handle: 'abcdef0123456789abcdef012345678$generation',
    recipientDevicePeerId: recipient,
    deviceKeyEpoch: 1,
    generation: generation,
    // Issued well before the frozen test clock, so a slow run cannot make
    // the grant look issued in the future.
    issuedAtMs: nowMs - const Duration(hours: 1).inMilliseconds,
    expiresAtMs: nowMs + const Duration(hours: 2).inMilliseconds,
  );
}

/// Lets queued deliveries, listeners and workers run to quiescence.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Polls [condition] until true (bounded), for asynchronous delivery chains.
Future<void> _eventually(Future<bool> Function() condition) async {
  for (var i = 0; i < 250; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(() {
    _bus
      ..register(_aId)
      ..register(_bId);
  });

  late FakeP2PNetwork network;
  late _Clock clock;
  late _Phone a;
  late _Phone b;

  setUp(() async {
    network = FakeP2PNetwork();
    clock = _Clock(DateTime.now().toUtc().millisecondsSinceEpoch);
    a = await _Phone.create(_aId, _bId, network, clock);
    b = await _Phone.create(_bId, _aId, network, clock);
    await a.contacts.addContact(
      contactFor(_bId, mlKem: 'mlkem-${_bId.peerId}'),
    );
    await b.contacts.addContact(
      contactFor(_aId, mlKem: 'mlkem-${_aId.peerId}'),
    );
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('B deletes and re-adds A from A\'s compact QR twice; each time one '
      'signed request earns one reply that repairs B', () async {
    for (var round = 1; round <= 2; round++) {
      await b.contacts.deleteContact(_aId.peerId);
      await b.reAddPeerFromQr(a);
      expect(await b.mlKemOfPeer(), isNull);
      await _eventually(() async => await b.mlKemOfPeer() != null);
      await _settle();

      expect(
        await b.mlKemOfPeer(),
        'mlkem-${_aId.peerId}',
        reason: 'round $round: A\'s reply installed its ML-KEM key in B',
      );
      expect(
        (await b.grants.readForIssuer(_aId.peerId))!.recipientDevicePeerId,
        _bId.peerId,
        reason: 'round $round: A\'s exact grant landed in B',
      );
      final aClaims = await a.db.query('contact_repair_requests');
      expect(aClaims, hasLength(round));
      expect(aClaims.map((r) => r['state']).toSet(), {'completed'});
      expect(await b.db.query('contact_repair_requests'), isEmpty);
      expect(a.sentKinds(), List.filled(round, 'repair_reply'));
      expect(b.sentKinds(), List.filled(round, 'new_request'));
      expect(a.bridge.encrypts.last.recipientPublicKey, _bId.publicKey);

      // Pacing: the next genuine request is at least 5 s later.
      clock.value += const Duration(seconds: 6).inMilliseconds;
    }
    // Identical account and ML-KEM keys did not suppress the second repair,
    // and A reused one grant generation for both replies.
    expect(a.mints, 1);
    expect(a.distributedGenerations, [1, 1]);
  });

  test('crossed simultaneous requests: one reply each, both ACKed before any '
      'reply is sent, and no reply to a reply', () async {
    a.holdReplies = Completer<void>();
    b.holdReplies = Completer<void>();
    await Future.wait([
      sendContactRequest(
        p2pService: a.p2p,
        identityRepo: a.identities,
        bridge: a.bridge,
        targetPeerId: _bId.peerId,
        recipientPublicKey: _bId.publicKey,
        markAsNewRequest: true,
      ),
      sendContactRequest(
        p2pService: b.p2p,
        identityRepo: b.identities,
        bridge: b.bridge,
        targetPeerId: _aId.peerId,
        recipientPublicKey: _aId.publicKey,
        markAsNewRequest: true,
      ),
    ]);
    await _settle();
    // Both inbound requests are durably reserved while both outbound replies
    // are still held: the ACK path never waits for the reciprocal send.
    expect(await a.db.query('contact_repair_requests'), hasLength(1));
    expect(await b.db.query('contact_repair_requests'), hasLength(1));
    expect(a.sentKinds(), ['new_request']);
    expect(b.sentKinds(), ['new_request']);

    a.holdReplies!.complete();
    b.holdReplies!.complete();
    await _eventually(
      () async => a.sentKinds().length == 2 && b.sentKinds().length == 2,
    );
    await _settle();

    expect(a.sentKinds(), ['new_request', 'repair_reply']);
    expect(b.sentKinds(), ['new_request', 'repair_reply']);
    for (final phone in [a, b]) {
      final rows = await phone.db.query('contact_repair_requests');
      expect(rows, hasLength(1), reason: 'no third round');
      expect(rows.single['state'], 'completed');
    }
  });

  test('an archived requester side still repairs and stays archived', () async {
    await a.contacts.archiveContact(_bId.peerId);
    await b.contacts.deleteContact(_aId.peerId);
    await b.reAddPeerFromQr(a);
    await _eventually(() async => await b.mlKemOfPeer() != null);
    expect(await b.mlKemOfPeer(), 'mlkem-${_aId.peerId}');
    expect((await a.contacts.getContact(_bId.peerId))!.isArchived, isTrue);
  });

  test('A blocked B: B\'s re-add request gets no reply and A stores nothing '
      'from it', () async {
    await a.contacts.blockContact(_bId.peerId);
    await b.contacts.deleteContact(_aId.peerId);
    await b.reAddPeerFromQr(a);
    await _settle();
    expect(await b.mlKemOfPeer(), isNull);
    expect(await a.db.query('contact_repair_requests'), isEmpty);
    expect(await a.grants.readForIssuer(_bId.peerId), isNull);
    expect(a.sentKinds(), isEmpty);
  });

  test(
    'A deleted B: B\'s marked request reaches A\'s manual dialog only',
    () async {
      final dialogs = <String>[];
      a.listener.requestStream.listen((r) => dialogs.add(r.peerId));
      await a.contacts.deleteContact(_bId.peerId);
      await b.contacts.deleteContact(_aId.peerId);
      await b.reAddPeerFromQr(a);
      await _settle();
      expect(dialogs, [_bId.peerId]);
      expect(await a.contacts.getContact(_bId.peerId), isNull);
      expect(a.sentKinds(), isEmpty);
      expect(await b.mlKemOfPeer(), isNull);
    },
  );

  test(
    'the duplicate inbox copy of a delivered request earns no second reply',
    () async {
      await b.contacts.deleteContact(_aId.peerId);
      await b.reAddPeerFromQr(a);
      await _settle();
      final request = b.bridge.encrypts.last;
      // Replay the same envelope through A's inbox path (a fresh listener with
      // an empty replay cache, as after a restart).
      final restarted = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: a.requests,
        contactRepo: a.contacts,
        bridge: a.bridge,
        getOwnPeerId: () => _aId.peerId,
        getOwnPrivateKey: () async => _aId.privateKey,
        repairRepository: a.repair,
        repairNowMs: () => clock.value,
        onRepairReplyQueued: () => unawaited(a.worker.drain()),
      );
      addTearDown(restarted.dispose);
      final envelope = a.received.singleWhere(
        (m) => (jsonDecode(m.content) as Map)['msgId'] == request.msgId,
      );
      await restarted.processIncomingMessage(envelope);
      await _settle();
      expect(await a.db.query('contact_repair_requests'), hasLength(1));
      expect(a.sentKinds(), ['repair_reply']);
    },
  );
}
