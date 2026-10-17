import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

// Task 12b: the signed `cr` operation marker on the send side, and the
// build/transmit split that lets a durable retry resend identical bytes.

final _bus = Ed25519ContactRequestCryptoBus();
final _a = TestEd25519Identity.fromSeedByte(0x51);
final _b = TestEd25519Identity.fromSeedByte(0x52);

const _uuidA = '0f8fad5b-d9cb-469f-a165-70867728950e';
const _uuidB = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

final class _Sender {
  _Sender() {
    _bus
      ..register(_a)
      ..register(_b);
    p2p = FakeP2PService(peerId: _a.peerId, network: network);
    identities = FakeIdentityRepository()
      ..seed(testIdentityModel(_a, username: 'A', mlKemPublicKey: 'mlkem-a'));
  }

  final network = FakeP2PNetwork();
  final bridge = Ed25519ContactRequestBridge(_bus);
  late final FakeP2PService p2p;
  late final FakeIdentityRepository identities;

  Future<SendContactRequestResult> send({
    required bool marked,
    String? recipientKey,
  }) => sendContactRequest(
    p2pService: p2p,
    identityRepo: identities,
    bridge: bridge,
    targetPeerId: _b.peerId,
    recipientPublicKey: recipientKey,
    markAsNewRequest: marked,
  );

  List<String> get inbox => network
      .retrieveInbox(_b.peerId)
      .map((entry) => entry['message'] as String)
      .toList();
}

void main() {
  group('ContactRequestControl.parse', () {
    test('round-trips both kinds with sorted canonical keys', () {
      const request = ContactRequestControl.newRequest(
        id: _uuidA,
        to: 'peer-b',
      );
      const reply = ContactRequestControl.repairReply(
        id: _uuidB,
        to: 'peer-a',
        replyTo: _uuidA,
      );
      expect(ContactRequestControl.parse(request.toCanonicalMap()), request);
      expect(ContactRequestControl.parse(reply.toCanonicalMap()), reply);
      expect(
        jsonEncode(reply.toCanonicalMap()),
        '{"id":"$_uuidB","kind":"repair_reply","replyTo":"$_uuidA",'
        '"to":"peer-a","v":1}',
      );
    });

    final rejects = <String, Object?>{
      'not an object': 'cr',
      'unknown key': {
        'v': 1,
        'kind': 'new_request',
        'id': _uuidA,
        'to': 'p',
        'x': 1,
      },
      'unknown version': {
        'v': 2,
        'kind': 'new_request',
        'id': _uuidA,
        'to': 'p',
      },
      'string version': {
        'v': '1',
        'kind': 'new_request',
        'id': _uuidA,
        'to': 'p',
      },
      'unknown kind': {
        'v': 1,
        'kind': 'key_exchange_retry',
        'id': _uuidA,
        'to': 'p',
      },
      'malformed id': {'v': 1, 'kind': 'new_request', 'id': 'abc', 'to': 'p'},
      'missing recipient': {'v': 1, 'kind': 'new_request', 'id': _uuidA},
      'reply without replyTo': {
        'v': 1,
        'kind': 'repair_reply',
        'id': _uuidA,
        'to': 'p',
      },
      'reply with malformed replyTo': {
        'v': 1,
        'kind': 'repair_reply',
        'id': _uuidA,
        'to': 'p',
        'replyTo': 'nope',
      },
      'request carrying replyTo': {
        'v': 1,
        'kind': 'new_request',
        'id': _uuidA,
        'to': 'p',
        'replyTo': _uuidB,
      },
    };
    for (final entry in rejects.entries) {
      test('rejects ${entry.key}', () {
        expect(
          () => ContactRequestControl.parse(entry.value),
          throwsFormatException,
        );
      });
    }
  });

  group('marked send', () {
    test(
      'signs cr inside the payload and uses cr.id as the outer msgId',
      () async {
        final sender = _Sender();
        expect(
          await sender.send(marked: true, recipientKey: _b.publicKey),
          SendContactRequestResult.success,
        );

        final encrypted = sender.bridge.encrypts.single;
        expect(encrypted.recipientPublicKey, _b.publicKey);
        final cr = encrypted.payload['cr'] as Map<String, dynamic>;
        expect(cr['v'], 1);
        expect(cr['kind'], 'new_request');
        expect(cr['to'], _b.peerId);
        expect(cr.containsKey('replyTo'), isFalse);
        expect(encrypted.msgId, cr['id']);

        final envelope =
            jsonDecode(sender.inbox.single) as Map<String, dynamic>;
        expect(envelope['msgId'], cr['id']);

        // The real Ed25519 signature covers the canonical payload WITH cr ...
        final unsigned = SplayTreeMap<String, dynamic>.from(encrypted.payload)
          ..remove('sig');
        final verifier = Ed25519ContactRequestBridge(_bus);
        Future<bool> verify(Map<String, dynamic> data) async =>
            jsonDecode(
              await verifier.send(
                jsonEncode({
                  'cmd': 'payload.verify',
                  'payload': {
                    'publicKey': _a.publicKey,
                    'data': jsonEncode(data),
                    'signature': encrypted.payload['sig'],
                  },
                }),
              ),
            )['valid'] ==
            true;
        expect(await verify(unsigned), isTrue);
        // ... so stripping or changing the marker breaks it.
        expect(await verify(SplayTreeMap.of(unsigned)..remove('cr')), isFalse);
        expect(
          await verify(
            SplayTreeMap.of(unsigned)
              ..['cr'] = SplayTreeMap.of(cr)
              ..['kind'] = 'repair_reply',
          ),
          isFalse,
        );
      },
    );

    test('an unmarked send carries no cr', () async {
      final sender = _Sender();
      await sender.send(marked: false, recipientKey: _b.publicKey);
      expect(sender.bridge.encrypts.single.payload.containsKey('cr'), isFalse);
    });

    test('a marked send without a recipient key fails and sends nothing '
        '(no plaintext downgrade)', () async {
      final sender = _Sender();
      expect(
        await sender.send(marked: true),
        SendContactRequestResult.encryptionError,
      );
      expect(sender.inbox, isEmpty);
      expect(sender.bridge.encrypts, isEmpty);
    });
  });

  test(
    'a prebuilt envelope is transmitted byte for byte on every retry',
    () async {
      final sender = _Sender();
      final build = await buildContactRequestEnvelope(
        identityRepo: sender.identities,
        bridge: sender.bridge,
        targetPeerId: _b.peerId,
        recipientPublicKey: _b.publicKey,
        control: ContactRequestControl.newRequest(id: _uuidA, to: _b.peerId),
      );
      final envelope = BuiltContactRequestEnvelope.fromJson(
        jsonDecode(jsonEncode(build.envelope!.toJson()))
            as Map<String, Object?>,
      );
      for (var i = 0; i < 2; i++) {
        expect(
          (await transmitContactRequestEnvelope(
            p2pService: sender.p2p,
            envelope: envelope,
          )).result,
          SendContactRequestResult.success,
        );
      }
      final sent = sender.inbox;
      expect(sent, hasLength(2));
      expect(sent[0], sent[1]);
      expect((jsonDecode(sent[0]) as Map)['msgId'], _uuidA);
      expect(sender.bridge.encrypts, hasLength(1));
    },
  );
}
