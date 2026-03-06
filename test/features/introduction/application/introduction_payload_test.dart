import 'dart:convert';

import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntroductionPayload serialization', () {
    final timestamp = DateTime.now().toUtc().toIso8601String();

    IntroductionPayload _makeSendPayload() {
      return IntroductionPayload(
        action: 'send',
        introductionId: 'intro-1',
        introducerId: 'peer-A',
        introducerUsername: 'Alice',
        recipientId: 'peer-B',
        recipientUsername: 'Bob',
        introducedId: 'peer-C',
        introducedUsername: 'Charlie',
        introducedPublicKey: 'pk-peer-C',
        introducedMlKemPublicKey: 'mlkem-pk-peer-C',
        responderId: null,
        responderUsername: null,
        timestamp: timestamp,
      );
    }

    IntroductionPayload _makeAcceptPayload() {
      return IntroductionPayload(
        action: 'accept',
        introductionId: 'intro-1',
        introducerId: 'peer-A',
        introducerUsername: 'Alice',
        recipientId: 'peer-B',
        recipientUsername: 'Bob',
        introducedId: 'peer-C',
        introducedUsername: 'Charlie',
        introducedPublicKey: 'pk-peer-C',
        introducedMlKemPublicKey: 'mlkem-pk-peer-C',
        responderId: 'peer-B',
        responderUsername: 'Bob',
        timestamp: timestamp,
      );
    }

    test('toInnerJson serializes send action correctly', () {
      final payload = _makeSendPayload();
      final json = payload.toInnerJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['action'], equals('send'));
      expect(map['introductionId'], equals('intro-1'));
      expect(map['introducerId'], equals('peer-A'));
      expect(map['introducerUsername'], equals('Alice'));
      expect(map['recipientId'], equals('peer-B'));
      expect(map['recipientUsername'], equals('Bob'));
      expect(map['introducedId'], equals('peer-C'));
      expect(map['introducedUsername'], equals('Charlie'));
      expect(map['introducedPublicKey'], equals('pk-peer-C'));
      expect(map['introducedMlKemPublicKey'], equals('mlkem-pk-peer-C'));
      expect(map['timestamp'], equals(timestamp));
    });

    test('fromInnerJson parses send action correctly', () {
      final original = _makeSendPayload();
      final json = original.toInnerJson();
      final parsed = IntroductionPayload.fromInnerJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.action, equals('send'));
      expect(parsed.introductionId, equals('intro-1'));
      expect(parsed.introducerId, equals('peer-A'));
      expect(parsed.introducerUsername, equals('Alice'));
      expect(parsed.recipientId, equals('peer-B'));
      expect(parsed.recipientUsername, equals('Bob'));
      expect(parsed.introducedId, equals('peer-C'));
      expect(parsed.introducedUsername, equals('Charlie'));
      expect(parsed.introducedPublicKey, equals('pk-peer-C'));
      expect(parsed.introducedMlKemPublicKey, equals('mlkem-pk-peer-C'));
    });

    test('toInnerJson serializes accept action correctly', () {
      final payload = _makeAcceptPayload();
      final json = payload.toInnerJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['action'], equals('accept'));
      expect(map['responderId'], equals('peer-B'));
      expect(map['responderUsername'], equals('Bob'));
    });

    test('fromInnerJson parses accept action correctly', () {
      final original = _makeAcceptPayload();
      final json = original.toInnerJson();
      final parsed = IntroductionPayload.fromInnerJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.action, equals('accept'));
      expect(parsed.responderId, equals('peer-B'));
      expect(parsed.responderUsername, equals('Bob'));
    });

    test('toJson wraps in v1 envelope', () {
      final payload = _makeSendPayload();
      final json = payload.toJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['type'], equals('introduction'));
      expect(map['version'], equals('1'));
      expect(map['payload'], isA<Map<String, dynamic>>());
      expect(map['payload']['action'], equals('send'));
      expect(map['payload']['introductionId'], equals('intro-1'));
    });

    test('fromJson parses v1 envelope', () {
      final original = _makeSendPayload();
      final json = original.toJson();
      final parsed = IntroductionPayload.fromJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.action, equals('send'));
      expect(parsed.introductionId, equals('intro-1'));
      expect(parsed.introducerId, equals('peer-A'));
    });

    test('buildEncryptedEnvelope creates v2 envelope', () {
      final envelope = IntroductionPayload.buildEncryptedEnvelope(
        senderPeerId: 'peer-A',
        kem: 'test-kem-data',
        ciphertext: 'test-ciphertext',
        nonce: 'test-nonce',
      );

      final map = jsonDecode(envelope) as Map<String, dynamic>;

      expect(map['type'], equals('introduction'));
      expect(map['version'], equals('2'));
      expect(map['encrypted'], isA<Map<String, dynamic>>());
      expect(map['encrypted']['kem'], equals('test-kem-data'));
      expect(map['encrypted']['ciphertext'], equals('test-ciphertext'));
      expect(map['encrypted']['nonce'], equals('test-nonce'));
    });

    test('parseEncryptedEnvelope rejects non-introduction types', () {
      final nonIntroEnvelope = jsonEncode({
        'type': 'chat_message',
        'version': '2',
        'encrypted': {
          'kem': 'test-kem',
          'ciphertext': 'test-ct',
          'nonce': 'test-nonce',
        },
      });

      final result =
          IntroductionPayload.parseEncryptedEnvelope(nonIntroEnvelope);

      expect(result, isNull);
    });
  });
}
