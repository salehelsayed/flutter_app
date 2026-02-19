import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

/// A simple in-memory mock bridge that records calls and returns
/// pre-configured responses.
class MockBridge extends Bridge {
  String? lastRawRequest;
  Map<String, dynamic>? lastParsedRequest;
  Map<String, dynamic> nextResponse = {'ok': true};

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
    lastRawRequest = message;
    lastParsedRequest = jsonDecode(message) as Map<String, dynamic>;
    return jsonEncode(nextResponse);
  }
}

void main() {
  late MockBridge bridge;

  setUp(() {
    bridge = MockBridge();
  });

  // ---------------------------------------------------------------------------
  // callSignPayload
  // ---------------------------------------------------------------------------
  group('callSignPayload', () {
    test('sends payload.sign with correct data and privateKey', () async {
      bridge.nextResponse = {'ok': true, 'signature': 'abc123sig'};

      final result = await callSignPayload(
        bridge: bridge,
        dataToSign: '{"hello":"world"}',
        privateKey: 'privKeyBase64',
      );

      expect(result['ok'], isTrue);
      expect(result['signature'], equals('abc123sig'));

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('payload.sign'));
      expect(req['payload']['data'], equals('{"hello":"world"}'));
      expect(req['payload']['privateKey'], equals('privKeyBase64'));
    });

    test('returns error map on timeout', () async {
      // Use a very short timeout with a bridge that never completes
      final slowBridge = _SlowBridge();
      final result = await callSignPayload(
        bridge: slowBridge,
        dataToSign: 'data',
        privateKey: 'key',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callVerifyPayload
  // ---------------------------------------------------------------------------
  group('callVerifyPayload', () {
    test('returns true when bridge returns ok=true and valid=true', () async {
      bridge.nextResponse = {'ok': true, 'valid': true};

      final result = await callVerifyPayload(
        bridge: bridge,
        publicKey: 'pubKey',
        data: '{"test":"data"}',
        signature: 'sigBase64',
      );

      expect(result, isTrue);

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('payload.verify'));
      expect(req['payload']['publicKey'], equals('pubKey'));
      expect(req['payload']['data'], equals('{"test":"data"}'));
      expect(req['payload']['signature'], equals('sigBase64'));
    });

    test('returns false when bridge returns ok=true but valid=false', () async {
      bridge.nextResponse = {'ok': true, 'valid': false};

      final result = await callVerifyPayload(
        bridge: bridge,
        publicKey: 'pk',
        data: 'data',
        signature: 'sig',
      );

      expect(result, isFalse);
    });

    test('returns false on timeout', () async {
      final slowBridge = _SlowBridge();
      final result = await callVerifyPayload(
        bridge: slowBridge,
        publicKey: 'pk',
        data: 'data',
        signature: 'sig',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // callEncryptMessage
  // ---------------------------------------------------------------------------
  group('callEncryptMessage', () {
    test('sends message.encrypt with correct payload', () async {
      bridge.nextResponse = {
        'ok': true,
        'kem': 'kemBase64',
        'ciphertext': 'ctBase64',
        'nonce': 'nonceBase64',
      };

      final result = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: 'recipientPK',
        plaintext: 'Hello, world!',
      );

      expect(result['ok'], isTrue);
      expect(result['kem'], equals('kemBase64'));
      expect(result['ciphertext'], equals('ctBase64'));
      expect(result['nonce'], equals('nonceBase64'));

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('message.encrypt'));
      expect(req['payload']['recipientPublicKey'], equals('recipientPK'));
      expect(req['payload']['plaintext'], equals('Hello, world!'));
    });

    test('returns error on timeout', () async {
      final slowBridge = _SlowBridge();
      final result = await callEncryptMessage(
        bridge: slowBridge,
        recipientMlKemPublicKey: 'pk',
        plaintext: 'text',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callDecryptMessage
  // ---------------------------------------------------------------------------
  group('callDecryptMessage', () {
    test('sends message.decrypt with correct payload', () async {
      bridge.nextResponse = {'ok': true, 'plaintext': 'Hello, world!'};

      final result = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: 'secretKey',
        kem: 'kemData',
        ciphertext: 'ctData',
        nonce: 'nonceData',
      );

      expect(result['ok'], isTrue);
      expect(result['plaintext'], equals('Hello, world!'));

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('message.decrypt'));
      expect(req['payload']['secretKey'], equals('secretKey'));
      expect(req['payload']['kem'], equals('kemData'));
      expect(req['payload']['ciphertext'], equals('ctData'));
      expect(req['payload']['nonce'], equals('nonceData'));
    });

    test('returns error on timeout', () async {
      final slowBridge = _SlowBridge();
      final result = await callDecryptMessage(
        bridge: slowBridge,
        ownMlKemSecretKey: 'sk',
        kem: 'k',
        ciphertext: 'ct',
        nonce: 'n',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callMlKemKeygen
  // ---------------------------------------------------------------------------
  group('callMlKemKeygen', () {
    test('sends mlkem.keygen and returns keys', () async {
      bridge.nextResponse = {
        'ok': true,
        'publicKey': 'mlkemPubKey',
        'secretKey': 'mlkemSecKey',
      };

      final result = await callMlKemKeygen(bridge);

      expect(result['ok'], isTrue);
      expect(result['publicKey'], equals('mlkemPubKey'));
      expect(result['secretKey'], equals('mlkemSecKey'));

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('mlkem.keygen'));
    });

    test('returns error on timeout', () async {
      final slowBridge = _SlowBridge();
      final result = await callMlKemKeygen(
        slowBridge,
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callIdentityGenerate
  // ---------------------------------------------------------------------------
  group('callIdentityGenerate', () {
    test('sends identity.generate and returns identity', () async {
      bridge.nextResponse = {
        'ok': true,
        'identity': {
          'peerId': '12D3KooWTest',
          'publicKey': 'pk',
          'privateKey': 'sk',
          'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
      };

      final result = await callIdentityGenerate(bridge);

      expect(result['ok'], isTrue);
      expect(result['identity'], isNotNull);

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('identity.generate'));
    });
  });

  // ---------------------------------------------------------------------------
  // callIdentityRestore
  // ---------------------------------------------------------------------------
  group('callIdentityRestore', () {
    test('sends identity.restore with mnemonic', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      bridge.nextResponse = {
        'ok': true,
        'identity': {
          'peerId': '12D3KooWRestored',
          'publicKey': 'pk',
          'privateKey': 'sk',
          'mnemonic12': mnemonic,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
      };

      final result = await callIdentityRestore(bridge, mnemonic);

      expect(result['ok'], isTrue);

      final req = bridge.lastParsedRequest!;
      expect(req['cmd'], equals('identity.restore'));
      expect(req['payload']['mnemonic12'], equals(mnemonic));
    });
  });
}

/// A bridge that never completes, to test timeout behavior.
class _SlowBridge extends Bridge {
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
  Future<String> send(String message) {
    // Return a future that never completes
    return Future.delayed(const Duration(hours: 1), () => '');
  }
}
