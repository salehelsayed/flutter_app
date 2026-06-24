import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

void main() {
  ConversationMessage build({required String timestamp}) => ConversationMessage(
    id: 'm1',
    contactPeerId: 'c1',
    senderPeerId: 's1',
    text: 'hi',
    timestamp: timestamp,
    status: 'sent',
    isIncoming: true,
    createdAt: '2026-06-24T10:00:00.000Z',
  );

  group('TC-159-01 ConversationMessage.parsedTimestamp', () {
    test(
      'parses a valid ISO-8601 timestamp; stable + non-throwing across reads',
      () {
        final msg = build(timestamp: '2026-06-24T10:00:00.000Z');
        final expected = DateTime.parse('2026-06-24T10:00:00.000Z');
        expect(msg.parsedTimestamp, expected);
        // A second read returns the same value (no exception, no drift).
        expect(msg.parsedTimestamp, expected);
      },
    );

    test('fails safe to null on a malformed timestamp', () {
      final msg = build(timestamp: 'not-a-date');
      expect(msg.parsedTimestamp, isNull);
    });

    test('is transient: NOT serialized into the DB row map', () {
      final msg = build(timestamp: '2026-06-24T10:00:00.000Z');
      final map = msg.toMap();
      expect(map.containsKey('parsedTimestamp'), isFalse);
      expect(map.containsKey('parsed_timestamp'), isFalse);
      // toMap still carries the raw String timestamp unchanged.
      expect(map['timestamp'], '2026-06-24T10:00:00.000Z');
    });

    test('round-trips through fromMap/toMap without a parsed-timestamp column', () {
      final msg = build(timestamp: '2026-06-24T10:00:00.000Z');
      final restored = ConversationMessage.fromMap(msg.toMap());
      expect(restored.timestamp, msg.timestamp);
      expect(restored.parsedTimestamp, msg.parsedTimestamp);
    });

    test('is NOT part of identity — == / hashCode stay id-only', () {
      final a = build(timestamp: '2026-06-24T10:00:00.000Z');
      final b = build(timestamp: '2020-01-01T00:00:00.000Z');
      // Same id => equal, despite different timestamps (and parsedTimestamps).
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('the const constructor is preserved (compiles in a const context)', () {
      const msg = ConversationMessage(
        id: 'm1',
        contactPeerId: 'c1',
        senderPeerId: 's1',
        text: 'hi',
        timestamp: '2026-06-24T10:00:00.000Z',
        status: 'sent',
        isIncoming: true,
        createdAt: '2026-06-24T10:00:00.000Z',
      );
      // The derived getter works on a const instance (no non-final cache).
      expect(msg.parsedTimestamp, DateTime.parse('2026-06-24T10:00:00.000Z'));
    });
  });
}
