import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

void main() {
  const testMessage = ConversationMessage(
    id: 'msg-001',
    contactPeerId: '12D3KooWContact123',
    senderPeerId: '12D3KooWSender456',
    text: 'Hello, world!',
    timestamp: '2026-02-09T15:30:00.000Z',
    status: 'sent',
    isIncoming: false,
    createdAt: '2026-02-09T15:30:01.000Z',
  );

  group('ConversationMessage', () {
    group('fromMap / toMap round-trip', () {
      test('round-trips correctly', () {
        final map = testMessage.toMap();
        final restored = ConversationMessage.fromMap(map);

        expect(restored.id, testMessage.id);
        expect(restored.contactPeerId, testMessage.contactPeerId);
        expect(restored.senderPeerId, testMessage.senderPeerId);
        expect(restored.text, testMessage.text);
        expect(restored.timestamp, testMessage.timestamp);
        expect(restored.status, testMessage.status);
        expect(restored.isIncoming, testMessage.isIncoming);
        expect(restored.createdAt, testMessage.createdAt);
      });

      test('toMap produces correct keys and values', () {
        final map = testMessage.toMap();

        expect(map['id'], 'msg-001');
        expect(map['contact_peer_id'], '12D3KooWContact123');
        expect(map['sender_peer_id'], '12D3KooWSender456');
        expect(map['text'], 'Hello, world!');
        expect(map['timestamp'], '2026-02-09T15:30:00.000Z');
        expect(map['status'], 'sent');
        expect(map['is_incoming'], 0);
        expect(map['created_at'], '2026-02-09T15:30:01.000Z');
      });

      test('isIncoming true maps to is_incoming = 1', () {
        final incoming = testMessage.copyWith(isIncoming: true);
        final map = incoming.toMap();
        expect(map['is_incoming'], 1);
      });

      test('fromMap handles null status as sent', () {
        final map = testMessage.toMap();
        map.remove('status');
        final restored = ConversationMessage.fromMap(map);
        expect(restored.status, 'sent');
      });

      test('fromMap handles null is_incoming as false', () {
        final map = testMessage.toMap();
        map.remove('is_incoming');
        final restored = ConversationMessage.fromMap(map);
        expect(restored.isIncoming, false);
      });
    });

    group('equality', () {
      test('two messages with same id are equal', () {
        final other = ConversationMessage(
          id: 'msg-001',
          contactPeerId: 'different-peer',
          senderPeerId: 'different-sender',
          text: 'Different text',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-01-01T00:00:01.000Z',
        );

        expect(testMessage, equals(other));
        expect(testMessage.hashCode, equals(other.hashCode));
      });

      test('two messages with different ids are not equal', () {
        final other = testMessage.copyWith(id: 'msg-002');
        expect(testMessage, isNot(equals(other)));
      });
    });

    group('copyWith', () {
      test('creates a copy with updated status', () {
        final updated = testMessage.copyWith(status: 'delivered');
        expect(updated.status, 'delivered');
        expect(updated.id, testMessage.id);
        expect(updated.text, testMessage.text);
      });

      test('creates a copy with updated text', () {
        final updated = testMessage.copyWith(text: 'New text');
        expect(updated.text, 'New text');
        expect(updated.status, testMessage.status);
      });

      test('creates a copy with no changes when no args passed', () {
        final copy = testMessage.copyWith();
        expect(copy.id, testMessage.id);
        expect(copy.contactPeerId, testMessage.contactPeerId);
        expect(copy.senderPeerId, testMessage.senderPeerId);
        expect(copy.text, testMessage.text);
        expect(copy.timestamp, testMessage.timestamp);
        expect(copy.status, testMessage.status);
        expect(copy.isIncoming, testMessage.isIncoming);
        expect(copy.createdAt, testMessage.createdAt);
      });
    });

    test('toString contains id and isIncoming', () {
      final str = testMessage.toString();
      expect(str, contains('msg-001'));
      expect(str, contains('isIncoming: false'));
    });
  });
}
