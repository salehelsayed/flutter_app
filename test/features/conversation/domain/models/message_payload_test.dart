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
  });
}
