import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge that records calls and returns configurable responses
// ---------------------------------------------------------------------------

class _FakeBridge extends Bridge {
  Map<String, dynamic>? lastPayload;
  String? lastCmd;
  Map<String, dynamic> encryptResponse = {
    'ok': true,
    'ephemeralPublicKey': 'ephPubBase64',
    'ciphertext': 'ctBase64',
    'nonce': 'nonceBase64',
  };
  Map<String, dynamic> decryptResponse = {
    'ok': true,
    'plaintext': '{"ns":"peer","pk":"key","sig":"sig"}',
  };
  bool shouldTimeout = false;

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
    if (shouldTimeout) {
      await Future.delayed(const Duration(seconds: 30));
      return jsonEncode({'ok': false});
    }

    final req = jsonDecode(message) as Map<String, dynamic>;
    lastCmd = req['cmd'] as String?;
    lastPayload = req['payload'] as Map<String, dynamic>?;

    if (lastCmd == 'contactrequest.encrypt') {
      return jsonEncode(encryptResponse);
    }
    if (lastCmd == 'contactrequest.decrypt') {
      return jsonEncode(decryptResponse);
    }
    return jsonEncode({'ok': true});
  }
}

void main() {
  late _FakeBridge bridge;

  setUp(() {
    bridge = _FakeBridge();
  });

  group('callEncryptContactRequest', () {
    test('sends contactrequest.encrypt with correct payload', () async {
      await callEncryptContactRequest(
        bridge: bridge,
        recipientPublicKey: 'recipPub',
        signedPayloadJson: '{"ns":"peer"}',
        msgId: 'msg-123',
        ts: '2024-01-01T00:00:00Z',
      );

      expect(bridge.lastCmd, equals('contactrequest.encrypt'));
      expect(bridge.lastPayload!['recipientPublicKey'], equals('recipPub'));
      expect(bridge.lastPayload!['plaintext'], equals('{"ns":"peer"}'));
      expect(bridge.lastPayload!['msgId'], equals('msg-123'));
      expect(bridge.lastPayload!['ts'], equals('2024-01-01T00:00:00Z'));
    });

    test('returns ok + ephemeralPublicKey + ciphertext + nonce', () async {
      final result = await callEncryptContactRequest(
        bridge: bridge,
        recipientPublicKey: 'recipPub',
        signedPayloadJson: '{"ns":"peer"}',
        msgId: 'msg-123',
        ts: '2024-01-01T00:00:00Z',
      );

      expect(result['ok'], isTrue);
      expect(result['ephemeralPublicKey'], equals('ephPubBase64'));
      expect(result['ciphertext'], equals('ctBase64'));
      expect(result['nonce'], equals('nonceBase64'));
    });

    test('returns error map on bridge ok: false', () async {
      bridge.encryptResponse = {
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': 'bad key',
      };

      final result = await callEncryptContactRequest(
        bridge: bridge,
        recipientPublicKey: 'badKey',
        signedPayloadJson: '{}',
        msgId: 'msg-123',
        ts: '2024-01-01T00:00:00Z',
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('INTERNAL_ERROR'));
    });

    test('returns BRIDGE_TIMEOUT on timeout', () async {
      bridge.shouldTimeout = true;

      final result = await callEncryptContactRequest(
        bridge: bridge,
        recipientPublicKey: 'recipPub',
        signedPayloadJson: '{}',
        msgId: 'msg-123',
        ts: '2024-01-01T00:00:00Z',
        timeout: const Duration(milliseconds: 50),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  group('callDecryptContactRequest', () {
    test('sends contactrequest.decrypt with correct payload', () async {
      await callDecryptContactRequest(
        bridge: bridge,
        ownPrivateKey: 'privKey',
        ephemeralPublicKey: 'ephPub',
        ciphertext: 'ct',
        nonce: 'nonce',
        msgId: 'msg-456',
        ts: '2024-06-15T12:00:00Z',
      );

      expect(bridge.lastCmd, equals('contactrequest.decrypt'));
      expect(bridge.lastPayload!['privateKey'], equals('privKey'));
      expect(bridge.lastPayload!['ephemeralPublicKey'], equals('ephPub'));
      expect(bridge.lastPayload!['ciphertext'], equals('ct'));
      expect(bridge.lastPayload!['nonce'], equals('nonce'));
      expect(bridge.lastPayload!['msgId'], equals('msg-456'));
      expect(bridge.lastPayload!['ts'], equals('2024-06-15T12:00:00Z'));
    });

    test('returns ok + plaintext on success', () async {
      final result = await callDecryptContactRequest(
        bridge: bridge,
        ownPrivateKey: 'privKey',
        ephemeralPublicKey: 'ephPub',
        ciphertext: 'ct',
        nonce: 'nonce',
        msgId: 'msg-456',
        ts: '2024-06-15T12:00:00Z',
      );

      expect(result['ok'], isTrue);
      expect(result['plaintext'], isNotNull);
    });

    test('returns error map on bridge ok: false', () async {
      bridge.decryptResponse = {
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': 'decryption failed',
      };

      final result = await callDecryptContactRequest(
        bridge: bridge,
        ownPrivateKey: 'privKey',
        ephemeralPublicKey: 'ephPub',
        ciphertext: 'ct',
        nonce: 'nonce',
        msgId: 'msg-456',
        ts: '2024-06-15T12:00:00Z',
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('INTERNAL_ERROR'));
    });

    test('returns BRIDGE_TIMEOUT on timeout', () async {
      bridge.shouldTimeout = true;

      final result = await callDecryptContactRequest(
        bridge: bridge,
        ownPrivateKey: 'privKey',
        ephemeralPublicKey: 'ephPub',
        ciphertext: 'ct',
        nonce: 'nonce',
        msgId: 'msg-456',
        ts: '2024-06-15T12:00:00Z',
        timeout: const Duration(milliseconds: 50),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });
}
