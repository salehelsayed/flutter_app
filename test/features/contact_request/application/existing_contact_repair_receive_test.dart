import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/deterministic_contact_request_crypto.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../support/contact_repair_harness.dart';

// Task 12b receive side: authenticate against the STORED signing authority
// before any write, honour only the signed marker, and reserve exactly one
// durable reply per fresh signed request from an existing, unblocked contact.

final _bus = Ed25519ContactRequestCryptoBus();
final _self = TestEd25519Identity.fromSeedByte(0xD1);
final _peer = TestEd25519Identity.fromSeedByte(0xD2);
final _rogue = TestEd25519Identity.fromSeedByte(0xD3);

final class _Receiver {
  _Receiver(this.db)
    : contacts = databaseContactRepository(db),
      repair = SqlContactRepairRepository(db);

  final Database db;
  final ContactRepositoryImpl contacts;
  final SqlContactRepairRepository repair;
  final requests = InMemoryContactRequestRepository();
  final grants = InMemoryReceivedCallWakeHandleStore();
  final tokens = InMemoryReceivedWakeTokens();
  final bridge = Ed25519ContactRequestBridge(_bus);
  final facts = <ContactRequestReceiveFacts>[];
  var introCalls = 0;

  Future<HandleMessageResult> receive(
    ChatMessage message, {
    bool withIntroHook = false,
    int? nowMs,
  }) async {
    final (result, _, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requests,
      contactRepo: contacts,
      ownPeerId: _self.peerId,
      ownPrivateKey: _self.privateKey,
      receivedWakeTokenStore: tokens,
      receivedCallWakeHandleStore: grants,
      repairRepository: repair,
      ownAccountPublicKey: _self.publicKey,
      onReceiveFacts: facts.add,
      nowMs: nowMs == null ? null : () => nowMs,
      attemptSilentIntroRecovery: withIntroHook
          ? (_) async {
              introCalls++;
              return const IntroContactRequestRecoveryResult.noMatch();
            }
          : null,
    );
    return result;
  }

  Future<List<Map<String, Object?>>> claims() =>
      db.query('contact_repair_requests');

  Future<Map<String, Object?>> contactRow() async =>
      (await contacts.getContact(_peer.peerId))!.toMap();
}

Future<ChatMessage> _request({
  TestEd25519Identity? signer,
  String? claimedPeerId,
  Map<String, Object>? control,
  Object? delivered = const _Same(),
  String? msgId,
  String intent = 'new_request',
  String? mlKem,
  String? ts,
  String? outerTs,
  String? wakeToken,
  CallWakeHandleGrant? grant,
  String? from,
}) => buildRepairWire(
  bus: _bus,
  signer: signer ?? _peer,
  recipientPublicKey: _self.publicKey,
  claimedPeerId: claimedPeerId,
  signedControl: control,
  deliveredControl: delivered is _Same ? control : delivered,
  msgId: msgId,
  intent: intent,
  mlKem: mlKem,
  ts: ts,
  outerTs: outerTs,
  wakeToken: wakeToken,
  callWakeHandle: grant,
  from: from,
);

final class _Same {
  const _Same();
}

/// The in-memory grant store with its one write paused (Codex Task 20 probe).
final class _PausedReceivedGrantStore implements ReceivedCallWakeHandleStore {
  final delegate = InMemoryReceivedCallWakeHandleStore();
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
  }) async {
    entered.complete();
    await release.future;
    return delegate.storeIfStrictlyNewer(
      issuerAccountPeerId: issuerAccountPeerId,
      grant: grant,
      nowMs: nowMs,
    );
  }

  @override
  Future<CallWakeHandleGrant?> readForIssuer(String id) =>
      delegate.readForIssuer(id);

  @override
  Future<void> removeForIssuer(String id) => delegate.removeForIssuer(id);

  @override
  Future<void> clear() => delegate.clear();
}

IntroductionModel _intro() => IntroductionModel(
  id: 'intro-1',
  introducerId: 'introducer-peer-000',
  recipientId: _self.peerId,
  introducedId: _peer.peerId,
  recipientStatus: IntroductionStatus.accepted,
  introducedStatus: IntroductionStatus.pending,
  status: IntroductionOverallStatus.pending,
  createdAt: DateTime.now().toUtc().toIso8601String(),
  introducerUsername: 'N',
  recipientUsername: 'S',
  introducedUsername: 'P',
);

CallWakeHandleGrant _grant({int generation = 1}) {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  return CallWakeHandleGrant(
    handle: '0123456789abcdef0123456789abcdef',
    recipientDevicePeerId: _self.peerId,
    deviceKeyEpoch: 1,
    generation: generation,
    issuedAtMs: nowMs - 1000,
    expiresAtMs: nowMs + const Duration(hours: 1).inMilliseconds,
  );
}

void main() {
  setUpAll(() {
    _bus
      ..register(_self)
      ..register(_peer)
      ..register(_rogue);
  });

  late _Receiver a;
  setUp(() async {
    a = _Receiver(await openRepairTestDatabase());
    await a.contacts.addContact(contactFor(_peer, mlKem: 'peer-mlkem-1'));
  });
  tearDown(() => a.db.close());

  group('existing contact, fresh marked request', () {
    test('both keys already good: one durable reply is reserved and the '
        'contact row is untouched', () async {
      final before = await a.contactRow();
      final control = newRequestControl(to: _self.peerId);
      final result = await a.receive(
        await _request(control: control, mlKem: 'peer-mlkem-1'),
      );

      expect(result, HandleMessageResult.alreadyContact);
      expect(await a.contactRow(), before);
      final claims = await a.claims();
      expect(claims, hasLength(1));
      expect(claims.single['request_id'], control['id']);
      expect(claims.single['state'], 'buildable');
      expect(
        claims.single['authority_fingerprint'],
        ed25519AuthorityFingerprint(_peer.publicKey),
      );
      expect(
        a.facts.single.repairClaim!.status,
        ContactRepairClaimStatus.reserved,
      );
      expect(
        a.facts.single.repairDecision,
        ExistingContactRepairDecision.claimReply,
      );
    });

    test('an archived contact gets one reply and stays archived', () async {
      await a.contacts.archiveContact(_peer.peerId);
      await a.receive(
        await _request(control: newRequestControl(to: _self.peerId)),
      );
      expect(await a.claims(), hasLength(1));
      expect((await a.contacts.getContact(_peer.peerId))!.isArchived, isTrue);
    });

    test('a signed request whose inner time is 25 h old gets no reply even '
        'with a fresh outer time', () async {
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      final result = await a.receive(
        await _request(
          control: newRequestControl(to: _self.peerId),
          ts: old,
        ),
      );
      expect(result, HandleMessageResult.alreadyContact);
      expect(await a.claims(), isEmpty);
      expect(
        a.facts.single.repairClaim!.status,
        ContactRepairClaimStatus.stale,
      );
    });
  });

  group('stored signing authority before any write', () {
    for (final from in <String?>[null, 'unknown']) {
      test('a rogue key claiming the stored peer ID (transport sender '
          '${from ?? 'known'}) writes and reserves nothing', () async {
        final before = await a.contactRow();
        final result = await a.receive(
          await _request(
            signer: _rogue,
            claimedPeerId: _peer.peerId,
            control: newRequestControl(to: _self.peerId),
            mlKem: 'rogue-mlkem',
            wakeToken: 'rogue-token',
            grant: _grant(),
            from: from ?? _peer.peerId,
          ),
          withIntroHook: true,
        );
        expect(result, HandleMessageResult.invalidMessage);
        expect(await a.contactRow(), before);
        expect(a.tokens.tokens, isEmpty);
        expect(await a.grants.readForIssuer(_peer.peerId), isNull);
        expect(a.introCalls, 0);
        expect(await a.claims(), isEmpty);
        expect(a.bridge.encrypts, isEmpty);
      });
    }

    test('a stored key that differs from the payload key is not authority, '
        'even when the payload key binds the peer ID', () async {
      // Legacy row whose stored key is not the peer's real key.
      await a.contacts.addContact(
        contactFor(_peer, publicKey: _rogue.publicKey, mlKem: 'peer-mlkem-1'),
      );
      final before = await a.contactRow();
      final result = await a.receive(
        await _request(
          control: newRequestControl(to: _self.peerId),
          mlKem: 'new-mlkem',
          ts: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        ),
      );
      expect(result, HandleMessageResult.invalidMessage);
      expect(await a.contactRow(), before);
      expect(await a.claims(), isEmpty);
    });

    test(
      'correct key with a bad signature, a malformed marker, a wrong '
      'recipient or a mismatched outer ID: no reservation, no writes',
      () async {
        final before = await a.contactRow();
        final control = newRequestControl(to: _self.peerId);
        final cases = <ChatMessage>[
          // Signed by the rogue but naming the peer's key: bad signature.
          await buildRepairWire(
            bus: _bus,
            signer: _rogue,
            recipientPublicKey: _self.publicKey,
            claimedPeerId: _peer.peerId,
            claimedPublicKey: _peer.publicKey,
            signedControl: control,
            mlKem: 'x-mlkem',
          ),
          await _request(control: {...control, 'v': 2}, mlKem: 'x-mlkem'),
          await _request(
            control: newRequestControl(to: _rogue.peerId),
            mlKem: 'x-mlkem',
          ),
          await _request(
            control: newRequestControl(to: _self.peerId),
            msgId: nextControlId(),
            mlKem: 'x-mlkem',
          ),
        ];
        for (final message in cases) {
          expect(await a.receive(message), HandleMessageResult.invalidMessage);
        }
        expect(await a.contactRow(), before);
        expect(await a.claims(), isEmpty);
      },
    );

    test('stripping or changing the signed marker breaks the signature: no '
        'legacy fallback, no state change', () async {
      final before = await a.contactRow();
      final control = newRequestControl(to: _self.peerId);
      for (final delivered in <Object?>[
        null,
        {...control, 'kind': 'repair_reply', 'replyTo': nextControlId()},
        {...control, 'to': _rogue.peerId},
      ]) {
        final result = await a.receive(
          await _request(
            control: control,
            delivered: delivered,
            msgId: control['id'] as String,
            mlKem: 'stripped-mlkem',
            ts: DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          ),
        );
        expect(result, HandleMessageResult.invalidMessage);
      }
      expect(await a.contactRow(), before);
      expect(await a.claims(), isEmpty);
      // Real crypto negative control: the canonical bytes that would have
      // verified include the marker.
      expect(a.bridge.verifiedData, isEmpty);
    });
  });

  group('replies and unsigned intent', () {
    for (final intent in ['new_request', 'key_exchange_retry', 'whatever']) {
      test('a signed repair reply with outer intent "$intent" updates the key '
          'once and schedules nothing', () async {
        await a.contacts.addContact(contactFor(_peer));
        final result = await a.receive(
          await _request(
            control: repairReplyControl(
              to: _self.peerId,
              replyTo: nextControlId(),
            ),
            intent: intent,
            mlKem: 'peer-mlkem-2',
          ),
        );
        expect(result, HandleMessageResult.contactKeyUpdated);
        expect(
          (await a.contacts.getContact(_peer.peerId))!.mlKemPublicKey,
          'peer-mlkem-2',
        );
        expect(await a.claims(), isEmpty);
        expect(
          a.facts.single.repairDecision,
          ExistingContactRepairDecision.isReply,
        );
      });
    }

    test('an unmarked legacy request, even with key_exchange_retry intent, '
        'gets no automatic reply', () async {
      await a.receive(await _request(intent: 'key_exchange_retry'));
      expect(await a.claims(), isEmpty);
      expect(
        a.facts.single.repairDecision,
        ExistingContactRepairDecision.notMarked,
      );
    });
  });

  group('silent introduction', () {
    test('an existing contact\'s request recovered by the intro hook still '
        'reserves exactly one reply', () async {
      final (result, _, _) = await handleIncomingMessage(
        message: await _request(control: newRequestControl(to: _self.peerId)),
        bridge: a.bridge,
        requestRepo: a.requests,
        contactRepo: a.contacts,
        ownPeerId: _self.peerId,
        ownPrivateKey: _self.privateKey,
        repairRepository: a.repair,
        ownAccountPublicKey: _self.publicKey,
        onReceiveFacts: a.facts.add,
        attemptSilentIntroRecovery: (_) async =>
            IntroContactRequestRecoveryResult.recovered(introduction: _intro()),
      );
      expect(result, HandleMessageResult.silentIntroRecovered);
      expect(await a.claims(), hasLength(1));
    });

    test('a signed reply never runs the intro hook', () async {
      await a.receive(
        await _request(
          control: repairReplyControl(
            to: _self.peerId,
            replyTo: nextControlId(),
          ),
        ),
        withIntroHook: true,
      );
      expect(a.introCalls, 0);
    });
  });

  group('duplicates and conflicts', () {
    test('the same signed request twice reserves one reply', () async {
      final control = newRequestControl(to: _self.peerId);
      final message = await _request(control: control);
      await a.receive(message);
      await a.receive(message);
      expect(await a.claims(), hasLength(1));
      expect(a.facts.map((f) => f.repairClaim!.status), [
        ContactRepairClaimStatus.reserved,
        ContactRepairClaimStatus.duplicate,
      ]);
    });

    test('the same signed ID with a different signed body is rejected before '
        'any state change and the original reply is kept', () async {
      final control = newRequestControl(to: _self.peerId);
      await a.receive(await _request(control: control));
      final reply = (await a.claims()).single['reply_id'];
      final before = await a.contactRow();

      final result = await a.receive(
        await _request(
          control: control,
          mlKem: 'conflicting-mlkem',
          ts: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          outerTs: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      expect(result, HandleMessageResult.invalidMessage);
      expect(await a.contactRow(), before);
      expect((await a.claims()).single['reply_id'], reply);
    });

    test(
      'a re-encryption under a different outer message ID is rejected',
      () async {
        final control = newRequestControl(to: _self.peerId);
        await a.receive(await _request(control: control));
        final result = await a.receive(
          await _request(control: control, msgId: nextControlId()),
        );
        expect(result, HandleMessageResult.invalidMessage);
        expect(await a.claims(), hasLength(1));
      },
    );
  });

  group('consent', () {
    test('blocked: no reply and no key, token, grant or intro write', () async {
      await a.contacts.blockContact(_peer.peerId);
      final before = await a.contactRow();
      final result = await a.receive(
        await _request(
          control: newRequestControl(to: _self.peerId),
          mlKem: 'blocked-mlkem',
          wakeToken: 'blocked-token',
          grant: _grant(),
        ),
        withIntroHook: true,
      );
      expect(result, HandleMessageResult.alreadyContact);
      expect(await a.contactRow(), before);
      expect(a.tokens.tokens, isEmpty);
      expect(await a.grants.readForIssuer(_peer.peerId), isNull);
      expect(a.introCalls, 0);
      expect(await a.claims(), isEmpty);
    });

    test('deleted: a new request goes to the manual dialog with no '
        'authority writes; a late signed reply creates nothing', () async {
      await a.contacts.deleteContact(_peer.peerId);
      final result = await a.receive(
        await _request(
          control: newRequestControl(to: _self.peerId),
          wakeToken: 'withdrawn-token',
          grant: _grant(),
        ),
        withIntroHook: true,
      );
      expect(result, HandleMessageResult.contactRequest);
      expect(a.tokens.tokens, isEmpty);
      expect(await a.grants.readForIssuer(_peer.peerId), isNull);
      expect(a.introCalls, 0);
      expect(await a.claims(), isEmpty);

      final requestsBefore = await a.requests.getPendingRequests();
      final late = await a.receive(
        await _request(
          control: repairReplyControl(
            to: _self.peerId,
            replyTo: nextControlId(),
          ),
        ),
      );
      expect(late, HandleMessageResult.repairReplyIgnored);
      expect(await a.contacts.getContact(_peer.peerId), isNull);
      expect(
        await a.requests.getPendingRequests(),
        hasLength(requestsBefore.length),
      );
    });

    test(
      'declined then a new request: manual dialog, never auto-add',
      () async {
        await a.contacts.deleteContact(_peer.peerId);
        await a.db.delete('contact_relationship_consent');
        await a.db.insert('contact_requests', {
          'peer_id': _peer.peerId,
          'public_key': _peer.publicKey,
          'rendezvous': 'r',
          'username': 'u',
          'signature': 's',
          'received_at': '2026-01-01T00:00:00.000Z',
          'status': 'pending',
        });
        await a.db.update(
          'contact_requests',
          {'status': 'declined'},
          where: 'peer_id = ?',
          whereArgs: [_peer.peerId],
        );
        final result = await a.receive(
          await _request(control: newRequestControl(to: _self.peerId)),
        );
        expect(result, HandleMessageResult.contactRequest);
      },
    );

    test(
      'historical deletion with no record keeps first-contact behaviour',
      () async {
        await a.contacts.deleteContact(_peer.peerId);
        // The deletion happened before v121: no record survives.
        await a.db.delete('contact_relationship_consent');
        final result = await a.receive(
          await _request(control: newRequestControl(to: _self.peerId)),
        );
        expect(result, HandleMessageResult.contactAutoAdded);
        expect(await a.claims(), isEmpty);
      },
    );

    test('explicit re-add after deletion: a new request repairs again under '
        'the new relationship revision', () async {
      await a.contacts.deleteContact(_peer.peerId);
      await a.contacts.addContact(contactFor(_peer));
      await a.receive(
        await _request(control: newRequestControl(to: _self.peerId)),
      );
      final claim = (await a.claims()).single;
      expect(claim['relationship_revision'], 3);
    });
  });

  group('ML-KEM and wake-token ordering on parsed instants', () {
    test('first key lands, newer rotation lands, older replay and '
        'equal-instant different key are ignored', () async {
      await a.contacts.addContact(
        contactFor(_peer, scannedAt: '2026-10-16T10:00:00.000Z'),
      );
      Future<String?> keyAfter(String mlKem, String ts) async {
        await a.receive(await _request(mlKem: mlKem, ts: ts));
        return (await a.contacts.getContact(_peer.peerId))!.mlKemPublicKey;
      }

      expect(await keyAfter('k1', '2026-10-16T09:00:00.000Z'), 'k1');
      expect(await keyAfter('k2', '2026-10-16T12:00:00.000Z'), 'k2');
      expect(await keyAfter('k0', '2026-10-16T11:00:00.000Z'), 'k2');
      // 14:00+02:00 is the same instant as 12:00Z; lexical order would call
      // it newer.
      expect(await keyAfter('k3', '2026-10-16T14:00:00.000+02:00'), 'k2');
      expect(await keyAfter('k4', '2026-10-16T13:30:00Z'), 'k4');
    });

    test('wake token: newer instant replaces, equal instant with a '
        'different token is a conflict', () async {
      await a.receive(
        await _request(wakeToken: 't1', ts: '2026-10-16T12:00:00.000Z'),
      );
      await a.receive(
        await _request(wakeToken: 't2', ts: '2026-10-16T14:00:00.000+02:00'),
      );
      expect(a.tokens.tokens[_peer.peerId]!['tok'], 't1');
      await a.receive(
        await _request(wakeToken: 't3', ts: '2026-10-16T12:00:01.000Z'),
      );
      expect(a.tokens.tokens[_peer.peerId]!['tok'], 't3');
    });
  });

  // Codex Task 20 finding 1: a delete or block that lands while the receive
  // path awaits the grant store survives; the ML-KEM write never upserts the
  // contact row cached before that await.
  group('relationship change during the incoming grant await', () {
    for (final action in ['none', 'delete', 'block']) {
      test('preserves $action', () async {
        await a.contacts.addContact(contactFor(_peer, mlKem: 'old-mlkem'));
        final store = _PausedReceivedGrantStore();
        final wire = await _request(
          mlKem: 'new-mlkem',
          ts: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          grant: _grant(),
        );
        final receive = handleIncomingMessage(
          message: wire,
          bridge: a.bridge,
          requestRepo: a.requests,
          contactRepo: a.contacts,
          ownPeerId: _self.peerId,
          ownPrivateKey: _self.privateKey,
          receivedCallWakeHandleStore: store,
          repairRepository: a.repair,
          ownAccountPublicKey: _self.publicKey,
        );
        await store.entered.future;
        if (action == 'delete') await a.contacts.deleteContact(_peer.peerId);
        if (action == 'block') await a.contacts.blockContact(_peer.peerId);
        store.release.complete();
        await receive;
        final contact = await a.contacts.getContact(_peer.peerId);
        if (action == 'delete') {
          expect(contact, isNull);
        } else if (action == 'block') {
          expect(contact?.isBlocked, isTrue);
          expect(contact?.mlKemPublicKey, 'old-mlkem');
        } else {
          expect(contact?.mlKemPublicKey, 'new-mlkem');
        }
      });
    }
  });

  test('repair diagnostics carry only allow-listed statuses', () async {
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
    addTearDown(() => debugSetFlowEventSink(null));
    final control = newRequestControl(to: _self.peerId);
    await a.receive(await _request(control: control));

    final repairEvents = events
        .where((e) => (e['event'] as String).startsWith('CONTACT_REPAIR'))
        .toList();
    expect(repairEvents, isNotEmpty);
    final rendered = jsonEncode(repairEvents);
    expect(rendered, isNot(contains(control['id'])));
    expect(rendered, isNot(contains(_peer.peerId.substring(0, 10))));
    expect(rendered, isNot(contains(_peer.publicKey.substring(0, 10))));
    for (final event in repairEvents) {
      expect(
        (event['details'] as Map).keys.toSet().difference({'status', 'reason'}),
        isEmpty,
      );
    }
  });

  test('a request row is never created for a known contact', () async {
    await a.receive(
      await _request(control: newRequestControl(to: _self.peerId)),
    );
    expect(await a.requests.getRequest(_peer.peerId), isNull);
    expect(ContactRequestStatus.values, isNotEmpty);
  });
}
