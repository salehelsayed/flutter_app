import 'dart:convert';

import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntroductionPayload extended', () {
    test('parseEncryptedEnvelope returns null for v1 envelope', () {
      final v1Envelope = jsonEncode({
        'type': 'introduction',
        'version': '1',
        'payload': {
          'action': 'send',
          'introductionId': 'intro-1',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      });

      final result = IntroductionPayload.parseEncryptedEnvelope(v1Envelope);
      expect(result, isNull);
    });

    test('parseEncryptedEnvelope returns null for missing encrypted block',
        () {
      final envelope = jsonEncode({
        'type': 'introduction',
        'version': '2',
        'senderPeerId': 'peer-A',
        // Missing 'encrypted' block
      });

      final result = IntroductionPayload.parseEncryptedEnvelope(envelope);
      expect(result, isNull);
    });

    test('fromJson returns null for non-introduction type', () {
      final chatMessage = jsonEncode({
        'type': 'chat',
        'version': '1',
        'payload': {
          'text': 'hello',
        },
      });

      final result = IntroductionPayload.fromJson(chatMessage);
      expect(result, isNull);
    });
  });
}
