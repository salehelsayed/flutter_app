import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

void main() {
  group('prepareNotificationOpen', () {
    test('conversation target drains 1:1 inbox before navigation', () async {
      var drainOfflineInboxCalls = 0;
      final drainedGroups = <String>[];

      final result = await prepareNotificationOpen(
        routeTarget: const NotificationRouteTarget.conversation('peer-123'),
        drainOfflineInbox: () async {
          drainOfflineInboxCalls += 1;
        },
        drainGroupOfflineInboxForGroup: (groupId) async {
          drainedGroups.add(groupId);
        },
      );

      expect(result.ok, isTrue);
      expect(drainOfflineInboxCalls, 1);
      expect(drainedGroups, isEmpty);
    });

    test(
      'group target drains the targeted group inbox before navigation',
      () async {
        var drainOfflineInboxCalls = 0;
        final drainedGroups = <String>[];

        final result = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.group('group-123'),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );

        expect(result.ok, isTrue);
        expect(drainOfflineInboxCalls, 0);
        expect(drainedGroups, ['group-123']);
      },
    );

    test(
      'contact requests and intros drain 1:1 inbox while posts do not',
      () async {
        var drainOfflineInboxCalls = 0;
        final drainedGroups = <String>[];

        final contactRequestResult = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.contactRequest('peer-123'),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
        final introsResult = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.intros(),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
        final postResult = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.post('post-123'),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );

        expect(contactRequestResult.ok, isTrue);
        expect(introsResult.ok, isTrue);
        expect(postResult.ok, isTrue);
        expect(drainOfflineInboxCalls, 2);
        expect(drainedGroups, isEmpty);
      },
    );

    test(
      'preparation errors are surfaced as explicit failure results',
      () async {
        final result = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.group('group-123'),
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (_) async {
            throw StateError('group catch-up failed');
          },
        );

        expect(result.ok, isFalse);
        expect(result.error, contains('group catch-up failed'));
      },
    );
  });
}
