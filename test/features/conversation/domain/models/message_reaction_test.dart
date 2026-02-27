import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

void main() {
  const testReaction = MessageReaction(
    id: 'reaction-001',
    messageId: 'msg-001',
    emoji: '👍',
    senderPeerId: '12D3KooWSender456',
    timestamp: '2026-02-27T10:00:00.000Z',
    createdAt: '2026-02-27T10:00:01.000Z',
  );

  group('MessageReaction', () {
    group('fromMap / toMap round-trip', () {
      test('round-trips correctly', () {
        final map = testReaction.toMap();
        final restored = MessageReaction.fromMap(map);

        expect(restored.id, testReaction.id);
        expect(restored.messageId, testReaction.messageId);
        expect(restored.emoji, testReaction.emoji);
        expect(restored.senderPeerId, testReaction.senderPeerId);
        expect(restored.timestamp, testReaction.timestamp);
        expect(restored.createdAt, testReaction.createdAt);
      });

      test('toMap produces snake_case keys', () {
        final map = testReaction.toMap();

        expect(map['id'], 'reaction-001');
        expect(map['message_id'], 'msg-001');
        expect(map['emoji'], '👍');
        expect(map['sender_peer_id'], '12D3KooWSender456');
        expect(map['timestamp'], '2026-02-27T10:00:00.000Z');
        expect(map['created_at'], '2026-02-27T10:00:01.000Z');
      });
    });

    group('fromJson / toJson round-trip', () {
      test('round-trips correctly', () {
        final json = testReaction.toJson();
        final restored = MessageReaction.fromJson(json);

        expect(restored.id, testReaction.id);
        expect(restored.messageId, testReaction.messageId);
        expect(restored.emoji, testReaction.emoji);
        expect(restored.senderPeerId, testReaction.senderPeerId);
        expect(restored.timestamp, testReaction.timestamp);
        expect(restored.createdAt, testReaction.createdAt);
      });

      test('toJson produces camelCase keys', () {
        final json = testReaction.toJson();

        expect(json['id'], 'reaction-001');
        expect(json['messageId'], 'msg-001');
        expect(json['emoji'], '👍');
        expect(json['senderPeerId'], '12D3KooWSender456');
        expect(json['timestamp'], '2026-02-27T10:00:00.000Z');
        expect(json['createdAt'], '2026-02-27T10:00:01.000Z');
      });
    });

    group('equality', () {
      test('two reactions with same id are equal', () {
        final other = MessageReaction(
          id: 'reaction-001',
          messageId: 'different-msg',
          emoji: '❤️',
          senderPeerId: 'different-sender',
          timestamp: '2026-01-01T00:00:00.000Z',
          createdAt: '2026-01-01T00:00:01.000Z',
        );

        expect(testReaction, equals(other));
        expect(testReaction.hashCode, equals(other.hashCode));
      });

      test('two reactions with different ids are not equal', () {
        final other = testReaction.copyWith(id: 'reaction-002');
        expect(testReaction, isNot(equals(other)));
      });
    });

    group('copyWith', () {
      test('creates a copy with updated emoji', () {
        final updated = testReaction.copyWith(emoji: '❤️');
        expect(updated.emoji, '❤️');
        expect(updated.id, testReaction.id);
        expect(updated.messageId, testReaction.messageId);
      });

      test('creates a copy with no changes when no args passed', () {
        final copy = testReaction.copyWith();
        expect(copy.id, testReaction.id);
        expect(copy.messageId, testReaction.messageId);
        expect(copy.emoji, testReaction.emoji);
        expect(copy.senderPeerId, testReaction.senderPeerId);
        expect(copy.timestamp, testReaction.timestamp);
        expect(copy.createdAt, testReaction.createdAt);
      });

      test('creates a copy with updated messageId', () {
        final updated = testReaction.copyWith(messageId: 'msg-999');
        expect(updated.messageId, 'msg-999');
        expect(updated.emoji, testReaction.emoji);
      });
    });

    test('multi-codepoint emoji (family with ZWJ)', () {
      final family = testReaction.copyWith(emoji: '👨‍👩‍👧‍👦');
      final map = family.toMap();
      final restored = MessageReaction.fromMap(map);
      expect(restored.emoji, '👨‍👩‍👧‍👦');

      final json = family.toJson();
      final restoredJson = MessageReaction.fromJson(json);
      expect(restoredJson.emoji, '👨‍👩‍👧‍👦');
    });

    test('toString contains id and emoji', () {
      final str = testReaction.toString();
      expect(str, contains('reaction-001'));
      expect(str, contains('👍'));
    });
  });
}
