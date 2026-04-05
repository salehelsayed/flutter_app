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

    test(
      'fromRemoteMessageData preserves group message anchors when present',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'group_message',
          'groupId': 'group-123',
          'messageId': 'msg-123',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.group);
        expect(routeTarget.groupId, 'group-123');
        expect(routeTarget.messageId, 'msg-123');
      },
    );

    test(
      'fromRemoteMessageData maps contact_request to contact-request route',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'contact_request',
          'sender_id': 'peer-contact-123',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.contactRequest);
        expect(routeTarget.peerId, 'peer-contact-123');
      },
    );

    test('fromPayload maps intros to intros route', () {
      final routeTarget = NotificationRouteTarget.fromPayload('intros');

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.intros);
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

    test(
      'anchored group payload round-trips through toPayload and fromPayload',
      () {
        const routeTarget = NotificationRouteTarget.group(
          'group-xyz',
          messageId: 'msg-xyz',
        );

        final payload = routeTarget.toPayload();
        final parsed = NotificationRouteTarget.fromPayload(payload);

        expect(payload, 'group:group-xyz|message:msg-xyz');
        expect(parsed, isNotNull);
        expect(parsed!.kind, NotificationRouteTargetKind.group);
        expect(parsed.groupId, 'group-xyz');
        expect(parsed.messageId, 'msg-xyz');
      },
    );

    test(
      'contact-request payload round-trips through toPayload and fromPayload',
      () {
        const routeTarget = NotificationRouteTarget.contactRequest(
          'peer-contact-123',
        );

        final payload = routeTarget.toPayload();
        final parsed = NotificationRouteTarget.fromPayload(payload);

        expect(payload, 'contact_request:peer-contact-123');
        expect(parsed, isNotNull);
        expect(parsed!.kind, NotificationRouteTargetKind.contactRequest);
        expect(parsed.peerId, 'peer-contact-123');
      },
    );

    test('unknown whitespace payload does not coerce to an invalid route', () {
      final parsed = NotificationRouteTarget.fromPayload('   ');

      expect(parsed, isNull);
    });
  });
}
