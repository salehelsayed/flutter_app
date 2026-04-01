import 'dart:convert';

import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payload = MessageDeletionPayload(
    messageId: 'msg-123',
    senderPeerId: 'peer-a',
    timestamp: '2026-03-31T10:00:00.000Z',
  );

  group('MessageDeletionPayload', () {
    test('round-trips a v1 envelope', () {
      final jsonString = payload.toJson();
      final restored = MessageDeletionPayload.fromJson(jsonString);

      expect(restored, isNotNull);
      expect(restored!.messageId, payload.messageId);
      expect(restored.senderPeerId, payload.senderPeerId);
      expect(restored.timestamp, payload.timestamp);
    });

    test('serializes the expected v1 envelope shape', () {
      final jsonString = payload.toJson();
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(parsed['type'], 'message_deletion');
      expect(parsed['version'], '1');
      expect(parsed['payload']['messageId'], 'msg-123');
      expect(parsed['payload']['senderPeerId'], 'peer-a');
      expect(parsed['payload']['timestamp'], '2026-03-31T10:00:00.000Z');
    });

    test('builds and parses a v2 encrypted envelope', () {
      final envelope = MessageDeletionPayload.buildEncryptedEnvelope(
        senderPeerId: 'peer-a',
        kem: 'fake-kem',
        ciphertext: 'fake-ciphertext',
        nonce: 'fake-nonce',
      );

      final parsed = MessageDeletionPayload.parseEncryptedEnvelope(envelope);
      expect(parsed, isNotNull);
      expect(parsed!['type'], 'message_deletion');
      expect(parsed['version'], '2');
      expect(parsed['senderPeerId'], 'peer-a');
      expect(parsed['encrypted']['kem'], 'fake-kem');
      expect(parsed['encrypted']['ciphertext'], 'fake-ciphertext');
      expect(parsed['encrypted']['nonce'], 'fake-nonce');
    });

    test('round-trips the decrypted inner payload', () {
      final innerJson = payload.toInnerJson();
      final restored = MessageDeletionPayload.fromDecryptedJson(innerJson);

      expect(restored, isNotNull);
      expect(restored!.messageId, payload.messageId);
      expect(restored.senderPeerId, payload.senderPeerId);
      expect(restored.timestamp, payload.timestamp);
    });

    test('rejects invalid or incomplete envelopes', () {
      expect(MessageDeletionPayload.fromJson('not json'), isNull);
      expect(
        MessageDeletionPayload.fromJson(
          jsonEncode({'type': 'chat_message', 'version': '1', 'payload': {}}),
        ),
        isNull,
      );
      expect(
        MessageDeletionPayload.parseEncryptedEnvelope(
          jsonEncode({
            'type': 'message_deletion',
            'version': '2',
            'encrypted': {'kem': 'fake-kem'},
          }),
        ),
        isNull,
      );
      expect(
        MessageDeletionPayload.fromDecryptedJson(
          jsonEncode({'messageId': 'msg-123'}),
        ),
        isNull,
      );
    });
  });
}
