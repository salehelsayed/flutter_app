import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

void main() {
  group('chat and group push open flow', () {
    late _PushOpenHarness harness;

    setUp(() {
      harness = _PushOpenHarness();
    });

    test(
      'background 1:1 push opens conversation only after inbox preparation',
      () async {
        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-123',
          },
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:peer-123',
          'drain:conversation',
          'route:peer-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routedTargets.single.peerId, 'peer-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'terminated 1:1 push opens conversation only after inbox preparation',
      () async {
        await routeInitialRemoteNotificationOpen(
          getInitialMessage: () async => const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-123',
            },
          ),
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:peer-123',
          'drain:conversation',
          'route:peer-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routedTargets.single.peerId, 'peer-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'background group push opens group only after targeted group catch-up',
      () async {
        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-123',
          },
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:group:group-123',
          'drain:group:group-123',
          'route:group:group-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.group,
        );
        expect(harness.routedTargets.single.groupId, 'group-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'terminated group push opens group only after targeted group catch-up',
      () async {
        await routeInitialRemoteNotificationOpen(
          getInitialMessage: () async => const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-123',
            },
          ),
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:group:group-123',
          'drain:group:group-123',
          'route:group:group-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.group,
        );
        expect(harness.routedTargets.single.groupId, 'group-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );
  });
}

class _PushOpenHarness {
  final List<String> events = <String>[];
  final List<NotificationRouteTarget> routedTargets =
      <NotificationRouteTarget>[];
  int missingRouteTargetCalls = 0;

  Future<void> prepare(NotificationRouteTarget routeTarget) async {
    events.add('prepare:${routeTarget.toPayload()}');

    final result = await prepareNotificationOpen(
      routeTarget: routeTarget,
      drainOfflineInbox: () async {
        events.add('drain:conversation');
      },
      drainGroupOfflineInboxForGroup: (groupId) async {
        events.add('drain:group:$groupId');
      },
    );

    expect(result.ok, isTrue, reason: result.error);
  }

  Future<void> handleRouteTarget(NotificationRouteTarget routeTarget) async {
    events.add('route:${routeTarget.toPayload()}');
    routedTargets.add(routeTarget);
  }

  Future<void> handleMissingRouteTarget() async {
    missingRouteTargetCalls += 1;
    events.add('missing');
  }
}
