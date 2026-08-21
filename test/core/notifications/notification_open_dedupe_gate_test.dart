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

    test('tryBegin blocks a duplicate while the first open is in flight', () {
      final gate = NotificationOpenDedupeGate();
      const data = {
        'type': 'new_message',
        'sender_id': 'peer-123',
        'message_id': 'msg-123',
      };

      expect(gate.tryBegin(data), isTrue);
      expect(gate.tryBegin(data), isFalse);
    });

    test('failed finish clears in-flight state without marking completed', () {
      final gate = NotificationOpenDedupeGate();
      const data = {
        'type': 'new_message',
        'sender_id': 'peer-123',
        'message_id': 'msg-123',
      };

      expect(gate.tryBegin(data), isTrue);
      gate.finish(data, success: false);

      expect(gate.tryBegin(data), isTrue);
    });

    test(
      'successful finish blocks duplicate until the completed TTL expires',
      () {
        var now = DateTime.utc(2026, 5, 24, 12);
        final gate = NotificationOpenDedupeGate(
          completedTtl: const Duration(seconds: 5),
          now: () => now,
        );
        const data = {
          'type': 'new_message',
          'sender_id': 'peer-123',
          'message_id': 'msg-123',
        };

        expect(gate.tryBegin(data), isTrue);
        gate.finish(data, success: true);
        expect(gate.tryBegin(data), isFalse);

        now = now.add(const Duration(seconds: 6));
        expect(gate.tryBegin(data), isTrue);
      },
    );

    test(
      'group route identity keeps same message id in different groups distinct',
      () {
        final firstKey = NotificationOpenDedupeGate.dedupeKeyFor(const {
          'type': 'group_message',
          'groupId': 'group-a',
          'message_id': 'msg-1',
        });
        final secondKey = NotificationOpenDedupeGate.dedupeKeyFor(const {
          'type': 'group_message',
          'groupId': 'group-b',
          'message_id': 'msg-1',
        });

        expect(firstKey, isNotNull);
        expect(secondKey, isNotNull);
        expect(firstKey, isNot(secondKey));
      },
    );

    test('TC-395-04 distinct group invite transport ids both route', () {
      final gate = NotificationOpenDedupeGate();

      expect(
        gate.shouldRoute(const {
          'type': 'group_invite',
          'groupId': 'group-123',
          'message_id': 'invite-123',
          'gcm.message_id': 'provider-delivery-a',
        }),
        isTrue,
      );
      expect(
        gate.shouldRoute(const {
          'type': 'group_invite',
          'groupId': 'group-123',
          'message_id': 'invite-123',
          'gcm.message_id': 'provider-delivery-b',
        }),
        isTrue,
      );
    });

    test('group invite native and Firebase opens share provider identity', () {
      final gate = NotificationOpenDedupeGate();

      expect(
        gate.shouldRoute(const {
          'type': 'group_invite',
          'groupId': 'group-123',
          'message_id': 'invite-123',
          'gcm.message_id': 'provider-delivery-a',
        }),
        isTrue,
      );
      expect(
        gate.shouldRoute(const {
          'type': 'group_invite',
          'group_id': 'group-123',
          'messageId': 'invite-123',
          'gcm.message_id': ' provider-delivery-a ',
        }),
        isFalse,
      );
    });

    test('group invite without transport identity creates no history key', () {
      const data = {
        'type': 'group_invite',
        'groupId': 'group-123',
        'message_id': 'invite-123',
      };
      final gate = NotificationOpenDedupeGate();

      expect(NotificationOpenDedupeGate.dedupeKeyFor(data), isNull);
      expect(gate.shouldRoute(data), isTrue);
      expect(gate.shouldRoute(data), isTrue);
    });

    test('payload-only group invite also creates no invite-history key', () {
      const data = {'payload': 'group_invite:group-123|message:invite-123'};
      final gate = NotificationOpenDedupeGate();

      expect(NotificationOpenDedupeGate.dedupeKeyFor(data), isNull);
      expect(gate.shouldRoute(data), isTrue);
      expect(gate.shouldRoute(data), isTrue);

      const providerData = {...data, 'gcm.message_id': 'provider-payload-only'};
      expect(gate.shouldRoute(providerData), isTrue);
      expect(gate.shouldRoute(providerData), isFalse);
    });

    test('legacy invite route also dedupes only by provider identity', () {
      const data = {
        'type': 'group_invite',
        'message_id': 'invite-legacy',
        'gcm.message_id': 'provider-legacy',
      };

      expect(
        NotificationOpenDedupeGate.dedupeKeyFor(data),
        'fcm:provider-legacy',
      );
    });
  });
}
