import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeBridge extends Bridge {
  bool verifyResult = true;

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'payload.verify') {
      return jsonEncode({'ok': true, 'valid': verifyResult});
    }
    return jsonEncode({'ok': true});
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _ownPeerId = '12D3KooWOwnPeerIdForTest';
const _otherPeerId = '12D3KooWOtherPeerIdTest';

Map<String, dynamic> _validPayload({String? peerId, String? ts}) => {
      'pk': 'publicKeyBase64',
      'ns': peerId ?? _otherPeerId,
      'rv': '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      'ts': ts ?? DateTime.now().toUtc().toIso8601String(),
      'sig': 'signatureBase64',
      'un': 'Alice',
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeBridge bridge;

  setUp(() {
    bridge = _FakeBridge();
  });

  test('success: parses valid QR payload and returns contact', () async {
    final payload = _validPayload();
    final qrString = jsonEncode(payload);

    final (result, contact) = await parseQRPayload(
      qrString: qrString,
      bridge: bridge,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(ParseQRResult.success));
    expect(contact, isNotNull);
    expect(contact!.peerId, equals(_otherPeerId));
    expect(contact.publicKey, equals('publicKeyBase64'));
    expect(contact.username, equals('Alice'));
  });

  test('invalidJson: non-JSON string', () async {
    final (result, contact) = await parseQRPayload(
      qrString: 'not valid json',
      bridge: bridge,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(ParseQRResult.invalidJson));
    expect(contact, isNull);
  });

  test('missingFields: required field missing', () async {
    final payload = {'pk': 'key', 'ns': 'peer'};
    // Missing rv, ts, sig

    final (result, contact) = await parseQRPayload(
      qrString: jsonEncode(payload),
      bridge: bridge,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(ParseQRResult.missingFields));
    expect(contact, isNull);
  });

  test('selfScan: scanning own QR code', () async {
    final payload = _validPayload(peerId: _ownPeerId);

    final (result, contact) = await parseQRPayload(
      qrString: jsonEncode(payload),
      bridge: bridge,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(ParseQRResult.selfScan));
    expect(contact, isNull);
  });

  test('expired: timestamp older than maxAge', () async {
    final oldTimestamp = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 25))
        .toIso8601String();

    final payload = _validPayload(ts: oldTimestamp);

    final (result, contact) = await parseQRPayload(
      qrString: jsonEncode(payload),
      bridge: bridge,
      ownPeerId: _ownPeerId,
      maxAge: const Duration(hours: 24),
    );

    expect(result, equals(ParseQRResult.expired));
    expect(contact, isNull);
  });

  test('invalidSignature: bridge returns invalid', () async {
    bridge.verifyResult = false;

    final payload = _validPayload();

    final (result, contact) = await parseQRPayload(
      qrString: jsonEncode(payload),
      bridge: bridge,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(ParseQRResult.invalidSignature));
    expect(contact, isNull);
  });

  test('success with mlkem key: preserves ML-KEM public key', () async {
    final payload = _validPayload();
    payload['mlkem'] = 'senderMlKemPubKey';

    final (result, contact) = await parseQRPayload(
      qrString: jsonEncode(payload),
      bridge: bridge,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(ParseQRResult.success));
    expect(contact!.mlKemPublicKey, equals('senderMlKemPubKey'));
  });

  test('success: non-expired timestamp within maxAge', () async {
    final recentTimestamp = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();

    final payload = _validPayload(ts: recentTimestamp);

    final (result, _) = await parseQRPayload(
      qrString: jsonEncode(payload),
      bridge: bridge,
      ownPeerId: _ownPeerId,
      maxAge: const Duration(hours: 24),
    );

    expect(result, equals(ParseQRResult.success));
  });
}
