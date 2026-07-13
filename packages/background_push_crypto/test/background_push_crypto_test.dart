import 'dart:convert';

import 'package:background_push_crypto/background_push_crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(BackgroundPushCrypto.channelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('decryptMessage forwards only the required ML-KEM inputs', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return jsonEncode(<String, Object?>{
            'ok': true,
            'plaintext': '{"emoji":"👍"}',
          });
        });

    final result = await const BackgroundPushCrypto().decryptMessage(
      secretKey: 'recipient-secret',
      kem: 'kem-ciphertext',
      ciphertext: 'message-ciphertext',
      nonce: 'nonce',
    );

    expect(captured?.method, 'decryptMessage');
    expect(jsonDecode(captured?.arguments as String), <String, Object?>{
      'secretKey': 'recipient-secret',
      'kem': 'kem-ciphertext',
      'ciphertext': 'message-ciphertext',
      'nonce': 'nonce',
    });
    expect(result['ok'], isTrue);
    expect(result['plaintext'], '{"emoji":"👍"}');
  });

  test('decryptMessage rejects a malformed native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'not-json');

    await expectLater(
      const BackgroundPushCrypto().decryptMessage(
        secretKey: 'secret',
        kem: 'kem',
        ciphertext: 'ciphertext',
        nonce: 'nonce',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('decryptGroup forwards only the required group crypto inputs', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return jsonEncode(<String, Object?>{
            'ok': true,
            'plaintext': '{"emoji":"👍"}',
          });
        });

    final result = await const BackgroundPushCrypto().decryptGroup(
      groupKey: 'group-secret',
      ciphertext: 'group-ciphertext',
      nonce: 'group-nonce',
    );

    expect(captured?.method, 'decryptGroup');
    expect(jsonDecode(captured?.arguments as String), <String, Object?>{
      'groupKey': 'group-secret',
      'ciphertext': 'group-ciphertext',
      'nonce': 'group-nonce',
    });
    expect(result['ok'], isTrue);
    expect(result['plaintext'], '{"emoji":"👍"}');
  });

  test('verifyPayload forwards only stateless Ed25519 inputs', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return jsonEncode(<String, Object?>{'ok': true, 'valid': true});
        });

    final result = await const BackgroundPushCrypto().verifyPayload(
      publicKey: 'sender-public-key',
      data: 'canonical-signed-payload',
      signature: 'signature',
    );

    expect(captured?.method, 'verifyPayload');
    expect(jsonDecode(captured?.arguments as String), <String, Object?>{
      'publicKey': 'sender-public-key',
      'data': 'canonical-signed-payload',
      'signature': 'signature',
    });
    expect(result, <String, Object?>{'ok': true, 'valid': true});
  });
}
