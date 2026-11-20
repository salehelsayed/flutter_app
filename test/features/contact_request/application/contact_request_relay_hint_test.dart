import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart' show callVerifyPayload;
import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _budget = Duration(seconds: 2);
const _firstTestRelay =
    '/dns/test-relay-a.invalid/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
const _secondTestRelay =
    '/dns/test-relay-b.invalid/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
const _configuredRelayCsv = ' , $_firstTestRelay , , $_secondTestRelay , ';
const _expectTestRelay = bool.fromEnvironment('B15CRRV_EXPECT_TEST_RELAY');
const _actualRelayCsv = String.fromEnvironment('MKNOON_RELAY_ADDRESSES');

void main() {
  test('B15CRRV001 v1 signs the effective relay hint', () {
    return _checkSignedRelay(encrypted: false).timeout(_budget);
  });
  test('B15CRRV002 v2 signs the effective relay hint before sealing', () {
    return _checkSignedRelay(encrypted: true).timeout(_budget);
  });
}

Future<void> _checkSignedRelay({required bool encrypted}) async {
  if (_expectTestRelay) {
    expect(_actualRelayCsv, _configuredRelayCsv,
        reason: 'The TEST variant must use the independently pinned relay CSV');
  } else {
    expect(_actualRelayCsv.split(',').every((entry) => entry.trim().isEmpty),
        isTrue, reason: 'Default controls must use absent or all-blank CSV');
  }
  final expectedRelay = _expectTestRelay ? _firstTestRelay : rendezvousAddress;
  final signer = TestEd25519Identity.fromSeedByte(0x51);
  final recipient = TestEd25519Identity.fromSeedByte(0x52);
  final repo = FakeIdentityRepository()
    ..seed(testIdentityModel(signer, username: 'RelayFixture'));
  final bus = Ed25519ContactRequestCryptoBus()..register(signer);
  final bridge = Ed25519ContactRequestBridge(bus);
  final built = await buildContactRequestEnvelope(
    identityRepo: repo,
    bridge: bridge,
    targetPeerId: recipient.peerId,
    recipientPublicKey: encrypted ? recipient.publicKey : null,
    signingTime: DateTime.utc(2026, 11, 19),
  ).timeout(_budget);

  expect(built.failure, isNull);
  expect(built.envelope, isNotNull);
  final envelope = built.envelope!;
  expect(envelope.encrypted, encrypted);
  final wire = jsonDecode(envelope.messageJson) as Map<String, dynamic>;
  expect(wire['type'], 'contact_request');
  expect(wire['version'], encrypted ? '2' : '1');
  expect(wire['intent'], 'new_request');
  final Map<String, dynamic> payload;
  if (encrypted) {
    expect(bridge.encrypts, hasLength(1));
    expect(wire.containsKey('payload'), isFalse);
    expect(wire.containsKey('rv'), isFalse);
    expect(bridge.encrypts.single.recipientPublicKey, recipient.publicKey);
    expect(bridge.encrypts.single.msgId, wire['msgId']);
    payload = bridge.encrypts.single.payload;
  } else {
    expect(bridge.encrypts, isEmpty);
    payload = Map<String, dynamic>.from(wire['payload'] as Map);
  }
  expect(payload.keys, ['ns', 'pk', 'rv', 'sig', 'ts', 'un']);
  expect(payload['ns'], signer.peerId);
  expect(payload['pk'], signer.publicKey);
  expect(payload['ts'], '2026-11-19T00:00:00.000Z');
  expect(payload['rv'], isA<String>());
  final unsigned = SplayTreeMap<String, dynamic>.from(payload)..remove('sig');
  final canonical = jsonEncode(unsigned);
  final signing = bridge.commands
      .singleWhere((command) => command['cmd'] == 'payload.sign')['payload']
      as Map<String, dynamic>;
  expect(signing['data'], canonical);
  expect(signing['privateKey'], signer.privateKey);

  // The retained fixture performs real Ed25519 signing and verification. Its
  // v2 sealing is an in-memory lookup, not native encryption or transport proof.
  final signature = payload['sig'] as String;
  expect(await callVerifyPayload(
    bridge: bridge,
    publicKey: signer.publicKey,
    data: canonical,
    signature: signature,
    timeout: _budget,
  ).timeout(_budget), isTrue);
  final tampered = SplayTreeMap<String, dynamic>.from(unsigned)
    ..['rv'] = '${unsigned['rv']}/tampered';
  expect(await callVerifyPayload(
    bridge: bridge,
    publicKey: signer.publicKey,
    data: jsonEncode(tampered),
    signature: signature,
    timeout: _budget,
  ).timeout(_budget), isFalse);
  expect(bridge.verifyCalls, 2);
  expect(bridge.verifiedData, [canonical]);

  // Keep the causal assertion after authentic-signature and tamper controls:
  // RED must show a correctly signed request advertising the wrong hint.
  expect(payload['rv'], expectedRelay,
      reason: 'B15CRRV effective relay hint must be selected before signing');
  expect((jsonDecode(signing['data'] as String) as Map<String, dynamic>)['rv'], expectedRelay);
}
