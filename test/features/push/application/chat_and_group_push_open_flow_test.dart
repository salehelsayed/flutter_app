import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

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
            'messageId': 'msg-123',
          },
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:group:group-123|message:msg-123',
          'drain:group:group-123',
          'route:group:group-123|message:msg-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.group,
        );
        expect(harness.routedTargets.single.groupId, 'group-123');
        expect(harness.routedTargets.single.messageId, 'msg-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'GIRD-006 group image push open prepares anchored group route before navigation',
      () async {
        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-image',
            'payloadType': 'group_message',
            'kind': 'group_offline_replay',
          },
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:group:group-gird006|message:msg-gird006-image',
          'drain:group:group-gird006',
          'route:group:group-gird006|message:msg-gird006-image',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(harness.routedTargets.single.groupId, 'group-gird006');
        expect(harness.routedTargets.single.messageId, 'msg-gird006-image');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'background contact-request push opens only after inbox preparation',
      () async {
        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'contact_request',
            'sender_id': 'peer-request-123',
          },
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:contact_request:peer-request-123',
          'drain:conversation',
          'route:contact_request:peer-request-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routedTargets.single.peerId, 'peer-request-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test('intros push opens only after inbox preparation', () async {
      await routeRemoteNotificationOpen(
        data: const <String, dynamic>{'type': 'intros'},
        onBeforeRouteTarget: harness.prepare,
        onRouteTarget: harness.handleRouteTarget,
        onMissingRouteTarget: harness.handleMissingRouteTarget,
      );

      expect(harness.events, <String>[
        'prepare:intros',
        'drain:conversation',
        'route:intros',
      ]);
      expect(harness.routedTargets, hasLength(1));
      expect(
        harness.routedTargets.single.kind,
        NotificationRouteTargetKind.intros,
      );
      expect(harness.missingRouteTargetCalls, 0);
    });

    test(
      'terminated group push opens group only after targeted group catch-up',
      () async {
        await routeInitialRemoteNotificationOpen(
          getInitialMessage: () async => const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-123',
              'messageId': 'msg-123',
            },
          ),
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:group:group-123|message:msg-123',
          'drain:group:group-123',
          'route:group:group-123|message:msg-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.group,
        );
        expect(harness.routedTargets.single.groupId, 'group-123');
        expect(harness.routedTargets.single.messageId, 'msg-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'terminated contact-request push opens only after inbox preparation',
      () async {
        await routeInitialRemoteNotificationOpen(
          getInitialMessage: () async => const RemoteMessage(
            data: <String, dynamic>{
              'type': 'contact_request',
              'sender_id': 'peer-request-123',
            },
          ),
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        expect(harness.events, <String>[
          'prepare:contact_request:peer-request-123',
          'drain:conversation',
          'route:contact_request:peer-request-123',
        ]);
        expect(harness.routedTargets, hasLength(1));
        expect(
          harness.routedTargets.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routedTargets.single.peerId, 'peer-request-123');
        expect(harness.missingRouteTargetCalls, 0);
      },
    );

    test(
      'group push whose group is unresolvable with no pending invite surfaces '
      'the missing-no-invite feedback branch (not a silent miss)',
      () async {
        // G-NM-2: links the open flow end-to-end — a group push routes to a
        // group target, and when neither the group nor a pending invite can be
        // recovered (even after the catch-up drain) the resolution is
        // missing-no-invite. That is exactly the branch main.dart routes to
        // showGroupMissingNotificationFeedback (route home + SnackBar, locked by
        // group_missing_notification_tap_feedback_test.dart) rather than a
        // silent miss, and distinct from the pending-invite intros-redirect
        // branch (locked by resolve_group_notification_route_target_use_case_test).
        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-unresolvable',
            'messageId': 'msg-unresolvable',
          },
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.handleRouteTarget,
          onMissingRouteTarget: harness.handleMissingRouteTarget,
        );

        // The push routes to a group target (route dispatch always builds it
        // from the push data; the "missing" verdict is decided downstream).
        expect(harness.routedTargets, hasLength(1));
        final routedGroupId = harness.routedTargets.single.groupId;
        expect(routedGroupId, 'group-unresolvable');

        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drained = false;
        final resolution = await resolveGroupNotificationRouteTarget(
          groupId: routedGroupId!,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          drainOfflineInbox: () async {
            drained = true;
          },
        );

        expect(drained, isTrue, reason: 'catch-up drain must be attempted');
        expect(resolution.hasGroup, isFalse);
        expect(resolution.hasPendingInvite, isFalse);
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
