import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/deterministic_contact_request_crypto.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../support/contact_repair_harness.dart';

// Owner decision A: the legacy reciprocal call-grant reply survives only for
// genuinely unmarked v2 `key_exchange_retry` traffic from an authenticated,
// unblocked existing contact whose exact grant is durably current, after the
// direct ACK. Every marked message bypasses it; a malformed marker never falls
// back to it.

final _bus = Ed25519ContactRequestCryptoBus();
final _self = TestEd25519Identity.fromSeedByte(0x41);
final _peer = TestEd25519Identity.fromSeedByte(0x42);
final _rogue = TestEd25519Identity.fromSeedByte(0x43);
const _challenge = '123e4567-e89b-42d3-a456-426614174000';

CallWakeHandleGrant _grant() {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  return CallWakeHandleGrant(
    handle: '0123456789abcdef0123456789abcdef',
    recipientDevicePeerId: _self.peerId,
    deviceKeyEpoch: 1,
    generation: 1,
    issuedAtMs: nowMs - 1000,
    expiresAtMs: nowMs + const Duration(hours: 1).inMilliseconds,
  );
}

final class _Receiver {
  _Receiver(this.db) : contacts = databaseContactRepository(db);

  final Database db;
  final ContactRepositoryImpl contacts;
  final bridge = Ed25519ContactRequestBridge(_bus);
  final order = <String>[];
  final grants = InMemoryReceivedCallWakeHandleStore();
  late final ContactRequestListener listener;

  void build({Future<void> Function(String peerId)? recover}) {
    bridge.onCommand = (command) {
      if (command['cmd'] == 'message:confirm') {
        final payload = command['payload'] as Map<String, dynamic>;
        order.add('ack:${payload['ok']}:${payload['callWakeReceipt']}');
      }
    };
    listener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: InMemoryContactRequestRepository(),
      contactRepo: contacts,
      bridge: bridge,
      getOwnPeerId: () => _self.peerId,
      getOwnPrivateKey: () async => _self.privateKey,
      getOwnPublicKey: () async => _self.publicKey,
      receivedCallWakeHandleStore: grants,
      repairRepository: SqlContactRepairRepository(db),
      onRepairReplyQueued: () => order.add('outbox'),
      requestReciprocalCallWakeRecovery:
          recover ??
          (peerId) async {
            order.add('recover:$peerId');
          },
    );
  }

  Future<List<Map<String, Object?>>> claims() =>
      db.query('contact_repair_requests');
}

Future<ChatMessage> _wire({
  TestEd25519Identity? signer,
  String intent = 'key_exchange_retry',
  Map<String, Object>? control,
  Object? delivered = const _Same(),
  bool withReceipt = true,
  String? nonce = 'nonce-1',
  String? msgId,
}) => buildRepairWire(
  bus: _bus,
  signer: signer ?? _peer,
  claimedPeerId: _peer.peerId,
  claimedPublicKey: signer == null ? null : _peer.publicKey,
  recipientPublicKey: _self.publicKey,
  intent: intent,
  signedControl: control,
  deliveredControl: delivered is _Same ? control : delivered,
  callWakeHandle: _grant(),
  callWakeReceiptChallenge: withReceipt ? _challenge : null,
  confirmNonce: nonce,
  msgId: msgId,
);

final class _Same {
  const _Same();
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
    await a.contacts.addContact(contactFor(_peer, mlKem: 'peer-mlkem'));
  });
  tearDown(() async {
    a.listener.dispose();
    await a.db.close();
  });

  test('legacy unmarked key_exchange_retry: exact receipt ACKed first, then '
      'exactly one reciprocal request', () async {
    a.build();
    final result = await a.listener.processIncomingMessage(await _wire());
    expect(result, HandleMessageResult.alreadyContact);
    expect(a.order, ['ack:true:$_challenge', 'recover:${_peer.peerId}']);
    expect(await a.claims(), isEmpty, reason: 'legacy traffic has no outbox');
  });

  test('a failing reciprocal does not undo the ACK', () async {
    a.build(
      recover: (_) async {
        a.order.add('recover-failed');
        throw StateError('reciprocal unavailable');
      },
    );
    final result = await a.listener.processIncomingMessage(await _wire());
    expect(result, HandleMessageResult.alreadyContact);
    expect(a.order, ['ack:true:$_challenge', 'recover-failed']);
  });

  test('a marked new_request with key_exchange_retry intent gets only the '
      'durable outbox reply', () async {
    a.build();
    await a.listener.processIncomingMessage(
      await _wire(control: newRequestControl(to: _self.peerId)),
    );
    expect(a.order, ['ack:true:$_challenge', 'outbox']);
    expect(await a.claims(), hasLength(1));
  });

  test(
    'a marked repair_reply with an altered outer intent gets no reply',
    () async {
      a.build();
      await a.listener.processIncomingMessage(
        await _wire(
          control: repairReplyControl(
            to: _self.peerId,
            replyTo: nextControlId(),
          ),
        ),
      );
      expect(a.order, ['ack:true:$_challenge']);
      expect(await a.claims(), isEmpty);
    },
  );

  group('no reciprocal', () {
    test('invalid signature (rogue key)', () async {
      a.build();
      await a.listener.processIncomingMessage(await _wire(signer: _rogue));
      expect(a.order.where((e) => e.startsWith('recover')), isEmpty);
    });

    test('malformed marker never falls back to the legacy reply', () async {
      a.build();
      final result = await a.listener.processIncomingMessage(
        await _wire(
          control: {
            ...newRequestControl(to: _self.peerId),
            'v': 2,
          },
        ),
      );
      expect(result, HandleMessageResult.invalidMessage);
      expect(a.order.where((e) => e.startsWith('recover')), isEmpty);
    });

    test('no exact receipt requested', () async {
      a.build();
      await a.listener.processIncomingMessage(await _wire(withReceipt: false));
      expect(a.order.where((e) => e.startsWith('recover')), isEmpty);
    });

    test('no direct nonce (inbox delivery)', () async {
      a.build();
      await a.listener.processIncomingMessage(await _wire(nonce: null));
      expect(a.order, isEmpty);
    });

    test(
      'stale, non-exact receipt (a newer grant is already stored)',
      () async {
        a.build();
        final stored = _grant();
        await a.grants.storeIfStrictlyNewer(
          issuerAccountPeerId: _peer.peerId,
          grant: CallWakeHandleGrant(
            handle: stored.handle,
            recipientDevicePeerId: stored.recipientDevicePeerId,
            deviceKeyEpoch: stored.deviceKeyEpoch,
            generation: 2,
            issuedAtMs: stored.issuedAtMs,
            expiresAtMs: stored.expiresAtMs,
          ),
          nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        await a.listener.processIncomingMessage(await _wire());
        expect(a.order, ['ack:false:null']);
      },
    );

    test('non-contact sender', () async {
      await a.contacts.deleteContact(_peer.peerId);
      await a.db.delete('contact_relationship_consent');
      a.build();
      await a.listener.processIncomingMessage(await _wire());
      expect(a.order.where((e) => e.startsWith('recover')), isEmpty);
    });

    // (e) The reciprocal we send is an unmarked new_request: it never
    // triggers the legacy reply on the other side, so there is no loop.
    test('ordinary new_request intent (the returned reciprocal)', () async {
      a.build();
      await a.listener.processIncomingMessage(
        await _wire(intent: 'new_request'),
      );
      expect(a.order, ['ack:true:$_challenge']);
    });

    test('blocked contact', () async {
      await a.contacts.blockContact(_peer.peerId);
      a.build();
      await a.listener.processIncomingMessage(await _wire());
      expect(a.order.where((e) => e.startsWith('recover')), isEmpty);
    });

    test('duplicate delivery replies once', () async {
      a.build();
      final message = await _wire();
      await a.listener.processIncomingMessage(message);
      await a.listener.processIncomingMessage(message);
      expect(a.order.where((e) => e.startsWith('recover')), hasLength(1));
    });
  });
}
