import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('NotificationRouteTarget', () {
    test('fromRemoteMessageData maps new_message to conversation route', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': 'peer-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.conversation);
      expect(routeTarget.peerId, 'peer-123');
    });

    test('fromRemoteMessageData maps group_message to group route', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'group_message',
        'groupId': 'group-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.group);
      expect(routeTarget.groupId, 'group-123');
    });

    test('group payload round-trips through toPayload and fromPayload', () {
      const routeTarget = NotificationRouteTarget.group('group-xyz');

      final payload = routeTarget.toPayload();
      final parsed = NotificationRouteTarget.fromPayload(payload);

      expect(payload, 'group:group-xyz');
      expect(parsed, isNotNull);
      expect(parsed!.kind, NotificationRouteTargetKind.group);
      expect(parsed.groupId, 'group-xyz');
    });

    test('unknown whitespace payload does not coerce to an invalid route', () {
      final parsed = NotificationRouteTarget.fromPayload('   ');

      expect(parsed, isNull);
    });
  });
}
