import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';

void main() {
  const testPayload = ReactionPayload(
    id: 'reaction-001',
    messageId: 'msg-001',
    emoji: '👍',
    action: 'add',
    senderPeerId: '12D3KooWSender456',
    timestamp: '2026-02-27T10:00:00.000Z',
  );

  group('ReactionPayload', () {
    group('fromJson (v1 envelope)', () {
      test('parses valid v1 envelope', () {
        final json = testPayload.toJson();
        final parsed = ReactionPayload.fromJson(json);

        expect(parsed, isNotNull);
        expect(parsed!.id, 'reaction-001');
        expect(parsed.messageId, 'msg-001');
        expect(parsed.emoji, '👍');
        expect(parsed.action, 'add');
        expect(parsed.senderPeerId, '12D3KooWSender456');
        expect(parsed.timestamp, '2026-02-27T10:00:00.000Z');
      });

      test('returns null for wrong type', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'r1',
            'messageId': 'm1',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': 'peer1',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        expect(ReactionPayload.fromJson(json), isNull);
      });

      test('returns null for missing payload', () {
        final json = jsonEncode({
          'type': 'message_reaction',
          'version': '1',
        });
        expect(ReactionPayload.fromJson(json), isNull);
      });

      test('returns null for missing required fields', () {
        final json = jsonEncode({
          'type': 'message_reaction',
          'version': '1',
          'payload': {
            'id': 'r1',
            'messageId': 'm1',
            // missing emoji, action, senderPeerId, timestamp
          },
        });
        expect(ReactionPayload.fromJson(json), isNull);
      });

      test('returns null for invalid JSON', () {
        expect(ReactionPayload.fromJson('not json'), isNull);
      });
    });

    group('toJson (v1 envelope)', () {
      test('produces correct v1 envelope', () {
        final jsonString = testPayload.toJson();
        final envelope = jsonDecode(jsonString) as Map<String, dynamic>;

        expect(envelope['type'], 'message_reaction');
        expect(envelope['version'], '1');

        final payload = envelope['payload'] as Map<String, dynamic>;
        expect(payload['id'], 'reaction-001');
        expect(payload['messageId'], 'msg-001');
        expect(payload['emoji'], '👍');
        expect(payload['action'], 'add');
        expect(payload['senderPeerId'], '12D3KooWSender456');
        expect(payload['timestamp'], '2026-02-27T10:00:00.000Z');
      });

      test('round-trips through fromJson', () {
        final json = testPayload.toJson();
        final restored = ReactionPayload.fromJson(json);
        expect(restored, isNotNull);
        expect(restored!.id, testPayload.id);
        expect(restored.emoji, testPayload.emoji);
        expect(restored.action, testPayload.action);
      });
    });

    group('v2 encrypted envelope', () {
      test('buildEncryptedEnvelope produces correct structure', () {
        final jsonString = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: 'sender-1',
          kem: 'kem-data',
          ciphertext: 'cipher-data',
          nonce: 'nonce-data',
        );
        final envelope = jsonDecode(jsonString) as Map<String, dynamic>;

        expect(envelope['type'], 'message_reaction');
        expect(envelope['version'], '2');
        expect(envelope['senderPeerId'], 'sender-1');

        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        expect(encrypted['kem'], 'kem-data');
        expect(encrypted['ciphertext'], 'cipher-data');
        expect(encrypted['nonce'], 'nonce-data');
      });

      test('parseEncryptedEnvelope parses valid v2', () {
        final jsonString = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: 'sender-1',
          kem: 'kem-data',
          ciphertext: 'cipher-data',
          nonce: 'nonce-data',
        );
        final parsed = ReactionPayload.parseEncryptedEnvelope(jsonString);

        expect(parsed, isNotNull);
        expect(parsed!['type'], 'message_reaction');
        expect(parsed['version'], '2');
        expect(parsed['encrypted'], isNotNull);
      });

      test('parseEncryptedEnvelope returns null for v1', () {
        final json = testPayload.toJson();
        expect(ReactionPayload.parseEncryptedEnvelope(json), isNull);
      });

      test('parseEncryptedEnvelope returns null for wrong type', () {
        final jsonString = jsonEncode({
          'type': 'chat_message',
          'version': '2',
          'encrypted': {
            'kem': 'k',
            'ciphertext': 'c',
            'nonce': 'n',
          },
        });
        expect(ReactionPayload.parseEncryptedEnvelope(jsonString), isNull);
      });

      test('parseEncryptedEnvelope returns null for missing encrypted fields',
          () {
        final jsonString = jsonEncode({
          'type': 'message_reaction',
          'version': '2',
          'encrypted': {
            'kem': 'k',
            // missing ciphertext and nonce
          },
        });
        expect(ReactionPayload.parseEncryptedEnvelope(jsonString), isNull);
      });
    });

    group('toInnerJson / fromDecryptedJson round-trip', () {
      test('round-trips correctly', () {
        final inner = testPayload.toInnerJson();
        final restored = ReactionPayload.fromDecryptedJson(inner);

        expect(restored, isNotNull);
        expect(restored!.id, testPayload.id);
        expect(restored.messageId, testPayload.messageId);
        expect(restored.emoji, testPayload.emoji);
        expect(restored.action, testPayload.action);
        expect(restored.senderPeerId, testPayload.senderPeerId);
        expect(restored.timestamp, testPayload.timestamp);
      });

      test('fromDecryptedJson returns null for missing fields', () {
        final inner = jsonEncode({'id': 'r1', 'messageId': 'm1'});
        expect(ReactionPayload.fromDecryptedJson(inner), isNull);
      });

      test('fromDecryptedJson returns null for invalid JSON', () {
        expect(ReactionPayload.fromDecryptedJson('not json'), isNull);
      });
    });

    group('toMessageReaction', () {
      test('converts to MessageReaction with correct fields', () {
        final reaction = testPayload.toMessageReaction();

        expect(reaction.id, testPayload.id);
        expect(reaction.messageId, testPayload.messageId);
        expect(reaction.emoji, testPayload.emoji);
        expect(reaction.senderPeerId, testPayload.senderPeerId);
        expect(reaction.timestamp, testPayload.timestamp);
        expect(reaction.createdAt, isNotEmpty);
      });
    });

    group('action types', () {
      test('remove action round-trips through v1', () {
        const removePayload = ReactionPayload(
          id: 'reaction-002',
          messageId: 'msg-001',
          emoji: '👍',
          action: 'remove',
          senderPeerId: '12D3KooWSender456',
          timestamp: '2026-02-27T10:00:00.000Z',
        );
        final json = removePayload.toJson();
        final restored = ReactionPayload.fromJson(json);
        expect(restored!.action, 'remove');
      });

      test('remove action round-trips through inner json', () {
        const removePayload = ReactionPayload(
          id: 'reaction-002',
          messageId: 'msg-001',
          emoji: '👍',
          action: 'remove',
          senderPeerId: '12D3KooWSender456',
          timestamp: '2026-02-27T10:00:00.000Z',
        );
        final inner = removePayload.toInnerJson();
        final restored = ReactionPayload.fromDecryptedJson(inner);
        expect(restored!.action, 'remove');
      });
    });
  });
}
