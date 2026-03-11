import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_payload.dart';

void main() {
  group('GroupMessagePayload', () {
    test('fromJson/toJson round-trip preserves all fields', () {
      final json = {
        'text': 'Hello group!',
        'timestamp': '2026-01-15T12:00:00.000Z',
        'username': 'Alice',
        'quotedMessageId': 'msg-prev',
        'extra': {'replyTo': 'msg-prev'},
      };

      final payload = GroupMessagePayload.fromJson(json);
      final result = payload.toJson();

      expect(result['text'], 'Hello group!');
      expect(result['timestamp'], '2026-01-15T12:00:00.000Z');
      expect(result['username'], 'Alice');
      expect(result['quotedMessageId'], 'msg-prev');
      expect(result['extra'], {'replyTo': 'msg-prev'});
    });

    test('toJson omits null optional fields', () {
      final payload = GroupMessagePayload(
        text: 'Hello',
        timestamp: '2026-01-15T12:00:00.000Z',
      );

      final result = payload.toJson();

      expect(result.containsKey('text'), true);
      expect(result.containsKey('timestamp'), true);
      expect(result.containsKey('username'), false);
      expect(result.containsKey('quotedMessageId'), false);
      expect(result.containsKey('extra'), false);
    });
  });
}
