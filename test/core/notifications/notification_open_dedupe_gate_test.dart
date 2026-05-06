import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_open_dedupe_gate.dart';

void main() {
  group('NotificationOpenDedupeGate', () {
    test('routes maps without a stable message id', () {
      final gate = NotificationOpenDedupeGate();

      expect(gate.shouldRoute(const {'type': 'intros'}), isTrue);
      expect(gate.shouldRoute(const {'type': 'intros'}), isTrue);
    });

    test('dedupes native and Firebase opens by route message_id', () {
      final gate = NotificationOpenDedupeGate();

      expect(
        gate.shouldRoute(const {
          'gcm.message_id': 'fcm-transport-id',
          'type': 'new_message',
          'sender_id': 'peer-123',
          'message_id': 'msg-123',
        }),
        isTrue,
      );
      expect(
        gate.shouldRoute(const {
          'type': 'new_message',
          'sender_id': 'peer-123',
          'message_id': 'msg-123',
        }),
        isFalse,
      );
    });

    test('dedupes camelCase message ids', () {
      final gate = NotificationOpenDedupeGate();

      expect(
        gate.shouldRoute(const {
          'type': 'group_message',
          'groupId': 'group-123',
          'messageId': 'msg-456',
        }),
        isTrue,
      );
      expect(
        gate.shouldRoute(const {
          'type': 'group_message',
          'groupId': 'group-123',
          'message_id': 'msg-456',
        }),
        isFalse,
      );
    });

    test('falls back to gcm.message_id when no route message id exists', () {
      final gate = NotificationOpenDedupeGate();

      expect(gate.shouldRoute(const {'gcm.message_id': 'fcm-1'}), isTrue);
      expect(gate.shouldRoute(const {'gcm.message_id': 'fcm-1'}), isFalse);
    });
  });
}
