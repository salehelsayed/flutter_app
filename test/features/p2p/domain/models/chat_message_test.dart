import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    const baseMsg = ChatMessage(
      from: 'peer-a',
      to: 'peer-b',
      content: 'hello',
      timestamp: '2026-01-01T00:00:00.000Z',
      isIncoming: true,
    );

    group('fromJson', () {
      test('parses timestamp as int (Unix ms)', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': 1706745600000, // 2024-01-31T16:00:00.000Z
          'isIncoming': true,
        });
        expect(msg.timestamp, contains('2024'));
        // Verify it is a valid ISO8601 string
        expect(() => DateTime.parse(msg.timestamp), returnsNormally);
      });

      test('parses timestamp as string', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'isIncoming': false,
        });
        expect(msg.timestamp, '2026-01-01T00:00:00.000Z');
      });

      test('defaults timestamp to now when missing', () {
        final before = DateTime.now().toUtc();
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
        });
        final parsed = DateTime.parse(msg.timestamp);
        expect(
          parsed.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
      });

      test('defaults to field to empty string when null', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': null,
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
        });
        expect(msg.to, '');
      });

      test('defaults isIncoming to true when missing', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
        });
        expect(msg.isIncoming, isTrue);
      });

      test('sets isIncoming to false when explicitly false', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'isIncoming': false,
        });
        expect(msg.isIncoming, isFalse);
      });
    });

    group('toJson', () {
      test('round-trips through fromJson and toJson', () {
        final json = baseMsg.toJson();
        final restored = ChatMessage.fromJson(json);
        expect(restored.from, baseMsg.from);
        expect(restored.to, baseMsg.to);
        expect(restored.content, baseMsg.content);
        expect(restored.timestamp, baseMsg.timestamp);
        expect(restored.isIncoming, baseMsg.isIncoming);
      });

      test('includes all fields in output map', () {
        final json = baseMsg.toJson();
        expect(json, {
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'isIncoming': true,
        });
      });
    });

    group('equality', () {
      test(
        'equal when from/to/content/timestamp match regardless of isIncoming',
        () {
          final incoming = baseMsg;
          final outgoing = baseMsg.copyWith(isIncoming: false);
          expect(incoming, equals(outgoing));
        },
      );

      test('not equal when content differs', () {
        final other = baseMsg.copyWith(content: 'goodbye');
        expect(baseMsg, isNot(equals(other)));
      });

      test('not equal when from differs', () {
        final other = baseMsg.copyWith(from: 'peer-z');
        expect(baseMsg, isNot(equals(other)));
      });

      test('hashCode is same for objects differing only in isIncoming', () {
        final incoming = baseMsg;
        final outgoing = baseMsg.copyWith(isIncoming: false);
        expect(incoming.hashCode, equals(outgoing.hashCode));
      });
    });

    group('copyWith', () {
      test('updates single field and preserves others', () {
        final updated = baseMsg.copyWith(content: 'world');
        expect(updated.content, 'world');
        expect(updated.from, baseMsg.from);
        expect(updated.to, baseMsg.to);
        expect(updated.timestamp, baseMsg.timestamp);
        expect(updated.isIncoming, baseMsg.isIncoming);
      });
    });

    group('toString', () {
      test('contains from, to, and isIncoming', () {
        final str = baseMsg.toString();
        expect(str, contains('peer-a'));
        expect(str, contains('peer-b'));
        expect(str, contains('true'));
      });
    });

    group('transport contract', () {
      test('fromJson parses transport key in JSON', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'isIncoming': true,
          'transport': 'wifi',
        });
        expect(msg.transport, 'wifi');
      });

      test('toJson excludes transport', () {
        final tagged = baseMsg.copyWith(transport: 'relay');
        final json = tagged.toJson();
        expect(json.containsKey('transport'), isFalse);
      });

      test('copyWith sets transport', () {
        final tagged = baseMsg.copyWith(transport: 'relay');
        expect(tagged.transport, 'relay');
      });

      test('copyWith(transport) preserves existing when null passed', () {
        final tagged = baseMsg.copyWith(transport: 'wifi');
        final copy = tagged.copyWith(content: 'updated');
        expect(copy.transport, 'wifi');
      });

      test('equality ignores transport', () {
        final wifi = baseMsg.copyWith(transport: 'wifi');
        final relay = baseMsg.copyWith(transport: 'relay');
        expect(wifi, equals(relay));
        expect(wifi.hashCode, equals(relay.hashCode));
      });
    });

    group('confirm nonce contract', () {
      test('fromJson parses confirmNonce key in JSON', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'isIncoming': true,
          'confirmNonce': 'nonce-123',
        });
        expect(msg.confirmNonce, 'nonce-123');
      });

      test('toJson includes confirmNonce when present', () {
        final tagged = baseMsg.copyWith(confirmNonce: 'nonce-123');
        final json = tagged.toJson();
        expect(json['confirmNonce'], 'nonce-123');
      });

      test('copyWith sets confirmNonce', () {
        final tagged = baseMsg.copyWith(confirmNonce: 'nonce-123');
        expect(tagged.confirmNonce, 'nonce-123');
      });

      test('equality ignores confirmNonce', () {
        final a = baseMsg.copyWith(confirmNonce: 'nonce-a');
        final b = baseMsg.copyWith(confirmNonce: 'nonce-b');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    // 147: predecryptedText is a TRANSIENT in-memory carrier for the inbox-drain
    // decrypt-prefetch plaintext. Because it carries DECRYPTED message content it
    // must never leak to the wire, the DB, equality/dedup, or logs — pin that
    // contract here so a future refactor can't silently serialize plaintext.
    group('predecryptedText privacy contract', () {
      const secret = 'SECRET-DECRYPTED-PLAINTEXT';

      test('fromJson never parses predecryptedText (not a wire field)', () {
        final msg = ChatMessage.fromJson({
          'from': 'peer-a',
          'to': 'peer-b',
          'content': 'hello',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'isIncoming': true,
          'predecryptedText': secret,
        });
        expect(msg.predecryptedText, isNull);
      });

      test('toJson excludes predecryptedText (never serialized to wire/DB)', () {
        final tagged = baseMsg.copyWith(predecryptedText: secret);
        final json = tagged.toJson();
        expect(json.containsKey('predecryptedText'), isFalse);
        expect(json.values.contains(secret), isFalse);
      });

      test('copyWith sets predecryptedText', () {
        final tagged = baseMsg.copyWith(predecryptedText: secret);
        expect(tagged.predecryptedText, secret);
      });

      test('copyWith preserves existing predecryptedText when null passed', () {
        final tagged = baseMsg.copyWith(predecryptedText: secret);
        final copy = tagged.copyWith(content: 'updated');
        expect(copy.predecryptedText, secret);
      });

      test('equality and hashCode ignore predecryptedText', () {
        final a = baseMsg.copyWith(predecryptedText: 'pt-a');
        final b = baseMsg.copyWith(predecryptedText: 'pt-b');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('toString does not leak the predecryptedText plaintext', () {
        final tagged = baseMsg.copyWith(predecryptedText: secret);
        expect(tagged.toString().contains(secret), isFalse);
      });
    });
  });
}
