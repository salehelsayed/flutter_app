import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';

void main() {
  const testPayload = MessagePayload(
    id: 'msg-uuid-001',
    text: 'Hello! This is my first letter.',
    senderPeerId: '12D3KooWSender123',
    senderUsername: 'Alice',
    timestamp: '2026-02-09T15:30:00.000Z',
  );

  group('MessagePayload', () {
    group('toJson / fromJson round-trip', () {
      test('round-trips correctly', () {
        final jsonString = testPayload.toJson();
        final restored = MessagePayload.fromJson(jsonString);

        expect(restored, isNotNull);
        expect(restored!.id, testPayload.id);
        expect(restored.text, testPayload.text);
        expect(restored.senderPeerId, testPayload.senderPeerId);
        expect(restored.senderUsername, testPayload.senderUsername);
        expect(restored.timestamp, testPayload.timestamp);
      });

      test('toJson produces correct envelope structure', () {
        final jsonString = testPayload.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

        expect(parsed['type'], 'chat_message');
        expect(parsed['version'], '1');
        expect(parsed['payload'], isA<Map<String, dynamic>>());

        final payload = parsed['payload'] as Map<String, dynamic>;
        expect(payload['id'], 'msg-uuid-001');
        expect(payload['text'], 'Hello! This is my first letter.');
        expect(payload['senderPeerId'], '12D3KooWSender123');
        expect(payload['senderUsername'], 'Alice');
        expect(payload['timestamp'], '2026-02-09T15:30:00.000Z');
      });
    });

    group('fromJson invalid input', () {
      test('returns null for non-JSON string', () {
        expect(MessagePayload.fromJson('not json'), isNull);
      });

      test('returns null for wrong type', () {
        final json = jsonEncode({
          'type': 'contact_request',
          'version': '1',
          'payload': {
            'id': '1',
            'text': 'hi',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        expect(MessagePayload.fromJson(json), isNull);
      });

      test('returns null for missing payload', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
        });
        expect(MessagePayload.fromJson(json), isNull);
      });

      test('returns null for missing required fields', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': '1',
            'text': 'hi',
            // missing senderPeerId, senderUsername, timestamp
          },
        });
        expect(MessagePayload.fromJson(json), isNull);
      });

      test('returns null for empty string', () {
        expect(MessagePayload.fromJson(''), isNull);
      });

      test('returns null when payload has null fields', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': null,
            'text': 'hi',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        expect(MessagePayload.fromJson(json), isNull);
      });
    });

    group('toConversationMessage', () {
      test('converts to incoming ConversationMessage correctly', () {
        final message = testPayload.toConversationMessage(
          contactPeerId: '12D3KooWSender123',
          isIncoming: true,
          status: 'delivered',
        );

        expect(message.id, testPayload.id);
        expect(message.contactPeerId, '12D3KooWSender123');
        expect(message.senderPeerId, testPayload.senderPeerId);
        expect(message.text, testPayload.text);
        expect(message.timestamp, testPayload.timestamp);
        expect(message.status, 'delivered');
        expect(message.isIncoming, true);
        expect(message.createdAt, isNotEmpty);
      });

      test('converts to outgoing ConversationMessage correctly', () {
        final message = testPayload.toConversationMessage(
          contactPeerId: 'target-peer',
          isIncoming: false,
          status: 'sent',
        );

        expect(message.isIncoming, false);
        expect(message.status, 'sent');
        expect(message.contactPeerId, 'target-peer');
      });

      test('uses default status of sent', () {
        final message = testPayload.toConversationMessage(
          contactPeerId: 'peer',
          isIncoming: false,
        );

        expect(message.status, 'sent');
      });
    });

    group('v2 encrypted envelope', () {
      const kem = 'base64kem==';
      const ciphertext = 'base64ct==';
      const nonce = 'base64nonce==';
      const senderPeerId = '12D3KooWSender123';

      test('buildEncryptedEnvelope produces correct structure', () {
        final envelope = MessagePayload.buildEncryptedEnvelope(
          senderPeerId: senderPeerId,
          kem: kem,
          ciphertext: ciphertext,
          nonce: nonce,
        );

        final parsed = jsonDecode(envelope) as Map<String, dynamic>;
        expect(parsed['type'], 'chat_message');
        expect(parsed['version'], '2');
        expect(parsed['senderPeerId'], senderPeerId);
        expect(parsed['encrypted']['kem'], kem);
        expect(parsed['encrypted']['ciphertext'], ciphertext);
        expect(parsed['encrypted']['nonce'], nonce);
      });

      test('parseEncryptedEnvelope returns map for valid v2', () {
        final envelope = MessagePayload.buildEncryptedEnvelope(
          senderPeerId: senderPeerId,
          kem: kem,
          ciphertext: ciphertext,
          nonce: nonce,
        );

        final result = MessagePayload.parseEncryptedEnvelope(envelope);
        expect(result, isNotNull);
        expect(result!['version'], '2');
        expect(result['encrypted']['kem'], kem);
      });

      test('parseEncryptedEnvelope returns null for v1 envelope', () {
        expect(
          MessagePayload.parseEncryptedEnvelope(testPayload.toJson()),
          isNull,
        );
      });

      test('parseEncryptedEnvelope returns null for non-chat_message', () {
        final json = jsonEncode({
          'type': 'contact_request',
          'version': '2',
          'encrypted': {'kem': 'x', 'ciphertext': 'y', 'nonce': 'z'},
        });
        expect(MessagePayload.parseEncryptedEnvelope(json), isNull);
      });

      test('parseEncryptedEnvelope returns null for missing encrypted fields',
          () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '2',
          'encrypted': {'kem': 'x'},
        });
        expect(MessagePayload.parseEncryptedEnvelope(json), isNull);
      });

      test('parseEncryptedEnvelope returns null for missing encrypted block',
          () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '2',
          'senderPeerId': senderPeerId,
        });
        expect(MessagePayload.parseEncryptedEnvelope(json), isNull);
      });

      test('parseEncryptedEnvelope returns null for invalid JSON', () {
        expect(MessagePayload.parseEncryptedEnvelope('not json'), isNull);
      });
    });

    group('fromDecryptedJson', () {
      test('parses inner payload JSON', () {
        final inner = testPayload.toInnerJson();
        final parsed = MessagePayload.fromDecryptedJson(inner);

        expect(parsed, isNotNull);
        expect(parsed!.id, testPayload.id);
        expect(parsed.text, testPayload.text);
        expect(parsed.senderPeerId, testPayload.senderPeerId);
        expect(parsed.senderUsername, testPayload.senderUsername);
        expect(parsed.timestamp, testPayload.timestamp);
      });

      test('returns null for missing fields', () {
        final json = jsonEncode({'id': 'x', 'text': 'y'});
        expect(MessagePayload.fromDecryptedJson(json), isNull);
      });

      test('returns null for invalid JSON', () {
        expect(MessagePayload.fromDecryptedJson('not json'), isNull);
      });
    });

    group('toInnerJson', () {
      test('produces JSON without envelope wrapper', () {
        final inner =
            jsonDecode(testPayload.toInnerJson()) as Map<String, dynamic>;

        expect(inner.containsKey('type'), isFalse);
        expect(inner.containsKey('version'), isFalse);
        expect(inner.containsKey('payload'), isFalse);
        expect(inner['id'], testPayload.id);
        expect(inner['text'], testPayload.text);
        expect(inner['senderPeerId'], testPayload.senderPeerId);
        expect(inner['senderUsername'], testPayload.senderUsername);
        expect(inner['timestamp'], testPayload.timestamp);
      });
    });

    group('quotedMessageId', () {
      const payloadWithQuote = MessagePayload(
        id: 'msg-q1',
        text: 'This is a reply',
        senderPeerId: '12D3KooWSender123',
        senderUsername: 'Alice',
        timestamp: '2026-02-20T10:00:00.000Z',
        quotedMessageId: 'original-msg-001',
      );

      test('v1 round-trip preserves quotedMessageId', () {
        final jsonString = payloadWithQuote.toJson();
        final restored = MessagePayload.fromJson(jsonString);

        expect(restored, isNotNull);
        expect(restored!.quotedMessageId, 'original-msg-001');
      });

      test('v1 toJson includes quotedMessageId in payload', () {
        final jsonString = payloadWithQuote.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload['quotedMessageId'], 'original-msg-001');
      });

      test('v1 toJson omits quotedMessageId when null', () {
        final jsonString = testPayload.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload.containsKey('quotedMessageId'), isFalse);
      });

      test('v1 fromJson reads null when quotedMessageId absent (backward compat)', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'old-msg',
            'text': 'old message',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        final restored = MessagePayload.fromJson(json);
        expect(restored, isNotNull);
        expect(restored!.quotedMessageId, isNull);
      });

      test('v2 inner round-trip preserves quotedMessageId', () {
        final innerJson = payloadWithQuote.toInnerJson();
        final restored = MessagePayload.fromDecryptedJson(innerJson);

        expect(restored, isNotNull);
        expect(restored!.quotedMessageId, 'original-msg-001');
      });

      test('v2 toInnerJson includes quotedMessageId', () {
        final inner = jsonDecode(payloadWithQuote.toInnerJson())
            as Map<String, dynamic>;
        expect(inner['quotedMessageId'], 'original-msg-001');
      });

      test('v2 toInnerJson omits quotedMessageId when null', () {
        final inner = jsonDecode(testPayload.toInnerJson())
            as Map<String, dynamic>;
        expect(inner.containsKey('quotedMessageId'), isFalse);
      });

      test('toConversationMessage passes quotedMessageId', () {
        final msg = payloadWithQuote.toConversationMessage(
          contactPeerId: 'target',
          isIncoming: false,
        );
        expect(msg.quotedMessageId, 'original-msg-001');
      });

      test('toConversationMessage passes null when no quote', () {
        final msg = testPayload.toConversationMessage(
          contactPeerId: 'target',
          isIncoming: false,
        );
        expect(msg.quotedMessageId, isNull);
      });
    });

    group('media', () {
      final mediaArray = [
        {
          'id': 'blob-001',
          'mime': 'image/jpeg',
          'size': 245000,
          'mediaType': 'image',
          'width': 1920,
          'height': 1080,
        },
        {
          'id': 'blob-002',
          'mime': 'audio/mp3',
          'size': 50000,
          'mediaType': 'audio',
          'durationMs': 30000,
        },
      ];

      final payloadWithMedia = MessagePayload(
        id: 'msg-media-001',
        text: 'Check this out',
        senderPeerId: '12D3KooWSender123',
        senderUsername: 'Alice',
        timestamp: '2026-02-20T10:00:00.000Z',
        media: mediaArray,
      );

      test('v1 round-trip preserves media array', () {
        final jsonString = payloadWithMedia.toJson();
        final restored = MessagePayload.fromJson(jsonString);

        expect(restored, isNotNull);
        expect(restored!.media, isNotNull);
        expect(restored.media!.length, 2);
        expect(restored.media![0]['id'], 'blob-001');
        expect(restored.media![0]['mime'], 'image/jpeg');
        expect(restored.media![0]['width'], 1920);
        expect(restored.media![1]['id'], 'blob-002');
        expect(restored.media![1]['durationMs'], 30000);
      });

      test('v1 toJson includes media in payload', () {
        final jsonString = payloadWithMedia.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload['media'], isNotNull);
        expect(payload['media'], isList);
        expect((payload['media'] as List).length, 2);
      });

      test('v1 toJson omits media when null', () {
        final jsonString = testPayload.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload.containsKey('media'), isFalse);
      });

      test('v1 toJson omits media when empty list', () {
        const emptyMedia = MessagePayload(
          id: 'msg-empty-media',
          text: 'No attachments',
          senderPeerId: '12D3KooWSender123',
          senderUsername: 'Alice',
          timestamp: '2026-02-20T10:00:00.000Z',
          media: [],
        );
        final jsonString = emptyMedia.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload.containsKey('media'), isFalse);
      });

      test('v1 fromJson reads null when media absent (backward compat)', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'old-msg',
            'text': 'old message without media',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        final restored = MessagePayload.fromJson(json);
        expect(restored, isNotNull);
        expect(restored!.media, isNull);
      });

      test('v2 inner round-trip preserves media', () {
        final innerJson = payloadWithMedia.toInnerJson();
        final restored = MessagePayload.fromDecryptedJson(innerJson);

        expect(restored, isNotNull);
        expect(restored!.media, isNotNull);
        expect(restored.media!.length, 2);
        expect(restored.media![0]['id'], 'blob-001');
        expect(restored.media![1]['id'], 'blob-002');
      });

      test('v2 toInnerJson includes media', () {
        final inner = jsonDecode(payloadWithMedia.toInnerJson())
            as Map<String, dynamic>;
        expect(inner['media'], isNotNull);
        expect((inner['media'] as List).length, 2);
      });

      test('v2 toInnerJson omits media when null', () {
        final inner = jsonDecode(testPayload.toInnerJson())
            as Map<String, dynamic>;
        expect(inner.containsKey('media'), isFalse);
      });

      test('toConversationMessage does not include media (transient)', () {
        final msg = payloadWithMedia.toConversationMessage(
          contactPeerId: 'target',
          isIncoming: true,
          status: 'delivered',
        );
        // media is a transient field on ConversationMessage, not set by toConversationMessage
        expect(msg.media, isEmpty);
      });
    });
  });
}
