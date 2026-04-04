import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('app-root notification open', () {
    late _AppRootNotificationHarness harness;

    setUp(() {
      harness = _AppRootNotificationHarness();
    });

    test(
      'warm remote push prepares conversation target before route',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-123',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:peer-123',
          'route:peer-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routed.single.peerId, 'peer-123');
        expect(harness.missingCalls, 0);
      },
    );

    test(
      'terminated local notification launch prepares group target before route',
      () async {
        await routeAppRootInitialLocalNotificationOpen(
          consumeInitialPayload: () async => 'group:group-123',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:group:group-123',
          'route:group:group-123',
        ]);
        expect(harness.routed.single.kind, NotificationRouteTargetKind.group);
        expect(harness.routed.single.groupId, 'group-123');
      },
    );

    test(
      'warm local notification tap prepares conversation target before route',
      () async {
        await routeAppRootLocalNotificationTap(
          payload: 'peer-456',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:peer-456',
          'route:peer-456',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routed.single.peerId, 'peer-456');
      },
    );

    test(
      'warm local contact-request tap prepares contact-request target before route',
      () async {
        await routeAppRootLocalNotificationTap(
          payload: 'contact_request:peer-request-123',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      'warm remote contact-request push prepares contact-request target before route',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'contact_request',
            'sender_id': 'peer-request-123',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      'missing warm remote route target skips prepare and calls missing handler',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{'type': 'unknown_type'},
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>['clear', 'missing']);
        expect(harness.routed, isEmpty);
        expect(harness.missingCalls, 1);
      },
    );
  });
}

class _AppRootNotificationHarness {
  final List<String> events = <String>[];
  final List<NotificationRouteTarget> routed = <NotificationRouteTarget>[];
  int missingCalls = 0;

  Future<void> prepare(NotificationRouteTarget routeTarget) async {
    events.add('prepare:${routeTarget.toPayload()}');
  }

  Future<void> clear() async {
    events.add('clear');
  }

  Future<void> route(NotificationRouteTarget routeTarget) async {
    events.add('route:${routeTarget.toPayload()}');
    routed.add(routeTarget);
  }

  Future<void> missing() async {
    missingCalls += 1;
    events.add('missing');
  }
}
