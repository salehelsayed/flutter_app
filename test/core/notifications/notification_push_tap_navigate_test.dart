import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

class _RouteHarness {
  final List<NotificationRouteTarget> routed = [];
  int missingCalls = 0;

  Future<void> route(NotificationRouteTarget target) async {
    routed.add(target);
  }

  Future<void> missing() async {
    missingCalls++;
  }
}

void main() {
  group('push tap → navigate integration', () {
    late _RouteHarness harness;

    setUp(() {
      harness = _RouteHarness();
    });

    test('1:1 push with sender_id navigates to correct conversation', () async {
      await routeRemoteNotificationOpen(
        data: const {
          'type': 'new_message',
          'sender_id': '12D3KooWAlicePeer',
        },
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed.single.peerId, '12D3KooWAlicePeer');
      expect(harness.missingCalls, 0);
    });

    test('1:1 push with from (pre-fix relay) still navigates', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message', 'from': '12D3KooWLegacyPeer'},
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed.single.peerId, '12D3KooWLegacyPeer');
    });

    test('1:1 push with no peer field calls onMissingRouteTarget', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message'},
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed, isEmpty);
      expect(harness.missingCalls, 1);
    });

    test('group push navigates to group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_message', 'groupId': 'group-team'},
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed.single.groupId, 'group-team');
    });
  });
}
