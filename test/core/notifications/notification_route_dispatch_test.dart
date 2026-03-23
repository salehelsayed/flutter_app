import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('notification route dispatch', () {
    test(
      'remote conversation push invokes preparation before route handoff',
      () async {
        final callOrder = <String>[];
        NotificationRouteTarget? routedTarget;

        await routeRemoteNotificationOpen(
          data: const {'type': 'new_message', 'from': 'peer-123'},
          onBeforeRouteTarget: (routeTarget) async {
            callOrder.add('prepare');
            expect(routeTarget.kind, NotificationRouteTargetKind.conversation);
          },
          onRouteTarget: (routeTarget) async {
            callOrder.add('route');
            routedTarget = routeTarget;
          },
          onMissingRouteTarget: () async {
            fail('expected route target');
          },
        );

        expect(callOrder, ['prepare', 'route']);
        expect(routedTarget, isNotNull);
        expect(routedTarget!.peerId, 'peer-123');
      },
    );

    test(
      'remote group push invokes preparation before route handoff',
      () async {
        final callOrder = <String>[];
        NotificationRouteTarget? routedTarget;

        await routeRemoteNotificationOpen(
          data: const {'type': 'group_message', 'groupId': 'group-123'},
          onBeforeRouteTarget: (routeTarget) async {
            callOrder.add('prepare');
            expect(routeTarget.kind, NotificationRouteTargetKind.group);
          },
          onRouteTarget: (routeTarget) async {
            callOrder.add('route');
            routedTarget = routeTarget;
          },
          onMissingRouteTarget: () async {
            fail('expected route target');
          },
        );

        expect(callOrder, ['prepare', 'route']);
        expect(routedTarget, isNotNull);
        expect(routedTarget!.groupId, 'group-123');
      },
    );

    test(
      'missing remote route target falls back to missing-route handler',
      () async {
        var missingCalled = false;
        var routeCalled = false;

        await routeRemoteNotificationOpen(
          data: const {'type': 'group_message'},
          onBeforeRouteTarget: (_) async {
            fail('should not prepare without a route target');
          },
          onRouteTarget: (_) async {
            routeCalled = true;
          },
          onMissingRouteTarget: () async {
            missingCalled = true;
          },
        );

        expect(missingCalled, isTrue);
        expect(routeCalled, isFalse);
      },
    );

    test('local-notification payload routing remains unchanged', () async {
      NotificationRouteTarget? routedTarget;

      await routeNotificationPayload(
        payload: 'group:group-local',
        onRouteTarget: (routeTarget) async {
          routedTarget = routeTarget;
        },
      );

      expect(routedTarget, isNotNull);
      expect(routedTarget!.kind, NotificationRouteTargetKind.group);
      expect(routedTarget!.groupId, 'group-local');
    });
  });
}
