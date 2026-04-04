import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

import '../shared/fakes/fake_notification_service.dart';
import '../shared/fakes/fake_push_token_store.dart';

void main() {
  group('Notification deep-link integration', () {
    test(
      '1. chat push open follows prepare -> drain -> route sequencing',
      () async {
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-alice-123',
          },
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            final result = await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async => events.add('drain:inbox'),
              drainGroupOfflineInboxForGroup: (_) async {},
            );
            expect(result.ok, isTrue);
            events.add('open:${target.toPayload()}');
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
          onMissingRouteTarget: () async => events.add('missing'),
        );

        expect(events, [
          'prepare:peer-alice-123',
          'drain:inbox',
          'open:peer-alice-123',
          'route:peer-alice-123',
        ]);
        expect(routed.single.kind, NotificationRouteTargetKind.conversation);
        expect(routed.single.peerId, 'peer-alice-123');
      },
    );

    test(
      '2. group push open follows prepare -> group drain -> route sequencing',
      () async {
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-xyz-789',
          },
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            final result = await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async {},
              drainGroupOfflineInboxForGroup: (groupId) async {
                events.add('drain:group:$groupId');
              },
            );
            expect(result.ok, isTrue);
            events.add('open:${target.toPayload()}');
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
          onMissingRouteTarget: () async => events.add('missing'),
        );

        expect(events, [
          'prepare:group:group-xyz-789',
          'drain:group:group-xyz-789',
          'open:group:group-xyz-789',
          'route:group:group-xyz-789',
        ]);
        expect(routed.single.kind, NotificationRouteTargetKind.group);
        expect(routed.single.groupId, 'group-xyz-789');
      },
    );

    test(
      '3. missing route target short-circuits before prepare or route',
      () async {
        final events = <String>[];

        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{'type': 'unknown_type'},
          onBeforeRouteTarget: (_) async => events.add('prepare'),
          onRouteTarget: (_) async => events.add('route'),
          onMissingRouteTarget: () async => events.add('missing'),
        );

        expect(events, ['missing']);
      },
    );

    test(
      '4. group notification payload round-trips through local tap open',
      () async {
        final notificationService = FakeNotificationService();
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await notificationService.showNotification(
          title: 'Team Chat',
          body: 'Alice: Hello group!',
          payload: const NotificationRouteTarget.group(
            'group-xyz-789',
          ).toPayload(),
        );
        notificationService.initialPayload =
            notificationService.shownGeneric.single.payload;

        await routeInitialLocalNotificationOpen(
          consumeInitialPayload: notificationService.consumeInitialPayload,
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            final result = await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async {},
              drainGroupOfflineInboxForGroup: (groupId) async {
                events.add('drain:group:$groupId');
              },
            );
            expect(result.ok, isTrue);
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
        );

        expect(
          notificationService.shownGeneric.single.payload,
          'group:group-xyz-789',
        );
        expect(events, [
          'prepare:group:group-xyz-789',
          'drain:group:group-xyz-789',
          'route:group:group-xyz-789',
        ]);
        expect(routed.single.kind, NotificationRouteTargetKind.group);
        expect(routed.single.groupId, 'group-xyz-789');
      },
    );

    test(
      '5. contact-request push open follows prepare -> drain -> route sequencing',
      () async {
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'contact_request',
            'sender_id': 'peer-request-123',
          },
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            final result = await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async => events.add('drain:inbox'),
              drainGroupOfflineInboxForGroup: (_) async {},
            );
            expect(result.ok, isTrue);
            events.add('open:${target.toPayload()}');
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
          onMissingRouteTarget: () async => events.add('missing'),
        );

        expect(events, [
          'prepare:contact_request:peer-request-123',
          'drain:inbox',
          'open:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(routed.single.kind, NotificationRouteTargetKind.contactRequest);
        expect(routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      '6. contact-request payload round-trips through local tap open',
      () async {
        final notificationService = FakeNotificationService();
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await notificationService.showNotification(
          title: 'New Contact Request',
          body: 'Alice wants to connect',
          payload: const NotificationRouteTarget.contactRequest(
            'peer-request-123',
          ).toPayload(),
        );
        notificationService.initialPayload =
            notificationService.shownGeneric.single.payload;

        await routeInitialLocalNotificationOpen(
          consumeInitialPayload: notificationService.consumeInitialPayload,
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            final result = await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async => events.add('drain:inbox'),
              drainGroupOfflineInboxForGroup: (_) async {},
            );
            expect(result.ok, isTrue);
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
        );

        expect(
          notificationService.shownGeneric.single.payload,
          'contact_request:peer-request-123',
        );
        expect(events, [
          'prepare:contact_request:peer-request-123',
          'drain:inbox',
          'route:contact_request:peer-request-123',
        ]);
        expect(routed.single.kind, NotificationRouteTargetKind.contactRequest);
        expect(routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      '7. push token survives logical app restart (persistent token store)',
      () async {
        final tokenStore = FakePushTokenStore();

        await tokenStore.writeToken('fcm-token-abc', 'apns');
        tokenStore.simulateRestart();

        final stored = await tokenStore.readToken();
        expect(stored, isNotNull);
        expect(stored!.token, 'fcm-token-abc');
        expect(stored.platform, 'apns');
        expect(tokenStore.writeCallCount, 1);
        expect(tokenStore.readCallCount, 1);
      },
    );
  });
}
